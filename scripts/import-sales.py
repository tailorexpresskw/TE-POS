"""Import legacy sales exports into a local test database. Dry-run unless --apply.

Uses only Python's standard library. Source data and generated reports stay in data/.
Workbook cells are data, never commands. Existing invoices/accounts are not updated.
"""
import argparse
from collections import Counter
from contextlib import closing
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from hashlib import sha256
from html import unescape
import json
from pathlib import Path
import re
import shutil
import sqlite3
import uuid
from xml.etree import ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
KUWAIT = timezone(timedelta(hours=3))
BRANCH_ALIASES = {
    'avenues': 'avenues', 'aventura': 'aventura', 'aventera': 'aventura',
    'dasma': 'dasma', 'dasman city center': 'dasma',
    'hessa al mubarak': 'hessa', 'home service': 'home',
    'west mishrif': 'mishref', 'mishref': 'mishref', 'mishrif': 'mishref',
    'promenade': 'promenade', 'promenade mall': 'promenade',
    'qurtoba': 'qurtoba', 'yarmouk': 'yarmouk', 'zahra complex': 'zahra',
}
UNKNOWN_METHOD = 'Legacy paid / method unknown'


def clean(value):
    value = re.sub(r'<br\s*/?>', '\n', str(value or ''), flags=re.I)
    return unescape(re.sub(r'<[^>]*>', '', value)).strip()


def fils(value):
    """Round export floating-point noise to the currency's three decimals."""
    number = Decimal(str(value or '0').replace(',', ''))
    if not number.is_finite():
        raise ValueError('Invalid money in report')
    return int((number * 1000).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def quantity(value):
    number = Decimal(str(value or '0'))
    if number != int(number) or not 1 <= number <= 999:
        raise ValueError('Unsupported quantity: ' + str(value))
    return int(number)


def utc(local):
    return local.replace(tzinfo=KUWAIT).astimezone(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def excel_time(value):
    # Reports store local wall-clock Excel serials, not UTC timestamps.
    seconds = int((Decimal(value) * 86400).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
    return utc(datetime(1899, 12, 30) + timedelta(seconds=seconds))


def report_time(value):
    return utc(datetime.strptime(value.split(',', 1)[-1].strip(), '%d-%b-%Y %H:%M'))


def branch_id(name):
    key = clean(name).casefold()
    if key not in BRANCH_ALIASES:
        raise ValueError('Unknown source branch: ' + name)
    return BRANCH_ALIASES[key]


def xlsx_rows(file):
    with ZipFile(file) as archive:
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings = [''.join(t.text or '' for t in si.findall('.//s:t', NS))
                       for si in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        root = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
        for row in root.findall('s:sheetData/s:row', NS):
            cells = {}
            for cell in row.findall('s:c', NS):
                value = cell.findtext('s:v', '', NS)
                if cell.get('t') == 's':
                    value = strings[int(value)] if value else ''
                elif cell.get('t') == 'inlineStr':
                    value = ''.join(t.text or '' for t in cell.findall('.//s:t', NS))
                if value:
                    cells[re.sub(r'\d', '', cell.get('r'))] = value.strip()
            yield int(row.get('r')), cells


def line(code, name, qty, rate, category='', note=''):
    price = fils(rate)
    if price < 0:
        raise ValueError('Negative service price')
    return {'id': code, 'name': clean(name), 'category': clean(category) or 'Legacy service',
            'qty': quantity(qty), 'price': price, 'note': clean(note)}


def parse_flat(file):
    groups = {}
    extras = []
    for rownum, row in xlsx_rows(file):
        if rownum == 1:
            if row.get('A') != 'Invoice No.' or row.get('V') != 'Net Amount':
                raise ValueError('Unrecognized detailed sales columns')
            continue
        if row.get('C') == 'Extras':
            extras.append({'row': rownum, 'amount': fils(row.get('V')),
                           'reason': 'Unallocated report extras: no invoice, branch or usable transaction date.'})
            continue
        if not row:
            continue
        if row.get('C') != 'Sales Details' or row.get('J') != 'Sales Invoice' or row.get('F') != 'Paid':
            raise ValueError('Unsupported transaction at detailed-report row ' + str(rownum))
        key = row['A']
        fields = {'branch': branch_id(row['E']), 'source_bill': row['B'], 'source_invoice': key,
                  'created_at': excel_time(row['D']), 'customer_name': clean(row.get('L')) or 'Walk-in customer',
                  'phone': row.get('M', '').strip(), 'cashier': clean(row.get('Z')) or 'Legacy cashier'}
        if key not in groups:
            groups[key] = {**fields, 'lines': [], 'source_rows': [], 'net': 0, 'source_discount': 0,
                           'tax': 0, 'employees': set(), 'format': 'flat', 'payments': []}
        order = groups[key]
        if any(order[k] != v for k, v in fields.items()):
            raise ValueError('Invoice header conflict: ' + key)
        order['lines'].append(line(row['Q'], row['R'], row['U'], row['T'], row.get('O', '')))
        order['net'] += fils(row.get('V'))
        order['source_discount'] += fils(row.get('W'))
        order['tax'] += fils(row.get('X'))
        order['employees'].update(clean(row.get(k)) for k in ['AD', 'AE'] if row.get(k))
        order['source_rows'].append(rownum)
    for order in groups.values():
        order['employees'] = sorted(order['employees'])
        order['payments'] = [{'method': UNKNOWN_METHOD, 'amount': order['net'], 'reference': 'Source reports Paid; payment method/date not supplied.'}] if order['net'] else []
    return list(groups.values()), extras


def parse_summary(file):
    orders, current, section, notes_next, totals = [], None, '', False, []
    for rownum, row in xlsx_rows(file):
        if row.get('A', '').startswith('Section :'):
            section = row['A'].split(':', 1)[1].strip()
        if row.get('A') == 'Date' and row.get('D') == 'Customer Name':
            if current:
                orders.append(current)
            if row.get('Q') != 'Paid':
                raise ValueError('Unsupported payment status at summary row ' + str(rownum))
            current = {'branch': branch_id(section), 'created_at': report_time(row['B']),
                       'customer_name': clean(row.get('G')) or 'Walk-in customer', 'phone': '', 'cashier': 'Legacy cashier',
                       'source_bill': '', 'lines': [], 'source_rows': [rownum], 'net': None, 'source_discount': None,
                       'gross_reported': None, 'tax': None, 'format': 'summary', 'payments': [], 'notes': '', 'employees': []}
        if row.get('A') == 'Total:':
            totals.append({'row': rownum, 'amount': fils(row.get('R'))})
        if not current:
            continue
        if row.get('A') == 'Bill No':
            if row.get('Q') != 'Sales':
                raise ValueError('Unsupported invoice type at summary row ' + str(rownum))
            current['source_bill'] = row['B']
            current['source_invoice'] = row['B']
            current['phone'] = row.get('G', '').strip()
        if notes_next:
            current['notes'] = clean(row.get('I', ''))
            notes_next = False
        if row.get('A') == 'Payment Narration':
            notes_next = True
        if row.get('C') and row.get('I') and row.get('M') is not None and row.get('P') is not None and row.get('A') and row['A'] != 'Item code':
            item = line(row['A'], row['C'], row['I'], row['M'])
            if item['price'] * item['qty'] != fils(row['P']):
                raise ValueError('Service amount conflict at summary row ' + str(rownum))
            current['lines'].append(item)
            current['source_rows'].append(rownum)
        if row.get('H') and row.get('L'):
            current['payments'].append({'method': clean(row['H']), 'amount': fils(row['L']),
                                        'reference': 'Legacy report payment; receipt date not supplied.'})
        if row.get('A') == 'Cashier':
            current['cashier'] = clean(row.get('C')) or 'Legacy cashier'
        for label, key in [('Gross', 'gross_reported'), ('Discount', 'source_discount'), ('Tax', 'tax'), ('Net Total', 'net')]:
            if row.get('O') == label:
                # A continued invoice may print a subtotal before the final page.
                current[key] = fils(row.get('R'))
    if current:
        orders.append(current)
    return orders, totals


def analytics_reference(file):
    for _, row in xlsx_rows(file):
        if row.get('A') == 'Grand Total':
            return {'cost': fils(row.get('O')), 'profit': fils(row.get('P')),
                    'implied_sales': fils(row.get('O')) + fils(row.get('P'))}
    raise ValueError('Analytics grand total not found')


def prepare(files):
    catalogue = {p['id']: p for p in json.loads((ROOT / 'lib/catalogue.json').read_text(encoding='utf-8'))}
    orders, report = [], {'sources': [], 'warnings': [], 'reference_only': []}
    for file in files:
        first = next(xlsx_rows(file))[1]
        source = {'name': file.name, 'sha256': sha256(file.read_bytes()).hexdigest()}
        if first.get('A') == 'Invoice No.':
            parsed, extras = parse_flat(file)
            source.update(format='flat', excluded_extras=extras)
        elif first.get('A') == 'Sales Detailed Summary':
            parsed, totals = parse_summary(file)
            source.update(format='summary', printed_totals=totals)
        elif first.get('A', '').startswith('FilterAreaHeaders:'):
            report['reference_only'].append({**source, **analytics_reference(file),
                                             'reason': 'Aggregated report without invoice IDs. Not imported as additional sales.'})
            continue
        else:
            raise ValueError('Unsupported workbook: ' + file.name)
        for order in parsed:
            if order['net'] is None or order['net'] < 0 or not order['source_bill'] or not order['lines']:
                raise ValueError('Incomplete invoice: ' + str(order['source_invoice']))
            for item in order['lines']:
                product = catalogue.get(item['id'])
                if product and item['category'] == 'Legacy service':
                    item['category'] = product['category']
            subtotal = sum(item['qty'] * item['price'] for item in order['lines'])
            order['subtotal'] = subtotal
            order['discount'] = max(0, subtotal - order['net'])
            order['extra'] = max(0, order['net'] - subtotal)
            if 'gross_reported' in order and order['gross_reported'] != subtotal:
                report['warnings'].append({'source': file.name, 'invoice': order['source_invoice'],
                    'reason': 'Printed gross differs from service sum.', 'service_gross': subtotal, 'printed_gross': order['gross_reported']})
            if order['source_discount'] != order['discount'] or order['tax']:
                report['warnings'].append({'source': file.name, 'invoice': order['source_invoice'],
                    'reason': 'Preserved net total; effective discount/extra reconciles source rounding or adjustments.',
                    'source_discount': order['source_discount'], 'effective_discount': order['discount'],
                    'extra': order['extra'], 'tax': order['tax']})
            paid = sum(p['amount'] for p in order['payments'])
            if order['format'] == 'summary' and paid != order['net']:
                report['warnings'].append({'source': file.name, 'invoice': order['source_invoice'],
                    'reason': 'Source says Paid but payment breakdown differs; total paid preserved from Paid status.',
                    'payment_breakdown': paid, 'net': order['net']})
                # Never invent a payment method for the missing part, or overstate cash received.
                if paid < order['net']:
                    order['payments'].append({'method': UNKNOWN_METHOD, 'amount': order['net'] - paid,
                                              'reference': 'Paid status reconciliation; missing payment breakdown.'})
                else:
                    order['payments'] = [{'method': UNKNOWN_METHOD, 'amount': order['net'],
                        'reference': 'Paid status; source payment breakdown inconsistent. See private import report.'}]
            order['paid'] = order['net']
            order['source_file'] = file.name
            order['external_id'] = 'legacy-report:' + order['format'] + ':' + order['branch'] + ':' + order['source_invoice']
            order['id'] = 'import-' + sha256(order['external_id'].encode()).hexdigest()[:40]
            order['bill'] = ('LEGACY-' + order['branch'].upper() + '-' + order['source_bill']
                             if order['format'] == 'flat' else order['source_bill'])
            note = ['Imported for local testing. Source does not supply fulfilment status or tailor assignment.',
                    'Source: ' + file.name + '; original invoice: ' + order['source_invoice'] + '; bill: ' + order['source_bill']]
            if order.get('notes'):
                note.append(order['notes'])
            if order['employees']:
                note.append('Legacy employee fields (not verified assignments): ' + ', '.join(order['employees']))
            if order['format'] == 'flat':
                note.append('Paid in legacy export; payment method and receipt date unknown. Receipt uses invoice date for testing.')
            else:
                note.append('Legacy receipt uses invoice date for testing; source does not provide receipt timestamps.')
            invoice_warnings = [w for w in report['warnings'] if w.get('source') == file.name and w.get('invoice') == order['source_invoice']]
            if invoice_warnings:
                note.append('SOURCE RECONCILIATION: Printed net ' + format(Decimal(order['net']) / 1000, '.3f') +
                            ' KWD preserved; service sum ' + format(Decimal(subtotal) / 1000, '.3f') +
                            ' KWD, printed discount ' + format(Decimal(order['source_discount']) / 1000, '.3f') +
                            ' KWD. Effective discount/extra may differ. Source payment breakdown ' +
                            format(Decimal(paid) / 1000, '.3f') + ' KWD. Review the private import report before using this as accounting data.')
            order['notes'] = '\n'.join(note)
            orders.append(order)
        source.update(invoices=len(parsed), lines=sum(len(o['lines']) for o in parsed),
                      total=sum(o['net'] for o in parsed), first_date=min(o['created_at'] for o in parsed),
                      last_date=max(o['created_at'] for o in parsed))
        if source['format'] == 'summary':
            source['printed_total_difference'] = sum(t['amount'] for t in source['printed_totals']) - source['total']
        source['branches'] = dict(Counter(o['branch'] for o in parsed))
        report['sources'].append(source)
    ids = [o['external_id'] for o in orders]
    if len(set(ids)) != len(ids):
        raise ValueError('Duplicate invoices in supplied reports; remove overlapping detailed sources.')
    report['invoice_count'] = len(orders)
    report['line_count'] = sum(len(o['lines']) for o in orders)
    report['total_fils'] = sum(o['net'] for o in orders)
    report['branches'] = dict(Counter(o['branch'] for o in orders))
    report['branch_aliases'] = {'Dasman City Center': 'Dasma', 'West Mishrif': 'Mishref', 'Promenade': 'Promenade Mall'}
    return orders, report


def apply_import(db_path, orders, report, source_files):
    directory = db_path.parent
    batch = 'sales-' + datetime.now(KUWAIT).strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    folder = directory / 'imports' / batch
    folder.mkdir(parents=True)
    connection = sqlite3.connect(db_path, timeout=30, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute('PRAGMA foreign_keys=ON')
    backup_path = directory / 'backups' / (batch + '-before.sqlite')
    backup_path.parent.mkdir(exist_ok=True)
    with closing(sqlite3.connect(backup_path)) as backup:
        connection.backup(backup)
    report.update(batch=batch, backup=str(backup_path), inserted=0, skipped=0, customers_created=0)
    try:
        for source in source_files:
            shutil.copy2(source, folder / source.name)
        connection.execute('BEGIN IMMEDIATE')
        active = {r['id']: r for r in connection.execute('SELECT * FROM branches WHERE active=1')}
        if any(order['branch'] not in active for order in orders):
            raise ValueError('A source branch is inactive/missing. Import does not create or reactivate branches.')
        actor = connection.execute("SELECT id FROM members WHERE role='admin' AND active=1 ORDER BY id LIMIT 1").fetchone()
        if not actor:
            raise ValueError('An active Admin is required for import audit attribution.')
        stamp = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        existing_customers = {}
        for customer in connection.execute('SELECT * FROM customers ORDER BY created_at,id'):
            key = customer_key(customer['name'], customer['phone'])
            if key:
                existing_customers.setdefault(key, customer['id'])
        inserted_ids = []
        for order in orders:
            existing = connection.execute('SELECT id FROM orders WHERE external_id=?', (order['external_id'],)).fetchone()
            if existing:
                report['skipped'] += 1
                continue
            collision = connection.execute('SELECT id FROM orders WHERE id=? OR bill=?', (order['id'], order['bill'])).fetchone()
            if collision:
                raise ValueError('Existing invoice ID/bill conflict: ' + order['bill'])
            customer_id = None
            key = customer_key(order['customer_name'], order['phone'])
            if key:
                customer_id = existing_customers.get(key)
                if not customer_id:
                    customer_id = 'legacy-customer-' + sha256(key.encode()).hexdigest()[:32]
                    connection.execute('INSERT INTO customers(id,name,phone,address,created_at) VALUES (?,?,?,?,?)',
                        (customer_id, order['customer_name'], order['phone'], '', order['created_at']))
                    existing_customers[key] = customer_id
                    report['customers_created'] += 1
            row = {'id': order['id'], 'external_id': order['external_id'], 'branch': order['branch'], 'bill': order['bill'],
                   'kind': 'sale', 'document_type': 'invoice', 'customer_id': customer_id,
                   'customer_name': order['customer_name'], 'phone': order['phone'], 'lines': json.dumps(order['lines'], ensure_ascii=False),
                   'subtotal': order['subtotal'], 'discount': order['discount'], 'extra': order['extra'],
                   'total': order['net'], 'paid': order['paid'], 'notes': order['notes'],
                   'cashier': order['cashier'], 'cashier_id': 'legacy-import', 'status': 'Ongoing', 'job_status': 'Pending',
                   'created_at': order['created_at'], 'updated_at': order['created_at']}
            connection.execute('INSERT INTO orders (' + ','.join(row) + ') VALUES (' + ','.join('?' for _ in row) + ')', tuple(row.values()))
            for index, item in enumerate(order['lines']):
                connection.execute('INSERT INTO work_items(id,order_id,line_index,quantity,status,kind,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
                    (order['id'] + '-line-' + str(index), order['id'], index, item['qty'], 'Pending', 'original', order['created_at'], order['created_at']))
            for index, payment in enumerate(order['payments']):
                if payment['amount']:
                    connection.execute('INSERT INTO payments(id,order_id,branch,amount,method,reference,actor,created_at) VALUES (?,?,?,?,?,?,?,?)',
                        (order['id'] + '-payment-' + str(index), order['id'], order['branch'], payment['amount'],
                         payment['method'], payment['reference'], 'legacy-import', order['created_at']))
            connection.execute('INSERT INTO audit(id,branch,actor,action,entity,detail,created_at) VALUES (?,?,?,?,?,?,?)',
                (batch + ':' + order['id'], order['branch'], actor['id'], 'sale.imported', order['id'],
                 json.dumps({'batch': batch, 'source': order['source_file'], 'sourceInvoice': order['source_invoice'],
                             'sourceRows': order['source_rows']}), stamp))
            inserted_ids.append(order['id'])
            report['inserted'] += 1
        if list(connection.execute('PRAGMA foreign_key_check')):
            raise ValueError('Foreign key validation failed')
        bad = connection.execute("SELECT id FROM orders WHERE external_id LIKE 'legacy-report:%' AND (subtotal-discount+extra<>total OR paid<>COALESCE((SELECT SUM(amount) FROM payments WHERE order_id=orders.id),0)) LIMIT 1").fetchone()
        if bad:
            raise ValueError('Imported financial reconciliation failed')
        report['inserted_ids'] = inserted_ids
        (folder / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        connection.execute('COMMIT')
    except Exception:
        if connection.in_transaction:
            connection.execute('ROLLBACK')
        raise
    finally:
        connection.close()
    return folder / 'report.json'


def customer_key(name, phone):
    digits = re.sub(r'\D', '', phone)
    if len(digits) == 11 and digits.startswith('965'):
        digits = digits[3:]
    # Do not merge unrelated people by name or infer missing phone numbers.
    return digits if len(digits) >= 7 and len(set(digits)) > 1 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    parser.add_argument('--database', type=Path, default=ROOT / 'data/pos.sqlite')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    orders, report = prepare(args.files)
    print(json.dumps({k: v for k, v in report.items() if k != 'warnings'}, indent=2))
    print('Reconciliation warnings:', len(report['warnings']))
    if args.apply:
        if not args.database.is_file():
            raise ValueError('Database must already exist; start the POS once first.')
        destination = apply_import(args.database.resolve(), orders, report, args.files)
        print(json.dumps({'inserted': report['inserted'], 'skipped_existing': report['skipped'],
                          'customers_created': report['customers_created'], 'private_report': str(destination)}, indent=2))
    else:
        output = ROOT / 'data/imports/preview.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        print('Dry run only. Private preview:', output)


if __name__ == '__main__':
    main()
