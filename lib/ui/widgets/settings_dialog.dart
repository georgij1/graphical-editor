import 'package:flutter/material.dart';

import '../../build_info.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

/// Opens the application settings dialog.
Future<void> showSettingsDialog(
  BuildContext context, {
  required EditorController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(controller: controller),
  );
}

/// Application settings: appearance and language. The dialog is the natural
/// place for further preferences.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.controller});

  final EditorController controller;

  /// A language is always listed in its own spelling.
  static const List<(String, String)> _languages = <(String, String)>[
    ('en', 'English'),
    ('ru', 'Русский'),
  ];

  static const List<(String, String, IconData)> _themes =
      <(String, String, IconData)>[
    ('system', 'brightness_auto', Icons.brightness_auto),
    ('light', 'Light', Icons.light_mode_outlined),
    ('dark', 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.settings_outlined),
          const SizedBox(width: 10),
          Text(context.tr('Settings')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SectionHeader(
                    title: context.tr('Theme'),
                    subtitle: context.tr('Theme of the editor interface.'),
                  ),
                  for (final (value, label, icon) in _themes)
                    _OptionTile(
                      icon: icon,
                      label: label == 'brightness_auto'
                          ? context.tr('System default')
                          : context.tr(label),
                      selected: controller.themeSetting == value,
                      onTap: () => controller.setTheme(value),
                    ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    title: context.tr('Interface language'),
                    subtitle: context.tr('Language of the editor interface.'),
                  ),
                  for (final (code, label) in _languages)
                    _OptionTile(
                      icon: Icons.translate,
                      label: label,
                      selected: controller.languageCode == code,
                      onTap: () => controller.setLanguage(code),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Build $buildId',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(label),
        trailing: selected
            ? Icon(Icons.check, color: theme.colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}