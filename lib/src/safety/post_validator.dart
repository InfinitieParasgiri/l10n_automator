import 'dart:io';

/// Runs `dart format` and `dart analyze` after a rewrite to make sure we
/// didn't break the project. Returns an error string if analyze reports new
/// errors; null if everything is clean.
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

  /// Runs `flutter gen-l10n` for the flutter_localizations stack. Best-effort —
  /// won't fail the run if Flutter isn't on PATH.
  static Future<void> genL10n(String projectRoot) async {
    try {
      await Process.run(
        'flutter',
        ['gen-l10n'],
        workingDirectory: projectRoot,
      );
    } catch (_) {
      // Silently ignored — user can run it themselves.
    }
  }
}
