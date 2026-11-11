import 'dart:convert';

import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/build_files.dart';
import '../../project/java_generator.dart';
import '../../project/project.dart';
import 'new_file_modal.dart';
import 'new_folder_modal.dart';
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

  @override
  Widget build(BuildContext context) {
    final project = controller.currentProject;
    if (project == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      primary: false,
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
              // Root project folder tile (renders recursively)
              _directoryTile(context, projectNow, root, 0),
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

    // Add generated Java sources
    final generatedFiles = JavaGenerator.generate(project);
    for (final source in generatedFiles) {
      addFile(source.path, content: source.content, isJava: true);
    }

    // Add build files
    for (final file in const BuildFiles().generate(project, BuildTool.maven)) {
      addFile(
        file.path,
        content: project.sourceOverrides[file.path] ?? file.content,
        isJava: false,
        isBuildFile: true,
        isXml: file.path.endsWith('.xml'),
      );
    }

    // Add project.json
    addFile(
      'project.json',
      content: const JsonEncoder.withIndent('  ').convert(project.toJson()),
      isJava: false,
      isBuildFile: true,
    );

    // Add FXML scenes
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

    // Add user-created files and empty folders from sourceOverrides
    final standardPaths = <String>{
      ...generatedFiles.map((f) => f.path),
      ...const BuildFiles()
          .generate(project, BuildTool.maven)
          .map((f) => f.path),
      'project.json',
      ...project.scenes.map(
        (s) => 'src/main/resources/$pkgDir/${s.name}.fxml',
      ),
    };

    for (final entry in project.sourceOverrides.entries) {
      if (!standardPaths.contains(entry.key)) {
        // Check if this is an empty folder (ends with /)
        if (entry.key.endsWith('/')) {
          // Create folder structure without adding a file
          final parts = entry.key.substring(0, entry.key.length - 1).split('/');
          var dir = root;
          for (final part in parts) {
            dir = dir.dirs.putIfAbsent(
              part,
              () => _DirNode(part, '${dir.path}/$part'),
            );
          }
        } else {
          addFile(
            entry.key,
            content: entry.value,
            isJava: entry.key.endsWith('.java'),
            isXml: entry.key.endsWith('.xml') || entry.key.endsWith('.fxml'),
          );
        }
      }
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
    final widgets = <Widget>[];

    // Рендерим поддиректории (они сами рекурсивно рендерят своё содержимое)
    for (final child in _sortedDirs(dir)) {
      widgets.add(_directoryTile(context, project, child, depth));
    }

    // Файлы отображаются на один уровень глубже родительской папки
    for (final file in _sortedFiles(dir)) {
      widgets.add(_fileTile(context, project, file, depth + 1));
    }

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

    final tile = _contextMenu(
      context,
      InkWell(
        // Always provide a non-null onTap so InkWell renders hover effects.
        // For empty folders the tap does nothing; for non-empty it toggles.
        onTap: empty ? null : () => _toggle(dir.path),
        hoverColor: Theme.of(context).hoverColor,
        child: Padding(
          padding: EdgeInsets.only(
            left: 6 + depth * 14.0,
            right: 6,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                empty
                    ? Icons.folder_outlined
                    : (collapsed ? Icons.chevron_right : Icons.expand_more),
                size: 16,
                color: empty
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dir.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      <PopupMenuEntry<int>>[
        PopupMenuItem<int>(value: 1, child: Text(context.tr('New scene'))),
        PopupMenuItem<int>(value: 2, child: Text(context.tr('New folder'))),
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
          final name = await showNewFolderModal(context);
          if (!mounted || name == null) return;
          final cleanPath = dir.path == project.name
              ? ''
              : (dir.path.startsWith('${project.name}/')
                  ? dir.path.substring(project.name.length + 1)
                  : dir.path);
          controller.newFolder(name, folderPath: cleanPath);
        } else if (value == 3) {
          final result = await showNewFileModal(context);
          if (!mounted || result == null) return;
          final fileName = result['name']!;
          final fileType = result['type']!;
          final cleanPath = dir.path == project.name
              ? ''
              : (dir.path.startsWith('${project.name}/')
                  ? dir.path.substring(project.name.length + 1)
                  : dir.path);
          controller.newFile(fileName, fileType, folderPath: cleanPath);
        } else if (value == 4) {
          final newName = await showPromptDialog(
            context,
            title: '${context.tr('Rename')} — ${context.tr('Folder')}',
            initial: dir.name,
          );
          if (newName == null || !context.mounted) return;
          final cleanPath = dir.path == project.name
              ? ''
              : (dir.path.startsWith('${project.name}/')
                  ? dir.path.substring(project.name.length + 1)
                  : dir.path);
          if (cleanPath.isEmpty) {
            _say(context, context.tr('Cannot rename the project root.'));
            return;
          }
          controller.renameFolder(cleanPath, newName);
        } else if (value == 5) {
          if (!context.mounted) return;
          final ok = await confirmDialog(
            context,
            title: context.tr('Delete'),
            message: '${context.tr('Delete')} ${dir.name}?',
          );
          if (!ok || !context.mounted) return;
          // Remove project name prefix from dir.path
          final cleanPath = dir.path == project.name
              ? ''
              : (dir.path.startsWith('${project.name}/')
                  ? dir.path.substring(project.name.length + 1)
                  : dir.path);
          if (cleanPath.isEmpty) {
            _say(context, context.tr('Cannot delete the project root.'));
            return;
          }
          final error = controller.deleteFolder(cleanPath);
          if (error != null && context.mounted) {
            _say(context, context.tr(error));
          }
        }
      },
    );

    if (collapsed || empty) return tile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        tile,
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
      final selected = controller.codeMode && file.path == controller.codePath;
      final tile = ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        selected: selected,
        selectedTileColor:
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
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
          const PopupMenuDivider(),
          PopupMenuItem<int>(value: 2, child: Text(context.tr('Delete'))),
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
          } else if (value == 2) {
            if (!context.mounted) return;
            final ok = await confirmDialog(
              context,
              title: context.tr('Delete'),
              message: '${context.tr('Delete')} ${file.name}?',
            );
            if (!ok || !context.mounted) return;
            final error = controller.deleteFile(file.path);
            if (error != null && context.mounted) {
              _say(context, context.tr(error));
            }
          }
        },
      );
    }

    if (file.isJava) {
      final selected = controller.codeMode && file.path == controller.codePath;
      final tile = ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        selected: selected,
        selectedTileColor:
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
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
            if (!context.mounted) return;
            final ok = await confirmDialog(
              context,
              title: context.tr('Delete'),
              message: '${context.tr('Delete')} ${file.name}?',
            );
            if (!ok || !context.mounted) return;
            final error = controller.deleteFile(file.path);
            if (error != null && context.mounted) {
              _say(context, context.tr(error));
            }
          }
        },
      );
    }

    // FXML scene file
    if (file.scene != null) {
      final scene = file.scene!;
      final active = controller.codeMode
          ? file.path == controller.codePath
          : identical(controller.activeScene, scene);
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

    // User-created file (CSS, JSON, etc.)
    return _renderUserFileTile(context, project, file, depth);
  }

  Widget _renderUserFileTile(
    BuildContext context,
    Project project,
    _FileNode file,
    int depth,
  ) {
    final padding = EdgeInsets.only(left: 6 + depth * 14.0, right: 6);
    final isCss = file.path.toLowerCase().endsWith('.css');
    final attached = isCss && controller.isStylesheetAttachedToActiveScene(file.path);
    final active = controller.openSource?.path == file.path;
    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: padding,
      selected: active,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.4),
      leading: Icon(
        isCss ? Icons.style_outlined : Icons.insert_drive_file,
        size: 16,
        color: attached || active ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(file.name, style: const TextStyle(fontSize: 12)),
      subtitle: attached
          ? Text(
              context.tr('Connected to this scene'),
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
      trailing: attached
          ? Icon(Icons.link, size: 14, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () => controller.showSource(
        GeneratedFile(
          path: file.path,
          content: file.content ?? '',
          isJava: file.path.endsWith('.java'),
          isXml: file.path.endsWith('.xml') || file.path.endsWith('.fxml'),
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
              isJava: file.path.endsWith('.java'),
              isXml: file.path.endsWith('.xml') || file.path.endsWith('.fxml'),
            ),
          );
        } else if (value == 2) {
          final newName = await showPromptDialog(
            context,
            title: '${context.tr('Rename')} — ${context.tr('File')}',
            initial: file.name,
          );
          if (newName == null || !context.mounted) return;
          controller.renameFile(file.path, newName);
        } else if (value == 3) {
          if (!context.mounted) return;
          final ok = await confirmDialog(
            context,
            title: context.tr('Delete'),
            message: '${context.tr('Delete')} ${file.name}?',
          );
          if (!ok || !context.mounted) return;
          final error = controller.deleteFile(file.path);
          if (error != null && context.mounted) {
            _say(context, context.tr(error));
          }
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
