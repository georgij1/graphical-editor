import 'local_store_base.dart';
import 'local_store_io.dart'
    if (dart.library.js_interop) 'local_store_web.dart';

export 'local_store_base.dart';

KeyValueStore createKeyValueStore() => PlatformKeyValueStore();