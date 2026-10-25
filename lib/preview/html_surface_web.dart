import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web implementation: embeds the generated page in an iframe.
///
/// The document is handed over as `srcdoc`, so the preview needs no server and
/// never reaches out to the network.
Widget buildHtmlSurface(String html, {required String viewType}) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int id) => _iframe(html),
  );
  return HtmlElementView(viewType: viewType);
}

web.HTMLIFrameElement _iframe(String html) {
  final web.HTMLIFrameElement frame =
      web.document.createElement('iframe') as web.HTMLIFrameElement;
  frame.setAttribute('title', 'JavaFX preview');
  frame.style
    ..width = '100%'
    ..height = '100%'
    ..border = 'none';
  frame.srcdoc = html.toJS;
  return frame;
}
