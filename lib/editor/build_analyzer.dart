/// Mini neural network for build analysis.
///
/// A single-layer "network" built from lambda functions (neurons). Each
/// neuron is a `double Function(Map<String, double>)` that evaluates one
/// aspect of the project/build and returns a value in [0, 1]. The output
/// layer is a weighted sum producing a health score in [0, 100] plus a list
/// of human-readable issues.
///
/// Designed to run in milliseconds with zero allocations beyond a few small
/// maps — minimal system load, no training, no external dependencies.
library;

import '../project/project.dart';
import '../project/project_history.dart';

/// The result of the build analysis.
class BuildReport {
  const BuildReport({
    required this.score,
    required this.issues,
    required this.suggestions,
    required this.buildSucceeded,
    required this.buildDurationMs,
  });

  /// Overall health score in [0, 100]. Higher is better.
  final int score;

  /// Problems detected by the neurons (empty when everything is fine).
  final List<String> issues;

  /// Recommendations how to fix the issues.
  final List<String> suggestions;

  /// Whether the compilation succeeded.
  final bool buildSucceeded;

  /// How long the build took.
  final int buildDurationMs;

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
  static BuildReport analyze(Project project, BuildRecord build) {
    final inputs = _Inputs(<String, double>{
      'scenes': project.scenes.length.toDouble(),
      'hasDescription': project.description.isNotEmpty ? 1.0 : 0.0,
      'packageValid': _isValidJavaPackage(project.package) ? 1.0 : 0.0,
      'mainClassValid': project.mainClass.isNotEmpty ? 1.0 : 0.0,
      'buildSucceeded': build.succeeded ? 1.0 : 0.0,
      'buildDuration': (build.durationMs / 1000.0).clamp(0, 60).toDouble(),
      'hasScenes': project.scenes.isNotEmpty ? 1.0 : 0.0,
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
      // Did the build succeed?
      'buildCheck': (i) => i['buildSucceeded'],
      // Was the build fast enough (< 10 s)?
      'speedCheck': (i) =>
          i['buildDuration'] > 0 && i['buildDuration'] < 10 ? 1.0 : 0.5,
    };

    // ---------------------------------------------------------- weights
    final weights = <String, double>{
      'sceneCheck': 0.25,
      'packageCheck': 0.20,
      'mainClassCheck': 0.15,
      'descriptionCheck': 0.10,
      'buildCheck': 0.20,
      'speedCheck': 0.10,
    };

    // ---------------------------------------------------------- forward pass
    double rawScore = 0;
    final issues = <String>[];
    final suggestions = <String>[];

    for (final name in neurons.keys) {
      final value = neurons[name]!(inputs);
      rawScore += value * weights[name]!;
      if (value < 1.0) {
        switch (name) {
          case 'sceneCheck':
            issues.add('No scenes in the project.');
            suggestions.add('Add at least one scene to the project.');
          case 'packageCheck':
            issues.add('Java package is invalid.');
            suggestions.add(
                'Fix the Java package in project settings (letters, digits, underscores, dots).');
          case 'mainClassCheck':
            issues.add('Main class is not set.');
            suggestions.add('Set the main class in project settings.');
          case 'descriptionCheck':
            issues.add('Project description is empty.');
            suggestions.add(
                'Add a description — it will appear in the exported README.');
          case 'buildCheck':
            issues.add('Build failed.');
            suggestions.add('Check the build log in the history window.');
          case 'speedCheck':
            issues.add('Build took more than 10 seconds.');
            suggestions.add('Consider simplifying the project or scenes.');
        }
      }
    }

    final score = (rawScore * 100).round().clamp(0, 100);

    return BuildReport(
      score: score,
      issues: issues,
      suggestions: suggestions,
      buildSucceeded: build.succeeded,
      buildDurationMs: build.durationMs,
    );
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
