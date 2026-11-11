import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../../editor/code_validator.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

/// Editor for Maven `pom.xml` with a live list of dependencies on the right.
class PomEditor extends StatefulWidget {
  const PomEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<PomEditor> createState() => _PomEditorState();
}

class _PomEditorState extends State<PomEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.codeContent);
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
      setState(() {});
    }
  }

  void _onChanged() {
    setState(() {
      _validation = _validate(_text.text);
    });
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  List<_MavenDependency> _parseDependencies(String source) {
    if (source.trim().isEmpty) return const <_MavenDependency>[];
    try {
      final doc = XmlDocument.parse(source);
      final deps = <_MavenDependency>[];
      for (final dep in doc.findAllElements('dependency')) {
        final inMgmt = dep.ancestors.any((n) =>
            n is XmlElement && n.name.local == 'dependencyManagement');
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
                const minPreview = 200.0;
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
  const _DependenciesPanel({required this.dependencies, required this.theme});

  final List<_MavenDependency> dependencies;
  final ThemeData theme;

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
        '${first.line}:${first.column} ${first.message}',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onErrorContainer,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
