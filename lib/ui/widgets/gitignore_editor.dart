import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/code_validator.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/java_generator.dart';
import '../../project/project.dart';

/// Editor for `.gitignore` files. The left pane is the editable text; the
/// right pane renders the project tree and highlights the files/folders that
/// the current patterns exclude from version control.
class GitignoreEditor extends StatefulWidget {
  const GitignoreEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<GitignoreEditor> createState() => _GitignoreEditorState();
}

class _GitignoreEditorState extends State<GitignoreEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.codeContent);
  final FocusNode _focusNode = FocusNode();
  int _lastEpoch = 0;
  double _previewFraction = 0.5;
  late ValidationResult _validation = _validate(_text.text);
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
      _validation = _validate(_text.text);
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {
      _validation = _validate(_text.text);
    });
    _updateSuggestions(_text.text);
  }

  bool _apply() {
    if (!_validation.isValid) {
      final error = _validation.errors.first;
      _showMessage(error.render(context.tr));
      return false;
    }
    final ok = widget.controller.applyCode(_text.text);
    setState(() {
      _validation = _validate(_text.text);
    });
    _showMessage(
      ok
          ? context.tr('Gitignore applied.')
          : context.tr('Apply failed.'),
    );
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

  ValidationResult _validate(String source) =>
      CodeValidator.validateGitignore(source);

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
      case '*':
        suggs = <String>['*', '*.log', '*.class', '*.tmp', '*.iml'];
        break;
      case '!':
        suggs = <String>['!', '!important/', '!*.log'];
        break;
      case '.':
        suggs = <String>['.idea/', '.gradle/', '.DS_Store', '.env'];
        break;
      case '/':
        suggs = <String>['/', '/*.log'];
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
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 200),
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
    final style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: Color(0xFFE6E6E6),
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
    final project = controller.currentProject;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
        const SingleActivator(LogicalKeyboardKey.escape): _hideSuggestions,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GitignoreValidationBar(validation: _validation),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerWidth = 8.0;
                const minEditor = 120.0;
                const minPreview = 160.0;
                final usable = (constraints.maxWidth - dividerWidth)
                    .clamp(0.0, double.infinity);
                final room = (usable - minPreview).clamp(minEditor, usable);
                final previewWidth =
                    (_previewFraction * usable).clamp(minPreview, room);
                final editorWidth = (usable - previewWidth).clamp(minEditor, usable);
                bool hovering = false;
                return StatefulBuilder(
                  builder: (context, setLocal) => Row(
                    children: <Widget>[
                      SizedBox(
                        width: editorWidth,
                        child: Container(
                          color: dark
                              ? const Color(0xFF1E1E1E)
                              : const Color(0xFFFBFBFB),
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
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        onEnter: (_) => setLocal(() => hovering = true),
                        onExit: (_) => setLocal(() => hovering = false),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onDoubleTap: () =>
                              setState(() => _previewFraction = 0.5),
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _previewFraction =
                                  ((_previewFraction * usable - details.delta.dx) /
                                          usable)
                                      .clamp(0.0, 1.0);
                            });
                          },
                          child: Container(
                            width: dividerWidth,
                            alignment: Alignment.center,
                            color: hovering
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.10)
                                : null,
                            child: Container(
                              width: 1,
                              color: theme.dividerColor,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: previewWidth,
                        child: Container(
                          color: theme.colorScheme.surface,
                          padding: const EdgeInsets.all(8),
                          child: project == null
                              ? Center(
                                  child: Text(
                                    context.tr('No project open.'),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                )
                              : _GitignoreTreeView(
                                  project: project,
                                  rulesText: _text.text,
                                ),
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

class _GitignoreTreeView extends StatelessWidget {
  const _GitignoreTreeView({
    required this.project,
    required this.rulesText,
  });

  final Project project;
  final String rulesText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = rulesText.split('\n');
    final filePaths = <String>{};
    final dirPaths = <String>{};
    final virtualPaths = <({String path, bool isDir})>[];
    // Generated Java sources.
    for (final f in JavaGenerator.generate(project)) {
      filePaths.add(f.path);
    }
    // Scenes.
    final pkgDir = JavaGenerator.packageDir(project);
    for (final s in project.scenes) {
      filePaths.add('src/main/resources/$pkgDir/${s.name}.fxml');
    }
    // User-created files/folders.
    for (final key in project.sourceOverrides.keys) {
      if (key.endsWith('/')) {
        dirPaths.add(key.substring(0, key.length - 1));
      } else {
        filePaths.add(key);
      }
    }

    // Virtual paths derived from the gitignore rules themselves, so that
    // patterns such as `target/` or `*.log` are visible in the preview even
    // when no matching file exists in the project yet. They are kept separate
    // from the real project tree to avoid confusing indentation.
    for (final raw in rulesText.split('\\n')) {
      final v = _virtualPathFromRule(raw);
      if (v == null) continue;
      final isDir = v.endsWith('/');
      final clean = isDir ? v.substring(0, v.length - 1) : v;
      if (!virtualPaths.any((e) => e.path == clean)) {
        virtualPaths.add((path: clean, isDir: isDir));
      }
    }
    // Derive directories.
    final allPaths = <String>{...filePaths, ...dirPaths};
    for (final p in [...filePaths, ...dirPaths]) {
      final parts = p.split('/');
      for (var i = 1; i < parts.length; i++) {
        allPaths.add(parts.sublist(0, i).join('/'));
      }
    }
    final sorted = allPaths.toList()..sort();
    // Build parent->children.
    final childrenOf = <String, List<String>>{};
    final roots = <String>[];
    for (final p in sorted) {
      final idx = p.lastIndexOf('/');
      final parent = idx < 0 ? '' : p.substring(0, idx);
      if (parent.isEmpty) {
        roots.add(p);
      } else {
        childrenOf.putIfAbsent(parent, () => <String>[]).add(p);
      }
    }

    Widget buildNode(String path, int depth) {
      final isDir = dirPaths.contains(path) || !filePaths.contains(path);
      final ignored = _isIgnored(path, isDir, rules);
      final name = path.split('/').last;
      final kids = childrenOf[path] ?? const <String>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: depth * 16.0, top: 2, bottom: 2),
            child: Row(
              children: <Widget>[
                Icon(
                  isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: ignored
                      ? theme.colorScheme.onSurfaceVariant
                      : (isDir
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: ignored
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                      decoration: ignored
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ignored)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      context.tr('ignored'),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final k in kids) buildNode(k, depth + 1),
        ],
      );
    }

    final realRoots = roots;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final r in realRoots) buildNode(r, 0),
          if (virtualPaths.isNotEmpty) ...<Widget>[
            for (final v in virtualPaths)
              _buildVirtualRow(context, theme, v.path, v.isDir, rules),
          ],
        ],
      ),
    );
  }
}

  Widget _buildVirtualRow(
    BuildContext context,
    ThemeData theme,
    String path,
    bool isDir,
    List<String> rules,
  ) {
    final ignored = _isIgnored(path, isDir, rules);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: <Widget>[
          Icon(
            isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            size: 14,
            color: ignored
                ? theme.colorScheme.onSurfaceVariant
                : (isDir
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              path,
              style: TextStyle(
                fontSize: 12,
                color: ignored
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
                decoration: ignored
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ignored)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                context.tr('ignored'),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.error,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

/// Validation bar for the .gitignore editor.
class _GitignoreValidationBar extends StatelessWidget {
  const _GitignoreValidationBar({required this.validation});

  final ValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = validation.issues;

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
            constraints: const BoxConstraints(maxHeight: 80),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: issues.length,
              itemBuilder: (context, index) {
                final issue = issues[index];
                final issueColor =
                    issue.isError ? theme.colorScheme.error : warnColor;
                return Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 2),
                  child: Text(
                    issue.toString(),
                    style: TextStyle(fontSize: 11.5, color: issueColor),
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

// ---------- virtual path helpers ----------

String? _virtualPathFromRule(String rule) {
  var r = rule.trim();
  if (r.isEmpty || r.startsWith('#')) return null;
  if (r.startsWith('!')) return null;
  final dirOnly = r.endsWith('/');
  if (dirOnly) r = r.substring(0, r.length - 1);
  if (r.startsWith('/')) r = r.substring(1);
  if (r.isEmpty) return null;
  // Only simple patterns become virtual entries.
  if (r.contains('[') || r.contains(']') || r.contains('{') || r.contains('}')) {
    return null;
  }
  r = r.replaceAll('*', 'x').replaceAll('?', 'x');
  if (r.isEmpty) return null;
  return dirOnly ? '$r/' : r;
}

// ---------- gitignore matching helpers ----------

bool _isIgnored(String relativePath, bool isDir, List<String> rules) {
  final parts = relativePath.split('/');
  bool ignored = false;
  String current = '';
  for (var i = 0; i < parts.length; i++) {
    current = i == 0 ? parts[i] : '$current/${parts[i]}';
    final levelIsDir = i < parts.length - 1 || isDir;
    for (final raw in rules) {
      var rule = raw.trim();
      if (rule.isEmpty || rule.startsWith('#')) continue;
      bool neg = false;
      if (rule.startsWith('!')) {
        neg = true;
        rule = rule.substring(1);
      }
      bool dirOnly = false;
      if (rule.endsWith('/')) {
        dirOnly = true;
        rule = rule.substring(0, rule.length - 1);
      }
      if (rule.isEmpty) continue;
      if (dirOnly && !levelIsDir) continue;

      final containsSlash = rule.contains('/');
      final anchored = rule.startsWith('/');
      if (anchored) rule = rule.substring(1);
      final target = containsSlash ? current : current.split('/').last;
      final pattern = anchored || containsSlash
          ? (anchored ? '^' : '') + _globToRegex(rule, anchored || containsSlash)
          : _globToRegex(rule, false);

      RegExp re;
      try {
        re = RegExp(pattern);
      } catch (_) {
        continue;
      }
      if (re.hasMatch(target) ||
          (!containsSlash && re.hasMatch(current))) {
        ignored = !neg;
      }
    }
  }
  return ignored;
}


String _globToRegex(String pat, bool anchored) {
  final buf = StringBuffer();
  if (anchored) buf.write('^');
  int i = 0;
  while (i < pat.length) {
    final c = pat[i];
    if (c == '*') {
      if (i + 1 < pat.length && pat[i + 1] == '*') {
        buf.write('.*');
        i += 2;
        if (i < pat.length && pat[i] == '/') i++;
      } else {
        buf.write('[^/]*');
        i++;
      }
    } else if (c == '?') {
      buf.write('[^/]');
      i++;
    } else if (r'\^$.|+()[]{}'.contains(c)) {
      buf.write('\\$c');
      i++;
    } else {
      buf.write(c);
      i++;
    }
  }
  if (anchored) buf.write(r'$');
  return buf.toString();
}
