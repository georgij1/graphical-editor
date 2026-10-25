import '../model/fxml_node.dart';

/// Serializes an [FxmlDocument] back to a JavaFX FXML string.
class FxmlSerializer {
  const FxmlSerializer();

  String serialize(FxmlDocument document) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    for (final import in document.imports) {
      final value = import.trim();
      if (value.isEmpty) continue;
      final statement = value.startsWith('?') ? value : '<?import $value?>';
      buffer.writeln(statement);
    }
    _writeNode(buffer, document.root, 0, wrapChildren: true);
    return buffer.toString();
  }

  void _writeNode(
    StringBuffer buffer,
    FxmlNode node,
    int depth, {
    required bool wrapChildren,
  }) {
    final indent = '    ' * depth;
    buffer.write('$indent<${node.tag}');
    for (final entry in node.attributes.entries) {
      buffer.write(' ${entry.key}="${_escape(entry.value)}"');
    }

    final hasText = node.text != null && node.text!.isNotEmpty;
    final hasProperties = node.properties.isNotEmpty;
    final hasChildren = node.children.isNotEmpty;
    final selfClosing = !hasText && !hasProperties && !hasChildren;

    if (selfClosing) {
      buffer.writeln('/>');
      return;
    }
    buffer.writeln('>');

    if (hasText) {
      buffer.writeln('$indent    ${_escape(node.text!)}');
    }

    for (final property in node.properties.values) {
      _writeNode(buffer, property, depth + 1, wrapChildren: false);
    }

    if (hasChildren) {
      if (wrapChildren) {
        buffer.writeln('$indent    <children>');
        for (final child in node.children) {
          _writeNode(buffer, child, depth + 2, wrapChildren: true);
        }
        buffer.writeln('$indent    </children>');
      } else {
        for (final child in node.children) {
          _writeNode(buffer, child, depth + 1, wrapChildren: true);
        }
      }
    }

    buffer.writeln('$indent</${node.tag}>');
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
