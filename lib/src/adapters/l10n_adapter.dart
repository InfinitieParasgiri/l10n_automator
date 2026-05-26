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
  static L10nAdapter forStack(L10nStack stack, Config config) {
    switch (stack) {
      case L10nStack.flutterLocalizations:
      case L10nStack.auto:
        return FlutterL10nAdapter(config);
      case L10nStack.easyLocalization:
        return EasyLocalizationAdapter(config);
    }
  }
}

class FlutterL10nAdapter implements L10nAdapter {
  FlutterL10nAdapter(this.config);
  final Config config;

  @override
  String get name => 'flutter_localizations';

  @override
  bool get needsBuildContext => true;

  @override
  String get requiredImport =>
      "import 'package:flutter_gen/gen_l10n/${_outputFileName()}';";

  String _outputFileName() {
    // Default generated file name from `output_class` (gen_l10n convention).
    // AppLocalizations -> app_localizations.dart
    final cls = config.outputClass;
    final snake = cls.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)}_${m.group(2)}',
    ).toLowerCase();
    return '$snake.dart';
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
