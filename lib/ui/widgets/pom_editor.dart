import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../../build/build_client.dart';
import '../../editor/code_validator.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'highlighting_text_controller.dart';

/// Editor for Maven `pom.xml` with a live list of dependencies on the right.
class PomEditor extends StatefulWidget {
  const PomEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<PomEditor> createState() => _PomEditorState();
}

class _PomEditorState extends State<PomEditor> {
  late final HighlightingTextEditingController _text =
      HighlightingTextEditingController(
    text: widget.controller.codeContent,
    language: HighlightLanguage.xml,
  );
  final FocusNode _focusNode = FocusNode();
  int _lastEpoch = 0;
  double _previewFraction = 0.45;
  late ValidationResult _validation = _validate(_text.text);

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _text.addListener(_onChanged);
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHighlighting();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHighlighting();
  }

  void _syncHighlighting() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final changed = _text.dark != dark || _text.language != HighlightLanguage.xml;
    _text.dark = dark;
    _text.language = HighlightLanguage.xml;
    if (changed) _text.refresh();
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
      _validation = _validate(_text.text);
      _syncHighlighting();
      setState(() {});
    } else {
      _syncHighlighting();
    }
  }

  void _onChanged() {
    setState(() {
      _validation = _validate(_text.text);
    });
    widget.controller.applyCode(_text.text);
  }

  ValidationResult _validate(String source) {
    if (source.trim().isEmpty) {
      return ValidationResult(const <ValidationIssue>[]);
    }
    try {
      XmlDocument.parse(source);
      return ValidationResult(const <ValidationIssue>[]);
    } catch (e) {
      int? line;
      int? column;
      try {
        final d = e as dynamic;
        final l = d.line;
        final c = d.column;
        if (l is int && l > 0) line = l;
        if (c is int && c > 0) column = c;
      } catch (_) {}
      return ValidationResult(<ValidationIssue>[
        ValidationIssue(
          e.toString(),
          line: line,
          column: column,
        ),
      ]);
    }
  }

  bool _apply() {
    if (_validation.hasErrors) {
      final error = _validation.errors.first;
      _showMessage(error.render(context.tr));
      return false;
    }
    final ok = widget.controller.applyCode(_text.text);
    setState(() {
      _validation = _validate(_text.text);
    });
    _showMessage(ok ? context.tr('Source applied.') : context.tr('Apply failed.'));
    return ok;
  }

  void _setSource(String source, {bool apply = true}) {
    _text.text = source;
    setState(() {
      _validation = _validate(_text.text);
    });
    if (apply) {
      // Best effort apply so the list/state stays in sync.
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

  static const List<String> _scopes = <String>[
    '',
    'compile',
    'provided',
    'runtime',
    'test',
    'system',
    'import',
  ];

  String _localizeValidationMessage(BuildContext ctx, String message) {
    final key = message.trim();
    const known = <String>{
      'Dependency not found in Maven Central',
      'Dependency version not found in Maven Central',
      'Group ID and Artifact ID are required',
      'Invalid dependency coordinates',
    };
    if (known.contains(key)) return ctx.tr(key);
    if (key.startsWith('Could not validate dependency')) {
      return ctx.tr('Could not validate dependency');
    }
    return message;
  }

  Future<_MavenDependencyInput?> _showDependencyDialog({
    required String titleKey,
    _MavenDependency? initial,
  }) async {
    final groupCtrl = TextEditingController(text: initial?.groupId ?? '');
    final artifactCtrl = TextEditingController(text: initial?.artifactId ?? '');
    final versionCtrl = TextEditingController(text: initial?.version ?? '');
    String scope = initial?.scope ?? '';
    if (!_scopes.contains(scope)) scope = '';
    bool validating = false;
    String? errorText;

    final result = await showDialog<_MavenDependencyInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final groupId = groupCtrl.text.trim();
              final artifactId = artifactCtrl.text.trim();
              final version = versionCtrl.text.trim();
              if (groupId.isEmpty || artifactId.isEmpty) {
                setDialogState(() {
                  errorText = dialogContext.tr('Group ID and Artifact ID are required');
                });
                return;
              }
              setDialogState(() {
                validating = true;
                errorText = null;
              });
              try {
                final client = widget.controller.buildClient ?? BuildClient();
                await client.validateDependency(
                  groupId: groupId,
                  artifactId: artifactId,
                  version: version,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(_MavenDependencyInput(
                  groupId: groupId,
                  artifactId: artifactId,
                  version: version,
                  scope: scope.trim(),
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
                      controller: groupCtrl,
                      enabled: !validating,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Group ID'),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: artifactCtrl,
                      enabled: !validating,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Artifact ID'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: versionCtrl,
                      enabled: !validating,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Version'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('scope-$scope'),
                      initialValue: scope,
                      decoration: InputDecoration(
                        labelText: dialogContext.tr('Scope'),
                      ),
                      items: [
                        for (final s in _scopes)
                          DropdownMenuItem<String>(
                            value: s,
                            child: Text(s.isEmpty ? '-' : s),
                          ),
                      ],
                      onChanged: validating
                          ? null
                          : (v) => setDialogState(() => scope = v ?? ''),
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
                            child: Text(dialogContext.tr('Validating dependency...')),
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
                  onPressed:
                      validating ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(dialogContext.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: validating ? null : submit,
                  child: Text(dialogContext.tr(initial == null ? 'Add' : 'Save')),
                ),
              ],
            );
          },
        );
      },
    );
    groupCtrl.dispose();
    artifactCtrl.dispose();
    versionCtrl.dispose();
    return result;
  }

  Future<void> _showAddDependencyDialog() async {
    final input = await _showDependencyDialog(titleKey: 'Add dependency');
    if (input == null) return;
    _addMavenDependency(input);
  }

  Future<void> _showEditDependencyDialog(int index, _MavenDependency dep) async {
    final input =
        await _showDependencyDialog(titleKey: 'Edit dependency', initial: dep);
    if (input == null) return;
    _replaceMavenDependency(index, input, existing: dep);
  }

  String _buildDependencyXml(_MavenDependencyInput input,
      {_MavenDependency? existing}) {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    final type = existing?.type ?? '';
    final optional = existing?.optional ?? '';

    final buf = StringBuffer();
    buf.writeln('        <dependency>');
    buf.writeln('            <groupId>${esc(input.groupId)}</groupId>');
    buf.writeln('            <artifactId>${esc(input.artifactId)}</artifactId>');
    if (input.version.isNotEmpty) {
      buf.writeln('            <version>${esc(input.version)}</version>');
    }
    if (type.isNotEmpty) {
      buf.writeln('            <type>${esc(type)}</type>');
    }
    if (input.scope.isNotEmpty) {
      buf.writeln('            <scope>${esc(input.scope)}</scope>');
    }
    if (optional.isNotEmpty) {
      buf.writeln('            <optional>${esc(optional)}</optional>');
    }
    buf.write('        </dependency>');
    return buf.toString();
  }

  void _addMavenDependency(_MavenDependencyInput input) {
    final depBlock = _buildDependencyXml(input);
    var source = _text.text;
    final depsClose = RegExp(r'^(\s*)</dependencies>', multiLine: true);
    final m = depsClose.firstMatch(source);
    if (m != null) {
      final insertAt = m.start;
      final needsNl = insertAt > 0 && source[insertAt - 1] != '\n';
      source = source.replaceRange(
        insertAt,
        insertAt,
        '${needsNl ? '\n' : ''}$depBlock\n',
      );
    } else {
      final projectClose = RegExp(r'^(\s*)</project>', multiLine: true);
      final pm = projectClose.firstMatch(source);
      final block = '    <dependencies>\n$depBlock\n    </dependencies>\n';
      if (pm != null) {
        source = source.replaceRange(pm.start, pm.start, block);
      } else {
        source = '$source\n$block';
      }
    }
    _setSource(source);
  }

  List<RegExpMatch> _dependencyMatches(String source) {
    final depRe = RegExp(r'<dependency>.*?</dependency>', dotAll: true);
    return depRe.allMatches(source).toList();
  }

  void _replaceMavenDependency(int index, _MavenDependencyInput input,
      {_MavenDependency? existing}) {
    final source = _text.text;
    final matches = _dependencyMatches(source);
    if (index < 0 || index >= matches.length) return;
    final m = matches[index];
    final replacement = _buildDependencyXml(input, existing: existing);
    final updated = source.replaceRange(m.start, m.end, replacement);
    _setSource(updated);
  }

  void _deleteMavenDependency(int index) {
    final source = _text.text;
    final matches = _dependencyMatches(source);
    if (index < 0 || index >= matches.length) return;
    final m = matches[index];
    var start = m.start;
    var end = m.end;
    // Remove surrounding line break/indentation nicely.
    if (end < source.length && source[end] == '\r') end++;
    if (end < source.length && source[end] == '\n') end++;
    // If previous chars are only whitespace on the line, trim them too.
    var lineStart = start;
    while (lineStart > 0 && source[lineStart - 1] != '\n' && source[lineStart - 1] != '\r') {
      lineStart--;
    }
    final prefix = source.substring(lineStart, start);
    if (prefix.trim().isEmpty) {
      start = lineStart;
    }
    final updated = source.replaceRange(start, end, '');
    _setSource(updated);
  }

  List<_MavenDependency> _parseDependencies(String source) {
    if (source.trim().isEmpty) return const <_MavenDependency>[];
    try {
      final doc = XmlDocument.parse(source);
      final deps = <_MavenDependency>[];
      for (final dep in doc.findAllElements('dependency')) {
        final inMgmt = dep.ancestors
            .any((n) => n is XmlElement && n.name.local == 'dependencyManagement');
        deps.add(_MavenDependency(
          groupId: _childText(dep, 'groupId'),
          artifactId: _childText(dep, 'artifactId'),
          version: _childText(dep, 'version'),
          scope: _childText(dep, 'scope'),
          type: _childText(dep, 'type'),
          optional: _childText(dep, 'optional'),
          managed: inMgmt,
        ));
      }
      return deps;
    } catch (_) {
      return _parseDependenciesRegex(source);
    }
  }

  String _childText(XmlElement parent, String name) {
    final el = parent.getElement(name);
    return el?.innerText.trim() ?? '';
  }

  List<_MavenDependency> _parseDependenciesRegex(String source) {
    final deps = <_MavenDependency>[];
    final depRe = RegExp(r'<dependency>(.*?)</dependency>', dotAll: true);
    for (final m in depRe.allMatches(source)) {
      final block = m.group(1) ?? '';
      String tag(String name) {
        final r = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(block);
        return r?.group(1)?.trim() ?? '';
      }
      deps.add(_MavenDependency(
        groupId: tag('groupId'),
        artifactId: tag('artifactId'),
        version: tag('version'),
        scope: tag('scope'),
        type: tag('type'),
        optional: tag('optional'),
        managed: false,
      ));
    }
    return deps;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final deps = _parseDependencies(_text.text);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PomValidationBar(validation: _validation),
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
                        child: _DependenciesPanel(
                          dependencies: deps,
                          theme: theme,
                          onAdd: _showAddDependencyDialog,
                          onEdit: (i, d) => _showEditDependencyDialog(i, d),
                          onDelete: (i) => _deleteMavenDependency(i),
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

class _MavenDependencyInput {
  const _MavenDependencyInput({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.scope,
  });

  final String groupId;
  final String artifactId;
  final String version;
  final String scope;
}

class _MavenDependency {
  const _MavenDependency({
    required this.groupId,
    required this.artifactId,
    required this.version,
    required this.scope,
    required this.type,
    required this.optional,
    required this.managed,
  });

  final String groupId;
  final String artifactId;
  final String version;
  final String scope;
  final String type;
  final String optional;
  final bool managed;

  String get coordinate {
    final g = groupId.isEmpty ? '?' : groupId;
    final a = artifactId.isEmpty ? '?' : artifactId;
    final v = version.isEmpty ? '' : ':$version';
    return '$g:$a$v';
  }
}

class _DependenciesPanel extends StatelessWidget {
  const _DependenciesPanel({
    required this.dependencies,
    required this.theme,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  final List<_MavenDependency> dependencies;
  final ThemeData theme;
  final VoidCallback? onAdd;
  final void Function(int index, _MavenDependency dep)? onEdit;
  final void Function(int index)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.account_tree_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  context.tr('Dependencies'),
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (onAdd != null)
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: context.tr('Add dependency'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onAdd,
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${dependencies.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: dependencies.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.tr('No dependencies found.'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: dependencies.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, index) {
                      final d = dependencies[index];
                      final details = <String>[
                        if (d.scope.isNotEmpty) 'scope: ${d.scope}',
                        if (d.type.isNotEmpty && d.type != 'jar')
                          'type: ${d.type}',
                        if (d.optional == 'true') 'optional',
                        if (d.managed) context.tr('dependencyManagement'),
                      ];
                      final canEdit = !d.managed && onEdit != null;
                      final canDelete = !d.managed && onDelete != null;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.extension_outlined,
                          size: 18,
                          color: d.managed
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                        ),
                        title: Text(
                          d.coordinate,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          ),
                        ),
                        subtitle: details.isEmpty
                            ? null
                            : Text(
                                details.join(' · '),
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
                                      onPressed: () => onEdit!(index, d),
                                    ),
                                  if (canDelete)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      tooltip: context.tr('Delete'),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => onDelete!(index),
                                    ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PomValidationBar extends StatelessWidget {
  const _PomValidationBar({required this.validation});

  final ValidationResult validation;

  @override
  Widget build(BuildContext context) {
    if (!validation.hasErrors) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final first = validation.errors.first;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '${first.line ?? ''}:${first.column ?? ''} ${first.message}',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onErrorContainer,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
