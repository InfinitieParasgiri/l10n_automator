import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Walks the `lib/` (or a configured root) of a Flutter project, returning
/// the absolute paths of .dart files that should be considered for
/// localization. Honors a list of exclude globs.
class FileWalker {
  FileWalker({
    required this.projectRoot,
    required this.scanRoot,
    required List<String> excludes,
  }) : _excludeGlobs =
            excludes.map((pattern) => Glob(pattern, recursive: true)).toList();

  /// Absolute path to the target Flutter project root.
  final String projectRoot;

  /// Absolute path to the directory to scan (typically `<projectRoot>/lib`).
  final String scanRoot;

  final List<Glob> _excludeGlobs;

  /// Yields absolute paths to .dart files under [scanRoot] that pass the
  /// exclude filter and don't contain the file-level opt-out header.
  Iterable<String> walk() sync* {
    final root = Directory(scanRoot);
    if (!root.existsSync()) return;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (_isExcluded(entity.path)) continue;
      if (_hasIgnoreForFileDirective(entity)) continue;
      yield entity.path;
    }
  }

  bool _isExcluded(String absPath) {
    final rel = p.relative(absPath, from: projectRoot);
    final relPosix = rel.split(p.separator).join('/');
    for (final g in _excludeGlobs) {
      if (g.matches(relPosix)) return true;
    }
    return false;
  }

  /// Files can opt out entirely by placing
  /// `// l10n_automator:ignore_for_file` near the top.
  /// The legacy spelling `// localization_automator:ignore_for_file`
  /// is also accepted.
  bool _hasIgnoreForFileDirective(File f) {
    try {
      final lines = f.readAsLinesSync();
      // Check first ~10 lines only — directive belongs near top.
      for (var i = 0; i < lines.length && i < 10; i++) {
        final line = lines[i];
        if (line.contains('l10n_automator:ignore_for_file') ||
            line.contains('localization_automator:ignore_for_file')) {
          return true;
        }
      }
    } catch (_) {
      // If we can't read, let the scanner surface the error.
    }
    return false;
  }
}
