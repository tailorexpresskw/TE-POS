import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_express_pos/invoice.dart';

void main() {
  test('receipt paper, separate mobile layout, notes and HTML escaping', () {
    final order = {
      'bill': 'ZC-TEST',
      'customer_name': 'A <B>',
      'phone': '55551234',
      'cashier': 'Reception',
      'created_at': '2026-11-04T12:00:00Z',
      'kind': 'sale',
      'status': 'Ongoing',
      'total': 4000,
      'subtotal': 4000,
      'paid': 1000,
      'discount': 0,
      'extra': 0,
      'tailor_name': 'Private Tailor',
      'lines': [
        {
          'name': 'Hem <script>',
          'qty': 1,
          'price': 2000,
          'note': 'First skirt: 90 cm',
        },
        {'name': 'Hem', 'qty': 1, 'price': 2000, 'note': 'Second skirt: 95 cm'},
      ],
    };
    final receipt = invoiceHtml(order, 'Zahra');
    expect(receipt, contains('80mm 297mm'));
    expect(receipt, contains('72mm'));
    expect(receipt, contains('First skirt: 90 cm'));
    expect(receipt, contains('Second skirt: 95 cm'));
    expect(receipt, contains('A &lt;B&gt;'));
    expect(receipt, contains('Hem &lt;script&gt;'));
    expect(receipt, isNot(contains('Hem <script>')));
    final mobile = invoiceHtml(order, 'Zahra', mobile: true);
    expect(mobile, contains('108mm 180mm'));
    expect(mobile, contains('Save WhatsApp PDF'));
    expect(mobile, isNot(contains('Private Tailor')));
    expect(mobile, contains('3.000'));
  });
}
