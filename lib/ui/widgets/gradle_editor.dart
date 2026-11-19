import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../build/build_client.dart';
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

  String _localizeValidationMessage(BuildContext ctx, String message) {
    final key = message.trim();
    const known = <String>{
      'Dependency not found in Maven Central',
      'Dependency version not found in Maven Central',
      'Group ID and Artifact ID are required',
      'Invalid dependency coordinates',
      'Plugin not found in Gradle Plugin Portal',
      'Plugin version not found in Gradle Plugin Portal',
      'Plugin ID is required',
      'Invalid plugin ID',
    };
    if (known.contains(key)) return ctx.tr(key);
    if (key.startsWith('Could not validate dependency')) {
      return ctx.tr('Could not validate dependency');
    }
    if (key.startsWith('Could not validate plugin')) {
      return ctx.tr('Could not validate plugin');
    }
    return message;
  }

  // ---------------------------- Dependencies ----------------------------

  Future<_GradleDependencyInput?> _showDependencyDialog({
    required String titleKey,
    _GradleDependencyInput? initial,
    bool isEdit = false,
  }) async {
    final notationCtrl = TextEditingController(text: initial?.notation ?? '');
    String configuration = initial?.configuration ?? 'implementation';
    if (!_configs.contains(configuration)) configuration = 'implementation';
    bool isPlatform = initial?.isPlatform ?? false;
    bool validating = false;
    String? errorText;

    final result = await showDialog<_GradleDependencyInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final notation = notationCtrl.text.trim();
              if (notation.isEmpty) {
                setDialogState(() {
                  errorText = dialogContext.tr('Dependency notation');
                });
                return;
              }
              setDialogState(() {
                validating = true;
                errorText = null;
              });
              try {
                final client = widget.controller.buildClient ?? BuildClient();
                await client.validateDependency(notation: notation);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(_GradleDependencyInput(
                  configuration: configuration,
                  notation: notation,
                  isPlatform: isPlatform,
                ));
              } catch (e) {
                if (!dialogContext.mounted) return;
                final msg = e is BuildException ? e.message : e.toString();
                setDialogState(() {
                  validating = false;
                  errorText = _localizeValidationMessage(dialogContext, msg);
                });
              }
            }

            return AlertDialog(
              title: Text(dialogContext.tr(titleKey)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      onChanged: validating
                          ? null
                          : (v) => setDialogState(
                              () => configuration = v ?? configuration),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notationCtrl,
                      enabled: !validating,
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
                      onChanged: validating
                          ? null
                          : (v) =>
                              setDialogState(() => isPlatform = v ?? false),
                      title: Text(dialogContext.tr('Platform (BOM)')),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                    if (validating) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                dialogContext.tr('Validating dependency...')),
                          ),
                        ],
                      ),
                    ],
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
                  onPressed: validating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(dialogContext.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: validating ? null : submit,
                  child: Text(dialogContext.tr(isEdit ? 'Save' : 'Add')),
                ),
              ],
            );
          },
        );
      },
    );
    notationCtrl.dispose();
    return result;
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
    if (start == null ||
        end == null ||
        start < 0 ||
        end > source.length ||
        start >= end) {
      return;
    }
    final line = _buildDependencyLine(input);
    final updated = source.replaceRange(start, end, '$line\n');
    _setSource(updated);
  }

  void _deleteGradleDependency(_GradleItem item) {
    _deleteGradleItem(item);
  }

  // ------------------------------ Plugins ------------------------------

  Future<_GradlePluginInput?> _showPluginDialog({
    required String titleKey,
    _GradlePluginInput? initial,
    bool isEdit = false,
  }) async {
    final idCtrl = TextEditingController(text: initial?.id ?? '');
    final versionCtrl = TextEditingController(text: initial?.version ?? '');
    bool validating = false;
    String? errorText;

    final result = await showDialog<_GradlePluginInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final id = idCtrl.text.trim();
              final version = versionCtrl.text.trim();
              if (id.isEmpty) {
                setDialogState(() {
                  errorText = dialogContext.tr('Plugin ID is required');
                });
                return;
              }
              setDialogState(() {
                validating = true;
                errorText = null;
              });
              try {
                final client = widget.controller.buildClient ?? BuildClient();
                await client.validatePlugin(id: id, version: version);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(_GradlePluginInput(
                  id: id,
                  version: version,
                ));
              } catch (e) {
                if (!dialogContext.mounted) return;
                final msg = e is BuildException ? e.message : e.toString();
                setDialogState(() {
                  validating = false;
                  errorText = _localizeValidationMessage(dialogContext, msg);
                });
              }
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
                      controller: idCtrl,
                      enabled: !validating,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Plugin ID'),
                        hintText: 'java / org.springframework.boot',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: versionCtrl,
                      enabled: !validating,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Plugin version'),
                        hintText: '3.3.5',
                      ),
                    ),
                    if (validating) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(dialogContext.tr('Validating plugin...')),
                          ),
                        ],
                      ),
                    ],
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
                  onPressed: validating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(dialogContext.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: validating ? null : submit,
                  child: Text(dialogContext.tr(isEdit ? 'Save' : 'Add')),
                ),
              ],
            );
          },
        );
      },
    );
    idCtrl.dispose();
    versionCtrl.dispose();
    return result;
  }

  Future<void> _showAddPluginDialog() async {
    final input = await _showPluginDialog(titleKey: 'Add plugin');
    if (input == null) return;
    _addGradlePlugin(input);
  }

  Future<void> _showEditPluginDialog(_GradleItem item) async {
    final input = await _showPluginDialog(
      titleKey: 'Edit plugin',
      initial: _GradlePluginInput(id: item.name, version: item.version),
      isEdit: true,
    );
    if (input == null) return;
    _replaceGradlePlugin(item, input);
  }

  String _buildPluginLine(_GradlePluginInput input) {
    final escapedId = input.id.replaceAll("'", "\\'");
    if (input.version.isNotEmpty) {
      final escapedVersion = input.version.replaceAll("'", "\\'");
      return "    id '$escapedId' version '$escapedVersion'";
    }
    return "    id '$escapedId'";
  }

  void _addGradlePlugin(_GradlePluginInput input) {
    final line = _buildPluginLine(input);
    var source = _text.text;
    final blockStartRe = RegExp(r'\bplugins\s*\{');
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
    // No plugins block found: prepend one.
    final prefix = 'plugins {\n$line\n}\n\n';
    _setSource('$prefix$source');
  }

  void _replaceGradlePlugin(_GradleItem item, _GradlePluginInput input) {
    final source = _text.text;
    final start = item.matchStart;
    final end = item.matchEnd;
    if (start == null ||
        end == null ||
        start < 0 ||
        end > source.length ||
        start >= end) {
      return;
    }
    final line = _buildPluginLine(input);
    final updated = source.replaceRange(start, end, '$line\n');
    _setSource(updated);
  }

  void _deleteGradlePlugin(_GradleItem item) {
    _deleteGradleItem(item);
  }

  void _deleteGradleItem(_GradleItem item) {
    final source = _text.text;
    final start = item.matchStart;
    final end = item.matchEnd;
    if (start == null ||
        end == null ||
        start < 0 ||
        end > source.length ||
        start >= end) {
      return;
    }
    final updated = source.replaceRange(start, end, '');
    _setSource(updated);
  }

  // ------------------------------- Parsing -------------------------------

  List<_GradleItem> _parseItems(String source) {
    if (source.trim().isEmpty) return const <_GradleItem>[];
    final items = <_GradleItem>[];

    // Plugins: id 'java' / id "java" version '1.0'
    final pluginRe = RegExp(
      '''^\\s*id\\s+['"]([^'"]+)['"](?:\\s+version\\s+['"]([^'"]+)['"])?[^\\n]*''',
      multiLine: true,
    );
    for (final m in pluginRe.allMatches(source)) {
      final id = (m.group(1) ?? '').trim();
      final version = (m.group(2) ?? '').trim();
      if (id.isEmpty) continue;

      var end = m.end;
      if (end < source.length && source[end] == '\r') end++;
      if (end < source.length && source[end] == '\n') end++;

      items.add(_GradleItem(
        kind: _GradleItemKind.plugin,
        name: id,
        detail: version.isEmpty ? '' : 'version: $version',
        version: version,
        configuration: '',
        isPlatform: false,
        matchStart: m.start,
        matchEnd: end,
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

      var end = m.end;
      if (end < source.length && source[end] == '\r') end++;
      if (end < source.length && source[end] == '\n') end++;

      items.add(_GradleItem(
        kind: _GradleItemKind.dependency,
        name: coord,
        detail: isPlatform ? '$config · platform' : config,
        version: '',
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
        final key = 'p:${it.name}:${it.version}:${it.matchStart ?? -1}';
        if (seenPlugins.add(key)) unique.add(it);
      } else {
        unique.add(it);
      }
    }
    return unique;
  }

  // --------------------------------- UI ---------------------------------

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
                          onAddPlugin: _showAddPluginDialog,
                          onEditPlugin: _showEditPluginDialog,
                          onDeletePlugin: _deleteGradlePlugin,
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

class _GradlePluginInput {
  const _GradlePluginInput({
    required this.id,
    required this.version,
  });

  final String id;
  final String version;
}

enum _GradleItemKind { plugin, dependency }

class _GradleItem {
  const _GradleItem({
    required this.kind,
    required this.name,
    required this.detail,
    required this.version,
    required this.configuration,
    required this.isPlatform,
    this.matchStart,
    this.matchEnd,
  });

  final _GradleItemKind kind;
  final String name;
  final String detail;
  final String version;
  final String configuration;
  final bool isPlatform;
  final int? matchStart;
  final int? matchEnd;
}

class _GradlePanel extends StatelessWidget {
  const _GradlePanel({
    required this.items,
    this.onAddPlugin,
    this.onEditPlugin,
    this.onDeletePlugin,
    this.onAddDependency,
    this.onEditDependency,
    this.onDeleteDependency,
  });

  final List<_GradleItem> items;
  final VoidCallback? onAddPlugin;
  final void Function(_GradleItem item)? onEditPlugin;
  final void Function(_GradleItem item)? onDeletePlugin;
  final VoidCallback? onAddDependency;
  final void Function(_GradleItem item)? onEditDependency;
  final void Function(_GradleItem item)? onDeleteDependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugins =
        items.where((i) => i.kind == _GradleItemKind.plugin).toList();
    final deps =
        items.where((i) => i.kind == _GradleItemKind.dependency).toList();

    Widget header(
      String title,
      int count,
      IconData icon, {
      VoidCallback? onAdd,
      String addTooltipKey = 'Add dependency',
    }) {
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
                tooltip: context.tr(addTooltipKey),
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

    Widget itemTile(_GradleItem item) {
      final isPlugin = item.kind == _GradleItemKind.plugin;
      final canEdit = item.matchStart != null &&
          ((isPlugin && onEditPlugin != null) ||
              (!isPlugin && onEditDependency != null));
      final canDelete = item.matchStart != null &&
          ((isPlugin && onDeletePlugin != null) ||
              (!isPlugin && onDeleteDependency != null));
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
                      tooltip: context
                          .tr(isPlugin ? 'Edit plugin' : 'Edit dependency'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => isPlugin
                          ? onEditPlugin!(item)
                          : onEditDependency!(item),
                    ),
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: context.tr('Delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => isPlugin
                          ? onDeletePlugin!(item)
                          : onDeleteDependency!(item),
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
          header(
            context.tr('Plugins'),
            plugins.length,
            Icons.extension_outlined,
            onAdd: onAddPlugin,
            addTooltipKey: 'Add plugin',
          ),
          if (plugins.isEmpty)
            empty(context.tr('No plugins found.'))
          else
            ...plugins.map(itemTile),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
          header(
            context.tr('Dependencies'),
            deps.length,
            Icons.account_tree_outlined,
            onAdd: onAddDependency,
            addTooltipKey: 'Add dependency',
          ),
          Expanded(
            child: deps.isEmpty
                ? empty(context.tr('No dependencies found.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: deps.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, index) => itemTile(deps[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
