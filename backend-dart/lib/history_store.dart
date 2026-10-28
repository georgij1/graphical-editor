import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A released version of the project: the state that was published and built.
class VersionEntry {
  VersionEntry({
    required this.revision,
    required this.date,
    required this.author,
    this.summary = '',
    this.scenesCount = 0,
    this.filesCount = 0,
    List<String>? sceneNames,
  })  : sceneNames = sceneNames ?? <String>[];

  /// The revision of the project this version was made of.
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

  Map<String, dynamic> toJson() => <String, dynamic>{
        'revision': revision,
        'date': date.toIso8601String(),
        'author': author,
        'summary': summary,
        'scenesCount': scenesCount,
        'filesCount': filesCount,
        'sceneNames': sceneNames,
      };

  factory VersionEntry.fromJson(Map<String, dynamic> json) => VersionEntry(
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
class BuildEntry {
  BuildEntry({
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

  factory BuildEntry.fromJson(Map<String, dynamic> json) => BuildEntry(
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

/// The history of a project: the released versions and the builds.
class ProjectHistory {
  ProjectHistory({
    required this.projectId,
    List<VersionEntry>? versions,
    List<BuildEntry>? builds,
  })  : versions = versions ?? <VersionEntry>[],
        builds = builds ?? <BuildEntry>[];

  final String projectId;

  /// The released versions, newest first.
  final List<VersionEntry> versions;

  /// The builds, newest first.
  final List<BuildEntry> builds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'versions': [for (final v in versions) v.toJson()],
        'builds': [for (final b in builds) b.toJson()],
      };

  factory ProjectHistory.fromJson(Map<String, dynamic> json) => ProjectHistory(
        projectId: json['projectId'] as String? ?? '',
        versions: [
          for (final v in (json['versions'] as List? ?? []))
            VersionEntry.fromJson(v as Map<String, dynamic>),
        ],
        builds: [
          for (final b in (json['builds'] as List? ?? []))
            BuildEntry.fromJson(b as Map<String, dynamic>),
        ],
      );
}

/// Stores the history of the projects: the released versions and the builds.
class HistoryStore {
  HistoryStore(this.dataDir);

  final String dataDir;
  Future<void> _lock = Future.value();

  Directory get _historyDir => Directory('$dataDir/history');

  Future<void> init() async {
    await _historyDir.create(recursive: true);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(() => completer.complete());
  }

  File _file(String projectId) =>
      File('${_historyDir.path}/$projectId.json');

  Future<ProjectHistory> read(String projectId) async {
    final file = _file(projectId);
    if (!await file.exists()) return ProjectHistory(projectId: projectId);
    try {
      final raw = await file.readAsString();
      return ProjectHistory.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ProjectHistory(projectId: projectId);
    }
  }

  Future<void> write(ProjectHistory history) async {
    await _historyDir.create(recursive: true);
    await _file(history.projectId)
        .writeAsString(jsonEncode(history.toJson()), flush: true);
  }

  /// Adds a released version to the history.
  Future<ProjectHistory> addVersion(
    String projectId,
    VersionEntry version,
  ) async {
    return _synchronized(() async {
      final history = await read(projectId);
      history.versions.insert(0, version);
      await write(history);
      return history;
    });
  }

  /// Adds a build to the history.
  Future<ProjectHistory> addBuild(String projectId, BuildEntry build) async {
    return _synchronized(() async {
      final history = await read(projectId);
      history.builds.insert(0, build);
      await write(history);
      return history;
    });
  }
}
