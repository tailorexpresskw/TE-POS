part of 'app.dart';

extension Account on AppState {
  Future<void> checkSession() async {
    try {
      final status = Json.from(await Api.get('auth/status'));
      update(() {
        authChecked = true;
        authenticated = status['authenticated'] == true;
        needsSetup = status['needsSetup'] == true;
        loading = false;
        failure = null;
      });
      if (authenticated) await loadBoot();
    } catch (e) {
      update(() {
        authChecked = true;
        loading = false;
        failure = 'Cannot connect to the POS server. ${e.toString()}';
      });
    }
  }

  Future<void> logout() async {
    if (cart.isNotEmpty &&
        !await confirm(
          'Logout?',
          'The current cart has not been saved. Hold it first, or confirm to discard it.',
        )) {
      return;
    }
    await run(() async {
      await Api.post('auth/logout', {});
      update(() {
        authenticated = false;
        clearCart();
        boot = null;
        branch = null;
        orders = [];
        payments = [];
        expenses = [];
        screen = 0;
      });
    });
  }

  Future<void> changePassword() async {
    final result = await form('Change password', [
      const Field(
        'currentPassword',
        'Current password',
        required: true,
        secret: true,
      ),
      const Field(
        'password',
        'New password (at least 12 characters)',
        required: true,
        secret: true,
      ),
    ]);
    if (result == null) return;
    await run(() async {
      await Api.post('auth/password', result);
      update(() => authenticated = false);
      notice('Password changed. Sign in with your new password.');
    });
  }
}

class LoginScreen extends StatefulWidget {
  final bool needsSetup;
  final String? error;
  final Future<void> Function() onSignedIn;
  const LoginScreen({
    super.key,
    required this.needsSetup,
    required this.onSignedIn,
    this.error,
  });
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final username = TextEditingController(), password = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.needsSetup || busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.post('auth/login', {
        'username': username.text.trim(),
        'password': password.text,
      });
      await widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: panel(
            Form(
              key: formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.content_cut, color: green, size: 38),
                    const SizedBox(height: 14),
                    const Text(
                      'TAILOR EXPRESS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Branch POS - Staff sign in',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 28),
                    if (widget.needsSetup)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Your administrator needs to set up access before you can sign in.',
                        ),
                      ),
                    TextFormField(
                      controller: username,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: (v) => (v ?? '').trim().isNotEmpty
                          ? null
                          : 'Enter your username',
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: password,
                      autofillHints: const [AutofillHints.password],
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onFieldSubmitted: (_) => submit(),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: busy || widget.needsSetup ? null : submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    if (error != null || widget.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error ?? widget.error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'Accounts are created by your administrator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
