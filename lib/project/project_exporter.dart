import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'build_files.dart';
import 'java_generator.dart';
import 'project.dart';

/// Container format used when a project is exported.
enum ExportArchiveFormat {
  zip('zip'),
  tarGz('tar.gz');

  const ExportArchiveFormat(this.extension);

  final String extension;

  String get mimeType =>
      this == ExportArchiveFormat.zip ? 'application/zip' : 'application/gzip';
}

/// Everything the export dialog collects.
class ExportOptions {
  const ExportOptions({
    this.format = ExportArchiveFormat.zip,
    this.includeJavaSources = true,
    this.buildTool = BuildTool.maven,
    this.kioskMode = false,
  });

  final ExportArchiveFormat format;
  final bool includeJavaSources;

  /// Build configuration written next to the sources (Maven/Gradle/none).
  final BuildTool buildTool;

  /// When true the generated launcher starts the stage in full-screen
  /// undecorated kiosk mode (no title bar, no taskbar, ESC disabled).
  final bool kioskMode;
}

/// Packs a project into a downloadable archive laid out like the real
/// application sources:
///
/// ```text
/// <Project>/
///   pom.xml                     (or build.gradle + settings.gradle)
///   README.md
///   .gitignore
///   project.json
///   src/main/java/...          generated + edited Java sources
///   src/main/resources/...     FXML scenes
/// ```
class ProjectExporter {
  const ProjectExporter();

  static const BuildFiles _buildFiles = BuildFiles();

  /// Suggested file name, e.g. `Demo.zip` or `Demo.tar.gz`.
  String fileName(Project project, ExportArchiveFormat format) =>
      '${project.name}.${format.extension}';

  /// Builds the archive bytes. Synchronous on purpose: the payloads are small
  /// and the result is handed straight to the file saver.
  Uint8List build(Project project, ExportOptions options) {
    final archive = Archive();
    final root = project.name;
    final added = <String>{};

    void add(String relPath, String content) {
      final path = '$root/$relPath';
      if (!added.add(path)) return;
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    void addOverrideable(String relPath, String content) {
      add(relPath, project.sourceOverrides[relPath] ?? content);
    }

    for (final file in _buildFiles.generate(project, options.buildTool)) {
      addOverrideable(file.path, file.content);
    }

    add('project.json',
        const JsonEncoder.withIndent('  ').convert(project.toJson()));

    if (options.includeJavaSources) {
      for (final source in JavaGenerator.generate(project,
          kioskMode: options.kioskMode)) {
        addOverrideable(source.path, source.content);
      }
    }

    final packageDir = JavaGenerator.packageDir(project);
    for (final scene in project.scenes) {
      addOverrideable(
          'src/main/resources/$packageDir/${scene.name}.fxml', scene.fxml);
    }

    // Extra files stored in sourceOverrides (e.g. CSS, custom files) and any
    // overrides that were not emitted by the generators above.
    for (final entry in project.sourceOverrides.entries) {
      if (entry.key.endsWith('/')) continue;
      add(entry.key, entry.value);
    }

    final encoded = switch (options.format) {
      ExportArchiveFormat.zip => ZipEncoder().encode(archive),
      ExportArchiveFormat.tarGz =>
        GZipEncoder().encode(TarEncoder().encode(archive)),
    };
    if (encoded == null) {
      throw StateError('Failed to encode ${options.format.extension} archive');
    }
    return Uint8List.fromList(encoded);
  }
}