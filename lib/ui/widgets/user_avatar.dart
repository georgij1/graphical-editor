import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Round user picture with a letter fallback.
///
/// The avatar is stored as a `data:` URL (see `EditorController.avatarDataUrl`),
/// so it works offline and needs no extra request to render.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.dataUrl,
    this.email,
    this.radius = 20,
  });

  /// `data:` URL of the picture, or null when none was uploaded.
  final String? dataUrl;

  /// Used for the letter shown when there is no picture.
  final String? email;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = radius * 2;
    final url = _asUrl(dataUrl);
    final bytes = url == null ? _decode(dataUrl) : null;

    Widget child;
    if (url != null) {
      child = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => _fallback(theme),
      );
    } else if (bytes != null) {
      child = Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => _fallback(theme),
      );
    } else {
      child = _fallback(theme);
    }

    return Tooltip(
      message: email ?? '',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (url == null && bytes == null)
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: Text(
          _initial(),
          style: TextStyle(
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  String _initial() {
    final value = (email ?? '').trim();
    if (value.isEmpty) return '?';
    return value[0].toUpperCase();
  }

  static String? _asUrl(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.startsWith('http://') || v.startsWith('https://') || v.startsWith('/')) {
      return v;
    }
    return null;
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      return bytes.isEmpty ? null : bytes;
    } on FormatException {
      return null;
    }
  }
}