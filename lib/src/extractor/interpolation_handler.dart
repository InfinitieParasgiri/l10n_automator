import 'package:analyzer/dart/ast/ast.dart';

/// Converts a Dart StringInterpolation into:
///   - an ARB-friendly value (interpolations replaced by `{name}`), and
///   - a map of placeholder name -> original Dart expression text.
class InterpolationConversion {
  InterpolationConversion(this.arbValue, this.placeholders);
  final String arbValue;
  final Map<String, String> placeholders;
}

/// Pure logic — given an AST node, return the ARB value + placeholder map.
class InterpolationHandler {
  /// For a [SimpleStringLiteral] (no interpolation), the value is the literal.
  static InterpolationConversion fromSimple(SimpleStringLiteral s) {
    return InterpolationConversion(s.value, const {});
  }

  /// For an [AdjacentStrings] ("foo" "bar"), concatenate child values.
  static InterpolationConversion fromAdjacent(AdjacentStrings a) {
    final buf = StringBuffer();
    final placeholders = <String, String>{};
    var phCounter = 0;
    for (final s in a.strings) {
      final piece = _convert(s, () => 'arg${++phCounter}');
      buf.write(piece.arbValue);
      placeholders.addAll(piece.placeholders);
    }
    return InterpolationConversion(buf.toString(), placeholders);
  }

  /// For a [StringInterpolation] ("Hello $name"), build the ARB form.
  static InterpolationConversion fromInterpolation(StringInterpolation si) {
    final buf = StringBuffer();
    final placeholders = <String, String>{};
    var counter = 0;
    for (final element in si.elements) {
      if (element is InterpolationString) {
        // Literal piece: escape any `{` or `}` for ICU.
        buf.write(_escapeIcuBraces(element.value));
      } else if (element is InterpolationExpression) {
        final exprText = element.expression.toSource();
        final name = _derivePlaceholderName(exprText, counter);
        counter++;
        // De-duplicate: if the same expression appears twice, reuse the name.
        final existing = placeholders.entries.firstWhere(
          (e) => e.value == exprText,
          orElse: () => MapEntry(name, exprText),
        );
        final finalName = existing.key;
        placeholders[finalName] = exprText;
        buf.write('{$finalName}');
      }
    }
    return InterpolationConversion(buf.toString(), placeholders);
  }

  static InterpolationConversion _convert(
    StringLiteral s,
    String Function() nameGen,
  ) {
    if (s is SimpleStringLiteral) return fromSimple(s);
    if (s is StringInterpolation) return fromInterpolation(s);
    if (s is AdjacentStrings) return fromAdjacent(s);
    return InterpolationConversion(s.toSource(), const {});
  }

  /// Derive a camelCase placeholder name from a Dart expression.
  /// `name` -> `name`, `user.firstName` -> `userFirstName`, `i + 1` -> `arg<n>`.
  static String _derivePlaceholderName(String expr, int counter) {
    final cleaned = expr.replaceAll(RegExp(r'\s+'), '');
    // Match simple identifier-or-property-access chains.
    final m = RegExp(r'^([a-zA-Z_$][a-zA-Z0-9_$]*)(\.[a-zA-Z_$][a-zA-Z0-9_$]*)*$')
        .firstMatch(cleaned);
    if (m == null) return 'arg${counter + 1}';
    final parts = cleaned.split('.');
    final head = parts.first;
    final rest = parts.skip(1).map(_capitalize).join();
    return '$head$rest';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _escapeIcuBraces(String s) =>
      s.replaceAll('{', "'{'").replaceAll('}', "'}'");
}
