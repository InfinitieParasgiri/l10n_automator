import 'dart:io';

import 'package:path/path.dart' as p;

/// Snapshots files before modification so that --rollback can restore them.
class BackupManager {
  BackupManager(this.projectRoot)
      : _backupRoot = p.join(projectRoot, '.localizator', 'backup');

  final String projectRoot;
  final String _backupRoot;

  /// Snapshot a set of files. Returns the absolute path to the snapshot dir.
  /// Files that don't exist on disk are silently skipped — useful when the
  /// caller passes a "might be touched" set that includes files about to be
  /// created.
  String snapshot(Iterable<String> filesAbsolutePaths) {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final dest = p.join(_backupRoot, stamp);
    Directory(dest).createSync(recursive: true);
    final seen = <String>{};
    for (final src in filesAbsolutePaths) {
      if (!seen.add(src)) continue;
      final f = File(src);
      if (!f.existsSync()) continue;
      final rel = p.relative(src, from: projectRoot);
      final target = File(p.join(dest, rel));
      target.parent.createSync(recursive: true);
      f.copySync(target.path);
    }
    return dest;
  }

  /// Returns the most recent backup directory, or null if none exists.
  String? latestBackup() {
    final dir = Directory(_backupRoot);
    if (!dir.existsSync()) return null;
    final subs = dir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path)
        .toList()
      ..sort();
    return subs.isEmpty ? null : subs.last;
  }

  /// Restore every file from [backupDir] back into the project tree.
  int restore(String backupDir) {
    final root = Directory(backupDir);
    var restored = 0;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: backupDir);
      final dest = File(p.join(projectRoot, rel));
      dest.parent.createSync(recursive: true);
      entity.copySync(dest.path);
      restored++;
    }
    return restored;
  }
}
