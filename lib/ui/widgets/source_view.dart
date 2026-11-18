import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';

import '../../editor/code_validator.dart';
import '../../editor/editor_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../project/project_history.dart';
import 'highlighting_text_controller.dart';

/// Editable text editor for the file currently selected in the project tree:
/// the active scene's FXML or a generated Java source. Replaces the canvas
/// while the "Code" tab is active. The content is validated as it is typed.
class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.controller});

  final EditorController controller;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  late final HighlightingTextEditingController _text =
      HighlightingTextEditingController(
    text: widget.controller.codeContent,
  );
  final FocusNode _focusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();
  late ValidationResult _validation = _validate(_text.text);
  int _lastEpoch = 0;
  String? _loadedPath;
  String _loadedContent = '';
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = <String>[];
  Timer? _autoApplyTimer;
  Timer? _remoteCheckTimer;
  bool _suppressChange = false;
  bool _syncingScroll = false;
  final ValueNotifier<Rect?> _currentLineRect = ValueNotifier<Rect?>(null);
  double _editorTextWidth = 0;
  bool _lineRectScheduled = false;
  int _remoteCheckSeq = 0;
  List<ValidationIssue> _remoteIssues = const <ValidationIssue>[];
  bool _remoteCheckInProgress = false;
  final Map<String, List<_CheckSnapshot>> _checkHistoryByPath = <String, List<_CheckSnapshot>>{};

  static const List<String> _javaSuggestions = <String>[
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'float',
    'for',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'new',
    'null',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'try',
    'void',
    'volatile',
    'while',
    'true',
    'false',
    'String',
    'Integer',
    'Long',
    'Double',
    'Float',
    'Boolean',
    'Object',
    'List',
    'Map',
    'Set',
    'Optional',
    'Override',
    'Deprecated',
    'SuppressWarnings',
    '@FXML',
    '@Override',
    '@Deprecated',
    'System.out.println()',
    'public static void main(String[] args)',
    'private',
    'protected',
    'public class',
    'public void',
    'private void',
    'return;',
  ];

  bool get _isJava => widget.controller.codeIsJavaSource;
  bool get _isXml =>
      widget.controller.codeIsXmlSource || widget.controller.openSource == null;

  ValidationResult _validate(String source) {
    if (_isJava) {
      return CodeValidator.validateJava(source, path: widget.controller.codePath);
    }
    if (_isXml) {
      return CodeValidator.validateFxml(source);
    }
    return ValidationResult.valid;
  }

  bool get _supportsRemoteCheck {
    if (widget.controller.currentProject == null) return false;
    final p = widget.controller.codePath.toLowerCase();
    return p.endsWith('.java') ||
        p.endsWith('.sh') ||
        p.endsWith('.bash') ||
        p.endsWith('.bat') ||
        p.endsWith('.cmd');
  }

  ValidationResult get _effectiveValidation {
    if (_remoteIssues.isEmpty) return _validation;
    final merged = <ValidationIssue>[..._validation.issues, ..._remoteIssues];
    return ValidationResult(merged);
  }

  void _scheduleRemoteCheck() {
    _remoteCheckTimer?.cancel();
    if (!_supportsRemoteCheck) {
      if ((_remoteIssues.isNotEmpty || _remoteCheckInProgress) && mounted) {
        setState(() {
          _remoteIssues = const <ValidationIssue>[];
          _remoteCheckInProgress = false;
        });
      } else {
        _remoteIssues = const <ValidationIssue>[];
        _remoteCheckInProgress = false;
      }
      return;
    }
    final path = widget.controller.codePath;
    final content = _text.text;
    if (!_remoteCheckInProgress && mounted) {
      setState(() {
        _remoteCheckInProgress = true;
      });
    } else {
      _remoteCheckInProgress = true;
    }
    _remoteCheckTimer = Timer(const Duration(milliseconds: 900), () {
      _runRemoteCheck(path: path, content: content);
    });
  }

  Future<void> _runRemoteCheck({required String path, required String content}) async {
    if (!mounted || !_supportsRemoteCheck) {
      if (mounted && _remoteCheckInProgress) {
        setState(() {
          _remoteCheckInProgress = false;
        });
      } else {
        _remoteCheckInProgress = false;
      }
      return;
    }
    final seq = ++_remoteCheckSeq;
    try {
      final diagnostics = await widget.controller.runBackendCheck(
        path: path,
        content: content,
      );
      if (!mounted || seq != _remoteCheckSeq) return;
      if (widget.controller.codePath != path) return;
      bool matchesPath(String diagFile, String currentPath) {
        String norm(String s) => s.replaceAll('\\', '/');
        final df = norm(diagFile);
        final cp = norm(currentPath);
        if (df == cp) return true;
        if (df.endsWith('/$cp') || cp.endsWith('/$df')) return true;
        // Handle cases where one side includes project/archive root prefixes.
        if (df.endsWith(cp) && (df.length == cp.length || df[df.length - cp.length - 1] == '/')) return true;
        if (cp.endsWith(df) && (cp.length == df.length || cp[cp.length - df.length - 1] == '/')) return true;
        final dfBase = df.split('/').last;
        final cpBase = cp.split('/').last;
        if (dfBase == cpBase && (df == cpBase || cp == dfBase)) return true;
        return false;
      }

      final current = diagnostics
          .where((d) => matchesPath(d.file, path))
          .map((d) => ValidationIssue(
                d.message,
                line: d.line,
                column: d.column,
                severity: d.isError ? ValidationSeverity.error : ValidationSeverity.warning,
              ))
          .toList();
      setState(() {
        _remoteIssues = current;
        _remoteCheckInProgress = false;
        final history = _checkHistoryByPath.putIfAbsent(
          path,
          () => <_CheckSnapshot>[],
        );
        history.insert(
          0,
          _CheckSnapshot(
            time: DateTime.now(),
            issues: List<ValidationIssue>.unmodifiable(current),
          ),
        );
        if (history.length > 20) {
          history.removeRange(20, history.length);
        }
      });
      // Persist check/compilation result for this file on the server (best effort).
      // ignore: discarded_futures
      widget.controller.recordFileCheck(file: path, diagnostics: diagnostics);
    } catch (_) {
      if (!mounted || seq != _remoteCheckSeq) return;
      setState(() {
        _remoteCheckInProgress = false;
      });
      // Backend unavailable or check failed: keep local validation only.
    }
  }

  HighlightLanguage get _highlightLanguage {
    final path = widget.controller.codePath.toLowerCase();
    if (path.endsWith('.sh') || path.endsWith('.bash')) {
      return HighlightLanguage.shell;
    }
    if (path.endsWith('.bat') || path.endsWith('.cmd')) {
      return HighlightLanguage.batch;
    }
    if (path.endsWith('.css')) return HighlightLanguage.css;
    if (_isXml) {
      return HighlightLanguage.xml;
    }
    if (_isJava || path.endsWith('.java')) return HighlightLanguage.java;
    return HighlightLanguage.plain;
  }

  void _syncHighlighting() {
    final lang = _highlightLanguage;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final changed = _text.language != lang || _text.dark != dark;
    _text.language = lang;
    _text.dark = dark;
    if (changed) {
      // HighlightingTextEditingController's custom fields don't notify on their own.
      _text.refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _lastEpoch = widget.controller.codeEpoch;
    _loadedPath = widget.controller.codePath;
    _loadedContent = widget.controller.codeContent;
    _text.addListener(_onChanged);
    _text.addListener(_scheduleCurrentLineUpdate);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
    _focusNode.onKeyEvent = _handleKeyEvent;
    _editorScrollController.addListener(_onEditorScroll);
    _editorScrollController.addListener(_onEditorViewportChanged);
    widget.controller.aiFixHandler = _fixWithAi;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncHighlighting();
        _updateCurrentLineRect();
        _scheduleRemoteCheck();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHighlighting();
  }

  @override
  void dispose() {
    _flushAutoApply(forLoadedFile: true);
    _remoteCheckTimer?.cancel();
    _remoteCheckInProgress = false;
    _hideSuggestions();
    if (identical(widget.controller.aiFixHandler, _fixWithAi)) {
      widget.controller.aiFixHandler = null;
    }
    _editorScrollController.removeListener(_onEditorScroll);
    _editorScrollController.removeListener(_onEditorViewportChanged);
    widget.controller.removeListener(_onControllerChanged);
    _text.removeListener(_onChanged);
    _text.removeListener(_scheduleCurrentLineUpdate);
    _focusNode.removeListener(_onFocusChanged);
    _text.dispose();
    _focusNode.dispose();
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    _currentLineRect.dispose();
    super.dispose();
  }

  void _flushAutoApply({bool forLoadedFile = false}) {
    _autoApplyTimer?.cancel();
    _autoApplyTimer = null;
    if (!widget.controller.isAutoSaveMode) return;
    if (!_validation.isValid) return;
    final text = _text.text;
    if (text == _loadedContent) return;
    final path = _loadedPath;
    if (forLoadedFile && path != null) {
      widget.controller.applyCodeToPath(path, text);
      if (path == widget.controller.codePath) {
        _loadedContent = widget.controller.codeContent;
      }
      return;
    }
    if (path != null) {
      widget.controller.applyCodeToPath(path, text);
    } else {
      widget.controller.applyCode(text);
    }
    if (path == widget.controller.codePath) {
      _loadedContent = widget.controller.codeContent;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.codeEpoch;
    if (epoch != _lastEpoch) {
      // Save pending edits for the file that was loaded before switching.
      _flushAutoApply(forLoadedFile: true);
      _lastEpoch = epoch;
      _loadedPath = widget.controller.codePath;
      _loadedContent = widget.controller.codeContent;
      _suppressChange = true;
      _text.text = _loadedContent;
      _suppressChange = false;
      _validation = _validate(_text.text);
      _remoteIssues = const <ValidationIssue>[];
      _remoteCheckInProgress = false;
      _remoteCheckSeq++;
      _syncHighlighting();
      setState(() {});
      _scheduleRemoteCheck();
    } else {
      // If controller updated current file content externally, keep baseline in sync.
      if (widget.controller.codePath == _loadedPath &&
          _text.text == widget.controller.codeContent) {
        _loadedContent = widget.controller.codeContent;
      }
      _syncHighlighting();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _unindentSelection();
      } else {
        _insertTextAtSelection('    ');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertTextAtSelection(String insert) {
    final value = _text.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start;
    final end = selection.end;
    final newText = value.text.replaceRange(start, end, insert);
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  void _unindentSelection() {
    final value = _text.value;
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final offset = selection.baseOffset;
    final text = value.text;
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    if (lineStart < 0 || lineStart >= text.length) return;
    int remove = 0;
    if (text.startsWith('    ', lineStart)) {
      remove = 4;
    } else if (text.startsWith('\t', lineStart)) {
      remove = 1;
    } else if (text.startsWith('  ', lineStart)) {
      remove = 2;
    } else if (text.startsWith(' ', lineStart)) {
      remove = 1;
    }
    if (remove == 0) return;
    final newText = text.replaceRange(lineStart, lineStart + remove, '');
    final newOffset = (offset - remove).clamp(lineStart, newText.length);
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  void _onEditorScroll() {
    if (_syncingScroll) return;
    if (!_gutterScrollController.hasClients) return;
    _syncingScroll = true;
    _gutterScrollController.jumpTo(
      _editorScrollController.offset.clamp(
        0.0,
        _gutterScrollController.position.maxScrollExtent,
      ),
    );
    _syncingScroll = false;
    _scheduleCurrentLineUpdate();
  }

  void _onChanged() {
    if (_suppressChange) return;
    setState(() {
      _validation = _validate(_text.text);
    });
    _updateSuggestions();
    _scheduleAutoApply();
    _scheduleRemoteCheck();
  }

  void _onEditorViewportChanged() {
    _scheduleCurrentLineUpdate();
  }

  void _scheduleCurrentLineUpdate() {
    if (_lineRectScheduled || !mounted) return;
    _lineRectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lineRectScheduled = false;
      if (!mounted) return;
      _updateCurrentLineRect();
    });
  }

  void _updateCurrentLineRect() {
    if (!mounted) return;
    final selection = _text.selection;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: dark ? const Color(0xFFE6E6E6) : const Color(0xFF1F1F1F),
    );

    Rect? lineRect;
    if (selection.isValid &&
        _focusNode.hasFocus &&
        _editorScrollController.hasClients &&
        _editorTextWidth > 0) {
      try {
        final painter = TextPainter(
          text: TextSpan(text: _text.text, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        final maxWidth = (_editorTextWidth - 32).clamp(0.0, double.infinity);
        painter.layout(maxWidth: maxWidth);
        final offset = selection.baseOffset.clamp(0, _text.text.length);
        final caret = painter.getOffsetForCaret(
          TextPosition(offset: offset),
          Rect.zero,
        );
        final scroll = _editorScrollController.offset;
        final lineHeight = painter.preferredLineHeight;
        var top = 16 + caret.dy - scroll;
        var height = lineHeight;
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset),
        );
        if (boxes.isNotEmpty) {
          final b = boxes.first;
          top = 16 + b.top - scroll;
          height = (b.bottom - b.top).abs();
        }
        if (height.isFinite && !height.isNaN && height > 0) {
          height = height.clamp(10.0, 32.0);
          if (top.isFinite && !top.isNaN) {
            final bottom = top + height;
            if (bottom >= -4 && top <= 100000) {
              lineRect = Rect.fromLTWH(0, top, _editorTextWidth, height);
            }
          }
        }
      } catch (_) {
        lineRect = null;
      }
    }

    if (_currentLineRect.value != lineRect) {
      _currentLineRect.value = lineRect;
    }
  }

  void _scheduleAutoApply() {
    _autoApplyTimer?.cancel();
    if (!widget.controller.isAutoSaveMode) return;
    final text = _text.text;
    if (text == _loadedContent) return;
    _autoApplyTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (!widget.controller.isAutoSaveMode) return;
      if (_text.text != text) return;
      if (_text.text == _loadedContent) return;
      if (!_validation.isValid) return;
      final path = _loadedPath;
      if (path != null) {
        widget.controller.applyCodeToPath(path, _text.text);
      } else {
        widget.controller.applyCode(_text.text);
      }
      if (path == widget.controller.codePath) {
        _loadedContent = widget.controller.codeContent;
      }
    });
  }

  bool _apply() {
    final controller = widget.controller;
    if (!_validation.isValid) {
      final error = _validation.errors.first;
      _showMessage(
        context.l10n.issueLocation(error.line, error.column) +
            error.render(context.tr),
      );
      return false;
    }
    final ok = controller.applyCode(_text.text);
    setState(() {
      _validation = _validate(_text.text);
    });
    _showMessage(
      ok
          ? (_isJava
                ? context.tr('Java source applied.')
                : (_isXml
                      ? context.tr('FXML applied.')
                      : context.tr('Source applied.')))
          : context.tr('Invalid FXML — not applied.'),
    );
    return ok;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _fixWithAi() async {
    final controller = widget.controller;
    controller.openAiFixPanel(
      path: controller.codePath,
      source: _text.text,
      errors: _effectiveValidation.issues.map((i) => i.toString()).toList(),
      onApply: (fixed) {
        if (!mounted) return;
        setState(() {
          _text.text = fixed;
          _validation = _validate(fixed);
          _remoteIssues = const <ValidationIssue>[];
        });
        _scheduleRemoteCheck();
        controller.closeAiFixPanel();
        _showMessage(context.tr('AI suggestion loaded. Review and Apply.'));
      },
    );
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hideSuggestions();
      _flushAutoApply(forLoadedFile: true);
      _currentLineRect.value = null;
    } else {
      // Defer highlight repaint so focus/caret placement isn't delayed.
      _scheduleCurrentLineUpdate();
    }
  }

  void _updateSuggestions() {
    _hideSuggestions();
    if (!_focusNode.hasFocus) return;
    // Show suggestions only for Java source editing.
    final path = widget.controller.codePath.toLowerCase();
    if (!widget.controller.codeIsJavaSource && !path.endsWith('.java')) {
      return;
    }
    final text = _text.text;
    final sel = _text.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) return;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) return;

    var start = cursor;
    while (start > 0) {
      final c = text.codeUnitAt(start - 1);
      final isAlpha = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
      final isDigit = c >= 48 && c <= 57;
      final isOther = c == 95 || c == 36 || c == 64; // _ $ @
      if (isAlpha || isDigit || isOther) {
        start--;
      } else {
        break;
      }
    }
    final prefix = text.substring(start, cursor);
    if (prefix.isEmpty) return;

    final lower = prefix.toLowerCase();
    final matches = <String>[];
    final seen = <String>{};
    for (final s in _javaSuggestions) {
      final sl = s.toLowerCase();
      if (sl == lower) continue;
      if (sl.startsWith(lower) && seen.add(s)) {
        matches.add(s);
      }
    }
    if (matches.isEmpty) return;
    _suggestions = matches.take(12).toList();
    _showSuggestions(start, cursor);
  }

  void _showSuggestions(int wordStart, int cursor) {
    _hideSuggestions();
    final pos = _caretGlobalPosition();
    if (pos == null) return;
    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: pos.dx,
        top: pos.dy + 20,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) => InkWell(
                onTap: () => _applySuggestion(_suggestions[i], wordStart, cursor),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _applySuggestion(String suggestion, int wordStart, int cursor) {
    _hideSuggestions();
    final text = _text.text;
    final newText = text.substring(0, wordStart) + suggestion + text.substring(cursor);
    var caret = wordStart + suggestion.length;
    // Place caret inside parentheses when suggestion ends with ()
    if (suggestion.endsWith('()')) {
      caret = wordStart + suggestion.length - 1;
    }
    _text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  void _hideSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Offset? _caretGlobalPosition() {
    final rb = _focusNode.context?.findRenderObject() as RenderBox?;
    if (rb == null) return null;
    final sel = _text.selection;
    if (!sel.isValid) return null;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE6E6E6)
          : const Color(0xFF1F1F1F),
    );
    final painter = TextPainter(
      text: TextSpan(text: _text.text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: (rb.size.width - 32).clamp(0.0, double.infinity));
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: sel.baseOffset),
      Rect.zero,
    );
    return rb.localToGlobal(Offset(16 + caret.dx, 16 + caret.dy));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lineCount = '\n'.allMatches(_text.text).length + 1;
    final lineNumbers = List<String>.generate(lineCount, (i) => '${i + 1}').join('\n');
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.45,
      color: dark ? const Color(0xFFE6E6E6) : const Color(0xFF1F1F1F),
    );
    final gutterStyle = textStyle.copyWith(
      color: dark ? const Color(0xFF858585) : const Color(0xFF8A8A8A),
    );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _apply,
        const SingleActivator(LogicalKeyboardKey.escape): _hideSuggestions,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ValidationBar(
            validation: _effectiveValidation,
            checking: _remoteCheckInProgress && _supportsRemoteCheck,
            filePath: widget.controller.codePath,
            history: List<_CheckSnapshot>.unmodifiable(
              _checkHistoryByPath[widget.controller.codePath] ?? const <_CheckSnapshot>[],
            ),
            onShowHistory: () => _showCompilationHistoryDialog(
              widget.controller.codePath,
            ),
          ),
          Expanded(
            child: Container(
              color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFFBFBFB),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 52,
                    color: dark ? const Color(0xFF252526) : const Color(0xFFF0F0F0),
                    child: SingleChildScrollView(
                      controller: _gutterScrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      child: Text(
                        lineNumbers,
                        textAlign: TextAlign.right,
                        style: gutterStyle,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    color: dark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        if ((w - _editorTextWidth).abs() > 0.5) {
                          _editorTextWidth = w;
                          _scheduleCurrentLineUpdate();
                        }
                        return Stack(
                          children: <Widget>[
                            ValueListenableBuilder<Rect?>(
                              valueListenable: _currentLineRect,
                              builder: (context, lineRect, _) {
                                if (lineRect == null) {
                                  return const SizedBox.shrink();
                                }
                                return Positioned(
                                  left: 0,
                                  right: 0,
                                  top: lineRect.top,
                                  height: lineRect.height,
                                  child: IgnorePointer(
                                    child: Container(
                                      color: dark
                                          ? const Color(0xFF2A2D2E)
                                          : const Color(0xFFEAEAF2),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned.fill(
                              child: TextField(
                                controller: _text,
                                focusNode: _focusNode,
                                scrollController: _editorScrollController,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: textStyle,
                                autocorrect: false,
                                enableSuggestions: false,
                                enableIMEPersonalizedLearning: false,
                                onTap: _scheduleCurrentLineUpdate,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(16),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCompilationHistoryDialog(String path) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _CompilationHistoryDialog(
          path: path,
          controller: widget.controller,
          localSnapshots: () => List<_CheckSnapshot>.from(
            _checkHistoryByPath[path] ?? const <_CheckSnapshot>[],
          ),
        );
      },
    );
  }
}

class _CheckSnapshot {
  const _CheckSnapshot({required this.time, required this.issues});
  final DateTime time;
  final List<ValidationIssue> issues;
}

enum _HistoryFilter { all, success, warnings, errors }

class _CompilationHistoryDialog extends StatefulWidget {
  const _CompilationHistoryDialog({
    required this.path,
    required this.controller,
    required this.localSnapshots,
  });

  final String path;
  final EditorController controller;
  final List<_CheckSnapshot> Function() localSnapshots;

  @override
  State<_CompilationHistoryDialog> createState() => _CompilationHistoryDialogState();
}

class _CompilationHistoryDialogState extends State<_CompilationHistoryDialog> {
  Timer? _timer;
  bool _loading = true;
  List<FileCheckRecord> _records = const <FileCheckRecord>[];
  String _recordsHash = '';
  String _localHash = '';
  List<_CheckSnapshot> _local = const <_CheckSnapshot>[];
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _HistoryFilter _filter = _HistoryFilter.all;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _local = widget.localSnapshots();
    _localHash = _hashLocal(_local);
    _refresh(force: true);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _hashRecords(List<FileCheckRecord> records) {
    final buf = StringBuffer();
    for (final r in records) {
      buf
        ..write(r.id)
        ..write('|')
        ..write(r.date.toIso8601String())
        ..write('|')
        ..write(r.file)
        ..write('|');
      for (final d in r.diagnostics) {
        buf
          ..write(d.file)
          ..write(',')
          ..write(d.line)
          ..write(',')
          ..write(d.column)
          ..write(',')
          ..write(d.kind)
          ..write(',')
          ..write(d.message)
          ..write(';');
      }
      buf.write('||');
    }
    return buf.toString().hashCode.toString();
  }

  String _hashLocal(List<_CheckSnapshot> snaps) {
    final buf = StringBuffer();
    for (final s in snaps) {
      buf
        ..write(s.time.millisecondsSinceEpoch)
        ..write('|');
      for (final i in s.issues) {
        buf
          ..write(i.line ?? 0)
          ..write(',')
          ..write(i.column ?? 0)
          ..write(',')
          ..write(i.isError)
          ..write(',')
          ..write(i.message)
          ..write(';');
      }
      buf.write('||');
    }
    return buf.toString().hashCode.toString();
  }

  Future<void> _refresh({bool force = false}) async {
    final local = widget.localSnapshots();
    final localHash = _hashLocal(local);
    try {
      final records = await widget.controller.getFileCheckHistory(widget.path);
      final hash = _hashRecords(records);
      if (!mounted) return;
      if (force || hash != _recordsHash || localHash != _localHash || _loading) {
        setState(() {
          _records = records;
          _recordsHash = hash;
          _local = local;
          _localHash = localHash;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (force || localHash != _localHash || _loading) {
        setState(() {
          _local = local;
          _localHash = localHash;
          _loading = false;
        });
      }
    }
  }

  String _issueKey({required int line, required int column, required String kind, required String message}) =>
      '$line|$column|$kind|$message';

  Future<void> _showCheckReportDialog({
    required DateTime date,
    required String? author,
    required List<({int line, int column, String kind, String message})> issues,
    required List<({int line, int column, String kind, String message})>? previousIssues,
  }) async {
    if (!mounted) return;
    final currentKeys = issues.map((e) => _issueKey(line: e.line, column: e.column, kind: e.kind, message: e.message)).toSet();
    final prevKeys = previousIssues
        ?.map((e) => _issueKey(line: e.line, column: e.column, kind: e.kind, message: e.message))
        .toSet();
    final introduced = previousIssues == null
        ? const <({int line, int column, String kind, String message})>[]
        : issues
            .where((e) => !(prevKeys!.contains(_issueKey(line: e.line, column: e.column, kind: e.kind, message: e.message))))
            .toList();
    final resolved = previousIssues == null
        ? const <({int line, int column, String kind, String message})>[]
        : previousIssues
            .where((e) => !currentKeys.contains(_issueKey(line: e.line, column: e.column, kind: e.kind, message: e.message)))
            .toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        String two(int v) => v.toString().padLeft(2, '0');
        String fmtDateTime(DateTime t) {
          final local = t.toLocal();
          return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
        }

        final errorCount = issues.where((e) => e.kind == 'error').length;
        final warningCount = issues.length - errorCount;
        final hasErrors = errorCount > 0;
        final statusColor = issues.isEmpty
            ? Colors.green.shade700
            : (hasErrors ? theme.colorScheme.error : Colors.amber.shade800);
        final statusIcon = issues.isEmpty
            ? Icons.check_circle_outline
            : (hasErrors ? Icons.error_outline : Icons.warning_amber_outlined);
        final statusText = issues.isEmpty
            ? dialogContext.tr('No issues found.')
            : dialogContext.l10n.validationSummary(errorCount, warningCount);

        Widget issueTile(({int line, int column, String kind, String message}) issue, {Color? forceColor}) {
          final isError = issue.kind == 'error';
          final color = forceColor ?? (isError ? theme.colorScheme.error : Colors.amber.shade800);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  isError ? Icons.error_outline : Icons.warning_amber_outlined,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dialogContext.l10n.issueLocation(issue.line, issue.column) + issue.message,
                    style: TextStyle(fontSize: 12.5, color: color, height: 1.35),
                  ),
                ),
              ],
            ),
          );
        }

        Widget sectionCard({required IconData icon, required String title, required Widget child, Color? accent}) {
          final accentColor = accent ?? theme.colorScheme.primary;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(icon, size: 16, color: accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          );
        }

        Widget fileTag() {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.insert_drive_file_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.path,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final infoItems = <Widget>[
          Row(
            children: <Widget>[
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${dialogContext.tr('Check')}: ${fmtDateTime(date)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (author != null && author.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.person_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${dialogContext.tr('Author')}: $author',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ];

        final children = <Widget>[
          fileTag(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: infoItems),
          ),
          const SizedBox(height: 12),
          sectionCard(
            icon: Icons.list_alt_outlined,
            title: '${dialogContext.tr('Issues in this check')} (${issues.length})',
            accent: statusColor,
            child: issues.isEmpty
                ? Text(dialogContext.tr('No issues found.'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: issues.map((e) => issueTile(e)).toList()),
          ),
          const SizedBox(height: 12),
          sectionCard(
            icon: Icons.compare_arrows_outlined,
            title: dialogContext.tr('Changes in this check'),
            child: previousIssues == null
                ? Text(dialogContext.tr('No previous check to compare.'))
                : (introduced.isEmpty && resolved.isEmpty)
                    ? Text(dialogContext.tr('No changes compared to previous check.'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (introduced.isNotEmpty) ...<Widget>[
                            Text(
                              '${dialogContext.tr('Introduced issues')} (${introduced.length})',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...introduced.map((e) => issueTile(e)),
                            if (resolved.isNotEmpty) const SizedBox(height: 8),
                          ],
                          if (resolved.isNotEmpty) ...<Widget>[
                            Text(
                              '${dialogContext.tr('Resolved issues')} (${resolved.length})',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...resolved.map((e) => issueTile(e, forceColor: Colors.green.shade700)),
                          ],
                        ],
                      ),
          ),
        ];

        return AlertDialog(
          title: Row(
            children: <Widget>[
              Icon(Icons.assignment_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(dialogContext.tr('Check report'))),
            ],
          ),
          content: SizedBox(
            width: 700,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
          actions: <Widget>[
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.tr('Close')),
            ),
          ],
        );
      },
    );
  }

  bool _matchesFilter({required bool isEmpty, required bool hasErrors}) {
    switch (_filter) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.success:
        return isEmpty;
      case _HistoryFilter.warnings:
        return !isEmpty && !hasErrors;
      case _HistoryFilter.errors:
        return hasErrors;
    }
  }

  bool _matchesQuery(String haystack) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return haystack.toLowerCase().contains(q);
  }

  bool _matchesDate(DateTime dt) {
    final r = _dateRange;
    if (r == null) return true;
    final local = dt.toLocal();
    final d = DateTime(local.year, local.month, local.day);
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  String _fmtDateShort(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = t.toLocal();
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget issueTile({required bool isError, required int line, required int column, required String message}) {
      final color = isError ? theme.colorScheme.error : Colors.amber.shade800;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.l10n.issueLocation(line, column) + message,
                style: TextStyle(fontSize: 12.5, color: color),
              ),
            ),
          ],
        ),
      );
    }

    String serverDiagSig(List<FileCheckDiagnostic> diags) =>
        diags.map((d) => '${d.line}|${d.column}|${d.kind}|${d.message}').join('\n');
    String localIssuesSig(List<ValidationIssue> issues) => issues
        .map((i) => '${i.line ?? 1}|${i.column ?? 1}|${i.isError ? 'error' : 'warning'}|${i.message}')
        .join('\n');

    final hasServerHistory = _records.isNotEmpty;
    final hasLocalHistory = _local.isNotEmpty;

    // Include very recent local in-session checks that may not be persisted/visible
    // on the server yet (dialog prefers server history when available).
    var localHeadCount = 0;
    if (hasLocalHistory && hasServerHistory) {
      final newestServerSig = serverDiagSig(_records.first.diagnostics);
      for (final snap in _local) {
        final isAfterServer = snap.time.isAfter(_records.first.date);
        final sameAsServer = localIssuesSig(snap.issues) == newestServerSig;
        if (isAfterServer && !sameAsServer) {
          localHeadCount++;
        } else {
          break;
        }
      }
    } else if (hasLocalHistory && !hasServerHistory) {
      localHeadCount = _local.length;
    }

    List<({int line, int column, String kind, String message})> serverIssues(FileCheckRecord rec) => rec.diagnostics
        .map((d) => (line: d.line, column: d.column, kind: d.kind, message: d.message))
        .toList();
    List<({int line, int column, String kind, String message})> localIssues(_CheckSnapshot snap) => snap.issues
        .map((issue) => (
              line: issue.line ?? 1,
              column: issue.column ?? 1,
              kind: issue.isError ? 'error' : 'warning',
              message: issue.render(context.tr),
            ))
        .toList();

    final filteredRecordIndices = <int>[];
    final filteredLocalIndices = <int>[];
    final filteredLocalHeadIndices = <int>[];
    if (hasServerHistory) {
      for (int i = 0; i < _records.length; i++) {
        final rec = _records[i];
        final diags = rec.diagnostics;
        final hasErrors = diags.any((d) => d.isError);
        if (!_matchesDate(rec.date)) continue;
        if (!_matchesFilter(isEmpty: diags.isEmpty, hasErrors: hasErrors)) continue;
        final buf = StringBuffer()
          ..write(_fmtTime(rec.date))
          ..write(' ')
          ..write(rec.date.toLocal().toIso8601String())
          ..write(' ')
          ..write(rec.author)
          ..write(' ');
        for (final d in diags) {
          buf
            ..write(d.kind)
            ..write(' ')
            ..write(d.line)
            ..write(':')
            ..write(d.column)
            ..write(' ')
            ..write(d.message)
            ..write(' ');
        }
        if (_matchesQuery(buf.toString())) filteredRecordIndices.add(i);
      }
      for (int i = 0; i < localHeadCount; i++) {
        final snap = _local[i];
        final hasErrors = snap.issues.any((issue) => issue.isError);
        if (!_matchesDate(snap.time)) continue;
        if (!_matchesFilter(isEmpty: snap.issues.isEmpty, hasErrors: hasErrors)) continue;
        final buf = StringBuffer()
          ..write(_fmtTime(snap.time))
          ..write(' ')
          ..write(snap.time.toLocal().toIso8601String())
          ..write(' ');
        for (final issue in snap.issues) {
          buf
            ..write(issue.isError ? 'error' : 'warning')
            ..write(' ')
            ..write(issue.line ?? 1)
            ..write(':')
            ..write(issue.column ?? 1)
            ..write(' ')
            ..write(issue.render(context.tr))
            ..write(' ')
            ..write(issue.message)
            ..write(' ');
        }
        if (_matchesQuery(buf.toString())) filteredLocalHeadIndices.add(i);
      }
    } else if (hasLocalHistory) {
      for (int i = 0; i < _local.length; i++) {
        final snap = _local[i];
        final hasErrors = snap.issues.any((issue) => issue.isError);
        if (!_matchesDate(snap.time)) continue;
        if (!_matchesFilter(isEmpty: snap.issues.isEmpty, hasErrors: hasErrors)) continue;
        final buf = StringBuffer()
          ..write(_fmtTime(snap.time))
          ..write(' ')
          ..write(snap.time.toLocal().toIso8601String())
          ..write(' ');
        for (final issue in snap.issues) {
          buf
            ..write(issue.isError ? 'error' : 'warning')
            ..write(' ')
            ..write(issue.line ?? 1)
            ..write(':')
            ..write(issue.column ?? 1)
            ..write(' ')
            ..write(issue.render(context.tr))
            ..write(' ')
            ..write(issue.message)
            ..write(' ');
        }
        if (_matchesQuery(buf.toString())) filteredLocalIndices.add(i);
      }
    }

    Widget buildList() {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      Widget serverCard(int i) {
        return Builder(builder: (context) {
          final rec = _records[i];
          final date = rec.date;
          final diags = rec.diagnostics;
          final hasErrors = diags.any((d) => d.isError);
          final statusColor = diags.isEmpty
              ? Colors.green.shade700
              : (hasErrors ? theme.colorScheme.error : Colors.amber.shade800);
          final statusIcon = diags.isEmpty
              ? Icons.check_circle_outline
              : (hasErrors ? Icons.error_outline : Icons.warning_amber_outlined);
          final current = serverIssues(rec);
          final previous = (i + 1 < _records.length) ? serverIssues(_records[i + 1]) : null;
          final isLatestOverall = i == 0 && localHeadCount == 0;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.tr('Check')} ${_fmtTime(date)}'
                      '${isLatestOverall ? ' (${context.tr('latest')})' : ''}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              if (diags.isEmpty)
                Text(
                  context.tr('No issues found.'),
                  style: TextStyle(color: statusColor),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final d in diags)
                      issueTile(
                        isError: d.isError,
                        line: d.line,
                        column: d.column,
                        message: d.message,
                      ),
                  ],
                ),
            ],
          );
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showCheckReportDialog(
                date: date,
                author: rec.author,
                issues: current,
                previousIssues: previous,
              ),
              mouseCursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: content,
              ),
            ),
          );
        });
      }

      Widget localCard(int i, {required bool fromHead}) {
        return Builder(builder: (context) {
          final snap = _local[i];
          final hasErrors = snap.issues.any((issue) => issue.isError);
          final statusColor = snap.issues.isEmpty
              ? Colors.green.shade700
              : (hasErrors ? theme.colorScheme.error : Colors.amber.shade800);
          final statusIcon = snap.issues.isEmpty
              ? Icons.check_circle_outline
              : (hasErrors ? Icons.error_outline : Icons.warning_amber_outlined);
          final current = localIssues(snap);
          List<({int line, int column, String kind, String message})>? previous;
          if (i + 1 < _local.length) {
            previous = localIssues(_local[i + 1]);
          } else if (fromHead && hasServerHistory) {
            previous = serverIssues(_records.first);
          } else {
            previous = null;
          }
          final isLatestOverall = fromHead ? i == 0 : (localHeadCount == 0 && i == 0 && !hasServerHistory);
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.tr('Check')} ${_fmtTime(snap.time)}'
                      '${isLatestOverall ? ' (${context.tr('latest')})' : ''}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              if (snap.issues.isEmpty)
                Text(
                  context.tr('No issues found.'),
                  style: TextStyle(color: statusColor),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: snap.issues
                      .map((issue) => issueTile(
                            isError: issue.isError,
                            line: issue.line ?? 1,
                            column: issue.column ?? 1,
                            message: issue.render(context.tr),
                          ))
                      .toList(),
                ),
            ],
          );
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showCheckReportDialog(
                date: snap.time,
                author: null,
                issues: current,
                previousIssues: previous,
              ),
              mouseCursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: content,
              ),
            ),
          );
        });
      }

      if (hasServerHistory) {
        if (filteredLocalHeadIndices.isEmpty && filteredRecordIndices.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(context.tr('No checks match search or filters.')),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final i in filteredLocalHeadIndices) localCard(i, fromHead: true),
            for (final i in filteredRecordIndices) serverCard(i),
          ],
        );
      }

      if (hasLocalHistory) {
        if (filteredLocalIndices.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(context.tr('No checks match search or filters.')),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final i in filteredLocalIndices) localCard(i, fromHead: false),
          ],
        );
      }

      return Text(context.tr('No compilation results yet for this file.'));
    }

    Widget filterChip(_HistoryFilter value, String label, IconData icon) {
      final selected = _filter == value;
      return ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return AlertDialog(
      title: Text(context.tr('Compilation history')),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.path,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: context.tr('Search checks'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('Clear'),
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  filterChip(_HistoryFilter.all, context.tr('All'), Icons.filter_list),
                  filterChip(_HistoryFilter.success, context.tr('Successful'), Icons.check_circle_outline),
                  filterChip(_HistoryFilter.errors, context.tr('With errors'), Icons.error_outline),
                  filterChip(_HistoryFilter.warnings, context.tr('With warnings'), Icons.warning_amber_outlined),
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.date_range, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _dateRange == null
                              ? context.tr('Date')
                              : '${_fmtDateShort(_dateRange!.start)} – ${_fmtDateShort(_dateRange!.end)}',
                        ),
                      ],
                    ),
                    selected: _dateRange != null,
                    onSelected: (_) async {
                      final now = DateTime.now();
                      final initialRange = _dateRange ??
                          DateTimeRange(
                            start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7)),
                            end: DateTime(now.year, now.month, now.day),
                          );
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(now.year + 1, 12, 31),
                        initialDateRange: initialRange,
                        helpText: context.tr('Date'),
                        saveText: context.tr('Apply'),
                        builder: (context, child) {
                          if (child == null) return const SizedBox.shrink();
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
                              child: child,
                            ),
                          );
                        },
                      );
                      if (!mounted) return;
                      if (picked != null) {
                        setState(() => _dateRange = picked);
                      }
                    },
                    onDeleted: _dateRange == null ? null : () => setState(() => _dateRange = null),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: buildList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}

class _ValidationBar extends StatelessWidget {
  const _ValidationBar({
    required this.validation,
    this.checking = false,
    this.filePath,
    this.history = const <_CheckSnapshot>[],
    this.onShowHistory,
  });

  final ValidationResult validation;
  final bool checking;
  final String? filePath;
  final List<_CheckSnapshot> history;
  final VoidCallback? onShowHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = validation.issues;

    // Nothing to complain about: a calm "all clear" row.
    if (issues.isEmpty) {
      final color = checking ? theme.colorScheme.tertiary : theme.colorScheme.primary;
      final row = Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            if (checking)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(Icons.check_circle_outline, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              context.tr(checking ? 'Checking...' : 'No issues found.'),
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ],
        ),
      );
      if (onShowHistory == null) return row;
      return InkWell(
        onTap: onShowHistory,
        mouseCursor: SystemMouseCursors.click,
        child: row,
      );
    }

    // Show checking status alongside existing issues (e.g. while recompiling).
    final checkingWidget = checking
        ? Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  context.tr('Checking...'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          )
        : null;

    // Red for errors (they block Apply), amber for warnings only — the same
    // split IntelliJ IDEA makes in its editor.
    final hasErrors = validation.hasErrors;
    final warnColor = Colors.amber.shade800;
    final color = hasErrors ? theme.colorScheme.error : warnColor;
    final header = Row(
      children: <Widget>[
        Icon(
          hasErrors ? Icons.error_outline : Icons.warning_amber_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.l10n.validationSummary(
              validation.errorCount,
              validation.warningCount,
            ),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (onShowHistory != null)
          Icon(Icons.history, size: 14, color: color.withValues(alpha: 0.8)),
      ],
    );

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ?checkingWidget,
          onShowHistory == null
              ? header
              : InkWell(
                  onTap: onShowHistory,
                  mouseCursor: SystemMouseCursors.click,
                  child: header,
                ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: issues.length,
              itemBuilder: (context, index) {
                final issue = issues[index];
                final issueColor = issue.isError
                    ? theme.colorScheme.error
                    : warnColor;
                final row = Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        issue.isError
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        size: 12,
                        color: issueColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.l10n.issueLocation(issue.line, issue.column) +
                              issue.render(context.tr),
                          style: TextStyle(fontSize: 11.5, color: issueColor),
                        ),
                      ),
                    ],
                  ),
                );
                if (onShowHistory == null) return row;
                return InkWell(
                  onTap: onShowHistory,
                  mouseCursor: SystemMouseCursors.click,
                  child: row,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
