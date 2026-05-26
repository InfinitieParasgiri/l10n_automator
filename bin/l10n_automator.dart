import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:l10n_automator/src/commands/doctor_command.dart';
import 'package:l10n_automator/src/commands/extract_command.dart';
import 'package:l10n_automator/src/commands/go_command.dart';
import 'package:l10n_automator/src/commands/init_command.dart';
import 'package:l10n_automator/src/commands/rollback_command.dart';
import 'package:l10n_automator/src/commands/scan_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'l10n_automator',
    'Extract hardcoded UI strings from a Flutter project and wire them up to '
        'flutter_localizations or easy_localization.',
  )
    ..addCommand(InitCommand())
    ..addCommand(ScanCommand())
    ..addCommand(ExtractCommand())
    ..addCommand(GoCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(RollbackCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
