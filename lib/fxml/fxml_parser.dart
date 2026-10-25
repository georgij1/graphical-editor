import 'package:xml/xml.dart';

import '../model/fxml_node.dart';

/// Parses a JavaFX FXML document into an [FxmlDocument] tree.
///
/// The parser is intentionally tolerant: unknown elements and attributes are
/// preserved as-is so that editing a file and saving it back does not silently
/// drop information.
class FxmlParser {
  const FxmlParser();

  FxmlDocument parse(String source) {
    final xmlDoc = XmlDocument.parse(source);
    final imports = <String>[];
    for (final node in xmlDoc.children.whereType<XmlProcessing>()) {
      if (node.target == 'import') {
        final value = node.value.trim();
        if (value.isNotEmpty) imports.add(value);
      }
    }
    final rootElement = xmlDoc.rootElement;
    final root = _buildNode(rootElement);
    return FxmlDocument(root: root, imports: imports);
  }

  FxmlNode _buildNode(XmlElement element, {bool isProperty = false}) {
    final node = FxmlNode(element.name.qualified, isProperty: isProperty);
    for (final attribute in element.attributes) {
      node.attributes[attribute.name.qualified] = attribute.value;
    }

    final buffer = StringBuffer();
    for (final child in element.children) {
      if (child is XmlElement) {
        final tag = child.name.qualified;
        if (tag == 'children') {
          node.explicitChildrenTag = true;
          for (final grandChild in child.childElements) {
            node.addChild(_buildNode(grandChild));
          }
        } else if (_isPropertyElement(tag)) {
          node.properties[tag] = _buildNode(child, isProperty: true);
        } else {
          node.addChild(_buildNode(child));
        }
      } else if (child is XmlText || child is XmlCDATA) {
        buffer.write(child.value);
      }
    }
    final text = buffer.toString().trim();
    if (text.isNotEmpty) node.text = text;
    return node;
  }

  /// A property element is a lower-case tag (e.g. `padding`, `top`) or a static
  /// property reference (e.g. `GridPane.margin`).
  bool _isPropertyElement(String qualified) {
    if (qualified.contains('.')) {
      final last = qualified.split('.').last;
      return last.isNotEmpty && _isLower(last.codeUnitAt(0));
    }
    final local = qualified.contains(':') ? qualified.split(':').last : qualified;
    return local.isNotEmpty && _isLower(local.codeUnitAt(0));
  }

  bool _isLower(int codeUnit) => codeUnit >= 0x61 && codeUnit <= 0x7A;
}
