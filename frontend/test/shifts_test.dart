import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

http.Response response(dynamic value) => http.Response(jsonEncode(value), 200);

Json fixture(String role) => {
  'member': {
    'id': role,
    'name': role,
    'role': role,
    'branches': ['zahra'],
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

void main() {
  test(
    'late responses cannot enter a new session; login waits for lock logout',
    () async {
      final oldReply = Completer<http.Response>(),
          logoutReply = Completer<http.Response>();
      final calls = <String>[];
      Api.client = MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/boot')) return oldReply.future;
        if (request.url.path.endsWith('/logout')) return logoutReply.future;
        return response({'ok': true});
      });
      final old = Api.get('boot');
      final rejected = expectLater(
        old,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'STALE_SESSION'),
        ),
      );
      Api.invalidatePendingRequests();
      Api.queueSessionLogout();
      final login = Api.post('auth/login', {
        'username': 'admin',
        'password': 'test password',
      });
      await Future<void>.delayed(Duration.zero);
      expect(calls, isNot(contains('/api/auth/login')));
      oldReply.complete(response({'private': 'old-session-data'}));
      await rejected;
      logoutReply.complete(response({'ok': true}));
      await login;
      expect(calls.last, '/api/auth/login');
    },
  );

  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'Admin saves working hours and views security analysis at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Json? saved;
        Api.client = MockClient((request) async {
          switch (request.url.path) {
            case '/api/auth/status':
              return response({'authenticated': true});
            case '/api/boot':
              return response(fixture('admin'));
            case '/api/shifts/staff':
              if (request.method == 'POST') {
                saved = Json.from(jsonDecode(request.body));
                return response({'ok': true});
              }
              return response({
                'staff': {
                  'branches': ['zahra'],
                },
                'policy': {
                  'enabled': false,
                  'revision': 3,
                  'weekly': [],
                  'exceptions': [],
                },
              });
            case '/api/shifts/alerts':
              return response({
                'summary': {
                  'attempts': 3,
                  'events': 1,
                  'staff': 1,
                  'login_attempts': 3,
                },
                'items': [
                  {
                    'staff_name': 'Test Reception',
                    'username': 'reception',
                    'source': 'login',
                    'attempts': 3,
                    'reason': 'Scheduled day off',
                    'attempted_branch': '',
                    'first_at': '2026-11-16T05:00:00Z',
                    'last_at': '2026-11-16T05:01:00Z',
                    'path': '/api/auth/login',
                  },
                ],
              });
            default:
              return response({
                'orders': [],
                'payments': [],
                'expenses': [],
                'jobs': [],
                'summary': {},
                'totals': {},
                'items': [],
                'branches': [],
              });
          }
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zahra Complex').last);
        await tester.pumpAndSettle();
        final state = tester.state<AppState>(find.byType(PosApp));
        unawaited(
          state.editWorkingHours({'id': 'staff', 'name': 'Test Reception'}),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.tap(find.text('Add weekly period'));
        await tester.pumpAndSettle();
        expect(find.text('Weekly shift period'), findsOneWidget);
        await tester.tap(find.text('Use shift period'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add dated exception'));
        await tester.tap(find.text('Add dated exception'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use dated exception'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save working hours'));
        await tester.pumpAndSettle();
        expect(saved?['enabled'], true);
        expect(saved?['revision'], 3);
        expect(saved?['weekly'], [
          {'day': 0, 'start': '09:00', 'end': '17:00', 'branch': ''},
        ]);
        expect((saved?['exceptions'] as List).single['off'], true);
        unawaited(state.showShiftAlerts());
        await tester.pumpAndSettle();
        expect(find.textContaining('3 attempts'), findsWidgets);
        expect(find.textContaining('Scheduled day off'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  testWidgets(
    'server-derived deadline closes private dialogs and restores only same-account branch draft',
    (tester) async {
      Api.client = MockClient((request) async {
        if (request.url.path.endsWith('/status')) {
          return response({'authenticated': true});
        }
        if (request.url.path.endsWith('/boot')) {
          return response(fixture('reception'));
        }
        return response({
          'ok': true,
          'orders': [],
          'payments': [],
          'expenses': [],
          'jobs': [],
          'summary': {},
          'totals': {},
          'items': [],
          'branches': [],
        });
      });
      await tester.pumpWidget(const PosRoot());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zahra Complex').last);
      await tester.pumpAndSettle();
      final state = tester.state<AppState>(find.byType(PosApp));
      state.cart = [
        {'id': '1001', 'name': 'Hem', 'price': 2000, 'qty': 1, 'note': '90 cm'},
      ];
      state.customer = {'id': 'c', 'name': 'Private Customer'};
      final draftId = state.draftId;
      unawaited(
        showDialog<void>(
          context: state.context,
          builder: (_) =>
              const AlertDialog(title: Text('Private customer record')),
        ),
      );
      state.configureShiftLock({
        'enabled': true,
        'revision': 1,
        'serverTime': '2020-01-01T10:00:00Z',
        'endsAt': '2020-01-01T10:00:02Z',
        'allowedBranches': ['zahra'],
      });
      await tester.pumpAndSettle();
      expect(find.text('Private customer record'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Branch POS - Staff sign in'), findsOneWidget);
      expect(find.text('Private customer record'), findsNothing);
      expect(state.boot, isNull);
      expect(state.cart, isEmpty);
      expect(state.suspendedShiftDraft?['draftId'], draftId);
      state.boot = fixture('manager');
      state.branch = {'id': 'zahra', 'name': 'Zahra Complex'};
      state.restoreShiftDraft();
      expect(state.cart, isEmpty);
      state.boot = fixture('reception');
      state.branch = {'id': 'avenues', 'name': 'Avenues'};
      state.restoreShiftDraft();
      expect(state.cart, isEmpty);
      state.branch = {'id': 'zahra', 'name': 'Zahra Complex'};
      state.restoreShiftDraft();
      expect(state.cart.single['note'], '90 cm');
      expect(state.customer?['name'], 'Private Customer');
      expect(state.draftId, draftId);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
