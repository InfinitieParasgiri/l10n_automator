import 'dart:io';

import 'package:yaml/yaml.dart';

import 'config.dart';

/// Detects which localization stack a target Flutter project is using by
/// inspecting its pubspec.yaml.
class StackDetector {
  /// Returns the detected [L10nStack], or [L10nStack.flutterLocalizations]
  /// as the safest default if nothing is detected.
  static L10nStack detect(String projectRoot) {
    final pubspec = File('$projectRoot/pubspec.yaml');
    if (!pubspec.existsSync()) return L10nStack.flutterLocalizations;
    final raw = loadYaml(pubspec.readAsStringSync());
    if (raw is! YamlMap) return L10nStack.flutterLocalizations;

    final deps = <String>{
      ..._depKeys(raw['dependencies']),
      ..._depKeys(raw['dev_dependencies']),
    };

    final hasEasy = deps.contains('easy_localization');
    final hasFlutterL10n = deps.contains('flutter_localizations');

    // If both are present, prefer flutter_localizations (the official path).
    if (hasFlutterL10n) return L10nStack.flutterLocalizations;
    if (hasEasy) return L10nStack.easyLocalization;
    return L10nStack.flutterLocalizations;
  }

  /// Resolve [Config.stack] to a concrete stack. If config says `auto`,
  /// fall back to detection.
  static L10nStack resolve(Config config, String projectRoot) {
    if (config.stack != L10nStack.auto) return config.stack;
    return detect(projectRoot);
  }

  static Iterable<String> _depKeys(Object? node) {
    if (node is YamlMap) return node.keys.map((k) => k.toString());
    return const [];
  }
}
