import 'project_storage_base.dart';
import 'project_storage_io.dart'
    if (dart.library.js_interop) 'project_storage_web.dart';

export 'project_storage_base.dart';

ProjectStorage createProjectStorage() => PlatformProjectStorage();