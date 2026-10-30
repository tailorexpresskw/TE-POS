"""Import the supplied Excel catalogue without third-party packages."""
import json
import re
import sys
import zipfile
from decimal import Decimal
from pathlib import Path
from xml.etree import ElementTree as ET

source = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(source) as archive:
    strings = [''.join(t.itertext()) for t in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
    sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
    items, category = [], None
    for row in sheet.findall('.//s:row', ns):
        cells = {}
        for cell in row:
            val = cell.find('s:v', ns)
            if val is not None:
                cells[re.sub(r'\d', '', cell.attrib['r'])] = strings[int(val.text)] if cell.attrib.get('t') == 's' else val.text
        if 'A' in cells and 'C' not in cells and 'E' not in cells and not cells['A'].isdigit() and int(row.attrib['r']) > 3:
            category = cells['A'].strip()
        if category and 'C' in cells and 'E' in cells:
            items.append({'id': cells['A'], 'name': cells['C'].strip(), 'category': category, 'price': int(Decimal(cells['E']) * 1000)})
if len(items) != 446 or len({p['id'] for p in items}) != len(items):
    raise ValueError('Unexpected catalogue count or duplicate item code')
(root / 'lib' / 'catalogue.json').write_text(json.dumps(items, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Imported {len(items)} items, {len({p["category"] for p in items})} categories; prices stored as integer fils.')
