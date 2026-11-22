import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ollama_client.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

class AiChatPanel extends StatefulWidget {
  AiChatPanel({
    super.key,
    required this.controller,
    required this.onClose,
    AiClient? client,
  }) : client = client ?? AiClient();

  final EditorController controller;
  final VoidCallback onClose;
  final AiClient client;

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<String> _remoteModels = const <String>[];
  List<AiModelConfig> _customModels = const <AiModelConfig>[];
  List<String> _hiddenModelIds = const <String>[];
  String? _selectedModelId;
  bool _loadingModels = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _elapsedSeconds = 0;
  final Map<AiChatMessage, String> _translations = <AiChatMessage, String>{};
  final Set<AiChatMessage> _showTranslation = <AiChatMessage>{};
  final Set<AiChatMessage> _translating = <AiChatMessage>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadModels();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPrompt());
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _consumePendingPrompt();
  }

  void _consumePendingPrompt() {
    final prompt = widget.controller.takeAiChatPendingPrompt();
    if (prompt == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _input.text = prompt;
      _input.selection = TextSelection.collapsed(offset: prompt.length);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    List<String> remote = const <String>[];
    String? loadError;
    try {
      remote = await widget.client.listModels();
    } on AiException catch (error) {
      loadError = error.message;
    } catch (error) {
      loadError = error.toString();
    }
    final custom = await widget.controller.readCustomAiModels();
    final hidden = await widget.controller.readHiddenAiModels();
    final saved = await widget.controller.readAiModel();
    if (!mounted) return;
    final allIds = _allModelIds(remote: remote, custom: custom, hidden: hidden, savedId: saved);
    String? selected = saved;
    if (selected == null || (allIds.isNotEmpty && !allIds.contains(selected))) {
      selected = allIds.isNotEmpty ? allIds.first : saved;
    }
    setState(() {
      _remoteModels = remote;
      _customModels = custom;
      _hiddenModelIds = hidden;
      _loadingModels = false;
      _error = loadError != null && allIds.isEmpty ? loadError : _error;
      _selectedModelId = selected;
    });
    if (_selectedModelId != null) {
      await widget.controller.writeAiModel(_selectedModelId!);
    }
  }

  String _modelId({required String name, String? baseUrl}) =>
      EditorController.aiModelSelectionId(name: name, baseUrl: baseUrl);

  List<String> _allModelIds({
    required List<String> remote,
    required List<AiModelConfig> custom,
    List<String> hidden = const <String>[],
    String? savedId,
  }) {
    final hiddenSet = hidden.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final out = <String>[];
    final seen = <String>{};
    void addId(String? id) {
      final s = (id ?? '').trim();
      if (s.isEmpty || !seen.add(s)) return;
      final parsed = EditorController.parseAiModelSelection(s);
      if (parsed.name.trim().toLowerCase() == 'codellama:latest') return;
      if (hiddenSet.contains(s)) return;
      out.add(s);
    }
    for (final m in custom) {
      addId(_modelId(name: m.name, baseUrl: m.baseUrl));
    }
    for (final name in remote) {
      addId(_modelId(name: name));
    }
    addId(savedId);
    return out;
  }

  List<String> get _allModelIdsCurrent =>
      _allModelIds(remote: _remoteModels, custom: _customModels, hidden: _hiddenModelIds, savedId: _selectedModelId);

  String _modelLabel(String id) {
    final parsed = EditorController.parseAiModelSelection(id);
    final base = (parsed.baseUrl ?? '').trim();
    if (base.isEmpty) return parsed.name.isEmpty ? id : parsed.name;
    final short = base.replaceFirst(RegExp(r'^https?://'), '');
    return '${parsed.name} ($short)';
  }

  String? _modelBaseUrl(String? id) {
    final parsed = EditorController.parseAiModelSelection(id);
    final b = (parsed.baseUrl ?? '').trim();
    return b.isEmpty ? null : b;
  }

  String _modelName(String? id) {
    final parsed = EditorController.parseAiModelSelection(id);
    return parsed.name.isEmpty ? (id ?? '') : parsed.name;
  }

  bool _isCustomModelId(String? id) {
    if (id == null) return false;
    for (final m in _customModels) {
      if (_modelId(name: m.name, baseUrl: m.baseUrl) == id) return true;
    }
    return false;
  }

  Future<void> _removeSelectedCustomModel() async {
    final id = _selectedModelId;
    if (!_isCustomModelId(id)) return;
    final parsed = EditorController.parseAiModelSelection(id);
    await widget.controller.removeCustomAiModel(name: parsed.name, baseUrl: parsed.baseUrl);
    final custom = await widget.controller.readCustomAiModels();
    if (!mounted) return;
    final allIds = _allModelIds(remote: _remoteModels, custom: custom, hidden: _hiddenModelIds, savedId: null);
    String? next;
    if (allIds.isNotEmpty) {
      next = allIds.first;
    }
    setState(() {
      _customModels = custom;
      _selectedModelId = next;
    });
    if (next != null) {
      await widget.controller.writeAiModel(next);
    }
  }

  Future<void> _editSelectedCustomModel() async {
    final id = _selectedModelId;
    if (!_isCustomModelId(id)) return;
    final parsed = EditorController.parseAiModelSelection(id);
    final nameController = TextEditingController(text: parsed.name);
    final urlController = TextEditingController(text: parsed.baseUrl ?? '');
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Edit model')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: ctx.tr('Model name'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: ctx.tr('Server URL (optional)'),
                  hintText: 'e.g. http://localhost:11434',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              name: nameController.text.trim(),
              url: urlController.text.trim(),
            )),
            child: Text(ctx.tr('Save')),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
    if (result == null || result.name.trim().isEmpty) return;
    final newBaseUrl = result.url.trim().isEmpty ? null : result.url.trim();
    await widget.controller.updateCustomAiModel(
      oldName: parsed.name,
      oldBaseUrl: parsed.baseUrl,
      newName: result.name.trim(),
      newBaseUrl: newBaseUrl,
    );
    final custom = await widget.controller.readCustomAiModels();
    if (!mounted) return;
    final newId = _modelId(name: result.name.trim(), baseUrl: newBaseUrl);
    setState(() {
      _customModels = custom;
      _selectedModelId = newId;
    });
    await widget.controller.writeAiModel(newId);
  }

  Future<void> _showManageModelsDialog() async {
    final hidden = Set<String>.from(_hiddenModelIds);
    final custom = List<AiModelConfig>.from(_customModels);
    final remote = List<String>.from(_remoteModels);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> saveHidden() async {
              await widget.controller.writeHiddenAiModels(hidden.toList());
            }

            Widget sectionTitle(String text) => Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                );

            final remoteIds = <String>[
              for (final name in remote)
                if (name.trim().toLowerCase() != 'codellama:latest')
                  _modelId(name: name),
            ];
            final customIds = <String>[
              for (final m in custom) _modelId(name: m.name, baseUrl: m.baseUrl),
            ];

            return AlertDialog(
              title: Text(context.tr('Manage models')),
              content: SizedBox(
                width: 520,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (remoteIds.isNotEmpty) sectionTitle(context.tr('Ollama models')),
                        for (final id in remoteIds)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: !hidden.contains(id) && EditorController.parseAiModelSelection(id).name.trim().toLowerCase() != 'codellama:latest',
                            onChanged: EditorController.parseAiModelSelection(id).name.trim().toLowerCase() == 'codellama:latest'
                                ? null
                                : (v) async {
                                    setDialogState(() {
                                      if (v == true) {
                                        hidden.remove(id);
                                      } else {
                                        hidden.add(id);
                                      }
                                    });
                                    await saveHidden();
                                  },
                            title: Text(
                              _modelLabel(id),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        sectionTitle(context.tr('Custom models')),
                        if (customIds.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              context.tr('No custom models'),
                              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        for (var i = 0; i < custom.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_modelLabel(customIds[i]), overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: context.tr('Edit model'),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () async {
                                    final m = custom[i];
                                    final nameController = TextEditingController(text: m.name);
                                    final urlController = TextEditingController(text: m.baseUrl ?? '');
                                    final result = await showDialog<({String name, String url})>(
                                      context: ctx,
                                      builder: (ctx2) => AlertDialog(
                                        title: Text(context.tr('Edit model')),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            TextField(
                                              controller: nameController,
                                              decoration: InputDecoration(labelText: context.tr('Model name')),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: urlController,
                                              decoration: InputDecoration(labelText: context.tr('Base URL (optional)')),
                                            ),
                                          ],
                                        ),
                                        actions: <Widget>[
                                          TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: Text(context.tr('Cancel'))),
                                          FilledButton(
                                            onPressed: () => Navigator.of(ctx2).pop((name: nameController.text.trim(), url: urlController.text.trim())),
                                            child: Text(context.tr('Save')),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (result == null || result.name.isEmpty) return;
                                    await widget.controller.updateCustomAiModel(
                                      oldName: m.name,
                                      oldBaseUrl: m.baseUrl,
                                      newName: result.name,
                                      newBaseUrl: result.url.isEmpty ? null : result.url,
                                    );
                                    final updated = await widget.controller.readCustomAiModels();
                                    setDialogState(() {
                                      custom
                                        ..clear()
                                        ..addAll(updated);
                                    });
                                  },
                                ),
                                IconButton(
                                  tooltip: context.tr('Delete model'),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () async {
                                    final m = custom[i];
                                    await widget.controller.removeCustomAiModel(name: m.name, baseUrl: m.baseUrl);
                                    final updated = await widget.controller.readCustomAiModels();
                                    setDialogState(() {
                                      custom
                                        ..clear()
                                        ..addAll(updated);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final nameController = TextEditingController();
                              final urlController = TextEditingController();
                              final result = await showDialog<({String name, String url})>(
                                context: ctx,
                                builder: (ctx2) => AlertDialog(
                                  title: Text(context.tr('Add model')),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      TextField(
                                        controller: nameController,
                                        decoration: InputDecoration(labelText: context.tr('Model name')),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: urlController,
                                        decoration: InputDecoration(labelText: context.tr('Base URL (optional)')),
                                      ),
                                    ],
                                  ),
                                  actions: <Widget>[
                                    TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: Text(context.tr('Cancel'))),
                                    FilledButton(
                                      onPressed: () => Navigator.of(ctx2).pop((name: nameController.text.trim(), url: urlController.text.trim())),
                                      child: Text(context.tr('Add')),
                                    ),
                                  ],
                                ),
                              );
                              if (result == null || result.name.isEmpty) return;
                              await widget.controller.addCustomAiModel(name: result.name, baseUrl: result.url.isEmpty ? null : result.url);
                              final updated = await widget.controller.readCustomAiModels();
                              setDialogState(() {
                                custom
                                  ..clear()
                                  ..addAll(updated);
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(context.tr('Add model')),
                          ),
                        ),
                        sectionTitle(context.tr('Ignored models')),
                        if (hidden.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              context.tr('No ignored models'),
                              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        for (final id in hidden.toList()..sort())
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_modelLabel(id), overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: context.tr('Restore'),
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              onPressed: () async {
                                setDialogState(() {
                                  hidden.remove(id);
                                });
                                await saveHidden();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(context.tr('Done')),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    await _loadModels();
  }

  Future<void> _addCustomModel() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Add model')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: ctx.tr('Model name'),
                  hintText: 'e.g. llama3.1:8b',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: ctx.tr('Server URL (optional)'),
                  hintText: 'e.g. http://localhost:11434',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              name: nameController.text.trim(),
              url: urlController.text.trim(),
            )),
            child: Text(ctx.tr('Add')),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
    if (result == null || result.name.trim().isEmpty) return;
    final baseUrl = result.url.trim().isEmpty ? null : result.url.trim();
    await widget.controller.addCustomAiModel(name: result.name.trim(), baseUrl: baseUrl);
    final custom = await widget.controller.readCustomAiModels();
    if (!mounted) return;
    final id = _modelId(name: result.name.trim(), baseUrl: baseUrl);
    setState(() {
      _customModels = custom;
      _selectedModelId = id;
      _error = null;
    });
    await widget.controller.writeAiModel(id);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  String _buildPrompt(AiChatSession chat, String userText) {
    final buf = StringBuffer();
    final ctxPath = widget.controller.aiChatContextPath;
    final ctxSource = widget.controller.aiChatContextSource;
    final ctxErrors = widget.controller.aiChatContextErrors;
    if (ctxSource != null && ctxSource.isNotEmpty) {
      buf.writeln('Current file context: ${ctxPath ?? '(unknown)'}');
      if (ctxErrors.isNotEmpty) {
        buf.writeln('Known issues:');
        for (final e in ctxErrors.take(10)) {
          buf.writeln('- $e');
        }
      }
      buf.writeln('```');
      buf.writeln(ctxSource);
      buf.writeln('```');
      buf.writeln();
    }
    buf.writeln('Conversation:');
    for (final m in chat.messages) {
      final role = m.role == AiChatRole.user ? 'User' : 'Assistant';
      buf.writeln('$role:');
      buf.writeln(m.content);
      buf.writeln();
    }
    buf.writeln('User:');
    buf.writeln(userText);
    buf.writeln();
    buf.writeln('Assistant:');
    return buf.toString();
  }

  Future<void> _send([String? textOverride]) async {
    final modelId = _selectedModelId;
    final text = (textOverride ?? _input.text).trim();
    if (modelId == null || text.isEmpty || _busy) return;
    final model = _modelName(modelId);
    final baseUrl = _modelBaseUrl(modelId);
    final chat = widget.controller.activeAiChat;
    if (chat == null) return;
    setState(() {
      _error = null;
      _busy = true;
      _elapsedSeconds = 0;
    });
    if (textOverride == null) _input.clear();
    widget.controller.addAiChatMessage(
      chat.id,
      AiChatMessage(role: AiChatRole.user, content: text, timestamp: DateTime.now()),
    );
    final assistant = AiChatMessage(
      role: AiChatRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );
    widget.controller.addAiChatMessage(chat.id, assistant);
    _scrollToBottom();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    try {
      final prompt = _buildPrompt(chat, text);
      var received = false;
      await for (final chunk in widget.client.generateStream(
        model: model,
        prompt: prompt,
        baseUrl: baseUrl,
        system:
            'You are a helpful coding assistant inside a graphical editor. '
            'Answer clearly. When providing corrected or example code, include it in fenced code blocks.',
      )) {
        if (!mounted) return;
        received = true;
        assistant.content += chunk;
        widget.controller.notifyAiChatsChanged();
        setState(() {});
        _scrollToBottom();
      }
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      if (!received && assistant.content.trim().isEmpty) {
        assistant.content = '(empty response)';
      }
      widget.controller.persistAiChats();
      widget.controller.notifyAiChatsChanged();
      setState(() => _busy = false);
      _scrollToBottom();
    } on AiException catch (e) {
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      if (assistant.content.trim().isEmpty) {
        assistant.content = 'Error: ${e.message}';
      } else {
        _error = e.message;
      }
      widget.controller.persistAiChats();
      widget.controller.notifyAiChatsChanged();
      setState(() => _busy = false);
    } catch (e) {
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      if (assistant.content.trim().isEmpty) {
        assistant.content = 'Error: $e';
      } else {
        _error = e.toString();
      }
      widget.controller.persistAiChats();
      widget.controller.notifyAiChatsChanged();
      setState(() => _busy = false);
    }
  }

  void _newChat() {
    widget.controller.createAiChat(seedFromContext: false);
    setState(() {});
    _scrollToBottom();
  }

  List<String> _extractCodeBlocks(String text) {
    final blocks = <String>[];
    final re = RegExp(r'```[^\n]*\n([\s\S]*?)```', multiLine: true);
    for (final m in re.allMatches(text)) {
      final b = (m.group(1) ?? '').trim();
      if (b.isNotEmpty) blocks.add(b);
    }
    if (blocks.isEmpty && text.trim().isNotEmpty) {
      // fallback: if looks like code, allow apply of whole message
      final t = text.trim();
      if (t.contains('\n') && (t.contains('{') || t.contains(';') || t.contains('<'))) {
        blocks.add(t);
      }
    }
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = widget.controller;
    final chats = controller.aiChats;
    final active = controller.activeAiChat;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.chat_bubble_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('AI chats'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 150,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: OutlinedButton.icon(
                          onPressed: _newChat,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            context.tr('New chat'),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: chats.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    context.tr('No chat selected'),
                                    style: const TextStyle(fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: chats.length,
                                itemBuilder: (context, i) {
                                  final chat = chats[i];
                                  final selected = chat.id == active?.id;
                                  return Material(
                                    color: selected
                                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                                        : Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setState(() => controller.selectAiChat(chat.id)),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                        child: Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                chat.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: context.tr('Close'),
                                              icon: const Icon(Icons.close, size: 14),
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                              onPressed: () => setState(() => controller.deleteAiChat(chat.id)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: _modelPicker(),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                      Expanded(
                        child: active == null
                            ? Center(child: Text(context.tr('No chat selected')))
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.all(8),
                                itemCount: active.messages.length +
                                    (_busy &&
                                            (active.messages.isEmpty ||
                                                active.messages.last.role == AiChatRole.user)
                                        ? 1
                                        : 0),
                                itemBuilder: (context, index) {
                                  final showPending = _busy &&
                                      (active.messages.isEmpty ||
                                          active.messages.last.role == AiChatRole.user);
                                  if (showPending && index == active.messages.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        children: <Widget>[
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('${context.tr('Thinking...')} ${_elapsedSeconds}s',
                                              style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    );
                                  }
                                  final msg = active.messages[index];
                                  return _buildMessage(context, msg);
                                },
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: theme.dividerColor)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: _input,
                                    minLines: 1,
                                    maxLines: 5,
                                    decoration: InputDecoration(
                                      hintText: context.tr('Message AI...'),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 10),
                                    ),
                                    onSubmitted: (_) => _send(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  onPressed: _busy || _selectedModelId == null ? null : _send,
                                  icon: const Icon(Icons.send, size: 18),
                                  tooltip: context.tr('Send'),
                                ),
                              ],
                            ),
                            if (controller.aiChatApply != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    context.tr('Tip: you can apply code blocks from replies to the editor.'),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isMostlyRussian(String text) {
    int cyr = 0;
    int lat = 0;
    for (final r in text.runes) {
      if ((r >= 0x0400 && r <= 0x04FF) || (r >= 0x0500 && r <= 0x052F)) cyr++;
      if ((r >= 0x0041 && r <= 0x005A) || (r >= 0x0061 && r <= 0x007A)) lat++;
    }
    return cyr > 0 && cyr >= lat;
  }

  Future<void> _translateMessage(AiChatMessage msg) async {
    if (_translating.contains(msg)) return;
    if (_translations.containsKey(msg)) {
      setState(() {
        if (_showTranslation.contains(msg)) {
          _showTranslation.remove(msg);
        } else {
          _showTranslation.add(msg);
        }
      });
      return;
    }
    final modelId = _selectedModelId;
    if (modelId == null) return;
    final model = _modelName(modelId);
    final baseUrl = _modelBaseUrl(modelId);
    final toRussian = !_isMostlyRussian(msg.content);
    final prompt = toRussian
        ? 'Переведи следующий текст на русский язык. Сохрани форматирование, код, списки и имена. Верни только перевод.\n\n${msg.content}'
        : 'Translate the following text to English. Preserve formatting, code, lists, and names. Return only the translation.\n\n${msg.content}';
    setState(() {
      _translating.add(msg);
    });
    try {
      final translated = await widget.client.generate(
        model: model,
        prompt: prompt,
        baseUrl: baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _translations[msg] = translated.trim();
        _showTranslation.add(msg);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _translating.remove(msg);
        });
      }
    }
  }

  Widget _buildMessage(BuildContext context, AiChatMessage msg) {
    final theme = Theme.of(context);
    final isUser = msg.role == AiChatRole.user;
    final bg = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final blocks = !isUser ? _extractCodeBlocks(msg.content) : const <String>[];
    final showingTranslation = _showTranslation.contains(msg);
    final displayedContent = showingTranslation ? (_translations[msg] ?? msg.content) : msg.content;
    final activeChat = widget.controller.activeAiChat;
    final isStreaming = _busy &&
        !isUser &&
        activeChat != null &&
        activeChat.messages.isNotEmpty &&
        identical(activeChat.messages.last, msg);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: (!isUser && msg.content.trim().isEmpty && _busy)
                ? _ThinkingIndicator(elapsedSeconds: _elapsedSeconds)
                : _AssistantMessageContent(text: displayedContent),
          ),
          if (!isUser && msg.content.trim().isNotEmpty && !isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: displayedContent));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('AI result copied to clipboard.')),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: Text(context.tr('Copy')),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _translating.contains(msg)
                        ? null
                        : () => _translateMessage(msg),
                    icon: _translating.contains(msg)
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.translate, size: 14),
                    label: Text(
                      _translating.contains(msg)
                          ? context.tr('Translating...')
                          : showingTranslation
                              ? context.tr('Show original')
                              : _isMostlyRussian(msg.content)
                                  ? context.tr('Translate to English')
                                  : context.tr('Translate to Russian'),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  if (blocks.isNotEmpty && widget.controller.aiChatApply != null)
                    FilledButton.icon(
                      onPressed: () => widget.controller.applyAiFixResult(blocks.last),
                      icon: const Icon(Icons.check, size: 14),
                      label: Text(context.tr('Apply to editor')),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _modelPicker() {
    if (_loadingModels) {
      return const SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final all = _allModelIdsCurrent;
    final value = all.contains(_selectedModelId) ? _selectedModelId : (all.isEmpty ? null : all.first);
    final label = value == null ? context.tr('Model') : _modelLabel(value);

    return Align(
      alignment: Alignment.centerLeft,
      child: MenuAnchor(
        builder: (context, controller, child) {
          return OutlinedButton.icon(
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            icon: const Icon(Icons.smart_toy_outlined, size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
        menuChildren: <Widget>[
          if (all.isEmpty)
            MenuItemButton(
              onPressed: null,
              child: Text(context.tr('No models found. Is Ollama running?')),
            ),
          for (final id in all)
            MenuItemButton(
              onPressed: () {
                setState(() => _selectedModelId = id);
                widget.controller.writeAiModel(id);
              },
              leadingIcon: Icon(
                id == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
              ),
              child: Text(_modelLabel(id), overflow: TextOverflow.ellipsis),
            ),
          const Divider(height: 8),
          MenuItemButton(
            onPressed: _showManageModelsDialog,
            leadingIcon: const Icon(Icons.tune, size: 18),
            child: Text(context.tr('Manage models')),
          ),
          MenuItemButton(
            onPressed: _addCustomModel,
            leadingIcon: const Icon(Icons.add, size: 18),
            child: Text(context.tr('Add model')),
          ),
          if (value != null && _isCustomModelId(value)) ...<Widget>[
            MenuItemButton(
              onPressed: _editSelectedCustomModel,
              leadingIcon: const Icon(Icons.edit_outlined, size: 18),
              child: Text(context.tr('Edit model')),
            ),
            MenuItemButton(
              onPressed: _removeSelectedCustomModel,
              leadingIcon: const Icon(Icons.delete_outline, size: 18),
              child: Text(context.tr('Delete model')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.elapsedSeconds});
  final int elapsedSeconds;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 36,
          height: 16,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List<Widget>.generate(3, (i) {
                  final t = (_controller.value - i * 0.2) % 1.0;
                  final scale = 0.45 + 0.55 * (0.5 - (t - 0.5).abs()) * 2;
                  final opacity = 0.35 + 0.65 * (0.5 - (t - 0.5).abs()) * 2;
                  return Opacity(
                    opacity: opacity.clamp(0.25, 1.0),
                    child: Transform.scale(
                      scale: scale.clamp(0.5, 1.0),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${context.tr('Thinking...')} ${widget.elapsedSeconds}s',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
class _AssistantMessageContent extends StatelessWidget {
  const _AssistantMessageContent({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final segments = _parseSegments(text);
    if (segments.isEmpty) {
      return SelectableText(text, style: const TextStyle(fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final seg in segments)
          if (seg.isCode)
            _CodeBlock(code: seg.content, language: seg.language)
          else if (seg.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MarkdownText(text: seg.content.trim()),
            ),
      ],
    );
  }

  static List<_MessageSegment> _parseSegments(String text) {
    final re = RegExp(r'```([^\n`]*)\n?([\s\S]*?)```', multiLine: true);
    final segments = <_MessageSegment>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        final plain = text.substring(last, m.start);
        if (plain.trim().isNotEmpty) {
          segments.add(_MessageSegment(content: plain, isCode: false));
        }
      }
      final lang = (m.group(1) ?? '').trim();
      final code = (m.group(2) ?? '').replaceAll(RegExp(r'\n$'), '');
      segments.add(_MessageSegment(content: code, isCode: true, language: lang));
      last = m.end;
    }
    if (last < text.length) {
      final tail = text.substring(last);
      if (tail.trim().isNotEmpty) {
        segments.add(_MessageSegment(content: tail, isCode: false));
      }
    }
    if (segments.isEmpty && text.trim().isNotEmpty) {
      segments.add(_MessageSegment(content: text, isCode: false));
    }
    return segments;
  }
}

class _MessageSegment {
  const _MessageSegment({required this.content, required this.isCode, this.language = ''});
  final String content;
  final bool isCode;
  final String language;
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language});
  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA);
    final border = isDark ? const Color(0xFF3C3C3C) : const Color(0xFFD0D7DE);
    final headerBg = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEAEEF2);
    final label = language.isEmpty ? 'code' : language;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('AI result copied to clipboard.')),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.copy, size: 13, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('Copy'),
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF24292F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      final t = para.join('\n').trim();
      para.clear();
      if (t.isEmpty) return;
      children.add(SelectableText.rich(
        _inlineSpans(t, theme),
        style: const TextStyle(fontSize: 13, height: 1.4),
      ));
    }

    for (final raw in lines) {
      final line = raw;
      final mHeading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line.trimLeft());
      final mBullet = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(line);
      final mNum = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (mHeading != null) {
        flushPara();
        final level = mHeading.group(1)!.length;
        final content = mHeading.group(2) ?? '';
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        final fontSize = switch (level) {
          1 => 18.0,
          2 => 16.0,
          3 => 14.5,
          4 => 13.5,
          _ => 13.0,
        };
        children.add(SelectableText.rich(
          _inlineSpans(content, theme, boldAll: true),
          style: TextStyle(fontSize: fontSize, height: 1.3, fontWeight: FontWeight.w700),
        ));
      } else if (mBullet != null) {
        flushPara();
        final indent = (mBullet.group(1) ?? '').length;
        final content = mBullet.group(2) ?? '';
        children.add(_listItem(context, '•', content, indent));
      } else if (mNum != null) {
        flushPara();
        final indent = (mNum.group(1) ?? '').length;
        final num = mNum.group(2) ?? '1';
        final content = mNum.group(3) ?? '';
        children.add(_listItem(context, '$num.', content, indent));
      } else if (line.trim().isEmpty) {
        flushPara();
        if (children.isNotEmpty) children.add(const SizedBox(height: 4));
      } else {
        para.add(line);
      }
    }
    flushPara();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _listItem(BuildContext context, String marker, String content, int indent) {
    final theme = Theme.of(context);
    final leftPad = (indent ~/ 2) * 14.0;
    final isKey = content.trim().endsWith(':') && content.trim().length < 60;
    return Padding(
      padding: EdgeInsets.only(left: leftPad, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 18,
            child: Text(
              marker,
              style: TextStyle(fontSize: 13, height: 1.4, color: theme.colorScheme.primary),
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              _inlineSpans(content, theme, boldAll: isKey),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  static TextSpan _inlineSpans(String text, ThemeData theme, {bool boldAll = false}) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'`([^`]+)`');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        _appendFormattedText(spans, text.substring(last, m.start));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          color: theme.colorScheme.onSurface,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      _appendFormattedText(spans, text.substring(last));
    }
    if (spans.isEmpty) _appendFormattedText(spans, text);
    return TextSpan(
      style: TextStyle(fontWeight: boldAll ? FontWeight.w600 : FontWeight.normal),
      children: spans,
    );
  }

  static void _appendFormattedText(List<InlineSpan> spans, String text) {
    final boldRe = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
    var last = 0;
    for (final m in boldRe.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final boldText = m.group(1) ?? m.group(2) ?? '';
      spans.add(TextSpan(
        text: boldText,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    if (last == 0 && text.isEmpty) {
      spans.add(const TextSpan(text: ''));
    }
  }
}
