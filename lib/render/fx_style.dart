import 'package:flutter/material.dart';

import '../model/fxml_node.dart';

/// Border/padding values expressed in the JavaFX `-fx-` convention.
@immutable
class FxInsets {
  const FxInsets(this.top, this.right, this.bottom, this.left);

  final double top;
  final double right;
  final double bottom;
  final double left;

  static const FxInsets zero = FxInsets(0, 0, 0, 0);

  EdgeInsets toEdgeInsets() =>
      EdgeInsets.only(top: top, right: right, bottom: bottom, left: left);

  @override
  bool operator ==(Object other) =>
      other is FxInsets &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// Font description parsed from `-fx-font-*` or a `<font>` property element.
@immutable
class FxFont {
  const FxFont({
    this.size,
    this.family,
    this.weight,
    this.color,
    this.italic = false,
  });

  final double? size;
  final String? family;
  final FontWeight? weight;
  final Color? color;
  final bool italic;

  TextStyle toTextStyle({TextStyle? base}) {
    final resolved = base ?? const TextStyle();
    return resolved.copyWith(
      fontSize: size,
      fontFamily: family,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : null,
      color: color,
    );
  }
}

/// Aggregated, resolved style of a JavaFX node.
@immutable
class FxStyle {
  const FxStyle({
    this.background,
    this.textFill,
    this.borderColor,
    this.borderWidth = 0,
    this.borderRadius = 0,
    this.padding = FxInsets.zero,
    this.opacity,
    this.alignment,
    this.font = const FxFont(),
  });

  final Color? background;
  final Color? textFill;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final FxInsets padding;
  final double? opacity;
  final Alignment? alignment;
  final FxFont font;

  static const FxStyle empty = FxStyle();

  BoxDecoration toBoxDecoration({Color? fallbackColor}) {
    final hasBorder = borderWidth > 0 && borderColor != null;
    return BoxDecoration(
      color: background ?? fallbackColor,
      border: hasBorder
          ? Border.all(color: borderColor!, width: borderWidth)
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
    );
  }

  FxStyle merge(FxStyle other) {
    return FxStyle(
      background: other.background ?? background,
      textFill: other.textFill ?? textFill,
      borderColor: other.borderColor ?? borderColor,
      borderWidth: other.borderWidth != 0 ? other.borderWidth : borderWidth,
      borderRadius: other.borderRadius != 0 ? other.borderRadius : borderRadius,
      padding: other.padding != FxInsets.zero ? other.padding : padding,
      opacity: other.opacity ?? opacity,
      alignment: other.alignment ?? alignment,
      font: FxFont(
        size: other.font.size ?? font.size,
        family: other.font.family ?? font.family,
        weight: other.font.weight ?? font.weight,
        color: other.font.color ?? font.color,
        italic: other.font.italic || font.italic,
      ),
    );
  }
}

/// Parses JavaFX style strings and node attributes into an [FxStyle].
class FxStyleParser {
  const FxStyleParser();

  FxStyle parse(FxmlNode node) {
    final declarations = <String, String>{};
    final style = node.attributes['style'];
    if (style != null) {
      declarations.addAll(parseDeclarations(style));
    }

    var result = FxStyle.empty;

    Color? directFill;
    final fill = node.attributes['fill'] ?? node.attributes['textFill'];
    if (fill != null) directFill = parseColor(fill);

    result = FxStyle(
      background: parseColor(declarations['-fx-background-color']),
      textFill: directFill ?? parseColor(declarations['-fx-text-fill']),
      borderColor: parseColor(declarations['-fx-border-color']),
      borderWidth: parseBorderWidth(declarations['-fx-border-width']) ?? 0,
      borderRadius: parseDouble(declarations['-fx-border-radius']) ??
          parseDouble(declarations['-fx-background-radius']) ??
          0,
      padding: parseInsets(declarations['-fx-padding']) ??
          _paddingProperty(node) ??
          FxInsets.zero,
      opacity: parseDouble(declarations['-fx-opacity']),
      alignment: parsePos(declarations['-fx-alignment']),
      font: _parseFont(node, declarations),
    );
    return result;
  }

  Map<String, String> parseDeclarations(String style) {
    final declarations = <String, String>{};
    for (final part in style.split(';')) {
      final index = part.indexOf(':');
      if (index <= 0) continue;
      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) declarations[key] = value;
    }
    return declarations;
  }

  FxFont _parseFont(FxmlNode node, Map<String, String> declarations) {
    double? size = parseDouble(declarations['-fx-font-size']);
    String? family = declarations['-fx-font-family'];
    FontWeight? weight = _parseFontWeight(declarations['-fx-font-weight']);
    var italic = false;

    final fontProperty = node.properties['font'];
    if (fontProperty != null && fontProperty.children.isNotEmpty) {
      final font = fontProperty.children.first;
      size ??= parseDouble(font.attributes['size']);
      final name = font.attributes['name'];
      if (name != null) {
        final lower = name.toLowerCase();
        if (lower.contains('bold')) weight ??= FontWeight.bold;
        if (lower.contains('italic') || lower.contains('oblique')) {
          italic = true;
        }
        family ??= _stripStyleSuffix(name);
      }
    }

    return FxFont(
      size: size,
      family: family,
      weight: weight,
      italic: italic,
    );
  }

  String _stripStyleSuffix(String name) {
    return name
        .replaceAll(RegExp(r'\b(bold|italic|oblique|regular|light)\b',
            caseSensitive: false), '')
        .trim();
  }

  FontWeight? _parseFontWeight(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower.contains('bold')) return FontWeight.bold;
    if (lower.contains('black')) return FontWeight.w900;
    if (lower.contains('light')) return FontWeight.w300;
    if (lower.contains('normal')) return FontWeight.normal;
    return null;
  }

  FxInsets? _paddingProperty(FxmlNode node) {
    final padding = node.properties['padding'];
    if (padding == null || padding.children.isEmpty) return null;
    final insets = padding.children.first;
    return FxInsets(
      parseDouble(insets.attributes['top']) ?? 0,
      parseDouble(insets.attributes['right']) ?? 0,
      parseDouble(insets.attributes['bottom']) ?? 0,
      parseDouble(insets.attributes['left']) ?? 0,
    );
  }

  double? parseBorderWidth(String? value) {
    if (value == null) return null;
    final parts = value.split(RegExp(r'\s+'));
    return parseDouble(parts.first);
  }

  FxInsets? parseInsets(String? value) {
    if (value == null) return null;
    final parts = value
        .split(RegExp(r'\s+'))
        .map((e) => parseDouble(e) ?? 0)
        .toList();
    switch (parts.length) {
      case 1:
        return FxInsets(parts[0], parts[0], parts[0], parts[0]);
      case 2:
        return FxInsets(parts[0], parts[1], parts[0], parts[1]);
      case 3:
        return FxInsets(parts[0], parts[1], parts[2], parts[1]);
      default:
        if (parts.length >= 4) {
          return FxInsets(parts[0], parts[1], parts[2], parts[3]);
        }
        return null;
    }
  }

  double? parseDouble(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(RegExp(r'[a-zA-Z%]'), '').trim();
    return double.tryParse(cleaned);
  }

  Alignment? parsePos(String? value) {
    if (value == null) return null;
    switch (value.trim().toUpperCase()) {
      case 'TOP_LEFT':
        return Alignment.topLeft;
      case 'TOP_CENTER':
        return Alignment.topCenter;
      case 'TOP_RIGHT':
        return Alignment.topRight;
      case 'CENTER_LEFT':
      case 'BASELINE_LEFT':
        return Alignment.centerLeft;
      case 'CENTER':
      case 'BASELINE_CENTER':
        return Alignment.center;
      case 'CENTER_RIGHT':
      case 'BASELINE_RIGHT':
        return Alignment.centerRight;
      case 'BOTTOM_LEFT':
        return Alignment.bottomLeft;
      case 'BOTTOM_CENTER':
        return Alignment.bottomCenter;
      case 'BOTTOM_RIGHT':
        return Alignment.bottomRight;
      default:
        return null;
    }
  }

  /// Parses a JavaFX/CSS color literal into a Flutter [Color].
  Color? parseColor(String? value) {
    if (value == null) return null;
    var text = value.trim();
    if (text.isEmpty) return null;

    // Handle gradients by taking the first color as a representative.
    if (text.startsWith('linear-gradient') ||
        text.startsWith('radial-gradient')) {
      final match = RegExp(r'#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)').firstMatch(text);
      if (match != null) text = match.group(0)!;
    }

    if (text.startsWith('#')) return _parseHex(text);
    if (text.startsWith('rgb')) return _parseRgb(text);
    if (text.startsWith('hsl')) return _parseHsl(text);

    final named = _namedColors[text.toLowerCase()];
    if (named != null) return named;
    return null;
  }

  Color? _parseHex(String hex) {
    var value = hex.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 4) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 6) {
      return Color(0xFF000000 | int.parse(value, radix: 16));
    }
    if (value.length == 8) {
      final rgb = value.substring(0, 6);
      final alpha = value.substring(6, 8);
      return Color(int.parse(alpha + rgb, radix: 16));
    }
    return null;
  }

  Color? _parseRgb(String value) {
    final match = RegExp(r'rgba?\(([^)]*)\)').firstMatch(value);
    if (match == null) return null;
    final parts = match
        .group(1)!
        .split(',')
        .map((e) => e.trim())
        .toList();
    if (parts.length < 3) return null;
    final r = _channel(parts[0]);
    final g = _channel(parts[1]);
    final b = _channel(parts[2]);
    final a = parts.length >= 4 ? (_alpha(parts[3])) : 255;
    return Color.fromARGB(a, r, g, b);
  }

  Color? _parseHsl(String value) {
    final match = RegExp(r'hsla?\(([^)]*)\)').firstMatch(value);
    if (match == null) return null;
    final parts = match.group(1)!.split(',').map((e) => e.trim()).toList();
    if (parts.length < 3) return null;
    final h = double.parse(parts[0]);
    final s = double.parse(parts[1].replaceAll('%', '')) / 100;
    final l = double.parse(parts[2].replaceAll('%', '')) / 100;
    final a = parts.length >= 4 ? _alpha(parts[3]) : 255;
    return HSLColor.fromAHSL(a / 255, h, s, l).toColor();
  }

  int _channel(String value) {
    if (value.endsWith('%')) {
      final percent = double.parse(value.replaceAll('%', '').trim());
      return (percent / 100 * 255).round().clamp(0, 255);
    }
    return double.parse(value).round().clamp(0, 255);
  }

  int _alpha(String value) {
    final v = value.trim();
    if (v.endsWith('%')) {
      return (double.parse(v.replaceAll('%', '')) / 100 * 255).round().clamp(0, 255);
    }
    final parsed = double.tryParse(v);
    if (parsed == null) return 255;
    return parsed <= 1 ? (parsed * 255).round().clamp(0, 255) : parsed.round().clamp(0, 255);
  }

  static final Map<String, Color> _namedColors = <String, Color>{
    'transparent': const Color(0x00000000),
    'black': const Color(0xFF000000),
    'white': const Color(0xFFFFFFFF),
    'red': const Color(0xFFFF0000),
    'green': const Color(0xFF008000),
    'lime': const Color(0xFF00FF00),
    'blue': const Color(0xFF0000FF),
    'yellow': const Color(0xFFFFFF00),
    'cyan': const Color(0xFF00FFFF),
    'aqua': const Color(0xFF00FFFF),
    'magenta': const Color(0xFFFF00FF),
    'fuchsia': const Color(0xFFFF00FF),
    'gray': const Color(0xFF808080),
    'grey': const Color(0xFF808080),
    'silver': const Color(0xFFC0C0C0),
    'lightgray': const Color(0xFFD3D3D3),
    'lightgrey': const Color(0xFFD3D3D3),
    'darkgray': const Color(0xFFA9A9A9),
    'darkgrey': const Color(0xFFA9A9A9),
    'orange': const Color(0xFFFFA500),
    'pink': const Color(0xFFFFC0CB),
    'brown': const Color(0xFFA52A2A),
    'purple': const Color(0xFF800080),
    'navy': const Color(0xFF000080),
    'teal': const Color(0xFF008080),
    'olive': const Color(0xFF808000),
    'maroon': const Color(0xFF800000),
    'gold': const Color(0xFFFFD700),
    'coral': const Color(0xFFFF7F50),
    'salmon': const Color(0xFFFA8072),
    'tomato': const Color(0xFFFF6347),
    'skyblue': const Color(0xFF87CEEB),
    'steelblue': const Color(0xFF4682B4),
    'dodgerblue': const Color(0xFF1E90FF),
    'royalblue': const Color(0xFF4169E1),
    'forestgreen': const Color(0xFF228B22),
    'seagreen': const Color(0xFF2E8B57),
    'darkgreen': const Color(0xFF006400),
    'crimson': const Color(0xFFDC143C),
    'indigo': const Color(0xFF4B0082),
    'violet': const Color(0xFFEE82EE),
    'beige': const Color(0xFFF5F5DC),
    'ivory': const Color(0xFFFFFFF0),
    'khaki': const Color(0xFFF0E68C),
    'lavender': const Color(0xFFE6E6FA),
    'plum': const Color(0xFFDDA0DD),
    'orchid': const Color(0xFFDA70D6),
    'tan': const Color(0xFFD2B48C),
    'snow': const Color(0xFFFFFAFA),
  };
}
