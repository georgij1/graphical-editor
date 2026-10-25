/// Local storage of the workspace.
///
/// The workspace is stored per account: [scope] identifies the owner of the
/// projects (the account id, or `guest` for work done without a sign-in).
/// Projects of one person are therefore never visible to another one on the
/// same device.
abstract class ProjectStorage {
  /// Reads the workspace of [scope]; null when there is nothing stored yet.
  Future<String?> load(String scope);

  /// Writes the workspace of [scope].
  Future<void> save(String scope, String data);
}

/// Scope used for projects created before anybody signed in.
const String guestScope = 'guest';

/// Turns an account id into a key that is safe for files and storage keys.
String storageScope(String? userId) {
  final id = (userId ?? '').trim();
  if (id.isEmpty) return guestScope;
  return id.replaceAll(RegExp(r'[^A-Za-z0-9_.@-]'), '_');
}
