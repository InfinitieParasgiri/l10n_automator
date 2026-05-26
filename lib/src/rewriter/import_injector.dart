/// Inserts a single-line import into Dart source if it isn't already present.
///
/// Strategy:
///   - If [importLine] (or any import of the same package URI) already exists,
///     return the source unchanged.
///   - Otherwise, insert it after the last existing `import` directive, or
///     at the very top if there are no imports (after any leading comments).
class ImportInjector {
  static String inject(String source, String importLine) {
    if (_alreadyImported(source, importLine)) return source;

    final lines = source.split('\n');
    var lastImportIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('import ') && trimmed.endsWith(';')) {
        lastImportIdx = i;
      } else if (trimmed.isNotEmpty &&
          !trimmed.startsWith('//') &&
          !trimmed.startsWith('library ') &&
          !trimmed.startsWith('@') &&
          lastImportIdx == -1) {
        // First non-import, non-comment, non-annotation line — stop scanning.
        break;
      }
    }

    if (lastImportIdx == -1) {
      // No imports yet — insert after leading comments/library directive.
      var insertAt = 0;
      while (insertAt < lines.length) {
        final t = lines[insertAt].trim();
        if (t.isEmpty || t.startsWith('//') || t.startsWith('library ')) {
          insertAt++;
        } else {
          break;
        }
      }
      lines.insert(insertAt, importLine);
      return lines.join('\n');
    }

    lines.insert(lastImportIdx + 1, importLine);
    return lines.join('\n');
  }

  static bool _alreadyImported(String source, String importLine) {
    // Extract the package URI from the line so we compare URIs, not whole lines.
    final m = RegExp(r"""import ['"]([^'"]+)['"]""").firstMatch(importLine);
    if (m == null) return false;
    final uri = m.group(1);
    final pattern = RegExp("""import ['"]${RegExp.escape(uri!)}['"]""");
    return pattern.hasMatch(source);
  }
}
