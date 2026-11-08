import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets('notification inbox and read state at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var read = false;
      Api.client = MockClient((request) async {
        dynamic value;
        switch (request.url.path) {
          case '/api/auth/status':
            value = {'authenticated': true};
            break;
          case '/api/boot':
            value = {
              'member': {
                'id': 'tailor',
                'role': 'tailor',
                'name': 'Tailor',
                'branches': ['zahra'],
              },
              'branches': [
                {'id': 'zahra', 'name': 'Zahra Complex'},
              ],
              'catalogue': [],
              'staff': [],
              'methods': [],
              'coupons': [],
            };
            break;
          case '/api/notifications/config':
            value = {'enabled': true, 'publicKey': 'test-key'};
            break;
          case '/api/notifications':
            if (request.method == 'POST') {
              expect(jsonDecode(request.body)['action'], 'read');
              read = true;
              value = {'ok': true};
            } else {
              value = {
                'unread': read ? 0 : 1,
                'items': [
                  {
                    'id': 'notice',
                    'order_id': 'invoice',
                    'branch': 'zahra',
                    'type': 'assigned',
                    'title': 'New tailor assignment',
                    'message': 'Invoice ZC-TEST has been assigned to you.',
                    'created_at': '2026-11-04T12:00:00Z',
                    'read_at': read ? '2026-11-04T12:10:00Z' : '',
                  },
                ],
              };
            }
            break;
          default:
            value = {'jobs': [], 'summary': {}};
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(const PosRoot());
      await tester.pumpAndSettle();
      expect(
        tester.state<AppState>(find.byType(PosApp)).unreadNotifications,
        1,
      );
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('New tailor assignment'), findsOneWidget);
      expect(find.text('Install POS app'), findsOneWidget);
      await tester.ensureVisible(find.text('Mark all as read'));
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(read, true);
      expect(
        tester.state<AppState>(find.byType(PosApp)).unreadNotifications,
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
