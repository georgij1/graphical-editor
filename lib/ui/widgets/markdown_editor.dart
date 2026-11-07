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
  final FocusNode _focusNode = FocusNode();
  bool _dirty = false;
  int _lastEpoch = 0;
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = <String>[];

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _text.addListener(_onChanged);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _hideSuggestions();
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
      _dirty = false;
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {
      _dirty = _text.text != widget.controller.codeContent;
    });
    _updateSuggestions(_text.text);
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

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _hideSuggestions();
  }

  void _updateSuggestions(String value) {
    _hideSuggestions();
    if (!_focusNode.hasFocus) return;
    final sel = _text.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) return;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > value.length) return;
    final ch = value[cursor - 1];
    List<String> suggs;
    switch (ch) {
      case '#':
        suggs = <String>['# ', '## ', '### ', '#### '];
        break;
      case '*':
        suggs = <String>['**bold**', '*italic*', '***bold italic***'];
        break;
      case '-':
        suggs = <String>['- ', '- [ ] '];
        break;
      case '>':
        suggs = <String>['> '];
        break;
      case '`':
        suggs = <String>['`code`', '```\ncode\n```'];
        break;
      case '[':
        suggs = <String>['[text](url)'];
        break;
      case '!':
        suggs = <String>['![alt](url)'];
        break;
      default:
        suggs = <String>[];
    }
    if (suggs.isEmpty) return;
    _suggestions = suggs;
    _showSuggestions();
  }

  void _showSuggestions() {
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
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) => InkWell(
                onTap: () => _applySuggestion(_suggestions[i]),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
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

  void _applySuggestion(String snippet) {
    _hideSuggestions();
    final sel = _text.selection;
    final cursor = sel.baseOffset;
    final text = _text.text;
    final start = cursor - 1;
    if (start < 0) return;
    final newText = text.substring(0, start) + snippet + text.substring(cursor);
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
    _dirty = true;
    setState(() {});
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
    painter.layout(maxWidth: rb.size.width - 32);
    final caret = painter.getOffsetForCaret(sel.base, Rect.zero);
    return rb.localToGlobal(Offset(16 + caret.dx, 16 + caret.dy));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
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
                const VerticalDivider(width: 1),
                // Preview pane
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface,
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SingleChildScrollView(
                        child: SizedBox(
                          width: double.infinity,
                          child: MarkdownPreview(
                            source: _text.text,
                            theme: theme,
                          ),
                        ),
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
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: MarkdownParser.parse(source, theme: theme),
    );
  }
}
