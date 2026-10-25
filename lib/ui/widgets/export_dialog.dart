import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../project/build_files.dart';
import '../../project/project_exporter.dart';

/// Asks which archive format to use, then hands the answer back. Returns null
/// when the user cancels.
Future<ExportOptions?> showExportDialog(BuildContext context) {
  return showDialog<ExportOptions>(
    context: context,
    builder: (_) => const ExportDialog(),
  );
}

/// Modal window for choosing the export format of a project archive.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportArchiveFormat _format = ExportArchiveFormat.zip;
  BuildTool _buildTool = BuildTool.maven;
  bool _includeJavaSources = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.archive_outlined),
          const SizedBox(width: 10),
          Text(context.tr('Export project')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(context.tr('Archive format'),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _FormatTile(
                icon: Icons.folder_zip_outlined,
                title: 'ZIP',
                subtitle: '.zip',
                selected: _format == ExportArchiveFormat.zip,
                onTap: () =>
                    setState(() => _format = ExportArchiveFormat.zip),
              ),
              _FormatTile(
                icon: Icons.compress_outlined,
                title: 'TAR + GZIP',
                subtitle: '.tar.gz',
                selected: _format == ExportArchiveFormat.tarGz,
                onTap: () =>
                    setState(() => _format = ExportArchiveFormat.tarGz),
              ),
              const SizedBox(height: 16),
              Text(context.tr('Build tool'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                context.tr('Build files added to the archive root.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _FormatTile(
                icon: Icons.account_tree_outlined,
                title: 'Maven',
                subtitle: 'pom.xml',
                selected: _buildTool == BuildTool.maven,
                onTap: () => setState(() => _buildTool = BuildTool.maven),
              ),
              _FormatTile(
                icon: Icons.settings_suggest_outlined,
                title: 'Gradle',
                subtitle: 'build.gradle, settings.gradle',
                selected: _buildTool == BuildTool.gradle,
                onTap: () => setState(() => _buildTool = BuildTool.gradle),
              ),
              _FormatTile(
                icon: Icons.block_outlined,
                title: context.tr('None'),
                subtitle: context.tr('Only sources and scenes'),
                selected: _buildTool == BuildTool.none,
                onTap: () => setState(() => _buildTool = BuildTool.none),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _includeJavaSources,
                onChanged: (value) =>
                    setState(() => _includeJavaSources = value ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(context.tr('Include Java sources')),
                subtitle: Text(
                  context.tr('Add the generated Java files to the archive.'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            ExportOptions(
              format: _format,
              includeJavaSources: _includeJavaSources,
              buildTool: _buildTool,
            ),
          ),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(context.tr('Export')),
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: selected
            ? Icon(Icons.check, color: theme.colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}