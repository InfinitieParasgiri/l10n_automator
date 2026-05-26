import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/stack_detector.dart';
import '../extractor/candidate.dart';
import '../pipeline.dart';
import '../safety/git_check.dart';

class DoctorCommand extends Command<int> {
  @override
  String get name => 'doctor';
  @override
  String get description =>
      'Validate config, detect l10n stack, and report the review queue.';

  DoctorCommand() {
    argParser.addOption('config',
        help: 'Path to .localizator.yaml.', valueHelp: 'path');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final config = Config.load(projectRoot,
        overridePath: argResults?['config'] as String?);
    final stack = StackDetector.resolve(config, projectRoot);
    final git = GitCheck.inspect(projectRoot);

    stdout.writeln('Localization Automator — doctor');
    stdout.writeln('  project root : $projectRoot');
    stdout.writeln('  l10n stack   : ${stack.name}');
    stdout.writeln(
        '  git          : ${git.isRepo ? (git.isClean ? "clean" : "DIRTY (${git.dirtyFiles.length} files)") : "not a repo"}');
    stdout.writeln('  config       : ${File(p.join(projectRoot, '.localizator.yaml')).existsSync() ? '.localizator.yaml found' : 'using defaults'}');

    final libDir = Directory(p.join(projectRoot, 'lib'));
    if (!libDir.existsSync()) {
      stderr.writeln('No lib/ directory found in project root.');
      return 1;
    }

    final pipeline = Pipeline(
      projectRoot: projectRoot,
      config: config,
      auto: true,
      dryRun: true,
    );
    final candidates = pipeline.collectCandidates();

    final review = candidates.where((c) => c.decision == Decision.review).toList();
    final localize = candidates.where((c) => c.decision == Decision.localize).toList();
    final skip = candidates.where((c) => c.decision == Decision.skip).toList();

    stdout.writeln('\nFound ${candidates.length} string literal(s):');
    stdout.writeln('  localize : ${localize.length}');
    stdout.writeln('  review   : ${review.length}');
    stdout.writeln('  skip     : ${skip.length}');

    if (review.isNotEmpty) {
      stdout.writeln('\nReview queue:');
      for (final c in review.take(50)) {
        final rel = p.relative(c.filePath, from: projectRoot);
        stdout.writeln('  $rel  →  "${_truncate(c.literalValue, 60)}"');
        stdout.writeln('    reason: ${c.reason}');
      }
      if (review.length > 50) {
        stdout.writeln('  ... and ${review.length - 50} more');
      }
    }

    return 0;
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n - 1)}…';
}
