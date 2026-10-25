import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/code_validator.dart';

void main() {
  group('FXML validation', () {
    test('accepts a valid FXML document', () {
      const source = '<?xml version="1.0" encoding="UTF-8"?>\n'
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
      const source = 'class Main {\n'
          '  // unbalanced {\n'
          '  String s = "}{";\n'
          '}';
      expect(CodeValidator.validateJava(source).isValid, isTrue);
    });

    test('rejects empty source', () {
      expect(CodeValidator.validateJava('').isValid, isFalse);
    });
  });
}
