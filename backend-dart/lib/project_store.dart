import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'security.dart';
/// A person who may open a shared project.
class ProjectMember {
  ProjectMember({required this.email, this.role = 'editor'});

  /// Login of the participant.
  final String email;

  /// `editor` may change the project, `viewer` may only read it.
  String role;

  Map<String, dynamic> toJson() => {'email': email, 'role': role};

  factory ProjectMember.fromJson(Map<String, dynamic> json) => ProjectMember(
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'editor',
      );
}

/// A project that several people work on together.
///
/// The file keeps the project itself (name, package, scenes, sources), the
/// list of participants and the revision counter used to synchronise the
/// participants.
class SharedProject {
  SharedProject({
    required this.id,
    required this.name,
    required this.package,
    required this.mainClass,
    this.description = '',
    this.ownerId = '',
    this.ownerEmail = '',
    this.revision = 1,
    this.inviteToken,
    this.inviteRole = 'editor',
    List<ProjectMember>? members,
    List<Map<String, dynamic>>? scenes,
    Map<String, String>? sources,
  })  : members = members ?? <ProjectMember>[],
        scenes = scenes ?? <Map<String, dynamic>>[],
        sources = sources ?? <String, String>{};

  final String id;
  String name;
  String package;
  String mainClass;
  String description;

  /// Account that created the project.
  String ownerId;
  String ownerEmail;

  /// Increases with every save; the clients compare it to know when the
  /// project was changed by somebody else.
  int revision;

  /// Participants of the project.
  List<ProjectMember> members;

  /// Token of the invitation link. It lets another account join the project
  /// without being invited by mail.
  String? inviteToken;

  /// Rights the invited person receives: editor or viewer.
  String inviteRole;

  /// Issues a new invitation link.
  String createInvite(String role) {
    inviteRole = role;
    inviteToken =
        base64Url.encode(randomBytes(24)).replaceAll('=', '');
    return inviteToken!;
  }

  /// True when the token opens the invitation.
  bool matchesInvite(String token) =>
      inviteToken != null && inviteToken!.isNotEmpty && inviteToken == token;

  /// Scenes of the project: `name`, `fxml` and `controller`.
  List<Map<String, dynamic>> scenes;

  /// Hand-edited sources, keyed by file path.
  Map<String, String> sources;

  DateTime updatedAt = DateTime.now().toUtc();

  bool get isOwner => ownerId.isNotEmpty;

  ProjectMember? memberOf(String email) {
    for (final m in members) {
      if (m.email.toLowerCase() == email.toLowerCase()) return m;
    }
    return null;
  }

  /// True when [userId]/[email] may change the project.
  bool canEdit(String userId, String email) {
    if (ownerId.isNotEmpty && ownerId == userId) return true;
    final member = memberOf(email);
    return member != null && member.role == 'editor';
  }

  /// True when [userId]/[email] may open the project at all.
  bool canRead(String userId, String email) {
    if (ownerId.isNotEmpty && ownerId == userId) return true;
    if (ownerEmail.isNotEmpty &&
        ownerEmail.toLowerCase() == email.toLowerCase()) {
      return true;
    }
    return memberOf(email) != null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'package': package,
        'mainClass': mainClass,
        'description': description,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'revision': revision,
        if (inviteToken != null) 'inviteToken': inviteToken,
        'inviteRole': inviteRole,
        'members': [for (final m in members) m.toJson()],
        'scenes': scenes,
        'sources': sources,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SharedProject.fromJson(Map<String, dynamic> json) => SharedProject(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        package: json['package'] as String? ?? '',
        mainClass: json['mainClass'] as String? ?? 'MainApp',
        description: json['description'] as String? ?? '',
        ownerId: json['ownerId'] as String? ?? '',
        ownerEmail: json['ownerEmail'] as String? ?? '',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        inviteToken: json['inviteToken'] as String?,
        inviteRole: json['inviteRole'] as String? ?? 'editor',
        members: [
          for (final m in (json['members'] as List? ?? []))
            ProjectMember.fromJson(m as Map<String, dynamic>),
        ],
        scenes: [
          for (final s in (json['scenes'] as List? ?? []))
            Map<String, dynamic>.from(s as Map),
        ],
        sources: {
          for (final e in (json['sources'] as Map? ?? {}).entries)
            e.key as String: e.value as String,
        },
      );
}

/// Stores the projects that are shared between several accounts.
class ProjectStore {
  ProjectStore(this.dataDir);

  final String dataDir;
  Future<void> _lock = Future.value();

  Directory get _projectsDir => Directory('$dataDir/projects');

  Future<void> init() async {
    await _projectsDir.create(recursive: true);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(() => completer.complete());
  }

  File _file(String id) => File('${_projectsDir.path}/$id.json');

  Future<SharedProject?> find(String id) async {
    final file = _file(id);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return SharedProject.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// All projects the account may open: the ones it owns and the ones it was
  /// invited to.
  Future<List<SharedProject>> listFor(String userId, String email) async {
    final result = <SharedProject>[];
    if (!await _projectsDir.exists()) return result;
    await for (final entity in _projectsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        final project =
            SharedProject.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (project.canRead(userId, email)) result.add(project);
      } catch (_) {
        // A damaged file must not break the whole list.
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Finds the project an invitation link points to.
  Future<SharedProject?> findByInvite(String token) async {
    if (token.isEmpty) return null;
    for (final project in await listAll()) {
      if (project.matchesInvite(token)) return project;
    }
    return null;
  }

  /// Every stored project, used to look for an invitation.
  Future<List<SharedProject>> listAll() async {
    final result = <SharedProject>[];
    if (!await _projectsDir.exists()) return result;
    await for (final entity in _projectsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        result.add(SharedProject.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // A damaged file must not break the whole list.
      }
    }
    return result;
  }

  /// Saves the project and moves the revision counter forward.
  Future<SharedProject> save(SharedProject project) {    return _synchronized(() async {
      project.revision += 1;
      project.updatedAt = DateTime.now().toUtc();
      await _projectsDir.create(recursive: true);
      await _file(project.id)
          .writeAsString(jsonEncode(project.toJson()), flush: true);
      return project;
    });
  }

  Future<void> delete(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}
