import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_express_pos/api.dart';
import 'package:tailor_express_pos/app.dart';
import 'package:tailor_express_pos/invoice.dart';

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'service selection, reception approval, backjob credit rule and partial refund at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <Json>[];
        var version = 0;
        final tasks = <Json>[
          {
            'id': 'work-a',
            'line_index': 0,
            'quantity': 2,
            'name': 'Hem- Skirt',
            'note': '90 cm',
            'tailor_id': 'a',
            'tailor_name': 'Tailor A',
            'status': 'Pending',
            'kind': 'original',
            'is_latest': true,
          },
          {
            'id': 'work-b',
            'line_index': 1,
            'quantity': 1,
            'name': 'Hem- Pant',
            'note': '95 cm',
            'tailor_id': 'a',
            'tailor_name': 'Tailor A',
            'status': 'Pending',
            'kind': 'original',
            'is_latest': true,
          },
        ];
        Json order() => {
          'id': 'invoice-one',
          'bill': 'ZC-TEST',
          'branch': 'zahra',
          'kind': 'sale',
          'document_type': 'invoice',
          'version': version,
          'customer_name': 'Customer',
          'phone': '55551234',
          'address': '',
          'total': 6000,
          'paid': 6000,
          'subtotal': 6000,
          'discount': 0,
          'extra': 0,
          'refunded_total': 0,
          'status': 'Ongoing',
          'job_status': 'Pending',
          'notes': '',
          'due_date': '',
          'tailor_id': 'a',
          'created_at': '2026-11-15T10:00:00Z',
          'lines': [
            {
              'id': '1001',
              'name': 'Hem- Skirt',
              'price': 2000,
              'qty': 2,
              'note': '90 cm',
            },
            {
              'id': '1002',
              'name': 'Hem- Pant',
              'price': 2000,
              'qty': 1,
              'note': '95 cm',
            },
          ],
        };
        Json job() => {...order(), 'tasks': tasks, 'unassigned_count': 0};
        Api.client = MockClient((request) async {
          dynamic data;
          if (request.method == 'POST') {
            final body = Json.from(jsonDecode(request.body));
            calls.add(body);
            version++;
            if (body['action'] == 'review') tasks.first['status'] = 'Completed';
            data = request.url.path.contains('/tracking/') ? job() : order();
          } else {
            switch (request.url.path) {
              case '/api/auth/status':
                data = {'authenticated': true, 'needsSetup': false};
                break;
              case '/api/boot':
                data = {
                  'member': {
                    'id': 'reception',
                    'name': 'Reception',
                    'role': 'reception',
                    'permissions': {'refund': true, 'cancel': true},
                    'branches': ['zahra'],
                  },
                  'branches': [
                    {'id': 'zahra', 'name': 'Zahra Complex'},
                  ],
                  'catalogue': [],
                  'methods': ['Cash'],
                  'statuses': ['Ongoing', 'Prepared'],
                  'staff': [
                    {
                      'id': 'a',
                      'name': 'Tailor A',
                      'role': 'tailor',
                      'branches': ['zahra'],
                    },
                    {
                      'id': 'b',
                      'name': 'Tailor B',
                      'role': 'tailor',
                      'branches': ['zahra'],
                    },
                  ],
                };
                break;
              case '/api/orders/invoice-one':
                data = {
                  'order': order(),
                  'tasks': tasks,
                  'payments': [],
                  'attachments': [],
                };
                break;
              case '/api/tracking/invoice-one':
                data = {'job': job(), 'events': [], 'attachments': []};
                break;
              case '/api/data':
                data = {'orders': [], 'payments': [], 'expenses': []};
                break;
              case '/api/tracking':
                data = {
                  'jobs': [job()],
                  'summary': {},
                  'matched': 1,
                };
                break;
              case '/api/dashboard':
                data = {
                  'totals': {},
                  'branches': [],
                  'operations': {'awaiting_review': 1},
                };
                break;
              default:
                data = {};
            }
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
        final state = tester.state<AppState>(find.byType(PosApp));
        final assignment = state.assignInvoice(order());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Whole invoice / all services'));
        await tester.pump();
        await tester.tap(find.byType(CheckboxListTile).at(1));
        await tester.pump();
        await tester.tap(find.text('Use selected services'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tailor B'));
        await tester.pumpAndSettle();
        await assignment;
        expect(calls.lastWhere((c) => c['action'] == 'assign')['taskIds'], [
          'work-a',
        ]);
        expect(
          calls.lastWhere((c) => c['action'] == 'assign')['tailorId'],
          'b',
        );

        tasks.first['status'] = 'Awaiting Review';
        final opened = state.jobDetail(job());
        await tester.pumpAndSettle();
        expect(find.text('Check finished work'), findsOneWidget);
        await tester.ensureVisible(find.text('Check finished work'));
        await tester.tap(find.text('Check finished work'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await opened;
        expect(
          calls.lastWhere((c) => c['action'] == 'review')['approved'],
          isTrue,
        );
        expect(calls.lastWhere((c) => c['action'] == 'review')['taskIds'], [
          'work-a',
        ]);

        final backjob = state.createBackjob(job(), tasks.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tailor B'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Previous tailor fault').last);
        await tester.pumpAndSettle();
        final formFields = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(formFields.at(0), '1');
        await tester.enterText(formFields.at(1), 'Correct the uneven hem');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await backjob;
        expect(
          calls.lastWhere((c) => c['action'] == 'backjob')['fault'],
          'tailor',
        );
        expect(calls.lastWhere((c) => c['action'] == 'backjob')['quantity'], 1);

        final refund = state.selectRefund(order(), [
          {
            'index': 0,
            'name': 'Hem- Skirt',
            'qty': 2,
            'remaining_qty': 2,
            'refunded_qty': 0,
            'net_value': 4000,
          },
          {
            'index': 1,
            'name': 'Hem- Pant',
            'qty': 1,
            'remaining_qty': 1,
            'refunded_qty': 0,
            'net_value': 2000,
          },
        ]);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await tester.pumpAndSettle();
        expect(find.text('Credit value: 2.000 KWD'), findsOneWidget);
        await tester.enterText(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(TextField),
              )
              .last,
          'Customer returned one service',
        );
        await tester.ensureVisible(find.text('Create refund sub-invoice'));
        await tester.tap(find.text('Create refund sub-invoice'));
        await tester.pumpAndSettle();
        final selected = await refund;
        expect(selected?['lines'], [
          {'index': 0, 'qty': 1},
        ]);
        expect(selected?['cashRefund'], 2000);
        expect(selected?['full'], isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
  test(
    'linked credit notes and tailor slips show their own purpose and protect work-slip privacy',
    () {
      final order = <String, dynamic>{
        'id': 'one',
        'bill': 'ZC-1-RF-1',
        'parent_bill': 'ZC-1',
        'document_type': 'refund',
        'kind': 'refund',
        'status': 'Issued',
        'total': 1889,
        'paid': 0,
        'cash_returned': 1889,
        'subtotal': 1889,
        'discount': 0,
        'extra': 0,
        'created_at': '2026-11-15T10:00:00Z',
        'customer_name': 'Customer',
        'phone': '55551234',
        'lines': [
          {
            'name': 'Hem',
            'qty': 1,
            'price': 2000,
            'amount': 1889,
            'note': '90 cm',
          },
        ],
      };
      final html = invoiceHtml(order, 'Zahra');
      expect(html, contains('Refund credit note'));
      expect(html, contains('Original invoice'));
      expect(html, contains('1.889'));
      expect(html, contains('Cash returned'));
      final slips = workSlipsHtml(order, [
        {
          'quantity': 1,
          'name': 'Hem',
          'tailor_name': 'Tailor A',
          'status': 'Pending',
          'kind': 'original',
          'note': '90 cm',
        },
      ], 'Zahra');
      expect(slips, contains('Tailor A'));
      expect(slips, contains('90 cm'));
      expect(slips, contains('80mm'));
      expect(slips, isNot(contains('55551234')));
      expect(slips, isNot(contains('1.889')));
      expect(slips, isNot(contains('2.000')));
    },
  );
}
