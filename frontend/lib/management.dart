part of 'app.dart';

extension Management on AppState {
  Widget management() {
    if (!isAdmin) {
      return empty('Administrator access required.', icon: Icons.lock_outline);
    }
    return FutureBuilder<dynamic>(
      future: Api.get('admin?from=$from&to=$to'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return empty(snapshot.error.toString());
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = Json.from(snapshot.data);
        final members = AppState.maps(data['members']);
        final audit = AppState.maps(data['audit']);
        final summary = AppState.maps(data['summary']);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Administration',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage staff access, catalogue prices and branch performance.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => inviteStaff(),
                          icon: const Icon(Icons.person_add_outlined, size: 18),
                          label: const Text('Add staff access'),
                        ),
                        OutlinedButton.icon(
                          onPressed: catalogueManager,
                          icon: const Icon(Icons.sell_outlined, size: 18),
                          label: const Text('Manage catalogue'),
                        ),
                        rangeButton(),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Create staff accounts with a username, password and allowed branches. Only Admin can create or change accounts.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Branch performance',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 15),
                    ...branches.map((b) {
                      final row = summary
                          .where((s) => s['branch'] == b['id'])
                          .firstOrNull;
                      return ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(b['name']),
                        subtitle: Text(
                          '${row?['count'] ?? 0} sales · Due ${money(row?['due'] ?? 0)} KWD',
                        ),
                        trailing: Text('${money(row?['total'] ?? 0)} KWD'),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Staff', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 15),
                    ...members.map(
                      (m) => ListTile(
                        leading: Icon(
                          m['active'] == 1
                              ? Icons.person_outline
                              : Icons.person_off_outlined,
                        ),
                        title: Text(m['name']),
                        subtitle: Text(
                          '${m['username'] ?? m['email']} · ${m['role']}\n${m['role'] == 'admin' ? 'All branches' : (jsonDecode(m['branches']) as List).map((id) => branches.where((b) => b['id'] == id).firstOrNull?['name'] ?? id).join(', ')}',
                        ),
                        isThreeLine: true,
                        trailing: m['id'] == 'owner'
                            ? badge('Owner')
                            : IconButton(
                                onPressed: () => inviteStaff(existing: m),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Audit trail', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 15),
                    ...audit.map(
                      (a) => ListTile(
                        dense: true,
                        title: Text(a['action']),
                        subtitle: Text(
                          '${displayDate(a['created_at'])} · ${a['branch']} · ${a['actor']}\n${a['detail']}',
                        ),
                        isThreeLine: true,
                      ),
                    ),
                    if (audit.isEmpty) empty('No activity yet'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> inviteStaff({Json? existing}) async {
    final selected = existing != null
        ? List<String>.from(jsonDecode(existing['branches']))
        : <String>[];
    final name = TextEditingController(text: existing?['name'] ?? '');
    final username = TextEditingController(text: existing?['username'] ?? '');
    final password = TextEditingController();
    String role = existing?['role'] ?? 'reception';
    bool active = existing?['active'] != 0;
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                modalHeader(
                  existing == null ? 'Add staff access' : 'Edit staff access',
                  ctx,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: username,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            helperText:
                                existing?['username'] == null &&
                                    existing != null
                                ? 'Add a username, or keep using the existing email login.'
                                : '3–50 letters, numbers, dots, hyphens or underscores',
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: existing == null
                                ? 'Initial password (at least 12 characters)'
                                : 'New password (leave blank to keep current)',
                          ),
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: role,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: ['reception', 'tailor', 'manager', 'admin']
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(roleLabel(r)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => set(() => role = v!),
                        ),
                        const SizedBox(height: 12),
                        if (role != 'admin')
                          ...branches.map(
                            (b) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(b['name']),
                              value: selected.contains(b['id']),
                              onChanged: (v) => set(() {
                                if (v == true) {
                                  selected.add(b['id']);
                                } else {
                                  selected.remove(b['id']);
                                }
                              }),
                            ),
                          ),
                        if (existing != null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active access'),
                            value: active,
                            onChanged: (v) => set(() => active = v),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'name': name.text,
                      'username': username.text,
                      'role': role,
                      'branches': selected,
                      'active': active ? 1 : 0,
                      'password': password.text,
                      if (existing != null) 'id': existing['id'],
                    }),
                    child: const Text('Save staff access'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      await run(() async {
        await Api.post('members', result);
        final data = Json.from(await Api.get('boot'));
        update(() => boot = data);
        notice('Staff access saved.');
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      name.dispose();
      username.dispose();
      password.dispose();
    });
  }

  Future<void> catalogueManager() async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final items = catalogue
              .where(
                (p) => '${p['name']} ${p['id']} ${p['category']}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              )
              .toList();
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
              child: Column(
                children: [
                  modalHeader(
                    'Catalogue · ${catalogue.length} imported items',
                    ctx,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search by item, category or code',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => set(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final p = items[i];
                        return ListTile(
                          title: Text(p['name']),
                          subtitle: Text(
                            '${p['id']} · ${p['category']}${p['active'] == 0 ? ' · Inactive' : ''}',
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              final result = await form(
                                'Edit catalogue item',
                                [
                                  Field(
                                    'price',
                                    'Price (KWD)',
                                    initial: money(p['price']),
                                    number: true,
                                    required: true,
                                  ),
                                  Field(
                                    'active',
                                    'Availability',
                                    options: ['Active', 'Inactive'],
                                    initial: p['active'] == 0
                                        ? 'Inactive'
                                        : 'Active',
                                  ),
                                ],
                                help:
                                    'Excel was used for the initial prices. Changes apply to future sales; old receipts keep their original prices.',
                              );
                              if (result != null) {
                                await run(() async {
                                  await Api.post('prices', {
                                    'id': p['id'],
                                    'price': parseMoney(result['price']),
                                    'active': result['active'] == 'Active'
                                        ? 1
                                        : 0,
                                  });
                                  final data = Json.from(await Api.get('boot'));
                                  update(() => boot = data);
                                  set(() {});
                                });
                              }
                            },
                            child: Text('${money(p['price'])} KWD'),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Initial catalogue: Item_Price_List_ Tailor Express.xlsx · 446 items',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
