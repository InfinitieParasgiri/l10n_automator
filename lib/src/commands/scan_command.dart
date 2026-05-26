import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/config.dart';
import '../pipeline.dart';
import '../report/reporter.dart';

class ScanCommand extends Command<int> {
  @override
  String get name => 'scan';
  @override
  String get description =>
      'Dry-run: report localizable strings found in lib/ (or --path targets) '
      'without modifying anything.';

  ScanCommand() {
    argParser
      ..addOption('config',
          help: 'Path to .localizator.yaml.', valueHelp: 'path')
      ..addMultiOption('path',
          abbr: 'p',
          help:
              'Limit scanning to these files / directories / globs (relative '
              'to project root). Repeat to add more. When omitted, the whole '
              'lib/ directory is scanned.',
          valueHelp: 'file-or-glob')
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
    final byFile = argResults?['by-file'] as bool? ?? false;
    final includeSkip = argResults?['include-skip'] as bool? ?? false;
    final topRaw = argResults?['top'] as String? ?? '50';
    final top = int.tryParse(topRaw) ?? 50;

    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      dryRun: true,
      auto: true,
      includePaths: paths,
    );
    final summary = pipeline.scanOnly();
    Reporter.printSummary(
      summary,
      stdout,
      byFile: byFile,
      topN: top,
      projectRoot: projectRoot,
      includeSkip: includeSkip,
    );
    return 0;
  }
}
