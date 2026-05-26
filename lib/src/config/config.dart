import 'dart:io';

import 'package:yaml/yaml.dart';

/// Which localization stack the target project uses.
enum L10nStack { flutterLocalizations, easyLocalization, auto }

/// What to do when a string would need a BuildContext but none is in scope.
enum OnMissingContext { skip, error, prompt }

/// Naming style for generated keys.
enum KeyStyle { camelCase, snakeCase }

/// Tool-wide configuration. Loaded from .localizator.yaml at project root,
/// or filled with defaults if no file exists.
class Config {
  Config({
    this.stack = L10nStack.auto,
    this.arbDir = 'lib/l10n',
    this.templateArbFile = 'app_en.arb',
    this.outputClass = 'AppLocalizations',
    this.translationsDir = 'assets/translations',
    this.fallbackLocale = 'en',
    this.keyStyle = KeyStyle.camelCase,
    this.keyMaxLength = 40,
    this.keyPrefix = '',
    this.minStringLength = 2,
    this.ignoreFileGlobs = const [
      '**/*.g.dart',
      '**/*.freezed.dart',
      '**/*.gr.dart',
      '**/*.mocks.dart',
      '**/*.config.dart',
      '**/generated/**',
      '**/.dart_tool/**',
      '**/build/**',
      '**/test/**',
      '**/integration_test/**',
    ],
    this.ignorePatterns = const [
      r'^https?://',
      r'^/api/',
      r'^mailto:',
      r'\.(png|jpg|jpeg|gif|webp|svg|json|mp3|mp4|webm|ttf|otf|lottie)$',
      r'^[A-Z0-9_]{16,}$',
    ],
    this.ignoreWidgets = const [
      'Image.asset',
      'AssetImage',
      'SvgPicture.asset',
      'Lottie.asset',
      'MethodChannel',
      'EventChannel',
      'RegExp',
      'DateFormat',
    ],
    this.reviewExceptions = true,
    this.reviewTopLevelConsts = true,
    this.onMissingContext = OnMissingContext.skip,
    this.fillMissingFromTemplate = true,
    this.placeholderPrefix = '[TODO] ',
    this.runFormatter = true,
    this.runAnalyzer = true,
    this.runGenL10n = true,
    this.localizationsImport = '',
  });

  final L10nStack stack;

  // flutter_localizations options
  final String arbDir;
  final String templateArbFile;
  final String outputClass;

  // easy_localization options
  final String translationsDir;
  final String fallbackLocale;

  // key naming
  final KeyStyle keyStyle;
  final int keyMaxLength;
  final String keyPrefix;
  final int minStringLength;

  // ignore rules
  final List<String> ignoreFileGlobs;
  final List<String> ignorePatterns;
  final List<String> ignoreWidgets;

  // review rules
  final bool reviewExceptions;
  final bool reviewTopLevelConsts;

  // context behavior
  final OnMissingContext onMissingContext;

  // locales
  final bool fillMissingFromTemplate;
  final String placeholderPrefix;

  // post actions
  final bool runFormatter;
  final bool runAnalyzer;
  final bool runGenL10n;

  /// Optional explicit import URI for AppLocalizations. When non-empty,
  /// overrides auto-detection of synthetic vs on-disk paths. Example:
  /// `package:my_app/l10n/app_localizations.dart`.
  final String localizationsImport;

  /// Load config from `.localizator.yaml` at [projectRoot]; if missing, use
  /// defaults.
  static Config load(String projectRoot, {String? overridePath}) {
    final path = overridePath ?? '$projectRoot/.localizator.yaml';
    final file = File(path);
    if (!file.existsSync()) return Config();
    final raw = loadYaml(file.readAsStringSync()) as YamlMap?;
    if (raw == null) return Config();
    return _fromYaml(raw);
  }

  static Config _fromYaml(YamlMap y) {
    L10nStack parseStack(Object? v) {
      switch (v?.toString()) {
        case 'flutter_localizations':
          return L10nStack.flutterLocalizations;
        case 'easy_localization':
          return L10nStack.easyLocalization;
        case 'auto':
        case null:
          return L10nStack.auto;
        default:
          throw FormatException('Unknown stack: $v');
      }
    }

    KeyStyle parseKeyStyle(Object? v) {
      switch (v?.toString()) {
        case 'snake_case':
          return KeyStyle.snakeCase;
        case 'camelCase':
        case null:
          return KeyStyle.camelCase;
        default:
          throw FormatException('Unknown key style: $v');
      }
    }

    OnMissingContext parseOmc(Object? v) {
      switch (v?.toString()) {
        case 'error':
          return OnMissingContext.error;
        case 'prompt':
          return OnMissingContext.prompt;
        case 'skip':
        case null:
          return OnMissingContext.skip;
        default:
          throw FormatException('Unknown on_missing_build_context: $v');
      }
    }

    List<String> strList(Object? v, List<String> fallback) {
      if (v is YamlList) return v.map((e) => e.toString()).toList();
      return fallback;
    }

    final keyNaming = y['key_naming'] as YamlMap?;
    final ignore = y['ignore'] as YamlMap?;
    final review = y['review'] as YamlMap?;
    final ctx = y['context'] as YamlMap?;
    final locales = y['locales'] as YamlMap?;
    final post = y['post_actions'] as YamlMap?;

    final defaults = Config();
    return Config(
      stack: parseStack(y['stack']),
      arbDir: (y['arb_dir'] as String?) ?? defaults.arbDir,
      templateArbFile:
          (y['template_arb_file'] as String?) ?? defaults.templateArbFile,
      outputClass: (y['output_class'] as String?) ?? defaults.outputClass,
      translationsDir:
          (y['translations_dir'] as String?) ?? defaults.translationsDir,
      fallbackLocale:
          (y['fallback_locale'] as String?) ?? defaults.fallbackLocale,
      keyStyle: parseKeyStyle(keyNaming?['style']),
      keyMaxLength: (keyNaming?['max_length'] as int?) ?? defaults.keyMaxLength,
      keyPrefix: (keyNaming?['prefix'] as String?) ?? defaults.keyPrefix,
      minStringLength:
          (y['min_string_length'] as int?) ?? defaults.minStringLength,
      ignoreFileGlobs:
          strList(ignore?['files'], defaults.ignoreFileGlobs),
      ignorePatterns:
          strList(ignore?['patterns'], defaults.ignorePatterns),
      ignoreWidgets:
          strList(ignore?['widgets'], defaults.ignoreWidgets),
      reviewExceptions:
          (review?['exceptions'] as bool?) ?? defaults.reviewExceptions,
      reviewTopLevelConsts: (review?['top_level_consts'] as bool?) ??
          defaults.reviewTopLevelConsts,
      onMissingContext: parseOmc(ctx?['on_missing_build_context']),
      fillMissingFromTemplate: (locales?['fill_missing_from_template']
              as bool?) ??
          defaults.fillMissingFromTemplate,
      placeholderPrefix: (locales?['placeholder_prefix'] as String?) ??
          defaults.placeholderPrefix,
      runFormatter:
          (post?['run_formatter'] as bool?) ?? defaults.runFormatter,
      runAnalyzer:
          (post?['run_analyzer'] as bool?) ?? defaults.runAnalyzer,
      runGenL10n: (post?['run_gen_l10n'] as bool?) ?? defaults.runGenL10n,
      localizationsImport:
          (y['localizations_import'] as String?) ?? defaults.localizationsImport,
    );
  }

  /// A canonical YAML representation, used by the `init` command.
  static String defaultYaml() => '''
# l10n_automator configuration.
# Run `dart run l10n_automator scan` for a dry-run report.

stack: auto                       # auto | flutter_localizations | easy_localization

# flutter_localizations options (ignored for easy_localization stack)
arb_dir: lib/l10n
template_arb_file: app_en.arb
output_class: AppLocalizations

# easy_localization options (ignored for flutter_localizations stack)
translations_dir: assets/translations
fallback_locale: en

key_naming:
  style: camelCase                # camelCase | snake_case
  max_length: 40
  prefix: ""

min_string_length: 2

ignore:
  files:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.gr.dart"
    - "**/*.mocks.dart"
    - "**/*.config.dart"
    - "**/generated/**"
    - "**/.dart_tool/**"
    - "**/build/**"
    - "**/test/**"
    - "**/integration_test/**"
  patterns:
    - "^https?://"
    - "^/api/"
    - "^mailto:"
    - "\\\\.(png|jpg|jpeg|gif|webp|svg|json|mp3|mp4|webm|ttf|otf|lottie)\$"
    - "^[A-Z0-9_]{16,}\$"
  widgets:
    - Image.asset
    - AssetImage
    - SvgPicture.asset
    - Lottie.asset
    - MethodChannel
    - EventChannel
    - RegExp
    - DateFormat

review:
  exceptions: true                # flag throw Exception("...") for review
  top_level_consts: true

context:
  on_missing_build_context: skip  # skip | error | prompt

locales:
  fill_missing_from_template: true
  placeholder_prefix: "[TODO] "

post_actions:
  run_formatter: true
  run_analyzer: true
  run_gen_l10n: true              # only for flutter_localizations
''';
}
