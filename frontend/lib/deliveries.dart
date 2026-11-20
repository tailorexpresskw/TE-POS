part of 'app.dart';

extension InventoryDeliveries on AppState {
  Future<void> inventoryConnection() async {
    try {
      final data = Json.from(await Api.get('inventory-connection'));
      if (!mounted || !authenticated) return;
      final remote = AppState.maps(data['branches']);
      final selected = <String, String>{
        for (final m in AppState.maps(data['mappings']))
          m['branch']: m['inventory_branch_id'],
      };
      var saving = false;
      String? error;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  modalHeader('Inventory delivery connection', ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            data['connected'] == true
                                ? 'Connected to inventory'
                                : 'Connection needs setup',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Match each POS branch to its branch in inventory. Delivery requests always use the invoice branch. One inventory branch can be mapped only once.',
                          ),
                          if (data['error'] != '' && data['error'] != null)
                            Text(
                              data['error'],
                              style: const TextStyle(color: Colors.red),
                            ),
                          if (data['configured'] != true)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Configure INVENTORY_URL and INVENTORY_INTEGRATION_KEY on the POS server, and the matching POS_INTEGRATION_KEY on the inventory server. The key stays on the servers.',
                              ),
                            ),
                          if (data['connected'] == true)
                            ...branches.map(
                              (branch) => Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: DropdownButtonFormField<String>(
                                  initialValue:
                                      remote.any(
                                        (b) =>
                                            b['id'] == selected[branch['id']],
                                      )
                                      ? selected[branch['id']]
                                      : '',
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: branch['name'],
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('Not linked'),
                                    ),
                                    ...remote.map(
                                      (b) => DropdownMenuItem(
                                        value: b['id'] as String,
                                        child: Text(b['name']),
                                      ),
                                    ),
                                  ],
                                  onChanged: saving
                                      ? null
                                      : (value) => set(
                                          () => selected[branch['id']] =
                                              value ?? '',
                                        ),
                                ),
                              ),
                            ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        TextButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                        FilledButton(
                          onPressed: saving || data['connected'] != true
                              ? null
                              : () async {
                                  set(() {
                                    saving = true;
                                    error = null;
                                  });
                                  try {
                                    await Api.post('inventory-connection', {
                                      'mappings': [
                                        for (final entry in selected.entries)
                                          if (entry.value.isNotEmpty)
                                            {
                                              'branch': entry.key,
                                              'inventoryBranchId': entry.value,
                                            },
                                      ],
                                    });
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    notice('Inventory branch mappings saved.');
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      set(() {
                                        saving = false;
                                        error = e.toString();
                                      });
                                    }
                                  }
                                },
                          child: Text(
                            saving ? 'Saving…' : 'Save branch mappings',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!handleShiftError(e) &&
          !(e is ApiException && e.code == 'STALE_SESSION')) {
        notice(e, error: true);
      }
    }
  }

  Future<void> customerDelivery(Json initial, {bool openEditor = false}) async {
    Timer? poll;
    var refreshing = false;
    try {
      var detail = Json.from(await Api.get('orders/${initial['id']}'));
      final source = Json.from(detail['order']);
      final childId = source['document_type'] == 'charge' ? source['id'] : null;
      if (childId != null) {
        detail = Json.from(
          await Api.get('orders/${source['parent_order_id']}'),
        );
      }
      var order = Json.from(detail['order']);
      if (childId != null) order['selectedDeliveryInvoiceId'] = childId;
      var data = Json.from(await Api.get('orders/${order['id']}/delivery'));
      if (!mounted || !authenticated) return;
      if (openEditor &&
          data['configured'] == true &&
          data['delivery'] == null) {
        await editDelivery(order);
        if (!mounted || !authenticated) return;
        data = Json.from(await Api.get('orders/${order['id']}/delivery'));
      }
      if (!mounted || !authenticated) return;
      var saving = false;
      String? error;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) {
            Future<void> refresh() async {
              if (refreshing || saving || !ctx.mounted || !authenticated) {
                return;
              }
              refreshing = true;
              try {
                final next = Json.from(
                  await Api.get('orders/${order['id']}/delivery'),
                );
                final fresh = Json.from(await Api.get('orders/${order['id']}'));
                if (ctx.mounted) {
                  set(() {
                    data = next;
                    detail = fresh;
                    order = {
                      ...Json.from(fresh['order']),
                      'selectedDeliveryInvoiceId': ?childId,
                    };
                    error = null;
                  });
                }
              } catch (e) {
                if (ctx.mounted &&
                    !(e is ApiException && e.code == 'STALE_SESSION')) {
                  set(() => error = e.toString());
                }
              } finally {
                refreshing = false;
              }
            }

            poll ??= Timer.periodic(
              const Duration(seconds: 10),
              (_) => refresh(),
            );
            deliveryPollTimer = poll;
            final delivery = data['delivery'] is Map
                ? Json.from(data['delivery'])
                : null;
            final payload = delivery?['payload'] is Map
                ? Json.from(delivery!['payload'])
                : <String, dynamic>{};
            final remote = delivery?['remote_status'] ?? '',
                desired = delivery?['desired_status'] ?? '';
            final terminal =
                ['in_transit', 'delivered', 'cancelled'].contains(remote) ||
                desired == 'cancelled';
            final eligible = ![
              'Voided',
              'Refunded',
              'Closed',
              'Delivered',
            ].contains(order['status']);
            final tasks = AppState.maps(detail['tasks']);
            final checked =
                eligible &&
                order['job_status'] == 'Completed' &&
                tasks.any((t) => t['status'] == 'Completed') &&
                tasks.every(
                  (t) => ['Completed', 'Cancelled'].contains(t['status']),
                );
            final draft =
                delivery != null && (delivery['approved_at'] ?? '') == '';
            final charges = AppState.maps(detail['related'])
                .where(
                  (d) =>
                      d['document_type'] == 'charge' &&
                      d['charge_kind'] == 'delivery' &&
                      !['Voided', 'Refunded'].contains(d['status']),
                )
                .toList();
            Future<void> action(String action) async {
              if (saving || delivery == null) return;
              if (action == 'cancel' &&
                  !await confirm(
                    'Cancel delivery request?',
                    'This cancels dispatch only. It does not refund or cancel either invoice.',
                  )) {
                return;
              }
              if (!ctx.mounted) return;
              set(() {
                saving = true;
                error = null;
              });
              try {
                await Api.post('orders/${order['id']}/delivery', {
                  'action': action,
                  'revision': delivery['revision'],
                });
                saving = false;
                await refresh();
                notice(
                  action == 'send'
                      ? 'Approved. Sending automatically to inventory as Ready.'
                      : 'Delivery update saved.',
                );
              } catch (e) {
                if (ctx.mounted) set(() => error = e.toString());
              } finally {
                if (ctx.mounted) set(() => saving = false);
              }
            }

            Future<void> edit() async {
              set(() => saving = true);
              try {
                if (await editDelivery(order, existing: delivery)) {
                  saving = false;
                  await refresh();
                }
              } catch (e) {
                if (ctx.mounted) set(() => error = e.toString());
              } finally {
                if (ctx.mounted) set(() => saving = false);
              }
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 700,
                  maxHeight: 800,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    modalHeader('Customer home delivery', ctx),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              order['bill'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              'From ${branchLabel(order['branch'])} → customer address',
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 15),
                            if (data['configured'] != true)
                              const Text(
                                'Admin must configure the inventory delivery connection before sending requests.',
                              ),
                            if (delivery == null) ...[
                              const Text(
                                'Create a delivery sub-invoice, enter the address and phone, then let Reception approve and send the request. Nothing is created in inventory before approval.',
                              ),
                              const SizedBox(height: 12),
                              if (charges.isEmpty)
                                FilledButton.icon(
                                  onPressed: saving || !eligible
                                      ? null
                                      : () async {
                                          Navigator.pop(ctx);
                                          await adjustmentAction(
                                            order,
                                            'charge',
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Create delivery sub-invoice',
                                  ),
                                )
                              else
                                FilledButton.icon(
                                  onPressed:
                                      saving ||
                                          !eligible ||
                                          data['configured'] != true
                                      ? null
                                      : edit,
                                  icon: const Icon(
                                    Icons.edit_location_alt_outlined,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Enter delivery address and phone',
                                  ),
                                ),
                            ] else ...[
                              Text(
                                terminal
                                    ? 'Dispatch: ${remote.toString().replaceAll('_', ' ')}'
                                    : draft
                                    ? 'Awaiting reception approval'
                                    : remote == 'ready'
                                    ? 'Ready in inventory'
                                    : 'Sending approved delivery',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (draft && delivery['remote_id'] == '')
                                const Text(
                                  'Saved only in POS. Not created in inventory.',
                                ),
                              if (!draft)
                                Text('Sync: ${delivery['sync_state']}'),
                              if (delivery['remote_id'] != '')
                                Text(
                                  'Inventory request: ${delivery['remote_id']}',
                                ),
                              if (delivery['last_error'] != '')
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    delivery['last_error'],
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              const Divider(height: 26),
                              Text(
                                'Delivery sub-invoice: ${payload['invoiceNo']}',
                              ),
                              Text(
                                '${payload['customerName']} · ${payload['customerPhone']}',
                              ),
                              Text(
                                '${payload['areaName']}\n${payload['address']}',
                              ),
                              if (payload['dueDate'] != '')
                                Text('Delivery date: ${payload['dueDate']}'),
                              if (payload['readyTimeAt'] != '')
                                Text(
                                  'Scheduled time: ${displayDate(payload['readyTimeAt'])} (Kuwait)',
                                ),
                              Text(
                                'Dispatch quote: ${money(payload['chargeFils'] ?? 0)} KWD',
                              ),
                              if (payload['customerChargeFils'] != null)
                                Text(
                                  'Delivery invoice amount: ${money(payload['customerChargeFils'])} KWD',
                                ),
                              if (delivery['driver_name'] != '')
                                Text('Driver: ${delivery['driver_name']}'),
                              if (delivery['eta_label'] != '')
                                Text('ETA: ${delivery['eta_label']}'),
                              if (delivery['delivered_at'] != '')
                                Text(
                                  'Delivered: ${displayDate(delivery['delivered_at'])}',
                                ),
                              if (draft && !terminal) ...[
                                const SizedBox(height: 14),
                                Text(
                                  checked
                                      ? 'Work has been checked. Reception can approve and send delivery now.'
                                      : 'Reception must check the finished work before sending delivery.',
                                ),
                                if (!canReviewWork)
                                  const Text(
                                    'Only Reception or Admin can approve and send this draft.',
                                  ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed:
                                      saving ||
                                          !checked ||
                                          !canReviewWork ||
                                          delivery['delivery_invoice_id'] ==
                                              null
                                      ? null
                                      : () => action('send'),
                                  icon: const Icon(
                                    Icons.send_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Send delivery request'),
                                ),
                                if (delivery['remote_id'] == '')
                                  OutlinedButton(
                                    onPressed: saving || !eligible
                                        ? null
                                        : edit,
                                    child: const Text(
                                      'Edit delivery address and phone',
                                    ),
                                  ),
                              ],
                              if (!terminal)
                                TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => action('cancel'),
                                  child: const Text('Cancel delivery request'),
                                ),
                              if (!draft &&
                                  [
                                    'retry',
                                    'attention',
                                  ].contains(delivery['sync_state']))
                                TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => action('retry'),
                                  child: const Text('Retry synchronization'),
                                ),
                              if (delivery['delivery_invoice_id'] != null)
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await receipt({
                                      'id': delivery['delivery_invoice_id'],
                                    });
                                  },
                                  child: const Text(
                                    'View delivery sub-invoice',
                                  ),
                                ),
                            ],
                            const SizedBox(height: 15),
                            const Text(
                              'Send delivery request is Reception’s approval. It creates a Ready request in inventory for dispatch and does not add another charge or collect payment.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 10,
                        children: [
                          TextButton(
                            onPressed: saving ? null : refresh,
                            child: const Text('Refresh delivery'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (!handleShiftError(e) &&
          !(e is ApiException && e.code == 'STALE_SESSION')) {
        notice(e, error: true);
      }
    } finally {
      poll?.cancel();
    }
  }

  Future<bool> editDelivery(Json order, {Json? existing}) async {
    final settings = Json.from(
      await Api.get('orders/${order['id']}/delivery-options'),
    );
    if (!mounted || !authenticated) return false;
    final areas = AppState.maps(settings['areas']),
        charges = AppState.maps(settings['deliveryInvoices']);
    if (areas.isEmpty || charges.isEmpty) {
      notice(
        areas.isEmpty
            ? 'Inventory has no active delivery areas.'
            : 'Create an active delivery sub-invoice first.',
        error: true,
      );
      return false;
    }
    existing ??= settings['delivery'] is Map
        ? Json.from(settings['delivery'])
        : null;
    final payload = existing?['payload'] is Map
        ? Json.from(existing!['payload'])
        : <String, dynamic>{};
    final preferred =
        order['selectedDeliveryInvoiceId'] ?? existing?['delivery_invoice_id'];
    var chargeId = charges.any((c) => c['id'] == preferred)
        ? preferred as String
        : charges.first['id'] as String;
    final name = TextEditingController(
          text: payload['customerName'] ?? order['customer_name'],
        ),
        phone = TextEditingController(
          text: payload['customerPhone'] ?? order['phone'],
        ),
        address = TextEditingController(
          text: payload['address'] ?? order['address'],
        ),
        date = TextEditingController(
          text: payload['dueDate'] ?? order['due_date'] ?? '',
        ),
        time = TextEditingController(
          text: payload['readyTimeAt'] != null && payload['readyTimeAt'] != ''
              ? displayDate(payload['readyTimeAt']).substring(11)
              : '',
        ),
        note = TextEditingController(text: payload['note'] ?? '');
    var area = areas.any((a) => a['name'] == payload['areaName'])
        ? payload['areaName'] as String
        : areas.first['name'] as String;
    final formKey = GlobalKey<FormState>();
    var saving = false;
    String? error;
    try {
      final route = DialogRoute<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) {
            Future<void> save(bool send) async {
              if (!formKey.currentState!.validate()) return;
              set(() {
                saving = true;
                error = null;
              });
              try {
                final result = Json.from(
                  await Api.post('orders/${order['id']}/delivery', {
                    'action': existing == null ? 'create' : 'edit',
                    'deliveryInvoiceId': chargeId,
                    'version': order['version'],
                    'revision': existing?['revision'],
                    'areaName': area,
                    'customerName': name.text.trim(),
                    'customerPhone': phone.text.trim(),
                    'address': address.text.trim(),
                    'dueDate': date.text.trim(),
                    'readyTimeAt': time.text.isEmpty
                        ? ''
                        : DateTime.parse(
                            '${date.text}T${time.text}:00+03:00',
                          ).toUtc().toIso8601String(),
                    'note': note.text.trim(),
                  }),
                );
                existing = result;
                if (send) {
                  await Api.post('orders/${order['id']}/delivery', {
                    'action': 'send',
                    'revision': result['revision'],
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
                notice(
                  send
                      ? 'Approved. Sending automatically to inventory as Ready.'
                      : 'Draft saved only in POS. Reception approval is required before sending.',
                );
              } catch (e) {
                if (ctx.mounted) {
                  set(() {
                    saving = false;
                    error = e.toString();
                  });
                }
              }
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 620,
                  maxHeight: 820,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    modalHeader('Delivery address and approval', ctx),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'From ${branchLabel(order['branch'])} → customer address',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: chargeId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Delivery sub-invoice',
                                ),
                                items: charges
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c['id'] as String,
                                        child: Text(
                                          '${c['bill']} · ${money((c['total'] ?? 0) - (c['refunded_total'] ?? 0))} KWD',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: saving
                                    ? null
                                    : (v) => set(() => chargeId = v!),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: area,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Delivery area',
                                ),
                                items: areas
                                    .map(
                                      (a) => DropdownMenuItem(
                                        value: a['name'] as String,
                                        child: Text(
                                          '${a['name']} · ${money(a['chargeFils'])} KWD',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: saving
                                    ? null
                                    : (v) => set(() => area = v!),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: name,
                                decoration: const InputDecoration(
                                  labelText: 'Customer name',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Enter a customer name.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Customer phone',
                                ),
                                validator: (v) =>
                                    v == null ||
                                        !RegExp(
                                          r'^[+\d\s()-]{5,30}$',
                                        ).hasMatch(v)
                                    ? 'Enter a phone number.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: address,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Full delivery address',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Enter the delivery address.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: date,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Delivery date (YYYY-MM-DD, optional)',
                                ),
                                validator: (v) => v == null || v.isEmpty
                                    ? null
                                    : RegExp(
                                            r'^\d{4}-\d{2}-\d{2}$',
                                          ).hasMatch(v) &&
                                          DateTime.tryParse(v)
                                                  ?.toIso8601String()
                                                  .substring(0, 10) ==
                                              v
                                    ? null
                                    : 'Enter a valid date.',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: time,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Ready time (HH:mm Kuwait, optional)',
                                ),
                                validator: (v) => v == null || v.isEmpty
                                    ? null
                                    : RegExp(
                                            r'^([01]\d|2[0-3]):[0-5]\d$',
                                          ).hasMatch(v) &&
                                          date.text.isNotEmpty
                                    ? null
                                    : 'Enter a 24-hour time and delivery date.',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: note,
                                minLines: 2,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Delivery note (optional)',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                settings['canMarkReady'] == true
                                    ? 'Reception can approve and send this request now.'
                                    : 'Save the draft now. Reception must check the finished work before sending.',
                              ),
                              const Text(
                                'Nothing is created in inventory until Reception approves with Send delivery request.',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                              if (error != null)
                                Text(
                                  error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          OutlinedButton(
                            onPressed: saving ? null : () => save(false),
                            child: const Text('Save delivery draft'),
                          ),
                          FilledButton.icon(
                            onPressed:
                                saving ||
                                    !canReviewWork ||
                                    settings['canMarkReady'] != true
                                ? null
                                : () => save(true),
                            icon: const Icon(Icons.send_outlined, size: 17),
                            label: Text(
                              saving ? 'Saving…' : 'Send delivery request',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result ?? false;
    } finally {
      for (final controller in [name, phone, address, date, time, note]) {
        controller.dispose();
      }
    }
  }
}
