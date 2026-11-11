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
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.codeContent,
  );
  final FocusNode _focusNode = FocusNode();
  late ValidationResult _validation = _validate(_text.text);
  int _lastEpoch = 0;
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = <String>[];

  static const List<String> _javaSuggestions = <String>[
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'float',
    'for',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'new',
    'null',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'try',
    'void',
    'volatile',
    'while',
    'true',
    'false',
    'String',
    'Integer',
    'Long',
    'Double',
    'Float',
    'Boolean',
    'Object',
    'List',
    'Map',
    'Set',
    'Optional',
    'Override',
    'Deprecated',
    'SuppressWarnings',
    '@FXML',
    '@Override',
    '@Deprecated',
    'System.out.println()',
    'public static void main(String[] args)',
    'private',
    'protected',
    'public class',
    'public void',
    'private void',
    'return;',
  ];

  bool get _isJava => widget.controller.codeIsJavaSource;
  bool get _isXml =>
      widget.controller.codeIsXmlSource || widget.controller.openSource == null;

  ValidationResult _validate(String source) {
    if (_isJava) {
      return CodeValidator.validateJava(source, path: widget.controller.codePath);
    }
    if (_isXml) {
      return CodeValidator.validateFxml(source);
    }
    return ValidationResult.valid;
  }

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _text.addListener(_onChanged);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
    widget.controller.aiFixHandler = _fixWithAi;
  }

  @override
  void dispose() {
    _hideSuggestions();
    if (identical(widget.controller.aiFixHandler, _fixWithAi)) {
      widget.controller.aiFixHandler = null;
    }
    widget.controller.removeListener(_onControllerChanged);
    _text.removeListener(_onChanged);
    _focusNode.removeListener(_onFocusChanged);
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.codeEpoch;
    if (epoch != _lastEpoch) {
      _lastEpoch = epoch;
      _text.text = widget.controller.codeContent;
      _validation = _validate(_text.text);
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {
      _validation = _validate(_text.text);
    });
    _updateSuggestions();
  }

  bool _apply() {
    final controller = widget.controller;
    if (!_validation.isValid) {
      final error = _validation.errors.first;
      _showMessage(
        context.l10n.issueLocation(error.line, error.column) +
            error.render(context.tr),
      );
      return false;
    }
    final ok = controller.applyCode(_text.text);
    setState(() {
      _validation = _validate(_text.text);
    });
    _showMessage(
      ok
          ? (_isJava
                ? context.tr('Java source applied.')
                : (_isXml
                      ? context.tr('FXML applied.')
                      : context.tr('Source applied.')))
          : context.tr('Invalid FXML — not applied.'),
    );
    return ok;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
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
      _validation = _validate(fixed);
    });
    _showMessage(context.tr('AI suggestion loaded. Review and Apply.'));
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _hideSuggestions();
  }

  void _updateSuggestions() {
    _hideSuggestions();
    if (!_focusNode.hasFocus) return;
    // Show suggestions only for Java source editing.
    if (!widget.controller.codeIsJava && !widget.controller.codeIsJavaSource) {
      // Still allow for generic code if path ends with .java
      final path = widget.controller.codePath.toLowerCase();
      if (!path.endsWith('.java')) return;
    }
    final text = _text.text;
    final sel = _text.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) return;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) return;

    var start = cursor;
    while (start > 0) {
      final c = text.codeUnitAt(start - 1);
      final isAlpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
      final isDigit = c >= 48 && c <= 57;
      final isOther = c == 95 || c == 36 || c == 64; // _ $ @
      if (isAlpha || isDigit || isOther) {
        start--;
      } else {
        break;
      }
    }
    final prefix = text.substring(start, cursor);
    if (prefix.isEmpty) return;

    final lower = prefix.toLowerCase();
    final matches = <String>[];
    final seen = <String>{};
    for (final s in _javaSuggestions) {
      final sl = s.toLowerCase();
      if (sl == lower) continue;
      if (sl.startsWith(lower) && seen.add(s)) {
        matches.add(s);
      }
    }
    if (matches.isEmpty) return;
    _suggestions = matches.take(12).toList();
    _showSuggestions(start, cursor);
  }

  void _showSuggestions(int wordStart, int cursor) {
    _hideSuggestions();
    final pos = _caretGlobalPosition();
    if (pos == null) return;
    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: pos.dx,
        top: pos.dy + 20,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) => InkWell(
                onTap: () => _applySuggestion(_suggestions[i], wordStart, cursor),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _applySuggestion(String suggestion, int wordStart, int cursor) {
    _hideSuggestions();
    final text = _text.text;
    final newText = text.substring(0, wordStart) + suggestion + text.substring(cursor);
    var caret = wordStart + suggestion.length;
    // Place caret inside parentheses when suggestion ends with ()
    if (suggestion.endsWith('()')) {
      caret = wordStart + suggestion.length - 1;
    }
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  void _hideSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Offset? _caretGlobalPosition() {
    final rb = _focusNode.context?.findRenderObject() as RenderBox?;
    if (rb == null) return null;
    final sel = _text.selection;
    if (!sel.isValid) return null;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE6E6E6)
          : const Color(0xFF1F1F1F),
    );
    final painter = TextPainter(
      text: TextSpan(text: _text.text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: (rb.size.width - 32).clamp(0.0, double.infinity));
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: sel.baseOffset),
      Rect.zero,
    );
    return rb.localToGlobal(Offset(16 + caret.dx, 16 + caret.dy));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
        const SingleActivator(LogicalKeyboardKey.escape): _hideSuggestions,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ValidationBar(validation: _validation),
          Expanded(
            child: Container(
              color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFFBFBFB),
              child: TextField(
                controller: _text,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                  color: dark
                      ? const Color(0xFFE6E6E6)
                      : const Color(0xFF1F1F1F),
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
    final issues = validation.issues;

    // Nothing to complain about: a calm "all clear" row.
    if (issues.isEmpty) {
      final color = theme.colorScheme.primary;
      return Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              context.tr('No issues found.'),
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ],
        ),
      );
    }

    // Red for errors (they block Apply), amber for warnings only — the same
    // split IntelliJ IDEA makes in its editor.
    final hasErrors = validation.hasErrors;
    final warnColor = Colors.amber.shade800;
    final color = hasErrors ? theme.colorScheme.error : warnColor;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                hasErrors ? Icons.error_outline : Icons.warning_amber_outlined,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.validationSummary(
                  validation.errorCount,
                  validation.warningCount,
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
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
              itemBuilder: (context, index) {
                final issue = issues[index];
                final issueColor = issue.isError
                    ? theme.colorScheme.error
                    : warnColor;
                return Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        issue.isError
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        size: 12,
                        color: issueColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.l10n.issueLocation(issue.line, issue.column) +
                              issue.render(context.tr),
                          style: TextStyle(fontSize: 11.5, color: issueColor),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
