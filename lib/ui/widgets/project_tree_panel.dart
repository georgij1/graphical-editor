import 'dart:convert';

import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/build_files.dart';
import '../../project/java_generator.dart';
import '../../project/project.dart';
import 'project_dialogs.dart';

/// Full project tree: the JavaFX application laid out like a real source tree
/// (`src/main/java/...` for the launcher + controllers and
/// `src/main/resources/...` for the FXML scenes).
class ProjectTreePanel extends StatefulWidget {
  const ProjectTreePanel({
    super.key,
    required this.controller,
    required this.onRenameScene,
    required this.onDeleteScene,
  });

  final EditorController controller;
  final void Function(SceneFile scene) onRenameScene;
  final void Function(SceneFile scene) onDeleteScene;

  @override
  State<ProjectTreePanel> createState() => _ProjectTreePanelState();
}

class _ProjectTreePanelState extends State<ProjectTreePanel> {
  final Set<String> _collapsed = <String>{};

  EditorController get controller => widget.controller;

  bool _isCollapsed(String path) => _collapsed.contains(path);

  /// Wraps [child] so a right mouse click shows [items] as a Flutter context
  /// menu instead of the browser's default one.
  Widget _contextMenu(
    BuildContext context,
    Widget child,
    List<PopupMenuEntry<int>> items,
    void Function(int) onSelected,
  ) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        final position = RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy,
        );
        showMenu<int>(context: context, position: position, items: items).then((
          value,
        ) {
          if (!mounted) return;
          if (value != null) onSelected(value);
        });
      },
      child: child,
    );
  }

  void _toggle(String path) {
    setState(() {
      if (_collapsed.contains(path)) {
        _collapsed.remove(path);
      } else {
        _collapsed.add(path);
      }
    });
  }

  void _collectDirs(_DirNode dir, Set<String> out) {
    out.add(dir.path);
    for (final child in dir.dirs.values) {
      _collectDirs(child, out);
    }
  }

  void _collapseAll(_DirNode dir) {
    setState(() {
      _collectDirs(dir, _collapsed);
    });
  }

  void _expandAll(_DirNode dir) {
    setState(() {
      _collapsed.clear();
    });
  }

  bool _allCollapsed(_DirNode dir, {bool isRoot = false}) {
    if (!isRoot && !_collapsed.contains(dir.path)) return false;
    for (final child in dir.dirs.values) {
      if (!_allCollapsed(child)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final project = controller.currentProject;
    if (project == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      physics: const ClampingScrollPhysics(),
      child: ListenableBuilder(
        // The tree content (folders, Java sources, scenes) is derived from
        // the model, so it must rebuild with every controller change —
        // renaming a class, a scene, adding files and so on.
        listenable: controller,
        builder: (context, _) {
          final projectNow = controller.currentProject ?? project;
          final root = _buildTree(projectNow);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Builder(
                builder: (context) {
                  final allCollapsed = _allCollapsed(root, isRoot: true);
                  final label = allCollapsed
                      ? context.tr('Expand all')
                      : context.tr('Collapse all');
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: label,
                          icon: Icon(
                            allCollapsed
                                ? Icons.unfold_more
                                : Icons.unfold_less,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (allCollapsed) {
                              _expandAll(root);
                            } else {
                              _collapseAll(root);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        Text(label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ..._renderChildren(context, projectNow, root, 0),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- tree model

  _DirNode _buildTree(Project project) {
    final root = _DirNode(project.name, project.name);

    void addFile(
      String path, {
      String? content,
      SceneFile? scene,
      required bool isJava,
      bool isBuildFile = false,
      bool isXml = false,
    }) {
      final parts = path.split('/');
      var dir = root;
      for (final part in parts.sublist(0, parts.length - 1)) {
        dir = dir.dirs.putIfAbsent(
          part,
          () => _DirNode(part, '${dir.path}/$part'),
        );
      }
      dir.files.add(
        _FileNode(
          name: parts.last,
          path: path,
          content: content,
          scene: scene,
          isJava: isJava,
          isBuildFile: isBuildFile,
          isXml: isXml,
        ),
      );
    }

    for (final source in JavaGenerator.generate(project)) {
      addFile(source.path, content: source.content, isJava: true);
    }
    for (final file in const BuildFiles().generate(project, BuildTool.maven)) {
      addFile(
        file.path,
        content: project.sourceOverrides[file.path] ?? file.content,
        isJava: false,
        isBuildFile: true,
        isXml: file.path.endsWith('.xml'),
      );
    }
    addFile(
      'project.json',
      content: const JsonEncoder.withIndent('  ').convert(project.toJson()),
      isJava: false,
      isBuildFile: true,
    );
    final pkgDir = JavaGenerator.packageDir(project);
    for (final scene in project.scenes) {
      addFile(
        'src/main/resources/$pkgDir/${scene.name}.fxml',
        content: scene.fxml,
        scene: scene,
        isJava: false,
        isXml: true,
      );
    }
    return root;
  }

  // ----------------------------------------------------------------- rendering

  List<Widget> _renderChildren(
    BuildContext context,
    Project project,
    _DirNode dir,
    int depth,
  ) {
    final widgets = <Widget>[
      for (final child in _sortedDirs(dir))
        _directoryTile(context, project, child, depth),
      // Файлы отображаются на один уровень глубже родительской папки,
      // как в обычном IDE: папка «содержит» файлы, поэтому они сдвинуты вправо.
      for (final file in _sortedFiles(dir))
        _fileTile(context, project, file, depth + 1),
    ];
    return widgets;
  }

  List<_DirNode> _sortedDirs(_DirNode dir) {
    final dirs = dir.dirs.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return dirs;
  }

  List<_FileNode> _sortedFiles(_DirNode dir) {
    final files = dir.files.toList()..sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  Widget _directoryTile(
    BuildContext context,
    Project project,
    _DirNode dir,
    int depth,
  ) {
    final empty = dir.dirs.isEmpty && dir.files.isEmpty;
    final collapsed = _isCollapsed(dir.path);

    final tile = InkWell(
      onTap: empty ? null : () => _toggle(dir.path),
      child: Padding(
        padding: EdgeInsets.only(
          left: 6 + depth * 14.0,
          right: 6,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: <Widget>[
            if (!empty)
              _contextMenu(
                context,
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                ),
                <PopupMenuEntry<int>>[
                  PopupMenuItem<int>(
                    value: 1,
                    child: Text(context.tr('New scene')),
                  ),
                  PopupMenuItem<int>(
                    value: 2,
                    child: Text(context.tr('New folder')),
                  ),
                  PopupMenuItem<int>(
                    value: 3,
                    child: Text(context.tr('New file')),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<int>(
                    value: 4,
                    child: Text(context.tr('Rename')),
                  ),
                  PopupMenuItem<int>(
                    value: 5,
                    child: Text(context.tr('Delete')),
                  ),
                ],
                (value) async {
                  if (value == 1) {
                    final name = await showPromptDialog(
                      context,
                      title: context.tr('New scene'),
                      initial: 'scene',
                    );
                    if (!mounted) return;
                    if (name != null && name.trim().isNotEmpty) {
                      controller.newScene(name);
                    }
                  } else if (value == 2) {
                    _say(
                      context,
                      context.tr('Folder creation is not supported yet.'),
                    );
                  } else if (value == 3) {
                    _say(
                      context,
                      context.tr('File creation is not supported yet.'),
                    );
                  } else if (value == 4) {
                    _say(
                      context,
                      context.tr('Folder rename is not supported yet.'),
                    );
                  } else if (value == 5) {
                    _say(
                      context,
                      context.tr('Folder deletion is not supported yet.'),
                    );
                  }
                },
              ),
            if (!empty) const SizedBox(width: 2),
            const Icon(Icons.folder_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dir.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final menuTile = empty
        ? tile
        : _contextMenu(
            context,
            tile,
            <PopupMenuEntry<int>>[
              PopupMenuItem<int>(
                value: 1,
                child: Text(context.tr('New scene')),
              ),
              PopupMenuItem<int>(
                value: 2,
                child: Text(context.tr('New folder')),
              ),
              PopupMenuItem<int>(value: 3, child: Text(context.tr('New file'))),
              const PopupMenuDivider(),
              PopupMenuItem<int>(value: 4, child: Text(context.tr('Rename'))),
              PopupMenuItem<int>(value: 5, child: Text(context.tr('Delete'))),
            ],
            (value) async {
              if (value == 1) {
                final name = await showPromptDialog(
                  context,
                  title: context.tr('New scene'),
                  initial: 'scene',
                );
                if (!mounted) return;
                if (name != null && name.trim().isNotEmpty) {
                  controller.newScene(name);
                }
              } else if (value == 2) {
                _say(
                  context,
                  context.tr('Folder creation is not supported yet.'),
                );
              } else if (value == 3) {
                _say(
                  context,
                  context.tr('File creation is not supported yet.'),
                );
              } else if (value == 4) {
                _say(
                  context,
                  context.tr('Folder rename is not supported yet.'),
                );
              } else if (value == 5) {
                _say(
                  context,
                  context.tr('Folder deletion is not supported yet.'),
                );
              }
            },
          );

    if (collapsed || empty) return menuTile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        menuTile,
        ..._renderChildren(context, project, dir, depth + 1),
      ],
    );
  }

  Widget _fileTile(
    BuildContext context,
    Project project,
    _FileNode file,
    int depth,
  ) {
    final padding = EdgeInsets.only(left: 6 + depth * 14.0, right: 6);

    if (file.isBuildFile) {
      final tile = ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        leading: const Icon(Icons.description_outlined, size: 16),
        title: Text(file.name, style: const TextStyle(fontSize: 12)),
        onTap: () => controller.showSource(
          GeneratedFile(
            path: file.path,
            content: file.content ?? '',
            isXml: file.path.endsWith('.xml'),
          ),
        ),
      );
      return _contextMenu(
        context,
        tile,
        <PopupMenuEntry<int>>[
          PopupMenuItem<int>(value: 1, child: Text(context.tr('Open source'))),
        ],
        (value) async {
          if (value == 1) {
            controller.showSource(
              GeneratedFile(
                path: file.path,
                content: file.content ?? '',
                isXml: file.path.endsWith('.xml'),
              ),
            );
          }
        },
      );
    }

    if (file.isJava) {
      final tile = ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        leading: const Icon(Icons.data_object, size: 16),
        title: Text(file.name, style: const TextStyle(fontSize: 12)),
        onTap: () => controller.showSource(
          GeneratedFile(
            path: file.path,
            content: file.content ?? '',
            isJava: true,
          ),
        ),
      );
      return _contextMenu(
        context,
        tile,
        <PopupMenuEntry<int>>[
          PopupMenuItem<int>(value: 1, child: Text(context.tr('Open source'))),
          const PopupMenuDivider(),
          PopupMenuItem<int>(value: 2, child: Text(context.tr('Rename'))),
          PopupMenuItem<int>(value: 3, child: Text(context.tr('Delete'))),
        ],
        (value) async {
          if (value == 1) {
            controller.showSource(
              GeneratedFile(
                path: file.path,
                content: file.content ?? '',
                isJava: true,
              ),
            );
          } else if (value == 2) {
            final current = file.name.endsWith('.java')
                ? file.name.substring(0, file.name.length - 5)
                : file.name;
            final newName = await showPromptDialog(
              context,
              title: '${context.tr('Rename')} — ${context.tr('Java file')}',
              initial: current,
            );
            if (newName == null || !context.mounted) return;
            final error = controller.renameJavaFile(file.path, newName);
            if (error != null && context.mounted) {
              _say(context, context.tr(error));
            }
          } else if (value == 3) {
            _say(
              context,
              context.tr('Java file deletion is not supported yet.'),
            );
          }
        },
      );
    }

    final scene = file.scene!;
    final active = identical(controller.activeScene, scene);
    final controllerClass = scene.controllerClass;
    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: padding,
      selected: active,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.4),
      leading: const Icon(Icons.description_outlined, size: 16),
      title: Text(file.name, style: const TextStyle(fontSize: 12)),
      subtitle: controllerClass == null || controllerClass.isEmpty
          ? null
          : Text(
              controllerClass,
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () {
        controller.openScene(scene);
        controller.setCodeMode(false);
      },
    );
    return _contextMenu(
      context,
      tile,
      <PopupMenuEntry<int>>[
        PopupMenuItem<int>(value: 1, child: Text(context.tr('Open in editor'))),
        const PopupMenuDivider(),
        PopupMenuItem<int>(value: 2, child: Text(context.tr('Rename'))),
        PopupMenuItem<int>(value: 3, child: Text(context.tr('Delete'))),
      ],
      (value) async {
        if (value == 1) {
          controller.openScene(scene);
          controller.setCodeMode(false);
        } else if (value == 2) {
          widget.onRenameScene(scene);
        } else if (value == 3) {
          widget.onDeleteScene(scene);
        }
      },
    );
  }

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class _DirNode {
  _DirNode(this.name, this.path);

  String name;
  final String path;
  final Map<String, _DirNode> dirs = <String, _DirNode>{};
  final List<_FileNode> files = <_FileNode>[];
}

class _FileNode {
  _FileNode({
    required this.name,
    required this.path,
    required this.isJava,
    this.content,
    this.scene,
    this.isBuildFile = false,
    this.isXml = false,
  });

  final String name;
  final String path;
  final bool isJava;
  final String? content;
  final SceneFile? scene;

  /// Generated project files (build configuration, README) that are written on
  /// export rather than edited on the canvas.
  final bool isBuildFile;

  /// True for XML files (FXML scenes, pom.xml) validated as XML.
  final bool isXml;
}
