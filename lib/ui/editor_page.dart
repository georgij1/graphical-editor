import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/login_screen.dart';
import '../editor/editor_controller.dart';
import '../l10n/app_localizations.dart';
import 'widgets/canvas_area.dart';
import 'widgets/downloads_dialog.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/outline_panel.dart';
import 'widgets/palette_panel.dart';
import 'widgets/profile_dialog.dart';
import 'widgets/project_panel.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/status_bar.dart';
import 'widgets/validation_strip.dart';
import 'widgets/toolbar.dart';
import 'widgets/user_avatar.dart';
import 'widgets/vertical_split_view.dart';

/// Root screen of the editor: login gate + responsive three-pane layout.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.controller});

  /// Optional injected controller (used in tests).
  final EditorController? controller;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorController _controller =
      widget.controller ?? EditorController();
  late final bool _ownsController = widget.controller == null;
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // The page may be opened with an invitation link.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInvitation();
    });
  }

  /// Asks the server about the invitation from the address of the page and
  /// offers to join the project.
  Future<void> _checkInvitation() async {
    final invite = _controller.pendingInviteLink;
    if (invite == null) return;
    final info = await _controller.readPendingInvite();
    if (!mounted || info == null) return;
    final join = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Invitation')),
        content: Text(
          context
              .tr(
                'You are invited to the project "{0}" of {1}. Do you want to join it?',
              )
              .replaceAll('{0}', info.projectName)
              .replaceAll('{1}', info.ownerEmail),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Join the project')),
          ),
        ],
      ),
    );
    if (join != true) return;
    final ok = await _controller.acceptInvite(invite);
    if (!mounted) return;
    if (ok) {
      _showMessage(context.tr('You have joined the project.'));
    } else {
      _showMessage(
        _controller.collaborationNotice ??
            context.tr('Could not join the project.'),
      );
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final ok = await _controller.openFile();
    if (!ok && mounted) {
      _showMessage(context.tr('Could not open the selected file.'));
    }
  }

  /// Ctrl+S writes the document into the workspace when the save mode allows it.
  /// No file is downloaded: that is what the explicit download action is for.
  Future<void> _save() async {
    final ok = await _controller.saveDocument(trigger: 'shortcut');
    if (!mounted) return;
    if (ok) {
      _showMessage(context.tr('Document saved.'));
    }
  }

  /// Writes the document to a file the user picks.
  Future<void> _download() async {
    final ok = await _controller.saveFile();
    if (mounted) {
      _showMessage(
        ok ? context.tr('Document saved.') : context.tr('Save cancelled.'),
      );
    }
  }

  void _showMessage(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showCode() => _controller.editSceneSource();

  Future<void> _attachStylesheet(BuildContext context) async {
    final paths = _controller.projectStylesheetPaths;
    if (paths.isEmpty) {
      _showMessage(context.tr('No stylesheet files found in the project.'));
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('Attach stylesheet')),
        children: <Widget>[
          for (final p in paths)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(p),
              child: Text(p, style: const TextStyle(fontFamily: 'monospace')),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final ok = _controller.attachStylesheetToScene(selected);
    if (!context.mounted) return;
    _showMessage(
      ok
          ? context.tr('Stylesheet attached to the scene.')
          : context.tr('Could not attach stylesheet.'),
    );
  }

  List<Widget> _accountActions() {
    return <Widget>[
      PopupMenuButton<String>(
        tooltip: context.tr('Account'),
        onSelected: (value) {
          switch (value) {
            case 'profile':
              showProfileDialog(context, controller: _controller);
            case 'settings':
              showSettingsDialog(context, controller: _controller);
            case 'download':
              DownloadsDialog.show(context);
            case 'out':
              _controller.signOut();
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          // Tapping the login opens the profile, so it is no longer inert.
          PopupMenuItem<String>(
            value: 'profile',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(
                dataUrl: _controller.avatarDataUrl,
                email: _controller.userEmail,
                radius: 16,
              ),
              title: Text(
                (_controller.userEmail ?? '').isEmpty
                    ? context.tr('Signed in')
                    : _controller.userEmail!,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                context.tr('Profile'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'settings',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_outlined),
              title: Text(context.tr('Settings')),
            ),
          ),
          PopupMenuItem<String>(
            value: 'download',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined),
              title: Text(context.tr('Download client')),
            ),
          ),
          PopupMenuItem<String>(
            value: 'out',
            child: Text(context.tr('Sign out')),
          ),
        ],
        icon: _AccountButton(controller: _controller),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.authStatus) {
            case AuthStatus.loading:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            case AuthStatus.signedOut:
              return LoginScreen(controller: _controller);
            case AuthStatus.signedIn:
              break;
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1040;
              return Scaffold(
                appBar: AppBar(
                  titleSpacing: 12,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  // Leaving a project belongs to the editor header, next to
                  // the name it applies to.
                  leading: _controller.currentProject != null
                      ? IconButton(
                          tooltip: context.tr('Back to projects'),
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _controller.backToProjects,
                        )
                      : null,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Title(controller: _controller),
                      if (_controller.currentProject != null &&
                          _controller.hasOpenDocument) ...<Widget>[
                        const SizedBox(width: 12),
                        _SaveStatus(controller: _controller),
                      ],
                    ],
                  ),
                  actions: <Widget>[
                    // Inside a project the header is crowded, so the account
                    // button moves to the far right instead of leading the
                    // actions. On the project list it stays on the left.
                    if (_controller.currentProject != null) ...<Widget>[
                      if (_controller.hasOpenFxml)
                        _PresenceBar(controller: _controller),
                      if (_controller.hasOpenFxml)
                        TextButton.icon(
                          onPressed: () => _attachStylesheet(context),
                          icon: const Icon(Icons.style_outlined, size: 18),
                          label: Text(context.tr('Attach stylesheet')),
                        ),
                      if (_controller.codeMode || _controller.openSource != null)
                        TextButton.icon(
                          onPressed: _controller.aiFixHandler == null
                              ? null
                              : () => _controller.aiFixHandler!.call(),
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: Text(context.tr('Fix with AI')),
                        ),
                      EditorToolbar(
                        controller: _controller,
                        onShowCode: _showCode,
                      ),
                      ..._accountActions(),
                    ] else
                      ..._accountActions(),
                  ],
                  bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(1),
                    child: Divider(height: 1),
                  ),
                ),
                body: _ShortcutScope(
                  controller: _controller,
                  onSave: _save,
                  child: wide
                      ? _WideLayout(
                          controller: _controller,
                          onShowCode: _showCode,
                          onOpen: _open,
                          onSave: _save,
                          onDownload: _download,
                        )
                      : _NarrowLayout(
                          controller: _controller,
                          onOpen: _open,
                          onSave: _save,
                          onDownload: _download,
                          onShowCode: _showCode,
                        ),
                ),
                // The status bar describes an open document, so it stays hidden on the
                // project picker. The validation strip above it reports build
                // problems found by the check that runs on every save.
                extendBody: true,
               resizeToAvoidBottomInset: false,
               bottomNavigationBar: (_controller.hasOpenDocument &&
                        (_controller.hasOpenFxml ||
                            (_controller.validation?.issues.isNotEmpty ?? false)))
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ValidationStrip(controller: _controller),
                          StatusBar(controller: _controller),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

/// Avatar with the signed in login next to it, so the account is recognisable
/// without opening the menu.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final email = controller.userEmail ?? '';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (email.isNotEmpty) ...<Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                maxLines: 1,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
          ],
          UserAvatar(
            dataUrl: controller.avatarDataUrl,
            email: controller.userEmail,
            radius: 15,
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final title = controller.displayTitle;
    final text = switch (title) {
      'Projects' => context.tr('Projects'),
      'Loading…' => context.tr('Loading…'),
      _ => title,
    };
    // The theme colour is explicit: a hard coded style here lost its contrast
    // on the dark theme and the project name became invisible.
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.account_tree_outlined, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            // The project name must survive a crowded header, so it keeps a
            // readable minimum and only then starts to ellipsize.
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
      ],
    );
  }
}

class _OpenTabsBar extends StatefulWidget {
  const _OpenTabsBar({required this.controller});

  final EditorController controller;

  @override
  State<_OpenTabsBar> createState() => _OpenTabsBarState();
}

class _OpenTabsBarState extends State<_OpenTabsBar> {
  int _hovered = -1;

  EditorController get controller => widget.controller;

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.java')) return Icons.data_object;
    if (lower.endsWith('.fxml') || lower.endsWith('.xml')) {
      return Icons.code;
    }
    if (lower.endsWith('.bat') || lower.endsWith('.sh') || lower.endsWith('.cmd')) {
      return Icons.terminal;
    }
    if (lower.endsWith('.json')) return Icons.data_object;
    if (lower.endsWith('.md')) return Icons.article_outlined;
    if (lower.endsWith('.gitignore')) return Icons.visibility_off_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final tabs = controller.openTabs;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tabs.length,
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final active = index == controller.activeTabIndex;
              final hovered = _hovered == index;
              final name = tab.path.split('/').last;
              return MouseRegion(
                onEnter: (_) => setState(() => _hovered = index),
                onExit: (_) => setState(() => _hovered = -1),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => controller.activateTab(index),
                    child: Container(
                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: active
                          ? theme.colorScheme.surface
                          : (hovered
                              ? theme.colorScheme.surface.withValues(alpha: 0.5)
                              : Colors.transparent),
                      border: Border(
                        right: BorderSide(color: theme.dividerColor, width: 1),
                        bottom: BorderSide(
                          color: active
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          _iconFor(name),
                          size: 14,
                          color: active
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.normal,
                              color: active
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (active || hovered)
                          InkWell(
                            onTap: () => controller.closeTab(index),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.controller,
    required this.onShowCode,
    required this.onOpen,
    required this.onSave,
    required this.onDownload,
  });

  final EditorController controller;
  final VoidCallback onShowCode;
  final Future<void> Function() onOpen;
  final Future<void> Function() onSave;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    // Without an open project the centre shows the project picker full width:
    // the side panels describe the document, so they are not built at all.
    if (!controller.hasOpenDocument) {
      return CanvasArea(controller: controller, onShowCode: onShowCode);
    }
    final showLeftPanels = controller.hasOpenFxml;
    return Row(
      children: <Widget>[
        if (showLeftPanels) ...<Widget>[
          SizedBox(
            width: 264,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: <Widget>[
                  TabBar(
                    tabs: <Widget>[
                      Tab(
                        icon: const Icon(Icons.widgets, size: 18),
                        text: context.tr('Components'),
                      ),
                      Tab(
                        icon: const Icon(Icons.account_tree, size: 18),
                        text: context.tr('Outline'),
                      ),
                    ],
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        PalettePanel(controller: controller),
                        OutlinePanel(controller: controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => controller.openTabs.isNotEmpty
                    ? _OpenTabsBar(controller: controller)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: CanvasArea(controller: controller, onShowCode: onShowCode),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: VerticalSplitView(
            fraction: controller.treeFraction,
            onChanged: controller.setTreeFraction,
            onReset: controller.clearTreeFraction,
            top: ProjectPanel(
              controller: controller,
              onOpen: onOpen,
              onSave: onSave,
              onDownload: onDownload,
            ),
            bottom: InspectorPanel(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatefulWidget {
  const _NarrowLayout({
    required this.controller,
    required this.onOpen,
    required this.onSave,
    required this.onDownload,
    required this.onShowCode,
  });

  final EditorController controller;
  final Future<void> Function() onOpen;
  final Future<void> Function() onSave;
  final Future<void> Function() onDownload;
  final VoidCallback onShowCode;

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<_NarrowLayout> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // The panels below the canvas describe the open document, so they are not
    // built while the project picker is showing.
    if (!widget.controller.hasOpenDocument) {
      return CanvasArea(
        controller: widget.controller,
        onShowCode: widget.onShowCode,
      );
    }
    return Column(
      children: <Widget>[
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => widget.controller.openTabs.isNotEmpty
              ? _OpenTabsBar(controller: widget.controller)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: CanvasArea(
            controller: widget.controller,
            onShowCode: widget.onShowCode,
          ),
        ),
        const Divider(height: 1),
        SizedBox(
          height: 300,
          child: DefaultTabController(
            length: 4,
            initialIndex: _tab,
            child: Column(
              children: <Widget>[
                TabBar(
                  onTap: (index) => setState(() => _tab = index),
                  tabs: <Widget>[
                    Tab(
                      icon: const Icon(Icons.folder_copy_outlined, size: 18),
                      text: context.tr('Project'),
                    ),
                    Tab(
                      icon: const Icon(Icons.widgets, size: 18),
                      text: context.tr('Components'),
                    ),
                    Tab(
                      icon: const Icon(Icons.account_tree, size: 18),
                      text: context.tr('Outline'),
                    ),
                    Tab(
                      icon: const Icon(Icons.tune, size: 18),
                      text: context.tr('Inspector'),
                    ),
                  ],
                  labelStyle: const TextStyle(fontSize: 12),
                ),
                Expanded(
                  child: TabBarView(
                    controller: null,
                    children: <Widget>[
                      ProjectPanel(
                        controller: widget.controller,
                        onOpen: widget.onOpen,
                        onSave: widget.onSave,
                        onDownload: widget.onDownload,
                      ),
                      PalettePanel(controller: widget.controller),
                      OutlinePanel(controller: widget.controller),
                      InspectorPanel(controller: widget.controller),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutScope extends StatefulWidget {
  const _ShortcutScope({
    required this.controller,
    required this.onSave,
    required this.child,
  });

  final EditorController controller;
  final VoidCallback onSave;
  final Widget child;

  @override
  State<_ShortcutScope> createState() => _ShortcutScopeState();
}

class _ShortcutScopeState extends State<_ShortcutScope> {
  /// True while a text field owns the keyboard.
  bool _editingText = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  /// A shortcut consumes the key even when its action does nothing, so the
  /// canvas bindings have to disappear while a text field is focused - you
  /// cannot press Backspace while editing text.
  void _onFocusChanged() {
    final editing = _isEditingText();
    if (editing == _editingText) return;
    setState(() => _editingText = editing);
  }

  bool _isEditingText() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    var editing = focusContext.widget is EditableText;
    if (editing) return true;
    focusContext.visitAncestorElements((Element element) {
      if (element.widget is EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  @override
  Widget build(BuildContext context) {
    // The canvas shortcuts (delete, arrows, undo/redo) must not fire while the
    // code editor is active - otherwise Backspace/arrows would edit the model
    // instead of the text field. Ctrl+S is always available.
    final controller = widget.controller;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          widget.onSave,
      if (!controller.codeMode &&
          !_editingText) ...<ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            controller.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            controller.redo,
        const SingleActivator(LogicalKeyboardKey.delete):
            controller.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace):
            controller.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            controller.moveSelected(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            controller.moveSelected(1, 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            controller.moveSelected(2, 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            controller.moveSelected(3, 1),
      },
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}

/// Save status indicator shown in the header next to the project name.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.controller});

  final EditorController controller;

  Future<void> _showSaveSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ListenableBuilder(
          listenable: controller,
          builder: (dialogContext, _) {
            final mode = controller.saveMode == 'shortcut' ? 'shortcut' : 'auto';
            return AlertDialog(
              title: Text(context.tr('Save settings')),
              content: RadioGroup<String>(
                groupValue: mode,
                onChanged: (v) {
                  if (v != null) controller.setSaveMode(v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RadioListTile<String>(
                      value: 'auto',
                      title: Text(context.tr('Automatically')),
                      subtitle: Text(context.tr('Save changes automatically')),
                    ),
                    RadioListTile<String>(
                      value: 'shortcut',
                      title: Text(context.tr('By Ctrl+S')),
                      subtitle: Text(context.tr('Save only with Ctrl+S')),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(context.tr('Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = controller.dirty;
    final color = dirty ? Colors.orange : Colors.green;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSaveSettings(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                dirty ? Icons.circle_outlined : Icons.check_circle_outline,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                dirty ? context.tr('Unsaved changes') : context.tr('Saved'),
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresenceBar extends StatelessWidget {
  const _PresenceBar({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final participants = controller.onlineParticipants;
    if (participants.isEmpty) return const SizedBox.shrink();

    // Show at most four avatars, then a "+N" badge.
    const maxShown = 4;
    final shown = participants.take(maxShown).toList();
    final overflow = participants.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Tooltip(
                message: (p['email'] as String?) ?? '',
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        _initial(p['email'] as String?),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+$overflow',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '${participants.length}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _initial(String? email) {
    if (email == null || email.isEmpty) return '?';
    return email[0].toUpperCase();
  }
}
