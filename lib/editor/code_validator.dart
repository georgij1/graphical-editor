import '../fxml/fxml_parser.dart';

/// A single validation problem found in an edited source file.
class ValidationIssue {
  const ValidationIssue(this.message, {this.line});

  final String message;
  final int? line;

  @override
  String toString() => line == null ? message : 'Line $line: $message';
}

/// Result of validating an edited source file. Reports every issue found rather
/// than stopping at the first one.
class ValidationResult {
  const ValidationResult(this.issues);

  static const ValidationResult valid = ValidationResult(<ValidationIssue>[]);

  final List<ValidationIssue> issues;

  bool get isValid => issues.isEmpty;
  ValidationIssue? get firstIssue => issues.isEmpty ? null : issues.first;
  String? get firstError => firstIssue?.toString();
}

class _Open {
  const _Open(this.ch, this.line);
  final String ch;
  final int line;
}

/// Lightweight validators for the code editor. FXML is validated by actually
/// parsing it (the XML parser reports the first structural problem it hits);
/// Java is scanned for all bracket problems plus a class declaration.
class CodeValidator {
  const CodeValidator._();

  static const FxmlParser _parser = FxmlParser();

  static ValidationResult validate({
    required bool isJava,
    required String source,
  }) {
    return isJava ? validateJava(source) : validateFxml(source);
  }

  static ValidationResult validateFxml(String source) {
    if (source.trim().isEmpty) {
      return const ValidationResult(
          <ValidationIssue>[ValidationIssue('FXML source is empty.')]);
    }
    try {
      _parser.parse(source);
      return ValidationResult.valid;
    } catch (error) {
      return ValidationResult(<ValidationIssue>[
        ValidationIssue(_shorten(error)),
      ]);
    }
  }

  static ValidationResult validateJava(String source) {
    if (source.trim().isEmpty) {
      return const ValidationResult(
          <ValidationIssue>[ValidationIssue('Java source is empty.')]);
    }
    final issues = <ValidationIssue>[];
    _scanBrackets(source, issues);
    if (!RegExp(r'\bclass\b').hasMatch(_stripLiteralsAndComments(source))) {
      issues.add(const ValidationIssue('No "class" declaration found.'));
    }
    return ValidationResult(issues);
  }

  /// Walks the source once, tracking strings/comments (so their brackets are
  /// ignored) and reporting every unmatched bracket with its line number.
  static void _scanBrackets(String source, List<ValidationIssue> issues) {
    const pairs = <String, String>{'}': '{', ')': '(', ']': '['};
    final stack = <_Open>[];
    var line = 1;
    var i = 0;
    final n = source.length;
    while (i < n) {
      final c = source[i];
      if (c == '\n') {
        line++;
        i++;
        continue;
      }
      if (c == '/' && i + 1 < n && source[i + 1] == '/') {
        i += 2;
        while (i < n && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && i + 1 < n && source[i + 1] == '*') {
        i += 2;
        while (i + 1 < n && !(source[i] == '*' && source[i + 1] == '/')) {
          if (source[i] == '\n') line++;
          i++;
        }
        i = i + 2 <= n ? i + 2 : n;
        continue;
      }
      if (c == '"' || c == "'") {
        final quote = c;
        i++;
        while (i < n) {
          if (source[i] == '\\') {
            i += 2;
            continue;
          }
          if (source[i] == '\n') line++;
          if (source[i] == quote) {
            i++;
            break;
          }
          i++;
        }
        continue;
      }
      if (c == '{' || c == '(' || c == '[') {
        stack.add(_Open(c, line));
        i++;
        continue;
      }
      if (pairs.containsKey(c)) {
        final expected = pairs[c];
        if (stack.isEmpty || stack.last.ch != expected) {
          issues.add(ValidationIssue('Unexpected "$c".', line: line));
        } else {
          stack.removeLast();
        }
        i++;
        continue;
      }
      i++;
    }
    for (final open in stack) {
      issues.add(ValidationIssue('Unclosed "${open.ch}".', line: open.line));
    }
  }

  static String _stripLiteralsAndComments(String source) {
    final buffer = StringBuffer();
    var i = 0;
    final n = source.length;
    while (i < n) {
      final c = source[i];
      if (c == '/' && i + 1 < n && source[i + 1] == '/') {
        i += 2;
        while (i < n && source[i] != '\n') {
          i++;
        }
      } else if (c == '/' && i + 1 < n && source[i + 1] == '*') {
        i += 2;
        while (i + 1 < n && !(source[i] == '*' && source[i + 1] == '/')) {
          i++;
        }
        i = i + 2 <= n ? i + 2 : n;
      } else if (c == '"' || c == "'") {
        final quote = c;
        i++;
        while (i < n) {
          if (source[i] == '\\') {
            i += 2;
            continue;
          }
          if (source[i] == quote) {
            i++;
            break;
          }
          i++;
        }
      } else {
        buffer.write(c);
        i++;
      }
    }
    return buffer.toString();
  }

  static String _shorten(Object error) {
    final text = error.toString().replaceFirst('XmlParserException: ', '');
    final firstLine = text.split('\n').first.trim();
    return firstLine.isEmpty ? 'Invalid FXML.' : firstLine;
  }
}
