import 'dart:convert';

import 'package:http/http.dart' as http;

import '../project/project.dart';
import '../project/project_history.dart';

/// Result of an API call: either a typed value or an error classification.
class ApiResult<T> {
  ApiResult.ok(this.value)
      : status = ApiStatus.ok,
        message = null;

  ApiResult.failure(this.status, this.message) : value = null;

  final ApiStatus status;
  final T? value;
  final String? message;

  bool get isOk => status == ApiStatus.ok;
}

enum ApiStatus { ok, unauthorized, invalid, offline }

class AuthUser {
  AuthUser({required this.email, required this.token, this.id, this.avatar});

  final String email;
  final String token;

  /// Identifier of the account. Used to bind projects to their owner.
  final String? id;

  /// Profile picture as a `data:` URL, or null.
  final String? avatar;
}

/// Login and profile picture of the signed-in account.
class Profile {
  const Profile({required this.email, this.id, this.avatar});

  final String email;

  /// Identifier of the account.
  final String? id;
  final String? avatar;
}

/// A registered account of the system. Used to pick the participants of a
/// project from the list.
class Account {
  const Account({required this.id, required this.email});

  final String id;
  final String email;
}

/// An invitation to a project: the token of the link and the rights the
/// invited person receives.
class ProjectInvite {
  const ProjectInvite({
    required this.token,
    required this.role,
    this.projectId = '',
    this.projectName = '',
    this.ownerEmail = '',
  });

  /// Token of the invitation link.
  final String token;

  /// Rights of the invited person: editor or viewer.
  final String role;

  /// The project the invitation points to.
  final String projectId;
  final String projectName;
  final String ownerEmail;
}

/// Client for the FXML editor auth + storage backend.
abstract class ApiClient {
  Future<ApiResult<AuthUser>> register(String email, String password);
  Future<ApiResult<AuthUser>> login(String email, String password);
  Future<ApiResult<String?>> getWorkspace(String token);
  Future<ApiResult<void>> putWorkspace(String token, String workspaceJson);

  // ------------------------------------------------------------- shared projects

  /// The accounts registered in the system.
  Future<ApiResult<List<Account>>> listAccounts(String token);

  /// The projects the account owns or takes part in.
  Future<ApiResult<List<Project>>> listSharedProjects(String token);

  /// One shared project with its participants.
  Future<ApiResult<Project>> getSharedProject(String token, String projectId);

  /// Creates or updates a shared project.
  Future<ApiResult<Project>> saveSharedProject(String token, Project project);

  /// Removes the project for everybody.
  Future<ApiResult<void>> deleteSharedProject(String token, String projectId);

  /// Invites a person to the project.
  Future<ApiResult<Project>> addProjectMember(
      String token, String projectId, String email, String role);

  /// Removes a person from the project.
  Future<ApiResult<Project>> removeProjectMember(
      String token, String projectId, String email);

  // ---------------------------------------------------------- invitation links

  /// Issues an invitation link for the project.
  Future<ApiResult<ProjectInvite>> createProjectInvite(
      String token, String projectId, String role);

  /// Reads the project an invitation link points to.
  Future<ApiResult<ProjectInvite>> getProjectInvite(
      String token, String inviteToken);

  /// Joins the project with the token of the invitation link.
  Future<ApiResult<Project>> joinProject(
      String token, String projectId, String inviteToken);

  // ------------------------------------------------------- versions and builds

  /// The released versions and the builds of the project.
  Future<ApiResult<ProjectHistory>> getProjectHistory(
      String token, String projectId);

  /// Releases a new version of the project.
  Future<ApiResult<ProjectHistory>> createProjectVersion(
      String token, String projectId, String summary, int revision,
      {int scenesCount = 0, int filesCount = 0, List<String>? sceneNames});

  /// Records the result of a build in the history of the project.
  Future<ApiResult<ProjectHistory>> recordProjectBuild(
      String token, String projectId, BuildRecord build);

  /// Reads the profile of [token]; the result may be null when signed out.
  Future<ApiResult<Profile?>> getProfile(String token);

  /// Changes the login and returns a session carrying a refreshed token.
  Future<ApiResult<AuthUser>> updateEmail(String token, String email);

  Future<ApiResult<void>> changePassword(
      String token, String currentPassword, String newPassword);

  /// Uploads (or clears, when [avatar] is null) the profile picture.
  Future<ApiResult<String?>> updateAvatar(String token, String? avatar);
}

class HttpApiClient implements ApiClient {
  HttpApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _configuredBaseUrl(),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 10);

  /// Base URL of the API, including the `/api` prefix. Override at build time
  /// with `--dart-define=API_BASE_URL=/api` (same-origin nginx proxy, used in
  /// Docker); defaults to the local backend for development.
  static String _configuredBaseUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'http://localhost:8080/api';
  }

  /// Builds an absolute URI. Relative bases (e.g. `/api`) are resolved against
  /// the page's own origin so the browser never needs to know the backend host.
  Uri _uri(String path) {
    final full = Uri.parse('$baseUrl$path');
    if (full.hasScheme) return full;
    return Uri.base.resolve(full.toString());
  }

  Future<ApiResult<Map<String, dynamic>>> _post(String path,
      [Map<String, dynamic>? body]) async {
    try {
      final response = await _client
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body ?? const <String, dynamic>{}),
          )
          .timeout(_timeout);
      return _decode(response);
    } on Exception {
      return ApiResult<Map<String, dynamic>>.failure(
          ApiStatus.offline, 'Cannot reach the server.');
    }
  }

  ApiResult<Map<String, dynamic>> _decode(http.Response response) {
    if (response.statusCode == 401) {
      return ApiResult<Map<String, dynamic>>.failure(
          ApiStatus.unauthorized, 'Invalid email or password.');
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResult.ok(data ?? <String, dynamic>{});
    }
    final message = (data?['error'] as String?) ?? 'Server error.';
    return ApiResult<Map<String, dynamic>>.failure(ApiStatus.invalid, message);
  }

  @override
  Future<ApiResult<AuthUser>> register(String email, String password) async {
    final result = await _post('/auth/register', {
      'email': email,
      'password': password,
    });
    if (!result.isOk || result.value == null) {
      return ApiResult<AuthUser>.failure(result.status, result.message);
    }
    return ApiResult.ok(AuthUser(
      email: result.value!['email'] as String,
      token: result.value!['token'] as String,
      id: result.value!['id'] as String?,
    ));
  }

  @override
  Future<ApiResult<AuthUser>> login(String email, String password) async {
    final result = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    if (!result.isOk || result.value == null) {
      return ApiResult<AuthUser>.failure(result.status, result.message);
    }
    return ApiResult.ok(AuthUser(
      email: result.value!['email'] as String,
      token: result.value!['token'] as String,
      id: result.value!['id'] as String?,
    ));
  }

  @override
  Future<ApiResult<Profile?>> getProfile(String token) async {
    try {
      final response = await _client
          .get(
            _uri('/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        return ApiResult<Profile?>.failure(ApiStatus.unauthorized, null);
      }
      final data = _decode(response);
      if (!data.isOk || data.value == null) {
        return ApiResult<Profile?>.failure(data.status, data.message);
      }
      return ApiResult.ok(Profile(
        email: data.value!['email'] as String,
        id: data.value!['id'] as String?,
        avatar: data.value!['avatar'] as String?,
      ));
    } on Exception {
      return ApiResult<Profile?>.failure(ApiStatus.offline, null);
    }
  }

  @override
  Future<ApiResult<AuthUser>> updateEmail(String token, String email) async {
    try {
      final response = await _client
          .patch(
            _uri('/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{'email': email}),
          )
          .timeout(_timeout);
      final result = _decode(response);
      if (!result.isOk || result.value == null) {
        return ApiResult<AuthUser>.failure(result.status, result.message);
      }
      return ApiResult.ok(AuthUser(
        email: result.value!['email'] as String,
        token: result.value!['token'] as String,
        id: result.value!['id'] as String?,
        avatar: result.value!['avatar'] as String?,
      ));
    } on Exception {
      return ApiResult<AuthUser>.failure(ApiStatus.offline, null);
    }
  }

  @override
  Future<ApiResult<void>> changePassword(
      String token, String currentPassword, String newPassword) async {
    try {
      final response = await _client
          .post(
            _uri('/me/password'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        return ApiResult<void>.failure(ApiStatus.unauthorized, null);
      }
      if (response.statusCode == 204) {
        return ApiResult<void>.ok(null);
      }
      final data = _decode(response);
      return ApiResult<void>.failure(data.status, data.message);
    } on Exception {
      return ApiResult<void>.failure(ApiStatus.offline, null);
    }
  }

  // ------------------------------------------------------------- shared projects

  /// Sends a request to the shared project API and decodes the answer.
  Future<ApiResult<Map<String, dynamic>>> _projectRequest(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, _uri(path))
        ..headers.addAll(<String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response =
          await _client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode == 204) {
        return ApiResult<Map<String, dynamic>>.ok(<String, dynamic>{});
      }
      final text = await response.stream.bytesToString();
      if (response.statusCode == 401) {
        return ApiResult<Map<String, dynamic>>.failure(
            ApiStatus.unauthorized, 'Not authenticated.');
      }
      if (response.statusCode == 403) {
        return ApiResult<Map<String, dynamic>>.failure(
            ApiStatus.invalid, 'This project is not shared with you.');
      }
      if (response.statusCode == 404) {
        return ApiResult<Map<String, dynamic>>.failure(
            ApiStatus.invalid, 'Project not found.');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return ApiResult<Map<String, dynamic>>.failure(
            ApiStatus.invalid, 'Unexpected answer from the server.');
      }
      if (response.statusCode >= 400) {
        return ApiResult<Map<String, dynamic>>.failure(ApiStatus.invalid,
            decoded['error'] as String? ?? 'Server error.');
      }
      return ApiResult<Map<String, dynamic>>.ok(decoded);
    } on Exception {
      return ApiResult<Map<String, dynamic>>.failure(
          ApiStatus.offline, 'Cannot reach the server.');
    }
  }

  @override
  Future<ApiResult<List<Account>>> listAccounts(String token) async {
    final result = await _projectRequest('GET', '/users', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<List<Account>>.failure(result.status, result.message);
    }
    final list = result.value!['accounts'] as List? ?? <dynamic>[];
    return ApiResult<List<Account>>.ok([
      for (final item in list)
        Account(
          id: (item as Map<String, dynamic>)['id'] as String? ?? '',
          email: item['email'] as String? ?? '',
        ),
    ]);
  }

  @override
  Future<ApiResult<List<Project>>> listSharedProjects(String token) async {
    final result = await _projectRequest('GET', '/projects', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<List<Project>>.failure(result.status, result.message);
    }
    final list = result.value!['projects'] as List? ?? <dynamic>[];
    return ApiResult<List<Project>>.ok([
      for (final item in list)
        Project.fromJson(item as Map<String, dynamic>)..shared = true,
    ]);
  }

  @override
  Future<ApiResult<Project>> getSharedProject(
      String token, String projectId) async {
    final result = await _projectRequest('GET', '/projects/$projectId', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<Project>.failure(result.status, result.message);
    }
    return ApiResult<Project>.ok(
        Project.fromJson(result.value!)..shared = true);
  }

  @override
  Future<ApiResult<Project>> saveSharedProject(
      String token, Project project) async {
    final result = await _projectRequest('PUT', '/projects/${project.id}', token,
        body: project.toJson());
    if (!result.isOk || result.value == null) {
      return ApiResult<Project>.failure(result.status, result.message);
    }
    return ApiResult<Project>.ok(
        Project.fromJson(result.value!)..shared = true);
  }

  @override
  Future<ApiResult<void>> deleteSharedProject(
      String token, String projectId) async {
    final result =
        await _projectRequest('DELETE', '/projects/$projectId', token);
    if (!result.isOk) {
      return ApiResult<void>.failure(result.status, result.message);
    }
    return ApiResult<void>.ok(null);
  }

  @override
  Future<ApiResult<Project>> addProjectMember(
      String token, String projectId, String email, String role) async {
    final result = await _projectRequest(
        'POST', '/projects/$projectId/members', token,
        body: <String, dynamic>{'email': email, 'role': role});
    if (!result.isOk || result.value == null) {
      return ApiResult<Project>.failure(result.status, result.message);
    }
    return ApiResult<Project>.ok(
        Project.fromJson(result.value!)..shared = true);
  }

  @override
  Future<ApiResult<ProjectInvite>> createProjectInvite(
      String token, String projectId, String role) async {
    final result = await _projectRequest(
        'POST', '/projects/$projectId/invite', token,
        body: <String, dynamic>{'role': role});
    if (!result.isOk || result.value == null) {
      return ApiResult<ProjectInvite>.failure(result.status, result.message);
    }
    return ApiResult<ProjectInvite>.ok(ProjectInvite(
      token: result.value!['token'] as String? ?? '',
      role: result.value!['role'] as String? ?? 'editor',
      projectId: projectId,
    ));
  }

  @override
  Future<ApiResult<ProjectInvite>> getProjectInvite(
      String token, String inviteToken) async {
    final result = await _projectRequest('GET', '/invites/$inviteToken', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<ProjectInvite>.failure(result.status, result.message);
    }
    return ApiResult<ProjectInvite>.ok(ProjectInvite(
      token: inviteToken,
      role: result.value!['role'] as String? ?? 'editor',
      projectId: result.value!['projectId'] as String? ?? '',
      projectName: result.value!['projectName'] as String? ?? '',
      ownerEmail: result.value!['ownerEmail'] as String? ?? '',
    ));
  }

  @override
  Future<ApiResult<Project>> joinProject(
      String token, String projectId, String inviteToken) async {
    final result = await _projectRequest(
        'POST', '/projects/$projectId/join', token,
        body: <String, dynamic>{'token': inviteToken});
    if (!result.isOk || result.value == null) {
      return ApiResult<Project>.failure(result.status, result.message);
    }
    return ApiResult<Project>.ok(
        Project.fromJson(result.value!)..shared = true);
  }

  @override
  Future<ApiResult<ProjectHistory>> getProjectHistory(
      String token, String projectId) async {
    final result = await _projectRequest('GET', '/projects/$projectId/history', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<ProjectHistory>.failure(result.status, result.message);
    }
    return ApiResult<ProjectHistory>.ok(
        ProjectHistory.fromJson(result.value!));
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
    final result = await _projectRequest(
        'POST', '/projects/$projectId/versions', token,
        body: <String, dynamic>{
          'summary': summary,
          'revision': revision,
          'scenesCount': scenesCount,
          'filesCount': filesCount,
          'sceneNames': sceneNames,
        });
    if (!result.isOk || result.value == null) {
      return ApiResult<ProjectHistory>.failure(result.status, result.message);
    }
    return ApiResult<ProjectHistory>.ok(
        ProjectHistory.fromJson(result.value!));
  }

  @override
  Future<ApiResult<ProjectHistory>> recordProjectBuild(
      String token, String projectId, BuildRecord build) async {
    final result = await _projectRequest(
        'POST', '/projects/$projectId/builds', token,
        body: build.toJson());
    if (!result.isOk || result.value == null) {
      return ApiResult<ProjectHistory>.failure(result.status, result.message);
    }
    return ApiResult<ProjectHistory>.ok(
        ProjectHistory.fromJson(result.value!));
  }

  @override
  Future<ApiResult<Project>> removeProjectMember(
      String token, String projectId, String email) async {
    final result = await _projectRequest(
        'DELETE', '/projects/$projectId/members/$email', token);
    if (!result.isOk || result.value == null) {
      return ApiResult<Project>.failure(result.status, result.message);
    }
    return ApiResult<Project>.ok(
        Project.fromJson(result.value!)..shared = true);
  }

  @override
  Future<ApiResult<String?>> updateAvatar(String token, String? avatar) async {
    try {
      final response = await _client
          .put(
            _uri('/me/avatar'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{'avatar': avatar}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        return ApiResult<String?>.failure(ApiStatus.unauthorized, null);
      }
      final data = _decode(response);
      if (!data.isOk) return ApiResult<String?>.failure(data.status, data.message);
      return ApiResult.ok(data.value?['avatar'] as String?);
    } on Exception {
      return ApiResult<String?>.failure(ApiStatus.offline, null);
    }
  }

  @override
  Future<ApiResult<String?>> getWorkspace(String token) async {
    try {
      final response = await _client
          .get(
            _uri('/workspace'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        return ApiResult<String?>.failure(ApiStatus.unauthorized, null);
      }
      if (response.statusCode != 200) {
        return ApiResult<String?>.failure(ApiStatus.invalid, null);
      }
      return ApiResult.ok(response.body);
    } on Exception {
      return ApiResult<String?>.failure(ApiStatus.offline, null);
    }
  }

  @override
  Future<ApiResult<void>> putWorkspace(String token, String workspaceJson) async {
    try {
      final response = await _client
          .put(
            _uri('/workspace'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: workspaceJson,
          )
          .timeout(_timeout);
      if (response.statusCode == 401) {
        return ApiResult<void>.failure(ApiStatus.unauthorized, null);
      }
      if (response.statusCode != 204) {
        return ApiResult<void>.failure(ApiStatus.invalid, null);
      }
      return ApiResult.ok(null);
    } on Exception {
      return ApiResult<void>.failure(ApiStatus.offline, null);
    }
  }
}
