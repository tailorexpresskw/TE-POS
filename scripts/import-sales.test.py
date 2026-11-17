import importlib.util
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from zipfile import ZipFile

spec = importlib.util.spec_from_file_location('sales_import', Path(__file__).with_name('import-sales.py'))
sales = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sales)


class ImportTests(unittest.TestCase):
    def workbook(self, path, rows):
        from xml.sax.saxutils import escape
        xml = '<worksheet xmlns="' + sales.NS['s'] + '"><sheetData>'
        for index, cells in enumerate(rows, 1):
            xml += '<row r="' + str(index) + '">'
            for col, value in cells.items():
                xml += '<c r="' + col + str(index) + '" t="inlineStr"><is><t>' + escape(value) + '</t></is></c>'
            xml += '</row>'
        xml += '</sheetData></worksheet>'
        with ZipFile(path, 'w') as archive:
            archive.writestr('xl/worksheets/sheet1.xml', xml)

    def database(self, path):
        with closing(sqlite3.connect(path)) as db, db:
            for migration in sorted((sales.ROOT / 'drizzle').glob('*.sql')):
                db.executescript(migration.read_text(encoding='utf-8'))
            db.execute("INSERT INTO members(id,user_id,email,name,role,branches) VALUES ('owner','owner','test@invalid','Test Admin','admin','[]')")

    def test_rounding_time_aliases_and_no_html_execution(self):
        self.assertEqual(sales.fils('3.3999999999999999'), 3400)
        self.assertEqual(sales.fils('8,373.500'), 8373500)
        self.assertEqual(sales.excel_time('46174.014340277776'), '2026-05-31T21:20:39.000Z')
        self.assertEqual(sales.report_time('Thu,01-Oct-2026 10:26'), '2026-10-01T07:26:00.000Z')
        self.assertEqual(sales.branch_id('West Mishrif'), 'mishref')
        self.assertEqual(sales.clean('note<br><b>90 cm</b>'), 'note\n90 cm')
        self.assertIsNone(sales.customer_key('Anonymous', '00000000'))
        self.assertEqual(sales.customer_key('Person', '+965 5555 1234'), '55551234')

    def test_import_is_atomic_idempotent_and_never_creates_staff_or_live_alerts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            file = root / 'flat.xlsx'
            self.workbook(file, [
                {'A': 'Invoice No.', 'V': 'Net Amount'},
                {'A': '101', 'B': '42', 'C': 'Sales Details', 'D': '46174.5', 'E': 'Zahra Complex',
                 'F': 'Paid', 'J': 'Sales Invoice', 'L': 'Test Customer', 'M': '55551234',
                 'O': 'Pant', 'Q': '1018', 'R': 'Hem', 'T': '2', 'U': '2', 'V': '3.3999999999999999', 'W': '0.6', 'X': '0', 'Z': 'Old Cashier'},
                {'A': '0', 'B': '0', 'C': 'Extras', 'V': '-318'},
            ])
            orders, report = sales.prepare([file])
            self.assertEqual(report['total_fils'], 3400)
            self.assertEqual(orders[0]['discount'], 600)
            self.assertEqual(report['sources'][0]['excluded_extras'][0]['amount'], -318000)
            db_path = root / 'pos.sqlite'
            self.database(db_path)
            first = sales.apply_import(db_path, orders, report, [file])
            self.assertTrue(first.is_file())
            self.assertEqual(report['inserted'], 1)
            orders, second = sales.prepare([file])
            sales.apply_import(db_path, orders, second, [file])
            self.assertEqual(second['skipped'], 1)
            with closing(sqlite3.connect(db_path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM orders').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM members').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM notifications').fetchone()[0], 0)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM integration_events').fetchone()[0], 0)
                self.assertEqual(db.execute('SELECT SUM(amount) FROM payments').fetchone()[0], 3400)
                self.assertEqual(db.execute('SELECT tailor_id,status FROM work_items').fetchone(), (None, 'Pending'))
                self.assertEqual(db.execute('SELECT method FROM payments').fetchone()[0], sales.UNKNOWN_METHOD)
            # A second invoice failing after a valid insert rolls the entire attempt back.
            one = dict(orders[0], id='new-import', external_id='new-import', bill='new-bill')
            clash = dict(orders[0], id='different', external_id='different')
            with self.assertRaisesRegex(ValueError, 'conflict'):
                sales.apply_import(db_path, [one, clash], {}, [file])
            with closing(sqlite3.connect(db_path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM orders').fetchone()[0], 1)

    def test_summary_continuation_totals_and_missing_payment_method(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'summary.xlsx'
            self.workbook(file, [
                {'A': 'Sales Detailed Summary'}, {'A': 'Section : Avenues'},
                {'A': 'Date', 'B': 'Thu,01-Oct-2026 10:26', 'D': 'Customer Name', 'G': 'Test', 'N': 'Payment Status', 'Q': 'Paid'},
                {'A': 'Bill No', 'B': 'AV-TEST', 'D': 'Mobile', 'G': '55551234', 'N': 'Type', 'Q': 'Sales'},
                {'A': 'Item code', 'C': 'Item Name', 'I': 'Qty', 'M': 'Rate', 'P': 'Amount'},
                {'A': '1018', 'C': 'Hem', 'I': '1', 'M': '2.000', 'P': '2.000'},
                {'A': 'Section : Avenues'},  # continued page without a second bill header
                {'A': '1236', 'C': 'Length', 'I': '1', 'M': '2.000', 'P': '2.000'},
                {'A': 'Cashier', 'C': 'Old Cashier', 'O': 'Gross', 'R': '4.000'},
                {'O': 'Discount', 'R': '0.000'}, {'O': 'Tax', 'R': '0.000'},
                {'O': 'Net Total', 'R': '4.000'}, {'A': 'Total:', 'R': '4.000'},
            ])
            orders, report = sales.prepare([file])
            self.assertEqual(len(orders), 1)
            self.assertEqual(len(orders[0]['lines']), 2)
            self.assertEqual(orders[0]['payments'][0]['method'], sales.UNKNOWN_METHOD)
            self.assertEqual(orders[0]['paid'], 4000)
            self.assertEqual(report['sources'][0]['printed_total_difference'], 0)
            self.assertIn('SOURCE RECONCILIATION', orders[0]['notes'])


if __name__ == '__main__':
    unittest.main()
