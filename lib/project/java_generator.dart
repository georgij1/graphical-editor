import 'project.dart';

class GeneratedFile {
  GeneratedFile({required this.path, required this.content});
  final String path;
  final String content;
}

class JavaGenerator {
  static String packageDir(Project p) => p.package.replaceAll('.', '/');

  /// Generates the Java sources of a runnable JavaFX application:
  /// an [Application] launcher plus one controller per scene.
  ///
  /// When [applyOverrides] is true (the default), hand-edited sources stored on
  /// the project replace the generated ones.
  static List<GeneratedFile> generate(Project p, {bool applyOverrides = true}) {
    final files = <GeneratedFile>[];
    final scenes = p.scenes.isNotEmpty ? p.scenes : [SceneFile(name: 'main', fxml: '')];
    final mainScene = p.mainScene ?? scenes.first;
    final mainPath = 'src/main/java/${packageDir(p)}/${p.mainClass}.java';
    files.add(GeneratedFile(
      path: mainPath,
      content: _resolve(p, mainPath, _mainClass(p, mainScene.name),
          applyOverrides: applyOverrides),
    ));
    for (final scene in scenes) {
      final c = scene.controllerClass;
      if (c == null || c.isEmpty) continue;
      final simple = c.contains('.') ? c.split('.').last : c;
      final path = 'src/main/java/${packageDir(p)}/$simple.java';
      files.add(GeneratedFile(
        path: path,
        content: _resolve(p, path, _controller(p.package, simple),
            applyOverrides: applyOverrides),
      ));
    }
    return files;
  }

  static String _resolve(
    Project p,
    String path,
    String generated, {
    required bool applyOverrides,
  }) {
    if (!applyOverrides) return generated;
    return p.sourceOverrides[path] ?? generated;
  }

  static String _mainClass(Project p, String sceneName) {
    return 'package ${p.package};\n'
        '\n'
        'import java.io.IOException;\n'
        '\n'
        'import javafx.application.Application;\n'
        'import javafx.fxml.FXMLLoader;\n'
        'import javafx.scene.Parent;\n'
        'import javafx.scene.Scene;\n'
        'import javafx.stage.Stage;\n'
        '\n'
        'public class ${p.mainClass} extends Application {\n'
        '\n'
        '    @Override\n'
        '    public void start(Stage stage) throws IOException {\n'
        '        FXMLLoader loader = new FXMLLoader(getClass().getResource("$sceneName.fxml"));\n'
        '        Parent root = loader.load();\n'
        '        Scene scene = new Scene(root);\n'
        '        stage.setTitle("${p.name}");\n'
        '        stage.setScene(scene);\n'
        '        stage.show();\n'
        '    }\n'
        '\n'
        '    public static void main(String[] args) {\n'
        '        launch();\n'
        '    }\n'
        '}\n';
  }

  static String _controller(String package, String className) {
    return 'package $package;\n'
        '\n'
        'import java.net.URL;\n'
        'import java.util.ResourceBundle;\n'
        '\n'
        'import javafx.fxml.FXML;\n'
        'import javafx.fxml.Initializable;\n'
        '\n'
        'public class $className implements Initializable {\n'
        '\n'
        '    @Override\n'
        '    public void initialize(URL location, ResourceBundle resources) {\n'
        '        // Wire up UI controls here.\n'
        '    }\n'
        '}\n';
  }
}