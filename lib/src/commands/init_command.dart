import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';

class InitCommand extends Command<int> {
  @override
  String get name => 'init';
  @override
  String get description =>
      'Create a default .localizator.yaml config file in the project root.';

  InitCommand() {
    argParser.addFlag('force',
        abbr: 'f',
        defaultsTo: false,
        help: 'Overwrite an existing .localizator.yaml.');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final path = p.join(projectRoot, '.localizator.yaml');
    final file = File(path);
    if (file.existsSync() && !(argResults?['force'] as bool)) {
      stderr.writeln('.localizator.yaml already exists. Use --force to overwrite.');
      return 1;
    }
    file.writeAsStringSync(Config.defaultYaml());
    stdout.writeln('Created $path');
    return 0;
  }
}
