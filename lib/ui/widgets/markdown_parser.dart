import 'package:flutter/material.dart';

/// Simple Markdown parser that converts Markdown text to a list of Flutter
/// widgets for rendering. Supports:
/// - Headers (# H1, ## H2, etc.)
/// - Paragraphs
/// - Bold (**text**) and italic (*text*)
/// - Unordered lists (- item)
/// - Code blocks (```code```)
/// - Inline code (`code`)
/// - Links ([text](url))
/// - Horizontal rules (---)
/// - Blockquotes (> text)
class MarkdownParser {
  /// Parses [source] Markdown text and returns a list of widgets.
  static List<Widget> parse(String source, {required ThemeData theme}) {
    if (source.trim().isEmpty) {
      return [
        Text(
          'No content',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ];
    }

    final widgets = <Widget>[];
    final lines = source.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();

      // Empty line
      if (line.isEmpty) {
        i++;
        continue;
      }

      // Code block
      if (line.startsWith('```')) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
        widgets.add(_buildCodeBlock(codeLines.join('\n'), theme));
        continue;
      }

      // Headers
      if (line.startsWith('#')) {
        int level = 0;
        while (level < line.length && line[level] == '#') {
          level++;
        }
        final text = line.substring(level).trim();
        widgets.add(_buildHeader(level, text, theme));
        i++;
        continue;
      }

      // Horizontal rule
      if (line == '---' || line == '***' || line == '___') {
        widgets.add(Divider(color: theme.dividerColor, thickness: 1));
        i++;
        continue;
      }

      // Blockquote
      if (line.startsWith('>')) {
        final text = line.substring(1).trim();
        widgets.add(_buildBlockquote(text, theme));
        i++;
        continue;
      }

      // Unordered list
      if (line.startsWith('- ') || line.startsWith('* ')) {
        final listItems = <String>[];
        while (i < lines.length && (lines[i].trim().startsWith('- ') || lines[i].trim().startsWith('* '))) {
          listItems.add(lines[i].trim().substring(2));
          i++;
        }
        widgets.add(_buildUnorderedList(listItems, theme));
        continue;
      }

      // Paragraph
      final paragraphLines = <String>[line];
      i++;
      while (i < lines.length && lines[i].trim().isNotEmpty &&
          !lines[i].trim().startsWith('#') &&
          !lines[i].trim().startsWith('```') &&
          !lines[i].trim().startsWith('- ') &&
          !lines[i].trim().startsWith('* ') &&
          !lines[i].trim().startsWith('>')) {
        paragraphLines.add(lines[i].trim());
        i++;
      }
      widgets.add(_buildParagraph(paragraphLines.join(' '), theme));
    }

    return widgets;
  }

  static Widget _buildHeader(int level, String text, ThemeData theme) {
    final styles = {
      1: theme.textTheme.headlineLarge,
      2: theme.textTheme.headlineMedium,
      3: theme.textTheme.headlineSmall,
      4: theme.textTheme.titleLarge,
      5: theme.textTheme.titleMedium,
      6: theme.textTheme.titleSmall,
    };
    final style = styles[level] ?? theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: style),
    );
  }

  static Widget _buildParagraph(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: _buildInlineText(text, theme),
    );
  }

  static Widget _buildInlineText(String text, ThemeData theme) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`|\[(.+?)\]\((.+?)\)');
    final matches = pattern.allMatches(text).toList();

    if (matches.isEmpty) {
      return Text(text, style: theme.textTheme.bodyMedium);
    }

    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null || match.group(2) != null) {
        // Bold
        spans.add(TextSpan(
          text: match.group(1) ?? match.group(2),
          style: TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null || match.group(4) != null) {
        // Italic
        spans.add(TextSpan(
          text: match.group(3) ?? match.group(4),
          style: TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(5) != null) {
        // Inline code
        spans.add(TextSpan(
          text: match.group(5),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14,
          ),
        ));
      } else if (match.group(6) != null && match.group(7) != null) {
        // Link
        spans.add(TextSpan(
          text: match.group(6),
          style: TextStyle(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  static Widget _buildCodeBlock(String code, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static Widget _buildBlockquote(String text, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outline, width: 4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  static Widget _buildUnorderedList(List<String> items, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: theme.textTheme.bodyMedium),
                Expanded(child: _buildInlineText(item, theme)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
