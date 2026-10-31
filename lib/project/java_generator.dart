import 'project.dart';

class GeneratedFile {
  GeneratedFile({
    required this.path,
    required this.content,
    bool? isJava,
    bool? isXml,
  })  : isJava = isJava ?? path.endsWith('.java'),
        isXml = isXml ?? (path.endsWith('.xml') || path.endsWith('.fxml'));
  final String path;
  final String content;

  /// True for generated Java sources that should be validated as Java.
  final bool isJava;

  /// True for XML files (FXML, pom.xml, ...) that should be validated as XML.
  final bool isXml;
}

class JavaGenerator {
  static String packageDir(Project p) => p.package.replaceAll('.', '/');

  /// Java reserved words that cannot be used as a class name.
  static const Set<String> _keywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
    'char', 'class', 'const', 'continue', 'default', 'do', 'double', 'else',
    'enum', 'extends', 'final', 'finally', 'float', 'for', 'goto', 'if',
    'implements', 'import', 'instanceof', 'int', 'interface', 'long',
    'native', 'new', 'package', 'private', 'protected', 'public', 'return',
    'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
    'throw', 'throws', 'transient', 'try', 'void', 'volatile', 'while',
    'true', 'false', 'null', 'var', 'record', 'yield', 'sealed',
    'permits', 'non-sealed',
  };

  /// True when [name] is a legal Java class name: a plain identifier that is
  /// not a reserved word. Used before renaming generated sources so the
  /// exported project always compiles.
  static bool isValidClassName(String name) {
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) return false;
    return !_keywords.contains(name);
  }

  /// Generates the Java sources of a runnable JavaFX application:
  /// an [Application] launcher plus one controller per scene.
  ///
  /// When [applyOverrides] is true (the default), hand-edited sources stored on
  /// the project replace the generated ones.
  ///
  /// When [kioskMode] is true the launcher starts the stage full-screen
  /// undecorated with ESC disabled (kiosk / digital-signage mode).
  static List<GeneratedFile> generate(Project p,
      {bool applyOverrides = true, bool kioskMode = false}) {
    final files = <GeneratedFile>[];
    final scenes = p.scenes.isNotEmpty ? p.scenes : [SceneFile(name: 'main', fxml: '')];
    final mainScene = p.mainScene ?? scenes.first;
    final mainPath = 'src/main/java/${packageDir(p)}/${p.mainClass}.java';
    files.add(GeneratedFile(
      path: mainPath,
      content: _resolve(p, mainPath, _mainClass(p, mainScene.name,
          kioskMode: kioskMode),
          applyOverrides: applyOverrides),
      isJava: true,
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
        isJava: true,
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

  static String _mainClass(Project p, String sceneName,
      {bool kioskMode = false}) {
    if (kioskMode) {
      return 'package ${p.package};\n'
          '\n'
          'import java.io.IOException;\n'
          '\n'
          'import javafx.application.Application;\n'
          'import javafx.fxml.FXMLLoader;\n'
          'import javafx.scene.Parent;\n'
          'import javafx.scene.Scene;\n'
          'import javafx.scene.input.KeyCombination;\n'
          'import javafx.stage.Stage;\n'
          'import javafx.stage.StageStyle;\n'
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
          '\n'
          '        // --- Kiosk mode ---\n'
          '        stage.initStyle(StageStyle.UNDECORATED);   // no title bar\n'
          '        stage.setFullScreen(true);                  // cover the whole screen\n'
          '        stage.setFullScreenExitHint("");            // suppress the default hint\n'
          '        stage.setFullScreenExitKeyCombination(KeyCombination.NO_MATCH); // disable ESC\n'
          '\n'
          '        stage.show();\n'
          '    }\n'
          '\n'
          '    public static void main(String[] args) {\n'
          '        launch();\n'
          '    }\n'
          '}\n';
    }
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