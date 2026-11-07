import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'markdown_parser.dart';

/// Markdown editor with live preview. The left pane is an editable text
/// field, the right pane renders the Markdown as Flutter widgets in
/// real time.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.codeContent);
  bool _dirty = false;
  int _lastEpoch = 0;

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _text.addListener(_onChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _text.removeListener(_onChanged);
    _text.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.codeEpoch;
    if (epoch != _lastEpoch) {
      _lastEpoch = epoch;
      _text.text = widget.controller.codeContent;
      _dirty = false;
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {
      _dirty = _text.text != widget.controller.codeContent;
    });
  }

  bool _apply() {
    final controller = widget.controller;
    final ok = controller.applyCode(_text.text);
    setState(() {
      _dirty = !ok;
    });
    _showMessage(
        ok ? context.tr('Markdown source applied.') : context.tr('Apply failed.'));
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

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
                const Icon(Icons.article_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.codePath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Back to canvas'),
                  onPressed: () => controller.closeSource(),
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: context.tr('Reload'),
                  onPressed: _dirty ? () => _reload() : null,
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
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(context.tr('Apply')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                // Editor pane
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
                const VerticalDivider(width: 1),
                // Preview pane
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: MarkdownPreview(
                        source: _text.text,
                        theme: theme,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _reload() {
    setState(() {
      _text.text = widget.controller.codeContent;
      _dirty = false;
    });
  }
}


/// Widget that renders Markdown source as Flutter widgets.
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.source, required this.theme});

  final String source;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: MarkdownParser.parse(source, theme: theme),
    );
  }
}
