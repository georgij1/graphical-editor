import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

/// Builds the AppBar action buttons for the editor.
///
/// The bar is crowded and the header is finite, so the actions are dropped by
/// priority as the space runs out: the Canvas/Code switch and the "More" menu
/// survive longest, the zoom buttons go first.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onShowCode,
  });

  final EditorController controller;
  final VoidCallback onShowCode;

  /// Budgets below which the optional groups are dropped.
  static const double _dropZoomAt = 900;
  static const double _dropCanvasToolsAt = 720;
  static const double _dropHistoryAt = 560;

  /// Space the title and the account button need: the project name is the
  /// thing that must stay readable, so the toolbar gives up room first.
  static const double _reservedSpace = 430;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // AppBar gives its actions an unbounded width, so the budget has to
        // come from the window: without it the bar cannot shrink and overflows
        // the header.
        final budget = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (MediaQuery.sizeOf(context).width - _reservedSpace)
                .clamp(240.0, double.infinity);
        final showZoom = budget >= _dropZoomAt;
        final showCanvasTools = budget >= _dropCanvasToolsAt;
        final showHistory = budget >= _dropHistoryAt;

        final actions = <Widget>[
          // A generated Java source has no visual form, so the Canvas/Code
          // switch is hidden while it is shown. No divider after it: every
          // following group starts with its own, and two in a row drew a double
          // bar.
          if (!controller.codeIsJava)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _ModeSwitch(controller: controller),
            ),
          // New/open/save/download live in the project tree, next to the files
          // they act on; the header keeps view and edit controls only.
          if (showHistory) ...<Widget>[
            const _Bar(),
            IconButton(
              tooltip: context.tr('Undo (Ctrl+Z)'),
              icon: const Icon(Icons.undo),
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              tooltip: context.tr('Redo (Ctrl+Y)'),
              icon: const Icon(Icons.redo),
              onPressed: controller.canRedo ? controller.redo : null,
            ),
          ],
          if (showCanvasTools) ...<Widget>[
            const _Bar(),
          IconButton(
            tooltip: context.tr('Toggle grid'),
              isSelected: controller.showGrid,
              icon: const Icon(Icons.grid_4x4),
              onPressed: controller.toggleGrid,
            ),
          ],
          if (showZoom) ...<Widget>[
            const _Bar(),
            IconButton(
              tooltip: context.tr('Zoom out'),
              icon: const Icon(Icons.remove),
              onPressed: controller.zoomOut,
            ),
            Center(
              child: TextButton(
                onPressed: controller.resetZoom,
                child: Text('${(controller.zoom * 100).round()}%'),
              ),
            ),
            IconButton(
              tooltip: context.tr('Zoom in'),
              icon: const Icon(Icons.add),
              onPressed: controller.zoomIn,
            ),
          ],
          const SizedBox(width: 4),
        ];

        // Scrolling is only a safety net for very narrow windows: on a normal
        // one the groups above already fit.
        return SizedBox(
          width: budget,
          child: ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Scrolled from the start, so the Canvas/Code switch stays
              // reachable when the window is too narrow for everything.
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        );
      },
    );
  }
}


/// The Canvas/Code switch, the main mode of the editor.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: <ButtonSegment<int>>[
        ButtonSegment<int>(
          value: 0,
          icon: const Icon(Icons.design_services_outlined, size: 16),
          label: Text(context.tr('Canvas')),
        ),
        ButtonSegment<int>(
          value: 1,
          icon: const Icon(Icons.code, size: 16),
          label: Text(context.tr('Code')),
        ),
      ],
      selected: <int>{controller.codeMode ? 1 : 0},
      onSelectionChanged: (selection) =>
          controller.setCodeMode(selection.first == 1),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: VerticalDivider(width: 8),
    );
  }
}
