import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import 'password_form.dart';
import 'session_controller.dart';

/// Shown while the session is restored, or when that failed (e.g. offline).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return Scaffold(
      body: session.hasError && !session.isLoading
          ? ErrorState(error: session.error!, onRetry: () => ref.read(sessionControllerProvider.notifier).retry())
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 64, color: context.colors.primary),
                  const SizedBox(height: Insets.l),
                  Text('WholeFlow', style: context.text.headlineSmall),
                  const SizedBox(height: Insets.xl),
                  const SizedBox(width: 160, child: LinearProgressIndicator()),
                ],
              ),
            ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signIn(_email.text, _password.text);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (e) {
      if (mounted) setState(() => _error = AppFailure.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).value;
    final notice = _error ?? (session is SignedOut ? session.message : null);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.account_balance_wallet_rounded, size: 56, color: context.colors.primary),
                      const SizedBox(height: Insets.l),
                      Text('WholeFlow', style: context.text.headlineMedium, textAlign: TextAlign.center),
                      const SizedBox(height: Insets.xs),
                      Text(
                        'Shop balances from Tally, wherever you are',
                        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Insets.xxl),
                      if (notice != null) ...[
                        Card.filled(
                          key: const Key('login-error'),
                          color: context.colors.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(Insets.m),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline_rounded, color: context.colors.onErrorContainer),
                                const SizedBox(width: Insets.m),
                                Expanded(
                                  child: Text(notice, style: TextStyle(color: context.colors.onErrorContainer)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.l),
                      ],
                      TextFormField(
                        key: const Key('login-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email, AutofillHints.username],
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email' : null,
                      ),
                      const SizedBox(height: Insets.l),
                      TextFormField(
                        key: const Key('login-password'),
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      const SizedBox(height: Insets.xl),
                      FilledButton(
                        key: const Key('login-submit'),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: Insets.l),
                      Text(
                        'Forgot password? Ask your business owner to reset it.',
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
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
}

/// Shown after the first sign-in with a password set by the owner.
class ForcePasswordChangeScreen extends ConsumerStatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  ConsumerState<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends ConsumerState<ForcePasswordChangeScreen> {
  bool _busy = false;

  Future<void> _submit(String password, String? _) async {
    setState(() => _busy = true);
    final session = ref.read(sessionControllerProvider.notifier);
    try {
      await session.changePassword(password);
    } on AppFailure catch (f) {
      if (f.kind == FailureKind.reauthenticationNeeded) {
        // The sign-in is too old for a password change: sign in again, which
        // brings the user straight back here.
        await session.signOut(message: 'Please sign in again, then set your password.');
      } else if (mounted) {
        showMessage(context, f.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set your password'),
        actions: [
          TextButton(onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(), child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your account was set up with a temporary password. Choose your own password to continue.',
                    style: context.text.bodyLarge,
                  ),
                  const SizedBox(height: Insets.xl),
                  NewPasswordForm(onSubmit: _submit, submitLabel: 'Save and continue', busy: _busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
