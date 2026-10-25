import 'project.dart';
import 'java_generator.dart';

/// Build tool configuration files written next to the generated sources.
/// Without one of them a JavaFX application cannot be started from the command
/// line.
enum BuildTool {
  maven('Maven', 'pom.xml'),
  gradle('Gradle', 'build.gradle'),
  none('None', '');

  const BuildTool(this.label, this.mainFile);

  final String label;

  /// File shown in the export dialog as a hint of what will be written.
  final String mainFile;
}

/// Generates the non-source files that make an exported project runnable.
class BuildFiles {
  const BuildFiles();

  /// Files for the chosen build tool, plus the shared README and .gitignore.
  List<GeneratedFile> generate(Project project, BuildTool tool) {
    return <GeneratedFile>[
      if (tool == BuildTool.maven) _mavenPom(project),
      if (tool == BuildTool.gradle) ...<GeneratedFile>[
        _gradleBuild(project),
        _gradleSettings(project),
      ],
      _runBat(project, tool),
      _runShell(project, tool),
      _gitignore,
      _readme(project, tool),
    ];
  }

  String get defaultArtifactId => 'app';

  String artifactId(Project p) {
    final cleaned = p.name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? defaultArtifactId : cleaned;
  }

  String get javafxVersion => '21.0.2';

  String mainClass(Project p) => '${p.package}.${p.mainClass}';

  GeneratedFile _mavenPom(Project p) => GeneratedFile(
        path: 'pom.xml',
        content: _pom(p),
      );

  String _pom(Project p) {
    final entryPoint = mainClass(p);
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<project xmlns="http://maven.apache.org/POM/4.0.0"\n'
        '         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n'
        '         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 '
        'http://maven.apache.org/xsd/maven-4.0.0.xsd">\n'
        '    <modelVersion>4.0.0</modelVersion>\n'
        '\n'
        '    <groupId>${p.package}</groupId>\n'
        '    <artifactId>${artifactId(p)}</artifactId>\n'
        '    <version>1.0.0</version>\n'
        '    <name>${p.name}</name>\n'
        '${p.description.isEmpty ? '' : '    <description>${p.description}</description>\n'}\n'
        '\n'
        '    <properties>\n'
        '        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>\n'
        '        <maven.compiler.release>21</maven.compiler.release>\n'
        '        <javafx.version>$javafxVersion</javafx.version>\n'
        '        <main.class>$entryPoint</main.class>\n'
        '    </properties>\n'
        '\n'
        '    <dependencies>\n'
        '        <dependency>\n'
        '            <groupId>org.openjfx</groupId>\n'
        '            <artifactId>javafx-controls</artifactId>\n'
        '            <version>\${javafx.version}</version>\n'
        '        </dependency>\n'
        '        <dependency>\n'
        '            <groupId>org.openjfx</groupId>\n'
        '            <artifactId>javafx-fxml</artifactId>\n'
        '            <version>\${javafx.version}</version>\n'
        '        </dependency>\n'
        '    </dependencies>\n'
        '\n'
        '    <build>\n'
        '        <plugins>\n'
        '            <plugin>\n'
        '                <groupId>org.apache.maven.plugins</groupId>\n'
        '                <artifactId>maven-compiler-plugin</artifactId>\n'
        '                <version>3.13.0</version>\n'
        '            </plugin>\n'
        '            <plugin>\n'
        '                <groupId>org.openjfx</groupId>\n'
        '                <artifactId>javafx-maven-plugin</artifactId>\n'
        '                <version>0.0.8</version>\n'
        '                <configuration>\n'
        '                    <mainClass>\${main.class}</mainClass>\n'
        '                </configuration>\n'
        '            </plugin>\n'
        '        </plugins>\n'
        '    </build>\n'
        '</project>\n';
  }

  GeneratedFile _gradleBuild(Project p) => GeneratedFile(
        path: 'build.gradle',
        content: _gradle(p),
      );

  String _gradle(Project p) => 'plugins {\n'
      "    id 'java'\n"
      "    id 'org.openjfx.javafxplugin' version '0.1.0'\n"
      '}\n'
      '\n'
      "group = '${p.package}'\n"
      "version = '1.0.0'\n"
      '\n'
      'repositories {\n'
      '    mavenCentral()\n'
      '}\n'
      '\n'
      'java {\n'
      '    toolchain {\n'
      '        languageVersion = JavaLanguageVersion.of(21)\n'
      '    }\n'
      '}\n'
      '\n'
      'javafx {\n'
      "    version = '$javafxVersion'\n"
      "    modules = ['javafx.controls', 'javafx.fxml']\n"
      '}\n'
      '\n'
      'application {\n'
      "    mainClass = '${mainClass(p)}'\n"
      '}\n';

  GeneratedFile _gradleSettings(Project p) => GeneratedFile(
        path: 'settings.gradle',
        content: "rootProject.name = '${artifactId(p)}'\n",
      );

  /// Windows batch file that launches the project with a ready JAR.
  /// Automatically downloads and installs Java 21 if it is missing.
  GeneratedFile _runBat(Project p, BuildTool tool) {
    return GeneratedFile(
      path: 'run.bat',
      content: '@echo off\n'
          'cd /d "%~dp0"\n'
          '\n'
          ':: Check if Java 21+ is available\n'
          'java -version >nul 2>&1\n'
          'if errorlevel 1 (\n'
          '    echo Installing Java 21...\n'
          '    powershell -NoProfile -Command "Invoke-WebRequest -Uri https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.4+11/OpenJDK21U-jdk_x64_windows_hotspot_21.0.4_11.msi -OutFile %TEMP%\\java21.msi"\n'
          '    msiexec /i "%TEMP%\\java21.msi" /quiet /norestart\n'
          '    del "%TEMP%\\java21.msi"\n'
          '    echo Java 21 installed. Restarting...\n'
          '    cmd /c "%~f0"\n'
          '    goto :eof\n'
          ')\n'
          '\n'
          ':: Run the application\n'
          'java -jar app.jar\n'
          'pause\n',
    );
  }

  /// Shell script that launches the project with the ready JAR.
  GeneratedFile _runShell(Project p, BuildTool tool) {
    return GeneratedFile(
      path: 'run.sh',
      content: '#!/usr/bin/env bash\n'
          'set -e\n'
          'cd "\$(dirname "\$0")"\n'
          'java -jar app.jar\n',
    );
  }

  GeneratedFile get _gitignore => GeneratedFile(
        path: '.gitignore',
        content: 'target/\n'
            'build/\n'
            '.gradle/\n'
            '.idea/\n'
            '*.iml\n'
            'out/\n'
            '*.class\n',
      );

  GeneratedFile _readme(Project p, BuildTool tool) {
    final runSection = switch (tool) {
      BuildTool.maven => '## Run\n'
          '\n'
          '```bash\n'
          'mvn javafx:run\n'
          '```\n',
      BuildTool.gradle => '## Run\n'
          '\n'
          '```bash\n'
          'gradle run\n'
          '```\n',
      BuildTool.none => '## Run\n'
          '\n'
          'Compile with your own JavaFX build setup, for example:\n'
          '\n'
          '```bash\n'
          'javac --module-path <javafx-sdk>/lib --add-modules javafx.controls,javafx.fxml '
          r'-d out $(find src/main/java -name "*.java")' '\n'
          'java --module-path <javafx-sdk>/lib --add-modules javafx.controls,javafx.fxml '
          '-cp out:src/main/resources ${mainClass(p)}\n'
          '```\n',
    };

    return GeneratedFile(
      path: 'README.md',
      content: '# ${p.name}\n'
          '\n'
          '${p.description.isEmpty ? 'JavaFX application built with the FXML Editor.' : p.description}\n'
          '\n'
          '## Layout\n'
          '\n'
          '```text\n'
          'src/main/java       Java sources (launcher and scene controllers)\n'
          'src/main/resources  FXML scenes\n'
          '```\n'
          '\n'
          '## Requirements\n'
          '\n'
          '- JDK 21 or newer\n'
          '- JavaFX $javafxVersion\n'
          '${tool == BuildTool.maven ? '- Maven 3.8+\n' : tool == BuildTool.gradle ? '- Gradle 8+\n' : ''}'
          '\n'
          '$runSection',
    );
  }

  /// Files that only describe how to build the project.
  List<GeneratedFile> forTree(Project p, BuildTool tool) =>
      generate(p, tool).where((f) => !f.path.startsWith('README')).toList();

  /// Convenience for callers that need the package folder of the sources.
  static String sourcesDir(Project p) => 'src/main/java/${JavaGenerator.packageDir(p)}';
}