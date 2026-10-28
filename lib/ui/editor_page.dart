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

  /// Ctrl+S and the save button write the document into the workspace. No file
  /// is downloaded: that is what the explicit download action is for.
  Future<void> _save() async {
    await _controller.saveDocument();
    if (mounted) _showMessage(context.tr('Document saved.'));
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
                  // Leaving a project belongs to the editor header, next to
                  // the name it applies to.
                  leading: _controller.currentProject != null
                      ? IconButton(
                          tooltip: context.tr('Back to projects'),
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _controller.backToProjects,
                        )
                      : null,
                  title: _Title(controller: _controller),
                  actions: <Widget>[
                    // Inside a project the header is crowded, so the account
                    // button moves to the far right instead of leading the
                    // actions. On the project list it stays on the left.
                    if (_controller.currentProject != null) ...<Widget>[
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
                bottomNavigationBar: _controller.hasOpenDocument
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
    return Row(
      children: <Widget>[
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
        Expanded(
          child: CanvasArea(controller: controller, onShowCode: onShowCode),
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
