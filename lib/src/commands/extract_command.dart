import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/config.dart';
import '../pipeline.dart';
import '../report/reporter.dart';

class ExtractCommand extends Command<int> {
  @override
  String get name => 'extract';
  @override
  String get description =>
      'Extract hardcoded strings into ARB/JSON and rewrite source. '
      'Interactive by default; pass --auto for unattended runs.';

  ExtractCommand() {
    argParser
      ..addOption('config',
          help: 'Path to .localizator.yaml.', valueHelp: 'path')
      ..addFlag('auto',
          defaultsTo: false,
          help: 'Skip interactive prompts; apply only safe-by-rule rewrites.')
      ..addFlag('dry-run',
          defaultsTo: false,
          help: 'Show what would change without writing anything.')
      ..addFlag('backup',
          defaultsTo: true,
          help:
              'Snapshot touched files to .localizator/backup/ before changes.')
      ..addFlag('force',
          defaultsTo: false,
          help: 'Run even on a dirty git tree.');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final config = Config.load(projectRoot,
        overridePath: argResults?['config'] as String?);
    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      auto: argResults?['auto'] as bool,
      dryRun: argResults?['dry-run'] as bool,
      force: argResults?['force'] as bool,
      takeBackup: argResults?['backup'] as bool,
    );
    try {
      final summary = await pipeline.run();
      Reporter.printSummary(summary, stdout);
      if (summary.analyzeError != null) {
        stderr.writeln(
            '\n❌ dart analyze reported errors after rewrite — rolled back.');
        stderr.writeln(summary.analyzeError);
        return 2;
      }
      return 0;
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 1;
    }
  }
}
