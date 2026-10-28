import 'package:flutter/material.dart';

import '../../editor/build_analyzer.dart';
import '../../l10n/app_localizations.dart';

/// What the user chose in the report dialog.
enum ReportDialogAction {
  /// Dismissed without doing anything (Close / Cancel).
  close,

  /// Continue with the build/export.
  proceed,

  /// Repair the scene controllers first, then continue.
  fix,
}

/// Which flow opened the report: a server build or a pre-export check.
enum ReportDialogMode {
  /// After a build: shows the build time and a single Close button.
  build,

  /// Before an export: offers Export / Export anyway and, when the scene
  /// controllers can be repaired, a Fix controllers button.
  export,
}

/// Shows the mini neural network analysis report of the project.
///
/// In [ReportDialogMode.build] the dialog is informational (returns
/// [ReportDialogAction.close]). In [ReportDialogMode.export] the caller uses
/// the returned action to decide whether to export, fix the controllers first
/// or cancel.
Future<ReportDialogAction> showBuildReportDialog(
  BuildContext context, {
  required BuildReport report,
  ReportDialogMode mode = ReportDialogMode.build,
}) async {
  final action = await showDialog<ReportDialogAction>(
    context: context,
    builder: (_) => BuildReportDialog(report: report, mode: mode),
  );
  return action ?? ReportDialogAction.close;
}

/// Modal dialog showing the mini neural network analysis report.
class BuildReportDialog extends StatelessWidget {
  const BuildReportDialog({
    super.key,
    required this.report,
    this.mode = ReportDialogMode.build,
  });

  final BuildReport report;

  final ReportDialogMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExport = mode == ReportDialogMode.export;
    final isOk = report.buildSucceeded;
    final badgeColor = report.isHealthy
        ? Colors.green
        : report.score >= 50
            ? theme.colorScheme.primary
            : theme.colorScheme.error;

    final title = isExport
        ? context.tr('Export check')
        : context.tr('Build analysis');
    final headerIcon = isExport
        ? Icons.fact_check_outlined
        : (isOk ? Icons.build : Icons.error);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
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
                  Icon(headerIcon, color: badgeColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
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
                  if (!isExport)
                    Text(
                      '${context.tr('Build time')}: '
                      '${(report.buildDurationMs / 1000).toStringAsFixed(1)} s',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (report.issues.isNotEmpty) ...<Widget>[
                    if (!isExport) const SizedBox(height: 12),
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
                            Expanded(child: Text(issue.render(context.tr))),
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
                            Expanded(child: Text(suggestion.render(context.tr))),
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
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (isExport) ...<Widget>[
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ReportDialogAction.close),
                      child: Text(context.tr('Cancel')),
                    ),
                    if (report.hasControllerIssues) ...<Widget>[
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            Navigator.of(context).pop(ReportDialogAction.fix),
                        icon: const Icon(Icons.build_outlined, size: 18),
                        label: Text(context.tr('Fix controllers')),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ReportDialogAction.proceed),
                      child: Text(report.issues.isNotEmpty
                          ? context.tr('Export anyway')
                          : context.tr('Export')),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ReportDialogAction.close),
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
