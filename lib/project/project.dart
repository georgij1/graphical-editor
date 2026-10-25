class SceneFile {
  SceneFile({required this.name, required this.fxml, this.controllerClass});

  String name;
  String fxml;
  String? controllerClass;

  Map<String, dynamic> toJson() => {
        'name': name,
        'fxml': fxml,
        if (controllerClass != null && controllerClass!.isNotEmpty)
          'controller': controllerClass,
      };

  factory SceneFile.fromJson(Map<String, dynamic> json) => SceneFile(
        name: json['name'] as String,
        fxml: json['fxml'] as String,
        controllerClass: json['controller'] as String?,
      );

  SceneFile copy() => SceneFile(
        name: name,
        fxml: fxml,
        controllerClass: controllerClass,
      );
}

/// A person who takes part in a shared project.
class ProjectMember {
  ProjectMember({required this.email, this.role = 'editor'});

  /// Login of the participant.
  final String email;

  /// `editor` may change the project, `viewer` may only read it.
  String role;

  bool get canEdit => role == 'editor';

  Map<String, dynamic> toJson() => {'email': email, 'role': role};

  factory ProjectMember.fromJson(Map<String, dynamic> json) => ProjectMember(
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'editor',
      );
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.package,
    required this.mainClass,
    this.description = '',
    this.ownerId,
    this.ownerEmail,
    this.revision = 0,
    this.shared = false,
    List<SceneFile>? scenes,
    Map<String, String>? sourceOverrides,
    List<ProjectMember>? members,
  })  : scenes = scenes ?? [],
        sourceOverrides = sourceOverrides ?? <String, String>{},
        members = members ?? <ProjectMember>[];

  String id;
  String name;
  String package;
  String mainClass;
  String description;

  /// Identifier of the account the project belongs to. Null for projects that
  /// were created before the owner was known (guest work).
  String? ownerId;

  /// Login of the owner, shown in the project card and in its settings.
  String? ownerEmail;

  /// Revision of the shared copy; it grows with every save and tells the
  /// participants that somebody else has changed the project.
  int revision;

  /// True when the project is shared with other people.
  bool shared;

  /// People who take part in the project.
  final List<ProjectMember> members;

  /// True when the project is worked on by more than one person.
  bool get collaborative => members.isNotEmpty;

  /// Participants besides the owner.
  List<ProjectMember> get participants =>
      members.where((m) => m.email != ownerEmail).toList();

  /// Replaces the list of participants.
  void replaceMembers(Iterable<ProjectMember> value) {
    members
      ..clear()
      ..addAll(value);
  }

  final List<SceneFile> scenes;

  /// Hand-edited copies of generated Java sources, keyed by file path. When a
  /// path is present its content replaces the auto-generated source.
  final Map<String, String> sourceOverrides;

  /// True when the project belongs to the account [userId].
  bool belongsTo(String? userId) =>
      userId != null && ownerId != null && ownerId == userId;

  /// Assigns the owner of the project. Projects of a different account are
  /// never re-assigned, so nobody can take them over by accident.
  void assignOwner(String? userId, String? email) {
    if (userId == null || userId.isEmpty) return;
    if (ownerId != null && ownerId != userId) return;
    ownerId = userId;
    if (email != null && email.isNotEmpty) ownerEmail = email;
  }

  SceneFile? get mainScene {
    if (scenes.isEmpty) return null;
    for (final s in scenes) {
      if (s.name.toLowerCase() == 'main') return s;
    }
    return scenes.first;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'package': package,
        'mainClass': mainClass,
        'description': description,
        if (ownerId != null) 'ownerId': ownerId,
        if (ownerEmail != null) 'ownerEmail': ownerEmail,
        if (revision > 0) 'revision': revision,
        if (shared) 'shared': true,
        if (members.isNotEmpty)
          'members': [for (final m in members) m.toJson()],
        'scenes': scenes.map((s) => s.toJson()).toList(),
        if (sourceOverrides.isNotEmpty) 'sources': sourceOverrides,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        package: (json['package'] as String?) ?? '',
        mainClass: (json['mainClass'] as String?) ?? 'MainApp',
        description: (json['description'] as String?) ?? '',
        ownerId: json['ownerId'] as String?,
        ownerEmail: json['ownerEmail'] as String?,
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        shared: json['shared'] as bool? ?? false,
        members: [
          for (final m in (json['members'] as List? ?? []))
            ProjectMember.fromJson(m as Map<String, dynamic>),
        ],
        scenes: [
          for (final s in (json['scenes'] as List? ?? []))
            SceneFile.fromJson(s as Map<String, dynamic>),
        ],
        sourceOverrides: {
          for (final e in (json['sources'] as Map? ?? {}).entries)
            e.key as String: e.value as String,
        },
      );

  Project copy() => Project(
        id: id,
        name: name,
        package: package,
        mainClass: mainClass,
        description: description,
        ownerId: ownerId,
        ownerEmail: ownerEmail,
        revision: revision,
        shared: shared,
        members: [for (final m in members) ProjectMember(email: m.email, role: m.role)],
        scenes: [for (final s in scenes) s.copy()],
        sourceOverrides: Map<String, String>.from(sourceOverrides),
      );
}

class WorkspaceData {
  WorkspaceData({required this.projects, this.document, this.documentName});

  final List<Project> projects;

  /// FXML of a document opened outside of any project, so it survives a
  /// reload. Saving writes here instead of downloading a file.
  final String? document;

  /// File name shown for [document], without the extension.
  final String? documentName;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'projects': projects.map((p) => p.toJson()).toList(),
        if (document != null) 'document': document,
        if (documentName != null) 'documentName': documentName,
      };

  factory WorkspaceData.fromJson(Map<String, dynamic> json) => WorkspaceData(
        projects: [
          for (final p in (json['projects'] as List? ?? []))
            Project.fromJson(p as Map<String, dynamic>),
        ],
        document: json['document'] as String?,
        documentName: json['documentName'] as String?,
      );
}