import 'package:flutter/material.dart';

enum HighlightLanguage { plain, java, xml, css }

class HighlightingTextEditingController extends TextEditingController {
  HighlightingTextEditingController({
    super.text,
    this.language = HighlightLanguage.plain,
    this.dark = false,
  });

  HighlightLanguage language;
  bool dark;

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
    final spans = <TextSpan>[];
    final pattern = _patternFor(language);
    int last = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > last) {
        spans.add(TextSpan(text: source.substring(last, match.start), style: baseStyle));
      }
      final matched = match.group(0)!;
      spans.add(TextSpan(text: matched, style: baseStyle.merge(_styleForMatch(match, matched))));
      last = match.end;
    }
    if (last < source.length) {
      spans.add(TextSpan(text: source.substring(last), style: baseStyle));
    }
    return TextSpan(style: baseStyle, children: spans);
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
      case HighlightLanguage.plain:
        return RegExp(r'$^');
    }
  }

  TextStyle _styleForMatch(RegExpMatch m, String text) {
    final isDark = dark;
    Color? color;
    FontWeight? weight;
    if (m.namedGroup('comment') != null) {
      color = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
    } else if (m.namedGroup('string') != null) {
      color = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    } else if (m.namedGroup('keyword') != null) {
      color = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
      weight = FontWeight.w600;
    } else if (m.namedGroup('annotation') != null) {
      color = isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26);
    } else if (m.namedGroup('number') != null) {
      color = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
    } else if (m.namedGroup('tag') != null) {
      color = isDark ? const Color(0xFF569CD6) : const Color(0xFF800000);
      weight = FontWeight.w600;
    } else if (m.namedGroup('attr') != null || m.namedGroup('property') != null) {
      color = isDark ? const Color(0xFF9CDCFE) : const Color(0xFFFF0000);
    } else if (m.namedGroup('selector') != null) {
      color = isDark ? const Color(0xFFD7BA7D) : const Color(0xFF800000);
      weight = FontWeight.w600;
    } else if (m.namedGroup('pi') != null) {
      color = isDark ? const Color(0xFFC586C0) : const Color(0xFF800080);
    }
    return TextStyle(color: color, fontWeight: weight);
  }
}
