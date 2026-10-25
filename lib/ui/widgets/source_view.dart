import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/code_validator.dart';
import '../../editor/editor_controller.dart';
import 'ai_fix_dialog.dart';
import '../../l10n/app_localizations.dart';

/// Editable text editor for the file currently selected in the project tree:
/// the active scene's FXML or a generated Java source. Replaces the canvas
/// while the "Code" tab is active. The content is validated as it is typed.
class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.controller});

  final EditorController controller;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.codeContent);
  late ValidationResult _validation = _validate(_text.text);
  bool _dirty = false;

  bool get _isJava => widget.controller.codeIsJava;

  ValidationResult _validate(String source) =>
      CodeValidator.validate(isJava: _isJava, source: source);

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _dirty = _text.text != widget.controller.codeContent;
      _validation = _validate(_text.text);
    });
  }

  void _reload() {
    setState(() {
      _text.text = widget.controller.codeContent;
      _dirty = false;
      _validation = _validate(_text.text);
    });
  }

  bool _apply() {
    final controller = widget.controller;
    if (!_validation.isValid) {
      _showMessage(_validation.firstError ?? context.tr('Cannot apply invalid source.'));
      return false;
    }
    final isJava = controller.codeIsJava;
    final ok = controller.applyCode(_text.text);
    setState(() {
      _dirty = !ok;
      _validation = _validate(_text.text);
    });
_showMessage(ok
        ? (isJava
            ? context.tr('Java source applied.')
            : context.tr('FXML applied.'))
        : context.tr('Invalid FXML — not applied.'));
    return ok;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _fixWithAi() async {
    final controller = widget.controller;
    final fixed = await showAiFixDialog(
      context,
      controller: controller,
      path: controller.codePath,
      source: _text.text,
      errors: _validation.issues.map((i) => i.toString()).toList(),
    );
    if (fixed == null || !mounted) return;
    setState(() {
      _text.text = fixed;
      _dirty = true;
      _validation = _validate(fixed);
    });
    _showMessage(context.tr('AI suggestion loaded. Review and Apply.'));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isJava = controller.codeIsJava;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: <Widget>[
                Icon(isJava ? Icons.data_object : Icons.description_outlined,
                    size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.codePath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (isJava)
                  IconButton(
                    tooltip: context.tr('Back to canvas'),
                    onPressed: () {
                      controller.closeSource();
                      controller.setCodeMode(false);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: context.tr('Reload'),
                  onPressed: _dirty ? _reload : null,
                  icon: const Icon(Icons.undo, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: context.tr('Copy'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _text.text));
                    _showMessage(context.tr('Source copied to clipboard.'));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: context.tr('Fix with AI'),
                  onPressed: _fixWithAi,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _validation.isValid ? _apply : null,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(context.tr('Apply')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _ValidationBar(validation: _validation),
          Expanded(
            child: Container(
              color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFFBFBFB),
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                  color:
                      dark ? const Color(0xFFE6E6E6) : const Color(0xFF1F1F1F),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationBar extends StatelessWidget {
  const _ValidationBar({required this.validation});

  final ValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = validation.isValid;
    final color = valid ? theme.colorScheme.primary : theme.colorScheme.error;
    final issues = validation.issues;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: valid
          ? Row(
              children: <Widget>[
                Icon(Icons.check_circle_outline, size: 14, color: color),
                const SizedBox(width: 6),
                Text(context.tr('No issues found.'),
                    style: TextStyle(fontSize: 11.5, color: color)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 14, color: color),
                    const SizedBox(width: 6),
Text(
                      context.l10n.issuesFound(issues.length),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: issues.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(left: 20, bottom: 2),
                      child: Text(
                        issues[index].toString(),
                        style: TextStyle(fontSize: 11.5, color: color),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
