import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/io/file_service.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/project/build_files.dart';
import 'package:graphical_editor/project/project_exporter.dart';

import 'test_doubles.dart';

Project _demoProject() => Project(
      id: 'p1',
      name: 'Demo',
      package: 'com.example.demo',
      mainClass: 'MainApp',
      scenes: [SceneFile(name: 'main', fxml: '<?import javafx.scene.layout.AnchorPane?><AnchorPane/>')],
    );

void main() {
  group('FileService.save', () {
    test('reports failure instead of throwing when the platform refuses',
        () async {
      const service = FileService();
      // No file_picker implementation is wired up in the test binding, so the
      // call must fail gracefully rather than surface as an uncaught error.
      final ok = await service.save('<x/>', 'scene.fxml');
      expect(ok, isFalse);
    });
  });

  group('ProjectExporter', () {
    const exporter = ProjectExporter();

    List<String> zipNames(ExportOptions options) {
      final bytes = exporter.build(_demoProject(), options);
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.files.map((f) => f.name).toList();
    }

    test('names the file after the project and format', () {
      final project = _demoProject();
      expect(
        exporter.fileName(project, ExportArchiveFormat.zip),
        'Demo.zip',
      );
      expect(
        exporter.fileName(project, ExportArchiveFormat.tarGz),
        'Demo.tar.gz',
      );
    });

    test('zip export contains a runnable maven layout', () {
      final project = _demoProject();
      final bytes = exporter.build(project, const ExportOptions());
      // "PK" local file header.
      expect(bytes.sublist(0, 2), <int>[0x50, 0x4B]);

      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('Demo/pom.xml'));
      expect(names, contains('Demo/README.md'));
      expect(names, contains('Demo/.gitignore'));
      expect(names, contains('Demo/project.json'));
      expect(names, contains('Demo/src/main/resources/com/example/demo/main.fxml'));
      expect(names.any((n) => n.startsWith('Demo/src/main/java/')), isTrue);

      final pom = utf8.decode(archive.findFile('Demo/pom.xml')!.content as List<int>);
      expect(pom, contains('<mainClass>${'\${main.class}'}</mainClass>'));
      expect(pom, contains('javafx-maven-plugin'));
      expect(pom, contains('<main.class>com.example.demo.MainApp</main.class>'));

      final readme =
          utf8.decode(archive.findFile('Demo/README.md')!.content as List<int>);
      expect(readme, contains('mvn javafx:run'));

      final manifest = archive.findFile('Demo/project.json');
      final json = jsonDecode(utf8.decode(manifest!.content as List<int>))
          as Map<String, dynamic>;
      expect(json['name'], 'Demo');
    });

    test('gradle export writes the gradle build files', () {
      final names = zipNames(
        const ExportOptions(buildTool: BuildTool.gradle),
      );
      expect(names, contains('Demo/build.gradle'));
      expect(names, contains('Demo/settings.gradle'));
      expect(names, isNot(contains('Demo/pom.xml')));

      final bytes = exporter.build(
        _demoProject(),
        const ExportOptions(buildTool: BuildTool.gradle),
      );
      final gradle =
          utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('Demo/build.gradle')!
              .content as List<int>);
      expect(gradle, contains("mainClass = 'com.example.demo.MainApp'"));
      expect(gradle, contains('org.openjfx.javafxplugin'));
    });

    test('build tool can be left out', () {
      final names = zipNames(
        const ExportOptions(buildTool: BuildTool.none),
      );
      expect(names, isNot(contains('Demo/pom.xml')));
      expect(names, isNot(contains('Demo/build.gradle')));
      expect(names, contains('Demo/README.md'));
    });

    test('tar.gz export is gzip compressed and lists the same files', () {
      final project = _demoProject();
      final bytes = exporter.build(
        project,
        const ExportOptions(format: ExportArchiveFormat.tarGz),
      );
      // gzip magic.
      expect(bytes.sublist(0, 2), <int>[0x1F, 0x8B]);

      final tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      final names = tar.files.map((f) => f.name).toList();
      expect(names, contains('Demo/pom.xml'));
      expect(names, contains('Demo/project.json'));
      expect(names, contains('Demo/src/main/resources/com/example/demo/main.fxml'));
    });

    test('java sources can be left out of the archive', () {
      final names = zipNames(const ExportOptions(includeJavaSources: false));
      expect(names.any((n) => n.startsWith('Demo/src/main/java/')), isFalse);
      expect(names.any((n) => n.endsWith('.fxml')), isTrue);
    });
  });

  group('exportProject', () {
    test('never throws when saving is unavailable', () async {
      final controller = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: FakeApiClient(),
      );
      await controller.register('a@b.com', 'secret1');
      controller.createProject(
        name: 'Demo',
        package: 'com.example',
        mainClass: 'MainApp',
      );

      final ok = await controller.exportProject(
        controller.projects.single,
        const ExportOptions(),
      );
      expect(ok, isFalse);
    });
  });
}