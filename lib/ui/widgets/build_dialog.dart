import 'package:flutter/material.dart';

import '../../build/build_client.dart';
import '../../editor/build_analyzer.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project.dart';
import '../../project/project_history.dart';
import '../../project/project_exporter.dart';

/// Modal window for choosing what the build service should produce, and for
/// running the build afterwards. Returns true when the artifact was saved.
Future<bool?> showBuildDialog(
  BuildContext context, {
  required EditorController controller,
  required Project project,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => BuildDialog(controller: controller, project: project),
  );
}

class BuildDialog extends StatefulWidget {
  const BuildDialog({super.key, required this.controller, required this.project});

  final EditorController controller;
  final Project project;

  @override
  State<BuildDialog> createState() => _BuildDialogState();
}

class _BuildDialogState extends State<BuildDialog> {
  static const List<(bool, String, String, IconData)> _artifacts =
      <(bool, String, String, IconData)>[
    (
      false,
      'JAR',
      'app.jar — needs JavaFX on the classpath',
      Icons.inventory_2_outlined,
    ),
    (
      true,
      'Bundle',
      'JAR + JavaFX runtime + run scripts for Windows, Linux and macOS',
      Icons.folder_zip_outlined,
    ),
  ];

  bool _bundle = true;
  bool _busy = false;
  String? _error;

  /// The notes of the release: what has changed since the last version.
  final TextEditingController _notes = TextEditingController();

  /// The history of the project: the versions and the builds.
  ProjectHistory _history = ProjectHistory();
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await widget.controller.loadHistory(widget.project);
    if (!mounted) return;
    setState(() {
      _history = history;
      _historyLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.build_outlined),
          const SizedBox(width: 10),
          Text(context.tr('Build project')),
        ],
      ),
      content: SizedBox(
        width: 440,
        // The window has to survive a small screen, so the body scrolls.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(context.tr('Artifact'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (bundle, title, subtitle, icon) in _artifacts)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                color: _bundle == bundle
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : null,
                child: ListTile(
                  dense: true,
                  enabled: !_busy,
                  leading: Icon(icon),
                  title: Text(context.tr(title)),
                  subtitle: Text(
                    context.tr(subtitle),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: _bundle == bundle
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => setState(() => _bundle = bundle),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              context.tr('The project is compiled on the build server.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // The build is a release: the state of the project is fixed as a
            // new version.
            Text(context.tr('Release notes'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: context.tr('What has changed in this version?'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            _VersionBanner(
              history: _history,
              revision: widget.project.revision,
              loaded: _historyLoaded,
            ),
            if (_history.builds.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(context.tr('Previous builds'),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final build in _history.builds.take(3))
                _BuildLine(record: build),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                context.tr('Compiling…'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _build,
          icon: const Icon(Icons.build_outlined, size: 18),
          label: Text(context.tr('Build')),
        ),
      ],
    );
  }

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.controller.buildProject(
        widget.project,
        bundle: _bundle,
        options: const ExportOptions(),
        releaseNotes: _notes.text.trim(),
      );
      if (!mounted) return;
      // The build has released a version: the history of the window is
      // refreshed before it closes.
      setState(() => _history = widget.controller.history);
      if (ok) {
        // Run the mini neural network analysis on the just-built project and
        // show the report in a modal dialog.
        final latest = widget.controller.history.builds.isNotEmpty
            ? widget.controller.history.builds.first
            : null;
        if (latest != null) {
          final report = BuildAnalyzer.analyze(widget.project, latest);
          if (!mounted) return;
          await showDialog<bool>(
            context: context,
            builder: (_) => _BuildReportDialog(report: report),
          );
        }
      }
      Navigator.of(context).pop(ok);
    } on BuildException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _history = widget.controller.history;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
        _history = widget.controller.history;
      });
    }
  }
}

/// The version that is about to be released.
class _VersionBanner extends StatelessWidget {
  const _VersionBanner({
    required this.history,
    required this.revision,
    required this.loaded,
  });

  final ProjectHistory history;
  final int revision;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = history.latestVersion;
    final dirty = history.isDirty(revision);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            dirty ? Icons.new_releases_outlined : Icons.history,
            size: 18,
            color: dirty ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              !loaded
                  ? context.tr('Reading the history…')
                  : latest == null
                      ? context.tr('The first version of the project')
                      : dirty
                          ? context.tr(
                              'Version {0} will be released (the last one was {1})',
                            )
                          : context.tr('Version {0} is already released', ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (latest != null && !dirty)
            Text('v${latest.revision}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
        ],
      ),
    );
  }
}

/// One line of the build history.
class _BuildLine extends StatelessWidget {
  const _BuildLine({required this.record});

  final BuildRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Icon(
            record.succeeded ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: record.succeeded ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'v${record.version} · '
              '${record.artifact.isEmpty ? record.status : record.artifact}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            '${(record.durationMs / 1000).toStringAsFixed(1)} s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal dialog showing the mini neural network analysis report of the
/// just-built project.
class _BuildReportDialog extends StatelessWidget {
  const _BuildReportDialog({required this.report});

  final BuildReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOk = report.buildSucceeded;
    final badgeColor = report.isHealthy
        ? Colors.green
        : report.score >= 50
            ? theme.colorScheme.primary
            : theme.colorScheme.error;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    isOk ? Icons.build : Icons.error,
                    color: badgeColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          context.tr('Build analysis'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.tr('Score')}: ${report.score} / 100  ·  ${report.badge}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '${context.tr('Build time')}: '
                    '${(report.buildDurationMs / 1000).toStringAsFixed(1)} s',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (report.issues.isNotEmpty) ...<Widget>[
                    Text(
                      context.tr('Issues found'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final issue in report.issues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.error_outline,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(child: Text(issue)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  if (report.suggestions.isNotEmpty) ...<Widget>[
                    Text(
                      context.tr('Recommendations'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final suggestion in report.suggestions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.lightbulb_outline,
                                size: 14, color: Colors.amber),
                            const SizedBox(width: 6),
                            Expanded(child: Text(suggestion)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  if (report.issues.isEmpty && report.suggestions.isEmpty)
                    Text(
                      context.tr('No issues found. The project looks healthy.'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Close')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
