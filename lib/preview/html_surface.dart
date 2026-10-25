/// Shows the generated HTML preview.
///
/// The web build embeds an iframe; every other target (including widget tests,
/// which have no DOM) gets a lightweight placeholder.
library;

export 'html_surface_stub.dart'
    if (dart.library.js_interop) 'html_surface_web.dart';
