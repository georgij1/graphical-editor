import 'code_validator.dart';

// Token kinds produced by the Java lexer.
const _kWord = 0;
const _kNum = 1;
const _kStr = 2;
const _kOp = 3;
const _kEof = 4;

/// A single Java token with its 1-based position.
class _Tok {
  _Tok(this.kind, this.text, this.line, this.col, {this.unterminated = false});

  final int kind;
  final String text;
  final int line;
  final int col;

  /// True for a string/char literal the lexer could not close: the "unclosed
  /// literal" error is already reported, so no follow-up errors are added.
  final bool unterminated;

  /// Column right after the token — where the caret for "';' expected" goes.
  int get endCol => col + text.length;
}

class _ImportRec {
  _ImportRec(this.from, this.to, this.simple);

  final int from; // first line of the import statement
  final int to; // last line of the import statement
  final String simple;
}

class _TypeRec {
  _TypeRec(this.name, this.line, this.isPublic);

  final String name;
  final int line;
  final bool isPublic;
}

const _primitiveTypes = <String>{
  'int',
  'long',
  'short',
  'byte',
  'char',
  'float',
  'double',
  'boolean',
  'void',
};

const _modifiers = <String>{
  'public',
  'protected',
  'private',
  'static',
  'final',
  'abstract',
  'native',
  'synchronized',
  'transient',
  'volatile',
  'strictfp',
  'default',
  'sealed',
};

const _typeDeclKeywords = <String>{'class', 'interface', 'enum', 'record'};

/// Words that can never start a type: used to tell declarations apart from
/// expressions and to reject bogus types during error recovery.
const _nonTypeWords = <String>{
  'new',
  'instanceof',
  'return',
  'throw',
  'yield',
  'else',
  'case',
  'default',
  'do',
  'while',
  'if',
  'for',
  'switch',
  'try',
  'catch',
  'finally',
  'synchronized',
  'break',
  'continue',
  'import',
  'package',
  'extends',
  'implements',
  'throws',
  'permits',
  'this',
  'super',
  'true',
  'false',
  'null',
  'class',
  'interface',
  'enum',
  'record',
  'abstract',
  'public',
  'private',
  'protected',
  'static',
  'native',
  'transient',
  'volatile',
  'strictfp',
  'sealed',
};

/// Words that do not complete a value inside an expression (they expect an
/// operand), so a following word is not mistaken for a missing semicolon.
const _nonValueWords = <String>{
  'new',
  'instanceof',
  'void',
  'return',
  'throw',
  'yield',
  'else',
  'case',
  'default',
  'do',
  'while',
  'if',
  'for',
  'switch',
  'try',
  'catch',
  'finally',
  'synchronized',
  'break',
  'continue',
  'import',
  'package',
  'class',
  'interface',
  'enum',
  'record',
  'extends',
  'implements',
  'throws',
  'permits',
};

bool _isAsciiDigit(String ch) {
  final u = ch.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

bool _isAsciiLetter(String ch) {
  final u = ch.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7a) || (u >= 0x41 && u <= 0x5a);
}

final _numberRe = RegExp(
  r'^(?:'
  r'0[xX][0-9a-fA-F][0-9a-fA-F_]*(?:\.[0-9a-fA-F_]*)?(?:[pP][+-]?[0-9_]+)?[lL]?'
  r'|0[bB][01][01_]*[lL]?'
  r'|(?:[0-9][0-9_]*\.[0-9_]*|\.[0-9][0-9_]*|[0-9][0-9_]*)'
  r'(?:[eE][+-]?[0-9_]+)?[fFdDlL]?'
  r')$',
);

/// IntelliJ-IDEA-style static analysis of a Java source file.
///
/// The source is tokenized (reporting lexical problems such as unclosed
/// strings and comments with line and column) and then parsed with error
/// recovery, so a single run reports every syntax problem it can find:
/// missing semicolons, unmatched brackets, malformed declarations and so on.
/// On top of that, non-blocking warnings are raised for unused imports and
/// package/file inconsistencies.
class JavaLinter {
  JavaLinter({this.path});

  /// Repository-style path of the analyzed file (for example
  /// `src/main/java/com/example/MainApp.java`); enables the package and file
  /// name consistency warnings.
  final String? path;

  late final List<_Tok> _toks;
  late final List<ValidationIssue> _issues;
  int _i = 0;

  final List<_ImportRec> _imports = <_ImportRec>[];
  final List<_TypeRec> _topLevelTypes = <_TypeRec>[];
  String? _packageDecl;
  int? _packageLine;

  /// Tokenizes and analyzes [source], appending every problem to [issues].
  void lint(String source, List<ValidationIssue> issues) {
    _issues = issues;
    _toks = _lex(source);
    _i = 0;
    _parseCompilationUnit();
    _collectWarnings();
    if (_topLevelTypes.isEmpty) {
      _issues.add(const ValidationIssue('No "class" declaration found.'));
    }
  }

  // ------------------------------------------------------------- accessors

  _Tok get _cur => _toks[_i];
  bool get _isEof => _cur.kind == _kEof;
  _Tok _peek([int k = 1]) => _toks[(_i + k).clamp(0, _toks.length - 1)];

  bool _isOp(String t) => _cur.kind == _kOp && _cur.text == t;
  bool _isWord(String t) => _cur.kind == _kWord && _cur.text == t;

  void _next() {
    if (_i < _toks.length - 1) _i++;
  }

  void _reportAtCur(
    String msg, {
    List<String> args = const <String>[],
    ValidationSeverity severity = ValidationSeverity.error,
  }) {
    _issues.add(
      ValidationIssue(
        msg,
        args: args,
        line: _cur.line,
        column: _cur.col,
        severity: severity,
      ),
    );
  }

  /// Reports at the caret position right after the previous token — the place
  /// IntelliJ puts "';' expected".
  void _reportAfterPrev(String msg, {List<String> args = const <String>[]}) {
    final prev = _toks[_i > 0 ? _i - 1 : 0];
    _issues.add(
      ValidationIssue(msg, args: args, line: prev.line, column: prev.endCol),
    );
  }

  // ------------------------------------------------------------------ lexer

  List<_Tok> _lex(String source) {
    final toks = <_Tok>[];
    var line = 1;
    var col = 1;
    var i = 0;
    final n = source.length;

    while (i < n) {
      final c = source[i];
      if (c == '\n') {
        line++;
        col = 1;
        i++;
        continue;
      }
      if (c == '\r') {
        i++;
        continue;
      }
      if (c == ' ' || c == '\t' || c == '\f') {
        col++;
        i++;
        continue;
      }
      // line comment
      if (c == '/' && i + 1 < n && source[i + 1] == '/') {
        while (i < n && source[i] != '\n') {
          i++;
          col++;
        }
        continue;
      }
      // block comment
      if (c == '/' && i + 1 < n && source[i + 1] == '*') {
        final sl = line, sc = col;
        i += 2;
        col += 2;
        var closed = false;
        while (i < n) {
          if (source[i] == '*' && i + 1 < n && source[i + 1] == '/') {
            i += 2;
            col += 2;
            closed = true;
            break;
          }
          if (source[i] == '\n') {
            line++;
            col = 1;
            i++;
          } else {
            col++;
            i++;
          }
        }
        if (!closed) {
          _issues.add(
            ValidationIssue('Unclosed comment.', line: sl, column: sc),
          );
          break;
        }
        continue;
      }
      // string / text block / char literals
      if (c == '"') {
        final sl = line, sc = col;
        if (i + 2 < n && source[i + 1] == '"' && source[i + 2] == '"') {
          i += 3;
          col += 3;
          var closed = false;
          while (i < n) {
            if (source[i] == '"' &&
                i + 2 < n &&
                source[i + 1] == '"' &&
                source[i + 2] == '"') {
              i += 3;
              col += 3;
              closed = true;
              break;
            }
            if (source[i] == '\n') {
              line++;
              col = 1;
              i++;
            } else {
              col++;
              i++;
            }
          }
          if (!closed) {
            _issues.add(
              ValidationIssue(
                'Unclosed text block literal.',
                line: sl,
                column: sc,
              ),
            );
            break;
          }
          toks.add(_Tok(_kStr, '"""', sl, sc));
          continue;
        }
        final start = i;
        i++;
        col++;
        var closed = false;
        while (i < n) {
          final ch = source[i];
          if (ch == '\\') {
            if (i + 1 >= n || source[i + 1] == '\n') break;
            i += 2;
            col += 2;
            continue;
          }
          if (ch == '"') {
            i++;
            col++;
            closed = true;
            break;
          }
          if (ch == '\n') break;
          col++;
          i++;
        }
        if (!closed) {
          _issues.add(
            ValidationIssue('Unclosed string literal.', line: sl, column: sc),
          );
        }
        toks.add(
          _Tok(
            _kStr,
            source.substring(start, i),
            sl,
            sc,
            unterminated: !closed,
          ),
        );
        continue;
      }
      if (c == "'") {
        final sl = line, sc = col;
        final start = i;
        i++;
        col++;
        var closed = false;
        while (i < n) {
          final ch = source[i];
          if (ch == '\\') {
            if (i + 1 >= n || source[i + 1] == '\n') break;
            i += 2;
            col += 2;
            continue;
          }
          if (ch == "'") {
            i++;
            col++;
            closed = true;
            break;
          }
          if (ch == '\n') break;
          col++;
          i++;
        }
        if (!closed) {
          _issues.add(
            ValidationIssue(
              'Unclosed character literal.',
              line: sl,
              column: sc,
            ),
          );
        }
        toks.add(
          _Tok(
            _kStr,
            source.substring(start, i),
            sl,
            sc,
            unterminated: !closed,
          ),
        );
        continue;
      }
      // numbers
      final isDigit = _isAsciiDigit(c);
      final isDotDigit = c == '.' && i + 1 < n && _isAsciiDigit(source[i + 1]);
      if (isDigit || isDotDigit) {
        final sl = line, sc = col;
        final start = i;
        while (i < n) {
          final ch = source[i];
          if (_isAsciiDigit(ch) || _isAsciiLetter(ch) || ch == '_') {
            i++;
            col++;
            continue;
          }
          if (ch == '.' && i + 1 < n && _isAsciiDigit(source[i + 1])) {
            i++;
            col++;
            continue;
          }
          if ((ch == '+' || ch == '-') &&
              i > start &&
              (source[i - 1] == 'e' || source[i - 1] == 'E')) {
            i++;
            col++;
            continue;
          }
          break;
        }
        final text = source.substring(start, i);
        if (!_numberRe.hasMatch(text)) {
          _issues.add(
            ValidationIssue('Invalid number literal.', line: sl, column: sc),
          );
        }
        toks.add(_Tok(_kNum, text, sl, sc));
        continue;
      }
      // identifiers and keywords
      final isIdentStart = _isAsciiLetter(c) || c == '_' || c == r'$';
      if (isIdentStart) {
        final sl = line, sc = col;
        final start = i;
        while (i < n) {
          final ch = source[i];
          if (!(_isAsciiLetter(ch) ||
              _isAsciiDigit(ch) ||
              ch == '_' ||
              ch == r'$')) {
            break;
          }
          i++;
          col++;
        }
        toks.add(_Tok(_kWord, source.substring(start, i), sl, sc));
        continue;
      }
      // operators
      if (i + 2 < n && source.substring(i, i + 3) == '...') {
        toks.add(_Tok(_kOp, '...', line, col));
        i += 3;
        col += 3;
        continue;
      }
      const pairs = <String>{
        '==',
        '!=',
        '<=',
        '>=',
        '&&',
        '||',
        '++',
        '--',
        '+=',
        '-=',
        '*=',
        '/=',
        '%=',
        '&=',
        '|=',
        '^=',
        '->',
        '::',
      };
      if (i + 1 < n && pairs.contains(source.substring(i, i + 2))) {
        toks.add(_Tok(_kOp, source.substring(i, i + 2), line, col));
        i += 2;
        col += 2;
        continue;
      }
      const singles = '{}()[];,.?+-*/%&|^!<>=~:@';
      if (singles.contains(c)) {
        toks.add(_Tok(_kOp, c, line, col));
        i++;
        col++;
        continue;
      }
      _issues.add(
        ValidationIssue(
          "Illegal character '{0}'.",
          args: [c],
          line: line,
          column: col,
        ),
      );
      i++;
      col++;
    }
    toks.add(_Tok(_kEof, '', line, col));
    return toks;
  }

  // ------------------------------------------------------- compilation unit

  void _parseCompilationUnit() {
    if (_isWord('package')) {
      _packageLine = _cur.line;
      _next();
      _packageDecl = _parseDottedName();
      _expectSemicolon();
    }
    while (!_isEof) {
      if (_isWord('import')) {
        _parseImport();
      } else if (_isDeclStart()) {
        _parseTypeDecl(topLevel: true);
      } else if (_isOp('}')) {
        _reportAtCur('Unexpected "{0}".', args: ['}']);
        _next();
      } else {
        _reportAtCur('Class, interface, enum, or record expected.');
        _skipToDeclStart();
      }
    }
  }

  bool _isDeclStart() {
    if (_isOp('@')) return true;
    if (_cur.kind != _kWord) return false;
    return _modifiers.contains(_cur.text) ||
        _typeDeclKeywords.contains(_cur.text) ||
        (_cur.text == 'non' &&
            _peek().kind == _kOp &&
            _peek().text == '-' &&
            _peek(2).kind == _kWord &&
            _peek(2).text == 'sealed');
  }

  void _skipToDeclStart() {
    _next();
    while (!_isEof && !_isDeclStart() && !_isOp('}')) {
      _next();
    }
  }

  String? _parseDottedName() {
    if (_cur.kind != _kWord) return null;
    final parts = <String>[_cur.text];
    _next();
    while (_isOp('.') && _peek().kind == _kWord) {
      _next();
      parts.add(_cur.text);
      _next();
    }
    return parts.join('.');
  }

  void _expectSemicolon() {
    if (_isOp(';')) {
      _next();
      return;
    }
    final prev = _toks[_i > 0 ? _i - 1 : 0];
    if (prev.unterminated) return; // the lexer already reported it
    _reportAfterPrev("';' expected");
    _recoverToSemicolon();
  }

  void _recoverToSemicolon() {
    while (!_isEof && !_isOp(';') && !_isOp('}') && !_isDeclStart()) {
      _next();
    }
    if (_isOp(';')) _next();
  }

  void _parseImport() {
    final from = _cur.line;
    _next(); // import
    if (_isWord('static')) _next();
    var simple = '';
    var wildcard = false;
    if (_cur.kind == _kWord) {
      final parts = <String>[_cur.text];
      simple = _cur.text;
      _next();
      while (_isOp('.')) {
        if (_peek().kind == _kOp && _peek().text == '*') {
          _next();
          _next();
          wildcard = true;
          break;
        }
        if (_peek().kind != _kWord) break;
        _next();
        parts.add(_cur.text);
        simple = _cur.text;
        _next();
      }
      simple = parts.last;
    } else {
      _reportAtCur('Identifier expected.');
    }
    var to = _cur.line;
    if (_isOp(';')) {
      to = _cur.line;
      _next();
    } else {
      _reportAfterPrev("';' expected");
      while (!_isEof && !_isOp(';') && !_isDeclStart()) {
        _next();
      }
      if (_isOp(';')) to = _cur.line;
      if (_isOp(';')) _next();
    }
    if (simple.isNotEmpty && !wildcard) {
      _imports.add(_ImportRec(from, to, simple));
    }
  }

  // ------------------------------------------------------ type declarations

  void _parseTypeDecl({required bool topLevel}) {
    var isPublic = false;
    while (!_isEof) {
      if (_isOp('@')) {
        if (_peek().kind == _kWord && _peek().text == 'interface') break;
        _parseAnnotation();
        continue;
      }
      if (_cur.kind == _kWord && _modifiers.contains(_cur.text)) {
        if (_cur.text == 'public') isPublic = true;
        _next();
        continue;
      }
      if (_isWord('non') &&
          _peek().kind == _kOp &&
          _peek().text == '-' &&
          _peek(2).kind == _kWord &&
          _peek(2).text == 'sealed') {
        _next();
        _next();
        _next();
        continue;
      }
      break;
    }
    if (_isOp('@') && _peek().kind == _kWord && _peek().text == 'interface') {
      _next();
      _next();
    } else if (_cur.kind == _kWord && _typeDeclKeywords.contains(_cur.text)) {
      _next();
    } else {
      _reportAtCur('Class, interface, enum, or record expected.');
      _skipToDeclStart();
      return;
    }
    String? name;
    var nameLine = 0;
    if (_cur.kind == _kWord) {
      name = _cur.text;
      nameLine = _cur.line;
      _next();
    } else {
      _reportAtCur('Identifier expected.');
      while (!_isEof && !_isOp('{') && !_isOp('}') && !_isOp(';')) {
        _next();
      }
    }
    if (topLevel && name != null) {
      _topLevelTypes.add(_TypeRec(name, nameLine, isPublic));
    }
    // extends / implements / permits clauses
    while (!_isEof && !_isOp('{') && !_isOp(';') && !_isOp('}')) {
      _next();
    }
    if (_isOp('{')) {
      _parseClassBody();
    } else if (_isOp(';')) {
      _next();
    } else if (name != null) {
      _reportAfterPrev("'}' expected");
    }
  }

  void _parseClassBody() {
    final open = _cur;
    _next(); // {
    while (!_isEof && !_isOp('}')) {
      if (_isOp(';')) {
        _next();
        continue;
      }
      _parseMember();
    }
    if (_isOp('}')) {
      _next();
    } else {
      _issues.add(
        ValidationIssue(
          'Unclosed "{0}".',
          args: ['{'],
          line: open.line,
          column: open.col,
        ),
      );
    }
  }

  // --------------------------------------------------------------- members

  void _parseMember() {
    // annotations and modifiers
    while (!_isEof) {
      if (_isOp('@')) {
        if (_peek().kind == _kWord && _peek().text == 'interface') break;
        _parseAnnotation();
        continue;
      }
      if (_cur.kind == _kWord && _modifiers.contains(_cur.text)) {
        _next();
        continue;
      }
      if (_isWord('non') &&
          _peek().kind == _kOp &&
          _peek().text == '-' &&
          _peek(2).kind == _kWord &&
          _peek(2).text == 'sealed') {
        _next();
        _next();
        _next();
        continue;
      }
      break;
    }
    if (_isEof) return;
    // instance initializer
    if (_isOp('{')) {
      _parseBlock();
      return;
    }
    // nested type declaration (or annotation type)
    if ((_isOp('@') && _peek().kind == _kWord && _peek().text == 'interface') ||
        (_cur.kind == _kWord && _typeDeclKeywords.contains(_cur.text))) {
      _parseTypeDecl(topLevel: false);
      return;
    }
    // generic method / constructor type parameters
    if (_isOp('<')) _skipTypeArgs();
    if (!_parseType()) {
      _reportAtCur("';' expected");
      _next();
      while (!_isEof && !_isOp(';') && !_isOp('{') && !_isOp('}')) {
        _next();
      }
      if (_isOp(';')) _next();
      return;
    }
    // constructor: Type(
    if (_isOp('(')) {
      _parseParams();
      _parseMethodTail();
      return;
    }
    // method: Type name(
    if (_cur.kind == _kWord && _peek().kind == _kOp && _peek().text == '(') {
      _next();
      _parseParams();
      _parseMethodTail();
      return;
    }
    // field
    _parseNamedDeclarators();
  }

  void _parseParams() {
    if (!_isOp('(')) {
      _reportAfterPrev("';' expected");
      return;
    }
    _next(); // (
    var reported = false;
    while (!_isEof && !_isOp(')')) {
      while (_isOp('@')) {
        _parseAnnotation();
      }
      while (_isWord('final')) {
        _next();
      }
      if (!_parseType()) {
        if (!reported) {
          _reportAtCur("')' expected");
          reported = true;
        }
        break;
      }
      if (_isOp('...')) _next();
      if (_cur.kind == _kWord) {
        _next();
      } else {
        if (!reported) {
          _reportAtCur('Identifier expected.');
          reported = true;
        }
        break;
      }
      if (_isOp('=')) {
        _next();
        _consumeExpression(report: false);
      }
      if (_isOp(',')) {
        _next();
        continue;
      }
      break;
    }
    if (_isOp(')')) {
      _next();
    } else if (!reported) {
      _reportAfterPrev("')' expected");
      while (!_isEof && !_isOp(')') && !_isOp('}')) {
        _next();
      }
      if (_isOp(')')) _next();
    }
  }

  void _parseMethodTail() {
    if (_isWord('throws')) {
      _next();
      while (!_isEof) {
        if (_parseDottedName() == null) break;
        if (_isOp(',')) {
          _next();
          continue;
        }
        break;
      }
    }
    if (_isOp('{')) {
      _parseBlock();
      return;
    }
    if (_isOp(';')) {
      _next();
      return;
    }
    _reportAfterPrev("';' expected");
    _recoverToSemicolon();
  }

  /// Parses declarators when the type and the first variable name have not
  /// been consumed yet: `Type name (= init)? (, name (= init)?)* ;`.
  void _parseNamedDeclarators() {
    if (_isOp('...')) _next();
    if (_cur.kind != _kWord) {
      _reportAtCur('Identifier expected.');
      _recoverToSemicolon();
      return;
    }
    _next();
    _parseDeclaratorTail();
  }

  void _parseDeclaratorTail() {
    while (true) {
      if (_isOp('=')) {
        _next();
        _consumeExpression(report: false);
      }
      if (_isOp(',')) {
        _next();
        if (_cur.kind == _kWord && !_nonTypeWords.contains(_cur.text)) {
          _next();
          continue;
        }
        _reportAtCur('Identifier expected.');
        _recoverToSemicolon();
        return;
      }
      break;
    }
    _expectSemicolon();
  }

  void _parseLocalDeclaration() {
    while (_isOp('@')) {
      _parseAnnotation();
    }
    while (_isWord('final')) {
      _next();
    }
    if (!_parseType()) {
      _reportAtCur('Identifier expected.');
      _recoverToSemicolon();
      return;
    }
    _parseNamedDeclarators();
  }

  /// Consumes a type: `qualified.Name<Args>[]`. Returns false when the
  /// current token cannot start a type.
  bool _parseType() {
    if (_cur.kind != _kWord || _nonTypeWords.contains(_cur.text)) return false;
    _next();
    while (_isOp('.') && _peek().kind == _kWord) {
      _next();
      _next();
    }
    if (_isOp('<')) {
      if (!_skipTypeArgs()) return false;
    }
    while (_isOp('[') && _peek().kind == _kOp && _peek().text == ']') {
      _next();
      _next();
    }
    return true;
  }

  /// Consumes a `<...>` type argument list. Returns false when the list is
  /// malformed (tokens already consumed stay consumed — the caller reports
  /// and recovers).
  bool _skipTypeArgs() {
    if (!_isOp('<')) return false;
    var depth = 0;
    while (!_isEof) {
      if (_isOp('<')) {
        depth++;
        _next();
        continue;
      }
      if (_isOp('>')) {
        depth--;
        _next();
        if (depth == 0) return true;
        continue;
      }
      final legal =
          _cur.kind == _kWord ||
          _isOp('?') ||
          _isOp('.') ||
          _isOp(',') ||
          _isOp('[') ||
          _isOp(']') ||
          _isOp('&') ||
          _isOp('...');
      if (!legal) return false;
      _next();
    }
    return false;
  }

  void _parseAnnotation() {
    if (!_isOp('@')) return;
    _next();
    if (_cur.kind == _kWord) _parseDottedName();
    if (_isOp('(')) {
      var depth = 0;
      while (!_isEof) {
        if (_isOp(';')) break;
        if (_isOp('(')) {
          depth++;
          _next();
          continue;
        }
        if (_isOp(')')) {
          depth--;
          _next();
          if (depth == 0) break;
          continue;
        }
        _next();
      }
    }
  }

  // ------------------------------------------------------------ statements

  void _parseBlock() {
    final open = _cur;
    _next(); // {
    while (!_isEof && !_isOp('}')) {
      _parseStatement();
    }
    if (_isOp('}')) {
      _next();
    } else {
      _issues.add(
        ValidationIssue(
          'Unclosed "{0}".',
          args: ['{'],
          line: open.line,
          column: open.col,
        ),
      );
    }
  }

  void _parseStatement() {
    if (_isEof) return;
    if (_isOp(';')) {
      _next();
      return;
    }
    if (_isOp('{')) {
      _parseBlock();
      return;
    }
    if (_cur.kind == _kWord) {
      final w = _cur.text;
      // labeled statement: `name: stmt`
      if (_peek().kind == _kOp &&
          _peek().text == ':' &&
          w != 'case' &&
          w != 'default') {
        _next();
        _next();
        if (!_isEof && !_isOp('}')) _parseStatement();
        return;
      }
      switch (w) {
        case 'if':
          _parseIf();
          return;
        case 'for':
          _parseFor();
          return;
        case 'while':
          _parseWhile();
          return;
        case 'do':
          _parseDoWhile();
          return;
        case 'switch':
          _parseSwitch();
          return;
        case 'synchronized':
          _next();
          if (_isOp('(')) {
            _parseParenExpression();
          } else {
            _reportAfterPrev("';' expected");
          }
          _parseRequiredBlock();
          return;
        case 'try':
          _parseTry();
          return;
        case 'return':
        case 'throw':
        case 'yield':
          _next();
          if (!_isOp(';') && !_isEof && !_isOp('}')) {
            _consumeExpression(report: false);
          }
          _expectSemicolon();
          return;
        case 'break':
        case 'continue':
          _next();
          if (_cur.kind == _kWord) _next();
          _expectSemicolon();
          return;
        case 'assert':
          _next();
          _consumeExpression(report: false);
          _expectSemicolon();
          return;
      }
      if (_looksLikeDeclaration()) {
        _parseLocalDeclaration();
        return;
      }
      _parseExpressionStatement();
      return;
    }
    _parseExpressionStatement();
  }

  void _parseExpressionStatement() {
    final before = _i;
    _consumeExpression(report: true);
    if (_i == before) {
      // No progress: swallow the offending token so the loop always moves on.
      _reportAtCur('Unexpected "{0}".', args: [_cur.text]);
      _next();
    }
  }

  void _parseRequiredBlock() {
    if (_isOp('{')) {
      _parseBlock();
    } else {
      _reportAtCur('Statement expected.');
    }
  }

  void _parseIf() {
    _next(); // if
    if (_isOp('(')) {
      _parseParenExpression();
    } else {
      _reportAfterPrev("';' expected");
    }
    if (_isEof || _isOp('}')) {
      _reportAtCur('Statement expected.');
    } else {
      _parseStatement();
    }
    if (_isWord('else')) {
      _next();
      if (_isEof || _isOp('}')) {
        _reportAtCur('Statement expected.');
      } else {
        _parseStatement();
      }
    }
  }

  void _parseWhile() {
    _next(); // while
    if (_isOp('(')) {
      _parseParenExpression();
    } else {
      _reportAfterPrev("';' expected");
    }
    if (_isEof || _isOp('}')) {
      _reportAtCur('Statement expected.');
    } else {
      _parseStatement();
    }
  }

  void _parseDoWhile() {
    final doTok = _cur;
    _next(); // do
    if (_isEof || _isOp('}')) {
      _reportAtCur('Statement expected.');
    } else {
      _parseStatement();
    }
    if (_isWord('while')) {
      _next();
      if (_isOp('(')) {
        _parseParenExpression();
      } else {
        _reportAfterPrev("';' expected");
      }
    } else {
      _issues.add(
        ValidationIssue(
          "'while' expected.",
          line: doTok.line,
          column: doTok.col,
        ),
      );
    }
    _expectSemicolon();
  }

  /// Parses `for (init; cond; update) body` and the enhanced
  /// `for (Type x : iterable) body` forms.
  void _parseFor() {
    _next(); // for
    if (!_isOp('(')) {
      _reportAfterPrev("';' expected");
      if (!_isEof && !_isOp('}')) _parseStatement();
      return;
    }
    _next(); // (
    // Count the semicolons at depth 1: none means the enhanced form.
    var semis = 0;
    var depth = 1;
    var j = _i;
    while (j < _toks.length) {
      final t = _toks[j];
      if (t.kind == _kOp) {
        if (t.text == '(' || t.text == '[') {
          depth++;
        } else if (t.text == ')' || t.text == ']') {
          depth--;
          if (depth == 0) break;
        } else if (t.text == ';' && depth == 1) {
          semis++;
        } else if (t.text == '{') {
          break;
        }
      }
      j++;
    }
    if (semis == 0) {
      _parseEnhancedFor();
    } else {
      _parseClassicFor();
    }
    if (_isEof || _isOp('}')) {
      _reportAtCur('Statement expected.');
    } else {
      _parseStatement();
    }
  }

  void _parseClassicFor() {
    // init
    if (_isOp(';')) {
      _next();
    } else if (_looksLikeDeclaration()) {
      _parseLocalDeclaration();
    } else {
      _consumeExpression(report: false);
      if (_isOp(';')) {
        _next();
      } else {
        _reportAfterPrev("';' expected");
        _recoverToSemicolon();
      }
    }
    // condition
    if (_isOp(';')) {
      _next();
    } else {
      _consumeExpression(report: false);
      if (_isOp(';')) {
        _next();
      } else {
        _reportAfterPrev("';' expected");
        _recoverToSemicolon();
      }
    }
    // update
    if (_isOp(')')) {
      _next();
    } else {
      _consumeExpression(report: false, stopAtCloseParen: true);
      _expectCloseParen();
    }
  }

  void _parseEnhancedFor() {
    while (_isOp('@')) {
      _parseAnnotation();
    }
    while (_isWord('final')) {
      _next();
    }
    if (!_parseType()) {
      _reportAtCur('Identifier expected.');
      _recoverToSemicolon();
      return;
    }
    if (_isOp('...')) _next();
    if (_cur.kind == _kWord) {
      _next();
    } else {
      _reportAtCur('Identifier expected.');
    }
    if (_isOp(':')) {
      _next();
    } else {
      _reportAfterPrev("';' expected");
      while (!_isEof && !_isOp(')') && !_isOp('}')) {
        _next();
      }
    }
    _consumeExpression(report: false, stopAtCloseParen: true);
    _expectCloseParen();
  }

  void _parseParenExpression() {
    if (!_isOp('(')) return;
    _next();
    final before = _i;
    _consumeExpression(report: false, stopAtCloseParen: true);
    if (_isOp(')')) {
      _next();
      if (_i - before == 0) {
        _reportAfterPrev("';' expected");
      }
      return;
    }
    _reportAfterPrev("')' expected");
    while (!_isEof && !_isOp(')') && !_isOp('}')) {
      _next();
    }
    if (_isOp(')')) _next();
  }

  void _expectCloseParen() {
    if (_isOp(')')) {
      _next();
      return;
    }
    _reportAfterPrev("')' expected");
    while (!_isEof && !_isOp(')') && !_isOp('}')) {
      _next();
    }
    if (_isOp(')')) _next();
  }

  void _parseSwitch() {
    _next(); // switch
    if (_isOp('(')) {
      _parseParenExpression();
    } else {
      _reportAfterPrev("';' expected");
    }
    if (!_isOp('{')) {
      _reportAtCur('Statement expected.');
      if (!_isEof && !_isOp('}')) _parseStatement();
      return;
    }
    final open = _cur;
    _next(); // {
    while (!_isEof && !_isOp('}')) {
      if (_isOp(';')) {
        _next();
        continue;
      }
      if (_isWord('case')) {
        _next();
        _consumeExpression(report: false, stopAtColon: true, stopAtArrow: true);
        if (_isOp(':') || _isOp('->')) {
          _next();
        } else {
          _reportAfterPrev("';' expected");
          while (!_isEof &&
              !_isOp(':') &&
              !_isOp('->') &&
              !_isWord('case') &&
              !_isWord('default') &&
              !_isOp('}')) {
            _next();
          }
          if (_isOp(':') || _isOp('->')) _next();
        }
        if (_isOp('->')) {
          if (!_isEof &&
              !_isOp('}') &&
              !_isWord('case') &&
              !_isWord('default')) {
            _parseStatement();
          }
        }
        continue;
      }
      if (_isWord('default')) {
        _next();
        if (_isOp(':') || _isOp('->')) {
          _next();
        } else {
          _reportAfterPrev("';' expected");
          while (!_isEof &&
              !_isOp(':') &&
              !_isOp('->') &&
              !_isWord('case') &&
              !_isWord('default') &&
              !_isOp('}')) {
            _next();
          }
          if (_isOp(':') || _isOp('->')) _next();
        }
        if (_isOp('->')) {
          if (!_isEof &&
              !_isOp('}') &&
              !_isWord('case') &&
              !_isWord('default')) {
            _parseStatement();
          }
        }
        continue;
      }
      _parseStatement();
    }
    if (_isOp('}')) {
      _next();
    } else {
      _issues.add(
        ValidationIssue(
          'Unclosed "{0}".',
          args: ['{'],
          line: open.line,
          column: open.col,
        ),
      );
    }
  }

  void _parseTry() {
    _next(); // try
    var hasResources = false;
    if (_isOp('(')) {
      hasResources = true;
      _next();
      var depth = 1;
      while (!_isEof && depth > 0) {
        if (_isOp('(')) {
          depth++;
          _next();
          continue;
        }
        if (_isOp(')')) {
          depth--;
          _next();
          continue;
        }
        if (_isOp('{') || _isOp('}')) break;
        _next();
      }
    }
    var hasHandler = false;
    var hasFinally = false;
    if (_isOp('{')) {
      _parseBlock();
    } else {
      _reportAtCur('Statement expected.');
    }
    while (_isWord('catch') || _isWord('finally')) {
      if (_isWord('catch')) {
        hasHandler = true;
        _next();
        if (_isOp('(')) {
          _next();
          var reported = false;
          // (Type | Type) name
          while (!_isEof) {
            while (_isOp('@')) {
              _parseAnnotation();
            }
            if (!_parseType()) {
              if (!reported) {
                _reportAtCur("')' expected");
                reported = true;
              }
              break;
            }
            if (_isOp('|')) {
              _next();
              continue;
            }
            break;
          }
          if (_cur.kind == _kWord) {
            _next();
          } else if (!reported) {
            _reportAtCur('Identifier expected.');
            reported = true;
          }
          if (_isOp(')')) {
            _next();
          } else if (!reported) {
            _reportAfterPrev("')' expected");
            while (!_isEof && !_isOp(')') && !_isOp('}')) {
              _next();
            }
            if (_isOp(')')) _next();
          } else {
            while (!_isEof && !_isOp(')') && !_isOp('}')) {
              _next();
            }
            if (_isOp(')')) _next();
          }
        }
        if (_isOp('{')) {
          _parseBlock();
        } else {
          _reportAtCur('Statement expected.');
        }
      } else {
        hasFinally = true;
        _next();
        if (_isOp('{')) {
          _parseBlock();
        } else {
          _reportAtCur('Statement expected.');
        }
      }
    }
    if (!hasHandler && !hasFinally && !hasResources) {
      _issues.add(
        const ValidationIssue(
          "'try' without 'catch', 'finally' or resource declarations.",
        ),
      );
    }
  }

  // ------------------------------------------------------------ expressions

  bool _isValueLike(_Tok t) =>
      t.kind == _kNum ||
      t.kind == _kStr ||
      (t.kind == _kWord && !_nonValueWords.contains(t.text));

  /// Consumes an expression starting at the current token.
  ///
  /// Stops (without consuming) at a depth-0 `;` or `,`, at a `}` that closes
  /// the enclosing block, at `)` when [stopAtCloseParen] is set and at `:` /
  /// `->` for switch labels. When [report] is true (plain expression
  /// statements) an abnormal stop is reported as "';' expected" right after
  /// the last consumed token; otherwise the caller reports its own
  /// expectation.
  void _consumeExpression({
    required bool report,
    bool stopAtCloseParen = false,
    bool stopAtColon = false,
    bool stopAtArrow = false,
  }) {
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var genericDepth = 0;
    var ternary = 0;
    var instanceofAllow = 0;
    var prevValue = false;
    var consumed = 0;

    void stopWithSemicolon() {
      if (report && consumed > 0) _reportAfterPrev("';' expected");
    }

    while (!_isEof) {
      final t = _cur;
      // --- stop rules that only apply at expression depth 0 ---
      if (paren == 0 && bracket == 0 && brace == 0 && t.kind == _kOp) {
        final text = t.text;
        if (text == ';') return;
        if (text == ',') {
          // a comma inside `Map<String, Integer>` is not the end of anything
          if (genericDepth == 0) return;
        } else if (text == '}') {
          stopWithSemicolon();
          return;
        } else if (text == ')') {
          if (stopAtCloseParen) return;
          _reportAtCur('Unexpected "{0}".', args: [')']);
          _next();
          consumed++;
          prevValue = false;
          instanceofAllow = 0;
          continue;
        } else if (text == ']') {
          _reportAtCur('Unexpected "{0}".', args: [']']);
          _next();
          consumed++;
          prevValue = true;
          instanceofAllow = 0;
          continue;
        } else if (text == ':' && stopAtColon && ternary == 0) {
          return;
        } else if (text == '->' && stopAtArrow) {
          return;
        }
      }
      // --- a value right after a complete value: missing semicolon ---
      if (instanceofAllow == 0 && prevValue && _isValueLike(t)) {
        stopWithSemicolon();
        return;
      }
      if (instanceofAllow > 0 && _isValueLike(t)) instanceofAllow--;
      // --- consume exactly one token ---
      if (t.kind == _kOp) {
        final text = t.text;
        instanceofAllow = 0;
        if (text == '(') {
          if (_looksLikeCastParen(_i)) {
            // cast prefix `(Type)` — consumed as a unit, it expects an operand
            _next();
            while (!_isEof && !_isOp(')')) {
              _next();
            }
            if (_isOp(')')) _next();
            consumed++;
            prevValue = false;
            continue;
          }
          paren++;
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == ')') {
          paren--;
          _next();
          prevValue = true;
          consumed++;
          continue;
        }
        if (text == '[') {
          bracket++;
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == ']') {
          bracket--;
          _next();
          prevValue = true;
          consumed++;
          continue;
        }
        if (text == '{') {
          brace++;
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == '}') {
          if (brace > 0) {
            brace--;
            _next();
            prevValue = true;
            consumed++;
            continue;
          }
          stopWithSemicolon();
          return;
        }
        if (text == '++' || text == '--') {
          _next();
          prevValue = true;
          consumed++;
          continue;
        }
        if (text == '?') {
          ternary++;
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == ':') {
          if (ternary > 0) ternary--;
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == '.') {
          if (_peek().kind != _kWord) _reportAtCur('Identifier expected.');
          _next();
          prevValue = false;
          consumed++;
          continue;
        }
        if (text == '<') genericDepth++;
        if (text == '>' && genericDepth > 0) genericDepth--;
        _next();
        prevValue = false;
        consumed++;
        continue;
      }
      // words and literals
      _next();
      consumed++;
      if (t.kind == _kWord) {
        if (t.text == 'instanceof') {
          // allow `instanceof Type variable` without a false "';' expected"
          instanceofAllow = 2;
          prevValue = false;
          continue;
        }
        prevValue = !_nonValueWords.contains(t.text);
      } else {
        prevValue = true;
      }
    }
    if (report) stopWithSemicolon();
  }

  /// True when `toks[start]` is `(` and the tokens up to the matching `)`
  /// form a cast prefix such as `(String)`, `(List<String>)` or `(int[])`.
  bool _looksLikeCastParen(int start) {
    var j = start + 1;
    if (j >= _toks.length || _toks[j].kind != _kWord) return false;
    if (_nonTypeWords.contains(_toks[j].text)) return false;
    j++;
    while (j + 1 < _toks.length &&
        _toks[j].kind == _kOp &&
        _toks[j].text == '.' &&
        _toks[j + 1].kind == _kWord) {
      j += 2;
    }
    if (j < _toks.length && _toks[j].kind == _kOp && _toks[j].text == '<') {
      var depth = 0;
      var k = j;
      var ok = false;
      while (k < _toks.length) {
        final t = _toks[k];
        if (t.kind == _kOp && t.text == '<') {
          depth++;
          k++;
          continue;
        }
        if (t.kind == _kOp && t.text == '>') {
          depth--;
          k++;
          if (depth == 0) {
            ok = true;
            break;
          }
          continue;
        }
        final legal =
            t.kind == _kWord ||
            (t.kind == _kOp &&
                const {'?', '.', ',', '[', ']', '&', '...'}.contains(t.text));
        if (!legal) break;
        k++;
      }
      if (!ok) return false;
      j = k;
    }
    while (j + 1 < _toks.length &&
        _toks[j].kind == _kOp &&
        _toks[j].text == '[' &&
        _toks[j + 1].kind == _kOp &&
        _toks[j + 1].text == ']') {
      j += 2;
    }
    return j < _toks.length && _toks[j].kind == _kOp && _toks[j].text == ')';
  }

  // ------------------------------------------- declaration vs expression

  bool _looksLikeDeclaration() {
    if (_isOp('@')) return true;
    if (_cur.kind != _kWord) return false;
    final w = _cur.text;
    if (w == 'new') return false;
    if (_primitiveTypes.contains(w) || w == 'var' || w == 'final') return true;
    final p = _peek();
    if (p.kind == _kWord) return p.text != 'instanceof';
    if (p.kind == _kOp) {
      if (p.text == '<') return _genericFollowedByWord();
      if (p.text == '[') return _arrayFollowedByWord();
      if (p.text == '.') return _dottedFollowedByWord();
    }
    return false;
  }

  /// `List<String> x` is a declaration, `a < b && c > d` is an expression.
  bool _genericFollowedByWord() {
    var j = _i + 1;
    var depth = 0;
    while (j < _toks.length) {
      final t = _toks[j];
      if (t.kind == _kOp) {
        if (t.text == '<') {
          depth++;
          j++;
          continue;
        }
        if (t.text == '>') {
          depth--;
          j++;
          if (depth == 0) break;
          continue;
        }
        const legal = {',', '.', '?', '[', ']', '&', '...'};
        if (!legal.contains(t.text)) return false;
        j++;
        continue;
      }
      if (t.kind == _kWord) {
        j++;
        continue;
      }
      return false;
    }
    if (depth != 0 || j >= _toks.length) return false;
    return _toks[j].kind == _kWord;
  }

  /// `Foo[] x` is a declaration, `arr[0]` is an expression.
  bool _arrayFollowedByWord() {
    var j = _i + 1;
    while (j + 1 < _toks.length &&
        _toks[j].kind == _kOp &&
        _toks[j].text == '[' &&
        _toks[j + 1].kind == _kOp &&
        _toks[j + 1].text == ']') {
      j += 2;
    }
    if (j == _i + 1) return false;
    return j < _toks.length && _toks[j].kind == _kWord;
  }

  /// `com.example.Foo x` is a declaration, `foo.bar()` is a call.
  bool _dottedFollowedByWord() {
    if (_toks[_i].kind != _kWord) return false;
    var j = _i + 1;
    while (j + 1 < _toks.length &&
        _toks[j].kind == _kOp &&
        _toks[j].text == '.' &&
        _toks[j + 1].kind == _kWord) {
      j += 2;
    }
    return j < _toks.length && _toks[j].kind == _kWord;
  }

  // -------------------------------------------------------------- warnings

  void _collectWarnings() {
    final importLines = <int>{};
    for (final rec in _imports) {
      for (var l = rec.from; l <= rec.to; l++) {
        importLines.add(l);
      }
    }
    final words = <String>{};
    for (final t in _toks) {
      if (t.kind == _kWord && !importLines.contains(t.line)) {
        words.add(t.text);
      }
    }
    for (final rec in _imports) {
      if (!words.contains(rec.simple)) {
        _issues.add(
          ValidationIssue(
            "Unused import '{0}'.",
            args: [rec.simple],
            line: rec.from,
            column: 1,
            severity: ValidationSeverity.warning,
          ),
        );
      }
    }
    final p = path;
    if (p == null || !p.endsWith('.java')) return;
    const marker = 'src/main/java/';
    final idx = p.indexOf(marker);
    final fileName = p.split('/').last;
    if (idx >= 0) {
      final rest = p.substring(idx + marker.length);
      final slash = rest.lastIndexOf('/');
      final dir = slash >= 0 ? rest.substring(0, slash) : '';
      if (dir.isNotEmpty) {
        final expected = dir.replaceAll('/', '.');
        if (_packageDecl == null) {
          _issues.add(
            const ValidationIssue(
              'Package declaration is missing.',
              line: 1,
              column: 1,
              severity: ValidationSeverity.warning,
            ),
          );
        } else if (_packageDecl != expected) {
          _issues.add(
            ValidationIssue(
              "Package name '{0}' does not correspond to the file location '{1}'.",
              args: [_packageDecl!, dir],
              line: _packageLine,
              column: 1,
              severity: ValidationSeverity.warning,
            ),
          );
        }
      }
    }
    final base = fileName.endsWith('.java')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
    for (final t in _topLevelTypes) {
      if (t.isPublic && t.name != base) {
        _issues.add(
          ValidationIssue(
            "Class '{0}' is public, should be declared in a file named {0}.java.",
            args: [t.name],
            line: t.line,
            column: 1,
            severity: ValidationSeverity.warning,
          ),
        );
      }
    }
  }
}
