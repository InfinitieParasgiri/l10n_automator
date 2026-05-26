import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/config.dart';

/// Common interface for emitting calls into a specific l10n stack.
abstract class L10nAdapter {
  String get name;

  /// True if `AppLocalizations.of(context)` requires a BuildContext in scope.
  bool get needsBuildContext;

  /// The single import line to inject at the top of a rewritten file.
  String get requiredImport;

  /// Render the call expression for [key] with [placeholders] (name -> Dart
  /// expression source text).
  ///
  /// Example flutter_localizations: `AppLocalizations.of(context)!.foo(bar)`
  /// Example easy_localization:    `'foo'.tr(args: [bar.toString()])`
  String renderCall(String key, Map<String, String> placeholders);

  /// Factory that picks the right adapter for the configured stack.
  ///
  /// [projectRoot] is used by the flutter_localizations adapter to read the
  /// target project's `pubspec.yaml` + `l10n.yaml` and compute the right
  /// import path (synthetic package vs. on-disk).
  static L10nAdapter forStack(
    L10nStack stack,
    Config config, {
    String? projectRoot,
  }) {
    switch (stack) {
      case L10nStack.flutterLocalizations:
      case L10nStack.auto:
        return FlutterL10nAdapter(config, projectRoot: projectRoot);
      case L10nStack.easyLocalization:
        return EasyLocalizationAdapter(config);
    }
  }
}

class FlutterL10nAdapter implements L10nAdapter {
  FlutterL10nAdapter(this.config, {this.projectRoot}) {
    _resolvedImport = _resolveImport();
  }

  final Config config;
  final String? projectRoot;
  late final String _resolvedImport;

  @override
  String get name => 'flutter_localizations';

  @override
  bool get needsBuildContext => true;

  @override
  String get requiredImport => _resolvedImport;

  /// Strategy (in priority order):
  ///   1. Explicit override in .localizator.yaml: `localizations_import:`.
  ///   2. If l10n.yaml has `synthetic-package: false` OR the file already
  ///      exists at `<output-dir-or-arb-dir>/<output-file>`, emit
  ///      `package:<pubspec.name>/<rel-from-lib>/<output-file>`.
  ///   3. Fallback: synthetic package path
  ///      `package:flutter_gen/gen_l10n/<file>`.
  String _resolveImport() {
    // 1. Explicit override.
    if (config.localizationsImport.isNotEmpty) {
      return "import '${config.localizationsImport}';";
    }

    final root = projectRoot;
    final outputFile = _defaultOutputFile();

    if (root != null) {
      final l10n = _loadL10nYaml(root);
      final packageName = _readPubspecName(root);

      final outputDir = (l10n['output-dir'] as String?) ??
          (l10n['arb-dir'] as String?) ??
          config.arbDir;
      final outputFileName =
          (l10n['output-localization-file'] as String?) ?? outputFile;
      final synthetic = l10n['synthetic-package'];

      // Resolve the path of the generated file relative to project root.
      final relFromRoot = p
          .normalize(p.join(outputDir, outputFileName))
          .split(p.separator)
          .join('/');
      final absPath = p.join(root, relFromRoot);

      final fileExistsOnDisk = File(absPath).existsSync();
      final useOnDisk =
          (synthetic is bool && synthetic == false) || fileExistsOnDisk;

      if (useOnDisk && packageName != null) {
        // Strip leading 'lib/' for the package: URI.
        final fromLib = relFromRoot.startsWith('lib/')
            ? relFromRoot.substring('lib/'.length)
            : relFromRoot;
        return "import 'package:$packageName/$fromLib';";
      }
    }

    // Fallback: synthetic package import.
    return "import 'package:flutter_gen/gen_l10n/$outputFile';";
  }

  /// Default output file name from `output_class` (gen_l10n convention).
  /// AppLocalizations -> app_localizations.dart
  String _defaultOutputFile() {
    final cls = config.outputClass;
    final snake = cls
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
    return '$snake.dart';
  }

  Map<String, Object?> _loadL10nYaml(String root) {
    final f = File(p.join(root, 'l10n.yaml'));
    if (!f.existsSync()) return const <String, Object?>{};
    try {
      final parsed = loadYaml(f.readAsStringSync());
      if (parsed is YamlMap) {
        return parsed.cast<String, Object?>();
      }
    } catch (_) {
      // Malformed l10n.yaml — fall back silently.
    }
    return const <String, Object?>{};
  }

  String? _readPubspecName(String root) {
    final f = File(p.join(root, 'pubspec.yaml'));
    if (!f.existsSync()) return null;
    try {
      final parsed = loadYaml(f.readAsStringSync());
      if (parsed is YamlMap) {
        final name = parsed['name'];
        if (name is String && name.isNotEmpty) return name;
      }
    } catch (_) {
      // Malformed pubspec.yaml.
    }
    return null;
  }

  @override
  String renderCall(String key, Map<String, String> placeholders) {
    final getter = '${config.outputClass}.of(context)!.$key';
    if (placeholders.isEmpty) return getter;
    final args = placeholders.values.join(', ');
    return '$getter($args)';
  }
}

class EasyLocalizationAdapter implements L10nAdapter {
  EasyLocalizationAdapter(this.config);
  final Config config;

  @override
  String get name => 'easy_localization';

  @override
  bool get needsBuildContext => false;

  @override
  String get requiredImport =>
      "import 'package:easy_localization/easy_localization.dart';";

  @override
  String renderCall(String key, Map<String, String> placeholders) {
    if (placeholders.isEmpty) return "'$key'.tr()";
    // easy_localization named-args form: 'key'.tr(namedArgs: {'name': name.toString()})
    final namedArgs = placeholders.entries
        .map((e) => "'${e.key}': ${e.value}.toString()")
        .join(', ');
    return "'$key'.tr(namedArgs: {$namedArgs})";
  }
}
