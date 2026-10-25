/// Saves a file either through a native dialog or, on the web, through a
/// browser download. The web implementation is picked automatically.
library;

export 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';