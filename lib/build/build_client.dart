import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A produced artifact: the JAR or the ready-to-run bundle.
class BuildArtifact {
  const BuildArtifact({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// A compiler diagnostic returned by the backend check.
class BuildDiagnostic {
  const BuildDiagnostic({
    required this.file,
    required this.line,
    required this.column,
    required this.kind,
    required this.message,
  });

  final String file;
  final int line;
  final int column;
  final String kind; // "error" | "warning"
  final String message;

  bool get isError => kind == 'error';

  factory BuildDiagnostic.fromJson(Map<String, dynamic> json) {
    return BuildDiagnostic(
      file: (json['file'] as String?) ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      kind: (json['kind'] as String?) ?? 'error',
      message: (json['message'] as String?) ?? '',
    );
  }
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

  /// Compiles [archive] and returns compiler diagnostics (no artifact).
  Future<List<BuildDiagnostic>> check(Uint8List archive) async {
    late http.Response response;
    try {
      response = await _http
          .post(_url('/build/check'), body: archive)
          .timeout(const Duration(minutes: 3));
    } catch (error) {
      throw BuildException('Build service is unreachable: $error');
    }

    final text = _decode(response.bodyBytes);
    if (response.statusCode != 200) {
      final detail = text.trim();
      throw BuildException(
        detail.isEmpty ? 'Check failed (HTTP ${response.statusCode})' : detail,
      );
    }
    try {
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final list = (decoded['diagnostics'] as List? ?? const []);
      return list
          .whereType<Map<String, dynamic>>()
          .map(BuildDiagnostic.fromJson)
          .toList();
    } catch (e) {
      throw BuildException('Invalid check response: $e');
    }
  }

  /// Validates that a dependency exists (checked against Maven Central by backend).
  /// [notation] can be "group:artifact:version" (Gradle-style). If provided, it
  /// takes precedence for parsing missing fields.
  Future<void> validateDependency({
    String? groupId,
    String? artifactId,
    String? version,
    String? notation,
  }) async {
    final params = <String, String>{};
    if (groupId != null && groupId.trim().isNotEmpty) {
      params['groupId'] = groupId.trim();
    }
    if (artifactId != null && artifactId.trim().isNotEmpty) {
      params['artifactId'] = artifactId.trim();
    }
    if (version != null && version.trim().isNotEmpty) {
      params['version'] = version.trim();
    }
    if (notation != null && notation.trim().isNotEmpty) {
      params['notation'] = notation.trim();
    }
    if (params.isEmpty) {
      throw BuildException('Dependency coordinates are required');
    }

    final uri = _url('/build/validate-dependency').replace(queryParameters: params);
    late http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 12));
    } catch (error) {
      throw BuildException('Could not validate dependency: $error');
    }

    final text = _decode(response.bodyBytes).trim();
    Map<String, dynamic> decoded = const <String, dynamic>{};
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) decoded = d;
    } catch (_) {}

    final valid = decoded['valid'] == true;
    if (response.statusCode == 200 && valid) {
      return;
    }

    final message = (decoded['message'] as String?)?.trim();
    if (message != null && message.isNotEmpty) {
      throw BuildException(message);
    }
    if (response.statusCode != 200) {
      throw BuildException('Could not validate dependency (HTTP ${response.statusCode})');
    }
    throw BuildException('Dependency not found');
  }

  /// Validates that a Gradle plugin exists (checked against Gradle Plugin Portal).
  Future<void> validatePlugin({
    required String id,
    String? version,
  }) async {
    final pluginId = id.trim();
    if (pluginId.isEmpty) {
      throw BuildException('Plugin ID is required');
    }
    final params = <String, String>{'id': pluginId};
    if (version != null && version.trim().isNotEmpty) {
      params['version'] = version.trim();
    }

    final uri = _url('/build/validate-plugin').replace(queryParameters: params);
    late http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 12));
    } catch (error) {
      throw BuildException('Could not validate plugin: $error');
    }

    final text = _decode(response.bodyBytes).trim();
    Map<String, dynamic> decoded = const <String, dynamic>{};
    try {
      final d = jsonDecode(text);
      if (d is Map<String, dynamic>) decoded = d;
    } catch (_) {}

    final valid = decoded['valid'] == true;
    if (response.statusCode == 200 && valid) {
      return;
    }

    final message = (decoded['message'] as String?)?.trim();
    if (message != null && message.isNotEmpty) {
      throw BuildException(message);
    }
    if (response.statusCode != 200) {
      throw BuildException('Could not validate plugin (HTTP ${response.statusCode})');
    }
    throw BuildException('Plugin not found');
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