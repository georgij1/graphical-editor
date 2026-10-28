import 'package:graphical_editor/auth/api_client.dart';
import 'package:graphical_editor/io/local_store.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/project/project_history.dart';
import 'package:graphical_editor/project/project_storage.dart';

class InMemoryProjectStorage implements ProjectStorage {
  /// One entry per storage scope (account id or `guest`), so tests can check
  /// that the projects of one person do not leak into another's slot.
  final Map<String, String> scopes = <String, String>{};
  int writes = 0;

  /// Convenience access to the guest scope.
  String? get data => scopes[guestScope];
  set data(String? value) {
    if (value == null) {
      scopes.remove(guestScope);
    } else {
      scopes[guestScope] = value;
    }
  }

  @override
  Future<String?> load(String scope) async => scopes[scope];

  @override
  Future<void> save(String scope, String value) async {
    scopes[scope] = value;
    writes++;
  }
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}

/// In-memory stand-in for the backend server.
class FakeApiClient implements ApiClient {
  final Map<String, String> _passwords = <String, String>{};
  final Map<String, String> _workspaces = <String, String>{};
  final Map<String, String> _tokens = <String, String>{};
  final Map<String, String> _avatars = <String, String>{};
  int _counter = 0;
  bool offline = false;

  /// Address the account was renamed to, if the test exercised that path.
  String? lastEmailChange;

  int get userCount => _passwords.length;
  String? workspaceFor(String email) => _workspaces[email];
  String? avatarFor(String email) => _avatars[email];

  void seedUser(String email, String password, {String? workspaceJson}) {
    _passwords[email] = password;
    if (workspaceJson != null) _workspaces[email] = workspaceJson;
  }

  String _tokenFor(String email) {
    final token = 'tok_$email${_counter++}';
    _tokens[token] = email;
    return token;
  }

  /// Keeps the avatar with the address it was uploaded for, so a rename does
  /// not lose it.
  void _moveSideData(String from, String to) {
    final avatar = _avatars.remove(from);
    if (avatar != null) _avatars[to] = avatar;
    final workspace = _workspaces.remove(from);
    if (workspace != null) _workspaces[to] = workspace;
  }

  /// Account id, as the real backend reports it.
  String _idFor(String email) => 'usr_${email.toLowerCase()}';

  ApiResult<T> _fail<T>(ApiStatus status, [String? message]) =>
      ApiResult<T>.failure(status, message);

  @override
  Future<ApiResult<AuthUser>> register(String email, String password) async {
    if (offline) return _fail(ApiStatus.offline, 'Cannot reach the server.');
    if (_passwords.containsKey(email)) {
      return _fail(ApiStatus.invalid, 'This email is already registered.');
    }
    _passwords[email] = password;
    return ApiResult.ok(
        AuthUser(email: email, token: _tokenFor(email), id: _idFor(email)));
  }

  @override
  Future<ApiResult<AuthUser>> login(String email, String password) async {
    if (offline) return _fail(ApiStatus.offline, 'Cannot reach the server.');
    if (_passwords[email] != password) {
      return _fail(ApiStatus.unauthorized, 'Invalid email or password.');
    }
    return ApiResult.ok(
        AuthUser(email: email, token: _tokenFor(email), id: _idFor(email)));
  }

  @override
  Future<ApiResult<Profile?>> getProfile(String token) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok(
      Profile(email: email, id: _idFor(email), avatar: _avatars[email]),
    );
  }

  @override
  Future<ApiResult<AuthUser>> updateEmail(String token, String email) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final current = _emailFromToken(token);
    if (current == null) return _fail(ApiStatus.unauthorized, null);
    if (_passwords.containsKey(email)) {
      return _fail(ApiStatus.invalid, 'This email is already registered.');
    }
    _passwords[email] = _passwords.remove(current)!;
    _moveSideData(current, email);
    lastEmailChange = '$current -> $email';
    return ApiResult.ok(AuthUser(
      email: email,
      token: _tokenFor(email),
      id: _idFor(email),
      avatar: _avatars[email],
    ));
  }

  @override
  Future<ApiResult<void>> changePassword(
      String token, String currentPassword, String newPassword) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    if (_passwords[email] != currentPassword) {
      return _fail(ApiStatus.invalid, 'Current password is incorrect.');
    }
    if (newPassword.length < 6) {
      return _fail(ApiStatus.invalid, 'Password must be at least 6 characters.');
    }
    _passwords[email] = newPassword;
    return ApiResult.ok(null);
  }

  @override
  Future<ApiResult<String?>> updateAvatar(String token, String? avatar) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    if (avatar == null) {
      _avatars.remove(email);
    } else {
      _avatars[email] = avatar;
    }
    return ApiResult.ok(avatar);
  }

  String? _emailFromToken(String token) => _tokens[token];

  @override
  Future<ApiResult<String?>> getWorkspace(String token) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok(_workspaces[email] ?? '{"projects":[]}');
  }

  @override
  Future<ApiResult<void>> putWorkspace(
      String token, String workspaceJson) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    _workspaces[email] = workspaceJson;
    return ApiResult.ok(null);
  }

  // ------------------------------------------------------------- shared projects

  /// Shared projects, keyed by their id.
  final Map<String, Project> sharedProjects = <String, Project>{};

  @override
  Future<ApiResult<List<Account>>> listAccounts(String token) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok([
      for (final account in _passwords.keys)
        Account(id: _idFor(account), email: account),
    ]);
  }

  @override
  Future<ApiResult<List<Project>>> listSharedProjects(String token) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    final id = _idFor(email);
    return ApiResult.ok([
      for (final p in sharedProjects.values)
        if (p.ownerId == id || p.members.any((m) => m.email == email)) p,
    ]);
  }

  @override
  Future<ApiResult<Project>> getSharedProject(
      String token, String projectId) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    final project = sharedProjects[projectId];
    if (project == null) return _fail(ApiStatus.invalid, 'Project not found.');
    final id = _idFor(email);
    if (project.ownerId != id &&
        !project.members.any((m) => m.email == email)) {
      return _fail(ApiStatus.invalid, 'This project is not shared with you.');
    }
    return ApiResult.ok(project.copy());
  }

  @override
  Future<ApiResult<Project>> saveSharedProject(
      String token, Project project) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    final id = _idFor(email);
    final existing = sharedProjects[project.id];
    final saved = project.copy()
      ..ownerId = existing?.ownerId ?? id
      ..ownerEmail = existing?.ownerEmail ?? email
      ..revision = (existing?.revision ?? 0) + 1
      ..shared = true;
    sharedProjects[project.id] = saved;
    return ApiResult.ok(saved.copy());
  }

  @override
  Future<ApiResult<void>> deleteSharedProject(
      String token, String projectId) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    sharedProjects.remove(projectId);
    return ApiResult.ok(null);
  }

  @override
  Future<ApiResult<void>> heartbeatPresence(
      String token, String projectId, {
      double? cursorX,
      double? cursorY,
      String? selectedNodeId,
      bool sendCursor = false,
  }) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok(null);
  }

  @override
  Future<ApiResult<List<Map<String, dynamic>>>> listPresence(
      String token, String projectId) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final email = _emailFromToken(token);
    if (email == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok(const <Map<String, dynamic>>[]);
  }

  @override
  Future<ApiResult<Project>> addProjectMember(
      String token, String projectId, String email, String role) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    final project = sharedProjects[projectId];
    if (project == null) return _fail(ApiStatus.invalid, 'Project not found.');
    final member = project.members.where((m) => m.email == email).toList();
    if (member.isEmpty) {
      project.members.add(ProjectMember(email: email, role: role));
    } else {
      member.first.role = role;
    }
    return ApiResult.ok(project.copy());
  }

  // ---------------------------------------------------------- invitation links

  /// The token of the last issued invitation.
  String? inviteToken;

  @override
  Future<ApiResult<ProjectInvite>> createProjectInvite(
      String token, String projectId, String role) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    final project = sharedProjects[projectId];
    if (project == null) return _fail(ApiStatus.invalid, 'Project not found.');
    inviteToken = 'inv-$projectId-${_counter++}';
    return ApiResult.ok(ProjectInvite(
      token: inviteToken!,
      role: role,
      projectId: projectId,
    ));
  }

  @override
  Future<ApiResult<ProjectInvite>> getProjectInvite(
      String token, String inviteToken) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    if (this.inviteToken != inviteToken) {
      return _fail(ApiStatus.invalid, 'The invitation is not valid.');
    }
    final project = sharedProjects[inviteToken.split('-')[1]];
    return ApiResult.ok(ProjectInvite(
      token: inviteToken,
      role: 'editor',
      projectId: project?.id ?? '',
      projectName: project?.name ?? '',
      ownerEmail: project?.ownerEmail ?? '',
    ));
  }

  @override
  Future<ApiResult<Project>> joinProject(
      String token, String projectId, String inviteToken) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    if (this.inviteToken != inviteToken) {
      return _fail(ApiStatus.invalid, 'The invitation is not valid.');
    }
    final project = sharedProjects[projectId];
    if (project == null) return _fail(ApiStatus.invalid, 'Project not found.');
    if (!project.members.any((m) => m.email == user)) {
      project.members.add(ProjectMember(email: user, role: 'editor'));
    }
    return ApiResult.ok(project.copy());
  }

  // ------------------------------------------------------- versions and builds

  /// The history of the projects, keyed by their id.
  final Map<String, ProjectHistory> histories = <String, ProjectHistory>{};

  @override
  Future<ApiResult<ProjectHistory>> getProjectHistory(
      String token, String projectId) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    return ApiResult.ok(
        histories[projectId] ?? ProjectHistory(projectId: projectId));
  }

  @override
  Future<ApiResult<ProjectHistory>> createProjectVersion(
    String token,
    String projectId,
    String summary,
    int revision, {
    int scenesCount = 0,
    int filesCount = 0,
    List<String>? sceneNames,
  }) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    final history = histories[projectId] ??
        ProjectHistory(projectId: projectId);
    history.versions.insert(
        0,
        ProjectVersion(
          revision: revision,
          date: DateTime.now().toUtc(),
          author: user,
          summary: summary,
          scenesCount: scenesCount,
          filesCount: filesCount,
          sceneNames: sceneNames,
        ));
    histories[projectId] = history;
    return ApiResult.ok(history);
  }

  @override
  Future<ApiResult<ProjectHistory>> recordProjectBuild(
      String token, String projectId, BuildRecord build) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    final history = histories[projectId] ??
        ProjectHistory(projectId: projectId);
    history.builds.insert(0, build);
    histories[projectId] = history;
    return ApiResult.ok(history);
  }

  @override
  Future<ApiResult<Project>> removeProjectMember(
      String token, String projectId, String email) async {
    if (offline) return _fail(ApiStatus.offline, null);
    final user = _emailFromToken(token);
    if (user == null) return _fail(ApiStatus.unauthorized, null);
    final project = sharedProjects[projectId];
    if (project == null) return _fail(ApiStatus.invalid, 'Project not found.');
    project.members.removeWhere((m) => m.email == email);
    return ApiResult.ok(project.copy());
  }
}