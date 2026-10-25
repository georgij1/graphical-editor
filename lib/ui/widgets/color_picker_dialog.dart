import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A compact color picker returning a `#RRGGBB` (or `#RRGGBBAA`) string.
Future<String?> showFxColorPicker(
  BuildContext context, {
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _FxColorDialog(initial: initial),
  );
}

class _FxColorDialog extends StatefulWidget {
  const _FxColorDialog({this.initial});
  final String? initial;

  @override
  State<_FxColorDialog> createState() => _FxColorDialogState();
}

class _FxColorDialogState extends State<_FxColorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '#000000');

  static const List<String> _palette = <String>[
    '#000000', '#3f3f3f', '#7f7f7f', '#b5b5b5', '#d9d9d9', '#ffffff',
    '#c62828', '#ef6c00', '#f9a825', '#2e7d32', '#00838f', '#1565c0',
    '#4a148c', '#ad1457', '#6d4c41', '#039ED3', '#6FBF73', '#FFB74D',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _parse(String value) {
    var text = value.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length == 6) {
      return Color(0xFF000000 | int.parse(text, radix: 16));
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Choose color')),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(height: 40, color: _parse(_controller.text)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: context.tr('Hex value'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final color in _palette)
                  InkWell(
                    onTap: () => setState(() => _controller.text = color),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _parse(color),
                        border: Border.all(color: const Color(0xFF999999)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.tr('Apply')),
        ),
      ],
    );
  }
}
