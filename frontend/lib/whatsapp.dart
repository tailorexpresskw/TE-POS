import 'api.dart';

String whatsappPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 8) digits = '965$digits';
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits)) {
    throw Exception(
      'Enter a WhatsApp number with country code, or an 8-digit Kuwait number.',
    );
  }
  return digits;
}

String whatsappInvoice(Json order, String branch) {
  final lines = (order['lines'] as List).cast<Map>();
  final reversed = ['Voided', 'Refunded'].contains(order['status']);
  return [
    '*TAILOR EXPRESS*',
    branch,
    '*Invoice: ${order['bill']}*',
    'Customer: ${order['customer_name']}',
    '',
    ...lines
        .take(30)
        .map(
          (l) =>
              '${l['qty']} x ${l['name']} - ${money(l['price'] * l['qty'])} KWD',
        ),
    if (lines.length > 30)
      '... and ${lines.length - 30} more items (see printed invoice).',
    '',
    'Total: ${money(order['total'])} KWD',
    'Paid: ${money(order['paid'])} KWD',
    'Balance due: ${money(reversed ? 0 : order['total'] - order['paid'])} KWD',
    if ((order['due_date'] ?? '').toString().isNotEmpty)
      'Collection: ${order['due_date']}',
    'Status: ${order['status']}',
    'Thank you for choosing Tailor Express.',
  ].join('\n');
}

Uri whatsappDraft(String phone, String message) => Uri.parse(
  'https://wa.me/${whatsappPhone(phone)}',
).replace(queryParameters: {'text': message});
