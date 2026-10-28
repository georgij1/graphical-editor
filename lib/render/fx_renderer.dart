import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor/node_geometry.dart';
import '../model/fxml_node.dart';
import 'fx_style.dart';

/// Callbacks and options passed down through the rendering tree.
class FxRenderContext {
  const FxRenderContext({
    this.selected,
    this.onSelect,
    this.onBeginEdit,
    this.onModelChanged,
    this.zoom = 1.0,
    this.showGrid = false,
    this.gridSize = 10,
    this.canvasSize,
    this.tr,
  });

  final FxmlNode? selected;
  final void Function(FxmlNode node)? onSelect;
  final VoidCallback? onBeginEdit;
  final VoidCallback? onModelChanged;
  final double zoom;
  final bool showGrid;
  final double gridSize;
  final Size? canvasSize;
  final String Function(String)? tr;

  FxRenderContext copyWith({FxmlNode? selected, double? zoom, bool? showGrid}) {
    return FxRenderContext(
      selected: selected,
      onSelect: onSelect,
      onBeginEdit: onBeginEdit,
      onModelChanged: onModelChanged,
      zoom: zoom ?? this.zoom,
      showGrid: showGrid ?? this.showGrid,
      gridSize: gridSize,
      canvasSize: canvasSize,
    );
  }
}

/// Builds Flutter widgets that visually represent JavaFX nodes.
class FxRenderer {
  const FxRenderer(this.context);

  final FxRenderContext context;

  static const FxStyleParser _styleParser = FxStyleParser();

  static const Color _fxAccent = Color(0xFF039ED3);
  static const Color _fxControlBg = Color(0xFFE9E9E9);
  static const Color _fxBorder = Color(0xFFB5B5B5);

  Widget build(FxmlNode node) {
    return _NodeInteraction(node: node, context: context, child: _buildNode(node));
  }

  // ------------------------------------------------------------------ dispatch

  Widget _buildNode(FxmlNode node) {
    switch (node.tag) {
      // Containers
      case 'VBox':
        return _buildVBox(node);
      case 'HBox':
        return _buildHBox(node);
      case 'AnchorPane':
        return _buildAnchorPane(node);
      case 'Pane':
      case 'Region':
      case 'Group':
        return _buildAbsolutePane(node);
      case 'StackPane':
        return _buildStackPane(node);
      case 'FlowPane':
      case 'TilePane':
        return _buildFlowPane(node);
      case 'GridPane':
        return _buildGridPane(node);
      case 'BorderPane':
        return _buildBorderPane(node);
      case 'ScrollPane':
        return _buildScrollPane(node);
      case 'ToolBar':
        return _buildToolBar(node);
      case 'TitledPane':
        return _buildTitledPane(node);
      case 'Accordion':
        return _buildAccordion(node);
      case 'TabPane':
        return _buildTabPane(node);
      case 'SplitPane':
        return _buildSplitPane(node);
      case 'TextFlow':
        return _buildFlowPane(node);
      // Controls
      case 'Button':
        return _buildButton(node);
      case 'ToggleButton':
        return _buildButton(node, toggled: true);
      case 'Label':
        return _buildLabel(node);
      case 'TextField':
        return _buildTextField(node);
      case 'PasswordField':
        return _buildTextField(node, password: true);
      case 'TextArea':
        return _buildTextArea(node);
      case 'CheckBox':
        return _buildCheckBox(node);
      case 'RadioButton':
        return _buildRadioButton(node);
      case 'ComboBox':
      case 'ChoiceBox':
      case 'MenuButton':
        return _buildComboBox(node);
      case 'Slider':
        return _buildSlider(node);
      case 'ProgressBar':
        return _buildProgressBar(node);
      case 'ProgressIndicator':
        return _buildProgressIndicator(node);
      case 'Separator':
        return _buildSeparator(node);
      case 'Hyperlink':
        return _buildHyperlink(node);
      case 'ColorPicker':
        return _buildColorPicker(node);
      case 'DatePicker':
        return _buildDatePicker(node);
      case 'Spinner':
        return _buildSpinner(node);
      case 'ImageView':
        return _buildImageView(node);
      case 'ListView':
        return _buildListLike(node, Icons.format_list_bulleted, 'ListView');
      case 'TableView':
        return _buildTableLike(node);
      case 'TreeView':
        return _buildListLike(node, Icons.account_tree, 'TreeView');
      case 'MenuBar':
        return _buildMenuBar(node);
      case 'ContextMenu':
        return _buildContextMenu(node);
      // Shapes
      case 'Rectangle':
        return _buildRectangle(node);
      case 'Circle':
        return _buildCircle(node);
      case 'Ellipse':
        return _buildEllipse(node);
      case 'Line':
        return _buildLine(node);
      case 'Polygon':
        return _buildPolygon(node, close: true);
      case 'Polyline':
        return _buildPolygon(node, close: false);
      case 'Arc':
        return _buildArc(node);
      // Text
      case 'Text':
        return _buildText(node);
      // Charts
      case 'PieChart':
        return _buildPieChart(node);
      case 'BarChart':
        return _buildBarChart(node);
      case 'LineChart':
        return _buildLineChart(node);
      // Misc
      case 'Canvas':
        return _buildCanvas(node);
      case 'WebView':
        return _buildPlaceholder(node, Icons.public, 'WebView');
      default:
        return _buildUnknown(node);
    }
  }

  // ------------------------------------------------------------------- helpers

  double? _num(String? value) {
    if (value == null) return null;
    final parsed = double.tryParse(value);
    return parsed;
  }

  double _number(FxmlNode node, String name, double fallback) =>
      _num(node.attributes[name]) ?? fallback;

  double? _optNumber(FxmlNode node, String name) => _num(node.attributes[name]);

  bool _bool(FxmlNode node, String name, bool fallback) {
    final value = node.attributes[name];
    if (value == null) return fallback;
    return value.toLowerCase() == 'true';
  }

  String _text(FxmlNode node) => node.attributes['text'] ?? node.text ?? '';

  FxStyle _styleOf(FxmlNode node) => _styleParser.parse(node);

  Alignment _alignmentOf(FxmlNode node, {Alignment fallback = Alignment.centerLeft}) {
    final attr = node.attributes['alignment'];
    return _styleParser.parsePos(attr) ?? fallback;
  }

  List<Widget> _children(FxmlNode node) =>
      node.children.map((child) => build(child)).toList();

  Color? _strokeColor(FxmlNode node) =>
      _styleParser.parseColor(node.attributes['stroke']);

  double _strokeWidth(FxmlNode node) =>
      _num(node.attributes['strokeWidth']) ?? 1;

  // ---------------------------------------------------------------- containers

  Widget _buildVBox(FxmlNode node) {
    final style = _styleOf(node);
    final children = <Widget>[];
    final spacing = _number(node, 'spacing', 0);
    final nodeChildren = node.children;
    for (var i = 0; i < nodeChildren.length; i++) {
      final child = nodeChildren[i];
      if (i > 0) children.add(SizedBox(height: spacing));
      final widget = build(child);
      if ((child.attributes['VBox.vgrow'] ?? 'NEVER') == 'ALWAYS') {
        children.add(Expanded(child: widget));
      } else {
        children.add(widget);
      }
    }
    return _region(
      node,
      style,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _toCrossAxis(_alignmentOf(node)),
        children: children,
      ),
    );
  }

  Widget _buildHBox(FxmlNode node) {
    final style = _styleOf(node);
    final children = <Widget>[];
    final spacing = _number(node, 'spacing', 0);
    final nodeChildren = node.children;
    for (var i = 0; i < nodeChildren.length; i++) {
      final child = nodeChildren[i];
      if (i > 0) children.add(SizedBox(width: spacing));
      final widget = build(child);
      if ((child.attributes['HBox.hgrow'] ?? 'NEVER') == 'ALWAYS') {
        children.add(Expanded(child: widget));
      } else {
        children.add(widget);
      }
    }
    return _region(
      node,
      style,
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _toCrossAxis(_alignmentOf(node)),
        children: children,
      ),
    );
  }

  CrossAxisAlignment _toCrossAxis(Alignment alignment) {
    if (alignment.y < -0.2) return CrossAxisAlignment.start;
    if (alignment.y > 0.2) return CrossAxisAlignment.end;
    return CrossAxisAlignment.center;
  }

  Widget _buildAnchorPane(FxmlNode node) {
    final style = _styleOf(node);
    final children = node.children.map(_positionedAnchor).toList();
    return _region(
      node,
      style,
      ClipRect(
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
      fill: true,
    );
  }

  Widget _positionedAnchor(FxmlNode child) {
    final geometry = NodeGeometry(child);
    final position = geometry.position();
    final size = geometry.size();
    final hasWidth = child.attributes.containsKey('prefWidth');
    final hasHeight = child.attributes.containsKey('prefHeight');
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: hasWidth ? size?.width : null,
      height: hasHeight ? size?.height : null,
      child: build(child),
    );
  }

  Widget _buildAbsolutePane(FxmlNode node) {
    final style = _styleOf(node);
    final children = node.children.map((child) {
      final geometry = NodeGeometry(child);
      final position = geometry.position();
      final size = geometry.size();
      return Positioned(
        left: position.dx,
        top: position.dy,
        width: size?.width,
        height: size?.height,
        child: build(child),
      );
    }).toList();
    return _region(
      node,
      style,
      ClipRect(child: Stack(clipBehavior: Clip.none, children: children)),
      fill: true,
    );
  }

  Widget _buildStackPane(FxmlNode node) {
    final style = _styleOf(node);
    final children = node.children.map((child) {
      final alignment = _styleParser
              .parsePos(child.attributes['StackPane.alignment']) ??
          _alignmentOf(node);
      return Align(alignment: alignment, child: build(child));
    }).toList();
    return _region(
      node,
      style,
      Stack(
        alignment: _alignmentOf(node, fallback: Alignment.center),
        children: children,
      ),
      fill: true,
    );
  }

  Widget _buildFlowPane(FxmlNode node) {
    final style = _styleOf(node);
    final hgap = _number(node, 'hgap', 0);
    final vgap = _number(node, 'vgap', 0);
    return _region(
      node,
      style,
      Wrap(
        spacing: hgap,
        runSpacing: vgap,
        alignment: WrapAlignment.start,
        children: _children(node),
      ),
    );
  }

  Widget _buildGridPane(FxmlNode node) {
    final style = _styleOf(node);
    final hgap = _number(node, 'hgap', 0);
    final vgap = _number(node, 'vgap', 0);

    final placements = <_GridPlacement>[];
    var autoColumn = 0;
    var autoRow = 0;
    final columns = math.max(1, (math.sqrt(node.children.length)).ceil());
    for (final child in node.children) {
      final row = _num(child.attributes['GridPane.rowIndex'])?.toInt() ?? autoRow;
      final column =
          _num(child.attributes['GridPane.columnIndex'])?.toInt() ?? autoColumn;
      placements.add(_GridPlacement(row, column, child));
      autoColumn++;
      if (autoColumn >= columns) {
        autoColumn = 0;
        autoRow++;
      }
    }
    final maxRow = placements.fold<int>(0, (m, p) => math.max(m, p.row));
    final maxColumn = placements.fold<int>(0, (m, p) => math.max(m, p.column));
    final rows = maxRow + 1;
    final cols = maxColumn + 1;

    final grid = List.generate(rows, (_) => List<Widget?>.filled(cols, null));
    for (final placement in placements) {
      if (placement.row < rows && placement.column < cols) {
        grid[placement.row][placement.column] = build(placement.node);
      }
    }

    return _region(
      node,
      style,
      Table(
        defaultColumnWidth: const FlexColumnWidth(),
        columnWidths: <int, TableColumnWidth>{
          for (var c = 0; c < cols; c++) c: const FlexColumnWidth(),
        },
        children: <TableRow>[
          for (var r = 0; r < rows; r++)
            TableRow(
              children: <Widget>[
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: c < cols - 1 ? hgap : 0,
                      bottom: r < rows - 1 ? vgap : 0,
                    ),
                    child: grid[r][c] ?? const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBorderPane(FxmlNode node) {
    final style = _styleOf(node);
    Widget? top = _propertyContent(node, 'top');
    Widget? bottom = _propertyContent(node, 'bottom');
    Widget? left = _propertyContent(node, 'left');
    Widget? right = _propertyContent(node, 'right');
    Widget? center = _propertyContent(node, 'center');

    final middle = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ?left,
        Expanded(child: center ?? const SizedBox.shrink()),
        ?right,
      ],
    );

    return _region(
      node,
      style,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ?top,
          Expanded(child: middle),
          ?bottom,
        ],
      ),
    );
  }

  Widget? _propertyContent(FxmlNode node, String property) {
    final propertyNode = node.properties[property];
    if (propertyNode == null) return null;
    if (propertyNode.children.isNotEmpty) {
      return build(propertyNode.children.first);
    }
    return null;
  }

  Widget _buildScrollPane(FxmlNode node) {
    final content = _propertyContent(node, 'content') ??
        (node.children.isNotEmpty ? build(node.children.first) : null);
    return _region(
      node,
      _styleOf(node),
      SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: content ?? const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildToolBar(FxmlNode node) {
    final style = _styleOf(node);
    return Container(
      decoration: style
          .merge(const FxStyle(background: Color(0xFFF2F2F2)))
          .toBoxDecoration(),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _intersperse(_children(node), const SizedBox(width: 6)),
      ),
    );
  }

  List<Widget> _intersperse(List<Widget> items, Widget separator) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) result.add(separator);
      result.add(items[i]);
    }
    return result;
  }

  Widget _buildTitledPane(FxmlNode node) {
    final content = _propertyContent(node, 'content') ??
        (node.children.isNotEmpty ? build(node.children.first) : null);
    return _region(
      node,
      _styleOf(node),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: const Color(0xFFEDEDED),
            child: Text(
              _text(node),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: _fxBorder),
            ),
            child: content ?? const SizedBox(height: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildAccordion(FxmlNode node) {
    return _region(
      node,
      _styleOf(node),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(node),
      ),
    );
  }

  Widget _buildTabPane(FxmlNode node) {
    final style = _styleOf(node);
    final tabs = node.properties['tabs']?.children ?? <FxmlNode>[];
    if (tabs.isEmpty) {
      return _buildPlaceholder(node, Icons.tab, 'TabPane');
    }
    final headers = tabs.map((tab) => _text(tab)).toList();
    return _region(
      node,
      style,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var i = 0; i < headers.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.white : const Color(0xFFEDEDED),
                    border: Border(
                      top: BorderSide(color: _fxBorder),
                      left: BorderSide(color: _fxBorder),
                      right: BorderSide(color: _fxBorder),
                      bottom: BorderSide(
                        color: i == 0 ? Colors.white : _fxBorder,
                      ),
                    ),
                  ),
                  child: Text(headers[i]),
                ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: _fxBorder)),
            child: _tabContent(tabs.first),
          ),
        ],
      ),
    );
  }

  Widget _tabContent(FxmlNode tab) {
    final content = _propertyContent(tab, 'content');
    if (content != null) return content;
    if (tab.children.isNotEmpty) return build(tab.children.first);
    return const SizedBox(height: 40);
  }

  Widget _buildSplitPane(FxmlNode node) {
    final orientation = node.attributes['orientation'] ?? 'HORIZONTAL';
    final children = _children(node);
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        widgets.add(Container(
          width: orientation == 'HORIZONTAL' ? 6 : null,
          height: orientation == 'VERTICAL' ? 6 : null,
          color: const Color(0xFFD0D0D0),
        ));
      }
      widgets.add(Expanded(child: children[i]));
    }
    return _region(
      node,
      _styleOf(node),
      orientation == 'HORIZONTAL'
          ? Row(children: widgets)
          : Column(children: widgets),
    );
  }

  // ------------------------------------------------------------------ controls

  Widget _buildButton(FxmlNode node, {bool toggled = false}) {
    final style = _styleOf(node);
    final fontSize = style.font.size ?? 13;
    final textWidget = Text(
      _text(node),
      style: style.font.toTextStyle(
        base: TextStyle(
          fontSize: fontSize,
          color: style.textFill ?? const Color(0xFF333333),
        ),
      ),
    );
    final base = BoxDecoration(
      color: style.background ?? (toggled ? _fxAccent : _fxControlBg),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: style.borderColor ?? _fxBorder),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: Color(0x22000000), blurRadius: 1, offset: Offset(0, 1)),
      ],
    );
    final textColor = toggled ? Colors.white : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: base,
      child: textColor == null ? textWidget : _recolor(textWidget, textColor),
    );
  }

  Widget _recolor(Widget text, Color color) {
    if (text is Text) {
      return Text(text.data ?? '',
          style: (text.style ?? const TextStyle()).copyWith(color: color));
    }
    return text;
  }

  Widget _buildLabel(FxmlNode node) {
    final style = _styleOf(node);
    return Text(
      _text(node),
      textAlign: _textAlign(node),
      softWrap: _bool(node, 'wrapText', true),
      style: style.font.toTextStyle(
        base: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
      ),
    );
  }

  TextAlign _textAlign(FxmlNode node) {
    switch (node.attributes['textAlignment']) {
      case 'CENTER':
        return TextAlign.center;
      case 'RIGHT':
        return TextAlign.right;
      case 'JUSTIFY':
        return TextAlign.justify;
      default:
        return TextAlign.left;
    }
  }

  Widget _buildTextField(FxmlNode node, {bool password = false}) {
    final style = _styleOf(node);
    final text = _text(node);
    final prompt = node.attributes['promptText'] ?? '';
    final display = password ? '••••••' : (text.isNotEmpty ? text : prompt);
    final isPrompt = text.isEmpty && !password;
    return Container(
      width: _optNumber(node, 'prefWidth') ?? 160,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: style.background ?? Colors.white,
        border: Border.all(color: style.borderColor ?? _fxBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: style.font.size ?? 13,
          color: isPrompt ? const Color(0xFF9E9E9E) : const Color(0xFF333333),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTextArea(FxmlNode node) {
    final style = _styleOf(node);
    final text = _text(node).isEmpty
        ? (node.attributes['promptText'] ?? '')
        : _text(node);
    return Container(
      width: _optNumber(node, 'prefWidth') ?? 200,
      height: _optNumber(node, 'prefHeight') ?? 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: style.background ?? Colors.white,
        border: Border.all(color: style.borderColor ?? _fxBorder),
      ),
      child: Text(text, style: TextStyle(fontSize: style.font.size ?? 13)),
    );
  }

  Widget _buildCheckBox(FxmlNode node) {
    final selected = _bool(node, 'selected', false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _fxBorder),
            borderRadius: BorderRadius.circular(2),
          ),
          child: selected
              ? const Icon(Icons.check, size: 12, color: _fxAccent)
              : null,
        ),
        const SizedBox(width: 6),
        Text(_text(node), style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildRadioButton(FxmlNode node) {
    final selected = _bool(node, 'selected', false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: _fxBorder),
          ),
          child: selected
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _fxAccent,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(_text(node), style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildComboBox(FxmlNode node) {
    final style = _styleOf(node);
    final value = node.attributes['value'] ??
        node.attributes['promptText'] ??
        _text(node);
    final box = Container(
      width: _optNumber(node, 'prefWidth') ?? 160,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: style.borderColor ?? _fxBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
    return box;
  }

  Widget _buildSlider(FxmlNode node) {
    final width = _optNumber(node, 'prefWidth') ?? 180;
    final min = _number(node, 'min', 0);
    final max = _number(node, 'max', 100);
    final value = _number(node, 'value', min).clamp(min, max);
    final fraction = max > min ? (value - min) / (max - min) : 0.0;
    return SizedBox(
      width: width,
      height: 24,
      child: CustomPaint(
        painter: _SliderPainter(fraction),
      ),
    );
  }

  Widget _buildProgressBar(FxmlNode node) {
    final width = _optNumber(node, 'prefWidth') ?? 180;
    final progress = _number(node, 'progress', -1);
    final value = progress < 0 ? null : progress.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: 16,
      child: LinearProgressIndicator(value: value),
    );
  }

  Widget _buildProgressIndicator(FxmlNode node) {
    final progress = _number(node, 'progress', -1);
    final diameter = _optNumber(node, 'prefWidth') ?? 36;
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CircularProgressIndicator(
        value: progress < 0 ? null : progress.clamp(0.0, 1.0),
      ),
    );
  }

  Widget _buildSeparator(FxmlNode node) {
    if ((node.attributes['orientation'] ?? 'HORIZONTAL') == 'VERTICAL') {
      return const SizedBox(
        height: 120,
        child: VerticalDivider(width: 1),
      );
    }
    return SizedBox(
      width: _optNumber(node, 'prefWidth') ?? 200,
      child: const Divider(height: 1, thickness: 1),
    );
  }

  Widget _buildHyperlink(FxmlNode node) {
    return Text(
      _text(node),
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF039ED3),
        decoration: TextDecoration.underline,
      ),
    );
  }

  Widget _buildColorPicker(FxmlNode node) {
    final color = _styleParser.parseColor(node.attributes['value']) ??
        _fxAccent;
    return Container(
      width: 90,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _fxBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 22, height: double.infinity, color: color),
          const SizedBox(width: 6),
          Text('#${color.toARGB32().toRadixString(16).substring(2, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildDatePicker(FxmlNode node) {
    return SizedBox(
      width: _optNumber(node, 'prefWidth') ?? 160,
      // The field is a picture of a date, not an input: the click belongs to
      // the node so it can be selected and moved.
      child: IgnorePointer(
        child: TextField(
          readOnly: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'dd.MM.yyyy',
            suffixIcon: Icon(Icons.calendar_today, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinner(FxmlNode node) {
    return Container(
      width: _optNumber(node, 'prefWidth') ?? 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _fxBorder),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(child: Text('0')),
          const Icon(Icons.unfold_more, size: 16),
        ],
      ),
    );
  }

  Widget _buildImageView(FxmlNode node) {
    final width = _optNumber(node, 'fitWidth') ?? 120;
    final height = _optNumber(node, 'fitHeight') ?? 90;
    final image = node.attributes['image'];
    if (image != null && (image.startsWith('http'))) {
      return Image.network(
        image,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _imagePlaceholder(width, height, image),
      );
    }
    return _imagePlaceholder(width, height, image);
  }

  Widget _imagePlaceholder(double width, double height, String? label) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF0F0F0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.image, color: Color(0xFF9E9E9E)),
          if (label != null)
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildListLike(FxmlNode node, IconData icon, String label) {
    final items = <String>['Item 1', 'Item 2', 'Item 3'];
    return Container(
      width: _optNumber(node, 'prefWidth') ?? 200,
      height: _optNumber(node, 'prefHeight') ?? 150,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _fxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(item, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildTableLike(FxmlNode node) {
    final columns = node.properties['columns']?.children ?? <FxmlNode>[];
    final headers = columns.isEmpty
        ? <String>['Column 1', 'Column 2']
        : columns.map((c) => _text(c)).toList();
    return Container(
      width: _optNumber(node, 'prefWidth') ?? 260,
      height: _optNumber(node, 'prefHeight') ?? 160,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _fxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: const Color(0xFFEDEDED),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                for (final header in headers)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(header,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: <Widget>[
                  for (final _ in headers)
                    const Expanded(child: Text('—')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuBar(FxmlNode node) {
    final children = _children(node);
    return Container(
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final child in children)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildContextMenu(FxmlNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCCCCCC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x22000000), blurRadius: 8),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(node),
      ),
    );
  }

  // -------------------------------------------------------------------- shapes

  Widget _buildRectangle(FxmlNode node) {
    final style = _styleOf(node);
    final width = _optNumber(node, 'width') ?? 120;
    final height = _optNumber(node, 'height') ?? 80;
    final arc = _optNumber(node, 'arcWidth') ?? 0;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: style.background ??
            _styleParser.parseColor(node.attributes['fill']) ??
            _fxAccent,
        border: _strokeColor(node) != null
            ? Border.all(
                color: _strokeColor(node)!, width: _strokeWidth(node))
            : null,
        borderRadius: arc > 0 ? BorderRadius.circular(arc / 2) : null,
      ),
    );
  }

  Widget _buildCircle(FxmlNode node) {
    final radius = _optNumber(node, 'radius') ?? 50;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _styleParser.parseColor(node.attributes['fill']) ?? _fxAccent,
        border: _strokeColor(node) != null
            ? Border.all(color: _strokeColor(node)!, width: _strokeWidth(node))
            : null,
      ),
    );
  }

  Widget _buildEllipse(FxmlNode node) {
    final rx = _optNumber(node, 'radiusX') ?? 60;
    final ry = _optNumber(node, 'radiusY') ?? 40;
    return Container(
      width: rx * 2,
      height: ry * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _styleParser.parseColor(node.attributes['fill']) ?? _fxAccent,
        border: _strokeColor(node) != null
            ? Border.all(color: _strokeColor(node)!, width: _strokeWidth(node))
            : null,
      ),
    );
  }

  Widget _buildLine(FxmlNode node) {
    final startX = _number(node, 'startX', 0);
    final startY = _number(node, 'startY', 0);
    final endX = _number(node, 'endX', 120);
    final endY = _number(node, 'endY', 80);
    final width = (endX - startX).abs();
    final height = (endY - startY).abs();
    return SizedBox(
      width: width == 0 ? 1 : width,
      height: height == 0 ? 1 : height,
      child: CustomPaint(
        painter: _LinePainter(
          Offset(startX, startY),
          Offset(endX, endY),
          _strokeColor(node) ?? const Color(0xFF333333),
          _strokeWidth(node),
        ),
      ),
    );
  }

  Widget _buildPolygon(FxmlNode node, {required bool close}) {
    final points = _parsePoints(node);
    if (points.isEmpty) {
      points.addAll(const <Offset>[
        Offset(0, 60),
        Offset(60, 0),
        Offset(120, 60),
      ]);
    }
    final width = points.map((p) => p.dx).reduce(math.max);
    final height = points.map((p) => p.dy).reduce(math.max);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PolygonPainter(
          points,
          close: close,
          fill: close
              ? (_styleParser.parseColor(node.attributes['fill']) ?? _fxAccent)
              : null,
          stroke: _strokeColor(node) ?? const Color(0xFF333333),
          strokeWidth: _strokeWidth(node),
        ),
      ),
    );
  }

  List<Offset> _parsePoints(FxmlNode node) {
    final pointsNode = node.properties['points'];
    if (pointsNode == null) return <Offset>[];
    final values = <double>[];
    for (final child in pointsNode.children) {
      final value = child.attributes['fx:value'] ??
          child.attributes['value'] ??
          child.text;
      final parsed = value == null ? null : double.tryParse(value);
      if (parsed != null) values.add(parsed);
    }
    final points = <Offset>[];
    for (var i = 0; i + 1 < values.length; i += 2) {
      points.add(Offset(values[i], values[i + 1]));
    }
    return points;
  }

  Widget _buildArc(FxmlNode node) {
    final rx = _optNumber(node, 'radiusX') ?? 60;
    final ry = _optNumber(node, 'radiusY') ?? 60;
    final startAngle = _number(node, 'startAngle', 0);
    final length = _number(node, 'length', 90);
    return SizedBox(
      width: rx * 2,
      height: ry * 2,
      child: CustomPaint(
        painter: _ArcPainter(
          rx,
          ry,
          startAngle,
          length,
          _strokeColor(node) ?? const Color(0xFF333333),
          _styleParser.parseColor(node.attributes['fill']),
          _strokeWidth(node),
        ),
      ),
    );
  }

  Widget _buildText(FxmlNode node) {
    final style = _styleOf(node);
    return Text(
      _text(node),
      style: style.font.toTextStyle(
        base: TextStyle(
          fontSize: 13,
          color: style.textFill ??
              _styleParser.parseColor(node.attributes['fill']) ??
              const Color(0xFF222222),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- charts

  Widget _buildPieChart(FxmlNode node) {
    final size = _optNumber(node, 'prefWidth') ?? 220;
    return SizedBox(
      width: size,
      height: _optNumber(node, 'prefHeight') ?? size,
      child: CustomPaint(painter: _PieChartPainter()),
    );
  }

  Widget _buildBarChart(FxmlNode node) {
    return SizedBox(
      width: _optNumber(node, 'prefWidth') ?? 280,
      height: _optNumber(node, 'prefHeight') ?? 180,
      child: CustomPaint(painter: _BarChartPainter()),
    );
  }

  Widget _buildLineChart(FxmlNode node) {
    return SizedBox(
      width: _optNumber(node, 'prefWidth') ?? 280,
      height: _optNumber(node, 'prefHeight') ?? 180,
      child: CustomPaint(painter: _LineChartPainter()),
    );
  }

  Widget _buildCanvas(FxmlNode node) {
    final width = _optNumber(node, 'width') ?? 200;
    final height = _optNumber(node, 'height') ?? 150;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _fxBorder, style: BorderStyle.solid),
      ),
      child: Center(
        child: Text(context.tr?.call('Canvas') ?? 'Canvas',
            style: TextStyle(color: Color(0xFFBBBBBB))),
      ),
    );
  }

  // ------------------------------------------------------------------- helpers

  Widget _buildPlaceholder(FxmlNode node, IconData icon, String label) {
    final width = _optNumber(node, 'prefWidth') ?? 200;
    final height = _optNumber(node, 'prefHeight') ?? 150;
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF5F5F5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 28, color: const Color(0xFFBBBBBB)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _buildUnknown(FxmlNode node) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFBDBDBD),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(node.tag,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9E9E9E),
                  fontStyle: FontStyle.italic)),
          if (node.children.isNotEmpty) ...[
            const SizedBox(height: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _children(node),
            ),
          ],
        ],
      ),
    );
  }

  Widget _region(FxmlNode node, FxStyle style, Widget child, {bool fill = false}) {
    final isRoot = node.parent == null;
    final width = _optNumber(node, 'prefWidth') ??
        (isRoot && fill ? context.canvasSize?.width : null);
    final height = _optNumber(node, 'prefHeight') ??
        (isRoot && fill ? context.canvasSize?.height : null);
    final hasBackground = style.background != null;
    final hasBorder = style.borderWidth > 0 && style.borderColor != null;

    Widget result = child;
    if (style.padding != FxInsets.zero) {
      result = Padding(padding: style.padding.toEdgeInsets(), child: result);
    }

    if (fill) {
      result = SizedBox(
        width: width,
        height: height,
        child: result,
      );
    } else {
      if (width != null || height != null) {
        result = SizedBox(width: width, height: height, child: result);
      }
    }

    if (!hasBackground && node == context.selected) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x0F039ED3),
          border: Border.all(color: const Color(0x55039ED3), width: 1),
        ),
        child: result,
      );
    } else if (hasBackground || hasBorder) {
      result = Container(decoration: style.toBoxDecoration(), child: result);
    }
    return result;
  }
}

class _GridPlacement {
  _GridPlacement(this.row, this.column, this.node);
  final int row;
  final int column;
  final FxmlNode node;
}

/// Wraps a node with selection and drag/resize behaviour in design mode.
class _NodeInteraction extends StatefulWidget {
  const _NodeInteraction({
    required this.node,
    required this.context,
    required this.child,
  });

  final FxmlNode node;
  final FxRenderContext context;
  final Widget child;

  @override
  State<_NodeInteraction> createState() => _NodeInteractionState();
}

class _NodeInteractionState extends State<_NodeInteraction> {
  bool get _isSelected => identical(widget.context.selected, widget.node);

  NodeGeometry get _geometry => NodeGeometry(widget.node);

  void _select() => widget.context.onSelect?.call(widget.node);

  void _drag(DragUpdateDetails details) {
    final geometry = _geometry;
    if (!geometry.isPositionable) return;
    final delta = details.delta / widget.context.zoom;
    geometry.setPosition(geometry.position() + delta);
    widget.context.onModelChanged?.call();
  }

  void _resize(DragUpdateDetails details, Alignment corner) {
    final geometry = _geometry;
    final delta = details.delta / widget.context.zoom;
    final position = geometry.position();
    var size = geometry.size() ?? const Size(100, 40);

    var newWidth = size.width;
    var newHeight = size.height;
    var dx = position.dx;
    var dy = position.dy;

    if (corner.x < 0) {
      newWidth -= delta.dx;
      dx += delta.dx;
    } else {
      newWidth += delta.dx;
    }
    if (corner.y < 0) {
      newHeight -= delta.dy;
      dy += delta.dy;
    } else {
      newHeight += delta.dy;
    }

    newWidth = math.max(8, newWidth);
    newHeight = math.max(8, newHeight);

    if (geometry.isPositionable) {
      geometry.setPosition(Offset(dx, dy));
    }
    geometry.setSize(Size(newWidth, newHeight));
    widget.context.onModelChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    final positionable = geometry.isPositionable;
    final resizable = geometry.isResizable && _isSelected;

    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _select,
      onPanStart: positionable ? (_) => widget.context.onBeginEdit?.call() : null,
      onPanUpdate: positionable ? _drag : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          widget.child,
          if (_isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF039ED3),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          if (resizable) ..._handles(),
        ],
      ),
    );

    return interactive;
  }

  List<Widget> _handles() {
    const handleSize = 9.0;
    Widget handle(Alignment corner) {
      return Positioned(
        left: corner.x < 0 ? 0 : null,
        right: corner.x > 0 ? 0 : null,
        top: corner.y < 0 ? 0 : null,
        bottom: corner.y > 0 ? 0 : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => widget.context.onBeginEdit?.call(),
          onPanUpdate: (details) => _resize(details, corner),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF039ED3), width: 1),
              ),
            ),
          ),
        ),
      );
    }

    return <Widget>[
      handle(Alignment.topLeft),
      handle(Alignment.topRight),
      handle(Alignment.bottomLeft),
      handle(Alignment.bottomRight),
    ];
  }
}

// ----------------------------------------------------------------- painters

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = Paint()
      ..color = const Color(0xFFB5B5B5)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);
    final filled = Paint()
      ..color = const Color(0xFF039ED3)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(0, y), Offset(size.width * fraction, y), filled);
    final knob = Paint()..color = const Color(0xFFF5F5F5);
    canvas.drawCircle(Offset(size.width * fraction, y), 8, knob);
    canvas.drawCircle(
      Offset(size.width * fraction, y),
      8,
      Paint()
        ..color = const Color(0xFFB5B5B5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.start, this.end, this.color, this.strokeWidth);
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => true;
}

class _PolygonPainter extends CustomPainter {
  _PolygonPainter(this.points,
      {required this.close,
      this.fill,
      required this.stroke,
      required this.strokeWidth});
  final List<Offset> points;
  final bool close;
  final Color? fill;
  final Color stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) path.close();
    if (fill != null && close) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_PolygonPainter oldDelegate) => true;
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.rx, this.ry, this.startAngle, this.length, this.stroke,
      this.fill, this.strokeWidth);
  final double rx;
  final double ry;
  final double startAngle;
  final double length;
  final Color stroke;
  final Color? fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, rx * 2, ry * 2);
    final startRad = startAngle * math.pi / 180;
    final sweepRad = length * math.pi / 180;
    if (fill != null) {
      canvas.drawArc(rect, startRad, sweepRad, true, Paint()..color = fill!);
    }
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => true;
}

class _PieChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final values = <double>[3, 5, 2, 4];
    final total = values.reduce((a, b) => a + b);
    final colors = <Color>[
      const Color(0xFF039ED3),
      const Color(0xFF6FBF73),
      const Color(0xFFFFB74D),
      const Color(0xFFE57373),
    ];
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
          sweep, true, Paint()..color = colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) => false;
}

class _BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(24, size.height - 20),
        Offset(size.width - 8, size.height - 20), axis);
    canvas.drawLine(
        Offset(24, 8), Offset(24, size.height - 20), axis);
    final values = <double>[5, 3, 7, 4, 6];
    final maxValue = values.reduce(math.max);
    final barWidth =
        (size.width - 40) / (values.length * 2);
    final paint = Paint()..color = const Color(0xFF039ED3);
    for (var i = 0; i < values.length; i++) {
      final barsHeight =
          (size.height - 32) * (values[i] / maxValue);
      final left = 32 + i * barWidth * 2;
      canvas.drawRect(
        Rect.fromLTWH(left, size.height - 20 - barsHeight, barWidth, barsHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) => false;
}

class _LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(24, size.height - 20),
        Offset(size.width - 8, size.height - 20), axis);
    canvas.drawLine(Offset(24, 8), Offset(24, size.height - 20), axis);
    final values = <double>[3, 6, 4, 7, 5];
    final maxValue = values.reduce(math.max);
    final stepX = (size.width - 40) / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = 32 + i * stepX;
      final y = size.height - 20 - (size.height - 32) * (values[i] / maxValue);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF039ED3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) => false;
}
