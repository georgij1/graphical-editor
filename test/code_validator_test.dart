import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/code_validator.dart';
import 'package:graphical_editor/project/java_generator.dart';
import 'package:graphical_editor/project/project.dart';

void main() {
  group('FXML validation', () {
    test('accepts a valid FXML document', () {
      const source =
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<?import javafx.scene.layout.VBox?>\n'
          '<VBox><children><Label text="Hi"/></children></VBox>';
      final result = CodeValidator.validateFxml(source);
      expect(result.isValid, isTrue);
    });

    test('rejects broken XML', () {
      final result = CodeValidator.validateFxml('<VBox><children>');
      expect(result.isValid, isFalse);
      expect(result.firstIssue, isNotNull);
    });

    test('rejects empty source', () {
      final result = CodeValidator.validateFxml('   ');
      expect(result.isValid, isFalse);
    });

    test('reports the position of a broken tag', () {
      final result = CodeValidator.validateFxml('<VBox>\n<children>');
      expect(result.isValid, isFalse);
      expect(result.firstIssue!.line, isNotNull);
      expect(result.firstIssue.toString(), startsWith('Line '));
    });
  });

  group('Java validation', () {
    test('accepts a structurally valid class', () {
      const source = 'package a;\npublic class Main {\n  void run() { }\n}';
      expect(CodeValidator.validateJava(source).isValid, isTrue);
    });

    test('reports every unclosed bracket with a line number', () {
      const source = 'class Main {\n  void run() {\n    int x = 1;\n';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(result.issues.length, 2);
      expect(result.issues.every((i) => i.line != null), isTrue);
      expect(result.issues.any((i) => i.message.contains('Unclosed')), isTrue);
    });

    test('collects multiple different problems at once', () {
      const source = 'class Main {\n  int x = );\n  void run( {\n';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(result.issues.length, greaterThanOrEqualTo(2));
    });

    test('flags a missing class declaration', () {
      const source = 'void run() {}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.message.contains('class')), isTrue);
    });

    test('ignores brackets inside strings and comments', () {
      const source =
          'class Main {\n'
          '  // unbalanced {\n'
          '  String s = "}{";\n'
          '}';
      expect(CodeValidator.validateJava(source).isValid, isTrue);
    });

    test('rejects empty source', () {
      expect(CodeValidator.validateJava('').isValid, isFalse);
    });
  });

  group('Java syntax errors (IntelliJ style)', () {
    test('points at the exact spot of a missing semicolon', () {
      const source =
          'class Main {\n'
          '  void run() {\n'
          '    int x = 1\n'
          '    x++;\n'
          '  }\n'
          '}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      final issue = result.issues.firstWhere(
        (i) => i.message.contains("';' expected"),
        orElse: () => result.issues.first,
      );
      expect(issue.line, 3);
      expect(issue.column, 14);
      expect(issue.toString(), "Line 3, column 14: ';' expected");
    });

    test('reports an unclosed string once, without follow-up noise', () {
      const source =
          'class Main {\n'
          '  String s = "abc\n'
          '}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(result.issues.length, 1);
      expect(result.issues.single.message, contains('Unclosed string'));
      expect(result.issues.single.line, 2);
      expect(result.issues.single.column, 14);
    });

    test('reports an unclosed comment with its opening position', () {
      const source =
          'class Main {\n'
          '  /* no end\n'
          '}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      final issue = result.issues.firstWhere(
        (i) => i.message.contains('Unclosed comment'),
      );
      expect(issue.line, 2);
      expect(issue.column, 3);
    });

    test('reports a stray closing brace at top level', () {
      const source =
          'class Main {\n'
          '}\n'
          '}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.message.contains('Unexpected')),
        isTrue,
      );
    });

    test('flags a try without catch or finally', () {
      const source =
          'class Main {\n'
          '  void run() {\n'
          '    try { x(); }\n'
          '  }\n'
          '}';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.message.contains("'try' without")),
        isTrue,
      );
    });
  });

  group('Java warnings (non-blocking)', () {
    test('unused import is a warning that does not block', () {
      const source =
          'package a.b;\n'
          'import java.util.List;\n'
          'class Main {}\n';
      final result = CodeValidator.validateJava(source);
      expect(result.isValid, isTrue);
      expect(result.warningCount, 1);
      expect(result.issues.single.message, contains('Unused import'));
      expect(result.issues.single.severity, ValidationSeverity.warning);
      expect(result.issues.single.line, 2);
    });

    test('package that does not match the folder is a warning', () {
      const source =
          'package other;\n'
          'class Main {}\n';
      final result = CodeValidator.validateJava(
        source,
        path: 'src/main/java/com/example/Main.java',
      );
      expect(result.isValid, isTrue);
      expect(result.warningCount, 1);
      expect(result.issues.single.message, contains('does not correspond'));
    });

    test('missing package declaration is a warning', () {
      const source = 'class Main {}\n';
      final result = CodeValidator.validateJava(
        source,
        path: 'src/main/java/com/example/Main.java',
      );
      expect(result.isValid, isTrue);
      expect(
        result.issues.single.message,
        contains('Package declaration is missing'),
      );
    });

    test('public class in a mismatching file name is a warning', () {
      const source =
          'package com.example;\n'
          'public class MainApp {}\n';
      final result = CodeValidator.validateJava(
        source,
        path: 'src/main/java/com/example/Main.java',
      );
      expect(result.isValid, isTrue);
      expect(result.warningCount, 1);
      expect(result.issues.single.text, contains('MainApp.java'));
    });

    test('errors block while warnings do not', () {
      const withWarning =
          'package a.b;\n'
          'import java.util.List;\n'
          'class Main {}\n';
      expect(CodeValidator.validateJava(withWarning).isValid, isTrue);

      const withError =
          'package a.b;\n'
          'import java.util.List;\n'
          'class Main { int x = }\n';
      final result = CodeValidator.validateJava(withError);
      expect(result.isValid, isFalse);
      expect(result.errorCount, greaterThanOrEqualTo(1));
    });
  });

  group('modern Java stays false-positive free', () {
    test('typical JavaFX application source validates clean', () {
      const source =
          'package com.example;\n'
          '\n'
          'import javafx.application.Application;\n'
          'import javafx.fxml.FXMLLoader;\n'
          'import javafx.scene.Parent;\n'
          'import javafx.scene.Scene;\n'
          'import javafx.stage.Stage;\n'
          'import java.io.IOException;\n'
          'import java.util.HashMap;\n'
          'import java.util.List;\n'
          'import java.util.Map;\n'
          '\n'
          'public class MainApp extends Application {\n'
          '    private final Map<String, String> cache = new HashMap<>();\n'
          '\n'
          '    @Override\n'
          '    public void start(Stage stage) throws IOException {\n'
          '        FXMLLoader loader = new FXMLLoader(\n'
          '                MainApp.class.getResource("main.fxml"));\n'
          '        Parent root = loader.load();\n'
          '        Scene scene = new Scene(root, 800, 600);\n'
          '        stage.setScene(scene);\n'
          '        stage.setTitle("Editor");\n'
          '        stage.show();\n'
          '    }\n'
          '\n'
          '    public static void main(String[] args) {\n'
          '        launch(args);\n'
          '    }\n'
          '}\n';
      final result = CodeValidator.validateJava(
        source,
        path: 'src/main/java/com/example/MainApp.java',
      );
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((i) => i.toString()).join('\n'),
      );
      expect(result.isValid, isTrue);
    });

    test('generics, lambdas, switch arrows and casts parse cleanly', () {
      const source =
          'import java.util.List;\n'
          'import java.util.ArrayList;\n'
          '\n'
          'class Main {\n'
          '  void run(boolean flag, List<String> items) {\n'
          '    List<String> copy = new ArrayList<String>(items);\n'
          '    Map<String, Integer> table = new HashMap<String, Integer>();\n'
          '    int x = flag ? 1 : 2;\n'
          '    String s = (String) copy;\n'
          '    items.forEach(t -> System.out.println(t));\n'
          '    for (String item : items) {\n'
          '      System.out.println(item);\n'
          '    }\n'
          '    for (int i = 0; i < 10; i++) {\n'
          '      x += i;\n'
          '    }\n'
          '    switch (x) {\n'
          '      case 1:\n'
          '        x++;\n'
          '        break;\n'
          '      case 2 -> x--;\n'
          '      default -> x = 0;\n'
          '    }\n'
          '    try (var in = open()) {\n'
          '      use(in);\n'
          '    } catch (Exception e) {\n'
          '      e.printStackTrace();\n'
          '    }\n'
          '  }\n'
          '\n'
          '  Object open() { return null; }\n'
          '  void use(Object in) {}\n'
          '}\n';
      final result = CodeValidator.validateJava(source);
      expect(
        result.errors,
        isEmpty,
        reason: result.errors.map((i) => i.toString()).join('\n'),
      );
    });

    test('generated project sources validate clean', () {
      final project = Project(
        id: 'p1',
        name: 'Demo',
        package: 'com.example',
        mainClass: 'MainApp',
        scenes: [
          SceneFile(
            name: 'main',
            fxml: '<VBox/>',
            controllerClass: 'MainController',
          ),
        ],
      );
      for (final file in JavaGenerator.generate(project)) {
        final result = CodeValidator.validateJava(
          file.content,
          path: file.path,
        );
        expect(
          result.errors,
          isEmpty,
          reason:
              '${file.path}:\n'
              '${result.errors.map((i) => i.toString()).join('\n')}',
        );
      }
    });
  });

  group('issue rendering', () {
    test('fills placeholders with the reported arguments', () {
      const source =
          'package a.b;\n'
          'import java.util.List;\n'
          'import java.util.List;\n'
          'class Main {}\n';
      final result = CodeValidator.validateJava(source);
      final issue = result.issues.firstWhere(
        (i) => i.message.contains('Unused import'),
      );
      expect(issue.text, "Unused import 'List'.");
      expect(issue.render((k) => k), "Unused import 'List'.");
    });

    test('localizes the message through the translation table', () {
      const source =
          'class Main {\n'
          '}\n'
          '}';
      final result = CodeValidator.validateJava(source);
      final issue = result.issues.firstWhere(
        (i) => i.message == 'Unexpected "{0}".',
      );
      final ru = issue.render(
        (key) => key == 'Unexpected "{0}".' ? 'Лишний "{0}".' : key,
      );
      expect(ru, 'Лишний "}".');
    });
  });
}
