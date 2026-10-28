import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/build_analyzer.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/project.dart';

import 'test_doubles.dart';

/// A minimal FXML document whose root declares [controller].
String fxmlWith(String controller) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<AnchorPane xmlns="http://javafx.com/javafx/17.0.2" '
    'xmlns:fx="http://javafx.com/fxml/1" fx:controller="$controller">'
    '</AnchorPane>';

Project project({
  String package = 'com.example.myapp1',
  String description = 'Demo project',
  String? sceneController = 'com.example.myapp1.MainAppController',
  String? fxmlController,
}) {
  final p = Project(
    id: 'p1',
    name: 'MyApp1',
    package: package,
    mainClass: 'MainApp1',
    description: description,
  );
  if (sceneController != null || fxmlController != null) {
    p.scenes.add(SceneFile(
      name: 'main',
      fxml: fxmlWith(fxmlController ?? sceneController ?? ''),
      controllerClass: sceneController,
    ));
  }
  return p;
}

void main() {
  group('BuildAnalyzer.validate (export check)', () {
    test('flags an FXML controller outside the project package', () {
      // The classic MyApp1 case: package was renamed to myapp1 while the
      // FXML still points at com.example.myapp.MainAppController.
      final report = BuildAnalyzer.validate(project(
        fxmlController: 'com.example.myapp.MainAppController',
        sceneController: 'com.example.myapp.MainAppController',
      ));

      expect(report.kind, BuildReportKind.export);
      expect(report.isExport, isTrue);
      expect(report.hasControllerIssues, isTrue);
      expect(report.controllerIssueCount, 1);
      expect(
        report.issues.map((i) => i.key),
        contains(
            'Scene "{0}": the FXML refers to the controller "{1}", but the '
            'project package is "{2}". The application will not start.'),
      );
      expect(report.score, lessThan(100));
      expect(report.buildSucceeded, isTrue);
    });

    test('passes when every controller matches the project package', () {
      final report = BuildAnalyzer.validate(project());

      expect(report.controllerIssueCount, 0);
      expect(report.hasControllerIssues, isFalse);
      expect(
        report.issues.where((i) => i.key.contains('controller')),
        isEmpty,
      );
      expect(report.score, 100);
      expect(report.isHealthy, isTrue);
    });

    test('flags a controller declared outside the package', () {
      final report = BuildAnalyzer.validate(project(
        sceneController: 'org.other.MainAppController',
        fxmlController: 'org.other.MainAppController',
      ));
      expect(report.hasControllerIssues, isTrue);
    });

    test('flags a scene whose FXML has no controller class behind it', () {
      final report = BuildAnalyzer.validate(project(
        sceneController: null,
        fxmlController: 'com.example.myapp1.MainAppController',
      ));
      expect(
        report.issues.map((i) => i.key),
        contains('Scene "{0}": the FXML refers to a controller, but the scene '
            'has no controller class.'),
      );
    });

    test('an empty project reports missing scenes', () {
      final report = BuildAnalyzer.validate(project(
        sceneController: null,
        fxmlController: null,
        description: '',
      ));
      expect(
        report.issues.map((i) => i.key),
        contains('No scenes in the project.'),
      );
      expect(report.score, lessThan(100));
    });
  });

  group('ReportLine', () {
    test('replaces the placeholders', () {
      const line = ReportLine('Scene "{0}" uses "{1}"', <String>['main', 'C']);
      expect(line.render((k) => k), 'Scene "main" uses "C"');
    });

    test('goes through the translation first', () {
      const line = ReportLine('Greeting {0}', <String>['you']);
      expect(
        line.render((k) => k == 'Greeting {0}' ? 'Привет {0}' : k),
        'Привет you',
      );
    });
  });

  group('fixSceneControllers', () {
    test('moves controllers and FXML into the new package on repackaging',
        () async {
      final controller = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: FakeApiClient(),
      );
      controller.createProject(
        name: 'MyApp1',
        package: 'com.example.myapp',
        mainClass: 'MainApp1',
      );
      final project = controller.currentProject!;
      expect(project.scenes.first.controllerClass,
          'com.example.myapp.MainApp1Controller');

      // Renaming the package keeps the exported FXML consistent, so the
      // application still finds its controller at launch.
      controller.setProjectPackage(project, 'com.example.myapp1');

      final scene = project.scenes.first;
      expect(scene.controllerClass, 'com.example.myapp1.MainApp1Controller');
      expect(
        scene.fxml,
        contains('fx:controller="com.example.myapp1.MainApp1Controller"'),
      );
      expect(scene.fxml, isNot(contains('com.example.myapp.')));

      expect(BuildAnalyzer.validate(project).hasControllerIssues, isFalse);
    });

    test('repairs a stale FXML even without a declared controller', () async {
      final controller = EditorController(
        storage: InMemoryProjectStorage(),
        tokenStore: InMemoryKeyValueStore(),
        api: FakeApiClient(),
      );
      controller.createProject(
        name: 'Broken',
        package: 'com.example.myapp1',
        mainClass: 'MainApp1',
      );
      final project = controller.currentProject!;
      // Make a second scene active so the editor buffer does not overwrite
      // the broken FXML of the first scene during the fix.
      controller.newScene('second');
      final scene = project.scenes.first;
      // Simulate the broken state: FXML points to the old package and the
      // declared controller was lost.
      scene.controllerClass = null;
      scene.fxml = fxmlWith('com.example.myapp.MainAppController');

      expect(BuildAnalyzer.validate(project).hasControllerIssues, isTrue);
      expect(controller.fixSceneControllers(project), isTrue);
      expect(scene.controllerClass, 'com.example.myapp1.MainAppController');
      expect(
        scene.fxml,
        contains('fx:controller="com.example.myapp1.MainAppController"'),
      );
      expect(BuildAnalyzer.validate(project).hasControllerIssues, isFalse);
    });
  });
}
