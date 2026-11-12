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
  String? _selectedModelId;
  bool _loadingModels = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
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
    final saved = await widget.controller.readAiModel();
    if (!mounted) return;
    final allIds = _allModelIds(remote: remote, custom: custom, savedId: saved);
    String? selected = saved;
    if (selected == null || (allIds.isNotEmpty && !allIds.contains(selected))) {
      selected = allIds.isNotEmpty ? allIds.first : saved;
    }
    setState(() {
      _remoteModels = remote;
      _customModels = custom;
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
    String? savedId,
  }) {
    final out = <String>[];
    final seen = <String>{};
    void addId(String? id) {
      final s = (id ?? '').trim();
      if (s.isEmpty || !seen.add(s)) return;
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
      _allModelIds(remote: _remoteModels, custom: _customModels, savedId: _selectedModelId);

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
    final allIds = _allModelIds(remote: _remoteModels, custom: custom, savedId: null);
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

  Future<void> _send() async {
    final modelId = _selectedModelId;
    final text = _input.text.trim();
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
    _input.clear();
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
                        child: Row(
                          children: <Widget>[
                            Text(context.tr('Model:'), style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 6),
                            Expanded(child: _modelPicker()),
                          ],
                        ),
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

  Widget _buildMessage(BuildContext context, AiChatMessage msg) {
    final theme = Theme.of(context);
    final isUser = msg.role == AiChatRole.user;
    final bg = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final blocks = !isUser ? _extractCodeBlocks(msg.content) : const <String>[];
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
            child: SelectableText(
              msg.content,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: msg.content));
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
        height: 20,
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
    if (all.isEmpty) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(
              context.tr('No models found. Is Ollama running?'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: context.tr('Add model'),
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: _addCustomModel,
          ),
        ],
      );
    }
    final value = all.contains(_selectedModelId) ? _selectedModelId : all.first;
    return Row(
      children: <Widget>[
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            items: <DropdownMenuItem<String>>[
              for (final id in all)
                DropdownMenuItem<String>(
                  value: id,
                  child: Text(_modelLabel(id), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              setState(() => _selectedModelId = v);
              if (v != null) widget.controller.writeAiModel(v);
            },
          ),
        ),
        IconButton(
          tooltip: context.tr('Add model'),
          icon: const Icon(Icons.add, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: _addCustomModel,
        ),
        if (_isCustomModelId(value))
          IconButton(
            tooltip: context.tr('Delete model'),
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: _removeSelectedCustomModel,
          ),
      ],
    );
  }
}
