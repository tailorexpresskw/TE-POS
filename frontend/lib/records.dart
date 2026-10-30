part of 'app.dart';

extension Records on AppState {
  Widget rangeButton() => OutlinedButton.icon(
    onPressed: busy ? null : chooseDates,
    icon: const Icon(Icons.calendar_today_outlined, size: 15),
    label: Text(from == to ? from : '$from — $to'),
  );
  int sum(List<Json> rows, String key) =>
      rows.fold<int>(0, (s, r) => s + ((r[key] as num?)?.toInt() ?? 0));
  Widget dashboard() {
    final cards = [
      (
        'Total Sales',
        '${money(sum(activeSales, 'total'))} KWD',
        Icons.receipt_long_outlined,
        green,
      ),
      (
        'Sales Count',
        '${activeSales.length}',
        Icons.shopping_cart_outlined,
        Colors.cyan,
      ),
      (
        'Amount Received',
        '${money(sum(payments, 'amount'))} KWD',
        Icons.payments_outlined,
        green,
      ),
      (
        'Due Amount',
        '${money(sum(activeSales, 'total') - sum(activeSales, 'paid'))} KWD',
        Icons.more_time_outlined,
        Colors.orange,
      ),
      (
        'Returns',
        '${money(sum(sales.where((o) => o['status'] == 'Refunded').toList(), 'total'))} KWD',
        Icons.assignment_return_outlined,
        Colors.redAccent,
      ),
      (
        'Deleted Sales',
        '${money(sum(sales.where((o) => o['status'] == 'Voided').toList(), 'total'))} KWD',
        Icons.delete_outline,
        muted,
      ),
    ];
    final byMethod = <String, int>{
      for (final m in methods)
        m: sum(payments.where((p) => p['method'] == m).toList(), 'amount'),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text(
                'Current POS Date',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              rangeButton(),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 1200
                  ? 6
                  : box.maxWidth >= 750
                  ? 3
                  : 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: cards
                    .map(
                      (c) => SizedBox(
                        width: (box.maxWidth - 16 * (columns - 1)) / columns,
                        child: statCard(c.$1, c.$2, c.$3, c.$4),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth > 850
                  ? (box.maxWidth - 20) / 2
                  : box.maxWidth;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: width,
                    child: chart('Sales by Invoice Type', {
                      'Default': sum(activeSales, 'total'),
                    }),
                  ),
                  SizedBox(
                    width: width,
                    child: chart('Sales by Payment Type', byMethod),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Low Stock'),
                const SizedBox(height: 25),
                const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'ITEM NAME',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CATEGORY NAME',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'STOCK',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'ALERT QTY',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 30),
                empty(
                  'Inventory will appear here after the inventory system is connected.',
                  icon: Icons.inventory_2_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget chart(String title, Map<String, int> values) {
    final peak = values.values.fold<int>(
      0,
      (s, v) => v.abs() > s ? v.abs() : s,
    );
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 5),
          const Text(
            'Current POS Date',
            style: TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values.entries
                  .map(
                    (e) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              money(e.value),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: peak == 0
                                  ? 1
                                  : (e.value.abs() / peak * 155)
                                        .clamp(1, 155)
                                        .toDouble(),
                              decoration: BoxDecoration(
                                color: mint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 28,
                              child: Text(
                                e.key,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget records({bool quotations = false}) {
    final available = quotations
        ? orders.where((o) => o['kind'] == 'quotation').toList()
        : sales;
    final filtered = available
        .where(
          (o) =>
              (saleStatus == 'All' || o['status'] == saleStatus) &&
              (payFilter == 'All' ||
                  (payFilter == 'Paid'
                      ? o['paid'] == o['total']
                      : payFilter == 'Unpaid'
                      ? o['paid'] == 0
                      : o['paid'] > 0 && o['paid'] < o['total'])) &&
              '${o['bill']} ${o['customer_name']} ${o['phone']} ${o['cashier']}'
                  .toLowerCase()
                  .contains(saleSearch.toLowerCase()),
        )
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          panel(
            Wrap(
              spacing: 65,
              runSpacing: 20,
              children: [
                summaryValue(
                  'Customers',
                  '${available.where((o) => o['customer_id'] != null).map((o) => o['customer_id']).toSet().length}',
                ),
                summaryValue(
                  quotations ? 'Quotations' : 'Bills',
                  '${available.length}',
                ),
                summaryValue('Paid', money(sum(available, 'paid'))),
                summaryValue(
                  'Unpaid',
                  money(
                    sum(
                          available
                              .where(
                                (o) => ![
                                  'Voided',
                                  'Refunded',
                                ].contains(o['status']),
                              )
                              .toList(),
                          'total',
                        ) -
                        sum(available, 'paid'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    badge(quotations ? 'Sales Quotations' : 'All'),
                    rangeButton(),
                    OutlinedButton.icon(
                      onPressed: () => run(loadData),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        update(() {
                          screen = 2;
                          invoiceKind = quotations ? 'quotation' : 'sale';
                        });
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(quotations ? 'New quotation' : 'New sale'),
                    ),
                  ],
                ),
                if (!quotations) ...[
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, box) {
                      final statuses = [
                        'All',
                        ...List<String>.from(boot?['statuses'] ?? []),
                      ];
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: statuses
                            .map(
                              (s) => SizedBox(
                                width: box.maxWidth >= 1000
                                    ? (box.maxWidth - 60) / 7
                                    : 130,
                                height: 74,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: saleStatus == s
                                        ? const Color(0xfff2faf5)
                                        : Colors.white,
                                    side: BorderSide(
                                      color: saleStatus == s ? mint : line,
                                    ),
                                  ),
                                  onPressed: () => update(() => saleStatus = s),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        statusIcon(s),
                                        size: 22,
                                        color: saleStatus == s ? green : muted,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        s,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search sales',
                          prefixIcon: Icon(Icons.search, size: 17),
                        ),
                        onChanged: (v) => update(() => saleSearch = v),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: payFilter,
                        decoration: const InputDecoration(
                          labelText: 'Payment status',
                        ),
                        items: ['All', 'Paid', 'Unpaid', 'Partial']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => payFilter = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (filtered.isEmpty)
                  empty(
                    quotations
                        ? 'No quotations found'
                        : 'No sales found for these filters',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 65,
                      columnSpacing: 32,
                      columns: const [
                        DataColumn(label: Text('BILL NO')),
                        DataColumn(label: Text('CUSTOMER')),
                        DataColumn(label: Text('STAFF')),
                        DataColumn(label: Text('CASHIER')),
                        DataColumn(label: Text('AGGREGATOR')),
                        DataColumn(label: Text('TOTAL'), numeric: true),
                        DataColumn(label: Text('PAYMENT STATUS')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: filtered
                          .map(
                            (o) => DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o['bill'],
                                        style: const TextStyle(
                                          color: green,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        displayDate(o['created_at']),
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => run(() => receipt(o)),
                                ),
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(o['customer_name']),
                                      Text(
                                        o['phone'],
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    employees
                                            .where((s) => s['id'] == o['staff'])
                                            .firstOrNull?['name'] ??
                                        '—',
                                  ),
                                ),
                                DataCell(Text(o['cashier'])),
                                DataCell(
                                  Text(
                                    o['aggregator'].toString().isEmpty
                                        ? '—'
                                        : o['aggregator'],
                                  ),
                                ),
                                DataCell(Text(money(o['total']))),
                                DataCell(
                                  badge(
                                    o['paid'] == o['total']
                                        ? 'Paid'
                                        : o['paid'] == 0
                                        ? 'Unpaid'
                                        : 'Partial',
                                    color: o['paid'] == o['total']
                                        ? green
                                        : Colors.orange,
                                  ),
                                ),
                                DataCell(
                                  badge(
                                    o['status'],
                                    color:
                                        [
                                          'Voided',
                                          'Refunded',
                                        ].contains(o['status'])
                                        ? Colors.redAccent
                                        : Colors.cyan,
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'View sale',
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 18,
                                          color: muted,
                                        ),
                                        onPressed: () => run(() => receipt(o)),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (action) =>
                                            saleAction(o, action),
                                        itemBuilder: (_) => [
                                          if (quotations)
                                            const PopupMenuItem(
                                              value: 'resume',
                                              child: Text('Convert to sale'),
                                            ),
                                          if (!quotations &&
                                              o['paid'] < o['total'] &&
                                              ![
                                                'Voided',
                                                'Refunded',
                                              ].contains(o['status']))
                                            const PopupMenuItem(
                                              value: 'payment',
                                              child: Text('Receive payment'),
                                            ),
                                          if (!quotations)
                                            const PopupMenuItem(
                                              value: 'staff',
                                              child: Text('Change staff'),
                                            ),
                                          if (!quotations)
                                            const PopupMenuItem(
                                              value: 'status',
                                              child: Text('Change status'),
                                            ),
                                          if (isManager && !quotations)
                                            const PopupMenuItem(
                                              value: 'method',
                                              child: Text(
                                                'Change payment method',
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'clone',
                                            child: Text('Clone bill'),
                                          ),
                                          if (isManager &&
                                              !quotations &&
                                              ![
                                                'Voided',
                                                'Refunded',
                                              ].contains(o['status']))
                                            PopupMenuItem(
                                              value: o['paid'] > 0
                                                  ? 'refund'
                                                  : 'void',
                                              child: Text(
                                                o['paid'] > 0
                                                    ? 'Refund sale'
                                                    : 'Delete sale',
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'print',
                                            child: Text('Re-print bill'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Showing ${filtered.length} entries · up to 1,000 orders per date range',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget summaryValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontSize: 22)),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
  IconData statusIcon(String status) => switch (status) {
    'Ongoing' => Icons.checkroom_outlined,
    'Prepared' => Icons.schedule,
    'Packed' => Icons.inventory_2_outlined,
    'Out for Delivery' => Icons.local_shipping_outlined,
    'Delivered' => Icons.check_circle_outline,
    'Closed' => Icons.lock_outline,
    _ => Icons.format_list_bulleted,
  };
  Future<void> saleAction(Json original, String action) async {
    if (action == 'resume') {
      await restore(original);
      return;
    }
    if (action == 'clone') {
      if (cart.isNotEmpty &&
          !await confirm('Replace cart?', 'Copy this sale into a new cart?')) {
        return;
      }
      update(() {
        clearCart();
        cart = AppState.maps(original['lines']);
        customer = original['customer_id'] != null
            ? {'id': original['customer_id'], 'name': original['customer_name']}
            : null;
        screen = 2;
        invoiceKind = 'sale';
      });
      return;
    }
    if (action == 'print') {
      await run(() => receipt(original));
      return;
    }
    final o = Json.from((await Api.get('orders/${original['id']}'))['order']);
    Json? values;
    if (action == 'payment') {
      values = await form('Receive payment', [
        Field(
          'amount',
          'Amount (KWD)',
          initial: money(o['total'] - o['paid']),
          number: true,
          required: true,
        ),
        Field(
          'method',
          'Payment method',
          options: methods,
          initial: methods.first,
        ),
        const Field('reference', 'Reference (optional)'),
      ], help: 'Record only payments already received.');
      if (values != null) {
        try {
          values['amount'] = parseMoney(values['amount']);
          values['id'] = uid();
        } catch (e) {
          notice(e, error: true);
          return;
        }
      }
    } else if (action == 'status') {
      values = await form('Order status', [
        Field(
          'status',
          'Status',
          options: List<String>.from(boot!['statuses']),
          initial: o['status'],
        ),
      ]);
    } else if (action == 'staff') {
      final result = await form('Change staff', [
        Field(
          'staff',
          'Employee',
          options: employees.map((s) => s['name'] as String).toList(),
          initial: employees.firstOrNull?['name'] ?? '',
        ),
      ]);
      if (result != null) {
        values = {
          'staff': employees.firstWhere(
            (s) => s['name'] == result['staff'],
          )['id'],
        };
      }
    } else if (action == 'method') {
      final detail = Json.from(await Api.get('orders/${o['id']}'));
      final ps = AppState.maps(detail['payments']);
      if (ps.isEmpty) {
        notice('No payments to change.');
        return;
      }
      final result = await form('Change payment method', [
        Field(
          'payment',
          'Payment',
          options: ps.map((p) => '${p['id']} · ${money(p['amount'])}').toList(),
          initial: '${ps.first['id']} · ${money(ps.first['amount'])}',
        ),
        Field('method', 'Method', options: methods, initial: methods.first),
      ]);
      if (result != null) {
        values = {
          'paymentId': (result['payment'] as String).split(' · ').first,
          'method': result['method'],
        };
      }
    } else if (action == 'void' || action == 'refund') {
      values = await form(
        action == 'refund' ? 'Refund sale' : 'Delete sale',
        [
          const Field('reason', 'Reason', required: true, multiline: true),
          if (action == 'refund')
            Field(
              'method',
              'Refund method',
              options: methods,
              initial: methods.first,
            ),
        ],
        help: action == 'refund'
            ? 'Confirm the refund was issued externally. The original sale and payment history will be kept.'
            : 'The sale will be marked void and kept in the audit trail.',
      );
    }
    if (values != null) {
      await run(() async {
        await Api.post('orders/${o['id']}', {
          ...values!,
          'action': action,
          'version': o['version'],
        });
        await loadData();
        notice('Sale updated.');
      });
    }
  }

  Future<void> receipt(Json sale) async {
    final detail = Json.from(await Api.get('orders/${sale['id']}'));
    final o = Json.from(detail['order']);
    final ps = AppState.maps(detail['payments']);
    final files = AppState.maps(detail['attachments']);
    final lines = AppState.maps(o['lines']);
    final branchTitle =
        branches.where((b) => b['id'] == o['branch']).firstOrNull?['name'] ??
        o['branch'];
    final html =
        '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(o['bill'])}</title><style>body{font:13px Arial,sans-serif;color:#252738;max-width:76mm;margin:20px auto}h1{font-size:20px;text-align:center}h2{font-size:15px}p{margin:7px 0}table{width:100%;border-collapse:collapse}td,th{padding:8px 2px;border-bottom:1px solid #ddd;text-align:left;font-size:11px}.right{text-align:right}.small{font-size:11px;color:#666}button{padding:12px;width:100%}@media print{button{display:none}body{margin:0} @page{margin:5mm}}</style></head><body><h1>TAILOR EXPRESS</h1><p style="text-align:center">${escape(branchTitle)}</p><h2>${o['kind'] == 'quotation' ? 'Quotation' : 'Sales receipt'}</h2><p>${escape(o['bill'])}</p><p class="small">${escape(displayDate(o['created_at']))} · ${escape(o['cashier'])}</p><p>${escape(o['customer_name'])} ${escape(o['phone'])}</p><p class="small">${escape(o['address'])}</p><table><tr><th>Item</th><th>Qty</th><th class="right">KWD</th></tr>${lines.map((l) => '<tr><td>${escape(l['name'])}<br><span class="small">${escape(l['note'])}</span></td><td>${l['qty']}</td><td class="right">${money(l['price'] * l['qty'])}</td></tr>').join()}</table><p>Subtotal <span style="float:right">${money(o['subtotal'])}</span></p><p>Discount <span style="float:right">${money(o['discount'])}</span></p><p>Extra <span style="float:right">${money(o['extra'])}</span></p><p><b>Total KWD <span style="float:right">${money(o['total'])}</span></b></p><p>Paid <span style="float:right">${money(o['paid'])}</span></p><p>Balance due <span style="float:right">${['Voided', 'Refunded'].contains(o['status']) ? '0.000' : money(o['total'] - o['paid'])}</span></p>${ps.map((p) => '<p class="small">${escape(p['method'])}: ${money(p['amount'])} ${escape(p['reference'])}</p>').join()}<p>${escape(o['notes']).replaceAll('\n', '<br>')}</p>${o['due_date'].toString().isEmpty ? '' : '<p>Collection: ${escape(o['due_date'])}</p>'}<p>Status: ${escape(o['status'])}</p><p style="text-align:center">Thank you · شكراً لكم</p><button onclick="window.print()">Print receipt</button></body></html>''';
    await modal(
      o['bill'],
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TAILOR EXPRESS',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(branchTitle),
          const SizedBox(height: 15),
          Text('${o['customer_name']} · ${o['phone']}'),
          Text(
            displayDate(o['created_at']),
            style: const TextStyle(color: muted),
          ),
          const Divider(height: 30),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l['name']}\n${l['note']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text('${l['qty']} × ${money(l['price'])}'),
                  const SizedBox(width: 20),
                  Text(money(l['qty'] * l['price'])),
                ],
              ),
            ),
          ),
          const Divider(height: 25),
          Text(
            'Discount: ${money(o['discount'])}  ·  Extra: ${money(o['extra'])}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          moneyText(o['total'], size: 25),
          Text('Paid: ${money(o['paid'])} · Status: ${o['status']}'),
          ...ps.map(
            (p) => Text(
              '${p['method']}: ${money(p['amount'])} · ${p['reference']}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 15),
          Text(o['notes']),
          if (o['due_date'] != '') Text('Collection: ${o['due_date']}'),
          ...files.map(
            (f) => TextButton.icon(
              onPressed: () =>
                  browser.navigate(Api.uri('documents/${f['id']}').toString()),
              icon: const Icon(Icons.attach_file, size: 16),
              label: Text(f['name']),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => browser.printHtml(html),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print receipt'),
          ),
        ],
      ),
      width: 650,
    );
  }

  Widget expensesScreen() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 15,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Petty Expenses', style: TextStyle(fontSize: 21)),
              rangeButton(),
              moneyText(sum(expenses, 'amount')),
              FilledButton.icon(
                onPressed: newExpense,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add expense'),
              ),
            ],
          ),
          const SizedBox(height: 25),
          if (expenses.isEmpty)
            empty('No expenses recorded')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('DATE')),
                  DataColumn(label: Text('CATEGORY')),
                  DataColumn(label: Text('DESCRIPTION')),
                  DataColumn(label: Text('METHOD')),
                  DataColumn(label: Text('AMOUNT'), numeric: true),
                ],
                rows: expenses
                    .map(
                      (e) => DataRow(
                        cells: [
                          DataCell(Text(displayDate(e['created_at']))),
                          DataCell(Text(e['category'])),
                          DataCell(
                            SizedBox(width: 250, child: Text(e['description'])),
                          ),
                          DataCell(Text(e['method'])),
                          DataCell(Text('${money(e['amount'])} KWD')),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    ),
  );
  Future<void> newExpense() async {
    final result = await form('Petty expense', [
      const Field(
        'category',
        'Category',
        options: ['Supplies', 'Transport', 'Maintenance', 'Utilities', 'Other'],
        initial: 'Supplies',
      ),
      const Field(
        'description',
        'Description',
        required: true,
        multiline: true,
      ),
      const Field('amount', 'Amount (KWD)', number: true, required: true),
      Field('method', 'Payment method', options: methods, initial: 'Cash'),
    ]);
    if (result != null) {
      await run(() async {
        await Api.post('expenses', {
          ...result,
          'id': uid(),
          'branch': branch!['id'],
          'amount': parseMoney(result['amount']),
        });
        await loadData();
        notice('Expense recorded.');
      });
    }
  }

  Widget reports() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Branch Reports', style: TextStyle(fontSize: 22)),
                  Text(branchName),
                  rangeButton(),
                  OutlinedButton.icon(
                    onPressed: exportSales,
                    icon: const Icon(Icons.download_outlined, size: 17),
                    label: const Text('Export sales CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: exportPayments,
                    icon: const Icon(Icons.download_outlined, size: 17),
                    label: const Text('Export payments CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Wrap(
                spacing: 45,
                runSpacing: 25,
                children: [
                  summaryValue('Net sales', money(sum(activeSales, 'total'))),
                  summaryValue(
                    'Received (less refunds)',
                    money(sum(payments, 'amount')),
                  ),
                  summaryValue('Expenses', money(sum(expenses, 'amount'))),
                  summaryValue(
                    'Receipts less expenses',
                    money(sum(payments, 'amount') - sum(expenses, 'amount')),
                  ),
                  summaryValue(
                    'Discounts',
                    money(sum(activeSales, 'discount')),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                'Sales use the order date. Receipts and refunds use the payment date. Amounts are in KWD.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        chart('Payments by Method', {
          for (final m in methods)
            m: sum(payments.where((p) => p['method'] == m).toList(), 'amount'),
        }),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sales by category'),
              const SizedBox(height: 15),
              ...catalogue
                  .map((p) => p['category'] as String)
                  .toSet()
                  .where(
                    (c) => activeSales.any(
                      (s) => AppState.maps(
                        s['lines'],
                      ).any((l) => l['category'] == c),
                    ),
                  )
                  .map((c) {
                    final amount = activeSales.fold<int>(
                      0,
                      (s, o) =>
                          s +
                          AppState.maps(o['lines'])
                              .where((l) => l['category'] == c)
                              .fold<int>(
                                0,
                                (v, l) =>
                                    v + (l['price'] as int) * (l['qty'] as int),
                              ),
                    );
                    return ListTile(
                      title: Text(c),
                      trailing: Text('${money(amount)} KWD'),
                    );
                  }),
              const Text(
                'Category amounts are before order-level discounts and extra charges.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  String csvCell(dynamic value) {
    var text = '$value';
    if (value is! num && RegExp(r'^[=+@\-\t\r]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  void exportRows(String filename, List<List<dynamic>> rows) =>
      browser.download(
        filename,
        '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}',
      );
  void exportSales() => exportRows('tailor-express-$from-$to-sales.csv', [
    [
      'Bill',
      'Date (Kuwait)',
      'Branch',
      'Customer',
      'Phone',
      'Subtotal KWD',
      'Discount KWD',
      'Extra KWD',
      'Total KWD',
      'Paid KWD',
      'Status',
      'Cashier',
    ],
    ...sales.map(
      (o) => [
        o['bill'],
        displayDate(o['created_at']),
        branchName,
        o['customer_name'],
        o['phone'],
        money(o['subtotal']),
        money(o['discount']),
        money(o['extra']),
        money(o['total']),
        money(o['paid']),
        o['status'],
        o['cashier'],
      ],
    ),
  ]);
  void exportPayments() => exportRows('tailor-express-$from-$to-payments.csv', [
    [
      'Payment ID',
      'Order ID',
      'Date (Kuwait)',
      'Branch',
      'Amount KWD',
      'Method',
      'Reference',
    ],
    ...payments.map(
      (p) => [
        p['id'],
        p['order_id'],
        displayDate(p['created_at']),
        branchName,
        money(p['amount']),
        p['method'],
        p['reference'],
      ],
    ),
  ]);
}
