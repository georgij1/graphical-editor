import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

/// Editor for Gradle build files (`build.gradle`) with a graphical panel
/// showing plugins and dependencies.
class GradleEditor extends StatefulWidget {
  const GradleEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<GradleEditor> createState() => _GradleEditorState();
}

class _GradleEditorState extends State<GradleEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.codeContent);
  final FocusNode _focusNode = FocusNode();
  int _lastEpoch = 0;
  double _previewFraction = 0.45;

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
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.codeEpoch;
    if (epoch != _lastEpoch) {
      _lastEpoch = epoch;
      _text.text = widget.controller.codeContent;
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {});
  }

  bool _apply() {
    final ok = widget.controller.applyCode(_text.text);
    _showMessage(
        ok ? context.tr('Source applied.') : context.tr('Apply failed.'));
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
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  static const List<String> _configs = <String>[
    'implementation',
    'api',
    'compileOnly',
    'runtimeOnly',
    'testImplementation',
    'testCompileOnly',
    'testRuntimeOnly',
    'annotationProcessor',
  ];

  Future<_GradleDependencyInput?> _showDependencyDialog({
    required String titleKey,
    _GradleDependencyInput? initial,
    bool isEdit = false,
  }) async {
    final notationCtrl = TextEditingController(text: initial?.notation ?? '');
    String configuration = initial?.configuration ?? 'implementation';
    if (!_configs.contains(configuration)) configuration = 'implementation';
    bool isPlatform = initial?.isPlatform ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(dialogContext.tr(titleKey)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('config-$configuration'),
                    initialValue: configuration,
                    decoration: InputDecoration(
                      labelText: dialogContext.tr('Configuration'),
                    ),
                    items: [
                      for (final c in _configs)
                        DropdownMenuItem<String>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => configuration = v ?? configuration),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notationCtrl,
                    decoration: InputDecoration(
                      labelText: dialogContext.tr('Dependency notation'),
                      hintText: 'group:artifact:version',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isPlatform,
                    onChanged: (v) =>
                        setDialogState(() => isPlatform = v ?? false),
                    title: Text(dialogContext.tr('Platform (BOM)')),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(dialogContext.tr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(dialogContext.tr(isEdit ? 'Save' : 'Add')),
              ),
            ],
          ),
        );
      },
    );
    if (result != true) {
      notationCtrl.dispose();
      return null;
    }
    final notation = notationCtrl.text.trim();
    notationCtrl.dispose();
    if (notation.isEmpty) return null;
    return _GradleDependencyInput(
      configuration: configuration,
      notation: notation,
      isPlatform: isPlatform,
    );
  }

  Future<void> _showAddDependencyDialog() async {
    final input = await _showDependencyDialog(titleKey: 'Add dependency');
    if (input == null) return;
    _addGradleDependency(input);
  }

  Future<void> _showEditDependencyDialog(_GradleItem item) async {
    final input = await _showDependencyDialog(
      titleKey: 'Edit dependency',
      initial: _GradleDependencyInput(
        configuration: item.configuration,
        notation: item.name,
        isPlatform: item.isPlatform,
      ),
      isEdit: true,
    );
    if (input == null) return;
    _replaceGradleDependency(item, input);
  }

  String _buildDependencyLine(_GradleDependencyInput input) {
    final escaped = input.notation.replaceAll("'", "\\'");
    if (input.isPlatform) {
      return "    ${input.configuration} platform('$escaped')";
    }
    return "    ${input.configuration} '$escaped'";
  }

  void _addGradleDependency(_GradleDependencyInput input) {
    final line = _buildDependencyLine(input);
    var source = _text.text;
    final blockStartRe = RegExp(r'\bdependencies\s*\{');
    final m = blockStartRe.firstMatch(source);
    if (m != null) {
      final openBrace = source.indexOf('{', m.start);
      if (openBrace >= 0) {
        var depth = 0;
        var closeBrace = -1;
        for (var i = openBrace; i < source.length; i++) {
          final ch = source[i];
          if (ch == '{') depth++;
          if (ch == '}') {
            depth--;
            if (depth == 0) {
              closeBrace = i;
              break;
            }
          }
        }
        if (closeBrace >= 0) {
          final before = source.substring(0, closeBrace);
          final after = source.substring(closeBrace);
          final needsNl = before.isNotEmpty && !before.endsWith('\n');
          source = '$before${needsNl ? '\n' : ''}$line\n$after';
          _setSource(source);
          return;
        }
      }
    }
    // No dependencies block found: append one.
    final suffix = source.endsWith('\n') || source.isEmpty ? '' : '\n';
    source = '$source$suffix\ndependencies {\n$line\n}\n';
    _setSource(source);
  }

  void _replaceGradleDependency(_GradleItem item, _GradleDependencyInput input) {
    final source = _text.text;
    final start = item.matchStart;
    final end = item.matchEnd;
    if (start == null || end == null || start < 0 || end > source.length || start >= end) {
      return;
    }
    final line = _buildDependencyLine(input);
    // matchEnd is set to end-of-line (after newline if present) in parser,
    // so replacing with "line\n" keeps structure stable.
    final updated = source.replaceRange(start, end, '$line\n');
    _setSource(updated);
  }

  void _deleteGradleDependency(_GradleItem item) {
    final source = _text.text;
    final start = item.matchStart;
    final end = item.matchEnd;
    if (start == null || end == null || start < 0 || end > source.length || start >= end) {
      return;
    }
    final updated = source.replaceRange(start, end, '');
    _setSource(updated);
  }

  List<_GradleItem> _parseItems(String source) {
    if (source.trim().isEmpty) return const <_GradleItem>[];
    final items = <_GradleItem>[];

    // Plugins: id 'java' / id "java" version '1.0'
    final pluginRe = RegExp(
      '''^\\s*id\\s+['"]([^'"]+)['"](?:\\s+version\\s+['"]([^'"]+)['"])?''',
      multiLine: true,
    );
    for (final m in pluginRe.allMatches(source)) {
      final id = (m.group(1) ?? '').trim();
      final version = (m.group(2) ?? '').trim();
      if (id.isEmpty) continue;
      items.add(_GradleItem(
        kind: _GradleItemKind.plugin,
        name: id,
        detail: version.isEmpty ? '' : 'version: $version',
        configuration: '',
        isPlatform: false,
      ));
    }

    // Dependencies: configuration 'group:artifact:version' or with platform(...)
    final depLineRe = RegExp(
      r'''^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(?:platform\(\s*)?['"]([^'"]+)['"]\s*\)?[^\n]*''',
      multiLine: true,
    );
    const depConfigs = <String>{
      'implementation',
      'api',
      'compileOnly',
      'runtimeOnly',
      'testImplementation',
      'testCompileOnly',
      'testRuntimeOnly',
      'annotationProcessor',
      'kapt',
      'classpath',
    };
    for (final m in depLineRe.allMatches(source)) {
      final config = (m.group(1) ?? '').trim();
      final coord = (m.group(2) ?? '').trim();
      if (!depConfigs.contains(config)) continue;
      if (coord.isEmpty) continue;
      final isPlatform = m.group(0)?.contains('platform(') ?? false;

      // Compute range covering the whole line including trailing newline if present.
      var start = m.start;
      // include leading indentation/newline start already at line start due to ^ with multiLine
      // find line start (in case)
      while (start > 0 && source[start - 1] != '\n' && source[start - 1] != '\r') {
        // keep going back only if regex didn't anchor at line start; but ^ should.
        break;
      }
      var end = m.end;
      if (end < source.length && source[end] == '\r') end++;
      if (end < source.length && source[end] == '\n') end++;

      items.add(_GradleItem(
        kind: _GradleItemKind.dependency,
        name: coord,
        detail: isPlatform ? '$config · platform' : config,
        configuration: config,
        isPlatform: isPlatform,
        matchStart: m.start,
        matchEnd: end,
      ));
    }

    // De-duplicate plugins only (keep dependencies as distinct editable entries).
    final seenPlugins = <String>{};
    final unique = <_GradleItem>[];
    for (final it in items) {
      if (it.kind == _GradleItemKind.plugin) {
        final key = 'p:${it.name}:${it.detail}';
        if (seenPlugins.add(key)) unique.add(it);
      } else {
        unique.add(it);
      }
    }
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final items = _parseItems(_text.text);

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
                              setState(() => _previewFraction = 0.45),
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _previewFraction = ((_previewFraction * usable -
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
                        child: _GradlePanel(
                          items: items,
                          onAddDependency: _showAddDependencyDialog,
                          onEditDependency: _showEditDependencyDialog,
                          onDeleteDependency: _deleteGradleDependency,
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

class _GradleDependencyInput {
  const _GradleDependencyInput({
    required this.configuration,
    required this.notation,
    required this.isPlatform,
  });

  final String configuration;
  final String notation;
  final bool isPlatform;
}

enum _GradleItemKind { plugin, dependency }

class _GradleItem {
  const _GradleItem({
    required this.kind,
    required this.name,
    required this.detail,
    required this.configuration,
    required this.isPlatform,
    this.matchStart,
    this.matchEnd,
  });

  final _GradleItemKind kind;
  final String name;
  final String detail;
  final String configuration;
  final bool isPlatform;
  final int? matchStart;
  final int? matchEnd;
}

class _GradlePanel extends StatelessWidget {
  const _GradlePanel({
    required this.items,
    this.onAddDependency,
    this.onEditDependency,
    this.onDeleteDependency,
  });

  final List<_GradleItem> items;
  final VoidCallback? onAddDependency;
  final void Function(_GradleItem item)? onEditDependency;
  final void Function(_GradleItem item)? onDeleteDependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugins = items.where((i) => i.kind == _GradleItemKind.plugin).toList();
    final deps = items.where((i) => i.kind == _GradleItemKind.dependency).toList();

    Widget header(String title, int count, IconData icon,
        {VoidCallback? onAdd}) {
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
                tooltip: context.tr('Add dependency'),
                visualDensity: VisualDensity.compact,
                onPressed: onAdd,
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
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

    Widget empty(String text) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    Widget itemTile(_GradleItem item, {bool editable = false}) {
      final isPlugin = item.kind == _GradleItemKind.plugin;
      final canEdit = editable && onEditDependency != null && item.matchStart != null;
      final canDelete =
          editable && onDeleteDependency != null && item.matchStart != null;
      return ListTile(
        dense: true,
        leading: Icon(
          isPlugin ? Icons.extension : Icons.account_tree_outlined,
          size: 18,
          color: isPlugin
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary,
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
          ),
        ),
        subtitle: item.detail.isEmpty
            ? null
            : Text(
                item.detail,
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: (canEdit || canDelete)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: context.tr('Edit dependency'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onEditDependency!(item),
                    ),
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: context.tr('Delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDeleteDependency!(item),
                    ),
                ],
              )
            : null,
      );
    }

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header(context.tr('Plugins'), plugins.length, Icons.extension_outlined),
          if (plugins.isEmpty)
            empty(context.tr('No plugins found.'))
          else
            ...plugins.map((p) => itemTile(p)),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
          header(context.tr('Dependencies'), deps.length,
              Icons.account_tree_outlined,
              onAdd: onAddDependency),
          Expanded(
            child: deps.isEmpty
                ? empty(context.tr('No dependencies found.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: deps.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, index) =>
                        itemTile(deps[index], editable: true),
                  ),
          ),
        ],
      ),
    );
  }
}
