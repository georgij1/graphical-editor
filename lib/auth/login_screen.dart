import 'package:flutter/material.dart';

import '../editor/editor_controller.dart';
import '../l10n/app_localizations.dart';

/// Sign in / registration screen shown before the editor for account users.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final EditorController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _toggleLanguage() {
    widget.controller.setLanguage(widget.controller.isRussian ? 'en' : 'ru');
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    String? error;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      error = context.tr('Enter a valid email address.');
    } else if (password.length < 6) {
      error = context.tr('Password must be at least 6 characters.');
    } else if (_isRegister && password != _confirm.text) {
      error = context.tr('Passwords do not match.');
    }
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    if (_isRegister) {
      await widget.controller.register(email, password);
    } else {
      await widget.controller.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final busy = widget.controller.authBusy;
                final error = widget.controller.authError;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.account_tree_outlined, size: 28),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('FXML Editor',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              tooltip: context.tr('Language'),
                              icon: const Icon(Icons.language_outlined),
                              onPressed: busy ? null : _toggleLanguage,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                              'Sign in to store your projects in the cloud.'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<bool>(
                          segments: <ButtonSegment<bool>>[
                            ButtonSegment<bool>(
                                value: false,
                                label: Text(context.tr('Sign in'))),
                            ButtonSegment<bool>(
                                value: true,
                                label: Text(context.tr('Create account'))),
                          ],
                          selected: <bool>{_isRegister},
                          onSelectionChanged: busy
                              ? null
                              : (selection) => setState(
                                    () => _isRegister = selection.first),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _email,
                          enabled: !busy,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: context.tr('Email'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !busy,
                          obscureText: _obscure,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: context.tr('Password'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_isRegister) ...<Widget>[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirm,
                            enabled: !busy,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: context.tr('Confirm password'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                        if (error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text(_isRegister
                                  ? context.tr('Create account')
                                  : context.tr('Sign in')),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
