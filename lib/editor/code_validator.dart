import 'package:xml/xml.dart';

import '../fxml/fxml_parser.dart';
import 'java_linter.dart';

/// How serious a [ValidationIssue] is. Errors block applying the source in
/// the editor; warnings are informational — the same split IntelliJ IDEA
/// makes between red errors and yellow warnings.
enum ValidationSeverity { error, warning }

/// A single validation problem found in an edited source file.
///
/// [message] is an English key that may contain `{0}`, `{1}`… placeholders
/// filled from [args]; [render] resolves it through the localization table.
class ValidationIssue {
  const ValidationIssue(
    this.message, {
    this.args = const <String>[],
    this.line,
    this.column,
    this.severity = ValidationSeverity.error,
  });

  /// Localization key of the problem (English text with `{0}`… placeholders).
  final String message;

  /// Values substituted into [message].
  final List<String> args;

  /// 1-based line of the problem, or `null` when unknown.
  final int? line;

  /// 1-based column of the problem, or `null` when unknown.
  final int? column;

  final ValidationSeverity severity;

  bool get isError => severity == ValidationSeverity.error;

  /// English text with [args] substituted.
  String get text => _fill(message, args);

  /// Localized text: [tr] resolves the key, then the arguments are filled in.
  String render(String Function(String) tr) => _fill(tr(message), args);

  /// `Line 3, column 12: ` prefix (IntelliJ style); empty without a position.
  String get _position {
    if (line == null) return '';
    if (column == null) return 'Line $line: ';
    return 'Line $line, column $column: ';
  }

  @override
  String toString() => '$_position$text';

  static String _fill(String template, List<String> args) {
    var out = template;
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', args[i]);
    }
    return out;
  }
}

/// Result of validating an edited source file. Reports every issue found
/// rather than stopping at the first one.
class ValidationResult {
  const ValidationResult(this.issues);

  static const ValidationResult valid = ValidationResult(<ValidationIssue>[]);

  final List<ValidationIssue> issues;

  List<ValidationIssue> get errors =>
      issues.where((i) => i.isError).toList(growable: false);
  List<ValidationIssue> get warnings =>
      issues.where((i) => !i.isError).toList(growable: false);

  int get errorCount => issues.where((i) => i.isError).length;
  int get warningCount => issues.where((i) => !i.isError).length;

  /// True when the source contains at least one error. Warnings do not block
  /// applying — IntelliJ never blocks saving a file for a warning either.
  bool get hasErrors => issues.any((i) => i.isError);
  bool get isValid => !hasErrors;

  ValidationIssue? get firstIssue => issues.isEmpty ? null : issues.first;
  String? get firstError => hasErrors ? errors.first.toString() : null;
}

/// Validators for the code editor.
///
/// FXML is validated by actually parsing it (the XML parser reports the
/// structural problem with line and column). Java goes through [JavaLinter]:
/// a real tokenizer plus a parser with error recovery, which reports every
/// syntax problem with its exact position, IntelliJ-IDEA style.
class CodeValidator {
  const CodeValidator._();

  static const FxmlParser _parser = FxmlParser();

  static ValidationResult validate({
    required bool isJava,
    required String source,
    String? path,
  }) {
    return isJava ? validateJava(source, path: path) : validateFxml(source);
  }

  static ValidationResult validateFxml(String source) {
    if (source.trim().isEmpty) {
      return const ValidationResult(<ValidationIssue>[
        ValidationIssue('FXML source is empty.'),
      ]);
    }
    try {
      _parser.parse(source);
      return ValidationResult.valid;
    } catch (error) {
      int? line;
      int? column;
      if (error is XmlFormatException) {
        if (error.line > 0) line = error.line;
        if (error.column > 0) column = error.column;
      }
      return ValidationResult(<ValidationIssue>[
        ValidationIssue(_shorten(error), line: line, column: column),
      ]);
    }
  }

  static ValidationResult validateJava(String source, {String? path}) {
    if (source.trim().isEmpty) {
      return const ValidationResult(<ValidationIssue>[
        ValidationIssue('Java source is empty.'),
      ]);
    }
    final issues = <ValidationIssue>[];
    JavaLinter(path: path).lint(source, issues);
    return ValidationResult(issues);
  }

  static String _shorten(Object error) {
    var text = error.toString();
    text = text.replaceFirst(RegExp(r'^Xml\w*Exception: '), '');
    text = text.replaceFirst(RegExp(r' at \d+:\d+$'), '');
    final firstLine = text.split('\n').first.trim();
    return firstLine.isEmpty ? 'Invalid FXML.' : firstLine;
  }
}
