import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

void main() {
  testWidgets('staff login and logout never offer user registration', (
    tester,
  ) async {
    Api.client = MockClient((request) async {
      dynamic data;
      switch (request.url.path) {
        case '/api/auth/status':
          data = {
            'needsSetup': false,
            'authenticated': false,
            'canSetup': false,
          };
          break;
        case '/api/auth/login':
          final body = jsonDecode(request.body);
          expect(body['username'], 'admin');
          expect(body['password'], 'a-long-test-password');
          data = {'ok': true};
          break;
        case '/api/boot':
          data = {
            'member': {
              'id': 'owner',
              'name': 'Owner',
              'role': 'admin',
              'branches': [],
            },
            'branches': [
              {'id': 'zahra', 'name': 'Zahra Complex'},
            ],
            'catalogue': [],
            'staff': [],
            'coupons': [],
            'methods': ['Cash'],
            'statuses': ['Ongoing'],
          };
          break;
        case '/api/auth/logout':
          data = {'ok': true};
          break;
        default:
          data = {
            'orders': [],
            'payments': [],
            'expenses': [],
            'jobs': [],
            'summary': {},
            'totals': {},
            'branches': [],
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
    expect(find.text('Create your administrator account'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), 'admin');
    await tester.enterText(inputs.at(1), 'a-long-test-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Zahra Complex'), findsOneWidget);
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('Branch POS - Staff sign in'), findsOneWidget);
    expect(find.text('Create your administrator account'), findsNothing);
    expect(find.textContaining('ChatGPT'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
