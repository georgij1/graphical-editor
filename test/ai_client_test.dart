import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/ai/ollama_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('listModels returns the installed model names', () async {
    final client = AiClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        expect(request.url.path, '/api/tags');
        return http.Response(
          jsonEncode({
            'models': [
              {'name': 'llama3:8b'},
              {'name': 'qwen2.5-coder'},
            ],
          }),
          200,
        );
      }),
    );
    expect(await client.listModels(), ['llama3:8b', 'qwen2.5-coder']);
  });

  test('generate posts the prompt and returns the response text', () async {
    final client = AiClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        expect(request.url.path, '/api/generate');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['stream'], isFalse);
        expect(body['model'], 'm');
        return http.Response(jsonEncode({'response': 'hello'}), 200);
      }),
    );
    expect(await client.generate(model: 'm', prompt: 'hi'), 'hello');
  });

  test('fixSource includes the errors and strips markdown fences', () async {
    String? sentPrompt;
    final client = AiClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sentPrompt = body['prompt'] as String;
        return http.Response(
          jsonEncode({'response': '```java\nclass Main {}\n```'}),
          200,
        );
      }),
    );
    final fixed = await client.fixSource(
      model: 'm',
      path: 'src/main/java/Main.java',
      source: 'class Main {}',
      errors: ['Line 1: Unclosed "{".'],
    );
    expect(sentPrompt, contains('Unclosed'));
    expect(sentPrompt, contains('src/main/java/Main.java'));
    expect(fixed, 'class Main {}');
  });

  test('throws AiException when the server is unreachable', () async {
    final client = AiClient(
      baseUrl: 'http://x',
      client: MockClient((request) async => throw const SocketExceptionStub()),
    );
    expect(
      () => client.listModels(),
      throwsA(isA<AiException>()),
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
