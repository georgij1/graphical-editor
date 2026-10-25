import 'package:flutter/widgets.dart';

/// Shows generated HTML inside the editor.
///
/// The web build embeds an iframe with the document; other platforms (and
/// widget tests) get a placeholder describing what the preview contains, since
/// there is no DOM to embed into.
Widget buildHtmlSurface(String html, {required String viewType}) {
  return HtmlSurfacePlaceholder(
    viewType: viewType,
    // Surfaced in tests: proves the generated document made it into the view.
    byteLength: html.length,
  );
}

/// Placeholder used off the web platform.
class HtmlSurfacePlaceholder extends StatelessWidget {
  const HtmlSurfacePlaceholder({
    super.key,
    required this.viewType,
    required this.byteLength,
  });

  final String viewType;
  final int byteLength;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SurfacePainter(),
      child: Center(
        child: Text('$viewType ($byteLength)'),
      ),
    );
  }
}

class _SurfacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_SurfacePainter oldDelegate) => false;
}
