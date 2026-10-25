import 'package:flutter/foundation.dart';

/// Editing widget type used by the property inspector.
enum FxPropKind { text, number, boolean, color, enumeration, multiline, insets }

/// Descriptor of an editable JavaFX property.
@immutable
class FxProp {
  const FxProp(
    this.name,
    this.label,
    this.kind, {
    this.values = const <String>[],
    this.group = 'Properties',
  });

  final String name;
  final String label;
  final FxPropKind kind;
  final List<String> values;
  final String group;
}

/// Knowledge base describing which properties are relevant for each JavaFX
/// component. Used to build a friendly inspector instead of a raw key/value
/// grid.
class FxMeta {
  const FxMeta._();

  static const List<FxProp> commonNodeProps = <FxProp>[
    FxProp('id', 'id', FxPropKind.text, group: 'Node'),
    FxProp('styleClass', 'styleClass', FxPropKind.text, group: 'Node'),
    FxProp('style', 'style (CSS)', FxPropKind.multiline, group: 'Node'),
    FxProp('visible', 'visible', FxPropKind.boolean, values: ['true', 'false'], group: 'Node'),
    FxProp('managed', 'managed', FxPropKind.boolean, values: ['true', 'false'], group: 'Node'),
    FxProp('opacity', 'opacity', FxPropKind.number, group: 'Node'),
    FxProp('rotate', 'rotate', FxPropKind.number, group: 'Transform'),
    FxProp('translateX', 'translateX', FxPropKind.number, group: 'Transform'),
    FxProp('translateY', 'translateY', FxPropKind.number, group: 'Transform'),
    FxProp('layoutX', 'layoutX', FxPropKind.number, group: 'Layout'),
    FxProp('layoutY', 'layoutY', FxPropKind.number, group: 'Layout'),
    FxProp('prefWidth', 'prefWidth', FxPropKind.number, group: 'Layout'),
    FxProp('prefHeight', 'prefHeight', FxPropKind.number, group: 'Layout'),
    FxProp('minWidth', 'minWidth', FxPropKind.number, group: 'Layout'),
    FxProp('maxWidth', 'maxWidth', FxPropKind.number, group: 'Layout'),
    FxProp('minHeight', 'minHeight', FxPropKind.number, group: 'Layout'),
    FxProp('maxHeight', 'maxHeight', FxPropKind.number, group: 'Layout'),
  ];

  static final Map<String, List<FxProp>> _controlProps = <String, List<FxProp>>{
    'Label': _textProps('Label text'),
    'Button': _textProps('Button text'),
    'ToggleButton': _textProps('Toggle text'),
    'CheckBox': _textProps('CheckBox text'),
    'RadioButton': _textProps('RadioButton text'),
    'Hyperlink': _textProps('Link text'),
    'TextField': [
      const FxProp('text', 'text', FxPropKind.text, group: 'Content'),
      const FxProp('promptText', 'promptText', FxPropKind.text, group: 'Content'),
      const FxProp('editable', 'editable', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
    ],
    'PasswordField': [
      const FxProp('text', 'text', FxPropKind.text, group: 'Content'),
      const FxProp('promptText', 'promptText', FxPropKind.text, group: 'Content'),
    ],
    'TextArea': [
      const FxProp('text', 'text', FxPropKind.multiline, group: 'Content'),
      const FxProp('promptText', 'promptText', FxPropKind.text, group: 'Content'),
      const FxProp('wrapText', 'wrapText', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
    ],
    'ComboBox': [
      const FxProp('promptText', 'promptText', FxPropKind.text, group: 'Content'),
      const FxProp('value', 'value', FxPropKind.text, group: 'Content'),
      const FxProp('visibleRowCount', 'visibleRowCount', FxPropKind.number, group: 'Content'),
    ],
    'ChoiceBox': [
      const FxProp('value', 'value', FxPropKind.text, group: 'Content'),
    ],
    'Slider': [
      const FxProp('min', 'min', FxPropKind.number, group: 'Value'),
      const FxProp('max', 'max', FxPropKind.number, group: 'Value'),
      const FxProp('value', 'value', FxPropKind.number, group: 'Value'),
      const FxProp('orientation', 'orientation', FxPropKind.enumeration, values: ['HORIZONTAL', 'VERTICAL'], group: 'Value'),
      const FxProp('showTickLabels', 'showTickLabels', FxPropKind.boolean, values: ['true', 'false'], group: 'Value'),
    ],
    'ProgressBar': [
      const FxProp('progress', 'progress', FxPropKind.number, group: 'Value'),
    ],
    'ProgressIndicator': [
      const FxProp('progress', 'progress', FxPropKind.number, group: 'Value'),
    ],
    'Separator': [
      const FxProp('orientation', 'orientation', FxPropKind.enumeration, values: ['HORIZONTAL', 'VERTICAL'], group: 'Value'),
    ],
    'TitledPane': [
      const FxProp('text', 'title', FxPropKind.text, group: 'Content'),
      const FxProp('collapsible', 'collapsible', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
      const FxProp('expanded', 'expanded', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
    ],
    'ScrollPane': [
      const FxProp('fitToWidth', 'fitToWidth', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
      const FxProp('fitToHeight', 'fitToHeight', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
    ],
    'AnchorPane': [
      const FxProp('prefWidth', 'prefWidth', FxPropKind.number, group: 'Layout'),
      const FxProp('prefHeight', 'prefHeight', FxPropKind.number, group: 'Layout'),
    ],
    'VBox': [
      const FxProp('spacing', 'spacing', FxPropKind.number, group: 'Layout'),
      const FxProp('alignment', 'alignment', FxPropKind.enumeration, values: _posValues, group: 'Layout'),
    ],
    'HBox': [
      const FxProp('spacing', 'spacing', FxPropKind.number, group: 'Layout'),
      const FxProp('alignment', 'alignment', FxPropKind.enumeration, values: _posValues, group: 'Layout'),
    ],
    'FlowPane': [
      const FxProp('hgap', 'hgap', FxPropKind.number, group: 'Layout'),
      const FxProp('vgap', 'vgap', FxPropKind.number, group: 'Layout'),
      const FxProp('orientation', 'orientation', FxPropKind.enumeration, values: ['HORIZONTAL', 'VERTICAL'], group: 'Layout'),
    ],
    'TilePane': [
      const FxProp('hgap', 'hgap', FxPropKind.number, group: 'Layout'),
      const FxProp('vgap', 'vgap', FxPropKind.number, group: 'Layout'),
      const FxProp('prefColumns', 'prefColumns', FxPropKind.number, group: 'Layout'),
      const FxProp('prefRows', 'prefRows', FxPropKind.number, group: 'Layout'),
    ],
    'GridPane': [
      const FxProp('hgap', 'hgap', FxPropKind.number, group: 'Layout'),
      const FxProp('vgap', 'vgap', FxPropKind.number, group: 'Layout'),
    ],
    'StackPane': [
      const FxProp('alignment', 'alignment', FxPropKind.enumeration, values: _posValues, group: 'Layout'),
    ],
    'BorderPane': [
      const FxProp('alignment', 'alignment', FxPropKind.enumeration, values: _posValues, group: 'Layout'),
    ],
    'Rectangle': [
      const FxProp('width', 'width', FxPropKind.number, group: 'Geometry'),
      const FxProp('height', 'height', FxPropKind.number, group: 'Geometry'),
      const FxProp('arcWidth', 'arcWidth', FxPropKind.number, group: 'Geometry'),
      const FxProp('arcHeight', 'arcHeight', FxPropKind.number, group: 'Geometry'),
      ..._shapeFillProps,
    ],
    'Circle': [
      const FxProp('radius', 'radius', FxPropKind.number, group: 'Geometry'),
      const FxProp('centerX', 'centerX', FxPropKind.number, group: 'Geometry'),
      const FxProp('centerY', 'centerY', FxPropKind.number, group: 'Geometry'),
      ..._shapeFillProps,
    ],
    'Ellipse': [
      const FxProp('radiusX', 'radiusX', FxPropKind.number, group: 'Geometry'),
      const FxProp('radiusY', 'radiusY', FxPropKind.number, group: 'Geometry'),
      ..._shapeFillProps,
    ],
    'Line': [
      const FxProp('startX', 'startX', FxPropKind.number, group: 'Geometry'),
      const FxProp('startY', 'startY', FxPropKind.number, group: 'Geometry'),
      const FxProp('endX', 'endX', FxPropKind.number, group: 'Geometry'),
      const FxProp('endY', 'endY', FxPropKind.number, group: 'Geometry'),
      ..._shapeStrokeProps,
    ],
    'Polygon': _shapeFillProps,
    'Polyline': _shapeStrokeProps,
    'Text': [
      const FxProp('text', 'text', FxPropKind.text, group: 'Content'),
      const FxProp('fill', 'fill', FxPropKind.color, group: 'Appearance'),
      const FxProp('x', 'x', FxPropKind.number, group: 'Geometry'),
      const FxProp('y', 'y', FxPropKind.number, group: 'Geometry'),
      const FxProp('textAlignment', 'textAlignment', FxPropKind.enumeration, values: ['LEFT', 'CENTER', 'RIGHT', 'JUSTIFY'], group: 'Content'),
    ],
    'ImageView': [
      const FxProp('fitWidth', 'fitWidth', FxPropKind.number, group: 'Geometry'),
      const FxProp('fitHeight', 'fitHeight', FxPropKind.number, group: 'Geometry'),
      const FxProp('preserveRatio', 'preserveRatio', FxPropKind.boolean, values: ['true', 'false'], group: 'Geometry'),
      const FxProp('image', 'image (url)', FxPropKind.text, group: 'Content'),
    ],
    'Canvas': [
      const FxProp('width', 'width', FxPropKind.number, group: 'Geometry'),
      const FxProp('height', 'height', FxPropKind.number, group: 'Geometry'),
    ],
    'ColorPicker': [
      const FxProp('value', 'value', FxPropKind.color, group: 'Value'),
    ],
    'Spinner': [
      const FxProp('editable', 'editable', FxPropKind.boolean, values: ['true', 'false'], group: 'Behaviour'),
    ],
  };

  static const List<FxProp> _shapeFillProps = <FxProp>[
    FxProp('fill', 'fill', FxPropKind.color, group: 'Appearance'),
    FxProp('stroke', 'stroke', FxPropKind.color, group: 'Appearance'),
    FxProp('strokeWidth', 'strokeWidth', FxPropKind.number, group: 'Appearance'),
    FxProp('opacity', 'opacity', FxPropKind.number, group: 'Appearance'),
  ];

  static const List<FxProp> _shapeStrokeProps = <FxProp>[
    FxProp('fill', 'fill', FxPropKind.color, group: 'Appearance'),
    FxProp('stroke', 'stroke', FxPropKind.color, group: 'Appearance'),
    FxProp('strokeWidth', 'strokeWidth', FxPropKind.number, group: 'Appearance'),
  ];

  static const List<String> _posValues = <String>[
    'TOP_LEFT', 'TOP_CENTER', 'TOP_RIGHT',
    'CENTER_LEFT', 'CENTER', 'CENTER_RIGHT',
    'BOTTOM_LEFT', 'BOTTOM_CENTER', 'BOTTOM_RIGHT',
  ];

  static List<FxProp> _textProps(String label) => <FxProp>[
        FxProp('text', 'text', FxPropKind.text, group: 'Content'),
        const FxProp('wrapText', 'wrapText', FxPropKind.boolean, values: ['true', 'false'], group: 'Content'),
      ];

  /// Layout constraints a child can set for a given parent container.
  static List<FxProp> constraintsFor(String? parentTag) {
    switch (parentTag) {
      case 'AnchorPane':
        return const <FxProp>[
          FxProp('AnchorPane.topAnchor', 'topAnchor', FxPropKind.number, group: 'Anchors'),
          FxProp('AnchorPane.bottomAnchor', 'bottomAnchor', FxPropKind.number, group: 'Anchors'),
          FxProp('AnchorPane.leftAnchor', 'leftAnchor', FxPropKind.number, group: 'Anchors'),
          FxProp('AnchorPane.rightAnchor', 'rightAnchor', FxPropKind.number, group: 'Anchors'),
        ];
      case 'VBox':
        return const <FxProp>[
          FxProp('VBox.vgrow', 'vgrow', FxPropKind.enumeration,
              values: ['NEVER', 'ALWAYS', 'SOMETIMES'], group: 'Constraints'),
          FxProp('VBox.margin', 'margin (Insets)', FxPropKind.insets, group: 'Constraints'),
        ];
      case 'HBox':
        return const <FxProp>[
          FxProp('HBox.hgrow', 'hgrow', FxPropKind.enumeration,
              values: ['NEVER', 'ALWAYS', 'SOMETIMES'], group: 'Constraints'),
          FxProp('HBox.margin', 'margin (Insets)', FxPropKind.insets, group: 'Constraints'),
        ];
      case 'GridPane':
        return const <FxProp>[
          FxProp('GridPane.rowIndex', 'rowIndex', FxPropKind.number, group: 'Grid'),
          FxProp('GridPane.columnIndex', 'columnIndex', FxPropKind.number, group: 'Grid'),
          FxProp('GridPane.rowSpan', 'rowSpan', FxPropKind.number, group: 'Grid'),
          FxProp('GridPane.columnSpan', 'columnSpan', FxPropKind.number, group: 'Grid'),
          FxProp('GridPane.halignment', 'halignment', FxPropKind.enumeration,
              values: ['LEFT', 'CENTER', 'RIGHT'], group: 'Grid'),
          FxProp('GridPane.valignment', 'valignment', FxPropKind.enumeration,
              values: ['TOP', 'CENTER', 'BOTTOM', 'BASELINE'], group: 'Grid'),
        ];
      case 'StackPane':
        return const <FxProp>[
          FxProp('StackPane.alignment', 'alignment', FxPropKind.enumeration,
              values: _posValues, group: 'Constraints'),
        ];
      case 'FlowPane':
        return const <FxProp>[
          FxProp('FlowPane.margin', 'margin (Insets)', FxPropKind.insets, group: 'Constraints'),
        ];
      case 'TilePane':
        return const <FxProp>[
          FxProp('TilePane.alignment', 'alignment', FxPropKind.enumeration,
              values: _posValues, group: 'Constraints'),
        ];
      case 'BorderPane':
        return const <FxProp>[
          FxProp('BorderPane.alignment', 'alignment', FxPropKind.enumeration,
              values: _posValues, group: 'Constraints'),
          FxProp('BorderPane.margin', 'margin (Insets)', FxPropKind.insets, group: 'Constraints'),
        ];
      default:
        return const <FxProp>[];
    }
  }

  static List<FxProp> propsFor(String control, {String? parentTag}) {
    final props = <FxProp>[];
    props.addAll(_controlProps[control] ?? const <FxProp>[]);
    props.addAll(constraintsFor(parentTag));
    props.addAll(commonNodeProps);
    return props;
  }

  static FxProp? find(String control, String name, {String? parentTag}) {
    for (final prop in propsFor(control, parentTag: parentTag)) {
      if (prop.name == name) return prop;
    }
    return null;
  }
}
