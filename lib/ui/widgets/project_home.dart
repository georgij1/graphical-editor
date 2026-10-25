import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project.dart';
import 'project_dialogs.dart';
import 'project_settings_dialog.dart';

/// How many project cards fit on one page of the picker.
///
/// The page is laid out from the space the picker actually got, so the grid
/// never has to scroll: whatever does not fit goes to the next page.
class _PageLayout {
  const _PageLayout({required this.columns, required this.perPage});

  final int columns;
  final int perPage;

  static const double cardWidth = 256;
  static const double cardHeight = 88;
  static const double gap = 12;
  static const double padding = 24;
  static const double maxContentWidth = 880;

  /// Vertical budget for the parts of the picker that are not cards.
  static const double headerHeight = 150;
  static const double footerHeight = 60;
  static const double pagerHeight = 44;

  factory _PageLayout.forBox(BoxConstraints constraints) {
    final contentWidth =
        math.min(constraints.maxWidth, maxContentWidth) - padding * 2;
    final columns = math.max(
      1,
      ((contentWidth + gap) / (cardWidth + gap)).floor(),
    );

    final cardsHeight = constraints.maxHeight -
        padding * 2 -
        headerHeight -
        footerHeight -
        pagerHeight;
    final rows = math.max(1, ((cardsHeight + gap) / (cardHeight + gap)).floor());

    return _PageLayout(columns: columns, perPage: columns * rows);
  }
}

/// Landing surface shown in the center when no project is open.
///
/// Instead of an empty white canvas the user is greeted with a picker that
/// lists existing projects and offers to create or import one. Long lists are
/// paginated to fit the window instead of scrolling.
class ProjectHome extends StatefulWidget {
  const ProjectHome({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ProjectHome> createState() => _ProjectHomeState();
}

class _ProjectHomeState extends State<ProjectHome> {
  /// Updated on every layout pass; drives the slicing and the page counter.
  _PageLayout _layout = const _PageLayout(columns: 1, perPage: 1);
  int _page = 0;

  EditorController get controller => widget.controller;

  /// The projects of the account: the ones it owns and the ones it takes
  /// part in. Projects without an owner are not shown.
  List<Project> get _visibleProjects => controller.myProjects;

  int get _pageCount {
    final total = _visibleProjects.length;
    if (total == 0) return 1;
    return math.max(1, (total / _layout.perPage).ceil());
  }

  /// Keeps the current page valid when projects are added or removed.
  void _clampPage() {
    final clamped = _page.clamp(0, _pageCount - 1);
    if (clamped != _page) setState(() => _page = clamped);
  }

  @override
  void didUpdateWidget(ProjectHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clampPage();
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _pageCount || page == _page) return;
    setState(() => _page = page);
  }

  Future<void> _create(BuildContext context) async {
    final result = await showNewProjectDialog(context);
    if (result == null) return;
    controller.createProject(
      name: result['name'] ?? '',
      package: result['package'] ?? '',
      mainClass: result['mainClass'] ?? '',
      description: result['description'] ?? '',
    );
  }

  Future<void> _import(BuildContext context) async {
    final ok = await controller.importProject();
    if (context.mounted) {
      _message(context, ok ? context.tr('Project imported.') : context.tr('Import failed.'));
    }
  }

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = _visibleProjects;

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The page is sized from the space available, so the grid never has
          // to scroll: the rest of the projects moves to the next page.
          _layout = _PageLayout.forBox(constraints);
          final pageCount = math.max(
            1,
            projects.isEmpty
                ? 1
                : (projects.length / _layout.perPage).ceil(),
          );
          final page = _page.clamp(0, pageCount - 1);
          final start = page * _layout.perPage;
          final end = math.min(start + _layout.perPage, projects.length);
          final visible =
              projects.isEmpty ? const <Project>[] : projects.sublist(start, end);

          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: _PageLayout.maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.all(_PageLayout.padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      height: _PageLayout.headerHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.account_tree_outlined,
                              size: 48, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('Choose a project'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            projects.isEmpty
                                ? context.tr('Create your first JavaFX application to start building scenes and generating Java sources.')
                                : context.tr('Open an existing project or start a new one.'),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (projects.isEmpty)
                      Expanded(
                        child: Center(
                          child: _EmptyState(
                            onCreate: () => _create(context),
                            onImport: () => _import(context),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: _ProjectGrid(
                        projects: visible,
                        perPage: _layout.perPage,
                        columns: _layout.columns,
                        page: page,
                        pageCount: pageCount,
                        total: projects.length,
                        onPage: _goToPage,
                          onOpen: controller.openProject,
                          onSettings: (project) =>
                              showProjectSettingsDialog(
                            context,
                            controller: controller,
                            project: project,
                          ),
                          onCreate: () => _create(context),
                          onImport: () => _import(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({
    required this.projects,
    required this.perPage,
    required this.columns,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
    required this.onOpen,
    required this.onSettings,
    required this.onCreate,
    required this.onImport,
  });

  /// Projects shown on the current page.
  final List<Project> projects;
  final int perPage;
  final int columns;
  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onPage;
  final ValueChanged<Project> onOpen;
  final ValueChanged<Project> onSettings;
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    // The grid, the pager and the action buttons share the space that is left,
    // so nothing is ever clipped or scrolled.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: _PageLayout.gap,
          runSpacing: _PageLayout.gap,
          children: <Widget>[
            for (final project in projects)
              SizedBox(
                width: _PageLayout.cardWidth,
                height: _PageLayout.cardHeight,
                child: _ProjectCard(
                  project: project,
                  onOpen: () => onOpen(project),
                  onSettings: () => onSettings(project),
                ),
              ),
          ],
        ),
        // The pager sits right under the grid; the slack that keeps the row count
        // stable is taken below it, so nothing jumps when pages appear.
        const SizedBox(height: 12),
        SizedBox(
          height: _PageLayout.pagerHeight,
          child: pageCount > 1
              ? Align(
                  alignment: Alignment.topCenter,
                  child: _Pagination(
                    page: page,
                    pageCount: pageCount,
                    total: total,
                    perPage: perPage,
                    onPage: onPage,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.tr('New project')),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(context.tr('Import project')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Page controls shown when the list does not fit on a single screen.
class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.perPage,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final int total;
  final int perPage;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = page * perPage + 1;
    final to = math.min((page + 1) * perPage, total);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: context.tr('Previous page'),
          icon: const Icon(Icons.chevron_left),
          onPressed: page > 0 ? () => onPage(page - 1) : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            '${page + 1} / $pageCount',
            style: theme.textTheme.labelLarge,
          ),
        ),
        IconButton(
          tooltip: context.tr('Next page'),
          icon: const Icon(Icons.chevron_right),
          onPressed: page < pageCount - 1 ? () => onPage(page + 1) : null,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            context.l10n.projectPageRange(from, to, total),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onOpen,
    required this.onSettings,
  });

  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.folder_copy_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // A project that several people work on.
                  if (project.collaborative)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Tooltip(
                        message: context.tr('Shared mode'),
                        child: Icon(Icons.group_outlined,
                            size: 15, color: theme.colorScheme.primary),
                      ),
                    ),
                  // Settings open in a modal window, not a popup list.
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      tooltip: context.tr('Project settings'),
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              Text(
                project.package,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              // The whole card opens the project, so it needs no button here.
              // The owner of the project shares the row with the scene count.
              Row(
                children: <Widget>[
                  Icon(Icons.layers_outlined,
                      size: 12, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      context.l10n.scenes(project.scenes.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.person_outline,
                      size: 12, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      context.l10n.owner(project.ownerEmail),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onImport});

  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.tr('New project')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(context.tr('Import project')),
        ),
      ],
    );
  }
}
