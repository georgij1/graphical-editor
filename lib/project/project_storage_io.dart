import 'dart:io';

import 'project_storage_base.dart';

class PlatformProjectStorage implements ProjectStorage {
  PlatformProjectStorage();

  Directory get _dir {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        '.';
    return Directory('$base${Platform.pathSeparator}graphical_editor');
  }

  /// One file per account: `projects_<scope>.json`.
  File _file(String scope) => File(
      '${_dir.path}${Platform.pathSeparator}projects_${storageScope(scope)}.json');

  /// File used before the workspace was stored per account.
  File get _legacyFile =>
      File('${_dir.path}${Platform.pathSeparator}projects.json');

  @override
  Future<String?> load(String scope) async {
    try {
      final file = _file(scope);
      if (file.existsSync()) return await file.readAsString();
      // Move the workspace of the previous versions into the guest slot.
      final legacy = _legacyFile;
      if (!legacy.existsSync()) return null;
      final data = await legacy.readAsString();
      await file.writeAsString(data, flush: true);
      await legacy.delete();
      return data;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String scope, String data) async {
    try {
      await _dir.create(recursive: true);
      await _file(scope).writeAsString(data, flush: true);
    } catch (_) {}
  }
}
