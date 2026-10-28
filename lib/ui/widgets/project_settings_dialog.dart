import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor/editor_controller.dart';
import '../../editor/build_analyzer.dart';
import '../../auth/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project.dart';
import '../../project/project_history.dart';
import 'build_report_dialog.dart';
import 'user_avatar.dart';
import 'export_dialog.dart';
import 'project_dialogs.dart';

/// Opens the settings window of a single project.
Future<void> showProjectSettingsDialog(
  BuildContext context, {
  required EditorController controller,
  required Project project,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProjectSettingsDialog(
      controller: controller,
      project: project,
    ),
  );
}

/// Project settings: the name, a summary and every action that used to live in
/// the card's overflow menu.
class ProjectSettingsDialog extends StatefulWidget {
  const ProjectSettingsDialog({
    super.key,
    required this.controller,
    required this.project,
  });

  final EditorController controller;
  final Project project;

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.project.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.project.description);
  late final TextEditingController _packageController =
      TextEditingController(text: widget.project.package);
  late final TextEditingController _mainClassController =
      TextEditingController(text: widget.project.mainClass);
  String _inviteRole = 'editor';

  bool _busy = false;
  String? _message;
  bool _error = false;
  String? _packageError;

  /// Debounce timer for auto-saving name/description after the user stops
  /// typing.
  Timer? _saveTimer;

  EditorController get controller => widget.controller;

  /// The accounts that may still be invited.
  List<Account> get available => controller.availableAccounts(widget.project);

  static Color _avatarColor(String email) {
    final hash = email.hashCode.abs();
    final colors = <Color>[
      Colors.blue, Colors.indigo, Colors.purple, Colors.pink, Colors.red,
      Colors.orange, Colors.amber, Colors.green, Colors.teal, Colors.cyan,
    ];
    return colors[hash % colors.length];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await controller.loadAccounts();
      if (!mounted) return;
      await controller.loadHistory(widget.project);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _name.dispose();
    _description.dispose();
    _packageController.dispose();
    _mainClassController.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _error = error;
    });
  }

  /// Saves the name, description, package and main class together.
  void _saveDetails() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _say('Project name is empty.', error: true);
      return;
    }

    final package = _packageController.text.trim();
    final description = _description.text.trim();
    final renamed = name != widget.project.name;
    final described = description != widget.project.description;
    final repackaged = package != widget.project.package;
    final reclassed =
        _mainClassController.text.trim() != widget.project.mainClass;

    if (repackaged) {
      final error = _validatePackage(package);
      if (error != null) {
        _packageError = error;
        return;
      }
    }
    _packageError = null;

    if (!renamed && !described && !repackaged && !reclassed) return;
    if (renamed) controller.renameProject(widget.project, name);
    if (described) controller.setProjectDescription(widget.project, description);
    if (repackaged) controller.setProjectPackage(widget.project, package);
    if (reclassed)
      controller.setProjectMainClass(widget.project, _mainClassController.text);
    final changed = <String>[];
    if (renamed) changed.add(context.tr('name'));
    if (described) changed.add(context.tr('description'));
    if (repackaged) changed.add(context.tr('package'));
    if (reclassed) changed.add(context.tr('main class'));
    _say(
      '${context.tr('Project updated')} (${changed.join(', ')}).',
    );
  }

  /// Validates a Java package name. Returns an error message, or null when
  /// valid.
  String? _validatePackage(String package) {
    if (package.isEmpty) {
      return context.tr('Package cannot be empty.');
    }
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
    for (final segment in segments) {
      if (segment.isEmpty) {
        return context.tr('Each package segment must not be empty.');
      }
      if (!_isValidJavaIdentifier(segment)) {
        return context.tr(
            'Each segment must start with a letter and contain only letters, digits and underscores.');
      }
      if (_javaKeywords.contains(segment.toLowerCase())) {
        return context.tr('Segment cannot be a Java keyword.');
      }
    }
    return null;
  }

  /// Java reserved keywords and literals that cannot be used as package
  /// segments.
  static final Set<String> _javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'null',
    'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
    'transient', 'try', 'void', 'volatile', 'while', 'true', 'false',
  };

  /// True when [segment] is a valid Java identifier.
  static bool _isValidJavaIdentifier(String segment) {
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(segment);
  }

  /// Saves after the user stops typing for a short moment, so there is no
  /// explicit Save button.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveDetails);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    await action();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() => _run(() async {
        final options = await showExportDialog(context);
        if (options == null || !mounted) return;

        // Pre-export check: the mini neural network looks for inconsistencies
        // (for example an FXML controller outside the project package that
        // would fail with ClassNotFoundException at launch).
        final report = BuildAnalyzer.validate(widget.project);
        if (!mounted) return;
        final action = await showBuildReportDialog(
          context,
          report: report,
          mode: ReportDialogMode.export,
        );
        if (!mounted) return;
        if (action == ReportDialogAction.fix) {
          controller.fixSceneControllers(widget.project);
        } else if (action != ReportDialogAction.proceed) {
          return;
        }

        final ok = await controller.exportProject(widget.project, options);
        if (!mounted) return;
        _say(
          ok ? 'Project exported.' : 'Export failed.',
          error: !ok,
        );
      });

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: context.tr('Delete project'),
      message: context.l10n.deleteProject(widget.project.name),
    );
    if (ok != true || !mounted) return;
    controller.deleteProject(widget.project);
    Navigator.of(context).pop();
  }

  /// Publishes the project, so the participants see the current state.
  Future<void> _publish() async {
    await _run(() async {
      final ok = await controller.publishSharedProject();
      _say(
        ok
            ? 'The project has been published for the participants.'
            : controller.collaborationNotice ?? 'Could not publish the project.',
        error: !ok,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;
    final initials = project.name.isEmpty
        ? '?'
        : project.name
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .take(2)
            .join();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ============ Header ============
            _DialogHeader(
              title: context.tr('Project settings'),
              project: project,
              initials: initials,
              color: _ProjectSettingsDialogState._avatarColor(project.name),
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),

            // ============ Body ============
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ---- Project details ----
                    _SectionCard(
                      title: context.tr('Project details'),
                      icon: Icons.info_outline,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _name,
                            enabled: !_busy,
                            autofocus: true,
                            style: theme.textTheme.titleMedium,
                            decoration: InputDecoration(
                              labelText: context.tr('Project name'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _scheduleSave(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _description,
                            enabled: !_busy,
                            minLines: 2,
                            maxLines: 4,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              labelText: context.tr('Description'),
                              helperText: context.tr(
                                  'Shown in the README of the export.'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _scheduleSave(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _packageController,
                            enabled: !_busy,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              labelText: context.tr('Java package'),
                              helperText: context.tr(
                                  'Used for the generated Java sources.'),
                              errorText: _packageError,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              _packageError = _validatePackage(value);
                              _scheduleSave();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _mainClassController,
                            enabled: !_busy,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              labelText: context.tr('Main class'),
                              helperText: context.tr(
                                  'Entry point of the generated application.'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _scheduleSave(),
                          ),
                          const SizedBox(height: 16),
                          // Owner badge shown as a colored pill:
                          if (project.ownerEmail != null) ...<Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.person, size: 14,
                                      color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    project.ownerEmail!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- Actions ----
                    _SectionCard(
                      title: context.tr('Actions'),
                      icon: Icons.play_circle_outline,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.start,
                        children: <Widget>[
                          _ActionButton(
                            icon: Icons.open_in_new,
                            label: context.tr('Open project'),
                            onPressed: _busy
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    controller.openProject(widget.project);
                                  },
                          ),
                          _ActionButton(
                            icon: Icons.copy_all_outlined,
                            label: context.tr('Duplicate'),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      controller.duplicateProject(
                                          widget.project);
                                      _say(context.tr('Project duplicated.'));
                                    }),
                          ),
                          _ActionButton(
                            icon: Icons.archive_outlined,
                            label: context.tr('Export'),
                            onPressed: _busy ? null : _export,
                          ),
                          if (controller.userEmail == project.ownerEmail)
                            _ActionButton(
                              icon: Icons.person_outline,
                              label: context.tr('Transfer ownership'),
                              onPressed: _busy ? null : () => _showTransferDialog(),
                            ),
                          TextButton.icon(
                            onPressed: _busy ? null : _delete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            label: Text(context.tr('Delete')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- Participants ----
                    _SectionCard(
                      title: context.tr('Participants'),
                      icon: Icons.group_outlined,
                      trailing: project.collaborative
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.sync,
                                      size: 13,
                                      color:
                                          theme.colorScheme.onPrimaryContainer),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.tr('Shared mode'),
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: theme.colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 8),
                          if (project.participants.isEmpty)
                            _EmptyParticipants()
                          else
                            ...project.participants.map((member) =>
                                _ParticipantRow(
                                  member: member,
                                  isOwner: controller.userId == project.ownerId,
                                  enabled: !_busy,
                                  onRoleChanged: (role) =>
                                      _changeRole(member, role),
                                  onRemove: () => _removeParticipant(
                                      member.email),
                                )),
                          const SizedBox(height: 10),
                          Autocomplete<String>(
                            displayStringForOption: (option) => option,
                            optionsBuilder: (value) {
                              final query = value.text.trim().toLowerCase();
                              final accounts = controller
                                  .availableAccounts(widget.project)
                                  .map((a) => a.email)
                                  .where((email) =>
                                      query.isEmpty ||
                                      email.toLowerCase().contains(query))
                                  .toList();
                              if (query.contains('@') &&
                                  !accounts.contains(query)) {
                                accounts.insert(0, query);
                              }
                              return accounts;
                            },
                            onSelected: (email) => _inviteParticipant(email),
                            fieldViewBuilder:
                                (context, fieldController, focusNode,
                                    onSubmitted) {
                              return TextField(
                                controller: fieldController,
                                focusNode: focusNode,
                                enabled: !_busy,
                                decoration: InputDecoration(
                                  labelText: context.tr('Participant'),
                                  hintText: context.tr(
                                      'Pick an account or type an email'),
                                  prefixIcon:
                                      const Icon(Icons.person_add_alt,
                                          size: 18),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onSubmitted: (value) =>
                                    _inviteParticipant(value),
                              );
                            },
                            optionsViewBuilder:
                                (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxHeight: 220),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final option =
                                            options.elementAt(index);
                                        return ListTile(
                                          dense: true,
                                          leading: UserAvatar(
                                            dataUrl: null,
                                            email: option,
                                            radius: 13,
                                          ),
                                          title: Text(option,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          onTap: () => onSelected(option),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Text(context.tr('Rights'),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )),
                              const SizedBox(width: 8),
                              _RoleChoice(
                                value: _inviteRole,
                                enabled: !_busy,
                                onChanged: (value) =>
                                    setState(() => _inviteRole = value ??
                                        'editor'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      final link =
                                          await controller.createInviteLink(
                                              _inviteRole);
                                      if (!mounted) return;
                                      if (link == null) {
                                        _say(
                                            controller.collaborationNotice ??
                                                'Could not create the link.',
                                            error: true);
                                        return;
                                      }
                                      if (!mounted || !context.mounted) {
                                        return;
                                      }
                                      await showDialog<void>(
                                        context: context,
                                        builder: (context) =>
                                            _InviteLinkDialog(link: link),
                                      );
                                    }),
                            icon: const Icon(Icons.link, size: 18),
                            label: Text(context.tr('Invite by link')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- History ----
                    _SectionCard(
                      title: context.tr('History'),
                      icon: Icons.history,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 8),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final history = controller.history;
                              if (history.versions.isEmpty &&
                                  history.builds.isEmpty) {
                                return Text(
                                  context.tr(
                                      'The project has no versions yet: build it to release the first one.'),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              }
                              final versions =
                                  history.versions.take(5).toList();
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  for (var i = 0; i < versions.length; i++)
                                    _VersionLine(
                                      version: versions[i],
                                      previous: i + 1 < versions.length
                                          ? versions[i + 1]
                                          : null,
                                    ),
                                  for (final build
                                      in history.builds.take(5))
                                    _BuildHistoryLine(record: build),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- Publish ----
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _publish,
                        icon: const Icon(
                            Icons.cloud_upload_outlined, size: 18),
                        label: Text(context.tr('Publish for the participants')),
                      ),
                    ),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _error
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _error ? Icons.error : Icons.check_circle,
                              size: 16,
                              color: _error
                                  ? theme.colorScheme.onErrorContainer
                                  : theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _message!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _error
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme
                                          .onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ============ Footer ============
            _DialogFooter(
              onClose: () => Navigator.of(context).pop(),
              showClose: false,
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferDialog() async {
    final eligible = widget.project.participants
        .where((m) => m.email.toLowerCase() !=
            widget.controller.userEmail?.toLowerCase())
        .toList();
    if (eligible.isEmpty) {
      _say(context.tr('No participants available to transfer ownership to.'));
      return;
    }
    String? selected = eligible.first.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Transfer ownership')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr('Select the new owner:')),
            const SizedBox(height: 12),
            for (final member in eligible)
              RadioListTile<String>(
                value: member.email,
                groupValue: selected,
                title: Text(member.email),
                secondary: UserAvatar(
                  dataUrl: null,
                  email: member.email,
                  radius: 16,
                ),
                onChanged: (value) => selected = value,
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: selected != null
                ? () => Navigator.of(context).pop(true)
                : null,
            child: Text(context.tr('Transfer')),
          ),
        ],
      ),
    );
    if (confirmed == true && selected != null && mounted) {
      final ok = await controller.transferProjectOwnership(
        widget.project,
        selected!,
      );
      if (ok) {
        _say(context.tr('Ownership transferred to ') + selected! + '.');
      } else {
        _say(context.tr('Failed to transfer ownership.'), error: true);
      }
    }
  }

  /// Adds a participant to the project and switches it to the shared mode.
  Future<void> _inviteParticipant(String email) async {
    final address = email.trim();
    if (address.isEmpty) {
      _say('Enter the email of the participant.', error: true);
      return;
    }
    await _run(() async {
      final ok = await controller.inviteCollaborator(address, _inviteRole);
      if (!ok) {
        _say(controller.collaborationNotice ?? 'Could not add the participant.',
            error: true);
        return;
      }
      _say('The participant has been added.');
    });
  }

  /// Changes the rights of a participant.
  Future<void> _changeRole(ProjectMember member, String role) async {
    await _run(() async {
      final ok = await controller.changeCollaboratorRole(member.email, role);
      if (!ok) {
        _say(controller.collaborationNotice ??
            'Could not change the rights.',
            error: true);
        return;
      }
      _say('The rights have been changed.');
    });
  }

  /// Removes a participant from the project.
  Future<void> _removeParticipant(String email) async {
    await _run(() async {
      final ok = await controller.removeCollaborator(email);
      if (!ok) {
        _say(controller.collaborationNotice ??
            'Could not remove the participant.',
            error: true);
        return;
      }
      _say('The participant has been removed.');
    });
  }
}

/// Shows the invitation link so that it can be copied and sent.
class _InviteLinkDialog extends StatefulWidget {
  const _InviteLinkDialog({required this.link});

  final String link;

  @override
  State<_InviteLinkDialog> createState() => _InviteLinkDialogState();
}

class _InviteLinkDialogState extends State<_InviteLinkDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DialogHeader(
              title: context.tr('Invitation link'),
              icon: Icons.link,
              color: theme.colorScheme.primary,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    context.tr(
                        'Send the link to the person: they join the project when they open it.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    widget.link,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DialogFooter(
              onClose: () => Navigator.of(context).pop(),
              actions: <Widget>[
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.link));
                    if (mounted) setState(() => _copied = true);
                  },
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                  label: Text(context.tr(_copied ? 'Copied' : 'Copy')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('Close')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A participant of the project with his picture, his rights and the button
/// that removes him.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.member,
    required this.isOwner,
    required this.enabled,
    required this.onRoleChanged,
    required this.onRemove,
  });

  final ProjectMember member;
  final bool isOwner;
  final bool enabled;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          UserAvatar(dataUrl: null, email: member.email, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  member.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isOwner) ...<Widget>[
                  const SizedBox(height: 2),
                  _RoleChoice(
                    value: member.role,
                    enabled: enabled,
                    onChanged: (value) => onRoleChanged(value ?? 'editor'),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    member.canEdit ? context.tr('Editor') : context.tr('Viewer'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('Remove participant'),
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// The rights of a participant: editor or viewer.
class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(8),
        style: Theme.of(context).textTheme.bodySmall,
        onChanged: enabled ? onChanged : null,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'editor',
            child: Text(context.tr('Editor')),
          ),
          DropdownMenuItem<String>(
            value: 'viewer',
            child: Text(context.tr('Viewer')),
          ),
        ],
      ),
    );
  }
}

/// Shown when nobody has been invited yet.
class _EmptyParticipants extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        context.tr(
            'Nobody has been invited yet. Add a participant to work on the project together.'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A released version in the history of the project.
class _VersionLine extends StatelessWidget {
  const _VersionLine({
    required this.version,
    this.previous,
  });

  final ProjectVersion version;
  final ProjectVersion? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _VersionDetailDialog(
          version: version,
          previous: previous,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.new_releases_outlined,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('v${version.revision}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                version.summary.isEmpty
                    ? context.tr('No notes')
                    : version.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Icon(Icons.chevron_right, size: 14,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(version.author,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}

/// Detail modal of a released version: what changed compared to the previous
/// version.
class _VersionDetailDialog extends StatelessWidget {
  const _VersionDetailDialog({
    required this.version,
    this.previous,
  });

  final ProjectVersion version;
  final ProjectVersion? previous;

  List<String> get addedScenes =>
      version.sceneNames
          .where((name) =>
              previous == null || !previous!.sceneNames.contains(name))
          .toList();

  List<String> get removedScenes =>
      previous == null
          ? <String>[]
          : previous!.sceneNames
              .where((name) => !version.sceneNames.contains(name))
              .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = '${version.date.day.toString().padLeft(2, '0')}'
        '.${version.date.month.toString().padLeft(2, '0')}'
        '.${version.date.year} '
        '${version.date.hour.toString().padLeft(2, '0')}'
        ':${version.date.minute.toString().padLeft(2, '0')}';

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DialogHeader(
              title: 'v${version.revision}',
              subtitle: date,
              icon: Icons.new_releases_outlined,
              color: theme.colorScheme.primary,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DetailRow(
                    label: context.tr('Author'),
                    value: version.author,
                  ),
                  _DetailRow(
                    label: context.tr('Scenes'),
                    value:
                        '${version.scenesCount} (${version.filesCount} files)',
                  ),
                  if (version.summary.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(context.tr('Notes'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    const SizedBox(height: 6),
                    Text(version.summary, style: theme.textTheme.bodyMedium),
                  ],
                  if (previous != null &&
                      (addedScenes.isNotEmpty || removedScenes.isNotEmpty))
                    ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                          context.tr('Changes compared to the previous version:'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (addedScenes.isNotEmpty) ...<Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.add_circle_outline,
                                size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(context.tr('Added scenes:')),
                                  const SizedBox(height: 4),
                                  for (final name in addedScenes)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 2),
                                      child: Text('• $name'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (removedScenes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.remove_circle_outline,
                                size: 16, color: Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(context.tr('Removed scenes:')),
                                  const SizedBox(height: 4),
                                  for (final name in removedScenes)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 2),
                                      child: Text('• $name'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  if (previous == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        context.tr('This is the first version of the project.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DialogFooter(
              onClose: () => Navigator.of(context).pop(),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('Close')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single label/value row inside the version detail dialog.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A build in the history of the project.
class _BuildHistoryLine extends StatelessWidget {
  const _BuildHistoryLine({required this.record});

  final BuildRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 23),
      child: Row(
        children: <Widget>[
          Icon(
            record.succeeded ? Icons.check_circle_outline : Icons.error_outline,
            size: 13,
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

/// The top bar of a dialog: title, optional subtitle, icon and close button.
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    required this.onClose,
    this.project,
    this.initials,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final VoidCallback onClose;
  final Project? project;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            CircleAvatar(
              radius: 16,
              backgroundColor: color ?? theme.colorScheme.primaryContainer,
              child: project != null && initials != null
                  ? Text(
                      initials!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    )
                  : Icon(icon!,
                      size: 18,
                      color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null)
                  Text(
                    title!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('Close'),
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// A section inside the dialog with a header and a card.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    this.trailing,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // ignore: use_null_aware_elements
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A single action button.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(100, 36),
        foregroundColor: theme.colorScheme.onSurface,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// The bottom bar of a dialog with optional action buttons.
class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    this.actions = const <Widget>[],
    required this.onClose,
    this.showClose = true,
  });

  final List<Widget> actions;
  final VoidCallback onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          ...actions,
          if (actions.isNotEmpty) const SizedBox(width: 8),
          if (showClose)
            TextButton(
              onPressed: onClose,
              child: Text(context.tr('Close')),
            ),
        ],
      ),
    );
  }
}
