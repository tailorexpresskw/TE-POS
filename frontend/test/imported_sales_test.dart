import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'imported receipt methods stay in reports without becoming checkout choices at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Api.client = MockClient((request) async {
          dynamic data;
          switch (request.url.path) {
            case '/api/auth/status':
              data = {'authenticated': true};
              break;
            case '/api/boot':
              data = {
                'member': {
                  'id': 'reception',
                  'name': 'Reception',
                  'role': 'reception',
                  'branches': ['zahra'],
                },
                'branches': [
                  {'id': 'zahra', 'name': 'Zahra Complex'},
                ],
                'catalogue': [],
                'staff': [],
                'methods': [
                  'Cash',
                  'K-NET',
                  'Visa / Mastercard',
                  'Bank transfer',
                ],
                'coupons': [],
              };
              break;
            case '/api/data':
              data = {
                'orders': [],
                'expenses': [],
                'payments': [
                  {
                    'amount': 68933850,
                    'method': 'Legacy paid / method unknown',
                  },
                  {'amount': 5000, 'method': 'LINK'},
                ],
              };
              break;
            default:
              data = {'jobs': [], 'summary': {}, 'totals': {}, 'items': []};
          }
          return http.Response(jsonEncode(data), 200);
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zahra Complex').last);
        await tester.pumpAndSettle();
        final state = tester.state<AppState>(find.byType(PosApp));
        expect(
          state.reportMethods,
          containsAll([
            'Cash',
            'K-NET',
            'LINK',
            'Legacy paid / method unknown',
          ]),
        );
        expect(state.methods, [
          'Cash',
          'K-NET',
          'Visa / Mastercard',
          'Bank transfer',
        ]);
        expect(find.text('Legacy paid / method unknown'), findsOneWidget);
        expect(find.text('LINK'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
