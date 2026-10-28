import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import 'build_report_dialog.dart';

/// Strip above the status bar showing the live validation of the project.
///
/// The report is recomputed on every save (see [EditorController.revalidate]),
/// so the strip appears as soon as a change breaks the build — a controller
/// outside the project package, a missing `<?import?>` and so on. Everything
/// that can be repaired automatically gets a Fix issues button; Details opens
/// the full report.
class ValidationStrip extends StatelessWidget {
  const ValidationStrip({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final report = controller.validation;
    // No project, or nothing to complain about: the strip stays hidden so the
    // editor is not cluttered.
    if (report == null || report.issues.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final critical = report.hasCriticalIssues;
    final color = critical ? theme.colorScheme.error : Colors.amber;
    final issues = report.issues;

    return Material(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => _openReport(context),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                critical ? Icons.error_outline : Icons.warning_amber_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.l10n.issuesFound(issues.length),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 46),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: issues.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: Text(
                            issues[index].render(context.tr),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: color),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (report.hasFixableIssues)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: color,
                  ),
                  onPressed: () => _fix(context),
                  child: Text(context.tr('Fix issues')),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: color,
                ),
                onPressed: () => _openReport(context),
                child: Text(context.tr('Details')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReport(BuildContext context) async {
    final action = await showBuildReportDialog(
      context,
      report: controller.validation!,
      mode: ReportDialogMode.editor,
    );
    if (action == ReportDialogAction.fix) {
      _fix(context);
    }
  }

  void _fix(BuildContext context) {
    controller.fixValidationIssues();
  }
}
