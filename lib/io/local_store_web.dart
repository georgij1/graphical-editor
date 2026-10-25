import 'package:web/web.dart' as web;

import 'local_store_base.dart';

class PlatformKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => web.window.localStorage.getItem(key);

  @override
  Future<void> write(String key, String value) async {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }
}