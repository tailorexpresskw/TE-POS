part of 'app.dart';

const shiftDays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

extension ShiftControls on AppState {
  bool handleShiftError(Object error) {
    if (error is! ApiException || error.code != 'SHIFT_BLOCKED') return false;
    lockForShift(error.message);
    return true;
  }

  void configureShiftLock(Json? access) {
    if (access?['enabled'] != true || access?['endsAt'] == null) {
      shiftEndTimer?.cancel();
      shiftWarningTimer?.cancel();
      shiftWindowKey = null;
      return;
    }
    final key =
        '${access!['revision']}|${access['endsAt']}|${access['allowedBranches']}';
    if (key == shiftWindowKey) return;
    shiftWindowKey = key;
    shiftEndTimer?.cancel();
    shiftWarningTimer?.cancel();
    final end = DateTime.tryParse('${access['endsAt']}'),
        server = DateTime.tryParse('${access['serverTime']}');
    if (end == null || server == null) return;
    final remaining = end.difference(server);
    void warn() {
      if (mounted && authenticated) {
        notice(
          'Your shift ends at ${displayDate(access['endsAt'])} (Kuwait). Finish or hold unsaved invoices before access locks.',
        );
      }
    }

    if (remaining > const Duration(minutes: 5)) {
      shiftWarningTimer = Timer(remaining - const Duration(minutes: 5), warn);
    } else if (remaining > Duration.zero) {
      Future<void>.delayed(Duration.zero, warn);
    }
    shiftEndTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted && authenticated) {
        lockForShift(
          'This shift period has ended. Sign in again when your next authorized shift starts.',
        );
      }
    });
  }

  Future<void> refreshShiftAccess() async {
    if (!authenticated || checkingShift) return;
    checkingShift = true;
    try {
      final result = Json.from(await Api.get('auth/status'));
      if (!authenticated) return;
      if (result['authenticated'] != true) {
        lockForShift(
          'Your session ended. Sign in again during your authorized shift.',
        );
        return;
      }
      final access = result['shiftAccess'] is Map
          ? Json.from(result['shiftAccess'])
          : null;
      if (access?['enabled'] == true &&
          branch != null &&
          !(access!['allowedBranches'] as List).contains(branch!['id'])) {
        lockForShift(
          'Your scheduled branch changed. Sign in again to select an authorized branch.',
        );
        return;
      }
      final previous = member['shift_access'];
      configureShiftLock(access);
      if (previous is Map &&
          access != null &&
          (previous['revision'] != access['revision'] ||
              jsonEncode(previous['allowedBranches']) !=
                  jsonEncode(access['allowedBranches']))) {
        await loadBoot();
      }
    } catch (error) {
      if (error is ApiException && error.code == 'STALE_SESSION') return;
      handleShiftError(error);
    } finally {
      checkingShift = false;
    }
  }

  void lockForShift(String message) {
    if (!mounted) return;
    if (!authenticated && boot == null && authChecked) {
      update(() => failure = message);
      return;
    }
    if (cart.isNotEmpty && member['id'] != null && branch != null) {
      suspendedShiftDraft = Json.from(
        jsonDecode(
          jsonEncode({
            'memberId': member['id'],
            'branchId': branch!['id'],
            'cart': cart,
            'docs': docs,
            'customer': customer,
            'restored': restored,
            'notes': notes,
            'staff': staff,
            'aggregator': aggregator,
            'dueDate': dueDate,
            'coupon': coupon,
            'discount': discount,
            'extra': extra,
            'draftId': draftId,
            'invoiceKind': invoiceKind,
          }),
        ),
      );
    }
    Api.invalidatePendingRequests();
    shiftEndTimer?.cancel();
    shiftWarningTimer?.cancel();
    shiftWindowKey = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    update(() {
      authenticated = false;
      authChecked = true;
      loading = false;
      busy = false;
      failure = message;
      boot = null;
      branch = null;
      clearCart();
      orders = [];
      payments = [];
      expenses = [];
      jobs = [];
      jobSummary = {};
      adminSummary = {};
      notificationItems = [];
      unreadNotifications = 0;
      screen = 0;
      trackingBranch = 'all';
      jobOffset = 0;
      jobMatched = 0;
    });
    Api.queueSessionLogout();
  }

  void restoreShiftDraft() {
    final draft = suspendedShiftDraft;
    if (draft == null ||
        draft['memberId'] != member['id'] ||
        draft['branchId'] != branch?['id']) {
      return;
    }
    cart = AppState.maps(draft['cart']);
    docs = AppState.maps(draft['docs']);
    customer = draft['customer'] == null ? null : Json.from(draft['customer']);
    restored = draft['restored'] == null ? null : Json.from(draft['restored']);
    notes = draft['notes'];
    staff = draft['staff'];
    aggregator = draft['aggregator'];
    dueDate = draft['dueDate'];
    coupon = draft['coupon'];
    discount = draft['discount'];
    extra = draft['extra'];
    draftId = draft['draftId'];
    invoiceKind = draft['invoiceKind'];
    suspendedShiftDraft = null;
    Future<void>.delayed(Duration.zero, () {
      if (mounted) {
        notice(
          'Your unsaved invoice draft was restored for this account and branch.',
        );
      }
    });
  }

  Future<Json?> shiftPeriod(
    List<Json> allowed, {
    Json? existing,
    bool weekly = true,
  }) async {
    final start = TextEditingController(text: existing?['start'] ?? '09:00'),
        end = TextEditingController(text: existing?['end'] ?? '17:00');
    var day = (existing?['day'] as int?) ?? 0;
    var selectedBranch = (existing?['branch'] ?? '').toString();
    if (!allowed.any((b) => b['id'] == selectedBranch)) selectedBranch = '';
    Future<void> chooseTime(TextEditingController controller) async {
      final parts = controller.text.split(':'),
          hour = int.tryParse(parts.first) ?? 9,
          minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: hour % 24, minute: minute.clamp(0, 59)),
      );
      if (picked != null) {
        controller.text =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      }
    }

    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                modalHeader(
                  weekly ? 'Weekly shift period' : 'Exception shift period',
                  ctx,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Kuwait time · 24-hour format',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 16),
                        if (weekly) ...[
                          DropdownButtonFormField<int>(
                            initialValue: day,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Day'),
                            items: shiftDays.indexed
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.$1,
                                    child: Text(entry.$2),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => set(() => day = value!),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: start,
                          decoration: InputDecoration(
                            labelText: 'Start (HH:MM)',
                            suffixIcon: IconButton(
                              tooltip: 'Choose start time',
                              onPressed: () => chooseTime(start),
                              icon: const Icon(Icons.schedule),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: end,
                          decoration: InputDecoration(
                            labelText: 'End (HH:MM)',
                            suffixIcon: IconButton(
                              tooltip: 'Choose end time',
                              onPressed: () => chooseTime(end),
                              icon: const Icon(Icons.schedule),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBranch,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Allowed branch',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Any assigned branch'),
                            ),
                            ...allowed.map(
                              (b) => DropdownMenuItem<String>(
                                value: b['id'],
                                child: Text(
                                  b['name'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              set(() => selectedBranch = value!),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'An end before the start continues into the next day. Use 24:00 for midnight at the end of this day.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, {
                      if (weekly) 'day': day,
                      'start': start.text.trim(),
                      'end': end.text.trim(),
                      'branch': selectedBranch,
                    }),
                    child: const Text('Use shift period'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      start.dispose();
      end.dispose();
    });
    return result;
  }

  Future<Json?> shiftException(List<Json> allowed, {Json? existing}) async {
    var date = existing?['date'] ?? today(), off = existing?['off'] ?? true;
    var periods = AppState.maps(existing?['periods']);
    return showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                modalHeader('Dated shift exception', ctx),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.parse(date),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100, 12, 31),
                            );
                            if (picked != null && ctx.mounted) {
                              set(
                                () => date = picked.toIso8601String().substring(
                                  0,
                                  10,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.event, size: 17),
                          label: Text(date),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Full calendar day off'),
                          value: off,
                          onChanged: (value) => set(() => off = value),
                        ),
                        const Text(
                          'This exception replaces the weekly schedule for the selected Kuwait date. A day off also blocks hours carried in from the previous night.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        if (!off) ...[
                          ...periods.indexed.map(
                            (entry) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${entry.$2['start']}–${entry.$2['end']}',
                              ),
                              subtitle: Text(
                                entry.$2['branch'] == ''
                                    ? 'Any assigned branch'
                                    : branchLabel(entry.$2['branch']),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove exception period',
                                onPressed: () =>
                                    set(() => periods.removeAt(entry.$1)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final period = await shiftPeriod(
                                allowed,
                                weekly: false,
                              );
                              if (period != null && ctx.mounted) {
                                set(() => periods = [...periods, period]);
                              }
                            },
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('Add exception period'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: FilledButton(
                    onPressed: !off && periods.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, {
                            'date': date,
                            'off': off,
                            'periods': off ? [] : periods,
                          }),
                    child: const Text('Use dated exception'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editWorkingHours(Json staff) async {
    try {
      final data = Json.from(await Api.get('shifts/${staff['id']}'));
      if (!mounted || !authenticated) return;
      final policy = Json.from(data['policy']),
          assigned = List<String>.from(data['staff']['branches']);
      final allowed = branches
          .where((branch) => assigned.contains(branch['id']))
          .toList();
      var enabled = policy['enabled'] == true, saving = false;
      var weekly = AppState.maps(policy['weekly']),
          exceptions = AppState.maps(policy['exceptions']);
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
                  modalHeader('Working hours · ${staff['name']}', ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Kuwait time · Admin-controlled access',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Every non-Admin role can be restricted. Only Admin receives blocked-access alerts. An enabled schedule with no periods blocks all access.',
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Restrict access to these shifts',
                            ),
                            value: enabled,
                            onChanged: saving
                                ? null
                                : (value) => set(() => enabled = value),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const Divider(),
                          const Text(
                            'Weekly periods',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (weekly.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'No weekly periods. Unlisted days are off when restrictions are enabled.',
                              ),
                            ),
                          ...weekly.indexed.map(
                            (entry) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${shiftDays[entry.$2['day']]} · ${entry.$2['start']}–${entry.$2['end']}',
                              ),
                              subtitle: Text(
                                entry.$2['branch'] == ''
                                    ? 'Any assigned branch'
                                    : branchLabel(entry.$2['branch']),
                              ),
                              onTap: saving
                                  ? null
                                  : () async {
                                      final result = await shiftPeriod(
                                        allowed,
                                        existing: entry.$2,
                                      );
                                      if (result != null && ctx.mounted) {
                                        set(() => weekly[entry.$1] = result);
                                      }
                                    },
                              trailing: IconButton(
                                tooltip: 'Remove weekly period',
                                onPressed: saving
                                    ? null
                                    : () =>
                                          set(() => weekly.removeAt(entry.$1)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final result = await shiftPeriod(allowed);
                                    if (result != null && ctx.mounted) {
                                      set(() => weekly = [...weekly, result]);
                                    }
                                  },
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('Add weekly period'),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Days off / temporary exceptions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          ...exceptions.indexed.map(
                            (entry) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${entry.$2['date']} · ${entry.$2['off'] == true ? 'Day off' : 'Working-day override'}',
                              ),
                              subtitle: entry.$2['off'] == true
                                  ? null
                                  : Text(
                                      AppState.maps(entry.$2['periods'])
                                          .map(
                                            (p) => '${p['start']}–${p['end']}',
                                          )
                                          .join(', '),
                                    ),
                              onTap: saving
                                  ? null
                                  : () async {
                                      final result = await shiftException(
                                        allowed,
                                        existing: entry.$2,
                                      );
                                      if (result != null && ctx.mounted) {
                                        set(
                                          () => exceptions[entry.$1] = result,
                                        );
                                      }
                                    },
                              trailing: IconButton(
                                tooltip: 'Remove dated exception',
                                onPressed: saving
                                    ? null
                                    : () => set(
                                        () => exceptions.removeAt(entry.$1),
                                      ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final result = await shiftException(
                                      allowed,
                                    );
                                    if (result != null && ctx.mounted) {
                                      set(
                                        () => exceptions = [
                                          ...exceptions,
                                          result,
                                        ],
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.event_available, size: 17),
                            label: const Text('Add dated exception'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              set(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await Api.post('shifts/${staff['id']}', {
                                  'enabled': enabled,
                                  'weekly': weekly,
                                  'exceptions': exceptions,
                                  'revision': policy['revision'],
                                });
                                if (ctx.mounted) Navigator.pop(ctx);
                                update(() {});
                                notice(
                                  'Working hours saved. Active sessions use the new rules immediately.',
                                );
                              } catch (e) {
                                if (ctx.mounted) {
                                  set(() {
                                    saving = false;
                                    error = e.toString();
                                  });
                                }
                              }
                            },
                      child: Text(saving ? 'Saving…' : 'Save working hours'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!handleShiftError(error)) notice(error, error: true);
    }
  }

  Future<void> showShiftAlerts() async {
    try {
      var start = from, end = to, saving = false;
      Future<Json> fetch() async =>
          Json.from(await Api.get('shifts/alerts?from=$start&to=$end'));
      var data = await fetch();
      if (!mounted || !authenticated) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) {
            final rows = AppState.maps(data['items']),
                summary = Json.from(data['summary'] ?? {});
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 800,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    modalHeader('Off-shift access alerts', ctx),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Admin only · Kuwait time',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Text(
                              'These are blocked account attempts, not proof of who was physically using the account. Repeated attempts are grouped in 15-minute windows.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          final range =
                                              await showDateRangePicker(
                                                context: ctx,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(
                                                  2100,
                                                  12,
                                                  31,
                                                ),
                                                initialDateRange: DateTimeRange(
                                                  start: DateTime.parse(start),
                                                  end: DateTime.parse(end),
                                                ),
                                              );
                                          if (range == null) return;
                                          set(() {
                                            start = range.start
                                                .toIso8601String()
                                                .substring(0, 10);
                                            end = range.end
                                                .toIso8601String()
                                                .substring(0, 10);
                                            saving = true;
                                          });
                                          try {
                                            final next = await fetch();
                                            if (ctx.mounted) {
                                              set(() => data = next);
                                            }
                                          } catch (e) {
                                            notice(e, error: true);
                                          } finally {
                                            if (ctx.mounted) {
                                              set(() => saving = false);
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.date_range, size: 17),
                                  label: Text('$start — $end'),
                                ),
                                TextButton(
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          await Api.post('shifts/alerts', {
                                            'action': 'read',
                                            'id': 'all',
                                          });
                                          await refreshNotifications();
                                          notice(
                                            'Security alerts marked as read.',
                                          );
                                        },
                                  child: const Text(
                                    'Mark security alerts read',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${summary['attempts'] ?? 0} attempts · ${summary['events'] ?? 0} groups · ${summary['staff'] ?? 0} accounts',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${summary['login_attempts'] ?? 0} sign-in attempts with valid credentials',
                            ),
                            if (saving) const LinearProgressIndicator(),
                            if (rows.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'No blocked attempts in this date range.',
                                ),
                              ),
                            ...rows.map(
                              (row) => Container(
                                margin: const EdgeInsets.only(top: 14),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: line),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${row['staff_name']} · ${row['username']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(row['reason']),
                                    Text(
                                      '${row['attempts']} attempt(s) · ${displayDate(row['first_at'])} to ${displayDate(row['last_at'])}',
                                    ),
                                    Text(
                                      'Source: ${row['source'] == 'login'
                                          ? 'Sign-in with valid credentials'
                                          : row['source'] == 'branch'
                                          ? 'Unscheduled branch request'
                                          : 'Existing-session request'}',
                                    ),
                                    if (row['attempted_branch'] != '')
                                      Text(
                                        'Requested branch: ${branchLabel(row['attempted_branch'])}',
                                      ),
                                    if (row['path'] != '')
                                      Text(
                                        row['path'],
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (rows.length == 200)
                              const Text(
                                'Showing the latest 200 groups; totals include the complete selected date range.',
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } catch (error) {
      if (!handleShiftError(error)) notice(error, error: true);
    }
  }
}
