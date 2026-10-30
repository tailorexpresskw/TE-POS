library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'api.dart';
import 'browser.dart' as browser;
part 'cashier.dart';
part 'records.dart';
part 'management.dart';

const mint = Color(0xffabdabb),
    green = Color(0xff22bf74),
    ink = Color(0xff30334d),
    bg = Color(0xfff7f7fa),
    muted = Color(0xff81818e),
    line = Color(0xffe9e9ef);
void main() => runApp(const PosRoot());

final posMessenger = GlobalKey<ScaffoldMessengerState>();

class PosRoot extends StatelessWidget {
  const PosRoot({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tailor Express ? POS',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: posMessenger,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['NotoSansArabic'],
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: line),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      dividerColor: line,
    ),
    home: const PosApp(),
  );
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});
  @override
  State<PosApp> createState() => AppState();
}

class Field {
  final String key, label, initial;
  final List<String>? options;
  final bool number, required, multiline;
  const Field(
    this.key,
    this.label, {
    this.initial = '',
    this.options,
    this.number = false,
    this.required = false,
    this.multiline = false,
  });
}

class AppState extends State<PosApp> {
  GlobalKey<ScaffoldMessengerState> get messenger => posMessenger;
  Json? boot, branch;
  List<Json> orders = [], payments = [], expenses = [], cart = [], docs = [];
  Json? customer, restored;
  String? coupon;
  String category = 'Skirt',
      search = '',
      notes = '',
      staff = '',
      aggregator = '',
      dueDate = '',
      draftId = uid(),
      from = today(),
      to = today(),
      saleSearch = '',
      saleStatus = 'All',
      payFilter = 'All',
      keypad = '',
      brand = 'All',
      invoiceKind = 'sale';
  int screen = 0, selected = -1, discount = 0, extra = 0, cartTab = 0;
  bool busy = false, loading = true, arabic = false;
  String? failure;
  Timer? timer;
  Json get member => boot?['member'] ?? {};
  bool get isManager =>
      member['role'] == 'admin' || member['role'] == 'manager';
  bool get isAdmin => member['role'] == 'admin';
  List<Json> get catalogue => maps(boot?['catalogue']);
  List<Json> get branches => maps(boot?['branches']);
  List<Json> get employees => maps(boot?['staff'])
      .where(
        (s) =>
            s['role'] == 'admin' ||
            (s['branches'] as List).contains(branch?['id']),
      )
      .toList();
  List<String> get methods => List<String>.from(boot?['methods'] ?? []);
  int get subtotal =>
      cart.fold(0, (s, l) => s + (l['qty'] as int) * (l['price'] as int));
  int get actualDiscount {
    if (coupon != null) {
      final c = maps(
        boot?['coupons'],
      ).where((c) => c['id'] == coupon).firstOrNull;
      if (c != null) return (subtotal * c['percent'] / 100).round();
    }
    return discount;
  }

  int get total => subtotal - actualDiscount + extra;
  String get branchName => branch?['name'] ?? 'Select location';
  List<Json> get sales => orders.where((o) => o['kind'] == 'sale').toList();
  List<Json> get activeSales => sales
      .where((o) => !['Voided', 'Refunded'].contains(o['status']))
      .toList();
  static List<Json> maps(dynamic data) =>
      (data as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  void update(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void notice(Object message, {bool error = false}) {
    messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(message.toString().replaceFirst('Exception: ', '')),
        backgroundColor: error ? Colors.red.shade700 : ink,
      ),
    );
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    update(() => busy = true);
    try {
      await fn();
    } catch (e) {
      notice(e, error: true);
    } finally {
      update(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    loadBoot();
    timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (branch != null && !busy) {
        loadData().catchError((Object e) {
          notice(
            'Connection interrupted. Your cart is still open.',
            error: true,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadBoot() async {
    update(() {
      loading = true;
      failure = null;
    });
    try {
      final data = Json.from(await Api.get('boot'));
      update(() => boot = data);
      update(() => loading = false);
      if (branch == null) {
        await Future<void>.delayed(Duration.zero);
        await chooseBranch();
      } else {
        await loadData();
      }
    } catch (e) {
      update(() => failure = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      update(() => loading = false);
    }
  }

  Future<void> loadData() async {
    if (branch == null) return;
    final target = branch!['id'];
    final data = Json.from(
      await Api.get('data?branch=$target&from=$from&to=$to'),
    );
    if (branch?['id'] != target) return;
    update(() {
      orders = maps(data['orders']);
      payments = maps(data['payments']);
      expenses = maps(data['expenses']);
    });
  }

  Future<void> chooseBranch() async {
    if (cart.isNotEmpty) {
      if (!await confirm(
        'Change location?',
        'Clear the current cart before changing branches?',
      )) {
        return;
      }
    }
    if (!mounted) return;
    final chosen = await showDialog<Json>(
      context: context,
      barrierDismissible: branch != null,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              modalHeader('Select location', ctx, close: branch != null),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'This location stays selected until you log out.',
                  style: TextStyle(color: muted),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: branches
                        .map(
                          (b) => SizedBox(
                            width: 190,
                            height: 64,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, b),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                              ),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: line,
                                    child: Icon(
                                      Icons.storefront_outlined,
                                      size: 20,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(b['name'])),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        browser.navigate('/signout-with-chatgpt?return_to=/'),
                    child: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      update(() {
        branch = chosen;
        clearCart();
      });
      await loadData();
    }
  }

  void clearCart() {
    cart = [];
    docs = [];
    customer = null;
    restored = null;
    coupon = null;
    notes = '';
    staff = '';
    aggregator = '';
    dueDate = '';
    discount = 0;
    extra = 0;
    selected = -1;
    keypad = '';
    draftId = uid();
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<Json?> form(
    String title,
    List<Field> fields, {
    String submit = 'Save',
    String? help,
  }) async {
    final controllers = {
      for (final f in fields) f.key: TextEditingController(text: f.initial),
    };
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              modalHeader(title, ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (help != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Text(
                              help,
                              style: const TextStyle(color: muted),
                            ),
                          ),
                        ...fields.map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: f.options != null
                                ? DropdownButtonFormField<String>(
                                    initialValue: f.options!.contains(f.initial)
                                        ? f.initial
                                        : f.options!.first,
                                    decoration: InputDecoration(
                                      labelText: f.label,
                                    ),
                                    items: f.options!
                                        .map(
                                          (s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(s),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        controllers[f.key]!.text = v ?? '',
                                    onSaved: (v) =>
                                        controllers[f.key]!.text = v ?? '',
                                    validator: (v) =>
                                        f.required && (v == null || v.isEmpty)
                                        ? 'Required'
                                        : null,
                                  )
                                : TextFormField(
                                    controller: controllers[f.key],
                                    decoration: InputDecoration(
                                      labelText: f.label,
                                    ),
                                    maxLines: f.multiline ? 5 : 1,
                                    keyboardType: f.number
                                        ? const TextInputType.numberWithOptions(
                                            decimal: true,
                                          )
                                        : TextInputType.text,
                                    validator: (v) =>
                                        f.required && (v ?? '').trim().isEmpty
                                        ? 'Required'
                                        : null,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          formKey.currentState!.save();
                          Navigator.pop(ctx, {
                            for (final f in fields)
                              f.key: controllers[f.key]!.text.trim(),
                          });
                        }
                      },
                      child: Text(submit),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Dialog transitions may still be using controllers during their closing frame.
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
    return result;
  }

  Future<void> modal(String title, Widget content, {double width = 600}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: MediaQuery.sizeOf(ctx).height - 70,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              modalHeader(title, ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: DateTime.parse(from),
        end: DateTime.parse(to),
      ),
    );
    if (range != null) {
      update(() {
        from = range.start.toIso8601String().substring(0, 10);
        to = range.end.toIso8601String().substring(0, 10);
      });
      await run(loadData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                header(),
                if (screen != 2) navigation(),
                Expanded(
                  child: failure != null
                      ? Center(
                          child: SizedBox(
                            width: 420,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_outline,
                                  size: 38,
                                  color: green,
                                ),
                                const SizedBox(height: 20),
                                Text(failure!, textAlign: TextAlign.center),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: () => browser.navigate(
                                    '/signin-with-chatgpt?return_to=/',
                                  ),
                                  child: const Text('Sign in with ChatGPT'),
                                ),
                                TextButton(
                                  onPressed: loadBoot,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : boot == null
                      ? const Center(child: CircularProgressIndicator())
                      : branch == null
                      ? Center(
                          child: FilledButton(
                            onPressed: chooseBranch,
                            child: const Text('Select location'),
                          ),
                        )
                      : screen == 2
                      ? cashier()
                      : screen == 0
                      ? dashboard()
                      : screen == 1
                      ? records(quotations: true)
                      : screen == 3
                      ? records()
                      : screen == 4
                      ? expensesScreen()
                      : screen == 5
                      ? reports()
                      : management(),
                ),
                if (screen != 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '© Tailor Express',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                        const Spacer(),
                        Text(
                          '${member['name'] ?? ''}  ·  ${member['role'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (busy || loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: const LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }

  Widget header() => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        const Icon(Icons.content_cut, color: green, size: 28),
        const SizedBox(width: 9),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MediaQuery.sizeOf(context).width < 600 ? 'TE' : 'TAILOR EXPRESS',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: .7,
              ),
            ),
            const Text(
              'BRANCH POS',
              style: TextStyle(fontSize: 9, color: green, letterSpacing: 2),
            ),
          ],
        ),
        const Spacer(),
        if (screen == 2)
          IconButton(
            tooltip: 'Dashboard',
            onPressed: () => update(() => screen = 0),
            icon: const Icon(Icons.dashboard_outlined),
          ),
        if (MediaQuery.sizeOf(context).width < 600)
          IconButton(
            tooltip: branchName,
            onPressed: busy ? null : () => run(chooseBranch),
            icon: const Icon(Icons.storefront_outlined, size: 20),
          ),
        if (MediaQuery.sizeOf(context).width >= 600)
          Flexible(
            child: TextButton.icon(
              onPressed: busy ? null : () => run(chooseBranch),
              icon: const Icon(Icons.storefront_outlined, size: 17),
              label: Text(branchName, overflow: TextOverflow.ellipsis),
            ),
          ),
        if (MediaQuery.sizeOf(context).width > 700)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(today(), style: const TextStyle(color: muted)),
          ),
        IconButton(
          tooltip: arabic ? 'English labels' : 'Arabic service labels',
          onPressed: () => update(() => arabic = !arabic),
          icon: const Icon(Icons.translate, size: 20),
        ),
        PopupMenuButton<String>(
          tooltip: 'Account',
          onSelected: (v) {
            if (v == 'logout') {
              browser.navigate('/signout-with-chatgpt?return_to=/');
            }
            if (v == 'refresh') run(loadData);
            if (v == 'admin') update(() => screen = 6);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Text(member['name'] ?? 'Account'),
            ),
            const PopupMenuItem(value: 'refresh', child: Text('Refresh data')),
            if (isAdmin)
              const PopupMenuItem(
                value: 'admin',
                child: Text('Administration'),
              ),
            const PopupMenuItem(value: 'logout', child: Text('Logout')),
          ],
          icon: const Icon(Icons.account_circle_outlined, color: green),
        ),
      ],
    ),
  );
  Widget navigation() {
    final names = [
      'Dashboard',
      'Sales Quotations',
      'POS',
      'Sales List',
      'Petty Expenses',
      'Reports',
    ];
    final icons = [
      Icons.dashboard_outlined,
      Icons.description_outlined,
      Icons.desktop_windows_outlined,
      Icons.format_list_bulleted,
      Icons.payments_outlined,
      Icons.assessment_outlined,
    ];
    return Container(
      height: 49,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          for (final i
              in (MediaQuery.sizeOf(context).width < 600
                  ? [2, 0, 3, 1, 4, 5]
                  : [0, 1, 2, 3, 4, 5]))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: ink,
                  backgroundColor: screen == i ? mint : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                onPressed: () => update(() => screen = i),
                icon: Icon(icons[i], size: 17),
                label: Text(names[i]),
              ),
            ),
          if (isAdmin)
            TextButton.icon(
              onPressed: () => update(() => screen = 6),
              icon: const Icon(Icons.settings_outlined, size: 17),
              label: const Text('Administration'),
            ),
        ],
      ),
    );
  }
}

Widget modalHeader(String title, BuildContext ctx, {bool close = true}) =>
    Container(
      height: 52,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: const BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (close)
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
            ),
        ],
      ),
    );
Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) =>
    Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d202035),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
Widget empty(String label, {IconData icon = Icons.inbox_outlined}) => Center(
  child: Padding(
    padding: const EdgeInsets.all(35),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: line),
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(color: muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  ),
);
Widget badge(String label, {Color color = green}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(label, style: TextStyle(color: color, fontSize: 11)),
);
Widget moneyText(num value, {double size = 20, Color color = ink}) => Text(
  '${money(value)} KWD',
  style: TextStyle(fontSize: size, color: color),
);
Widget statCard(String label, String value, IconData icon, Color color) =>
    panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 21)),
        ],
      ),
    );
String escape(dynamic value) => '$value'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
