import 'dart:convert';

import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../project/build_files.dart';
import '../../project/java_generator.dart';
import '../../project/project.dart';
import '../../l10n/app_localizations.dart';

/// Full project tree: the JavaFX application laid out like a real source tree
/// (`src/main/java/...` for the launcher + controllers and
/// `src/main/resources/...` for the FXML scenes).
class ProjectTreePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final project = controller.currentProject;
    if (project == null) return const SizedBox.shrink();
final root = _buildTree(project);
    // Not a lazy list: the pane measures its content so the divider can sit
    // right below the last row.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _renderChildren(context, project, root, 0),
          ),
        ),
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
    }) {
      final parts = path.split('/');
      var dir = root;
      for (final part in parts.sublist(0, parts.length - 1)) {
        dir = dir.dirs.putIfAbsent(part, () => _DirNode(part, '${dir.path}/$part'));
      }
      dir.files.add(_FileNode(
        name: parts.last,
        path: path,
        content: content,
        scene: scene,
        isJava: isJava,
        isBuildFile: isBuildFile,
      ));
    }

for (final source in JavaGenerator.generate(project)) {
      addFile(source.path, content: source.content, isJava: true);
    }
    for (final file in const BuildFiles().generate(project, BuildTool.maven)) {
      addFile(file.path, content: file.content, isJava: false, isBuildFile: true);
    }
    addFile('project.json', content: const JsonEncoder.withIndent('  ').convert(project.toJson()), isJava: false, isBuildFile: true);
    final pkgDir = JavaGenerator.packageDir(project);
    for (final scene in project.scenes) {
      addFile(
        'src/main/resources/$pkgDir/${scene.name}.fxml',
        content: scene.fxml,
        scene: scene,
        isJava: false,
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
      for (final file in _sortedFiles(dir))
        _fileTile(context, project, file, depth),
    ];
    return widgets;
  }

  List<_DirNode> _sortedDirs(_DirNode dir) {
    final dirs = dir.dirs.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return dirs;
  }

  List<_FileNode> _sortedFiles(_DirNode dir) {
    final files = dir.files.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  Widget _directoryTile(
    BuildContext context,
    Project project,
    _DirNode dir,
    int depth,
  ) {
    final padding = EdgeInsets.only(left: 6 + depth * 14.0, right: 8);
    final empty = dir.dirs.isEmpty && dir.files.isEmpty;
    if (empty) {
      return Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
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
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('ptdir:${dir.path}'),
        initiallyExpanded: true,
        tilePadding: padding,
        childrenPadding: EdgeInsets.zero,
        minTileHeight: 34,
        leading: const Icon(Icons.folder_outlined, size: 17),
        title: Text(
          dir.name,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        children: _renderChildren(context, project, dir, depth + 1),
      ),
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
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        leading: const Icon(Icons.description_outlined, size: 16),
        title: Text(file.name, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          context.tr('generated on export'),
          style: const TextStyle(fontSize: 10),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (file.isJava) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: padding,
        leading: const Icon(Icons.data_object, size: 16),
        title: Text(file.name, style: const TextStyle(fontSize: 12)),
        onTap: () => controller.showSource(
          GeneratedFile(path: file.path, content: file.content ?? ''),
        ),
      );
    }

    final scene = file.scene!;
    final active = identical(controller.activeScene, scene);
    final controllerClass = scene.controllerClass;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: padding,
      selected: active,
      selectedTileColor:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
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
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        tooltip: context.tr('Scene actions'),
        onSelected: (value) {
          switch (value) {
            case 'rename':
              onRenameScene(scene);
            case 'delete':
              onDeleteScene(scene);
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'rename', child: Text(context.tr('Rename'))),
          PopupMenuItem<String>(value: 'delete', child: Text(context.tr('Delete'))),
        ],
      ),
    );
  }
}

class _DirNode {
  _DirNode(this.name, this.path);

  final String name;

  /// Full slash separated path, so nested folders sharing a name keep their
  /// own expansion state.
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
  });

  final String name;
  final String path;
  final bool isJava;
  final String? content;
  final SceneFile? scene;

  /// Generated project files (build configuration, README) that are written on
  /// export rather than edited on the canvas.
  final bool isBuildFile;
}
