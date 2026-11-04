import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_express_pos/whatsapp.dart';

void main() {
  test(
    'manual WhatsApp links normalize numbers and preserve invoice content',
    () {
      expect(whatsappPhone('5555 1234'), '96555551234');
      expect(whatsappPhone('+965 5555 1234'), '96555551234');
      expect(whatsappPhone('00965-5555-1234'), '96555551234');
      expect(() => whatsappPhone('12345'), throwsException);
      final invoice = {
        'bill': 'ZC-1',
        'customer_name': 'A & B',
        'phone': '55551234',
        'total': 2000,
        'paid': 500,
        'status': 'Ongoing',
        'due_date': '2026-11-03',
        'lines': [
          {
            'qty': 1,
            'price': 2000,
            'name': 'Hem & cuff',
            'note': 'Internal note',
          },
        ],
      };
      final message = whatsappInvoice(invoice, 'Zahra Complex');
      expect(message, contains('Balance due: 1.500 KWD'));
      expect(message, contains('Collection: 2026-11-03'));
      expect(message, isNot(contains('Internal note')));
      final draft = whatsappDraft(invoice['phone'] as String, message);
      expect(draft.host, 'wa.me');
      expect(draft.path, '/96555551234');
      expect(draft.queryParameters['text'], message);
      expect(
        whatsappInvoice({...invoice, 'status': 'Refunded', 'paid': 0}, 'Zahra'),
        contains('Balance due: 0.000 KWD'),
      );
    },
  );
}
