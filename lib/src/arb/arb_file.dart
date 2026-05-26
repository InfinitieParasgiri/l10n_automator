import 'dart:convert';
import 'dart:io';

/// In-memory model of an ARB file.
///
/// We preserve key order: existing keys keep their position; new keys are
/// appended at the end (alphabetized among themselves).
class ArbFile {
  ArbFile({
    required this.path,
    required this.entries,
    this.locale,
    this.lastModified,
    this.context,
    this.author,
    Map<String, Object?>? extraTopLevel,
  }) : extraTopLevel = extraTopLevel ?? <String, Object?>{};

  final String path;

  /// Ordered map: key -> value. Includes both regular keys and `@key`
  /// metadata entries.
  final Map<String, Object?> entries;

  String? locale;
  String? lastModified;
  String? context;
  String? author;

  /// Any other `@@` top-level entries we don't model explicitly. Preserved
  /// verbatim on write.
  final Map<String, Object?> extraTopLevel;

  // -------------------------------------------------------------------------
  // I/O
  // -------------------------------------------------------------------------

  static ArbFile load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return ArbFile(path: path, entries: <String, Object?>{});
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw FormatException('ARB file is not a JSON object: $path');
    }
    final entries = <String, Object?>{};
    String? locale, lastModified, context, author;
    final extra = <String, Object?>{};
    raw.forEach((k, v) {
      final key = k.toString();
      if (key == '@@locale') {
        locale = v?.toString();
      } else if (key == '@@last_modified') {
        lastModified = v?.toString();
      } else if (key == '@@context') {
        context = v?.toString();
      } else if (key == '@@author') {
        author = v?.toString();
      } else if (key.startsWith('@@')) {
        extra[key] = v;
      } else {
        entries[key] = v;
      }
    });
    return ArbFile(
      path: path,
      entries: entries,
      locale: locale,
      lastModified: lastModified,
      context: context,
      author: author,
      extraTopLevel: extra,
    );
  }

  void save() {
    final out = <String, Object?>{};
    if (locale != null) out['@@locale'] = locale;
    if (context != null) out['@@context'] = context;
    if (author != null) out['@@author'] = author;
    // Refresh last_modified.
    out['@@last_modified'] = DateTime.now().toUtc().toIso8601String();
    out.addAll(extraTopLevel);
    out.addAll(entries);

    final encoder = const JsonEncoder.withIndent('  ');
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${encoder.convert(out)}\n');
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Iterate over the user-visible (non-metadata) keys.
  Iterable<String> get translatableKeys =>
      entries.keys.where((k) => !k.startsWith('@'));

  String? value(String key) => entries[key] as String?;

  Map<String, Object?>? metadata(String key) =>
      entries['@$key'] as Map<String, Object?>?;

  /// Look up an existing key whose value equals [value]. Used for key reuse.
  String? findKeyByValue(String value) {
    for (final k in translatableKeys) {
      if (entries[k] == value) return k;
    }
    return null;
  }

  /// Insert a new key with optional placeholders and description. No-op if
  /// the key already exists.
  void upsert(
    String key, {
    required String value,
    String? description,
    Map<String, String>? placeholders,
  }) {
    entries[key] = value;
    if (description != null || (placeholders != null && placeholders.isNotEmpty)) {
      final meta = <String, Object?>{};
      if (description != null) meta['description'] = description;
      if (placeholders != null && placeholders.isNotEmpty) {
        meta['placeholders'] = {
          for (final entry in placeholders.entries)
            entry.key: {'type': _inferType(entry.value)},
        };
      }
      entries['@$key'] = meta;
    }
  }

  /// Insert *only if missing* — used to preserve non-English translations.
  void upsertIfMissing(String key, {required String value}) {
    if (!entries.containsKey(key)) {
      entries[key] = value;
    }
  }

  static String _inferType(String dartExpr) {
    final lower = dartExpr.toLowerCase();
    if (lower.contains('count') ||
        lower.contains('index') ||
        lower.contains('length') ||
        lower.contains('total') ||
        lower.contains('num')) {
      return 'num';
    }
    return 'String';
  }
}
