import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../preview/preview_view.dart';

/// Bottom status bar summarising the current document state.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selected;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;

    // Every label is flexible and clips with an ellipsis: the bar must survive
    // narrow windows and long scene names instead of overflowing.
    Widget label(String text, {Color? color}) => Flexible(
          child: Text(
            text,
            style: style?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            maxLines: 1,
          ),
        );

    return Container(
      height: 28,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.hub_outlined, size: 14, color: theme.hintColor),
          const SizedBox(width: 4),
          label(context.l10n.nodes(controller.nodeCount)),
          const _Sep(),
          // The run button lives next to the document summary: it is used
          // often, and the header is already crowded.
          _RunPreview(controller: controller),
          const _Sep(),
          // Without an open project there is nothing to save, so the state
          // indicator stays hidden until a document is actually being edited.
          if (controller.hasOpenDocument) ...<Widget>[
            const _Sep(),
            Icon(
              Icons.check_circle_outline,
              size: 14,
              color: controller.dirty ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 4),
            label(
              controller.dirty
                  ? context.tr('Unsaved changes')
                  : context.tr('Saved'),
              color: controller.dirty ? Colors.orange : null,
            ),
          ],
          if (selected != null) ...<Widget>[
            label(context.l10n.selected(selected.displayName)),
            const _Sep(),
          ],
          // The shared mode: the project is worked on by several people and
          // the editor watches the server for their changes.
          if (controller.collaborativeMode) ...<Widget>[
            Icon(Icons.group_outlined,
                size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            label(
              context.tr('Shared mode'),
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            label('${controller.collaborators.length}'),
            const _Sep(),
          ],
          label(context.l10n.canvasSize(
              controller.canvasWidth.round(), controller.canvasHeight.round())),
          const _Sep(),
          label('${(controller.zoom * 100).round()}%'),
        ],
      ),
    );
  }
}


/// Opens the browser preview of the current scene.
class _RunPreview extends StatelessWidget {
  const _RunPreview({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showPreview(context, controller),
      icon: const Icon(Icons.play_arrow_outlined, size: 14),
      label: Text(
        context.tr('Run preview'),
        style: const TextStyle(fontSize: 11),
      ),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Text('·', style: TextStyle(fontSize: 12)),
    );
  }
}
