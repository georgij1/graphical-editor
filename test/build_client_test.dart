import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/build/build_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BuildClient', () {
    test('posts the archive and returns the jar', () async {
      late http.Request seen;
      final client = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response.bytes(
            <int>[0x50, 0x4B, 0x03, 0x04],
            200,
            headers: <String, String>{
              'content-disposition': 'attachment; filename="app.jar"',
            },
          );
        }),
      );

      final artifact = await client.build(
        Uint8List.fromList(<int>[1, 2, 3]),
        bundle: false,
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/build');
      expect(seen.bodyBytes, <int>[1, 2, 3]);
      expect(artifact.fileName, 'app.jar');
      expect(artifact.bytes, <int>[0x50, 0x4B, 0x03, 0x04]);
    });

    test('bundle requests the bundle endpoint', () async {
      late String path;
      final client = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((request) async {
          path = request.url.path;
          return http.Response.bytes(<int>[0x50, 0x4B], 200);
        }),
      );

      final artifact =
          await client.build(Uint8List(0), bundle: true);

      expect(path, '/build/bundle');
      // No content-disposition header: fall back to the known name.
      expect(artifact.fileName, 'bundle.zip');
    });

    test('surfaces the compiler error message', () async {
      final client = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((_) async => http.Response(
              'MainApp.java:3: error: cannot find symbol',
              400,
            )),
      );

      expect(
        () => client.build(Uint8List(0), bundle: false),
        throwsA(
          isA<BuildException>().having(
            (e) => e.message,
            'message',
            contains('cannot find symbol'),
          ),
        ),
      );
    });

    test('reports an unreachable service', () async {
      final client = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(
        () => client.build(Uint8List(0), bundle: false),
        throwsA(isA<BuildException>()),
      );
    });

    test('health check reflects the answer', () async {
      final up = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );
      expect(await up.isAvailable(), isTrue);

      final down = BuildClient(
        baseUrl: 'http://localhost:8081',
        httpClient: MockClient((_) async => http.Response('', 500)),
      );
      expect(await down.isAvailable(), isFalse);
    });

    test('default base url is same-origin', () {
      expect(BuildClient.defaultBaseUrl, isEmpty);
    });

    test('a relative base url is resolved against the page origin', () async {
      late Uri seen;
      final client = BuildClient(
        httpClient: MockClient((request) async {
          seen = request.url;
          return http.Response.bytes(<int>[0x50, 0x4B], 200);
        }),
      );

      await client.build(Uint8List(0), bundle: false);

      expect(seen.path, '/build');
      expect(seen.scheme, Uri.base.scheme);
      expect(seen.host, Uri.base.host);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'connection refused';
}