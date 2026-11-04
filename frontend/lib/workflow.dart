part of 'app.dart';

const jobStatuses = ['Pending', 'In Progress', 'On Hold', 'Completed'];
String roleLabel(dynamic value) => switch (value) {
  'admin' => 'Admin',
  'reception' || 'cashier' => 'Reception',
  'tailor' => 'Tailor',
  'manager' => 'Branch Manager',
  _ => '$value',
};

extension Workflow on AppState {
  Future<void> goScreen(int target) async {
    update(() => screen = target);
    if ((target == 0 || target == 7) && branch != null) await run(loadData);
  }

  Future<void> selectJobFilter(String filter) async {
    update(() {
      jobFilter = filter;
      jobOffset = 0;
      screen = 7;
    });
    await run(loadData);
  }

  Future<void> searchJobs() async {
    update(() => jobOffset = 0);
    await run(loadData);
  }

  String branchLabel(dynamic id) =>
      branches.where((b) => b['id'] == id).firstOrNull?['name'] ?? '$id';
  String tailorLabel(dynamic id, {String fallback = 'Assign later'}) =>
      AppState.maps(
        boot?['staff'],
      ).where((s) => s['id'] == id).firstOrNull?['name'] ??
      fallback;
  List<Json> branchTailors(String branchId) => AppState.maps(boot?['staff'])
      .where(
        (s) =>
            s['role'] == 'tailor' && (s['branches'] as List).contains(branchId),
      )
      .toList();
  Widget jobMetrics({bool compact = false}) => LayoutBuilder(
    builder: (ctx, box) {
      final metrics = [
        (
          'Unassigned',
          jobSummary['unassigned'] ?? 0,
          Icons.person_add_alt_outlined,
        ),
        ('Pending', jobSummary['pending'] ?? 0, Icons.schedule),
        ('In Progress', jobSummary['in_progress'] ?? 0, Icons.content_cut),
        ('On Hold', jobSummary['on_hold'] ?? 0, Icons.pause_circle_outline),
        ('Completed', jobSummary['completed'] ?? 0, Icons.task_alt),
      ];
      final visible = isTailor ? metrics.skip(1).toList() : metrics;
      final count = box.maxWidth > 950
          ? visible.length
          : box.maxWidth > 550
          ? 3
          : 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: visible
            .map(
              (m) => SizedBox(
                width: (box.maxWidth - 12 * (count - 1)) / count,
                child: InkWell(
                  onTap: () => selectJobFilter(m.$1),
                  child: statCard(
                    m.$1,
                    '${m.$2}',
                    m.$3,
                    m.$1 == 'Completed' ? green : ink,
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
  Widget receptionActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${roleLabel(member['role'])} Dashboard',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          Text(branchName, style: const TextStyle(color: muted)),
          FilledButton.icon(
            onPressed: () => update(() => screen = 2),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('New invoice'),
          ),
          OutlinedButton.icon(
            onPressed: () => goScreen(7),
            icon: const Icon(Icons.content_cut, size: 17),
            label: const Text('Tracking & assignment'),
          ),
          if (isManager)
            OutlinedButton.icon(
              onPressed: () => goScreen(5),
              icon: const Icon(Icons.assessment_outlined, size: 17),
              label: const Text('Branch reports'),
            ),
        ],
      ),
      const SizedBox(height: 14),
      jobMetrics(),
      const SizedBox(height: 18),
      if ((jobSummary['unassigned'] ?? 0) > 0) ...[
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Awaiting tailor assignment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              ...jobs
                  .where((j) => j['tailor_id'] == null)
                  .take(3)
                  .map(
                    (j) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  j['bill'],
                                  style: const TextStyle(color: green),
                                ),
                                Text(
                                  j['customer_name'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Assign tailor',
                            onPressed: () =>
                                assignInvoice(j).catchError((Object e) {
                                  notice(e, error: true);
                                  return null;
                                }),
                            icon: const Icon(Icons.person_add_alt_outlined),
                          ),
                          IconButton(
                            tooltip: 'Invoice / WhatsApp',
                            onPressed: () => receipt(j),
                            icon: const Icon(Icons.receipt_long_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
              TextButton(
                onPressed: () => selectJobFilter('Unassigned'),
                child: const Text('View all unassigned invoices'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    ],
  );
  Widget adminDashboard() {
    final totals = adminSummary['totals'] as Map? ?? {};
    final rows = AppState.maps(adminSummary['branches']);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Admin Dashboard',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const Text('All branches', style: TextStyle(color: muted)),
              rangeButton(),
              FilledButton.icon(
                onPressed: () => update(() => screen = 6),
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Manage users'),
              ),
              OutlinedButton.icon(
                onPressed: () => goScreen(7),
                icon: const Icon(Icons.content_cut, size: 18),
                label: const Text('Tailor tracking'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (ctx, box) {
              final c = box.maxWidth > 1000 ? 4 : 2;
              final values = [
                (
                  'Invoices',
                  '${totals['invoices'] ?? 0}',
                  Icons.receipt_long_outlined,
                ),
                (
                  'Sales (KWD)',
                  money(totals['total'] ?? 0),
                  Icons.shopping_bag_outlined,
                ),
                (
                  'Balance due (KWD)',
                  money(totals['due'] ?? 0),
                  Icons.payments_outlined,
                ),
                (
                  'Open tailor jobs',
                  '${totals['open_jobs'] ?? 0}',
                  Icons.content_cut,
                ),
              ];
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: values
                    .map(
                      (v) => SizedBox(
                        width: (box.maxWidth - 14 * (c - 1)) / c,
                        child: statCard(v.$1, v.$2, v.$3, green),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Branch overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('BRANCH')),
                      DataColumn(label: Text('INVOICES')),
                      DataColumn(label: Text('SALES KWD')),
                      DataColumn(label: Text('DUE KWD')),
                      DataColumn(label: Text('UNASSIGNED')),
                      DataColumn(label: Text('OPEN JOBS')),
                      DataColumn(label: Text('')),
                    ],
                    rows: rows
                        .map(
                          (b) => DataRow(
                            cells: [
                              DataCell(Text(b['name'])),
                              DataCell(Text('${b['invoices']}')),
                              DataCell(Text(money(b['total']))),
                              DataCell(Text(money(b['due']))),
                              DataCell(Text('${b['unassigned']}')),
                              DataCell(Text('${b['open_jobs']}')),
                              DataCell(
                                TextButton(
                                  onPressed: () async {
                                    update(() {
                                      trackingBranch = b['id'];
                                      jobOffset = 0;
                                      screen = 7;
                                    });
                                    await run(loadData);
                                  },
                                  child: const Text('View jobs'),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          jobMetrics(),
          const SizedBox(height: 18),
          jobPreview(
            'Invoices needing assignment',
            jobs.where((j) => j['tailor_id'] == null).take(8).toList(),
          ),
        ],
      ),
    );
  }

  Widget tailorDashboard() => SingleChildScrollView(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Tailor Dashboard',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            Text(
              '${member['name']} - $branchName',
              style: const TextStyle(color: muted),
            ),
            OutlinedButton.icon(
              onPressed: () => run(loadData),
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Refresh'),
            ),
            FilledButton.icon(
              onPressed: () => goScreen(7),
              icon: const Icon(Icons.content_cut, size: 17),
              label: const Text('My tracking'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        jobMetrics(),
        if ((jobSummary['overdue'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: badge(
              '${jobSummary['overdue']} jobs past their collection date',
              color: Colors.orange,
            ),
          ),
        const SizedBox(height: 20),
        jobPreview(
          'My current jobs',
          jobs.where((j) => j['job_status'] != 'Completed').take(10).toList(),
        ),
      ],
    ),
  );
  Widget jobPreview(String title, List<Json> rows) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          empty(
            isTailor
                ? 'No assigned work in this queue.'
                : 'No invoices waiting in this queue.',
          )
        else
          ...rows.map(jobCard),
      ],
    ),
  );
  Widget jobCard(Json job) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              job['bill'],
              style: const TextStyle(color: green, fontWeight: FontWeight.w600),
            ),
            badge(
              job['job_status'] ?? 'Pending',
              color: job['job_status'] == 'Completed'
                  ? green
                  : job['job_status'] == 'On Hold'
                  ? Colors.orange
                  : Colors.cyan,
            ),
            if (isAdmin)
              Text(
                branchLabel(job['branch']),
                style: const TextStyle(color: muted),
              ),
            if ((job['due_date'] ?? '') != '')
              Text(
                'Collection: ${job['due_date']}',
                style: TextStyle(
                  color:
                      job['due_date'].toString().compareTo(today()) < 0 &&
                          job['job_status'] != 'Completed'
                      ? Colors.orange
                      : muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(job['customer_name'] ?? ''),
        Text(
          AppState.maps(
            job['lines'],
          ).map((l) => '${l['qty']} x ${l['name']}').join(' / '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        if (!isTailor)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tailor: ${(job['tailor_name'] ?? '').toString().isEmpty ? 'Unassigned' : job['tailor_name']}${job['tailor_active'] == 0 ? ' (inactive)' : ''}',
            ),
          ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => jobDetail(job),
              icon: const Icon(Icons.history, size: 15),
              label: const Text('Job details'),
            ),
            if (!isTailor)
              OutlinedButton.icon(
                onPressed: () => run(() async {
                  await assignInvoice(job);
                }),
                icon: const Icon(Icons.person_add_alt_outlined, size: 15),
                label: const Text('Assign tailor'),
              ),
            if (!isTailor)
              TextButton(
                onPressed: () => receipt(job),
                child: const Text('Invoice / WhatsApp'),
              ),
            if (isTailor && job['job_status'] != 'Completed')
              FilledButton(
                onPressed: () => updateJob(job),
                child: const Text('Update progress'),
              ),
          ],
        ),
      ],
    ),
  );
  Widget trackingScreen() => SingleChildScrollView(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              isTailor ? 'My Tailor Tracking' : 'Tailor Tracking & Assignment',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            if (isAdmin)
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: trackingBranch,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All branches'),
                    ),
                    ...branches.map(
                      (b) => DropdownMenuItem<String>(
                        value: b['id'],
                        child: Text(b['name']),
                      ),
                    ),
                  ],
                  onChanged: (v) async {
                    update(() {
                      trackingBranch = v!;
                      jobOffset = 0;
                    });
                    await run(loadData);
                  },
                ),
              ),
            if (!isAdmin) Text(branchName),
            OutlinedButton.icon(
              onPressed: () => run(loadData),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        jobMetrics(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in [
              'All',
              if (!isTailor) 'Unassigned',
              ...jobStatuses,
            ])
              ChoiceChip(
                label: Text(filter),
                selected: jobFilter == filter,
                onSelected: (_) => selectJobFilter(filter),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            labelText: 'Find invoice or customer',
            prefixIcon: Icon(Icons.search, size: 17),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: searchJobs,
              icon: const Icon(Icons.arrow_forward, size: 18),
            ),
          ),
          onSubmitted: (_) => searchJobs(),
          onChanged: (v) => update(() => jobSearch = v),
        ),
        const SizedBox(height: 16),
        ...jobs
            .where(
              (j) =>
                  (jobFilter == 'All' ||
                      (jobFilter == 'Unassigned'
                          ? j['tailor_id'] == null
                          : j['job_status'] == jobFilter)) &&
                  '${j['bill']} ${j['customer_name']} ${j['tailor_name']}'
                      .toLowerCase()
                      .contains(jobSearch.toLowerCase()),
            )
            .map(jobCard),
        if (jobs.isEmpty)
          empty(
            isTailor
                ? 'No invoices have been assigned to you.'
                : 'No jobs found.',
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Showing ${jobs.isEmpty ? 0 : jobOffset + 1}-${jobOffset + jobs.length} of $jobMatched jobs',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            TextButton(
              onPressed: jobOffset > 0
                  ? () async {
                      update(() => jobOffset -= 500);
                      await run(loadData);
                    }
                  : null,
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: jobOffset + jobs.length < jobMatched
                  ? () async {
                      update(() => jobOffset += 500);
                      await run(loadData);
                    }
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    ),
  );
  Future<String?> chooseTailor(String invoiceBranch, String current) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              modalHeader('Assign tailor - ${branchLabel(invoiceBranch)}', ctx),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListTile(
                      title: const Text('Assign later / Unassigned'),
                      leading: const Icon(Icons.person_outline),
                      trailing: current.isEmpty
                          ? const Icon(Icons.check, color: green)
                          : null,
                      onTap: () => Navigator.pop(ctx, ''),
                    ),
                    if (branchTailors(invoiceBranch).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No active tailors are configured for this branch. An Admin can add them under Administration.',
                        ),
                      ),
                    ...branchTailors(invoiceBranch).map(
                      (t) => ListTile(
                        title: Text(t['name']),
                        subtitle: Text(branchLabel(invoiceBranch)),
                        leading: const Icon(Icons.content_cut),
                        trailing: t['id'] == current
                            ? const Icon(Icons.check, color: green)
                            : null,
                        onTap: () => Navigator.pop(ctx, t['id']),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Json?> assignInvoice(Json invoice) async {
    final current = Json.from(
      (await Api.get('orders/${invoice['id']}'))['order'],
    );
    final chosen = await chooseTailor(
      current['branch'],
      current['tailor_id'] ?? '',
    );
    if (chosen == null) return null;
    var reason = '';
    if ((current['tailor_id'] ?? '') != chosen &&
        current['tailor_id'] != null &&
        current['job_status'] != 'Pending') {
      final answer = await form('Reassign work', [
        const Field(
          'reason',
          'Reason for reassignment',
          required: true,
          multiline: true,
        ),
      ]);
      if (answer == null) return null;
      reason = answer['reason'];
    }
    final updated = Json.from(
      await Api.post('orders/${current['id']}', {
        'action': 'assign',
        'tailorId': chosen,
        'version': current['version'],
        'reason': reason,
      }),
    );
    updated['tailor_name'] = chosen.isEmpty
        ? 'Unassigned'
        : tailorLabel(chosen);
    await loadData();
    notice(chosen.isEmpty ? 'Invoice left unassigned.' : 'Tailor assigned.');
    return updated;
  }

  Future<void> updateJob(Json job, {bool noteOnly = false}) async {
    try {
      final current = Json.from(
        (await Api.get('tracking/${job['id']}'))['job'],
      );
      final transitions = {
        'Pending': ['In Progress', 'On Hold'],
        'In Progress': ['On Hold', 'Completed'],
        'On Hold': ['In Progress'],
        'Completed': <String>[],
      };
      final options = isManager
          ? jobStatuses
          : transitions[current['job_status']] ?? <String>[];
      if (!noteOnly && options.isEmpty) {
        notice('This work is complete.');
        return;
      }
      final result =
          await form(noteOnly ? 'Progress note' : 'Update tailor progress', [
            if (!noteOnly)
              Field(
                'status',
                'Work status',
                options: options,
                initial: options.first,
              ),
            Field(
              'note',
              noteOnly ? 'Note' : 'Note / reason (required for corrections)',
              required: noteOnly,
              multiline: true,
            ),
          ]);
      if (result == null) return;
      await run(() async {
        await Api.post('tracking/${job['id']}', {
          ...result,
          'action': noteOnly ? 'note' : 'progress',
          'version': current['version'],
        });
        await loadData();
        notice('Tracking updated.');
      });
    } catch (e) {
      notice(e, error: true);
    }
  }

  Future<void> jobDetail(Json job) async {
    try {
      final detail = Json.from(await Api.get('tracking/${job['id']}'));
      final row = Json.from(detail['job']);
      await modal(
        'Job ${row['bill']}',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(row['customer_name'], style: const TextStyle(fontSize: 20)),
            Text('${branchLabel(row['branch'])} - ${row['job_status']}'),
            if ((row['due_date'] ?? '') != '')
              Text('Collection: ${row['due_date']}'),
            const Divider(height: 26),
            ...AppState.maps(row['lines']).map(
              (l) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${l['qty']} x ${l['name']}'),
                subtitle: (l['note'] ?? '') != '' ? Text(l['note']) : null,
              ),
            ),
            if ((row['notes'] ?? '') != '') Text(row['notes']),
            ...AppState.maps(detail['attachments']).map(
              (f) => TextButton.icon(
                onPressed: () => browser.openExternal(
                  Api.uri('documents/${f['id']}').toString(),
                ),
                icon: const Icon(Icons.attach_file, size: 16),
                label: Text(f['name']),
              ),
            ),
            const SizedBox(height: 14),
            if ((isTailor || isManager) && row['tailor_id'] != null)
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await updateJob(row);
                    },
                    child: const Text('Update progress'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await updateJob(row, noteOnly: true);
                    },
                    child: const Text('Add note'),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const Text(
              'Work history',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            ...AppState.maps(detail['events']).map((e) {
              final entry = Json.from(jsonDecode(e['detail']));
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${e['actor_name']} - ${e['action']}'),
                subtitle: Text(
                  '${displayDate(e['created_at'])}\n${entry['from'] ?? ''} → ${entry['to'] ?? ''}\n${entry['note'] ?? ''}',
                ),
              );
            }),
          ],
        ),
      );
    } catch (e) {
      notice(e, error: true);
    }
  }

  Future<void> shareInvoice(Json invoice) async {
    final phone = TextEditingController(
      text: (invoice['phone'] ?? '').toString(),
    );
    try {
      final detail = Json.from(await Api.get('orders/${invoice['id']}'));
      final order = Json.from(detail['order']);
      final payments = AppState.maps(detail['payments']);
      if (phone.text.isEmpty) phone.text = order['phone'] ?? '';
      final message = whatsappInvoice(order, branchLabel(order['branch']));
      await modal(
        'WhatsApp invoice',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Customer invoice',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              'Save the compact PDF and attach it manually in WhatsApp. You review the message and press Send.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Customer WhatsApp number',
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xffedf7ef),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(message),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => browser.printHtml(
                invoiceHtml(
                  {
                    ...order,
                    'lines': AppState.maps(
                      order['lines'],
                    ).map((l) => {...l, 'arabic': arabicService(l)}).toList(),
                  },
                  branchLabel(order['branch']),
                  payments: payments,
                  mobile: true,
                  fontBase: Api.uri(
                    'boot',
                  ).resolve('/pos/assets/assets/fonts').toString(),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Save WhatsApp PDF'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                try {
                  browser.openExternal(
                    whatsappDraft(phone.text, message).toString(),
                  );
                  notice(
                    'WhatsApp draft opened. Attach the PDF if needed, then press Send yourself.',
                  );
                } catch (e) {
                  notice(e, error: true);
                }
              },
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Open WhatsApp'),
            ),
          ],
        ),
        width: 540,
      );
    } catch (e) {
      notice(e, error: true);
    } finally {
      Future<void>.delayed(const Duration(seconds: 1), phone.dispose);
    }
  }
}
