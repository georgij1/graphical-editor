import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/java_generator.dart';
import 'package:graphical_editor/ui/widgets/project_tree_panel.dart';

import 'test_doubles.dart';

EditorController standaloneController() => EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );

void main() {
  testWidgets('project tree shows folders, Java sources and FXML scenes',
      (tester) async {
    final controller = standaloneController()
      ..createProject(
        name: 'TreeApp',
        package: 'com.example.tree',
        mainClass: 'MainApp',
      );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectTreePanel(
          controller: controller,
          onRenameScene: (_) {},
          onDeleteScene: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('src'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('resources'), findsOneWidget);
    expect(find.text('MainApp.java'), findsOneWidget);
    expect(find.text('MainAppController.java'), findsOneWidget);
    expect(find.text('main.fxml'), findsOneWidget);
    expect(find.text('com.example.tree.MainAppController'), findsOneWidget);
  });

  testWidgets('tapping a scene file opens it in the controller',
      (tester) async {
    final controller = standaloneController()
      ..createProject(
        name: 'TreeApp',
        package: 'com.example.tree',
        mainClass: 'MainApp',
      )
      ..newScene('secondary');
    controller.openScene(controller.currentProject!.scenes.first);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectTreePanel(
          controller: controller,
          onRenameScene: (_) {},
          onDeleteScene: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    controller.showSource(
      GeneratedFile(path: 'src/main/java/MainApp.java', content: 'class MainApp {}'),
    );
    await tester.pump();
    expect(controller.codeMode, isTrue);
    expect(controller.codeIsJava, isTrue);

    await tester.tap(find.text('secondary.fxml'));
    await tester.pump();
    expect(controller.activeScene!.name, 'secondary');
    expect(controller.codeMode, isFalse);
  });

  testWidgets('tapping a Java file opens it in the main pane (not a dialog)',
      (tester) async {
    final controller = standaloneController()
      ..createProject(
        name: 'TreeApp',
        package: 'com.example.tree',
        mainClass: 'MainApp',
      );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectTreePanel(
          controller: controller,
          onRenameScene: (_) {},
          onDeleteScene: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MainApp.java'));
    await tester.pump();

    expect(controller.codeMode, isTrue);
    expect(controller.openSource!.path, endsWith('MainApp.java'));
    expect(controller.openSource!.content, contains('class MainApp'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('code editing', () {
    test('editing a Java source stores an override and survives regeneration',
        () {
      final controller = standaloneController()
        ..createProject(
          name: 'TreeApp',
          package: 'com.example.tree',
          mainClass: 'MainApp',
        );
      final path = 'src/main/java/com/example/tree/MainApp.java';

      final ok = controller.applyJavaSource(path, 'class MainApp { /* custom */ }');

      expect(ok, isTrue);
      expect(controller.currentProject!.sourceOverrides[path],
          contains('custom'));
      final regenerated = JavaGenerator.generate(controller.currentProject!)
          .firstWhere((f) => f.path == path);
      expect(regenerated.content, contains('custom'));
    });

    test('editing a Java source back to the generated text drops the override',
        () {
      final controller = standaloneController()
        ..createProject(
          name: 'TreeApp',
          package: 'com.example.tree',
          mainClass: 'MainApp',
        );
      final path = 'src/main/java/com/example/tree/MainApp.java';
      final generated = JavaGenerator.generate(
              controller.currentProject!, applyOverrides: false)
          .firstWhere((f) => f.path == path)
          .content;

      controller
        ..applyJavaSource(path, 'class X {}')
        ..applyJavaSource(path, generated);

      expect(controller.currentProject!.sourceOverrides.containsKey(path),
          isFalse);
    });

    test('applying valid FXML replaces the document', () {
      final controller = standaloneController()
        ..createProject(
          name: 'TreeApp',
          package: 'com.example.tree',
          mainClass: 'MainApp',
        );
      final ok = controller.applyFxmlSource(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<?import javafx.scene.layout.VBox?>\n'
        '<VBox/>',
      );
      expect(ok, isTrue);
      expect(controller.root.tag, 'VBox');
    });

    test('applying invalid FXML is rejected', () {
      final controller = standaloneController()
        ..createProject(
          name: 'TreeApp',
          package: 'com.example.tree',
          mainClass: 'MainApp',
        );
      final before = controller.root.tag;
      final ok = controller.applyFxmlSource('<VBox><</VBox>');
      expect(ok, isFalse);
      expect(controller.root.tag, before);
    });
  });
}
