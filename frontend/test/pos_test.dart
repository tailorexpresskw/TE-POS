import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

void main() {
  for (final size in [
    const Size(1440, 900),
    const Size(800, 1024),
    const Size(390, 844),
  ]) {
    testWidgets('branch selection and cashier work at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <Json>[];
      Api.client = MockClient((request) async {
        dynamic result;
        if (request.url.path.endsWith('/auth/status')) {
          result = {
            'authenticated': true,
            'needsSetup': false,
            'canSetup': true,
          };
        } else if (request.url.path.endsWith('/boot')) {
          result = {
            'member': {
              'id': 'owner',
              'name': 'Owner',
              'role': 'admin',
              'branches': [],
            },
            'branches': [
              {'id': 'zahra', 'name': 'Zahra Complex'},
              {'id': 'aventura', 'name': 'Aventura'},
            ],
            'catalogue': [
              {
                'id': '1001',
                'name': 'Hem- Skirt',
                'category': 'Skirt',
                'price': 2000,
                'active': 1,
              },
              {
                'id': '1002',
                'name': 'Hem/cuff - Skirt',
                'category': 'Skirt',
                'price': 3000,
                'active': 1,
              },
            ],
            'staff': [],
            'methods': ['Cash', 'K-NET'],
            'statuses': [
              'Ongoing',
              'Prepared',
              'Packed',
              'Out for Delivery',
              'Delivered',
              'Closed',
            ],
            'coupons': [
              {'id': 'family', 'name': 'Family and Friends', 'percent': 20},
            ],
          };
        } else if (request.url.path.endsWith('/data')) {
          result = {'orders': saved, 'payments': [], 'expenses': []};
        } else if (request.url.path.endsWith('/orders')) {
          final body = Json.from(jsonDecode(request.body));
          expect(body['branch'], 'zahra');
          expect(body['lines'][0]['price'], 2000);
          result = {
            ...body,
            'bill': 'ZC-TEST-001',
            'total': 2000,
            'paid': 0,
            'status': 'Ongoing',
            'customer_name': 'Walk-in customer',
            'customer_id': null,
            'phone': '',
            'cashier': 'Owner',
            'created_at': '2026-10-30T12:00:00Z',
            'version': 0,
          };
          saved.add(result);
        } else {
          result = {'error': 'Unknown endpoint'};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(const PosRoot());
      await tester.pumpAndSettle();
      expect(find.text('Select location'), findsWidgets);
      await tester.tap(find.text('Zahra Complex'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('POS'));
      await tester.pumpAndSettle();
      expect(find.text('Hem- Skirt'), findsOneWidget);
      await tester.tap(find.text('Hem- Skirt'));
      await tester.pumpAndSettle();
      if (size.width < 1050) {
        await tester.tap(find.textContaining('Cart ·'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Pay & Print'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save Unpaid'));
      await tester.pumpAndSettle();
      expect(saved.length, 1);
      expect(saved.first['kind'], 'sale');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
  test(
    'KWD parsing preserves three decimal precision and rejects invalid amounts',
    () {
      expect(parseMoney('0.001'), 1);
      expect(parseMoney('12.5'), 12500);
      expect(parseMoney('2'), 2000);
      expect(() => parseMoney('-1'), throwsException);
      expect(() => parseMoney('1.0001'), throwsException);
    },
  );
}
