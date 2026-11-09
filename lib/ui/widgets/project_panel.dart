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

    // Own Material so row highlights stay inside this section instead of being
    // painted on the Scaffold's Material, above the clip.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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