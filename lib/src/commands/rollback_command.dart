import 'dart:io';

import 'package:args/command_runner.dart';

import '../safety/backup_manager.dart';

class RollbackCommand extends Command<int> {
  @override
  String get name => 'rollback';
  @override
  String get description =>
      'Restore source files from the most recent backup snapshot.';

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final manager = BackupManager(projectRoot);
    final latest = manager.latestBackup();
    if (latest == null) {
      stderr.writeln('No backups found in .localizator/backup/.');
      return 1;
    }
    final n = manager.restore(latest);
    stdout.writeln('Restored $n file(s) from $latest');
    return 0;
  }
}
