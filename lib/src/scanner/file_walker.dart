import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Walks the `lib/` (or a configured root) of a Flutter project, returning
/// the absolute paths of .dart files that should be considered for
/// localization. Honors a list of exclude globs.
///
/// If [includePaths] is non-empty, the walker scans **only** those files /
/// directories / globs instead of [scanRoot]. Each entry can be:
///  - an absolute or project-relative path to a single `.dart` file, or
///  - an absolute or project-relative path to a directory (scanned
///    recursively), or
///  - a POSIX-style glob (e.g. `lib/screens/**`).
class FileWalker {
  FileWalker({
    required this.projectRoot,
    required this.scanRoot,
    required List<String> excludes,
    List<String> includePaths = const [],
  })  : _excludeGlobs =
            excludes.map((pattern) => Glob(pattern, recursive: true)).toList(),
        _includePaths = includePaths;

  /// Absolute path to the target Flutter project root.
  final String projectRoot;

  /// Absolute path to the directory to scan (typically `<projectRoot>/lib`).
  /// Ignored when [_includePaths] is non-empty.
  final String scanRoot;

  final List<Glob> _excludeGlobs;
  final List<String> _includePaths;

  /// Yields absolute paths to .dart files under [scanRoot] (or the explicit
  /// [includePaths]) that pass the exclude filter and don't contain the
  /// file-level opt-out header.
  Iterable<String> walk() sync* {
    final seen = <String>{};

    Iterable<String> sources() sync* {
      if (_includePaths.isEmpty) {
        final root = Directory(scanRoot);
        if (!root.existsSync()) return;
        for (final entity
            in root.listSync(recursive: true, followLinks: false)) {
          if (entity is File) yield entity.path;
        }
        return;
      }
      for (final raw in _includePaths) {
        yield* _resolveInclude(raw);
      }
    }

    for (final path in sources()) {
      if (!path.endsWith('.dart')) continue;
      if (!seen.add(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      if (_isExcluded(path)) continue;
      if (_hasIgnoreForFileDirective(file)) continue;
      yield path;
    }
  }

  Iterable<String> _resolveInclude(String raw) sync* {
    final abs = p.isAbsolute(raw) ? raw : p.join(projectRoot, raw);
    final asFile = File(abs);
    final asDir = Directory(abs);

    if (asFile.existsSync()) {
      yield asFile.absolute.path;
      return;
    }
    if (asDir.existsSync()) {
      for (final entity in asDir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) yield entity.path;
      }
      return;
    }

    // Treat as glob, relative to projectRoot.
    final glob = Glob(raw, recursive: true);
    final root = Directory(projectRoot);
    if (!root.existsSync()) return;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: projectRoot).split(p.separator).join('/');
      if (glob.matches(rel)) yield entity.path;
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
