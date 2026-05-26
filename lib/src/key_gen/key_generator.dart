import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../config/config.dart';

/// Generates deterministic, collision-safe identifier keys from string values.
class KeyGenerator {
  KeyGenerator(this.config);

  final Config config;

  static const _dartReservedWords = <String>{
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
    'factory', 'false', 'final', 'finally', 'for', 'function', 'get', 'hide',
    'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
    'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
    'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
    'throw', 'true', 'try', 'typedef', 'var', 'void', 'when', 'while', 'with',
    'yield',
  };

  static const _wordNumbers = <String, String>{
    '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four',
    '5': 'five', '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine',
  };

  /// Generate a base key (without collision suffix). Pass to [disambiguate]
  /// with a set of already-taken keys to produce the final key.
  String baseKey(String value) {
    // Strip ICU placeholders so they don't pollute the key.
    final stripped = value.replaceAll(RegExp(r'\{[^}]+\}'), ' ');
    final words = _splitWords(stripped);
    if (words.isEmpty) {
      // Fallback: hash the original value so keys remain deterministic.
      return '${config.keyPrefix}str${_hashSuffix(value)}';
    }

    final styled = config.keyStyle == KeyStyle.snakeCase
        ? _snakeCase(words)
        : _camelCase(words);

    var key = '${config.keyPrefix}$styled';

    // Trim to max length, preserving prefix.
    if (key.length > config.keyMaxLength) {
      key = key.substring(0, config.keyMaxLength);
    }

    // Fix leading digit.
    if (RegExp(r'^[0-9]').hasMatch(key)) {
      key = 'n$key';
    }

    // Avoid reserved words.
    if (_dartReservedWords.contains(key)) {
      key = '${key}Label';
    }

    if (key.isEmpty) {
      key = '${config.keyPrefix}str${_hashSuffix(value)}';
    }

    return key;
  }

  /// If [base] is already in [taken] with a *different* value, append a
  /// deterministic 4-hex suffix derived from [value].
  String disambiguate(String base, String value, Set<String> taken) {
    if (!taken.contains(base)) return base;
    final suffix = _hashSuffix(value);
    final withSuffix = '${base}_$suffix';
    if (!taken.contains(withSuffix)) return withSuffix;
    // Pathological collision — append a counter.
    var i = 2;
    while (taken.contains('${withSuffix}_$i')) {
      i++;
    }
    return '${withSuffix}_$i';
  }

  // ---------------------------------------------------------------------------

  List<String> _splitWords(String s) {
    // Replace non-letter, non-digit chars with spaces, then split.
    final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim();
    if (cleaned.isEmpty) return const [];
    final parts = cleaned.split(RegExp(r'\s+'));
    // Replace digit-only words with their English name to keep keys readable.
    final mapped = <String>[];
    for (final p in parts) {
      if (RegExp(r'^[0-9]+$').hasMatch(p) && _wordNumbers[p] != null) {
        mapped.add(_wordNumbers[p]!);
      } else {
        mapped.add(p);
      }
    }
    return mapped.take(8).toList();
  }

  String _camelCase(List<String> words) {
    if (words.isEmpty) return '';
    final head = words.first.toLowerCase();
    final rest = words.skip(1).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join();
    return '$head$rest';
  }

  String _snakeCase(List<String> words) =>
      words.map((w) => w.toLowerCase()).join('_');

  String _hashSuffix(String value) {
    final digest = sha1.convert(utf8.encode(value));
    return digest.toString().substring(0, 4);
  }
}
