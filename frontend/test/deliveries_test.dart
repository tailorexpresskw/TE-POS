import 'dart:async';
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
      'invoice delivery, reception readiness and driver updates at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Json? delivery;
        var approved = false;
        final writes = <Json>[];
        Json order() => {
          'id': 'invoice-test',
          'branch': 'zahra',
          'bill': 'ZC-TEST',
          'kind': 'sale',
          'document_type': 'invoice',
          'version': 0,
          'job_status': approved ? 'Completed' : 'Pending',
          'customer_name': 'Test Customer',
          'phone': '55551234',
          'address': 'Test block and street',
          'due_date': '',
          'status': 'Ongoing',
        };
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
                  'role': 'reception',
                  'name': 'Reception',
                  'branches': ['zahra'],
                },
                'branches': [
                  {'id': 'zahra', 'name': 'Zahra Complex'},
                ],
                'catalogue': [],
                'methods': ['Cash'],
                'staff': [],
                'coupons': [],
              };
              break;
            case '/api/orders/invoice-test':
              data = {
                'order': order(),
                'related': [
                  {
                    'id': 'charge-test',
                    'bill': 'ZC-TEST-ADD',
                    'document_type': 'charge',
                    'charge_kind': 'delivery',
                    'total': 2000,
                    'paid': 0,
                    'refunded_total': 0,
                    'status': 'Ongoing',
                  },
                ],
                'tasks': [
                  {'status': approved ? 'Completed' : 'Pending'},
                ],
              };
              break;
            case '/api/orders/invoice-test/delivery-options':
              data = {
                'canMarkReady': approved,
                'deliveryInvoices': [
                  {
                    'id': 'charge-test',
                    'bill': 'ZC-TEST-ADD',
                    'total': 2000,
                    'refunded_total': 0,
                  },
                ],
                'areas': [
                  {'name': 'Test Area', 'chargeFils': 2000},
                ],
              };
              break;
            case '/api/orders/invoice-test/delivery':
              if (request.method == 'POST') {
                final body = Json.from(jsonDecode(request.body));
                writes.add(body);
                if (body['action'] == 'create') {
                  delivery = {
                    'id': 'request',
                    'revision': 0,
                    'remote_status': '',
                    'desired_status': 'draft',
                    'sync_state': 'draft',
                    'approved_at': '',
                    'approved_by': null,
                    'delivery_invoice_id': 'charge-test',
                    'remote_id': '',
                    'driver_name': '',
                    'eta_label': '',
                    'delivered_at': '',
                    'last_error': '',
                    'payload': {
                      ...body,
                      'chargeFils': 2000,
                      'invoiceNo': 'ZC-TEST-ADD',
                      'customerChargeFils': 2000,
                    },
                  };
                } else if (body['action'] == 'send') {
                  delivery = {
                    ...delivery!,
                    'revision': 1,
                    'approved_at': '2026-11-19T10:00:00Z',
                    'approved_by': 'reception',
                    'desired_status': 'ready',
                    'sync_state': 'pending',
                  };
                }
                data = delivery;
              } else {
                data = {'delivery': delivery, 'configured': true};
              }
              break;
            default:
              data = {
                'orders': [],
                'payments': [],
                'expenses': [],
                'jobs': [],
                'totals': {},
                'summary': {},
                'items': [],
              };
          }
          return http.Response(jsonEncode(data), 200);
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zahra Complex').last);
        await tester.pumpAndSettle();
        final state = tester.state<AppState>(find.byType(PosApp));
        unawaited(state.customerDelivery(order()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enter delivery address and phone'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'Customer phone'),
          findsOneWidget,
        );
        await tester.tap(find.text('Save delivery draft'));
        await tester.pumpAndSettle();
        expect(writes.single['action'], 'create');
        expect(writes.single.containsKey('fromBranchId'), false);
        expect(writes.single['customerPhone'], '55551234');
        expect(writes.single['address'], 'Test block and street');
        expect(find.text('Dispatch quote: 2.000 KWD'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find
                    .ancestor(
                      of: find.text('Send delivery request'),
                      matching: find.byWidgetPredicate(
                        (widget) => widget is FilledButton,
                      ),
                    )
                    .first,
              )
              .onPressed,
          isNull,
        );
        approved = true;
        await tester.tap(find.text('Refresh delivery'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Send delivery request'));
        await tester.tap(find.text('Send delivery request'));
        await tester.pumpAndSettle();
        expect(writes.last['action'], 'send');
        expect(writes.last['revision'], 0);
        delivery = {
          ...delivery!,
          'remote_status': 'in_transit',
          'remote_id': 'DEL-TEST',
          'sync_state': 'synced',
          'driver_name': 'Test Driver',
          'eta_label': '30 minutes',
        };
        await tester.tap(find.text('Refresh delivery'));
        await tester.pumpAndSettle();
        expect(find.text('Driver: Test Driver'), findsOneWidget);
        expect(find.text('ETA: 30 minutes'), findsOneWidget);
        expect(find.text('Cancel delivery request'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'Admin explicitly maps invoice branches without exposing integration keys at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Json? saved;
        Api.client = MockClient((request) async {
          dynamic data;
          switch (request.url.path) {
            case '/api/auth/status':
              data = {'authenticated': true};
              break;
            case '/api/boot':
              data = {
                'member': {
                  'id': 'admin',
                  'role': 'admin',
                  'name': 'Admin',
                  'branches': [],
                },
                'branches': [
                  {'id': 'zahra', 'name': 'Zahra Complex'},
                ],
                'catalogue': [],
                'methods': ['Cash'],
                'staff': [],
                'coupons': [],
              };
              break;
            case '/api/inventory-connection':
              if (request.method == 'POST') {
                saved = Json.from(jsonDecode(request.body));
                data = {'ok': true};
              } else {
                data = {
                  'configured': true,
                  'connected': true,
                  'branches': [
                    {'id': 'B008', 'name': 'Inventory Zahra'},
                  ],
                  'mappings': [
                    {'branch': 'zahra', 'inventory_branch_id': 'B008'},
                  ],
                  'error': '',
                };
              }
              break;
            default:
              data = {
                'orders': [],
                'payments': [],
                'expenses': [],
                'jobs': [],
                'totals': {},
                'summary': {},
                'items': [],
              };
          }
          return http.Response(jsonEncode(data), 200);
        });
        await tester.pumpWidget(const PosRoot());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zahra Complex').last);
        await tester.pumpAndSettle();
        final state = tester.state<AppState>(find.byType(PosApp));
        unawaited(state.inventoryConnection());
        await tester.pumpAndSettle();
        expect(find.text('Connected to inventory'), findsOneWidget);
        await tester.tap(find.text('Save branch mappings'));
        await tester.pumpAndSettle();
        expect(saved?['mappings'], [
          {'branch': 'zahra', 'inventoryBranchId': 'B008'},
        ]);
        expect(saved!.containsKey('key'), false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
