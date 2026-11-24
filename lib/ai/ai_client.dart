import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_exception.dart';

export 'ai_exception.dart';

/// Client for the AI service (default) or a direct Ollama-compatible server.
///
/// Default base URL is `/api/ai`, which nginx routes to the AI microservice.
/// The AI service proxies to Ollama and requires Bearer auth.
/// For direct Ollama access, pass an Ollama base URL such as
/// `http://localhost:11434` or `/ai`.
class AiClient {
  AiClient({http.Client? client, String? baseUrl, Duration? timeout})
      : _client = client ?? http.Client(),
        baseUrl = _normalize(baseUrl ?? defaultBaseUrl),
        _timeout = timeout ?? const Duration(minutes: 5);

  static const String defaultBaseUrl =
      String.fromEnvironment('AI_BASE_URL', defaultValue: '/api/ai');

  final http.Client _client;
  final String baseUrl;
  final Duration _timeout;

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  String _resolveBaseUrl(String? override) {
    final v = (override ?? '').trim();
    if (v.isEmpty) return baseUrl;
    return _normalize(v);
  }

  bool _isServiceApi(String root) {
    final r = root.toLowerCase();
    return r.endsWith('/api/ai') || r == '/api/ai';
  }

  Map<String, String> _headers(String? authToken, {bool json = false}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    final t = (authToken ?? '').trim();
    if (t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  /// Names of the models installed on the AI server.
  Future<List<String>> listModels({String? baseUrl, String? authToken}) async {
    final root = _resolveBaseUrl(baseUrl);
    final path = _isServiceApi(root) ? '/models' : '/api/tags';
    final response = await _get('$root$path', root: root, authToken: authToken);
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
    String? baseUrl,
    String? authToken,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in generateStream(
      model: model,
      prompt: prompt,
      system: system,
      baseUrl: baseUrl,
      authToken: authToken,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Streams generated text chunks as they arrive.
  Stream<String> generateStream({
    required String model,
    required String prompt,
    String? system,
    String? baseUrl,
    String? authToken,
  }) async* {
    final root = _resolveBaseUrl(baseUrl);
    final path = _isServiceApi(root) ? '/generate' : '/api/generate';
    final uri = Uri.parse('$root$path');
    final request = http.Request('POST', uri)
      ..headers.addAll(_headers(authToken, json: true))
      ..body = jsonEncode(<String, dynamic>{
        'model': model,
        'prompt': prompt,
        if (system != null && system.isNotEmpty) 'system': system,
        'stream': true,
      });
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw AiException('Cannot reach the AI server at $root.\n$error');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiException('AI server returned ${response.statusCode}. ${body.trim()}');
    }
    await for (final line
        in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        final chunk = decoded['response'] as String?;
        if (chunk != null && chunk.isNotEmpty) {
          yield chunk;
        }
        if (decoded['done'] == true) {
          break;
        }
      } catch (_) {
        // Ignore malformed partial lines.
      }
    }
  }

  Future<String> _get(String url, {String? root, String? authToken}) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: _headers(authToken))
          .timeout(_timeout);
    } catch (error) {
      throw AiException('Cannot reach the AI server at ${root ?? baseUrl}.\n$error');
    }
    if (response.statusCode != 200) {
      throw AiException('AI server returned ${response.statusCode}.');
    }
    return response.body;
  }

  void close() => _client.close();
}
