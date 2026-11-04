import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';

void main() {
  for (final role in ['admin', 'manager', 'reception', 'tailor']) {
    for (final width in [1440.0, 390.0]) {
      testWidgets('$role dashboard and tracking at ${width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        final queries = <Uri>[];
        Json? savedMember;
        var status = 'Pending', version = 0;
        Json job() => {
          'id': 'job-1',
          'bill': 'ZC-TEST-1',
          'branch': 'zahra',
          'customer_name': 'Test Customer',
          'lines': [
            {
              'id': '1001',
              'name': 'Hem- Skirt',
              'qty': 1,
              'note': 'Hem to 90 cm',
            },
          ],
          'notes': '',
          'due_date': '2026-11-03',
          'tailor_id': 'tailor-1',
          'tailor_name': 'Test Tailor',
          'tailor_active': 1,
          'job_status': status,
          'version': version,
          'assigned_at': '2026-11-02T10:00:00Z',
          'created_at': '2026-11-02T10:00:00Z',
        };
        Api.client = MockClient((request) async {
          calls.add(request.url.path);
          queries.add(request.url);
          dynamic data;
          switch (request.url.path) {
            case '/api/auth/status':
              data = {
                'authenticated': true,
                'needsSetup': false,
                'canSetup': false,
              };
              break;
            case '/api/boot':
              data = {
                'member': {
                  'id': role == 'tailor' ? 'tailor-1' : role,
                  'name': 'Test User',
                  'role': role,
                  'branches': ['zahra'],
                },
                'branches': [
                  {'id': 'zahra', 'name': 'Zahra Complex'},
                ],
                'catalogue': [],
                'methods': ['Cash'],
                'coupons': [],
                'statuses': ['Ongoing', 'Prepared'],
                'jobStatuses': [
                  'Pending',
                  'In Progress',
                  'On Hold',
                  'Completed',
                ],
                'staff': [
                  {
                    'id': 'tailor-1',
                    'name': 'Test Tailor',
                    'role': 'tailor',
                    'branches': ['zahra'],
                  },
                ],
              };
              break;
            case '/api/tracking':
              data = {
                'jobs': [
                  job(),
                  if (role == 'reception')
                    {
                      ...job(),
                      'id': 'job-2',
                      'bill': 'ZC-TEST-2',
                      'tailor_id': null,
                      'tailor_name': '',
                    },
                ],
                'summary': {
                  'total': 1,
                  'unassigned': role == 'reception' ? 1 : 0,
                  'pending': status == 'Pending' ? 1 : 0,
                  'in_progress': status == 'In Progress' ? 1 : 0,
                  'on_hold': 0,
                  'completed': 0,
                  'overdue': 0,
                },
                'matched': 1,
              };
              break;
            case '/api/tracking/job-1':
              if (request.method == 'POST') {
                final body = jsonDecode(request.body);
                expect(body['status'], 'In Progress');
                expect(body['version'], 0);
                status = body['status'];
                version++;
                data = job();
              } else {
                data = {'job': job(), 'events': [], 'attachments': []};
              }
              break;
            case '/api/members':
              savedMember = Json.from(jsonDecode(request.body));
              data = {'id': 'new-manager'};
              break;
            case '/api/data':
              data = {'orders': [], 'payments': [], 'expenses': []};
              break;
            case '/api/dashboard':
              data = {
                'totals': {
                  'invoices': 1,
                  'total': 2000,
                  'due': 0,
                  'open_jobs': 1,
                },
                'branches': [
                  {
                    'id': 'zahra',
                    'name': 'Zahra Complex',
                    'invoices': 1,
                    'total': 2000,
                    'due': 0,
                    'unassigned': role == 'reception' ? 1 : 0,
                    'open_jobs': 1,
                  },
                ],
              };
              break;
            default:
              data = {};
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        if (role != 'tailor') {
          await tester.tap(find.text('Zahra Complex').last);
          await tester.pumpAndSettle();
        }
        final title = role == 'admin'
            ? 'Admin Dashboard'
            : role == 'reception'
            ? 'Reception Dashboard'
            : role == 'manager'
            ? 'Branch Manager Dashboard'
            : 'Tailor Dashboard';
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (role == 'reception') {
          expect(find.text('Awaiting tailor assignment'), findsOneWidget);
          expect(find.byTooltip('Assign tailor'), findsOneWidget);
        }
        if (role == 'manager') {
          expect(find.text('Branch reports'), findsOneWidget);
          expect(find.text('Administration'), findsNothing);
          expect(
            queries
                .where((q) => q.path == '/api/tracking')
                .last
                .queryParameters['branch'],
            'zahra',
          );
        }
        if (role == 'tailor') {
          expect(calls.contains('/api/data'), isFalse);
          expect(calls.contains('/api/dashboard'), isFalse);
          expect(find.text('POS'), findsNothing);
          expect(find.text('Reports'), findsNothing);
          expect(find.text('Administration'), findsNothing);
        }
        if (role == 'admin') {
          final appState = tester.state<AppState>(find.byType(PosApp));
          appState.update(() => appState.trackingBranch = 'zahra');
          await appState.goScreen(0);
          await tester.pumpAndSettle();
          expect(
            queries
                .where((q) => q.path == '/api/tracking')
                .last
                .queryParameters['branch'],
            'all',
          );
        }
        await tester.ensureVisible(find.text('Pending').first);
        await tester.tap(find.text('Pending').first);
        await tester.pumpAndSettle();
        expect(
          find.text(
            role == 'tailor'
                ? 'My Tailor Tracking'
                : 'Tailor Tracking & Assignment',
          ),
          findsOneWidget,
        );
        expect(find.text('ZC-TEST-1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (role == 'tailor') {
          expect(find.text('Assign tailor'), findsNothing);
          expect(find.text('Invoice / WhatsApp'), findsNothing);
          await tester.ensureVisible(find.text('Update progress'));
          await tester.tap(find.text('Update progress'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(status, 'In Progress');
          expect(tester.takeException(), isNull);
        }
        if (role == 'admin') {
          final appState = tester.state<AppState>(find.byType(PosApp));
          final save = appState.inviteStaff();
          await tester.pumpAndSettle();
          final dialog = find.byType(Dialog);
          final fields = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), 'New Manager');
          await tester.enterText(fields.at(1), 'zahra.manager');
          await tester.enterText(fields.at(2), 'a-long-test-password');
          await tester.ensureVisible(find.text('Role'));
          await tester.tap(
            find.descendant(
              of: dialog,
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Branch Manager').last);
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .descendant(of: dialog, matching: find.byType(CheckboxListTile))
                .first,
          );
          await tester.ensureVisible(find.text('Save staff access'));
          await tester.tap(find.text('Save staff access'));
          await tester.pumpAndSettle();
          await save;
          expect(savedMember?['username'], 'zahra.manager');
          expect(savedMember?['role'], 'manager');
          expect(savedMember?['branches'], ['zahra']);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
  testWidgets(
    'sign-in never offers account creation even before initial setup',
    (tester) async {
      Api.client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'needsSetup': true,
            'authenticated': false,
            'canSetup': false,
          }),
          200,
        ),
      );
      await tester.pumpWidget(const PosRoot());
      await tester.pumpAndSettle();
      expect(find.text('Create account & open POS'), findsNothing);
      expect(find.text('Your name'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
