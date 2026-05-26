import 'dart:io';

/// Result of inspecting a project's git state.
class GitStatus {
  GitStatus({required this.isRepo, required this.isClean, this.dirtyFiles = const []});
  final bool isRepo;
  final bool isClean;
  final List<String> dirtyFiles;
}

class GitCheck {
  /// Returns the git status of [projectRoot]. If git isn't installed or the
  /// project isn't a git repo, returns isRepo=false (and isClean=true so the
  /// pipeline doesn't refuse to run on non-git projects).
  static GitStatus inspect(String projectRoot) {
    try {
      final result = Process.runSync(
        'git',
        ['status', '--porcelain'],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        return GitStatus(isRepo: false, isClean: true);
      }
      final out = (result.stdout as String).trim();
      if (out.isEmpty) {
        return GitStatus(isRepo: true, isClean: true);
      }
      final files = out
          .split('\n')
          .map((l) => l.trim().split(RegExp(r'\s+')).last)
          .toList();
      return GitStatus(isRepo: true, isClean: false, dirtyFiles: files);
    } catch (_) {
      return GitStatus(isRepo: false, isClean: true);
    }
  }
}
