import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'user_avatar.dart';

/// Opens the profile dialog: login, avatar and password.
Future<void> showProfileDialog(
  BuildContext context, {
  required EditorController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProfileDialog(controller: controller),
  );
}

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final TextEditingController _email =
      TextEditingController(text: widget.controller.userEmail ?? '');
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  EditorController get controller => widget.controller;

  Future<void> _run(Future<bool> Function() action) async {
    setState(() {
      _busy = true;
      _passwordError = null;
    });
    await action();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveEmail() async {
    await _run(() async {
      final ok = await controller.updateEmail(_email.text);
      if (ok && mounted) _email.text = controller.userEmail ?? '';
      return ok;
    });
  }

  Future<void> _savePassword() async {
    if (_next.text != _confirm.text) {
      setState(() => _passwordError = context.tr('Passwords do not match.'));
      return;
    }
    if (_next.text.length < 6) {
      setState(() => _passwordError =
          context.tr('Password must be at least 6 characters.'));
      return;
    }
    await _run(() async {
      final ok = await controller.changePassword(_current.text, _next.text);
      if (!mounted) return false;
      if (ok) {
        _current.clear();
        _next.clear();
        _confirm.clear();
        return true;
      }
      setState(() =>
          _passwordError = controller.profileMessage ?? 'Server error.');
      return false;
    });
  }

  Future<void> _pickPicture() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    await _run(() => controller.uploadAvatar(bytes, mimeType: _mimeOf(result!.files.single.name)));
  }

  String _mimeOf(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = controller.avatarDataUrl;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.account_circle_outlined),
          const SizedBox(width: 10),
          Text(context.tr('Profile')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  UserAvatar(dataUrl: avatar, email: controller.userEmail, radius: 38),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickPicture,
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(context.tr('Choose picture')),
                        ),
                        if (avatar != null) ...<Widget>[
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(controller.removeAvatar),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(context.tr('Remove picture')),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          context.tr('PNG or JPEG, up to 400 KB.'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(context.tr('Login'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: context.tr('Email'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _saveEmail,
                  child: Text(context.tr('Save')),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.tr('Password'),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _current,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Current password'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _next,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('New password'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Confirm password'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_passwordError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _passwordError!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],
const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _savePassword,
                  child: Text(context.tr('Change password')),
                ),
              ),
              if (controller.profileMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  context.tr(controller.profileMessage!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: controller.profileError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}
