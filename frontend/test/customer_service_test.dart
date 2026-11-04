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
      'customer details, create/edit and separate service notes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final customers = <String, Json>{
          'one': {
            'id': 'one',
            'name': 'Mariam',
            'phone': '55551234',
            'address': 'Kuwait',
          },
        };
        Api.client = MockClient((request) async {
          final path = request.url.path;
          dynamic data;
          if (path.endsWith('/auth/status')) {
            data = {'authenticated': true};
          } else if (path.endsWith('/boot')) {
            data = {
              'member': {
                'id': 'reception',
                'role': 'reception',
                'name': 'Reception',
                'branches': ['zahra'],
              },
              'branches': [
                {'id': 'zahra', 'name': 'Zahra Complex'},
              ],
              'catalogue': [
                {
                  'id': '1001',
                  'name': 'Hem- Skirt',
                  'category': 'Skirt',
                  'price': 2000,
                  'active': 1,
                },
              ],
              'staff': [],
              'methods': ['Cash'],
              'coupons': [],
              'statuses': ['Ongoing'],
            };
          } else if (path == '/api/customers' && request.method == 'GET') {
            data = [customers['one']];
          } else if (path == '/api/customers' && request.method == 'POST') {
            final values = Json.from(jsonDecode(request.body));
            data = customers['two'] = {...values, 'id': 'two'};
          } else if (path.startsWith('/api/customers/')) {
            final id = path.split('/').last;
            if (request.method == 'POST') {
              data = customers[id] = {
                ...customers[id]!,
                ...Json.from(jsonDecode(request.body)),
              };
            } else {
              expect(request.url.queryParameters['branch'], 'zahra');
              data = {
                'customer': customers[id],
                'summary': {'bills': 0, 'total': 0, 'due': 0},
                'history': [],
              };
            }
          } else {
            data = {
              'orders': [],
              'payments': [],
              'expenses': [],
              'jobs': [],
              'summary': {},
            };
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zahra Complex').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('POS'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Walk-in customer'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '55551234');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mariam'));
        await tester.pumpAndSettle();
        expect(find.text('Kuwait'), findsOneWidget);
        await tester.tap(find.text('Edit details'));
        await tester.pumpAndSettle();
        final name = find.widgetWithText(TextFormField, 'Customer name');
        await tester.enterText(name, 'Mariam Updated');
        await tester.tap(find.text('Save customer'));
        await tester.pumpAndSettle();
        expect(customers['one']!['name'], 'Mariam Updated');
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
        expect(find.text('No invoices in this branch yet.'), findsOneWidget);
        await tester.tap(find.text('Add customer'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Customer name'),
          'New Customer',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number'),
          '55556789',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Address'),
          'New address',
        );
        await tester.tap(find.text('Save customer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select customer'));
        await tester.pumpAndSettle();
        final state = tester.state<AppState>(find.byType(PosApp));
        expect(state.customer?['phone'], '55556789');
        await tester.tap(find.text('Hem- Skirt'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(state.cart.length, 1);
        expect(state.cart.first['note'], '');
        if (width < 1050) {
          await tester.tap(find.textContaining('Cart'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Hem- Skirt').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.widgetWithText(TextFormField, 'Price (KWD)'),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Service notes / measurements'),
          'First skirt: 90 cm',
        );
        await tester.tap(find.text('Save service'));
        await tester.pumpAndSettle();
        await state.addItem(state.catalogue.first);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        await tester.tap(find.text('Hem- Skirt').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Service notes / measurements'),
          'Second skirt: 95 cm',
        );
        await tester.tap(find.text('Save service'));
        await tester.pumpAndSettle();
        expect(state.cart.length, 2);
        expect(state.cart.map((l) => l['note']), [
          'First skirt: 90 cm',
          'Second skirt: 95 cm',
        ]);
        await tester.tap(find.text('First skirt: 90 cm'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Service notes / measurements'),
          'First skirt: 91 cm',
        );
        await tester.tap(find.text('Save service'));
        await tester.pumpAndSettle();
        expect(state.cart.first['note'], 'First skirt: 91 cm');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
