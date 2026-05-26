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
      ..addMultiOption('path',
          abbr: 'p',
          help:
              'Limit extraction to these files / directories / globs '
              '(relative to project root). Repeat to add more. When omitted, '
              'the whole lib/ directory is scanned.',
          valueHelp: 'file-or-glob')
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
          help: 'Run even on a dirty git tree.')
      ..addFlag('by-file',
          abbr: 'f',
          defaultsTo: false,
          help: 'Print a per-file breakdown of localize / review counts '
              'after the summary.')
      ..addFlag('include-skip',
          defaultsTo: false,
          help: 'In --by-file output, also include files whose only hits '
              'are skipped literals.')
      ..addOption('top',
          defaultsTo: '50',
          help: 'In --by-file output, show at most N files. Use 0 to '
              'show all.',
          valueHelp: 'N');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final config = Config.load(projectRoot,
        overridePath: argResults?['config'] as String?);
    final paths = (argResults?['path'] as List<String>?) ?? const [];
    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      auto: argResults?['auto'] as bool,
      dryRun: argResults?['dry-run'] as bool,
      force: argResults?['force'] as bool,
      takeBackup: argResults?['backup'] as bool,
      includePaths: paths,
    );
    try {
      final summary = await pipeline.run();
      final byFile = argResults?['by-file'] as bool? ?? false;
      final includeSkip = argResults?['include-skip'] as bool? ?? false;
      final top = int.tryParse(argResults?['top'] as String? ?? '50') ?? 50;
      Reporter.printSummary(
        summary,
        stdout,
        byFile: byFile,
        topN: top,
        projectRoot: projectRoot,
        includeSkip: includeSkip,
      );
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
