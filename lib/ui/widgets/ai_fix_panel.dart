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

  List<String> _models = const <String>[];
  String? _selectedModel;
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
    try {
      final models = await widget.client.listModels();
      final saved = await widget.controller.readAiModel();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        if (saved != null && models.contains(saved)) {
          _selectedModel = saved;
        } else if (models.isNotEmpty) {
          _selectedModel = models.first;
        }
      });
      if (_selectedModel != null) {
        await widget.controller.writeAiModel(_selectedModel!);
      }
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _error = error.toString();
      });
    }
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
    final model = _selectedModel;
    final text = _input.text.trim();
    if (model == null || text.isEmpty || _busy) return;
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
    _scrollToBottom();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    try {
      final prompt = _buildPrompt(chat, text);
      final reply = await widget.client.generate(
        model: model,
        prompt: prompt,
        system:
            'You are a helpful coding assistant inside a graphical editor. '
            'Answer clearly. When providing corrected or example code, include it in fenced code blocks.',
      );
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      widget.controller.addAiChatMessage(
        chat.id,
        AiChatMessage(
          role: AiChatRole.assistant,
          content: reply.trim().isEmpty ? '(empty response)' : reply.trim(),
          timestamp: DateTime.now(),
        ),
      );
      setState(() => _busy = false);
      _scrollToBottom();
    } on AiException catch (e) {
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      _timer?.cancel();
      _timer = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
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
                  tooltip: context.tr('New chat'),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: _newChat,
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
          if (chats.length > 1 || chats.isNotEmpty)
            Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                itemCount: chats.length,
                separatorBuilder: (context, index) => const SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final chat = chats[i];
                  final selected = chat.id == active?.id;
                  return InputChip(
                    label: SizedBox(
                      width: 110,
                      child: Text(chat.title, overflow: TextOverflow.ellipsis),
                    ),
                    selected: selected,
                    onPressed: () => setState(() => controller.selectAiChat(chat.id)),
                    onDeleted: () => setState(() => controller.deleteAiChat(chat.id)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                },
              ),
            ),
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
                    itemCount: active.messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_busy && index == active.messages.length) {
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
                      onPressed: _busy || _selectedModel == null ? null : _send,
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
    if (_models.isEmpty) {
      return Text(
        context.tr('No models found. Is Ollama running?'),
        style: const TextStyle(fontSize: 12),
      );
    }
    return DropdownButton<String>(
      value: _selectedModel,
      isExpanded: true,
      isDense: true,
      items: <DropdownMenuItem<String>>[
        for (final model in _models)
          DropdownMenuItem<String>(value: model, child: Text(model, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        setState(() => _selectedModel = value);
        if (value != null) widget.controller.writeAiModel(value);
      },
    );
  }
}
