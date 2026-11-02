import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'canvas_view.dart';
import 'project_home.dart';
import 'source_view.dart';

/// The central editing surface. "Code" shows an editable text editor for the
/// selected file (scene FXML or a generated Java source); "Canvas" shows the
/// visual designer. The switch between them lives in the header.
class CanvasArea extends StatelessWidget {
  const CanvasArea({
    super.key,
    required this.controller,
    required this.onShowCode,
  });

  final EditorController controller;
  final VoidCallback onShowCode;

  @override
  Widget build(BuildContext context) {
    // With no project (and no loose document) open the canvas would just be an
    // empty white sheet, so present a project picker instead.
    if (!controller.hasOpenDocument) {
      return ProjectHome(controller: controller);
    }

    // A collaborative project opens without auto-loading a scene: prompt the
    // user to pick a file from the tree instead of showing an empty canvas.
    if (controller.activeScene == null && !controller.codeMode) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_open_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              context.tr('Select a file in the project tree to start editing.'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final codeView = CodeView(
      key: ValueKey<String>('${controller.codePath}#${controller.codeEpoch}'),
      controller: controller,
    );

    // A generated Java source has no visual representation: show the editor
    // alone.
    if (controller.codeIsJava) {
      return codeView;
    }

    return controller.codeMode
        ? codeView
        : CanvasView(
            controller: controller,
            onShowCode: onShowCode,
          );
  }
}
