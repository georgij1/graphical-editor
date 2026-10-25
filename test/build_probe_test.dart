import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphical_editor/editor/editor_controller.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/project/project_exporter.dart';

/// Sends the archive of a fresh project to the build service: the smoke test
/// of the whole build path.
void main() {
  test('the build service compiles a fresh project', () async {
    final project = Project(
      id: 'demo',
      name: 'Demo',
      package: 'com.example.demo',
      mainClass: 'MainApp',
    );
    project.scenes.add(SceneFile(
      name: 'main',
      fxml: exampleFxml,
      controllerClass: 'com.example.demo.MainAppController',
    ));

    final bytes = const ProjectExporter().build(project, const ExportOptions());
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('http://localhost:8080/build'));
    request.headers.contentType = ContentType('application', 'zip');
    request.add(bytes);
    final response = await request.close();
    final body = await response.fold<int>(0, (sum, chunk) => sum + chunk.length);

    // ignore: avoid_print
    print('статус: ${response.statusCode}, размер: $body байт, '
        'тип: ${response.headers.contentType}');
    if (response.statusCode != 200) {
      final text = await response.transform(utf8.decoder).join();
      // ignore: avoid_print
      print(text.length > 2000 ? text.substring(0, 2000) : text);
    }
    client.close();

    expect(response.statusCode, 200,
        reason: 'The build service must compile a fresh project.');
    expect(body, greaterThan(1000));
  });
}
