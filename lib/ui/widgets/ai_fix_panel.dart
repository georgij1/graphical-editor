import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ollama_client.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

class AiFixPanel extends StatefulWidget {
  AiFixPanel({
    super.key,
    required this.controller,
    required this.path,
    required this.source,
    required this.errors,
    required this.onApply,
    required this.onClose,
    AiClient? client,
  }) : client = client ?? AiClient();

  final EditorController controller;
  final String path;
  final String source;
  final List<String> errors;
  final void Function(String fixed) onApply;
  final VoidCallback onClose;
  final AiClient client;

  @override
  State<AiFixPanel> createState() => _AiFixPanelState();
}

class _AiFixPanelState extends State<AiFixPanel> {
  final TextEditingController _instruction = TextEditingController();
  final TextEditingController _result = TextEditingController();

  List<String> _models = const <String>[];
  String? _selectedModel;
  bool _loadingModels = true;
  bool _busy = false;
  String? _error;
  String? _resultText;
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _cancelled = false;
  String _sourceSnapshot = '';
  List<String> _errorsSnapshot = const <String>[];

  @override
  void initState() {
    super.initState();
    _sourceSnapshot = widget.source;
    _errorsSnapshot = List<String>.from(widget.errors);
    _loadModels();
  }

  @override
  void didUpdateWidget(covariant AiFixPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If opened for a different file/context, reset result and snapshot.
    if (oldWidget.path != widget.path ||
        oldWidget.source != widget.source ||
        oldWidget.errors.join('\n') != widget.errors.join('\n')) {
      _timer?.cancel();
      _timer = null;
      _busy = false;
      _error = null;
      _resultText = null;
      _result.clear();
      _elapsedSeconds = 0;
      _sourceSnapshot = widget.source;
      _errorsSnapshot = List<String>.from(widget.errors);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _instruction.dispose();
    _result.dispose();
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

  Future<void> _fix() async {
    final model = _selectedModel;
    if (model == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _elapsedSeconds = 0;
      _cancelled = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    try {
      final fixed = await widget.client.fixSource(
        model: model,
        path: widget.path,
        source: _sourceSnapshot,
        errors: _errorsSnapshot,
        instruction: _instruction.text,
      );
      _timer?.cancel();
      _timer = null;
      if (!mounted || _cancelled) return;
      setState(() {
        _busy = false;
        _resultText = fixed;
        _result.text = fixed;
      });
    } on AiException catch (error) {
      _timer?.cancel();
      _timer = null;
      if (!mounted || _cancelled) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      _timer?.cancel();
      _timer = null;
      if (!mounted || _cancelled) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  void _cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.auto_fix_high, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('Fix with AI'),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.fileLabel(widget.path),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (_errorsSnapshot.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final error in _errorsSnapshot.take(8))
                            Text('• $error', style: const TextStyle(fontSize: 12)),
                          if (_errorsSnapshot.length > 8)
                            Text('… +${_errorsSnapshot.length - 8}',
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(context.tr('Model:'), style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(child: _modelPicker()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _instruction,
                    decoration: InputDecoration(
                      labelText: context.tr('Extra instruction (optional)'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _busy
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text(context.tr('Asking the local model:')),
                                  const SizedBox(height: 6),
                                  Text('$_elapsedSeconds s',
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _cancel,
                                    child: Text(context.tr('Cancel')),
                                  ),
                                ],
                              ),
                            )
                          : TextField(
                              controller: _result,
                              readOnly: true,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: _resultText == null
                                    ? context.tr('The corrected source will appear here.')
                                    : null,
                                contentPadding: const EdgeInsets.all(8),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: _resultText == null
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: _resultText!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(context
                                        .tr('AI result copied to clipboard.')),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                        child: Text(context.tr('Copy')),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || _selectedModel == null ? null : _fix,
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: Text(context.tr('Fix')),
                      ),
                      FilledButton(
                        onPressed: _resultText == null
                            ? null
                            : () => widget.onApply(_resultText!),
                        child: Text(context.tr('Apply to editor')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelPicker() {
    if (_loadingModels) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('Loading models:'),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
      items: <DropdownMenuItem<String>>[
        for (final model in _models)
          DropdownMenuItem<String>(value: model, child: Text(model)),
      ],
      onChanged: (value) {
        setState(() => _selectedModel = value);
        if (value != null) widget.controller.writeAiModel(value);
      },
    );
  }
}
