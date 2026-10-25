import 'dart:convert';

import '../model/fxml_node.dart';

/// Builds a standalone HTML page out of an FXML document.
///
/// A real JavaFX runtime cannot execute inside a browser: it needs the native
/// Prism/Glass libraries, which no JVM-to-WebAssembly port ships. The scene is
/// therefore translated into DOM. Layout, sizes, colours and the JavaFX `style`
/// attribute carry over, and interactive controls report the handler that the
/// Java controller would be asked to run - which is what makes the preview
/// useful while designing a scene.
String buildPreviewHtml(
  FxmlDocument document, {
  String title = 'Preview',
  double width = 800,
  double height = 600,
}) {
  final _PreviewBuilder builder = _PreviewBuilder(width: width, height: height);
  return builder.page(title, builder.build(document.root));
}

class _PreviewBuilder {
  _PreviewBuilder({required this.width, required this.height});

  final double width;
  final double height;

  static const List<String> _containerTags = <String>[
    'AnchorPane',
    'VBox',
    'HBox',
    'StackPane',
    'GridPane',
    'BorderPane',
    'FlowPane',
    'TilePane',
    'ScrollPane',
  ];

  static const List<String> _collectionTags = <String>[
    'items',
    'columns',
  ];

  String build(FxmlNode root) => _control(root);

  String page(String title, String body) => '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: system-ui, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
    font-size: 13px;
    background: #e8e8ec;
    display: flex;
    flex-direction: column;
    height: 100vh;
  }
  #stage {
    flex: 1;
    overflow: auto;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 16px;
  }
  #scene {
    background: #ffffff;
    position: relative;
    overflow: hidden;
    box-shadow: 0 2px 10px rgba(0,0,0,.25);
  }
  #log {
    height: 108px;
    overflow: auto;
    background: #1f2430;
    color: #c8d3e0;
    font: 12px/1.5 ui-monospace, "Cascadia Mono", Consolas, monospace;
    padding: 6px 10px;
    border-top: 1px solid #2f3646;
  }
  #log div { white-space: pre-wrap; }
  #log .handler { color: #7fd6a2; }
  button, input, select, textarea { font: inherit; }
  .java-label { white-space: pre-wrap; display: inline-block; }
  .java-image {
    border: 1px dashed #9aa4b2;
    color: #6b7280;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    min-height: 24px;
  }
  .java-separator { height: 0; border-top: 1px solid #b9c0cc; margin: 6px 0; }
  .java-spin {
    width: 26px; height: 26px;
    border: 3px solid #c8ced8;
    border-top-color: #039ec8;
    border-radius: 50%;
    animation: fx-spin 1s linear infinite;
  }
  @keyframes fx-spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>
  <div id="stage"><div id="scene" style="width:${_px(width)};height:${_px(height)}">$body</div></div>
  <div id="log"></div>
<script>
(function () {
  var log = document.getElementById('log');
  function write(message, handler) {
    var line = document.createElement('div');
    line.appendChild(document.createTextNode(message));
    if (handler) {
      var tag = document.createElement('span');
      tag.className = 'handler';
      tag.textContent = handler;
      line.appendChild(tag);
    }
    log.insertBefore(line, log.firstChild);
  }
  function describe(node) {
    var id = node.getAttribute('data-fx-id');
    return node.tagName.toLowerCase() + (id ? '#' + id : '');
  }
  function report(node) {
    var handler = node.getAttribute('data-handler');
    if (!handler) return;
    write(describe(node) + '  onAction -> ', handler);
  }
  document.addEventListener('click', function (event) {
    var node = event.target.closest('[data-handler]');
    if (!node || node.tagName === 'INPUT' || node.tagName === 'SELECT'
        || node.tagName === 'TEXTAREA') {
      return;
    }
    report(node);
    if (node.tagName === 'BUTTON' && node.getAttribute('data-toggle') === 'true') {
      node.setAttribute('aria-pressed',
          node.getAttribute('aria-pressed') === 'true' ? 'false' : 'true');
    }
  });
  document.addEventListener('change', function (event) {
    report(event.target.closest('[data-handler]'));
  });
  write('Preview ready - click a control to see which handler would run.');
})();
</script>
</body>
</html>''';

  // --------------------------------------------------------------- containers

  String _container(FxmlNode node) => switch (node.tag) {
        'VBox' => _flex(node, column: true),
        'HBox' => _flex(node, column: false),
        'GridPane' => _grid(node),
        'BorderPane' => _border(node),
        'FlowPane' || 'TilePane' => _flow(node),
        'ScrollPane' => _scroll(node),
        _ => _stack(node),
      };

  String _shell(FxmlNode node, String extraStyle, String inner) =>
      '<div class="fx-${node.tag.toLowerCase()}" style="${_box(node)}$extraStyle"'
      '${_idAttr(node)}>$inner</div>';

  String _flex(FxmlNode node, {required bool column}) {
    final style = StringBuffer(
      'display:flex;flex-direction:${column ? 'column' : 'row'};',
    );
    final spacing = _number(node, 'spacing');
    if (spacing != null) style.write('gap:${_px(spacing)};');
    final alignment = _string(node, 'alignment');
    if (alignment != null) {
      style.write('align-items:${_cssAlignment(alignment, cross: true)};');
      style.write('justify-content:${_cssAlignment(alignment, cross: false)};');
    }
    return _shell(node, style.toString(), _children(node));
  }

  /// StackPane: children overlap. Anchored children stay absolutely placed.
  String _stack(FxmlNode node) {
    final children = _visibleChildren(node);
    final positioned =
        children.where((child) => _anchors(child).isNotEmpty).toList();
    final flowing =
        children.where((child) => !positioned.contains(child)).toList();

    final buffer = StringBuffer('<div style="position:relative;flex:1;'
        'min-width:0;min-height:0;">');
    for (final child in flowing) {
      buffer.write('<div style="position:absolute;inset:0;'
          'display:flex;">${_control(child)}</div>');
    }
    for (final child in positioned) {
      buffer.write(_control(child));
    }
    buffer.write('</div>');
    return _shell(node, 'position:relative;', buffer.toString());
  }

  String _grid(FxmlNode node) {
    final children = _visibleChildren(node);
    var columns = 0;
    var rows = 0;
    for (final child in children) {
      final column = (_number(child, 'GridPane.columnIndex') ?? 0).round();
      final row = (_number(child, 'GridPane.rowIndex') ?? 0).round();
      final spanColumns =
          (_number(child, 'GridPane.columnSpan') ?? 1).round().clamp(1, 64);
      final spanRows = (_number(child, 'GridPane.rowSpan') ?? 1).round().clamp(1, 64);
      if (column + spanColumns > columns) columns = column + spanColumns;
      if (row + spanRows > rows) rows = row + spanRows;
    }
    if (columns == 0) columns = 1;
    if (rows == 0) rows = 1;

    final hGap = _number(node, 'hgap') ?? 0;
    final vGap = _number(node, 'vgap') ?? 0;
    final style = StringBuffer('display:grid;');
    style.write('grid-template-columns:repeat($columns, minmax(0, 1fr));');
    style.write('grid-template-rows:repeat($rows, minmax(0, auto));');
    if (hGap > 0 || vGap > 0) {
      style.write('column-gap:${_px(hGap)};row-gap:${_px(vGap)};');
    }

    final cells = <String>[];
    for (final child in children) {
      final column = (_number(child, 'GridPane.columnIndex') ?? 0).round() + 1;
      final row = (_number(child, 'GridPane.rowIndex') ?? 0).round() + 1;
      final spanColumns =
          (_number(child, 'GridPane.columnSpan') ?? 1).round().clamp(1, 64);
      final spanRows = (_number(child, 'GridPane.rowSpan') ?? 1).round().clamp(1, 64);
      final placement = 'grid-column:$column / span $spanColumns;'
          'grid-row:$row / span $spanRows;';
      final alignment = _gridAlignment(child);
      cells.add('<div style="$placement$alignment">${_control(child)}</div>');
    }
    return _shell(node, style.toString(), cells.join());
  }

  String _border(FxmlNode node) {
    final children = _visibleChildren(node);
    // JavaFX shows the first child in the center; the rest fill the sides in
    // the documented order.
    const areas = <String>['center', 'left', 'right', 'top', 'bottom'];
    final slots = <String, String>{};
    if (children.isNotEmpty) slots['center'] = _control(children.first);
    for (var i = 1; i < children.length && i < areas.length; i++) {
      slots[areas[i]] = _control(children[i]);
    }
    const gridAreas = <String>['top', 'left', 'center', 'right', 'bottom'];
    final cells = <String>[];
    for (final area in gridAreas) {
      final content = slots[area] ?? '';
      cells.add('<div style="grid-area:${_gridArea(area)};overflow:auto;'
          'min-width:0;min-height:0;">$content</div>');
    }
    return _shell(
      node,
      'display:grid;grid-template-columns:auto 1fr auto;'
          'grid-template-rows:auto 1fr auto;',
      cells.join(),
    );
  }

  String _flow(FxmlNode node) {
    final gap = _number(node, 'hgap') ?? 0;
    final gapY = _number(node, 'vgap') ?? gap;
    final style = StringBuffer(
      'display:flex;flex-wrap:wrap;align-content:flex-start;',
    );
    if (gap > 0 || gapY > 0) {
      style.write('column-gap:${_px(gap)};row-gap:${_px(gapY)};');
    }
    return _shell(node, style.toString(), _children(node));
  }

  String _scroll(FxmlNode node) =>
      _shell(node, 'overflow:auto;', _children(node));

  String _children(FxmlNode node) {
    final buffer = StringBuffer();
    for (final child in _visibleChildren(node)) {
      buffer.write(_control(child));
    }
    return buffer.toString();
  }

  // ----------------------------------------------------------------- controls

  String _control(FxmlNode node) {
    if (_containerTags.contains(node.tag)) return _container(node);
    return switch (node.tag) {
      'Label' || 'Text' || 'String' => _label(node),
      'Button' => _button(node, toggle: false),
      'ToggleButton' => _button(node, toggle: true),
      'CheckBox' => _checkBox(node),
      'RadioButton' => _radio(node),
      'TextField' => _textField(node),
      'PasswordField' => _textField(node, password: true),
      'TextArea' => _textArea(node),
      'ComboBox' => _comboBox(node),
      'ListView' => _listView(node),
      'TableView' => _table(node),
      'ProgressBar' => _progressBar(node),
      'ProgressIndicator' => '<div class="java-spin"></div>',
      'Slider' => _slider(node),
      'ImageView' => _image(node, 'ImageView'),
      'Canvas' => _image(node, 'Canvas'),
      'Separator' => '<div class="java-separator"></div>',
      'ScrollBar' => '<div style="width:12px;background:#dfe3ea"></div>',
      'ColorPicker' => '<input type="color" value="#039ec8">',
      'DatePicker' => '<input type="date">',
      _ => '<div style="border:1px dashed #9aa4b2;padding:4px 6px;color:#6b7280;'
          'font-size:11px;${_box(node)}">'
          '${_escape(node.tag)}</div>',
    };
  }

  String _label(FxmlNode node) {
    final text = _string(node, 'text') ?? _value(node) ?? node.fxId ?? '';
    final wrap = _boolean(node, 'wrapText') ?? false;
    final style = StringBuffer(_box(node))
      ..write(wrap ? 'white-space:pre-wrap;' : 'white-space:pre;')
      ..write(_foreground(node))
      ..write(_font(node))
      ..write(_inlineStyle(node));
    return '<span class="java-label" style="$style"${_idAttr(node)}>'
        '${_escape(text)}</span>';
  }

  String _button(FxmlNode node, {required bool toggle}) {
    final text = _string(node, 'text') ?? '';
    final selected = _boolean(node, 'selected') ?? false;
    final disabled = _boolean(node, 'disable') ?? false;
    final style = StringBuffer(
      'padding:4px 12px;border:1px solid #9aa4b2;border-radius:4px;'
      'background:#f4f5f7;cursor:pointer;',
    )
      ..write(_box(node))
      ..write(_foreground(node))
      ..write(_font(node));
    if (disabled) style.write('opacity:.5;cursor:default;');
    style.write(_inlineStyle(node));
    final toggleAttrs = toggle
        ? ' data-toggle="true" aria-pressed="${selected ? 'true' : 'false'}"'
        : '';
    return '<button style="$style"${_idAttr(node)}${_handler(node)}'
        '$toggleAttrs${disabled ? ' disabled' : ''}>${_escape(text)}</button>';
  }

  String _checkBox(FxmlNode node) {
    final text = _string(node, 'text') ?? '';
    final selected = _boolean(node, 'selected') ?? false;
    final disabled = _boolean(node, 'disable') ?? false;
    return '<label style="display:flex;gap:6px;align-items:center;'
        '${_box(node)}${_visibility(node)}"'
        '${_idAttr(node)}${_handler(node)}>'
        '<input type="checkbox"${selected ? ' checked' : ''}'
        '${disabled ? ' disabled' : ''}>'
        '<span>${_escape(text)}</span></label>';
  }

  String _radio(FxmlNode node) {
    final text = _string(node, 'text') ?? '';
    final selected = _boolean(node, 'selected') ?? false;
    final group = node.fxId ?? text;
    return '<label style="display:flex;gap:6px;align-items:center;'
        '${_box(node)}${_visibility(node)}"'
        '${_idAttr(node)}${_handler(node)}>'
        '<input type="radio" name="grp-${_escape(group)}"'
        '${selected ? ' checked' : ''}>'
        '<span>${_escape(text)}</span></label>';
  }

  String _textField(FxmlNode node, {bool password = false}) {
    final prompt = _string(node, 'promptText') ?? '';
    final disabled = _boolean(node, 'disable') ?? false;
    return '<input type="${password ? 'password' : 'text'}" '
        'placeholder="${_escape(prompt)}" '
        'style="border:1px solid #9aa4b2;border-radius:3px;padding:3px 6px;'
        'background:#fff;${_box(node)}${_visibility(node)}"'
        '${_idAttr(node)}${_handler(node)}${disabled ? ' disabled' : ''}>';
  }

  String _textArea(FxmlNode node) {
    final prompt = _string(node, 'promptText') ?? '';
    return '<textarea placeholder="${_escape(prompt)}" '
        'style="border:1px solid #9aa4b2;border-radius:3px;padding:4px 6px;'
        'background:#fff;resize:both;${_box(node)}'
        '${_visibility(node)}"></textarea>${_handler(node)}';
  }

  String _comboBox(FxmlNode node) {
    final options = _items(node).map((item) => '<option>${_escape(item)}</option>').join();
    return '<select style="border:1px solid #9aa4b2;border-radius:3px;'
        'padding:3px 6px;background:#fff;${_box(node)}'
        '${_visibility(node)}"${_idAttr(node)}${_handler(node)}>$options</select>';
  }

  String _listView(FxmlNode node) {
    final items = _items(node);
    final rows = items
        .map((item) => '<div style="padding:2px 6px">${_escape(item)}</div>')
        .join();
    return '<div style="border:1px solid #c8ced8;border-radius:3px;'
        'background:#fff;overflow:auto;min-height:44px;'
        '${_box(node)}${_visibility(node)}"${_idAttr(node)}>$rows</div>';
  }

  String _table(FxmlNode node) {
    final header = _columns(node)
        .map((column) =>
            '<div style="padding:3px 6px;font-weight:600">${_escape(column)}</div>')
        .join();
    return '<div style="border:1px solid #c8ced8;border-radius:3px;'
        'background:#fff;overflow:auto;${_box(node)}"${_idAttr(node)}>'
        '<div style="display:flex;background:#eef0f4;'
        'border-bottom:1px solid #c8ced8">$header</div></div>';
  }

  String _progressBar(FxmlNode node) {
    final progress = (_number(node, 'progress') ?? 0).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    return '<div style="height:16px;background:#e2e6ec;border-radius:3px;'
        'overflow:hidden;${_box(node)}"><div style="height:100%;width:$percent%;'
        'background:#039ec8"></div></div>';
  }

  String _slider(FxmlNode node) {
    final min = _number(node, 'min') ?? 0;
    final max = _number(node, 'max') ?? 100;
    final value = (_number(node, 'value') ?? min).clamp(min, max);
    return '<input type="range" min="$min" max="$max" value="$value" '
        'style="${_box(node)}"${_idAttr(node)}${_handler(node)}>';
  }

  String _image(FxmlNode node, String hint) => '<div class="java-image" '
      'style="${_box(node)}">${_escape(hint)}</div>';

  // --------------------------------------------------------------- properties

  List<FxmlNode> _visibleChildren(FxmlNode node) {
    final result = <FxmlNode>[];
    for (final child in node.children) {
      if (_collectionTags.contains(child.tag)) {
        result.addAll(child.children);
      } else {
        result.add(child);
      }
    }
    return result;
  }

  List<String> _items(FxmlNode node) => _collectionValues(node, 'items');

  List<String> _columns(FxmlNode node) => _collectionValues(node, 'columns');

  List<String> _collectionValues(FxmlNode node, String tag) {
    final result = <String>[];
    for (final child in node.children) {
      if (child.tag != tag) continue;
      for (final entry in child.children) {
        result.add(_value(entry) ?? _string(entry, 'text') ?? entry.tag);
      }
    }
    return result;
  }

  String? _value(FxmlNode node) =>
      node.attributes['fx:value'] ?? node.properties['value']?.text;

  String? _string(FxmlNode node, String name) {
    final direct = node.attributes[name];
    if (direct != null) return direct;
    final property = node.properties[name];
    if (property == null) return null;
    final value = property.attributes['value'];
    if (value != null) return value;
    final text = property.text?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  double? _number(FxmlNode node, String name) =>
      double.tryParse(_string(node, name)?.trim() ?? '');

  bool? _boolean(FxmlNode node, String name) {
    final value = _string(node, name);
    if (value == null) return null;
    return value.trim().toLowerCase() == 'true';
  }

  /// Sizing, spacing, visibility and the inline JavaFX `style` attribute.
  String _box(FxmlNode node, {bool sizing = true}) {
    final style = StringBuffer();
    if (sizing) {
      final width = _number(node, 'prefWidth');
      final height = _number(node, 'prefHeight');
      if (width != null) style.write('width:${_px(width)};');
      if (height != null) style.write('height:${_px(height)};');
      final minWidth = _number(node, 'minWidth');
      final maxWidth = _number(node, 'maxWidth');
      if (minWidth != null) style.write('min-width:${_px(minWidth)};');
      if (maxWidth != null) style.write('max-width:${_px(maxWidth)};');
      final minHeight = _number(node, 'minHeight');
      final maxHeight = _number(node, 'maxHeight');
      if (minHeight != null) style.write('min-height:${_px(minHeight)};');
      if (maxHeight != null) style.write('max-height:${_px(maxHeight)};');
    }
    final padding = _insets(node, 'padding');
    if (padding.isNotEmpty) style.write('padding:$padding;');
    final spacing = _number(node, 'spacing');
    if (spacing != null) style.write('gap:${_px(spacing)};');
    style.write(_visibility(node));
    style.write(_background(node));
    final margin = _insets(node, 'margin');
    if (margin.isNotEmpty) style.write('margin:$margin;');
    style.write(_anchors(node));
    style.write(_backgroundRadius(node));
    return style.toString();
  }

  /// Inline `style="..."` is applied last so a designed colour or font wins
  /// over the defaults the preview adds.
  String _inlineStyle(FxmlNode node) {
    final inline = node.attributes['style'];
    if (inline == null || inline.trim().isEmpty) return '';
    return '${_javaFxStyleToCss(inline.trim())};';
  }

  /// Insets, or an empty string when the property is not set. These helpers
  /// never return null: writing null into a [StringBuffer] would emit the
  /// literal text "null" into the CSS.
  String _insets(FxmlNode node, String name) => _insetsOf(_string(node, name));

  String _visibility(FxmlNode node) {
    if (_boolean(node, 'visible') == false) return 'visibility:hidden;';
    final opacity = _number(node, 'opacity');
    if (opacity != null && opacity < 1) return 'opacity:$opacity;';
    return '';
  }

  String _background(FxmlNode node) {
    final color = _color(
      _string(node, 'styleBackground') ?? _string(node, 'background'),
    );
    return color == null ? '' : 'background:$color;';
  }

  String _backgroundRadius(FxmlNode node) {
    final radius = _number(node, 'styleBackgroundRadius') ??
        _number(node, 'backgroundRadius');
    return radius == null ? '' : 'border-radius:${_px(radius)};';
  }

  String _foreground(FxmlNode node) {
    final color = _color(
      _string(node, 'styleTextFill') ?? _string(node, 'textFill'),
    );
    return color == null ? '' : 'color:$color;';
  }

  String _font(FxmlNode node) {
    final size = _number(node, 'styleFontSize') ?? _number(node, 'fontSize');
    final style = StringBuffer();
    if (size != null) style.write('font-size:${_px(size)};');
    final weight = _string(node, 'styleFontWeight') ?? _string(node, 'fontWeight');
    if (weight != null && weight.trim().toUpperCase() == 'BOLD') {
      style.write('font-weight:700;');
    }
    return style.toString();
  }

  /// AnchorPane children are placed with their anchors instead of in flow.
  String _anchors(FxmlNode node) {
    final top = _number(node, 'AnchorPane.topAnchor');
    final bottom = _number(node, 'AnchorPane.bottomAnchor');
    final left = _number(node, 'AnchorPane.leftAnchor');
    final right = _number(node, 'AnchorPane.rightAnchor');
    if (top == null && bottom == null && left == null && right == null) {
      return '';
    }
    final style = StringBuffer('position:absolute;');
    if (top != null) style.write('top:${_px(top)};');
    if (bottom != null) style.write('bottom:${_px(bottom)};');
    if (left != null) style.write('left:${_px(left)};');
    if (right != null) style.write('right:${_px(right)};');
    return style.toString();
  }

  String _gridAlignment(FxmlNode node) {
    final horizontal = _string(node, 'GridPane.halignment') ?? 'LEFT';
    final vertical = _string(node, 'GridPane.valignment') ?? 'TOP';
    return 'justify-self:${_cssAlignment(horizontal, cross: false)};'
        'align-self:${_cssAlignment(vertical, cross: true)};';
  }

  String _idAttr(FxmlNode node) =>
      node.fxId == null ? '' : ' data-fx-id="${_escape(node.fxId!)}"';

  String _handler(FxmlNode node) {
    final handler = _string(node, 'onAction') ??
        _string(node, 'onMouseClicked') ??
        _string(node, 'onChange');
    if (handler == null) return '';
    final cleaned = handler.trim().replaceFirst('#', '').trim();
    if (cleaned.isEmpty) return '';
    return ' data-handler="${_escape(cleaned)}"';
  }
}

String _px(double value) {
  final rounded = value.round();
  return rounded == value ? '${rounded}px' : '${value.toStringAsFixed(2)}px';
}

/// Escapes markup and quotes: values land in both text and attributes.
String _escape(String value) => const HtmlEscape(HtmlEscapeMode.element)
    .convert(value)
    .replaceAll('"', '&quot;');

String _cssAlignment(String value, {required bool cross}) {
  final name = value.trim().toUpperCase();
  if (cross) {
    return switch (name) {
      'TOP' || 'TOP_LEFT' || 'TOP_CENTER' || 'TOP_RIGHT' => 'flex-start',
      'CENTER' || 'CENTER_LEFT' || 'CENTER_RIGHT' => 'center',
      _ => 'flex-end',
    };
  }
  return switch (name) {
    'LEFT' || 'TOP_LEFT' || 'CENTER_LEFT' || 'BOTTOM_LEFT' => 'flex-start',
    'CENTER' || 'TOP_CENTER' || 'CENTER_RIGHT' || 'BOTTOM_CENTER' => 'center',
    _ => 'flex-end',
  };
}

String _gridArea(String area) => switch (area) {
      'top' => '1 / 1 / 2 / 4',
      'left' => '2 / 1 / 3 / 2',
      'center' => '2 / 2 / 3 / 3',
      'right' => '2 / 3 / 3 / 4',
      _ => '3 / 1 / 4 / 4',
    };

/// JavaFX CSS uses `-fx-background-color`; CSS needs `background`.
String _javaFxStyleToCss(String style) {
  final out = <String>[];
  for (final part in style.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final separator = trimmed.indexOf(':');
    if (separator <= 0) continue;
    final property = trimmed.substring(0, separator).trim();
    final value = trimmed.substring(separator + 1).trim();
    if (property == '-fx-background-color') {
      out.add('background:${_color(value) ?? value}');
    } else if (property == '-fx-text-fill') {
      out.add('color:${_color(value) ?? value}');
    } else if (property == '-fx-font-size') {
      out.add('font-size:${_px(double.tryParse(value) ?? 13)}');
    } else if (property.startsWith('-fx-')) {
      out.add('${_cssProperty(property.substring(4))}:$value');
    } else {
      out.add('$property:$value');
    }
  }
  return out.join(';');
}

String _cssProperty(String javaFx) => javaFx.replaceAllMapped(
      RegExp(r'-([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );

const Map<String, String> _colors = <String, String>{
  'WHITE': '#ffffff',
  'BLACK': '#000000',
  'RED': '#ff0000',
  'GREEN': '#008000',
  'BLUE': '#0000ff',
  'YELLOW': '#ffff00',
  'ORANGE': '#ffa500',
  'GRAY': '#808080',
  'GREY': '#808080',
  'LIGHTGRAY': '#d3d3d3',
  'LIGHTGREY': '#d3d3d3',
  'TRANSPARENT': 'transparent',
  'NAVY': '#000080',
  'TEAL': '#008080',
  'PURPLE': '#800080',
  'SILVER': '#c0c0c0',
  'DARKGRAY': '#a9a9a9',
  'DARKGREY': '#a9a9a9',
  'LIGHTBLUE': '#add8e6',
  'DARKBLUE': '#00008b',
  'LIGHTGREEN': '#90ee90',
  'DARKGREEN': '#006400',
  'LIGHTCYAN': '#e0ffff',
  'LIGHTCORAL': '#f08080',
  'LIGHTGREEN_VALUE': '#90ee90',
  'DARKRED': '#8b0000',
  'DARKORANGE': '#ff8c00',
  'DARKYELLOW': '#808000',
  'AQUA': '#00ffff',
  'FUCHSIA': '#ff00ff',
  'BROWN': '#a52a2a',
  'GOLD': '#ffd700',
  'INDIGO': '#4b0082',
  'PINK': '#ffc0cb',
  'CYAN': '#00ffff',
  'MAGENTA': '#ff00ff',
};

/// Understands JavaFX colour names, hex values and rgb()/rgba().
String? _color(String? value) {
  if (value == null) return null;
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final named = _colors[raw.toUpperCase()];
  if (named != null) return named;
  if (raw.startsWith('#')) {
    final digits = raw.substring(1);
    if (digits.length == 6 || digits.length == 8) return raw;
    if (digits.length == 3) {
      return '#${digits.split('').map((digit) => '$digit$digit').join()}';
    }
  }
  final rgb = RegExp(r'rgba?\(([^)]*)\)').firstMatch(raw);
  if (rgb != null) {
    final parts = rgb.group(1)!.split(',').map((p) => p.trim()).toList();
    if (parts.length >= 3) {
      final alpha = parts.length == 4 ? parts[3] : '1';
      return 'rgba(${parts[0]}, ${parts[1]}, ${parts[2]}, $alpha)';
    }
  }
  return null;
}

/// JavaFX prints insets as `top, right, bottom, left`.
String _insetsOf(String? raw) {
  if (raw == null) return '';
  final parts =
      raw.split(',').map((part) => double.tryParse(part.trim()) ?? 0).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return _px(parts.first);
  if (parts.length == 2) return '${_px(parts[0])} ${_px(parts[1])}';
  if (parts.length == 3) {
    return '${_px(parts[0])} ${_px(parts[1])} ${_px(parts[2])} ${_px(parts[1])}';
  }
  return '${_px(parts[0])} ${_px(parts[1])} ${_px(parts[2])} ${_px(parts[3])}';
}