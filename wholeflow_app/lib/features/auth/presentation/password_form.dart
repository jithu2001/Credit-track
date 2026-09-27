import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// New password + confirmation fields with validation. Calls [onSubmit] with
/// the new password when valid.
class NewPasswordForm extends StatefulWidget {
  const NewPasswordForm({super.key, required this.onSubmit, required this.submitLabel, this.busy = false});

  final Future<void> Function(String password) onSubmit;
  final String submitLabel;
  final bool busy;

  @override
  State<NewPasswordForm> createState() => _NewPasswordFormState();
}

class _NewPasswordFormState extends State<NewPasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) widget.onSubmit(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('new-password'),
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New password',
              helperText: 'At least 8 characters',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
          ),
          const SizedBox(height: Insets.l),
          TextFormField(
            key: const Key('confirm-password'),
            controller: _confirm,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            validator: (v) => v != _password.text ? "Passwords don't match" : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Insets.xl),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: widget.busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
