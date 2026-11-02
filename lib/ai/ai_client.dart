import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_exception.dart';

export 'ai_exception.dart';

/// Minimal client for a local [Ollama](https://ollama.com) server.
///
/// The base URL defaults to the `/ai` path, which the nginx frontend proxies to
/// the host's Ollama (`host.docker.internal:11434`). When running the app
/// outside Docker, override it with
/// `--dart-define=AI_BASE_URL=http://localhost:11434`.
class AiClient {
  AiClient({http.Client? client, String? baseUrl, Duration? timeout})
      : _client = client ?? http.Client(),
        baseUrl = _normalize(baseUrl ?? defaultBaseUrl),
        _timeout = timeout ?? const Duration(minutes: 5);

  static const String defaultBaseUrl =
      String.fromEnvironment('AI_BASE_URL', defaultValue: '/ai');

  final http.Client _client;
  final String baseUrl;
  final Duration _timeout;

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  /// Names of the models installed on the Ollama server.
  Future<List<String>> listModels() async {
    final response = await _get('$baseUrl/api/tags');
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    final models = decoded['models'] as List? ?? const [];
    return <String>[
      for (final model in models)
        if (model is Map && (model['name'] ?? model['model']) != null)
          (model['name'] ?? model['model']).toString(),
    ];
  }

  /// Sends [prompt] to [model] and returns the generated text.
  Future<String> generate({
    required String model,
    required String prompt,
    String? system,
  }) async {
    final body = jsonEncode(<String, dynamic>{
      'model': model,
      'prompt': prompt,
      if (system != null && system.isNotEmpty) 'system': system,
      'stream': false,
    });
    final response = await _post('$baseUrl/api/generate', body);
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    return (decoded['response'] as String?) ?? '';
  }

  Future<String> _get(String url) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(_timeout);
    } catch (error) {
      throw AiException('Cannot reach the AI server at $baseUrl.\n$error');
    }
    if (response.statusCode != 200) {
      throw AiException('AI server returned ${response.statusCode}.');
    }
    return response.body;
  }

  Future<String> _post(String url, String body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
    } catch (error) {
      throw AiException('Cannot reach the AI server at $baseUrl.\n$error');
    }
    if (response.statusCode != 200) {
      throw AiException('AI server returned ${response.statusCode}.');
    }
    return response.body;
  }

  void close() => _client.close();
}
