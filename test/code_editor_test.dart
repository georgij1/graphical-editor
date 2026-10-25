import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/java_generator.dart';
import 'package:graphical_editor/ui/widgets/source_view.dart';

import 'test_doubles.dart';

EditorController standaloneController() => EditorController(
      storage: InMemoryProjectStorage(),
      tokenStore: InMemoryKeyValueStore(),
      api: FakeApiClient(),
    );

Future<void> _pressCtrlS(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('Ctrl+S applies edited FXML source', (tester) async {
    final controller = standaloneController()
      ..createProject(name: 'P', package: 'com.example', mainClass: 'MainApp')
      ..editSceneSource();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CodeView(controller: controller)),
    ));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<?import javafx.scene.layout.VBox?>\n'
      '<VBox/>',
    );
    await tester.pump();
    await _pressCtrlS(tester);

    expect(controller.root.tag, 'VBox');
  });

  testWidgets('Ctrl+S stores an edited Java source override', (tester) async {
    final controller = standaloneController()
      ..createProject(name: 'P', package: 'com.example', mainClass: 'MainApp');
    const path = 'src/main/java/com/example/MainApp.java';
    controller.showSource(
      GeneratedFile(path: path, content: controller.codeContent),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CodeView(controller: controller)),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'class MainApp { /* edited */ }');
    await tester.pump();
    await _pressCtrlS(tester);

    expect(controller.currentProject!.sourceOverrides[path], contains('edited'));
  });

  testWidgets('invalid FXML shows a validation error and blocks Apply',
      (tester) async {
    final controller = standaloneController()
      ..createProject(name: 'P', package: 'com.example', mainClass: 'MainApp')
      ..editSceneSource();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CodeView(controller: controller)),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '<VBox><children>');
    await tester.pump();

    expect(find.text('No issues found.'), findsNothing);
    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(applyButton.onPressed, isNull);
  });
}
