import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/config.dart';
import '../pipeline.dart';
import '../report/reporter.dart';

/// `go` — opinionated one-shot extraction.
///
/// Equivalent to `extract --auto`, with a scoped git-clean check so
/// unrelated uncommitted files (pubspec.lock, IDE configs, other folders)
/// don't block the run. Intended for users who want to type one command
/// per folder without remembering flags.
class GoCommand extends Command<int> {
  @override
  String get name => 'go';

  @override
  String get description =>
      'One-shot extraction. Same as `extract --auto`, but only refuses '
      'to run if there are uncommitted changes inside the scan target.';

  GoCommand() {
    argParser
      ..addOption('config',
          help: 'Path to .localizator.yaml.', valueHelp: 'path')
      ..addMultiOption('path',
          abbr: 'p',
          help: 'Limit to these files / directories / globs (relative '
              'to project root). Repeat for multiple targets.',
          valueHelp: 'file-or-glob')
      ..addFlag('by-file',
          abbr: 'f',
          defaultsTo: false,
          help: 'Show the per-file breakdown alongside the summary.')
      ..addFlag('dry-run',
          defaultsTo: false,
          help: 'Show what would change without writing anything.')
      ..addFlag('force',
          defaultsTo: false,
          help: 'Skip the dirty-tree check entirely.');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final config = Config.load(projectRoot,
        overridePath: argResults?['config'] as String?);
    final paths = (argResults?['path'] as List<String>?) ?? const [];
    final byFile = argResults?['by-file'] as bool? ?? false;
    final dryRun = argResults?['dry-run'] as bool? ?? false;
    final force = argResults?['force'] as bool? ?? false;

    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      auto: true,
      dryRun: dryRun,
      force: force,
      includePaths: paths,
    );

    try {
      final summary = await pipeline.run();
      Reporter.printSummary(
        summary,
        stdout,
        byFile: byFile,
        topN: 50,
        projectRoot: projectRoot,
      );
      if (summary.analyzeError != null) {
        stderr.writeln(
            '\n❌ analyze/gen-l10n reported errors after rewrite — rolled back.');
        stderr.writeln(summary.analyzeError);
        return 2;
      }
      if (summary.appliedChanges) {
        stdout.writeln('\n✅ Done. Inspect with `git diff`, smoke-test with '
            '`flutter run`, then commit.');
      }
      return 0;
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 1;
    }
  }
}
