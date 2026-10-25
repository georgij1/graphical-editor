import 'package:web/web.dart' as web;

import 'project_storage_base.dart';

class PlatformProjectStorage implements ProjectStorage {
  PlatformProjectStorage();

  static const _prefix = 'graphical_editor_workspaces_';

  /// Key used before the workspace was stored per account. Its content is
  /// moved into the guest slot on the first run, so nothing is lost.
  static const _legacyKey = 'graphical_editor_projects';

  String _key(String scope) => '$_prefix${storageScope(scope)}';

  @override
  Future<String?> load(String scope) async {
    final key = _key(scope);
    final current = web.window.localStorage.getItem(key);
    if (current != null) return current;

    // Move the workspace of the previous versions into the guest slot.
    final legacy = web.window.localStorage.getItem(_legacyKey);
    if (legacy == null) return null;
    try {
      web.window.localStorage.setItem(key, legacy);
      web.window.localStorage.removeItem(_legacyKey);
    } catch (_) {}
    return legacy;
  }

  @override
  Future<void> save(String scope, String data) async {
    try {
      web.window.localStorage.setItem(_key(scope), data);
    } catch (_) {}
  }
}
