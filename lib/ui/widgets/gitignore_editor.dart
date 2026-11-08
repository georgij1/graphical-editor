import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _dirty = false;
  int _lastEpoch = 0;
  double _previewFraction = 0.5;

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
    final ok = widget.controller.applyCode(_text.text);
    setState(() {
      _dirty = !ok;
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final project = controller.currentProject;

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
                const Icon(Icons.visibility_off_outlined, size: 16),
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
                  onPressed: _dirty
                      ? () {
                          setState(() {
                            _text.text = controller.codeContent;
                            _dirty = false;
                          });
                        }
                      : null,
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
    // when no matching file exists in the project yet.
    for (final raw in rulesText.split('\\n')) {
      final v = _virtualPathFromRule(raw);
      if (v == null) continue;
      if (v.endsWith('/')) {
        dirPaths.add(v.substring(0, v.length - 1));
      } else {
        filePaths.add(v);
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final r in roots) buildNode(r, 0),
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
  bool ignored = false;
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
    if (dirOnly && !isDir) continue;

    final containsSlash = rule.contains('/');
    final anchored = rule.startsWith('/');
    if (anchored) rule = rule.substring(1);
    final target = containsSlash ? relativePath : relativePath.split('/').last;
    final pattern = anchored || containsSlash
        ? (anchored ? '^' : '') + _globToRegex(rule, anchored || containsSlash)
        : _globToRegex(rule, false);

    // For non-anchored patterns without slash, match against basename in any dir.
    RegExp re;
    try {
      re = RegExp(pattern);
    } catch (_) {
      continue;
    }
    if (re.hasMatch(target) || (!containsSlash && re.hasMatch(relativePath))) {
      ignored = !neg;
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