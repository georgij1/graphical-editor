import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:graphical_editor/project/project.dart';
import 'package:graphical_editor/project/project_exporter.dart';

/// run.bat запускается через cmd.exe, который понимает только CRLF и может
/// споткнуться о BOM — проверяем оба условия на реальном экспорте.
void main() {
  test('run.bat has CRLF and no BOM', () {
    final project = Project(
        id: 'test', name: 'Test', package: 'com.example', mainClass: 'MainApp');
    final exporter = ProjectExporter();
    final bytes = exporter.build(project, ExportOptions());
    final archive = ZipDecoder().decodeBytes(bytes);
    final runBat = archive.findFile('Test/run.bat');
    expect(runBat, isNotNull);
    final raw = runBat!.content as List<int>;

    // Ни одной LF без предшествующего CR.
    for (var i = 0; i < raw.length - 1; i++) {
      if (raw[i] == 10 && (i == 0 || raw[i - 1] != 13)) {
        fail('run.bat must use CRLF line endings');
      }
    }
    final hasBom =
        raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF;
    expect(hasBom, isFalse, reason: 'run.bat must not have BOM');
  });
}
