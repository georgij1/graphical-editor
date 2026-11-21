import 'package:flutter/material.dart';

enum HighlightLanguage {
  plain,
  java,
  xml,
  css,
  shell,
  batch,
  gradle,
  gitignore,
  markdown,
}

class HighlightingTextEditingController extends TextEditingController {
  HighlightingTextEditingController({
    super.text,
    this.language = HighlightLanguage.plain,
    this.dark = false,
  });

  HighlightLanguage language;
  bool dark;

  void refresh() => notifyListeners();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final source = text;
    if (source.isEmpty || language == HighlightLanguage.plain) {
      return super.buildTextSpan(
        context: context,
        style: baseStyle,
        withComposing: withComposing,
      );
    }
    try {
      final spans = <TextSpan>[];
      final pattern = _patternFor(language);
      int last = 0;
      for (final match in pattern.allMatches(source)) {
        if (match.start > last) {
          spans.add(
            TextSpan(
              text: source.substring(last, match.start),
              style: baseStyle,
            ),
          );
        }
        final matched = match.group(0)!;
        spans.add(
          TextSpan(
            text: matched,
            style: baseStyle.merge(_styleForMatch(match, matched)),
          ),
        );
        last = match.end;
      }
      if (last < source.length) {
        spans.add(TextSpan(text: source.substring(last), style: baseStyle));
      }
      return TextSpan(style: baseStyle, children: spans);
    } catch (_) {
      return TextSpan(text: source, style: baseStyle);
    }
  }

  RegExp _patternFor(HighlightLanguage lang) {
    switch (lang) {
      case HighlightLanguage.java:
        return RegExp(
          r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/)|'
          r'(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')|"
          r'(?<annotation>@[A-Za-z_]\w*)|'
          r'(?<keyword>\b(?:abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|null|package|private|protected|public|return|short|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while|var|record|sealed|permits|yield|true|false)\b)|'
          r'(?<number>\b\d+(?:\.\d+)?[fFdDlL]?\b)',
          multiLine: true,
        );
      case HighlightLanguage.xml:
        return RegExp(
          r'(?<comment><!--[\s\S]*?-->)|'
          r'(?<pi><\?[\s\S]*?\?>)|'
          r'(?<tag></?[A-Za-z_][\w:.-]*(?:\s|/?>))|'
          r'(?<attr>\b[A-Za-z_][\w:.-]*(?=\s*=))|'
          r'(?<string>"[^"]*"|'
          r"'[^']*')",
          multiLine: true,
        );
      case HighlightLanguage.css:
        return RegExp(
          r'(?<comment>/\*[\s\S]*?\*/)|'
          r'(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')|"
          r'(?<property>\b-?[a-zA-Z_][\w-]*(?=\s*:))|'
          r'(?<selector>[.#][A-Za-z_][\w-]*)|'
          r'(?<keyword>@[A-Za-z_-]+|\b(?:important|inherit|initial|unset|none|auto|solid|dashed|dotted|block|inline|flex|grid)\b)|'
          r'(?<number>\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms)?\b)',
          multiLine: true,
        );
      case HighlightLanguage.shell:
        return RegExp(
          r'(#[^\n]*)|'
          r'("[^"\n]*")|'
          r"(\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}\n]+\})|"
          r'(\b(?:if|then|else|elif|fi|for|in|do|done|while|case|esac|function|export|local|return|exit|set|unset|cd|echo|source|test)\b)|'
          r'(\b\d+\b)',
          multiLine: true,
        );
      case HighlightLanguage.batch:
        return RegExp(
          r'(^\s*@?\s*(?:REM\b|::).*$)|'
          r'("[^"\r\n]*")|'
          r'(%%[A-Za-z]|%~?[A-Za-z0-9_*]+%?|![A-Za-z0-9_]+!)|'
          r'(\b(?:if|else|for|in|do|goto|call|set|setlocal|endlocal|echo|exit|pause|rem|shift|pushd|popd|cd|chdir|dir|copy|xcopy|move|del|erase|md|mkdir|rd|rmdir|cls|title|type|path|start|defined|exist|errorlevel|not|equ|neq|lss|leq|gtr|geq|off|on|assoc|ftype|ver|vol|date|time|find|findstr|sort|more|powershell|msiexec)\b)|'
          r'(^\s*:[A-Za-z0-9_.][A-Za-z0-9_.-]*)|'
          r'(\b\d+\b)',
          multiLine: true,
          caseSensitive: false,
        );
      case HighlightLanguage.gradle:
        return RegExp(
          r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/)|'
          r'(?<string>"""[\s\S]*?"""|'
          r"'''[\s\S]*?'''|"
          r'"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')|"
          r'(?<keyword>\b(?:plugins|dependencies|repositories|implementation|api|compileOnly|runtimeOnly|testImplementation|testCompileOnly|testRuntimeOnly|annotationProcessor|kapt|classpath|id|version|group|name|apply|plugin|from|into|include|exclude|project|subprojects|allprojects|buildscript|ext|task|tasks|def|val|var|new|if|else|for|in|while|do|switch|case|break|continue|return|try|catch|finally|throw|throws|import|package|class|interface|enum|extends|implements|static|final|abstract|public|private|protected|void|boolean|int|long|double|float|true|false|null|as|is|in|instanceof|assert|mavenCentral|google|gradlePluginPortal|maven|flatDir|ivy|jcenter|resolutionStrategy|configurations|sourceSets|java|kotlin|application|javafx|modules|mainClass|mainClassName|test|useJUnitPlatform|jar|bootJar|manifest|attributes|files|file|fileTree|platform|enforcedPlatform|constraints)\b)|'
          r'(?<number>\b\d+(?:\.\d+)?\b)',
          multiLine: true,
        );
      case HighlightLanguage.gitignore:
        return RegExp(
          r'(?<comment>^\s*#.*$)|'
          r'(?<negation>^\s*!)|'
          r'(?<glob>\*\*|\*|\?|\[(?:\\.|[^\]\n])*\])|'
          r'(?<escape>\\.)',
          multiLine: true,
        );
      case HighlightLanguage.markdown:
        return RegExp(
          r'(?<code>```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]+`)|'
          r'(?<heading>^\s{0,3}#{1,6}[ \t].*$)|'
          r'(?<quote>^\s{0,3}>.*$)|'
          r'(?<list>^\s*(?:[-*+]|\d+\.)\s)|'
          r'(?<link>!?\[[^\]\n]*\]\([^\)\n]*\)|!?\[[^\]\n]*\]\[[^\]\n]*\])|'
          r'(?<bold>\*\*[^*\n]+\*\*|__[^_\n]+__)|'
          r'(?<hr>^\s{0,3}(?:[-*_][ \t]*){3,}\s*$)',
          multiLine: true,
        );
      case HighlightLanguage.plain:
        return RegExp(r'$^');
    }
  }

  TextStyle _styleForMatch(RegExpMatch m, String text) {
    final isDark = dark;
    Color? color;
    FontWeight? weight;

    if (language == HighlightLanguage.shell) {
      if (m.group(1) != null) {
        color = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
      } else if (m.group(2) != null) {
        color = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
      } else if (m.group(3) != null) {
        color = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF001080);
        weight = FontWeight.w600;
      } else if (m.group(4) != null) {
        color = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
        weight = FontWeight.w600;
      } else if (m.group(5) != null) {
        color = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
      }
      return TextStyle(color: color, fontWeight: weight);
    }

    if (language == HighlightLanguage.batch) {
      if (m.group(1) != null) {
        color = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
      } else if (m.group(2) != null) {
        color = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
      } else if (m.group(3) != null) {
        color = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF001080);
        weight = FontWeight.w600;
      } else if (m.group(4) != null) {
        color = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
        weight = FontWeight.w600;
      } else if (m.group(5) != null) {
        color = isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26);
        weight = FontWeight.w600;
      } else if (m.group(6) != null) {
        color = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
      }
      return TextStyle(color: color, fontWeight: weight);
    }

    bool has(String name) {
      try {
        return m.namedGroup(name) != null;
      } catch (_) {
        return false;
      }
    }

    if (has('comment')) {
      color = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
    } else if (has('string')) {
      color = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    } else if (has('keyword')) {
      color = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
      weight = FontWeight.w600;
    } else if (has('annotation')) {
      color = isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26);
    } else if (has('number')) {
      color = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
    } else if (has('tag')) {
      color = isDark ? const Color(0xFF569CD6) : const Color(0xFF800000);
      weight = FontWeight.w600;
    } else if (has('attr') || has('property')) {
      color = isDark ? const Color(0xFF9CDCFE) : const Color(0xFFFF0000);
    } else if (has('selector')) {
      color = isDark ? const Color(0xFFD7BA7D) : const Color(0xFF800000);
      weight = FontWeight.w600;
    } else if (has('pi')) {
      color = isDark ? const Color(0xFFC586C0) : const Color(0xFF800080);
    } else if (has('variable')) {
      color = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF001080);
      weight = FontWeight.w600;
    } else if (has('negation')) {
      color = isDark ? const Color(0xFFC586C0) : const Color(0xFFAF00DB);
      weight = FontWeight.w700;
    } else if (has('glob')) {
      color = isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26);
      weight = FontWeight.w600;
    } else if (has('escape')) {
      color = isDark ? const Color(0xFF4EC9B0) : const Color(0xFF267F99);
      weight = FontWeight.w600;
    } else if (has('heading')) {
      color = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
      weight = FontWeight.w700;
    } else if (has('code')) {
      color = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    } else if (has('link')) {
      color = isDark ? const Color(0xFF4EC9B0) : const Color(0xFF267F99);
    } else if (has('bold')) {
      color = isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26);
      weight = FontWeight.w700;
    } else if (has('list')) {
      color = isDark ? const Color(0xFFC586C0) : const Color(0xFFAF00DB);
      weight = FontWeight.w600;
    } else if (has('quote')) {
      color = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
    } else if (has('hr')) {
      color = isDark ? const Color(0xFF858585) : const Color(0xFF6E7681);
      weight = FontWeight.w600;
    }
    return TextStyle(color: color, fontWeight: weight);
  }
}