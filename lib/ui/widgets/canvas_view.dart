import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../editor/editor_controller.dart';
import '../../render/fx_renderer.dart';

/// The design surface where the JavaFX UI is rendered and edited.
///
/// The canvas is intentionally unbounded: its surface is sized far beyond any
/// realistic project so the user can pan and zoom in any direction without
/// hitting an edge. The surface is always at least as big as the viewport so
/// there are no empty gaps around it (like Figma).
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    required this.onShowCode,
  });

  final EditorController controller;
  final VoidCallback onShowCode;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    // Set the initial scale from the controller (e.g. restored from prefs).
    _transformationController.value =
        Matrix4.identity()
            ..scale(widget.controller.zoom, widget.controller.zoom, 1.0);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final renderer = FxRenderer(controller.buildRenderContext());

    // The canvas surface is sized far beyond any realistic project so the user
    // can pan and zoom in any direction without hitting an edge.
    final infiniteSize = Size(
      math.max(controller.canvasWidth, 100000).toDouble(),
      math.max(controller.canvasHeight, 100000).toDouble(),
    );

    final surface = DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x33000000), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: SizedBox(
        width: infiniteSize.width,
        height: infiniteSize.height,
        child: Stack(
          children: <Widget>[
            if (controller.showGrid)
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(controller.gridSize),
                ),
              ),
            renderer.build(controller.root),
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFE8E8EC),
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.1,
        maxScale: 10.0,
        panEnabled: true,
        scaleEnabled: true,
        // Keep the controller zoom in sync when the user zooms/pans.
        onInteractionUpdate: (details) {
          final newZoom = _transformationController.value
              .getMaxScaleOnAxis();
          if ((newZoom - controller.zoom).abs() > 0.001) {
            controller.setZoom(newZoom);
          }
        },
        onInteractionEnd: (details) {
          final newZoom = _transformationController.value
              .getMaxScaleOnAxis();
          if ((newZoom - controller.zoom).abs() > 0.001) {
            controller.setZoom(newZoom);
          }
        },
        alignment: Alignment.center,
        // Make the surface at least as big as the viewport so there are no
        // empty gaps around it (like Figma).
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = constraints.biggest;
            final surfaceWidth = math.max(
                infiniteSize.width, viewportSize.width);
            final surfaceHeight = math.max(
                infiniteSize.height, viewportSize.height);
            return SizedBox(
              width: surfaceWidth,
              height: surfaceHeight,
              child: surface,
            );
          },
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.step);
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final fine = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    final bold = Paint()
      ..color = const Color(0x22039EC8)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += step) {
      final paint = (x % (step * 5) == 0) ? bold : fine;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      final paint = (y % (step * 5) == 0) ? bold : fine;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.step != step;
}
