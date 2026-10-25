import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ollama_client.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';

/// Opens the "fix with AI" dialog and returns the corrected source, or null if
/// the user cancelled.
Future<String?> showAiFixDialog(
  BuildContext context, {
  required EditorController controller,
  required String path,
  required String source,
  required List<String> errors,
  AiClient? client,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AiFixDialog(
      controller: controller,
      path: path,
      source: source,
      errors: errors,
      client: client ?? AiClient(),
    ),
  );
}

class _AiFixDialog extends StatefulWidget {
  const _AiFixDialog({
    required this.controller,
    required this.path,
    required this.source,
    required this.errors,
    required this.client,
  });

  final EditorController controller;
  final String path;
  final String source;
  final List<String> errors;
  final AiClient client;

  @override
  State<_AiFixDialog> createState() => _AiFixDialogState();
}

class _AiFixDialogState extends State<_AiFixDialog> {
  final TextEditingController _instruction = TextEditingController();
  final TextEditingController _result = TextEditingController();

  List<String> _models = const <String>[];
  String? _selectedModel;
  bool _loadingModels = true;
  bool _busy = false;
  String? _error;
  String? _resultText;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
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
        _selectedModel = models.contains(saved) ? saved : (models.isNotEmpty ? models.first : null);
        _loadingModels = false;
      });
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _error = error.message;
      });
    }
  }

  Future<void> _fix() async {
    final model = _selectedModel;
    if (model == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.writeAiModel(model);
      final fixed = await widget.client.fixSource(
        model: model,
        path: widget.path,
        source: widget.source,
        errors: widget.errors,
        instruction: _instruction.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resultText = fixed;
        _result.text = fixed;
      });
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
title: Row(
        children: <Widget>[
          const Icon(Icons.auto_fix_high, size: 20),
          const SizedBox(width: 8),
          Text(context.tr('Fix with AI')),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.fileLabel(widget.path),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (widget.errors.isNotEmpty)
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
                    for (final error in widget.errors)
                      Text('• $error', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(context.tr('Model:'), style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(child: _modelPicker()),
              ],
            ),
            const SizedBox(height: 12),
TextField(
              controller: _instruction,
              decoration: InputDecoration(
                labelText: context.tr('Extra instruction (optional)'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ],
            const SizedBox(height: 12),
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
                            Text(context.tr('Asking the local model…')),
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
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _resultText == null
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: _resultText!));
ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('AI result copied to clipboard.')),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
          child: Text(context.tr('Copy')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
        FilledButton.icon(
          onPressed: _busy || _selectedModel == null ? null : _fix,
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: Text(context.tr('Fix')),
        ),
        FilledButton(
          onPressed: _resultText == null
              ? null
              : () => Navigator.of(context).pop(_resultText),
          child: Text(context.tr('Apply to editor')),
        ),
      ],
    );
  }

Widget _modelPicker() {
    if (_loadingModels) {
      return Row(
        children: <Widget>[
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(context.tr('Loading models…'), style: const TextStyle(fontSize: 12)),
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
      onChanged: (value) => setState(() => _selectedModel = value),
    );
  }
}
