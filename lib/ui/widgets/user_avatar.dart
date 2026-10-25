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
    final bytes = _decode(dataUrl);

    return Tooltip(
      message: email ?? '',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bytes == null
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: bytes == null
            ? Center(
                child: Text(
                  _initial(),
                  style: TextStyle(
                    fontSize: radius * 0.9,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            : Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => Icon(
                  Icons.person_outline,
                  size: radius,
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