/// The history of a project: the released versions and the builds.
///
/// A version is released when the project is built: the state of the project
/// is fixed and gets a number. A build is the result of the compilation of
/// one of the versions.
library;

/// A released version of the project: the state that was published and built.
class ProjectVersion {
  ProjectVersion({
    required this.revision,
    required this.date,
    required this.author,
    this.summary = '',
    this.scenesCount = 0,
    this.filesCount = 0,
    List<String>? sceneNames,
  })  : sceneNames = sceneNames ?? <String>[];

  /// The revision of the project the version was made of.
  final int revision;
  final DateTime date;

  /// The account that released the version.
  final String author;

  /// What was changed in the release.
  final String summary;

  /// Number of the scenes in the release.
  final int scenesCount;

  /// Number of the generated files in the release.
  final int filesCount;

  /// Names of the scenes of the release, in the order of creation.
  final List<String> sceneNames;

  factory ProjectVersion.fromJson(Map<String, dynamic> json) => ProjectVersion(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        author: json['author'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        scenesCount: (json['scenesCount'] as num?)?.toInt() ?? 0,
        filesCount: (json['filesCount'] as num?)?.toInt() ?? 0,
        sceneNames: [
          for (final name in (json['sceneNames'] as List? ?? <String>[]))
            name as String? ?? '',
        ],
      );
}

/// The result of a build of a version.
class BuildRecord {
  const BuildRecord({
    required this.id,
    required this.version,
    required this.date,
    required this.author,
    required this.status,
    this.log = '',
    this.artifact = '',
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  final String id;

  /// The version the build was made of.
  final int version;
  final DateTime date;
  final String author;

  /// `ok` or `failed`.
  final String status;

  /// The output of the build service.
  final String log;

  /// The name of the produced file.
  final String artifact;

  /// How long the build took.
  final int durationMs;

  /// The size of the produced file.
  final int sizeBytes;

  bool get succeeded => status == 'ok';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'version': version,
        'date': date.toIso8601String(),
        'author': author,
        'status': status,
        'log': log,
        'artifact': artifact,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };

  factory BuildRecord.fromJson(Map<String, dynamic> json) => BuildRecord(
        id: json['id'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        author: json['author'] as String? ?? '',
        status: json['status'] as String? ?? 'failed',
        log: json['log'] as String? ?? '',
        artifact: json['artifact'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

/// The whole history of a project.
class ProjectHistory {
  ProjectHistory({
    this.projectId = '',
    List<ProjectVersion>? versions,
    List<BuildRecord>? builds,
  })  : versions = versions ?? <ProjectVersion>[],
        builds = builds ?? <BuildRecord>[];

  final String projectId;

  /// The released versions, newest first.
  final List<ProjectVersion> versions;

  /// The builds, newest first.
  final List<BuildRecord> builds;

  /// The version that is being built now.
  ProjectVersion? get latestVersion =>
      versions.isEmpty ? null : versions.first;

  /// True when the project was changed since the last release.
  bool isDirty(int currentRevision) =>
      currentRevision > (latestVersion?.revision ?? 0);

  factory ProjectHistory.fromJson(Map<String, dynamic> json) => ProjectHistory(
        projectId: json['projectId'] as String? ?? '',
        versions: [
          for (final v in (json['versions'] as List? ?? []))
            ProjectVersion.fromJson(v as Map<String, dynamic>),
        ],
        builds: [
          for (final b in (json['builds'] as List? ?? []))
            BuildRecord.fromJson(b as Map<String, dynamic>),
        ],
      );
}

/// A recorded live source-check/compilation run for a specific file.
class FileCheckDiagnostic {
  const FileCheckDiagnostic({
    required this.file,
    required this.line,
    required this.column,
    required this.kind,
    required this.message,
  });

  final String file;
  final int line;
  final int column;
  final String kind; // "error" | "warning"
  final String message;

  bool get isError => kind == 'error';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'file': file,
        'line': line,
        'column': column,
        'kind': kind,
        'message': message,
      };

  factory FileCheckDiagnostic.fromJson(Map<String, dynamic> json) =>
      FileCheckDiagnostic(
        file: (json['file'] as String?) ?? '',
        line: (json['line'] as num?)?.toInt() ?? 1,
        column: (json['column'] as num?)?.toInt() ?? 1,
        kind: (json['kind'] as String?) ?? 'error',
        message: (json['message'] as String?) ?? '',
      );
}

class FileCheckRecord {
  const FileCheckRecord({
    required this.id,
    required this.file,
    required this.date,
    required this.author,
    required this.diagnostics,
  });

  final String id;
  final String file;
  final DateTime date;
  final String author;
  final List<FileCheckDiagnostic> diagnostics;

  factory FileCheckRecord.fromJson(Map<String, dynamic> json) => FileCheckRecord(
        id: (json['id'] as String?) ?? '',
        file: (json['file'] as String?) ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        author: (json['author'] as String?) ?? '',
        diagnostics: [
          for (final d in (json['diagnostics'] as List? ?? []))
            if (d is Map<String, dynamic>)
              FileCheckDiagnostic.fromJson(d)
            else if (d is Map)
              FileCheckDiagnostic.fromJson(Map<String, dynamic>.from(d)),
        ],
      );
}
