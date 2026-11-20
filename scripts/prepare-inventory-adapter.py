"""Prepare reviewable inventory-app changes without touching its working tree."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
stage = root / 'work/inventory-integration'
stage.mkdir(parents=True, exist_ok=True)
manifest = {'source': str(source), 'files': {}}


def replace_once(content, old, new):
    if content.count(old) != 1:
        raise ValueError('Inventory source differs; review before applying: ' + old[:100])
    return content.replace(old, new, 1)


server = (source / 'server.js').read_text(encoding='utf-8')
original = server
if 'require("./pos-deliveries.cjs")' in server:
    raise ValueError('The inventory connector is already installed. Test the applied source directly; do not prepare the same patch twice.')
server = replace_once(server, 'app.use(express.static(path.join(__dirname, "public"))); // serve frontend',
    'app.use(express.static(path.join(__dirname, "public"))); // serve frontend\n\n'
    '// Authenticated POS adapter; serializes JSON mutations with legacy writes.\n'
    'const { installPosIntegration, guardPosDelivery } = require("./pos-deliveries.cjs");\n'
    'installPosIntegration({ app, loadData, saveData, mainStorageBranchId: MAIN_STORAGE_BRANCH_ID });')
server = replace_once(server, '    if (!allStatuses.includes(next)) return res.status(400).json({ error: "Invalid status" });',
    '    if (!allStatuses.includes(next)) return res.status(400).json({ error: "Invalid status" });\n'
    '    try { guardPosDelivery(delivery, next); } catch (error) {\n'
    '      return res.status(error.status || 409).json({ error: error.message });\n'
    '    }')
server = replace_once(server, '    if (delivery.status === "delivered") return res.status(400).json({ error: "Delivery already delivered" });',
    '    if (["delivered", "cancelled"].includes(delivery.status)) return res.status(400).json({ error: "Delivery is already finished or cancelled" });')
server = replace_once(server, '    if (idx === -1) return res.status(404).json({ error: "Delivery not found" });\n    data.deliveries.splice(idx, 1);',
    '    if (idx === -1) return res.status(404).json({ error: "Delivery not found" });\n'
    '    if (data.deliveries[idx].posRequestId) return res.status(409).json({ error: "Cancel linked deliveries from POS; their history must be retained." });\n'
    '    data.deliveries.splice(idx, 1);')


def output(relative, before, after):
    destination = stage / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(after, encoding='utf-8')
    manifest['files'][relative] = hashlib.sha256((source / relative).read_bytes()).hexdigest()
    patch = ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='a/' + relative, tofile='b/' + relative))
    patch_file = root / 'integrations/inventory' / (relative.replace('/', '-') + '.patch')
    patch_file.write_text(patch, encoding='utf-8')


output('server.js', original, server)
html = (source / 'public/index.html').read_text(encoding='utf-8')
original = html
html = replace_once(html, '      in_transit: "in transit",', '      in_transit: "in transit",\n      cancelled: "cancelled",')
html = replace_once(html, '      in_transit: "في الطريق",', '      in_transit: "في الطريق",\n      cancelled: "ملغي",')
html = replace_once(html, '    const active = all.filter((d) => d.status !== "delivered");', '    const active = all.filter((d) => !["delivered", "cancelled"].includes(d.status));')
html = replace_once(html, '    const delivered = (state.deliveries || []).filter((d) => d.status === "delivered");', '    const delivered = (state.deliveries || []).filter((d) => ["delivered", "cancelled"].includes(d.status));')
html = replace_once(html, '      .filter((d) => d.status !== "delivered")', '      .filter((d) => !["delivered", "cancelled"].includes(d.status))')
html = replace_once(html, '        if (d.status === "new" || d.status === "ready") {', '        if ((!d.posRequestId && d.status === "new") || (d.status === "ready" && (!d.posRequestId || d.posReady))) {')
html = replace_once(html, '      const canDelete = state.user.role === "admin" || state.user.role === "manager";\n      const canSet = ["admin", "manager", "supervisor", "driver_supervisor", "staff"].includes(state.user.role);\n      const canAssignDriver',
    '      const canDelete = !d.posRequestId && (state.user.role === "admin" || state.user.role === "manager");\n'
    '      const canSet = !d.posRequestId && ["admin", "manager", "supervisor", "driver_supervisor", "staff"].includes(state.user.role);\n      const canAssignDriver')
output('public/index.html', original, html)
shutil.copy2(root / 'integrations/inventory/pos-deliveries.cjs', stage / 'pos-deliveries.cjs')
(stage / 'package.json').write_text(json.dumps({'private': True, 'type': 'commonjs'}), encoding='utf-8')
(stage / 'apply-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Inventory adapter and patches prepared in work/inventory-integration; source working tree unchanged.')
