/// Mini neural network for build analysis and pre-export validation.
///
/// A single-layer "network" built from lambda functions (neurons). Each
/// neuron is a `double Function(_Inputs)` that evaluates one aspect of the
/// project/build and returns a value in [0, 1]. The output layer is a
/// weighted sum producing a health score in [0, 100] plus a list of
/// human-readable issues.
///
/// Two entry points feed the same network:
///  * [BuildAnalyzer.analyze] — after a real build on the server;
///  * [BuildAnalyzer.validate] — before an export, without a build, to catch
///    inconsistencies such as an FXML `fx:controller` that points to a class
///    outside the project package (which would fail with
///    `ClassNotFoundException` at launch).
///
/// Designed to run in milliseconds with zero allocations beyond a few small
/// maps — minimal system load, no training, no external dependencies.
library;

import '../project/project.dart';
import '../project/project_history.dart';

/// What produced the report: a server build or a pre-export check.
enum BuildReportKind {
  /// The project was compiled on the build server.
  build,

  /// Static checks run before an export (no compilation).
  export,
}

/// One line of a [BuildReport]: an English template key containing `{0}`,
/// `{1}` … placeholders plus the arguments. Resolved into the active
/// language when the report is displayed.
class ReportLine {
  const ReportLine(this.key, [this.args = const <String>[]]);

  /// English template (used as the localization key).
  final String key;

  /// Values substituted for `{0}`, `{1}` …
  final List<String> args;

  /// Renders the line: [tr] translates the template, then the placeholders
  /// are replaced with [args].
  String render(String Function(String) tr) {
    var out = tr(key);
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', args[i]);
    }
    return out;
  }

  @override
  String toString() => render((k) => k);
}

/// The result of the build analysis.
class BuildReport {
  const BuildReport({
    required this.score,
    required this.issues,
    required this.suggestions,
    required this.buildSucceeded,
    required this.buildDurationMs,
    this.kind = BuildReportKind.build,
    this.controllerIssueCount = 0,
  });

  /// Overall health score in [0, 100]. Higher is better.
  final int score;

  /// Problems detected by the neurons (empty when everything is fine).
  final List<ReportLine> issues;

  /// Recommendations how to fix the issues.
  final List<ReportLine> suggestions;

  /// Whether the compilation succeeded (always true for export checks).
  final bool buildSucceeded;

  /// How long the build took (0 for export checks).
  final int buildDurationMs;

  /// What produced this report.
  final BuildReportKind kind;

  /// Number of issues caused by scene controllers lying outside the project
  /// package. These can be repaired automatically.
  final int controllerIssueCount;

  /// True when the report came from the pre-export validation.
  bool get isExport => kind == BuildReportKind.export;

  /// True when the controller mismatches can be fixed automatically.
  bool get hasControllerIssues => controllerIssueCount > 0;

  /// True when the project looks healthy (score >= 80 and no critical issues).
  bool get isHealthy => score >= 80 && issues.isEmpty;

  /// Text badge shown in the dialog.
  String get badge {
    if (!buildSucceeded) return 'Build failed';
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 50) return 'Needs work';
    return 'Poor';
  }
}

/// Inputs fed into the network neurons.
class _Inputs {
  _Inputs(this._map);
  final Map<String, double> _map;
  double operator [](String key) => _map[key] ?? 0.0;
}

/// Mini neural network: input layer -> lambda neurons -> weighted output.
class BuildAnalyzer {
  BuildAnalyzer._();

  /// Analyzes the just-built project and returns a [BuildReport].
  static BuildReport analyze(Project project, BuildRecord build) => _run(
        project,
        kind: BuildReportKind.build,
        build: build,
      );

  /// Static pre-export check: runs the same network without a build record,
  /// so only the project consistency neurons are active.
  static BuildReport validate(Project project) => _run(
        project,
        kind: BuildReportKind.export,
      );

  static BuildReport _run(
    Project project, {
    required BuildReportKind kind,
    BuildRecord? build,
  }) {
    final controllerIssues = BuildAnalyzer.controllerProblems(project);
    final hasBuild = build != null;

    final inputs = _Inputs(<String, double>{
      'scenes': project.scenes.length.toDouble(),
      'hasDescription': project.description.isNotEmpty ? 1.0 : 0.0,
      'packageValid': _isValidJavaPackage(project.package) ? 1.0 : 0.0,
      'mainClassValid': project.mainClass.isNotEmpty ? 1.0 : 0.0,
      'hasScenes': project.scenes.isNotEmpty ? 1.0 : 0.0,
      'controllersOk': controllerIssues.isEmpty ? 1.0 : 0.0,
      if (hasBuild) ...<String, double>{
        'buildSucceeded': build.succeeded ? 1.0 : 0.0,
        'buildDuration': (build.durationMs / 1000.0).clamp(0, 60).toDouble(),
      },
    });

    // ---------------------------------------------------------- neurons
    // Each neuron is a lambda function that maps inputs -> [0, 1].
    final neurons = <String, double Function(_Inputs)>{
      // Is there at least one scene?
      'sceneCheck': (i) => i['hasScenes'],
      // Is the Java package valid?
      'packageCheck': (i) => i['packageValid'],
      // Is the main class set?
      'mainClassCheck': (i) => i['mainClassValid'],
      // Is there a project description?
      'descriptionCheck': (i) => i['hasDescription'],
      // Do the FXML controllers match the project package?
      'controllerCheck': (i) => i['controllersOk'],
      if (hasBuild) ...<String, double Function(_Inputs)>{
        // Did the build succeed?
        'buildCheck': (i) => i['buildSucceeded'],
        // Was the build fast enough (< 10 s)?
        'speedCheck': (i) =>
            i['buildDuration'] > 0 && i['buildDuration'] < 10 ? 1.0 : 0.5,
      },
    };

    // ---------------------------------------------------------- weights
    // Each set sums to 1.0.
    final weights = hasBuild
        ? <String, double>{
            'sceneCheck': 0.20,
            'packageCheck': 0.15,
            'mainClassCheck': 0.10,
            'descriptionCheck': 0.05,
            'buildCheck': 0.20,
            'speedCheck': 0.10,
            'controllerCheck': 0.20,
          }
        : <String, double>{
            'sceneCheck': 0.25,
            'packageCheck': 0.20,
            'mainClassCheck': 0.15,
            'descriptionCheck': 0.10,
            'controllerCheck': 0.30,
          };

    // ---------------------------------------------------------- forward pass
    double rawScore = 0;
    final issues = <ReportLine>[];
    final suggestions = <ReportLine>[];

    for (final name in neurons.keys) {
      final value = neurons[name]!(inputs);
      rawScore += value * weights[name]!;
      if (value < 1.0) {
        switch (name) {
          case 'sceneCheck':
            issues.add(const ReportLine('No scenes in the project.'));
            suggestions
                .add(const ReportLine('Add at least one scene to the project.'));
          case 'packageCheck':
            issues.add(const ReportLine('Java package is invalid.'));
            suggestions.add(const ReportLine(
                'Fix the Java package in project settings (letters, digits, underscores, dots).'));
          case 'mainClassCheck':
            issues.add(const ReportLine('Main class is not set.'));
            suggestions
                .add(const ReportLine('Set the main class in project settings.'));
          case 'descriptionCheck':
            issues.add(const ReportLine('Project description is empty.'));
            suggestions.add(const ReportLine(
                'Add a description — it will appear in the exported README.'));
          case 'buildCheck':
            issues.add(const ReportLine('Build failed.'));
            suggestions.add(
                const ReportLine('Check the build log in the history window.'));
          case 'speedCheck':
            issues
                .add(const ReportLine('Build took more than 10 seconds.'));
            suggestions.add(const ReportLine(
                'Consider simplifying the project or scenes.'));
          case 'controllerCheck':
            issues.addAll(controllerIssues);
            suggestions.add(ReportLine(
              'The controller package must match the project package "{0}". '
              'Update the scene controllers or the package in the settings.',
              <String>[project.package],
            ));
        }
      }
    }

    final score = (rawScore * 100).round().clamp(0, 100);

    return BuildReport(
      score: score,
      issues: issues,
      suggestions: suggestions,
      buildSucceeded: build?.succeeded ?? true,
      buildDurationMs: build?.durationMs ?? 0,
      kind: kind,
      controllerIssueCount: controllerIssues.length,
    );
  }

  // ------------------------------------------------------ controller checks

  /// Detects mismatches between the FXML `fx:controller` attribute, the
  /// controller declared on the scene and the project package — the classic
  /// `ClassNotFoundException` trap after the package was renamed.
  ///
  /// The Java generator always writes controllers into `project.package`,
  /// while the FXML keeps whatever controller it was authored with, so a
  /// package that no longer matches makes the application fail at launch.
  static List<ReportLine> controllerProblems(Project project) {
    final problems = <ReportLine>[];
    final pkg = project.package;
    for (final scene in project.scenes) {
      final name = scene.name;
      final fxmlFqn = _fxmlController(scene.fxml);
      final declared = (scene.controllerClass ?? '').trim();

      if (fxmlFqn != null && fxmlFqn.isNotEmpty) {
        if (_packageOf(fxmlFqn) != pkg) {
          problems.add(ReportLine(
            'Scene "{0}": the FXML refers to the controller "{1}", but the '
            'project package is "{2}". The application will not start.',
            <String>[name, fxmlFqn, pkg],
          ));
        } else if (declared.isNotEmpty &&
            _simpleNameOf(fxmlFqn) != _simpleNameOf(declared)) {
          problems.add(ReportLine(
            'Scene "{0}": the FXML controller "{1}" differs from the scene '
            'controller "{2}".',
            <String>[name, _simpleNameOf(fxmlFqn), _simpleNameOf(declared)],
          ));
        }
        if (declared.isEmpty) {
          problems.add(ReportLine(
            'Scene "{0}": the FXML refers to a controller, but the scene has '
            'no controller class.',
            <String>[name],
          ));
        }
      }

      // The declared controller is outside the package and was not already
      // reported through the FXML attribute above.
      if (declared.isNotEmpty &&
          declared.contains('.') &&
          _packageOf(declared) != pkg &&
          declared != fxmlFqn) {
        problems.add(ReportLine(
          'Scene "{0}": the controller "{1}" lies outside the project '
          'package "{2}".',
          <String>[name, declared, pkg],
        ));
      }
    }
    return problems;
  }

  /// The `fx:controller` value of an FXML document, or null when absent.
  static String? _fxmlController(String fxml) => RegExp(r'fx:controller\s*=\s*"([^"]+)"')
      .firstMatch(fxml)
      ?.group(1);

  static String _packageOf(String fqn) {
    final i = fqn.lastIndexOf('.');
    return i < 0 ? '' : fqn.substring(0, i);
  }

  static String _simpleNameOf(String fqn) {
    final i = fqn.lastIndexOf('.');
    return i < 0 ? fqn : fqn.substring(i + 1);
  }

  static bool _isValidJavaPackage(String package) {
    if (package.isEmpty) return false;
    if (package.startsWith('.') || package.endsWith('.')) return false;
    if (package.contains('..')) return false;
    if (package.contains(' ')) return false;
    final segments = package.split('.');
    for (final segment in segments) {
      if (segment.isEmpty) return false;
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(segment)) return false;
    }
    return true;
  }
}
