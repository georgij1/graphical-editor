import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project.dart';
import 'project_dialogs.dart';
import 'project_tree_panel.dart';

/// "Project" tab of the left panel: the current project's sources and scenes.
///
/// The tree used to live above the canvas; it now sits next to the component
/// palette and the outline, where the other document views are.
class ProjectPanel extends StatefulWidget {
  const ProjectPanel({
    super.key,
    required this.controller,
    this.onOpen,
    this.onSave,
    this.onDownload,
  });

  final EditorController controller;
  final Future<void> Function()? onOpen;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onDownload;

  @override
  State<ProjectPanel> createState() => _ProjectPanelState();
}

class _ProjectPanelState extends State<ProjectPanel> {
  EditorController get controller => widget.controller;

  Future<void> _newScene() async {
    final name = await showPromptDialog(
      context,
      title: context.tr('New scene'),
      initial: 'scene',
    );
    if (name != null && name.trim().isNotEmpty) {
      controller.newScene(name);
    }
  }

  Future<void> _renameScene(SceneFile scene) async {
    final name = await showPromptDialog(
      context,
      title: context.tr('Rename scene'),
      initial: scene.name,
    );
    if (name != null && name.trim().isNotEmpty) {
      controller.renameScene(scene, name);
    }
  }

  Future<void> _deleteScene(SceneFile scene) async {
    final ok = await confirmDialog(
      context,
      title: context.tr('Delete scene'),
      message: context.l10n.deleteScene(scene.name),
    );
    if (ok) controller.deleteScene(scene);
  }

  @override
  Widget build(BuildContext context) {
    final project = controller.currentProject;
    if (project == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // Own Material so row highlights stay inside this section instead of being
    // painted on the Scaffold's Material, above the clip.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_copy_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${project.package} · ${context.l10n.scenes(project.scenes.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('New document'),
                icon: const Icon(Icons.note_add_outlined, size: 16),
                onPressed: controller.newDocument,
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: context.tr('Open FXML…'),
                icon: const Icon(Icons.folder_open, size: 16),
                onPressed: widget.onOpen,
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: context.tr('Save document'),
                icon: const Icon(Icons.save_outlined, size: 16),
                onPressed: widget.onSave,
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: context.tr('Download FXML…'),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                onPressed: widget.onDownload,
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: context.tr('New scene'),
                icon: const Icon(Icons.add, size: 18),
                onPressed: _newScene,
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Loose so the pane can end right below the last row instead of
        // cutting it with the divider.
        Flexible(
          fit: FlexFit.loose,
          child: ProjectTreePanel(
            controller: controller,
            onRenameScene: _renameScene,
            onDeleteScene: _deleteScene,
          ),
        ),
        ],
      ),
    );
  }
}