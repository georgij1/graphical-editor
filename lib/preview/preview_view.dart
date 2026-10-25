import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'html_preview.dart';
import 'html_surface.dart';

/// Runs the designed scene as HTML, filling the whole window.
///
/// A JavaFX runtime needs native libraries and cannot be shipped to a browser,
/// so the FXML is translated into DOM: layout and styling are reproduced and
/// the controls report the Java handler they would call.
class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key, required this.controller});

  final EditorController controller;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  /// Bumped on refresh so the platform view is rebuilt with the same document.
  int _epoch = 0;

  String _html() => buildPreviewHtml(
        widget.controller.document,
        title: widget.controller.currentProject?.name ?? context.tr('Preview'),
        width: widget.controller.canvasWidth,
        height: widget.controller.canvasHeight,
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final html = _html();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('Close preview'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.tr('Preview')),
            Text(
              controller.currentProject?.name ?? context.tr('Live document'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('Refresh preview'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _epoch++),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: buildHtmlSurface(
              html,
              // The epoch forces a new platform view on refresh.
              viewType: 'preview-${html.hashCode}-$_epoch',
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the full screen preview.
///
/// Does not wait for the route to close: the caller has nothing to do while
/// the preview is open.
void showPreview(BuildContext context, EditorController controller) {
  Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) =>
          PreviewPage(controller: controller),
    ),
  );
}
