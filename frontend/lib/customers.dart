part of 'app.dart';

extension Customers on AppState {
  Future<void> selectCustomer() async {
    final result = await showDialog<Json>(
      context: context,
      builder: (_) => CustomerPicker(app: this, initial: customer),
    );
    if (result != null) {
      update(() => customer = result['id'] == null ? null : result);
    }
  }

  Future<Json?> customerForm({Json? existing, String query = ''}) async {
    final phoneQuery = RegExp(r'^[+\d\s()-]+$').hasMatch(query);
    final result =
        await form(existing == null ? 'New customer' : 'Edit customer', [
          Field(
            'name',
            'Customer name',
            required: true,
            initial: existing?['name'] ?? (phoneQuery ? '' : query),
          ),
          Field(
            'phone',
            'Phone number',
            initial: existing?['phone'] ?? (phoneQuery ? query : ''),
          ),
          Field(
            'address',
            'Address',
            initial: existing?['address'] ?? '',
            multiline: true,
          ),
        ], submit: 'Save customer');
    if (result == null) return null;
    return Json.from(
      await Api.post(
        existing == null ? 'customers' : 'customers/${existing['id']}',
        {...result, 'branch': branch!['id']},
      ),
    );
  }
}

class CustomerPicker extends StatefulWidget {
  final AppState app;
  final Json? initial;
  const CustomerPicker({super.key, required this.app, this.initial});
  @override
  State<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<CustomerPicker> {
  final query = TextEditingController();
  List<Json> results = [], history = [];
  Json? selected;
  Json summary = {};
  Timer? debounce;
  int request = 0, tab = 0;
  bool loading = false, searched = false;
  String? error;
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      selected = widget.initial;
      tab = 1;
      loadCustomer(widget.initial!);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    debounce?.cancel();
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
      searched = true;
      tab = 0;
    });
    try {
      final data = AppState.maps(
        await Api.get('customers?q=${Uri.encodeComponent(query.text.trim())}'),
      );
      if (mounted && token == request) setState(() => results = data);
    } catch (e) {
      if (mounted && token == request) setState(() => error = e.toString());
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  Future<void> loadCustomer(Json customer) async {
    debounce?.cancel();
    final token = ++request;
    setState(() {
      selected = customer;
      loading = true;
      error = null;
      tab = 1;
      summary = {};
      history = [];
    });
    try {
      final data = Json.from(
        await Api.get(
          'customers/${customer['id']}?branch=${app.branch!['id']}',
        ),
      );
      if (mounted && token == request) {
        setState(() {
          selected = Json.from(data['customer']);
          summary = Json.from(data['summary']);
          history = AppState.maps(data['history']);
        });
      }
    } catch (e) {
      if (mounted && token == request) setState(() => error = e.toString());
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  Future<void> save({bool edit = false}) async {
    try {
      final saved = await app.customerForm(
        existing: edit ? selected : null,
        query: query.text.trim(),
      );
      if (saved != null && mounted) await loadCustomer(saved);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget detail(String title, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: muted)),
        const SizedBox(height: 4),
        SelectableText((value ?? '').toString().isEmpty ? '—' : '$value'),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 580,
        maxHeight: MediaQuery.sizeOf(context).height - 60,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          modalHeader('Walk-in customer', context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: query,
                    decoration: const InputDecoration(
                      labelText: 'Find customer by name or phone',
                    ),
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(
                        const Duration(milliseconds: 350),
                        search,
                      );
                    },
                    onSubmitted: (_) => search(),
                  ),
                ),
                IconButton(
                  tooltip: 'Find customer',
                  onPressed: search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => setState(() => tab = 0),
                child: const Text('Search'),
              ),
              TextButton(
                onPressed: selected == null
                    ? null
                    : () => setState(() => tab = 1),
                child: const Text('Details'),
              ),
              TextButton(
                onPressed: selected == null
                    ? null
                    : () => setState(() => tab = 2),
                child: const Text('History'),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (tab == 0) ...[
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Walk-in customer'),
                      subtitle: const Text(
                        'Continue without saved customer details',
                      ),
                      onTap: () => Navigator.pop(context, <String, dynamic>{}),
                    ),
                    if (searched && results.isEmpty && !loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No customers found. Add a new customer below.',
                        ),
                      ),
                    ...results.map(
                      (c) => ListTile(
                        title: Text(c['name']),
                        subtitle: Text('${c['phone']}\n${c['address']}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => loadCustomer(c),
                      ),
                    ),
                  ] else if (selected != null) ...[
                    if (tab == 1) ...[
                      detail('Customer name', selected!['name']),
                      detail('Phone number', selected!['phone']),
                      detail('Address', selected!['address']),
                      const Divider(),
                      Text(
                        '${app.branchName} invoices',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      detail('Total bills', summary['bills'] ?? 0),
                      detail(
                        'Total / balance due',
                        '${money(summary['total'] ?? 0)} / ${money(summary['due'] ?? 0)} KWD',
                      ),
                      if (summary['last_bill'] != null)
                        detail(
                          'Last bill date',
                          displayDate(summary['last_bill']),
                        ),
                    ] else ...[
                      Text(
                        'Invoice history · ${app.branchName}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (history.isEmpty && !loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No invoices in this branch yet.'),
                        ),
                      ...history.map(
                        (o) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(o['bill']),
                          subtitle: Text(
                            '${displayDate(o['created_at'])}\n${o['status']} · ${money(o['total'])} KWD',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.receipt_long_outlined),
                          onTap: () => app.receipt(o),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: loading ? null : () => save(),
                  icon: const Icon(Icons.person_add_outlined, size: 17),
                  label: const Text('Add customer'),
                ),
                if (selected != null)
                  OutlinedButton(
                    onPressed: loading ? null : () => save(edit: true),
                    child: const Text('Edit details'),
                  ),
                if (selected != null)
                  FilledButton(
                    onPressed: loading || error != null
                        ? null
                        : () => Navigator.pop(context, selected),
                    child: const Text('Select customer'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
