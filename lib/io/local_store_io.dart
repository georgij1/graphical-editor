import 'dart:io';

import 'local_store_base.dart';

class PlatformKeyValueStore implements KeyValueStore {
  PlatformKeyValueStore();

  Directory get _dir {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        '.';
    return Directory('$base${Platform.pathSeparator}graphical_editor');
  }

  File _fileFor(String key) =>
      File('${_dir.path}${Platform.pathSeparator}$key.txt');

  @override
  Future<String?> read(String key) async {
    try {
      final file = _fileFor(key);
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _dir.create(recursive: true);
      await _fileFor(key).writeAsString(value, flush: true);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = _fileFor(key);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}