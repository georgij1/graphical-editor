import 'dart:ui';

import '../model/fxml_node.dart';

/// Reads and writes the geometry (position/size) attributes of a node, taking
/// the JavaFX layout semantics of the parent container into account.
class NodeGeometry {
  NodeGeometry(this.node);

  final FxmlNode node;

  FxmlNode? get parent => node.parent;

  static const Set<String> _absoluteParents = {
    'Pane', 'Region', 'AnchorPane', 'Group',
  };

  bool get _parentIsAbsolute =>
      parent != null && _absoluteParents.contains(parent!.tag);

  /// Whether the node can be freely positioned on the canvas.
  bool get isPositionable =>
      parent != null && (_parentIsAbsolute || parent == null);

  /// Whether the node has a size that can be manipulated.
  bool get isResizable => _sizeAttributes != null;

  double _attr(String name, double fallback) {
    final raw = node.attributes[name];
    if (raw == null) return fallback;
    return double.tryParse(raw) ?? fallback;
  }

  bool _has(String name) => node.attributes.containsKey(name);

  Offset position() {
    if (parent?.tag == 'AnchorPane') {
      final left = _attr('AnchorPane.leftAnchor',
          _has('AnchorPane.leftAnchor') ? 0 : _attr('layoutX', 0));
      final top = _attr('AnchorPane.topAnchor',
          _has('AnchorPane.topAnchor') ? 0 : _attr('layoutY', 0));
      return Offset(left, top);
    }
    return Offset(_attr('layoutX', 0), _attr('layoutY', 0));
  }

  void setPosition(Offset value) {
    if (parent?.tag == 'AnchorPane') {
      node.attributes['AnchorPane.leftAnchor'] = value.dx.toStringAsFixed(1);
      node.attributes['AnchorPane.topAnchor'] = value.dy.toStringAsFixed(1);
      node.attributes.remove('AnchorPane.rightAnchor');
      node.attributes.remove('AnchorPane.bottomAnchor');
      node.attributes.remove('layoutX');
      node.attributes.remove('layoutY');
      return;
    }
    node.attributes['layoutX'] = value.dx.toStringAsFixed(1);
    node.attributes['layoutY'] = value.dy.toStringAsFixed(1);
  }

  _SizeAttrs? get _sizeAttributes {
    switch (node.tag) {
      case 'Rectangle':
        return const _SizeAttrs('width', 'height');
      case 'Canvas':
        return const _SizeAttrs('width', 'height');
      case 'ImageView':
        return const _SizeAttrs('fitWidth', 'fitHeight');
      case 'Circle':
        return const _SizeAttrs('radius', 'radius');
      case 'Ellipse':
        return const _SizeAttrs('radiusX', 'radiusY');
      default:
        return const _SizeAttrs('prefWidth', 'prefHeight');
    }
  }

  Size? size() {
    final attrs = _sizeAttributes;
    if (attrs == null) return null;
    final w = node.attributes[attrs.width];
    final h = node.attributes[attrs.height];
    if (w == null && h == null) return null;
    double wv = double.tryParse(w ?? '') ?? -1;
    double hv = double.tryParse(h ?? '') ?? -1;
    if (node.tag == 'Circle') {
      wv = double.tryParse(w ?? '') ?? 0;
      hv = wv;
    }
    return Size(wv, hv);
  }

  void setSize(Size size) {
    final attrs = _sizeAttributes;
    if (attrs == null) return;
    if (node.tag == 'Circle') {
      final r = (size.width < size.height ? size.width : size.height);
      node.attributes['radius'] = r.toStringAsFixed(1);
      return;
    }
    node.attributes[attrs.width] = size.width.toStringAsFixed(1);
    node.attributes[attrs.height] = size.height.toStringAsFixed(1);
  }

  /// Current size, synthesising a default when no size is set.
  Size effectiveSize(Size fallback) => size() ?? fallback;
}

class _SizeAttrs {
  const _SizeAttrs(this.width, this.height);
  final String width;
  final String height;
}
