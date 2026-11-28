import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project.dart';

const Map<String, IconData> kProjectIcons = <String, IconData>{
  'folder': Icons.folder_copy_outlined,
  'dashboard': Icons.dashboard_outlined,
  'code': Icons.code,
  'terminal': Icons.terminal,
  'web': Icons.language,
  'phone_android': Icons.phone_android,
  'shopping_cart': Icons.shopping_cart_outlined,
  'analytics': Icons.analytics_outlined,
  'school': Icons.school_outlined,
  'sports_esports': Icons.sports_esports_outlined,
  'palette': Icons.palette_outlined,
  'chat': Icons.chat_bubble_outline,
  'rocket': Icons.rocket_launch_outlined,
  'build': Icons.build_outlined,
  'science': Icons.science_outlined,
  'auto_awesome': Icons.auto_awesome_outlined,
};

IconData projectIconData(String? key) =>
    kProjectIcons[key] ?? Icons.folder_copy_outlined;

bool isCustomProjectIcon(String? key) =>
    key != null && key.startsWith('data:image');

Uint8List? decodeCustomProjectIcon(String? key) {
  if (!isCustomProjectIcon(key)) return null;
  final comma = key!.indexOf(',');
  if (comma < 0 || comma == key.length - 1) return null;
  try {
    return base64Decode(key.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

Widget projectIconWidget(String? key, {double size = 18, Color? color}) {
  final bytes = decodeCustomProjectIcon(key);
  if (bytes != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.folder_copy_outlined, size: size, color: color),
      ),
    );
  }
  return Icon(projectIconData(key), size: size, color: color);
}

Future<void> showProjectIconPickerDialog(
  BuildContext context, {
  required EditorController controller,
  required Project project,
}) async {
  final selected = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final customBytes = decodeCustomProjectIcon(project.icon);
      return AlertDialog(
        title: Text(context.tr('Choose icon')),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final entry in kProjectIcons.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(ctx).pop(entry.key),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: project.icon == entry.key
                                ? theme.colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: project.icon == entry.key
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            size: 22,
                            color: project.icon == entry.key
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  context.tr('Custom icon'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (customBytes != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(ctx).pop(project.icon),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.primary),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Image.memory(customBytes, fit: BoxFit.cover),
                        ),
                      ),
                    Tooltip(
                      message: context.tr('Upload icon'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                            withData: true,
                          );
                          if (result == null || result.files.isEmpty) return;
                          final file = result.files.first;
                          final bytes = file.bytes;
                          if (bytes == null || bytes.isEmpty) return;
                          if (bytes.length > 512 * 1024) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(context.tr('Icon is too large (max 512 KB).')),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                            return;
                          }
                          final ext = (file.extension ?? 'png').toLowerCase();
                          final mime = switch (ext) {
                            'jpg' || 'jpeg' => 'image/jpeg',
                            'gif' => 'image/gif',
                            'webp' => 'image/webp',
                            _ => 'image/png',
                          };
                          final dataUrl =
                              'data:$mime;base64,${base64Encode(bytes)}';
                          if (ctx.mounted) Navigator.of(ctx).pop(dataUrl);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 22,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  context.tr('Icon studio'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final dataUrl = await showIconStudioDialog(ctx);
                    if (dataUrl != null && ctx.mounted) {
                      Navigator.of(ctx).pop(dataUrl);
                    }
                  },
                  icon: const Icon(Icons.brush_outlined, size: 18),
                  label: Text(context.tr('Create icon')),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('Cancel')),
          ),
        ],
      );
    },
  );
  if (selected != null) {
    controller.setProjectIcon(project, selected);
  }
}

Future<String?> showIconStudioDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _IconStudioDialog(),
  );
}

class _IconStudioDialog extends StatefulWidget {
  const _IconStudioDialog();

  @override
  State<_IconStudioDialog> createState() => _IconStudioDialogState();
}

class _IconStudioDialogState extends State<_IconStudioDialog> {
  final GlobalKey _previewKey = GlobalKey();
  String _shape = 'rounded';
  Color _bgColor = const Color(0xFF4F46E5);
  Color _fgColor = Colors.white;
  String _iconKey = 'folder';
  double _iconSize = 56;
  bool _saving = false;

  static const List<Color> _palette = <Color>[
    Color(0xFF4F46E5), Color(0xFF2563EB), Color(0xFF0891B2), Color(0xFF059669),
    Color(0xFF16A34A), Color(0xFFCA8A04), Color(0xFFEA580C), Color(0xFFDC2626),
    Color(0xFFDB2777), Color(0xFF7C3AED), Color(0xFF334155), Color(0xFF111827),
  ];

  static const List<Color> _fgPalette = <Color>[
    Colors.white, Color(0xFFF8FAFC), Color(0xFFFDE68A), Color(0xFFBFDBFE),
    Color(0xFFBBF7D0), Color(0xFFFBCFE8), Color(0xFF111827), Color(0xFF334155),
  ];

  BorderRadius get _radius => switch (_shape) {
        'circle' => BorderRadius.circular(999),
        'square' => BorderRadius.zero,
        _ => BorderRadius.circular(24),
      };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      final bytes = byteData.buffer.asUint8List();
      final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
      Navigator.of(context).pop(dataUrl);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.brush_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(context.tr('Icon studio'),
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 180,
                      child: Column(
                        children: <Widget>[
                          RepaintBoundary(
                            key: _previewKey,
                            child: Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                color: _bgColor,
                                borderRadius: _radius,
                              ),
                              child: Icon(
                                kProjectIcons[_iconKey] ?? Icons.folder_copy_outlined,
                                size: _iconSize,
                                color: _fgColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(context.tr('Preview'),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(context.tr('Shape'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: <Widget>[
                                for (final s in ['rounded', 'circle', 'square'])
                                  ChoiceChip(
                                    label: Text(context.tr(switch (s) {
                                      'circle' => 'Circle',
                                      'square' => 'Square',
                                      _ => 'Rounded',
                                    })),
                                    selected: _shape == s,
                                    onSelected: (_) => setState(() => _shape = s),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(context.tr('Background'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                for (final c in _palette)
                                  GestureDetector(
                                    onTap: () => setState(() => _bgColor = c),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _bgColor == c
                                              ? theme.colorScheme.onSurface
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(context.tr('Symbol'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: <Widget>[
                                for (final entry in kProjectIcons.entries)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() => _iconKey = entry.key),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: _iconKey == entry.key
                                            ? theme.colorScheme.primaryContainer
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _iconKey == entry.key
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Icon(entry.value, size: 20),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(context.tr('Symbol color'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                for (final c in _fgPalette)
                                  GestureDetector(
                                    onTap: () => setState(() => _fgColor = c),
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _fgColor == c
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.outlineVariant,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(context.tr('Symbol size'), style: theme.textTheme.titleSmall),
                            Slider(
                              value: _iconSize,
                              min: 32,
                              max: 88,
                              divisions: 14,
                              label: _iconSize.round().toString(),
                              onChanged: (v) => setState(() => _iconSize = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(context.tr('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(context.tr('Save icon')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
