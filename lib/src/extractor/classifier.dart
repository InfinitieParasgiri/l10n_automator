import '../config/config.dart';
import 'candidate.dart';

/// Context gathered by the AST visitor for a single string literal.
class CallSiteContext {
  CallSiteContext({
    this.methodName,
    this.constructorName,
    this.namedArgument,
    this.positionalIndex,
    this.isInAnnotation = false,
    this.isInAssertMessage = false,
    this.isInThrow = false,
    this.isInMapLiteralKey = false,
    this.isInIndexExpression = false,
    this.isInImport = false,
    this.isInLogCall = false,
    this.isTopLevelConst = false,
    this.isInBinaryConcat = false,
    this.isInRouteNamedArg = false,
    this.isInConstContext = false,
    this.parentDescription = 'unknown',
  });

  /// Method or function name the string is an argument to.
  final String? methodName;

  /// Constructor name, if it's a `new Foo(...)` call.
  /// May include receiver (e.g. `Image.asset`).
  final String? constructorName;

  final String? namedArgument;
  final int? positionalIndex;

  final bool isInAnnotation;
  final bool isInAssertMessage;
  final bool isInThrow;
  final bool isInMapLiteralKey;
  final bool isInIndexExpression;
  final bool isInImport;
  final bool isInLogCall;
  final bool isTopLevelConst;
  final bool isInBinaryConcat;
  final bool isInRouteNamedArg;

  /// True if the string is inside a `const ...` expression (e.g.
  /// `const Text('Hi')`, `const SomeWidget(label: 'Hi')`). The rewrite
  /// would introduce a non-const call (`AppLocalizations.of(context)!.foo`),
  /// breaking the const context — so we leave these for the human.
  final bool isInConstContext;

  final String parentDescription;
}

class ClassificationResult {
  ClassificationResult(this.decision, this.reason);
  final Decision decision;
  final String reason;
}

/// Decides whether a given string literal should be localized, skipped, or
/// flagged for review. This is the heart of the tool's safety guarantees.
class Classifier {
  Classifier(this.config) : _ignoreRegexes = [
          for (final p in config.ignorePatterns) RegExp(p),
        ];

  final Config config;
  final List<RegExp> _ignoreRegexes;

  static const _logFunctions = <String>{
    'print',
    'debugPrint',
    'log',
    'developer.log',
  };

  static const _loggerMethods = <String>{
    'd', 'i', 'w', 'e', 'v', 't', 'f',
    'debug', 'info', 'warning', 'error', 'verbose', 'trace', 'fatal',
    'log', // dev.log, Logger.log, _logger.log
  };

  /// Constructor / method names that take string args that should never be
  /// localized.
  static const _builtinSkippedCallees = <String>{
    'Image.asset',
    'AssetImage',
    'SvgPicture.asset',
    'Lottie.asset',
    'rootBundle.loadString',
    'rootBundle.load',
    'MethodChannel',
    'EventChannel',
    'BasicMessageChannel',
    'RegExp',
    'DateFormat',
    'Uri.parse',
    'Uri',
    'String.fromEnvironment',
    'int.fromEnvironment',
    'bool.fromEnvironment',
    'Platform.environment',
  };

  /// Named arguments whose string values are UI labels (most are
  /// String-typed in Flutter).
  static const _uiStringNamedArgs = <String>{
    'hintText',
    'helperText',
    'errorText',
    'labelText',
    'prefixText',
    'suffixText',
    'counterText',
    'semanticsLabel',
    'tooltip',
    'message',
    'restorationId', // identifier, but rarely UI — see deny below
  };

  /// Named arguments that are identifiers, not UI labels.
  static const _identifierNamedArgs = <String>{
    'restorationId',
    'heroTag',
    'debugLabel',
    'tag',
    'name',
    'routeName',
    'initialRoute',
  };

  /// Widgets whose first positional String arg is the visible text.
  static const _uiPositionalConstructors = <String>{
    'Text',
    'SelectableText',
    'TextSpan',
    'WidgetSpan', // rare
  };

  ClassificationResult classify({
    required String value,
    required CallSiteContext context,
    required bool hasInterpolation,
  }) {
    // 0) Empty / whitespace / no-letter values are not user text.
    if (value.isEmpty) {
      return ClassificationResult(Decision.skip, 'empty string');
    }
    if (value.trim().isEmpty) {
      return ClassificationResult(Decision.skip, 'whitespace only');
    }
    if (!_hasAnyLetter(value)) {
      return ClassificationResult(
          Decision.skip, 'no letters (punctuation/symbols)');
    }
    if (value.length < config.minStringLength) {
      return ClassificationResult(
          Decision.skip, 'shorter than min_string_length');
    }

    // 1) Regex-based value skip rules (URLs, asset extensions, env keys).
    for (final r in _ignoreRegexes) {
      if (r.hasMatch(value)) {
        return ClassificationResult(
            Decision.skip, 'matches ignore pattern ${r.pattern}');
      }
    }

    // 2) Context-based skip: never localize in these positions.
    if (context.isInImport) {
      return ClassificationResult(Decision.skip, 'inside import directive');
    }
    if (context.isInAnnotation) {
      return ClassificationResult(Decision.skip, 'inside annotation');
    }
    if (context.isInAssertMessage) {
      return ClassificationResult(Decision.skip, 'inside assert message');
    }
    if (context.isInMapLiteralKey) {
      return ClassificationResult(Decision.skip, 'map literal key');
    }
    if (context.isInIndexExpression) {
      return ClassificationResult(
          Decision.skip, 'index expression (map/list lookup)');
    }
    if (context.isInLogCall) {
      return ClassificationResult(Decision.skip, 'logging call');
    }
    if (context.isInRouteNamedArg) {
      return ClassificationResult(Decision.skip, 'route name');
    }

    // 3) Callee-based skip.
    final calleeMatch = _matchesSkippedCallee(context);
    if (calleeMatch != null) {
      return ClassificationResult(
          Decision.skip, 'argument to $calleeMatch');
    }

    final callee = context.constructorName ?? context.methodName ?? '';
    if (_logFunctions.contains(callee)) {
      return ClassificationResult(Decision.skip, 'log function $callee');
    }

    // Detect Logger().d("..."), talker.info("..."), etc.
    if (_isLikelyLoggerMethod(callee, context)) {
      return ClassificationResult(
          Decision.skip, 'logger method $callee');
    }

    if (context.namedArgument != null &&
        _identifierNamedArgs.contains(context.namedArgument)) {
      return ClassificationResult(
          Decision.skip, 'identifier-typed arg ${context.namedArgument}:');
    }

    // 4) Review-flagged contexts.
    if (context.isInThrow && config.reviewExceptions) {
      return ClassificationResult(
          Decision.review, 'inside throw — may or may not reach UI');
    }
    if (context.isTopLevelConst && config.reviewTopLevelConsts) {
      return ClassificationResult(
          Decision.review, 'top-level const — could be config or UI label');
    }
    if (context.isInBinaryConcat) {
      return ClassificationResult(
          Decision.review,
          'string concatenation with `+` — should be rewritten as interpolation first');
    }

    // 5) UI-positive signals.
    //
    // If the string is inside a `const` expression, we'd otherwise rewrite
    // it to a non-const `AppLocalizations.of(context)!.foo` call, which
    // makes `const` invalid. Downgrade to review so the human can decide
    // whether to drop the const or change the surrounding code.
    if (context.namedArgument != null &&
        _uiStringNamedArgs.contains(context.namedArgument) &&
        !_identifierNamedArgs.contains(context.namedArgument)) {
      if (context.isInConstContext) {
        return ClassificationResult(
            Decision.review,
            'UI named arg ${context.namedArgument}: inside const — '
            'rewrite would break const-ness');
      }
      return ClassificationResult(
          Decision.localize,
          'UI-typed named arg ${context.namedArgument}:');
    }

    if (context.positionalIndex == 0 &&
        context.constructorName != null &&
        _uiPositionalConstructors.contains(context.constructorName)) {
      if (context.isInConstContext) {
        return ClassificationResult(
            Decision.review,
            'first positional arg to ${context.constructorName} inside '
            'const — rewrite would break const-ness');
      }
      return ClassificationResult(
          Decision.localize,
          'first positional arg to ${context.constructorName}');
    }

    // 6) Default: review. Conservative — auto mode will skip these.
    return ClassificationResult(
        Decision.review, 'no rule matched — review recommended');
  }

  String? _matchesSkippedCallee(CallSiteContext ctx) {
    final callee = ctx.constructorName ?? ctx.methodName;
    if (callee == null) return null;
    if (_builtinSkippedCallees.contains(callee)) return callee;
    if (config.ignoreWidgets.contains(callee)) return callee;
    // Handle wildcard match for things like `Foo.fromEnvironment`.
    for (final pattern in config.ignoreWidgets) {
      if (callee == pattern) return callee;
    }
    return null;
  }

  bool _isLikelyLoggerMethod(String callee, CallSiteContext ctx) {
    // Heuristic: a method named d/i/w/e/... called on a target whose name
    // contains "log" or matches popular logger libs (e.g. `talker.info(...)`,
    // `logger.d(...)`, `_log.warning(...)`).
    final lastSegment = callee.contains('.')
        ? callee.substring(callee.lastIndexOf('.') + 1)
        : callee;
    if (!_loggerMethods.contains(lastSegment)) return false;
    final targetSegment = callee.contains('.')
        ? callee.substring(0, callee.lastIndexOf('.')).toLowerCase()
        : '';
    if (targetSegment.contains('log') ||
        targetSegment.contains('talker') ||
        targetSegment.contains('logger')) {
      return true;
    }
    // Fall back to the descriptive parent string the visitor recorded.
    final parent = ctx.parentDescription.toLowerCase();
    return parent.contains('log') ||
        parent.contains('talker') ||
        parent.contains('logger');
  }

  static bool _hasAnyLetter(String s) =>
      RegExp(r'[A-Za-zÀ-￿]').hasMatch(s);
}
