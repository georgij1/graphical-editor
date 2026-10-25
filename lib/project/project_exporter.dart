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
  });

  final ExportArchiveFormat format;
  final bool includeJavaSources;

  /// Build configuration written next to the sources (Maven/Gradle/none).
  final BuildTool buildTool;
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

    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    for (final file in _buildFiles.generate(project, options.buildTool)) {
      add('$root/${file.path}', file.content);
    }

    add('$root/project.json',
        const JsonEncoder.withIndent('  ').convert(project.toJson()));

    if (options.includeJavaSources) {
      for (final source in JavaGenerator.generate(project)) {
        add('$root/${source.path}', source.content);
      }
    }

    final packageDir = JavaGenerator.packageDir(project);
    for (final scene in project.scenes) {
      add('$root/src/main/resources/$packageDir/${scene.name}.fxml',
          scene.fxml);
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