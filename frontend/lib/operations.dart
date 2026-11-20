part of 'app.dart';

extension ServiceOperations on AppState {
  Future<List<String>?> chooseServiceTasks(
    List<Json> tasks, {
    String title = 'Choose services',
  }) async {
    if (tasks.isEmpty) {
      notice('No services are available for this action.');
      return null;
    }
    if (tasks.length == 1) return ['${tasks.first['id']}'];
    final selected = tasks.map((t) => '${t['id']}').toSet();
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                modalHeader(title, ctx),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: const Text('Whole invoice / all services'),
                          value: selected.length == tasks.length,
                          onChanged: (value) => set(() {
                            selected.clear();
                            if (value == true) {
                              selected.addAll(tasks.map((t) => '${t['id']}'));
                            }
                          }),
                        ),
                        const Divider(),
                        ...tasks.map(
                          (task) => CheckboxListTile(
                            title: Text(
                              '${task['quantity']} × ${task['name']}',
                            ),
                            subtitle: Text(
                              '${task['tailor_name'] ?? 'Unassigned'} · ${task['status']}',
                            ),
                            value: selected.contains(task['id']),
                            onChanged: (value) => set(() {
                              if (value == true) {
                                selected.add(task['id']);
                              } else {
                                selected.remove(task['id']);
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, selected.toList()),
                    child: const Text('Use selected services'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> reviewService(Json invoice, Json task) async {
    final result = await form(
      'Reception check',
      [
        const Field(
          'decision',
          'Inspection result',
          initial: 'Approve completed work',
          options: ['Approve completed work', 'Return for correction'],
        ),
        const Field(
          'note',
          'Check notes / correction instructions',
          multiline: true,
        ),
      ],
      help:
          'Only approved services become completed. Corrections go back to the assigned tailor.',
    );
    if (result == null) return;
    final approved = result['decision'] == 'Approve completed work';
    if (!approved && (result['note'] as String).trim().length < 3) {
      notice('Explain what needs correcting.', error: true);
      return;
    }
    await run(() async {
      final fresh = Json.from(
        (await Api.get('tracking/${invoice['id']}'))['job'],
      );
      await Api.post('tracking/${invoice['id']}', {
        'action': 'review',
        'version': fresh['version'],
        'taskIds': [task['id']],
        'approved': approved,
        'note': result['note'],
      });
      await loadData();
      notice(
        approved
            ? 'Work checked and approved.'
            : 'Work returned for correction.',
      );
    });
  }

  Future<void> createBackjob(Json invoice, Json task) async {
    final tailor = await chooseTailor(invoice['branch'], '');
    if (tailor == null || tailor.isEmpty) return;
    final result = await form(
      'Create backjob',
      [
        Field(
          'quantity',
          'Quantity to correct',
          number: true,
          required: true,
          initial: '${task['quantity']}',
        ),
        const Field(
          'fault',
          'Credit rule',
          initial: 'No tailor fault',
          options: ['No tailor fault', 'Previous tailor fault'],
        ),
        const Field(
          'note',
          'Backjob reason / instructions',
          required: true,
          multiline: true,
        ),
      ],
      help:
          'Previous tailor fault: transfer the affected work credit after approval. No tailor fault: keep the previous credit and credit the fixing tailor too. Sales revenue is counted once.',
    );
    if (result == null) return;
    final quantity = int.tryParse(result['quantity']);
    if (quantity == null || quantity < 1) {
      notice('Enter a whole quantity.', error: true);
      return;
    }
    await run(() async {
      final fresh = Json.from(
        (await Api.get('tracking/${invoice['id']}'))['job'],
      );
      await Api.post('tracking/${invoice['id']}', {
        'action': 'backjob',
        'version': fresh['version'],
        'parentTaskId': task['id'],
        'quantity': quantity,
        'tailorId': tailor,
        'fault': result['fault'] == 'Previous tailor fault'
            ? 'tailor'
            : 'no_fault',
        'note': result['note'],
      });
      await loadData();
      notice('Backjob assigned. Management has been notified.');
    });
  }

  Future<void> serviceTrackingDetails(Json detail) async {
    final job = Json.from(detail['job']), tasks = AppState.maps(job['tasks']);
    await modal(
      'Work ${job['bill']}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            job['customer_name'] ?? '',
            style: const TextStyle(fontSize: 20),
          ),
          Text('${branchLabel(job['branch'])} · ${job['job_status']}'),
          if (canReviewWork)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Finished services stay awaiting review until Reception checks them.',
              ),
            ),
          ...tasks.map(
            (task) => Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${task['quantity']} × ${task['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      badge(
                        task['status'],
                        color: task['status'] == 'Completed'
                            ? green
                            : Colors.orange,
                      ),
                      if (task['kind'] == 'backjob')
                        badge('Backjob', color: Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Tailor: ${task['tailor_name'] ?? 'Unassigned'}'),
                  if ((task['note'] ?? '') != '') Text(task['note']),
                  if ((task['reason'] ?? '') != '')
                    Text('Instructions: ${task['reason']}'),
                  if ((task['approved_at'] ?? '') != '')
                    Text(
                      'Checked: ${task['approved_name'] ?? 'Legacy completion'} · ${displayDate(task['approved_at'])}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((isTailor || isManager) &&
                          task['tailor_id'] != null &&
                          ![
                            'Completed',
                            'Cancelled',
                            'Awaiting Review',
                          ].contains(task['status']))
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await updateJob(job, task: task);
                          },
                          child: const Text('Update service'),
                        ),
                      if (canReviewWork && task['status'] == 'Awaiting Review')
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await reviewService(job, task);
                          },
                          icon: const Icon(Icons.fact_check_outlined, size: 17),
                          label: const Text('Check finished work'),
                        ),
                      if ((isTailor || isManager) &&
                          task['tailor_id'] != null &&
                          task['status'] != 'Cancelled')
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await updateJob(job, task: task, noteOnly: true);
                          },
                          child: const Text('Add work note'),
                        ),
                      if (canReviewWork &&
                          task['status'] == 'Completed' &&
                          task['is_latest'] == true)
                        OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await createBackjob(job, task);
                          },
                          icon: const Icon(Icons.replay, size: 17),
                          label: const Text('Create backjob'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isTailor) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                await assignInvoice(job);
              },
              child: const Text('Assign selected services / full invoice'),
            ),
          ],
          ...AppState.maps(detail['attachments']).map(
            (file) => TextButton.icon(
              onPressed: () => browser.openExternal(
                Api.uri('documents/${file['id']}').toString(),
              ),
              icon: const Icon(Icons.attach_file, size: 16),
              label: Text(file['name']),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Work history',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          ...AppState.maps(detail['events']).map((event) {
            final data = Json.from(jsonDecode(event['detail']));
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${event['actor_name']} · ${event['action']}'),
              subtitle: Text(
                '${displayDate(event['created_at'])}\n${data['to'] ?? ''} ${data['note'] ?? ''}',
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> adjustmentAction(Json invoice, String action) async {
    final detail = Json.from(await Api.get('orders/${invoice['id']}')),
        order = Json.from(detail['order']);
    Json? values;
    if (action == 'charge') {
      values = await form(
        'Add delivery / extra charge',
        [
          const Field(
            'chargeKind',
            'Charge type',
            options: ['Delivery', 'Other extra charge'],
            initial: 'Delivery',
            required: true,
          ),
          const Field(
            'name',
            'Description',
            initial: 'Delivery fee',
            required: true,
          ),
          const Field('amount', 'Amount (KWD)', number: true, required: true),
          const Field(
            'paid',
            'Already received (KWD)',
            number: true,
            initial: '0.000',
            required: true,
          ),
          Field(
            'method',
            'Payment method',
            options: methods,
            initial: methods.first,
          ),
          const Field('note', 'Customer note', multiline: true),
        ],
        help:
            'Creates a separate numbered sub-invoice linked to this invoice. Record payments already received.',
      );
      if (values != null) {
        values['chargeKind'] = values['chargeKind'] == 'Delivery'
            ? 'delivery'
            : 'extra';
        try {
          values['amount'] = parseMoney(values['amount']);
          values['paid'] = parseMoney(values['paid']);
        } catch (e) {
          notice(e, error: true);
          return;
        }
      }
    } else if (action == 'cancel' || action == 'void') {
      values = await form(
        'Cancel invoice',
        [
          const Field(
            'reasonCode',
            'Cancellation reason',
            initial: 'Customer request',
            options: [
              'Customer request',
              'Duplicate invoice',
              'Incorrect services',
              'Unable to complete',
              'Other',
            ],
          ),
          const Field(
            'reason',
            'Reason details',
            required: true,
            multiline: true,
          ),
          Field(
            'method',
            'Return payment by',
            options: methods,
            initial: methods.first,
          ),
        ],
        help:
            'Creates a cancellation sub-invoice and keeps the original. Any remaining collected payment must be returned externally. Existing delivery sub-invoices are handled separately.',
      );
    } else {
      values = await selectRefund(
        order,
        AppState.maps(detail['refundOptions']),
      );
    }
    if (values == null) return;
    Json? document;
    await run(() async {
      final result = Json.from(
        await Api.post('orders/${order['id']}', {
          ...values!,
          'action': action,
          'id': uid(),
          'version': order['version'],
        }),
      );
      await loadData();
      notice('Linked document created. Management has been notified.');
      if (result['adjustment'] != null) {
        document = Json.from(result['adjustment']);
      }
    });
    if (document != null) await receipt(document!);
  }

  Future<Json?> selectRefund(Json order, List<Json> options) async {
    final quantities = <int, int>{
      for (final row in options) row['index'] as int: 0,
    };
    final reason = TextEditingController();
    var full = false, returnPayment = true, method = methods.first;
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final amount = full
              ? invoiceNet(order)
              : options.fold<int>(0, (sum, row) {
                  final qty = quantities[row['index']] ?? 0;
                  return sum +
                      ((row['net_value'] as num) *
                              ((row['refunded_qty'] as num) + qty) /
                              (row['qty'] as num))
                          .floor() -
                      ((row['net_value'] as num) *
                              (row['refunded_qty'] as num) /
                              (row['qty'] as num))
                          .floor();
                });
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 740),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  modalHeader('Refund services / full invoice', ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Refund whole invoice'),
                            value: full,
                            onChanged: (v) => set(() => full = v),
                          ),
                          const Text(
                            'Choose quantities from this invoice. Delivery sub-invoices are refunded separately.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          ...options
                              .where((row) => (row['remaining_qty'] as num) > 0)
                              .map(
                                (row) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(row['name']),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Available: ${row['remaining_qty']}',
                                            ),
                                          ),
                                          IconButton(
                                            onPressed:
                                                full ||
                                                    quantities[row['index']] ==
                                                        0
                                                ? null
                                                : () => set(
                                                    () => quantities[row['index']] =
                                                        quantities[row['index']]! -
                                                        1,
                                                  ),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                          Text(
                                            '${full ? row['remaining_qty'] : quantities[row['index']]}',
                                          ),
                                          IconButton(
                                            onPressed:
                                                full ||
                                                    quantities[row['index']]! >=
                                                        row['remaining_qty']
                                                ? null
                                                : () => set(
                                                    () => quantities[row['index']] =
                                                        quantities[row['index']]! +
                                                        1,
                                                  ),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          const Divider(),
                          Text(
                            'Credit value: ${money(amount)} KWD',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Return collected payment now'),
                            value: returnPayment,
                            onChanged: (v) => set(() => returnPayment = v),
                          ),
                          Text(
                            'Cash returned: ${money(returnPayment ? min(amount, (order['paid'] as num).toInt()) : 0)} KWD',
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: method,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Refund method',
                            ),
                            items: methods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => set(() => method = v!),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: reason,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Refund reason (required)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Record only refunds already returned externally. This does not send money.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: FilledButton(
                      onPressed: amount <= 0
                          ? null
                          : () {
                              if (reason.text.trim().length < 3) {
                                notice('Enter the refund reason.', error: true);
                                return;
                              }
                              Navigator.pop(ctx, {
                                'full': full,
                                'lines': [
                                  for (final row in options)
                                    if ((quantities[row['index']] ?? 0) > 0)
                                      {
                                        'index': row['index'],
                                        'qty': quantities[row['index']],
                                      },
                                ],
                                'reason': reason.text.trim(),
                                'method': method,
                                'cashRefund': returnPayment
                                    ? min(
                                        amount,
                                        (order['paid'] as num).toInt(),
                                      )
                                    : 0,
                              });
                            },
                      child: const Text('Create refund sub-invoice'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), reason.dispose);
    return result;
  }

  Future<void> showExceptions(String type) async {
    try {
      final scope = isMultiBranch ? 'all' : branch?['id'];
      final data = Json.from(
        await Api.get('exceptions?branch=$scope&from=$from&to=$to&type=$type'),
      );
      final rows = AppState.maps(data['items']);
      await modal(
        type == 'refund' ? 'Refund credit notes' : 'Cancellation notes',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty) const Text('No documents in the selected dates.'),
            ...rows.map(
              (row) => Card(
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await receipt(row);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          row['bill'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text('Original: ${row['parent_bill']}'),
                        Text(
                          '${branchLabel(row['branch'])} · ${displayDate(row['created_at'])}',
                        ),
                        Text(row['reason']),
                        const SizedBox(height: 8),
                        Text(
                          '${money(row['total'])} KWD',
                          style: const TextStyle(
                            color: green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      notice(e, error: true);
    }
  }

  Widget operationsOverview() {
    final operations = Json.from(adminSummary['operations'] ?? {}),
        credits = AppState.maps(adminSummary['tailorPerformance']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Text(
          'Work & exceptions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (ctx, box) {
            final columns = box.maxWidth > 800 ? 4 : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in [
                  (
                    'Reception checks',
                    operations['awaiting_review'] ?? 0,
                    Icons.fact_check_outlined,
                    'Awaiting Review',
                  ),
                  (
                    'Open backjobs',
                    operations['open_backjobs'] ?? 0,
                    Icons.replay,
                    'Backjobs',
                  ),
                  (
                    'Refunds',
                    operations['refunds'] ?? 0,
                    Icons.assignment_return_outlined,
                    'refund',
                  ),
                  (
                    'Cancellations',
                    operations['cancellations'] ?? 0,
                    Icons.cancel_outlined,
                    'cancellation',
                  ),
                ])
                  SizedBox(
                    width: (box.maxWidth - 12 * (columns - 1)) / columns,
                    child: InkWell(
                      onTap: ['refund', 'cancellation'].contains(card.$4)
                          ? () => showExceptions(card.$4)
                          : () => selectJobFilter(card.$4),
                      child: statCard(
                        card.$1,
                        '${card.$2}',
                        card.$3,
                        card.$4 == 'Awaiting Review' ? Colors.orange : green,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (isManager) ...[
          const SizedBox(height: 16),
          panel(
            ExpansionTile(
              initiallyExpanded: MediaQuery.sizeOf(context).width >= 800,
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Tailor work credit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Approved work credit is separate from sales revenue.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              children: [
                ...credits.map(
                  (row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['name']),
                    subtitle: Text(
                      '${row['quantity']} services · ${row['backjob_quantity']} backjob services',
                    ),
                    trailing: Text('${money(row['amount'])} KWD'),
                  ),
                ),
                if (credits.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No approved work credit in this period.'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
