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
          valueHelp: 'file-or-glob');
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
      dryRun: true,
      auto: true,
      includePaths: paths,
    );
    final summary = pipeline.scanOnly();
    Reporter.printSummary(summary, stdout);
    return 0;
  }
}
