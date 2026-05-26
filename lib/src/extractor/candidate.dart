import 'package:analyzer/dart/ast/ast.dart';

/// Classification decision for a string literal found in source.
enum Decision {
  /// Definitely localize. Safe to rewrite in --auto mode.
  localize,

  /// Definitely skip. Never localize (URL, asset path, etc.).
  skip,

  /// Ambiguous. Prompt in interactive mode; skip in --auto mode unless
  /// the user lowers the threshold via config.
  review,
}

/// A string literal found by the scanner, with everything needed to make a
/// rewrite decision.
class Candidate {
  Candidate({
    required this.filePath,
    required this.source,
    required this.node,
    required this.literalValue,
    required this.hasInterpolation,
    required this.interpolationPlaceholders,
    required this.parentContextDescription,
    required this.hasBuildContextInScope,
    required this.decision,
    required this.reason,
    this.overrideKey,
  });

  /// Absolute path to the .dart file.
  final String filePath;

  /// Full file source (so the rewriter can compute byte offsets reliably).
  final String source;

  /// The string-literal AST node (StringLiteral or StringInterpolation).
  final StringLiteral node;

  /// The string value with interpolations replaced by `{name}` placeholders
  /// (ICU-style), so it can be written directly to ARB.
  final String literalValue;

  final bool hasInterpolation;

  /// Map of placeholder name -> the original Dart expression that filled it.
  /// E.g. for `"Hello $name"`, `{ "name": "name" }`.
  /// For `"Total: ${cart.total}"`, `{ "cartTotal": "cart.total" }`.
  final Map<String, String> interpolationPlaceholders;

  /// Human-readable label of where this string was found, used in reports
  /// (e.g. `Text(child:)`, `AppBar(title:)`, `throw Exception(...)`).
  final String parentContextDescription;

  /// Whether a `BuildContext`-typed parameter is in scope at this call site.
  final bool hasBuildContextInScope;

  final Decision decision;
  final String reason;

  /// Optional per-line override key (from `// l10n:key=foo` comment).
  final String? overrideKey;
}
