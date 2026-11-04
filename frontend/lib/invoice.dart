import 'api.dart';

String _html(dynamic value) => (value ?? '')
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// 80 mm paper with a 72 mm printable receipt, or a separate phone invoice.
String invoiceHtml(
  Json order,
  String branch, {
  List<Json> payments = const [],
  bool mobile = false,
  String? fontBase,
}) {
  final lines = (order['lines'] as List? ?? []).cast<Map>();
  final reversed = ['Voided', 'Refunded'].contains(order['status']);
  final due = reversed ? 0 : (order['total'] as num) - (order['paid'] as num);
  final fonts = fontBase == null
      ? ''
      : '''
@font-face{font-family:Receipt;src:url('${_html(fontBase)}/Roboto-Regular.ttf')}
@font-face{font-family:Receipt;src:url('${_html(fontBase)}/Roboto-Bold.ttf');font-weight:700}
@font-face{font-family:Arabic;src:url('${_html(fontBase)}/NotoSansArabic.ttf')}
''';
  String row(String label, dynamic value, {bool bold = false}) =>
      '<div class="row${bold ? ' strong' : ''}"><span>$label</span><span dir="auto">${_html(value)}</span></div>';
  final logo =
      '<svg width="56" height="56" viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="31" fill="currentColor"/><path d="M14 14C28 20 43 38 50 50C36 44 22 29 14 14ZM50 14C44 28 29 43 14 50C20 36 38 21 50 14Z" fill="white"/></svg>';
  return '''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${_html(order['bill'])}${mobile ? ' - WhatsApp invoice' : ''}</title>
<style id="paper">@page{size:${mobile ? '108mm 180mm' : '80mm 297mm'};margin:4mm}</style>
<style>$fonts
*{box-sizing:border-box}body{margin:0;background:${mobile ? '#edf4ef' : '#eee'};color:#111;font:12px Receipt,Arabic,Arial,sans-serif;line-height:1.45}
.toolbar{max-width:440px;margin:18px auto;padding:0 12px;font:14px Arial,sans-serif}.toolbar button{border:0;background:#16834b;color:white;padding:12px 18px;border-radius:6px;cursor:pointer}.toolbar p{color:#444;font-size:13px}
.invoice{width:${mobile ? '100mm' : '72mm'};max-width:100%;margin:0 auto;background:white;padding:${mobile ? '6mm' : '0'};overflow-wrap:anywhere}
header{text-align:center}h1{font-size:${mobile ? '21' : '15'}px;margin:3px 0}h2{font-size:${mobile ? '20' : '15'}px;margin:8px 0;text-align:center}.branch{font-size:13px}.subtitle{margin:4px 0}section{margin-top:12px}.rule{border-top:1px dashed #222;margin:9px 0}.row{display:flex;justify-content:space-between;gap:10px;margin:5px 0}.row>span:last-child{text-align:right;max-width:64%;white-space:pre-wrap}.strong{font-weight:700}.total{font-size:${mobile ? '21' : '14'}px;font-weight:700}
table{width:100%;border-collapse:collapse;table-layout:fixed}thead{border-top:1px dashed #222;border-bottom:1px dashed #222}th,td{padding:5px 1px;vertical-align:top;text-align:right;font-size:11px;font-weight:400}th:first-child,td:first-child{text-align:left;width:49%}th:nth-child(2){width:12%}th:nth-child(3){width:18%}th:nth-child(4){width:21%}tr{break-inside:avoid}.arabic{font-family:Arabic,Arial,sans-serif;direction:rtl;unicode-bidi:plaintext}.note{display:block;margin-top:3px;white-space:pre-wrap;font-size:10px}.payments td,.payments th{border:1px solid #222;text-align:left;width:auto;padding:4px}.payments td:last-child{text-align:right}.footer{text-align:center;margin-top:16px}.muted{color:#555;font-size:10px}
${mobile ? '.invoice{border-radius:12px;font-size:14px}th,td{font-size:12px}header{color:#16834b;border-bottom:2px solid #16834b;padding-bottom:12px}.total{color:#16834b}.rule{border-color:#ccc}thead{background:#eff7f1;border:0}.note{color:#444;font-size:11px}td{padding-top:10px;padding-bottom:10px}h2{text-align:left;font-size:16px}' : ''}
@media screen{.invoice{box-shadow:0 2px 18px #0001;padding-top:${mobile ? '6mm' : '4mm'};padding-bottom:4mm}}
@media print{body{background:white}.toolbar{display:none}.invoice{margin:0;width:100%;border-radius:0;box-shadow:none;padding:${mobile ? '4mm' : '0'}}}
</style></head><body>
<div class="toolbar"><button onclick="printInvoice()">${mobile ? 'Save WhatsApp PDF' : 'Print invoice'}</button><p>${mobile ? 'Choose Save as PDF, then attach the saved invoice manually in WhatsApp.' : '80 mm receipt paper · 72 mm content · print at 100% scale with browser headers and footers off.'}</p></div>
<main class="invoice"><header>$logo<h1>Tailor Express</h1><div class="branch">${_html(branch)}</div><div class="subtitle">${order['kind'] == 'quotation' ? 'Quotation / عرض سعر' : 'Invoice / الفاتورة'}</div></header>
<div class="rule"></div><h2>ORDER #${_html(order['bill'])}</h2>
${mobile ? '' : row('Cashier', order['cashier'])}
${row('Date / التاريخ', displayDate(order['created_at']))}
${row('Customer / العميل', order['customer_name'], bold: true)}
${row('Customer No. / تلفون', order['phone'])}
${(order['address'] ?? '').toString().isEmpty ? '' : row('Address', order['address'])}
${(order['due_date'] ?? '').toString().isEmpty ? '' : '<section>${row('Collection / الاستلام', order['due_date'], bold: true)}</section>'}
<section><table><thead><tr><th># Description<br><span class="arabic">الوصف</span></th><th>Qty<br>كمية</th><th>Price<br>سعر</th><th>Amount<br>إجمالي</th></tr></thead><tbody>
${lines.indexed.map((entry) {
    final (i, l) = entry;
    return '<tr><td>${i + 1}. ${_html(l['name'])}${(l['arabic'] ?? '').toString().isEmpty ? '' : '<div class="arabic">${_html(l['arabic'])}</div>'}${(l['note'] ?? '').toString().isEmpty ? '' : '<span class="note" dir="auto">${_html(l['note'])}</span>'}</td><td>${_html(l['qty'])}</td><td>${money(l['price'])}</td><td>${money(l['price'] * l['qty'])}</td></tr>';
  }).join()}
</tbody></table></section><div class="rule"></div>
${row('Gross / الإجمالي', money(order['subtotal'] ?? order['total']), bold: true)}
${row('Discount / الخصم', money(order['discount'] ?? 0))}
${(order['extra'] ?? 0) == 0 ? '' : row('Extra', money(order['extra']))}
<div class="total">${row('Net Amount / المبلغ الصافي', money(order['total']))}</div>
${row('Paid / المدفوع', money(order['paid']))}
${row('Balance Due / المتبقي', money(due), bold: true)}
${payments.isEmpty ? '' : '<section><table class="payments"><thead><tr><th>Payment type / نوع الدفع</th><th>Amount / المبلغ</th></tr></thead><tbody>${payments.map((p) => '<tr><td>${_html(p['method'])}</td><td>${money(p['amount'])}</td></tr>').join()}</tbody></table></section>'}
<section>${row('Status', order['status'])}${mobile ? '' : row('Tailor', order['tailor_name'] ?? 'Unassigned')}</section>
${!mobile && (order['notes'] ?? '').toString().isNotEmpty ? '<section><b>Order notes</b><div class="note" dir="auto">${_html(order['notes'])}</div></section>' : ''}
<footer class="footer">Thank you for choosing Tailor Express.<br><span class="arabic">شكراً لاختياركم تيلور إكسبرس</span></footer></main>
<script>
async function sizePaper(){await document.fonts.ready;const h=Math.ceil(document.querySelector('.invoice').getBoundingClientRect().height*25.4/96+10);document.querySelector('#paper').textContent='@page{size:${mobile ? '108' : '80'}mm '+Math.max(h,${mobile ? '140' : '100'})+'mm;margin:4mm}';}
async function printInvoice(){await sizePaper();window.print();}
sizePaper();
</script></body></html>''';
}
