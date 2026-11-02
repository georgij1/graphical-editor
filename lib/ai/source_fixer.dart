import 'package:graphical_editor/ai/ai_client.dart';

/// Extension providing the "fix source" workflow on top of [AiClient].
extension AiClientFixSource on AiClient {
  /// Asks the model to fix [source] given the [errors] found by the validator.
  Future<String> fixSource({
    required String model,
    required String path,
    required String source,
    required List<String> errors,
    String? instruction,
  }) async {
    final buffer = StringBuffer()
      ..writeln('File: $path')
      ..writeln()
      ..writeln('The file has the following problems:');
    if (errors.isEmpty) {
      buffer.writeln('- (no automatic issues found; review manually)');
    } else {
      for (final error in errors) {
        buffer.writeln('- $error');
      }
    }
    if (instruction != null && instruction.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Additional instruction: ${instruction.trim()}');
    }
    buffer
      ..writeln()
      ..writeln('Fix the file so it is valid and keeps its intent. '
          'Return ONLY the full corrected file content.');

    final raw = await generate(
      model: model,
      prompt: buffer.toString(),
      system: 'You are a precise coding assistant. Output only the corrected '
          'file content, without explanations and without markdown code fences.',
    );
    return AiClientFixSource.stripCodeFences(raw);
  }

  /// Removes an optional ```lang ... ``` wrapper from a model response.
  static String stripCodeFences(String value) {
    var text = value.trim();
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline == -1) return text;
    text = text.substring(firstNewline + 1);
    final closing = text.lastIndexOf('```');
    if (closing != -1) text = text.substring(0, closing);
    return text.trim();
  }
}
