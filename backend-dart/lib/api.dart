import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'project_store.dart';
import 'history_store.dart';
import 'security.dart';
import 'store.dart';

const _emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';

Response _json(int status, Object? body) => Response(status,
    body: jsonEncode(body), headers: {'content-type': 'application/json'});

Response _error(int status, String message) => _json(status, {'error': message});

String _token(UserRecord user, String secret) =>
    signJwt({'sub': user.id, 'email': user.email}, secret);

Map<String, dynamic> _profile(UserRecord user) => <String, dynamic>{
      'id': user.id,
      'email': user.email,
      'avatar': user.avatar,
    };

Future<UserRecord?> _authenticate(
    Request request, UserStore store, String secret) async {
  final header = request.headers['authorization'] ?? '';
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  final token = header.substring(7).trim();
  final claims = verifyJwt(token, secret);
  if (claims == null) return null;
  final id = claims['sub'] as String?;
  if (id == null) return null;
  return store.findById(id);
}

Handler buildHandler(
    {required String secret,
    required UserStore store,
    required ProjectStore projects,
    HistoryStore? history}) {
  final router = Router();
  final historyStore = history ?? HistoryStore(store.dataDir);

  router.post('/api/auth/register', (Request request) async {
    final body = await _readBody(request);
    final email = (body['email'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    if (!RegExp(_emailRegex).hasMatch(email)) {
      return _error(400, 'Enter a valid email address.');
    }
    if (password.length < 6) {
      return _error(400, 'Password must be at least 6 characters.');
    }
    UserRecord user;
    try {
      user = await store.createUser(email, password);
    } on EmailTakenException {
      return _error(409, 'This email is already registered.');
    }
    final token = signJwt({'sub': user.id, 'email': user.email}, secret);
    return _json(201, {'id': user.id, 'email': user.email, 'token': token});
  });

  router.post('/api/auth/login', (Request request) async {
    final body = await _readBody(request);
    final email = (body['email'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    final user = await store.findByEmail(email);
    if (user == null || !verifyPassword(password, user.salt, user.hash)) {
      return _error(401, 'Invalid email or password.');
    }
    final token = signJwt({'sub': user.id, 'email': user.email}, secret);
    return _json(200, {'id': user.id, 'email': user.email, 'token': token});
  });

  router.get('/api/me', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    return _json(200, _profile(user));
  });

  // Changes the login. A fresh token is issued because the old one carries
  // the previous address in its claims.
  router.patch('/api/me', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final body = await _readBody(request);
    final email = (body['email'] as String? ?? '').trim();
    if (!RegExp(_emailRegex).hasMatch(email)) {
      return _error(400, 'Enter a valid email address.');
    }
    if (email.toLowerCase() == user.email) {
      return _json(200, {..._profile(user), 'token': _token(user, secret)});
    }
    try {
      final updated = await store.updateEmail(user.id, email);
      return _json(200, {..._profile(updated), 'token': _token(updated, secret)});
    } on EmailTakenException {
      return _error(409, 'This email is already registered.');
    }
  });

  router.post('/api/me/password', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final body = await _readBody(request);
    final current = body['currentPassword'] as String? ?? '';
    final next = body['newPassword'] as String? ?? '';
    if (next.length < 6) {
      return _error(400, 'Password must be at least 6 characters.');
    }
    try {
      await store.updatePassword(user.id, current, next);
      return Response(204);
    } on WrongPasswordException {
      return _error(400, 'Current password is incorrect.');
    }
  });

  router.put('/api/me/avatar', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final body = await _readBody(request);
    final avatar = body['avatar'] as String?;
    try {
      final updated = await store.updateAvatar(user.id, avatar);
      return _json(200, {'avatar': updated.avatar});
    } on AvatarTooLargeException {
      return _error(413, 'The picture is too large.');
    }
  });

  router.get('/api/workspace', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final workspace = await store.readWorkspace(user.id);
    return _json(200, workspace == null ? {'projects': <dynamic>[]} : jsonDecode(workspace));
  });

  router.put('/api/workspace', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final body = await request.readAsString();
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('projects')) {
        return _error(400, 'Invalid workspace payload.');
      }
    } catch (_) {
      return _error(400, 'Invalid JSON.');
    }
    await store.writeWorkspace(user.id, body);
    return Response(204);
  });

  _projectRoutes(router,
      secret: secret,
      store: store,
      projects: projects,
      history: historyStore);

  return _cors()(router.call);
}

/// Routes of the shared projects: the ones several accounts work on.
void _projectRoutes(
  Router router, {
  required String secret,
  required UserStore store,
  required ProjectStore projects,
  required HistoryStore history,
}) {
  // In-memory presence: projectId -> { userId -> {id, email, avatar, lastSeen} }.
  // Entries older than a minute are treated as offline.
  final presence = <String, Map<String, Map<String, dynamic>>>{};

  router.get('/api/users', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final accounts = await store.listAccounts();
    return _json(200, {'accounts': accounts});
  });

  // All projects the account may open: its own and the shared ones.
  router.get('/api/projects', (Request request) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final list = await projects.listFor(user.id, user.email);
    return _json(200, {
      'projects': [for (final p in list) p.toJson()],
    });
  });

  // One shared project with its participants.
  router.get('/api/projects/<id>', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canRead(user.id, user.email)) {
      return _error(403, 'This project is not shared with you.');
    }
    return _json(200, project.toJson());
  });

  // Creates or updates a shared project.
  router.put('/api/projects/<id>', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final body = await _readBody(request);
    final existing = await projects.find(id);
    if (existing != null && !existing.canEdit(user.id, user.email)) {
      return _error(403, 'You cannot change this project.');
    }
    final project = SharedProject.fromJson(<String, dynamic>{
      ...body,
      'id': id,
      'ownerId': existing?.ownerId ?? user.id,
      'ownerEmail': existing?.ownerEmail ?? user.email,
      'revision': existing?.revision ?? 0,
    });
    if (project.ownerId == user.id) {
      // The owner decides who takes part, so the list of participants is only
      // taken from the request when the owner sends it.
      final members = body['members'];
      if (members is List) {
        project.members = [
          for (final m in members)
            ProjectMember.fromJson(m as Map<String, dynamic>),
        ];
      }
    } else {
      project.members = existing?.members ?? <ProjectMember>[];
    }
    final saved = await projects.save(project);
    return _json(200, saved.toJson());
  });

  // Adds a participant to the project.
  router.post('/api/projects/<id>/members', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (project.ownerId != user.id) {
      return _error(403, 'Only the owner can invite people.');
    }
    final body = await _readBody(request);
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    if (!RegExp(_emailRegex).hasMatch(email)) {
      return _error(400, 'Enter a valid email address.');
    }
    final role = body['role'] as String? ?? 'editor';
    if (role != 'editor' && role != 'viewer') {
      return _error(400, 'Unknown role.');
    }
    final member = project.memberOf(email);
    if (member != null) {
      member.role = role;
    } else {
      project.members.add(ProjectMember(email: email, role: role));
    }
    final saved = await projects.save(project);
    return _json(200, saved.toJson());
  });

  // Removes a participant from the project.
  router.delete('/api/projects/<id>/members/<email>',
      (Request request, String id, String email) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (project.ownerId != user.id) {
      return _error(403, 'Only the owner can remove people.');
    }
    project.members
        .removeWhere((m) => m.email.toLowerCase() == email.toLowerCase());
    final saved = await projects.save(project);
    return _json(200, saved.toJson());
  });

  // Removes the project for everybody.
  router.delete('/api/projects/<id>', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (project.ownerId != user.id) {
      return _error(403, 'Only the owner can delete the project.');
    }
    await projects.delete(id);
    presence.remove(id);
    return Response(204);
  });

  // Presence: a participant announces that they have the project open.
  router.post('/api/projects/<id>/presence', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canRead(user.id, user.email)) {
      return _error(403, 'You cannot open this project.');
    }
    final bucket = presence.putIfAbsent(id, () => <String, Map<String, dynamic>>{});
    bucket[user.id] = <String, dynamic>{
      'id': user.id,
      'email': user.email,
      'avatar': user.avatar,
      'lastSeen': DateTime.now().toUtc().toIso8601String(),
    };
    return _json(200, {'ok': true});
  });

  // Presence: who is currently in the project (seen within the last minute).
  router.get('/api/projects/<id>/presence', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canRead(user.id, user.email)) {
      return _error(403, 'You cannot open this project.');
    }
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(seconds: 60));
    final bucket = presence[id];
    final result = <Map<String, dynamic>>[];
    if (bucket != null) {
      final stale = <String>[];
      for (final entry in bucket.entries) {
        final lastSeen = DateTime.tryParse(entry.value['lastSeen'] as String? ?? '');
        if (lastSeen == null || lastSeen.isBefore(cutoff)) {
          stale.add(entry.key);
        } else {
          result.add(entry.value);
        }
      }
      for (final key in stale) {
        bucket.remove(key);
      }
    }
    return _json(200, {'participants': result});
  });

  // Issues an invitation link for the project.
  router.post('/api/projects/<id>/invite', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (project.ownerId != user.id) {
      return _error(403, 'Only the owner can invite people.');
    }
    final body = await _readBody(request);
    final role = body['role'] as String? ?? 'editor';
    if (role != 'editor' && role != 'viewer') {
      return _error(400, 'Unknown role.');
    }
    final token = project.createInvite(role);
    await projects.save(project);
    return _json(200, {'token': token, 'role': role});
  });

  // Information about the project an invitation link points to.
  router.get('/api/invites/<token>', (Request request, String token) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.findByInvite(token);
    if (project == null) return _error(404, 'The invitation is not valid.');
    return _json(200, {
      'projectId': project.id,
      'projectName': project.name,
      'ownerEmail': project.ownerEmail,
      'role': project.inviteRole,
    });
  });

  // Joins the project with the token of the invitation link.
  router.post('/api/projects/<id>/join', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    final body = await _readBody(request);
    final token = body['token'] as String? ?? '';
    if (!project.matchesInvite(token)) {
      return _error(403, 'The invitation is not valid.');
    }
    if (!project.canEdit(user.id, user.email)) {
      project.members.add(ProjectMember(email: user.email, role: project.inviteRole));
    }
    final saved = await projects.save(project);
    return _json(200, saved.toJson());
  });

  // The history of the project: the released versions and the builds.
  router.get('/api/projects/<id>/history', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canRead(user.id, user.email)) {
      return _error(403, 'This project is not shared with you.');
    }
    final stored = await history.read(id);
    return _json(200, stored.toJson());
  });

  // Releases a new version of the project.
  router.post('/api/projects/<id>/versions', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canEdit(user.id, user.email)) {
      return _error(403, 'You cannot change this project.');
    }
    final body = await _readBody(request);
    final entry = VersionEntry(
      revision: (body['revision'] as num?)?.toInt() ?? project.revision,
      date: DateTime.now().toUtc(),
      author: user.email,
      summary: body['summary'] as String? ?? '',
      scenesCount: (body['scenesCount'] as num?)?.toInt() ?? 0,
      filesCount: (body['filesCount'] as num?)?.toInt() ?? 0,
    );
    final stored = await history.addVersion(id, entry);
    return _json(200, stored.toJson());
  });

  // Records the result of a build.
  router.post('/api/projects/<id>/builds', (Request request, String id) async {
    final user = await _authenticate(request, store, secret);
    if (user == null) return _error(401, 'Not authenticated.');
    final project = await projects.find(id);
    if (project == null) return _error(404, 'Project not found.');
    if (!project.canEdit(user.id, user.email)) {
      return _error(403, 'You cannot change this project.');
    }
    final body = await _readBody(request);
    final entry = BuildEntry(
      id: body['id'] as String? ?? '',
      version: (body['version'] as num?)?.toInt() ?? project.revision,
      date: DateTime.now().toUtc(),
      author: user.email,
      status: body['status'] as String? ?? 'failed',
      log: body['log'] as String? ?? '',
      artifact: body['artifact'] as String? ?? '',
      durationMs: (body['durationMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (body['sizeBytes'] as num?)?.toInt() ?? 0,
    );
    final stored = await history.addBuild(id, entry);
    return _json(200, stored.toJson());
  });
}

Future<Map<String, dynamic>> _readBody(Request request) async {
  try {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

Middleware _cors() {
  const headers = <String, String>{
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') {
      return Response(204, headers: headers);
    }
    final response = await inner(request);
    return response.change(headers: headers);
  };
}