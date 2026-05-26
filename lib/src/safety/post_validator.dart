import 'dart:io';

/// Runs `dart format`, `flutter gen-l10n` and `dart analyze` after a rewrite
/// to make sure we didn't break the project. The methods return either `null`
/// on success or a non-empty error message on failure.
class PostValidator {
  static Future<void> format(String projectRoot, List<String> files) async {
    if (files.isEmpty) return;
    await Process.run(
      'dart',
      ['format', ...files],
      workingDirectory: projectRoot,
    );
  }

  /// Returns null on success, or a non-empty error message on failure.
  static Future<String?> analyze(String projectRoot) async {
    final result = await Process.run(
      'dart',
      ['analyze', '--no-fatal-warnings'],
      workingDirectory: projectRoot,
    );
    if (result.exitCode != 0) {
      return (result.stdout as String) + (result.stderr as String);
    }
    return null;
  }

  /// Runs `flutter gen-l10n` for the flutter_localizations stack so that the
  /// `AppLocalizations` class is regenerated with the newly merged keys
  /// before `analyze` runs.
  ///
  /// Returns null on success or when Flutter isn't on PATH (treated as
  /// best-effort — the user can run it themselves). Returns a non-empty
  /// error string only when Flutter ran and reported a non-zero exit code.
  static Future<String?> genL10n(String projectRoot) async {
    try {
      final result = await Process.run(
        'flutter',
        ['gen-l10n'],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        return (result.stdout as String) + (result.stderr as String);
      }
      return null;
    } catch (_) {
      // Flutter not on PATH — best-effort, don't fail the run.
      return null;
    }
  }
}
