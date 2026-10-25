import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A produced artifact: the JAR or the ready-to-run bundle.
class BuildArtifact {
  const BuildArtifact({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

class BuildException implements Exception {
  BuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the JavaFX build service (`builder` in docker-compose), which
/// compiles an exported project archive into a runnable artifact.
class BuildClient {
  BuildClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? defaultBaseUrl;

  final http.Client _http;

  /// Root of the build service. Empty by default, which targets the same
  /// origin (`/build`) and therefore works behind the bundled nginx. Point it
  /// elsewhere with `--dart-define=BUILD_BASE_URL=http://host:8081`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'BUILD_BASE_URL',
    defaultValue: '',
  );

  final String baseUrl;

  Uri _url(String path) {
    final base = Uri.parse(baseUrl);
    // A relative base is resolved against the page origin, so the same client
    // works in the browser and behind a native proxy.
    return base.hasScheme ? base.resolve(path) : Uri.base.resolve('$baseUrl$path');
  }

  /// Compiles [archive] and returns the artifact bytes.
  ///
  /// [bundle] asks for the self-contained archive (JAR + JavaFX SDK + launch
  /// scripts) instead of the bare JAR.
  Future<BuildArtifact> build(Uint8List archive, {required bool bundle}) async {
    final path = bundle ? '/build/bundle' : '/build';
    late http.Response response;
    try {
      response = await _http
          .post(_url(path), body: archive)
          .timeout(const Duration(minutes: 5));
    } catch (error) {
      throw BuildException('Build service is unreachable: $error');
    }

    if (response.statusCode != 200) {
      final detail = _decode(response.bodyBytes).trim();
      throw BuildException(
        detail.isEmpty ? 'Build failed (HTTP ${response.statusCode})' : detail,
      );
    }
    return BuildArtifact(
      fileName: _nameOf(response, bundle ? 'bundle.zip' : 'app.jar'),
      bytes: response.bodyBytes,
    );
  }

  /// True when the service answers its health check.
  Future<bool> isAvailable() async {
    try {
      final response = await _http
          .get(_url('/build/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _nameOf(http.Response response, String fallback) {
    final header = response.headers['content-disposition'];
    final match = header == null ? null : RegExp(r'filename="?([^";]+)"?').firstMatch(header);
    return match?.group(1) ?? fallback;
  }

  String _decode(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  void close() => _http.close();
}