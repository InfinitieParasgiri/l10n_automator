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
      'Dry-run: report localizable strings found in lib/ without modifying anything.';

  ScanCommand() {
    argParser.addOption('config',
        help: 'Path to .localizator.yaml.', valueHelp: 'path');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final config = Config.load(projectRoot,
        overridePath: argResults?['config'] as String?);
    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      dryRun: true,
      auto: true,
    );
    final summary = pipeline.scanOnly();
    Reporter.printSummary(summary, stdout);
    return 0;
  }
}
