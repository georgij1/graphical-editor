import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'user_avatar.dart';

import '../../auth/api_client.dart';
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
    final ok = controller.createProject(
      name: result['name'] ?? '',
      package: result['package'] ?? '',
      mainClass: result['mainClass'] ?? '',
      description: result['description'] ?? '',
    );
    if (!ok && context.mounted) {
      _message(
        context,
        controller.collaborationNotice ??
            context.tr('A project with this name already exists.'),
      );
    }
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
                        controller: controller,
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
    required this.controller,
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

  final EditorController controller;
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
                  controller: controller,
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
    required this.controller,
    required this.project,
    required this.onOpen,
    required this.onSettings,
  });

  final EditorController controller;
  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onSettings;

  String? _validatePackage(BuildContext context, String value) {
    final package = value.trim();
    if (package.isEmpty) return context.tr('Package cannot be empty.');
    if (package.startsWith('.') || package.endsWith('.')) {
      return context.tr('Package must not start or end with a dot.');
    }
    if (package.contains('..')) {
      return context.tr('Package must not contain consecutive dots.');
    }
    if (package.contains(' ')) {
      return context.tr('Package must not contain spaces.');
    }
    final segments = package.split('.');
    final reserved = <String>{
      'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
      'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
      'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
      'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
      'package', 'private', 'protected', 'public', 'return', 'short', 'static',
      'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
      'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
    };
    for (final segment in segments) {
      if (segment.isEmpty) return context.tr('Each package segment must not be empty.');
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(segment)) {
        return context.tr('Package segment "{0}" is not a valid identifier.').replaceFirst('{0}', segment);
      }
      if (reserved.contains(segment)) {
        return context.tr('Package segment "{0}" is a reserved Java keyword.').replaceFirst('{0}', segment);
      }
    }
    return null;
  }

  Future<void> _editPackage(BuildContext context) async {
    final textController = TextEditingController(text: project.package);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(ctx.tr('Edit package name')),
              content: SizedBox(
                width: 420,
                child: TextField(
                  controller: textController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: ctx.tr('Java package'),
                    errorText: error,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      error = _validatePackage(ctx, value);
                    });
                  },
                  onSubmitted: (value) {
                    final err = _validatePackage(ctx, value);
                    if (err == null) Navigator.of(ctx).pop(value.trim());
                    setDialogState(() => error = err);
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(ctx.tr('Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final err = _validatePackage(ctx, textController.text);
                    if (err != null) {
                      setDialogState(() => error = err);
                      return;
                    }
                    Navigator.of(ctx).pop(textController.text.trim());
                  },
                  child: Text(ctx.tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
    textController.dispose();
    if (result == null) return;
    if (result == project.package) return;
    controller.setProjectPackage(project, result);
  }

  Future<void> _showTransferDialog(BuildContext context) async {
    final controller = this.controller;
    final project = this.project;
    final isOwner = controller.userEmail?.toLowerCase() ==
            project.ownerEmail?.toLowerCase() ||
        (controller.userId != null &&
            controller.userId!.isNotEmpty &&
            controller.userId == project.ownerId);
    if (!isOwner) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(context.tr('Only the project owner can transfer the project.')),
            behavior: SnackBarBehavior.floating,
          ));
      }
      return;
    }

    await controller.loadAccounts();
    final candidates = <Account>[];
    final seen = <String>{};
    final ownerEmail = project.ownerEmail?.toLowerCase();
    final myEmail = controller.userEmail?.toLowerCase();
    for (final m in project.members) {
      final email = m.email.trim();
      if (email.isEmpty) continue;
      final lower = email.toLowerCase();
      if (lower == ownerEmail || lower == myEmail) continue;
      if (seen.add(lower)) {
        final acc = controller.accounts.cast<Account?>().firstWhere(
              (a) => a!.email.toLowerCase() == lower,
              orElse: () => null,
            );
        candidates.add(acc ?? Account(id: '', email: email));
      }
    }
    for (final a in controller.accounts) {
      final lower = a.email.toLowerCase();
      if (lower == ownerEmail || lower == myEmail) continue;
      if (seen.add(lower)) candidates.add(a);
    }

    if (!context.mounted) return;
    String? selected = candidates.isNotEmpty ? candidates.first.email : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(ctx.tr('Transfer project')),
            content: SizedBox(
              width: 420,
              child: candidates.isEmpty
                  ? Text(ctx.tr('No other users available.'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(ctx.tr('Select the new owner:')),
                        const SizedBox(height: 12),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              children: candidates.map<Widget>((Account a) {
                                return RadioListTile<String>(
                                  value: a.email,
                                  groupValue: selected,
                                  title: Text(a.email),
                                  secondary: UserAvatar(
                                    dataUrl: null,
                                    email: a.email,
                                    radius: 16,
                                  ),
                                  onChanged: (v) => setDialogState(() => selected = v),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ctx.tr('Cancel')),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: Text(ctx.tr('Transfer')),
              ),
            ],
          );
        });
      },
    );

    if (confirmed != true || selected == null || !context.mounted) return;
    final ok = await controller.transferProjectOwnership(project, selected!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? context.tr('Ownership transferred.')
            : (controller.collaborationNotice ?? context.tr('Failed to transfer ownership.'))),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProjectOwner = controller.userEmail?.toLowerCase() ==
            project.ownerEmail?.toLowerCase() ||
        (controller.userId != null &&
            controller.userId!.isNotEmpty &&
            controller.userId == project.ownerId);
return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          InkWell(
            onTap: onOpen,
            child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 28),
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
               Align(
                 alignment: Alignment.centerLeft,
                 child: Tooltip(
                   message: context.tr('Edit package name'),
                   child: InkWell(
                     borderRadius: BorderRadius.circular(12),
                     onTap: () => _editPackage(context),
                     child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                       decoration: BoxDecoration(
                         color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Text(
                         project.package.isEmpty ? context.tr('Set package') : project.package,
                         maxLines: 1,
                         overflow: TextOverflow.ellipsis,
                         style: TextStyle(
                           fontSize: 11,
                           color: theme.colorScheme.onSecondaryContainer,
                         ),
                       ),
                     ),
                   ),
                 ),
               ),
               const SizedBox(height: 2),
            ],
          ),
        ),
      ),
          Positioned(
            left: 12,
            bottom: 6,
            child: Tooltip(
              message: isProjectOwner
                  ? context.tr('Transfer project')
                  : (project.ownerEmail ?? ''),
              child: MouseRegion(
                cursor: isProjectOwner
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showTransferDialog(context),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        UserAvatar(
                          dataUrl: null,
                          email: project.ownerEmail,
                          radius: 6,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            project.ownerEmail ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        if (isProjectOwner) ...<Widget>[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.swap_horiz,
                            size: 13,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
