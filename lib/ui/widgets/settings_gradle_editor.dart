import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'highlighting_text_controller.dart';

/// Dedicated editor for `settings.gradle` with graphical controls for common
/// Gradle settings (root project name and included projects/modules).
class SettingsGradleEditor extends StatefulWidget {
  const SettingsGradleEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<SettingsGradleEditor> createState() => _SettingsGradleEditorState();
}

class _SettingsGradleEditorState extends State<SettingsGradleEditor> {
  late final HighlightingTextEditingController _text =
      HighlightingTextEditingController(
    text: widget.controller.codeContent,
    language: HighlightLanguage.gradle,
  );
  final FocusNode _focusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();
  bool _syncingScroll = false;
  int _lastEpoch = 0;
  double _previewFraction = 0.45;

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _text.addListener(_onChanged);
    widget.controller.addListener(_onControllerChanged);
    _editorScrollController.addListener(_onEditorScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHighlighting();
    });
  }

  void _onEditorScroll() {
    if (_syncingScroll) return;
    if (!_gutterScrollController.hasClients ||
        !_editorScrollController.hasClients) {
      return;
    }
    _syncingScroll = true;
    final target = _editorScrollController.offset.clamp(
      0.0,
      _gutterScrollController.position.maxScrollExtent,
    );
    _gutterScrollController.jumpTo(target);
    _syncingScroll = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHighlighting();
  }

  void _syncHighlighting() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final changed =
        _text.dark != dark || _text.language != HighlightLanguage.gradle;
    _text.dark = dark;
    _text.language = HighlightLanguage.gradle;
    if (changed) _text.refresh();
  }

  @override
  void dispose() {
    _editorScrollController.removeListener(_onEditorScroll);
    widget.controller.removeListener(_onControllerChanged);
    _text.removeListener(_onChanged);
    _text.dispose();
    _focusNode.dispose();
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.codeEpoch;
    if (epoch != _lastEpoch) {
      _lastEpoch = epoch;
      _text.text = widget.controller.codeContent;
      _syncHighlighting();
      setState(() {});
    } else {
      _syncHighlighting();
    }
  }

  void _onChanged() {
    setState(() {});
  }

  bool _apply() {
    final ok = widget.controller.applyCode(_text.text);
    _showMessage(
      ok ? context.tr('Source applied.') : context.tr('Apply failed.'),
    );
    return ok;
  }

  void _setSource(String source, {bool apply = true}) {
    _text.text = source;
    setState(() {});
    if (apply) {
      widget.controller.applyCode(_text.text);
    }
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

  // ------------------------------- Parsing -------------------------------

  _RootProjectNameMatch? _parseRootProjectName(String source) {
    final re = RegExp(
      '''^\\s*rootProject\\.name\\s*=\\s*(['"])([^'"]*)\\1\\s*\$''',
      multiLine: true,
    );
    final m = re.firstMatch(source);
    if (m == null) return null;
    var end = m.end;
    // include trailing newline in replace range when convenient
    if (end < source.length && source[end] == '\r') end++;
    if (end < source.length && source[end] == '\n') end++;
    return _RootProjectNameMatch(
      name: m.group(2) ?? '',
      quote: m.group(1) ?? "'",
      start: m.start,
      end: end,
      lineStart: m.start,
      lineEnd: end,
    );
  }

  List<_IncludeItem> _parseIncludes(String source) {
    final items = <_IncludeItem>[];
    final lineRe = RegExp(r'^\s*include\b[^\n]*$', multiLine: true);
    final tokenRe = RegExp('''(['"])([^'"]+)\\1''');
    for (final lineMatch in lineRe.allMatches(source)) {
      final line = lineMatch.group(0) ?? '';
      for (final token in tokenRe.allMatches(line)) {
        final name = token.group(2) ?? '';
        if (name.isEmpty) continue;
        final absStart = lineMatch.start + token.start;
        final absEnd = lineMatch.start + token.end;
        items.add(_IncludeItem(
          name: name,
          tokenStart: absStart,
          tokenEnd: absEnd,
          lineStart: lineMatch.start,
          lineEnd: lineMatch.end,
        ));
      }
    }
    return items;
  }

  // ----------------------------- Root name ------------------------------

  Future<void> _editRootProjectName(String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.tr('Root project name')),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: dialogContext.tr('Project name'),
                hintText: dialogContext.tr('Project name'),
              ),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(ctrl.text.trim()),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
              child: Text(dialogContext.tr('Save')),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (result == null) return;
    _setRootProjectName(result);
  }

  void _setRootProjectName(String name) {
    var source = _text.text;
    final trimmed = name.trim();
    final existing = _parseRootProjectName(source);
    if (trimmed.isEmpty) {
      if (existing != null) {
        source = source.replaceRange(existing.start, existing.end, '');
      }
      _setSource(source);
      return;
    }
    final escaped = trimmed.replaceAll("'", "\\'");
    final line = "rootProject.name = '$escaped'\n";
    if (existing != null) {
      source = source.replaceRange(existing.start, existing.end, line);
    } else {
      if (source.isEmpty) {
        source = line;
      } else if (source.startsWith('\n')) {
        source = '$line$source';
      } else {
        source = '$line\n$source';
      }
    }
    _setSource(source);
  }

  // ------------------------------- Includes ------------------------------

  String _normalizeIncludeName(String input) {
    var v = input.trim();
    if (v.isEmpty) return v;
    // Accept forms like :app or app; keep leading ':' if user provided it.
    v = v.replaceAll(RegExp(r'^include\s+'), '').trim();
    if ((v.startsWith("'") && v.endsWith("'")) ||
        (v.startsWith('"') && v.endsWith('"'))) {
      v = v.substring(1, v.length - 1);
    }
    return v.trim();
  }

  String? _validateIncludeName(String raw, {String? originalName}) {
    final name = _normalizeIncludeName(raw);
    if (name.isEmpty) return 'Module name is required';
    final valid = RegExp(r'^:?[A-Za-z0-9_.\-]+(?::[A-Za-z0-9_.\-]+)*$');
    if (!valid.hasMatch(name)) return 'Invalid module name';
    final existing = _parseIncludes(_text.text).map((e) => e.name).toList();
    for (final e in existing) {
      if (e == name && name != originalName) {
        return 'Module is already included';
      }
    }
    return null;
  }

  Future<String?> _showIncludeDialog({
    required String titleKey,
    String initial = '',
    String? originalName,
  }) async {
    final ctrl = TextEditingController(text: initial);
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void submit() {
              final err = _validateIncludeName(
                ctrl.text,
                originalName: originalName,
              );
              if (err != null) {
                setDialogState(() {
                  errorText = dialogContext.tr(err);
                });
                return;
              }
              final name = _normalizeIncludeName(ctrl.text);
              Navigator.of(dialogContext).pop(name);
            }

            return AlertDialog(
              title: Text(dialogContext.tr(titleKey)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Module name'),
                        hintText: ':app',
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                      onSubmitted: (_) => submit(),
                    ),
                    if (errorText != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(dialogContext.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: submit,
                  child: Text(dialogContext.tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _addInclude() async {
    final input = await _showIncludeDialog(titleKey: 'Add module');
    if (input == null) return;
    final name = _normalizeIncludeName(input);
    if (name.isEmpty) return;
    final escaped = name.replaceAll("'", "\\'");
    final line = "include '$escaped'\n";
    var source = _text.text;
    if (source.isEmpty) {
      source = line;
    } else {
      final suffix = source.endsWith('\n') ? '' : '\n';
      source = '$source$suffix$line';
    }
    _setSource(source);
  }

  Future<void> _editInclude(_IncludeItem item) async {
    final input = await _showIncludeDialog(
      titleKey: 'Edit module',
      initial: item.name,
      originalName: item.name,
    );
    if (input == null) return;
    final name = _normalizeIncludeName(input);
    if (name.isEmpty) return;
    final escaped = name.replaceAll("'", "\\'");
    final replacement = "'$escaped'";
    final source = _text.text;
    if (item.tokenStart < 0 ||
        item.tokenEnd > source.length ||
        item.tokenStart >= item.tokenEnd) {
      return;
    }
    final updated =
        source.replaceRange(item.tokenStart, item.tokenEnd, replacement);
    _setSource(updated);
  }

  void _deleteInclude(_IncludeItem item) {
    var source = _text.text;
    if (item.tokenStart < 0 ||
        item.tokenEnd > source.length ||
        item.tokenStart >= item.tokenEnd) {
      return;
    }
    var start = item.tokenStart;
    var end = item.tokenEnd;

    // Try to remove a comma adjacent to this token to keep the line valid.
    var removedComma = false;
    var i = end;
    while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
      i++;
    }
    if (i < source.length && source[i] == ',') {
      end = i + 1;
      removedComma = true;
    } else {
      i = start - 1;
      while (i >= 0 && (source[i] == ' ' || source[i] == '\t')) {
        i--;
      }
      if (i >= 0 && source[i] == ',') {
        start = i;
        removedComma = true;
      }
    }

    // Trim one adjacent space around removed token/comma for cleanliness.
    if (!removedComma) {
      if (start > 0 && source[start - 1] == ' ') start--;
    } else {
      while (end < source.length && source[end] == ' ') {
        end++;
        break;
      }
    }

    var updated = source.replaceRange(start, end, '');

    // If the include line became empty like "include" or "include   ", remove the line.
    final lineRe =
        RegExp(r'^\s*include\s*,?\s*$', multiLine: true);
    final m = lineRe.firstMatch(updated);
    if (m != null) {
      var ls = m.start;
      var le = m.end;
      if (le < updated.length && updated[le] == '\r') le++;
      if (le < updated.length && updated[le] == '\n') le++;
      updated = updated.replaceRange(ls, le, '');
    }

    _setSource(updated);
  }

  // --------------------------------- UI ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final root = _parseRootProjectName(_text.text);
    final includes = _parseIncludes(_text.text);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerWidth = 8.0;
                const minEditor = 120.0;
                const minPreview = 220.0;
                final usable = (constraints.maxWidth - dividerWidth)
                    .clamp(0.0, double.infinity);
                final room = (usable - minEditor).clamp(minPreview, usable);
                final previewWidth =
                    (_previewFraction * usable).clamp(minPreview, room);
                final editorWidth =
                    (usable - previewWidth).clamp(minEditor, usable);
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _LineNumberGutter(
                                controller: _gutterScrollController,
                                lineCount:
                                    '\n'.allMatches(_text.text).length + 1,
                                dark: dark,
                              ),
                              Container(
                                width: 1,
                                color: dark
                                    ? const Color(0xFF2D2D2D)
                                    : const Color(0xFFE0E0E0),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  focusNode: _focusNode,
                                  scrollController: _editorScrollController,
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
                            ],
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
                              setState(() => _previewFraction = 0.45),
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _previewFraction =
                                  ((_previewFraction * usable -
                                              details.delta.dx) /
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
                        child: _SettingsPanel(
                          rootProjectName: root?.name,
                          includes: includes,
                          onEditRootName: () => _editRootProjectName(root?.name),
                          onAddInclude: _addInclude,
                          onEditInclude: _editInclude,
                          onDeleteInclude: _deleteInclude,
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

class _RootProjectNameMatch {
  const _RootProjectNameMatch({
    required this.name,
    required this.quote,
    required this.start,
    required this.end,
    required this.lineStart,
    required this.lineEnd,
  });

  final String name;
  final String quote;
  final int start;
  final int end;
  final int lineStart;
  final int lineEnd;
}

class _IncludeItem {
  const _IncludeItem({
    required this.name,
    required this.tokenStart,
    required this.tokenEnd,
    required this.lineStart,
    required this.lineEnd,
  });

  final String name;
  final int tokenStart;
  final int tokenEnd;
  final int lineStart;
  final int lineEnd;
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.rootProjectName,
    required this.includes,
    required this.onEditRootName,
    required this.onAddInclude,
    required this.onEditInclude,
    required this.onDeleteInclude,
  });

  final String? rootProjectName;
  final List<_IncludeItem> includes;
  final VoidCallback onEditRootName;
  final VoidCallback onAddInclude;
  final void Function(_IncludeItem item) onEditInclude;
  final void Function(_IncludeItem item) onDeleteInclude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget header(String title, IconData icon, {VoidCallback? onAdd, String? countText}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall),
            const Spacer(),
            if (onAdd != null)
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: context.tr('Add module'),
                visualDensity: VisualDensity.compact,
                onPressed: onAdd,
              ),
            if (countText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  countText,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header(context.tr('Project settings'), Icons.settings_outlined),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.badge_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            title: Text(context.tr('Root project name')),
            subtitle: Text(
              (rootProjectName == null || rootProjectName!.isEmpty)
                  ? context.tr('Not set')
                  : rootProjectName!,
              style: TextStyle(
                fontFamily: (rootProjectName == null || rootProjectName!.isEmpty)
                    ? null
                    : 'monospace',
                fontSize: 12.5,
                color: (rootProjectName == null || rootProjectName!.isEmpty)
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: context.tr('Edit'),
              visualDensity: VisualDensity.compact,
              onPressed: onEditRootName,
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
          header(
            context.tr('Included projects'),
            Icons.account_tree_outlined,
            onAdd: onAddInclude,
            countText: '${includes.length}',
          ),
          Expanded(
            child: includes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      context.tr('No included projects found.'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: includes.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, index) {
                      final item = includes[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: context.tr('Edit'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onEditInclude(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: context.tr('Delete'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onDeleteInclude(item),
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

class _LineNumberGutter extends StatelessWidget {
  const _LineNumberGutter({
    required this.controller,
    required this.lineCount,
    required this.dark,
  });

  final ScrollController controller;
  final int lineCount;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final count = lineCount < 1 ? 1 : lineCount;
    final text = List<String>.generate(count, (i) => '${i + 1}').join('\n');
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: dark ? const Color(0xFF858585) : const Color(0xFF6E7681),
    );
    return SizedBox(
      width: 48,
      child: SingleChildScrollView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Padding(
          padding: const EdgeInsets.only(right: 8, left: 8),
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ),
    );
  }
}
