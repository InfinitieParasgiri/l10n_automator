import 'dart:io';

import '../extractor/candidate.dart';
import '../pipeline.dart';

class Reporter {
  static void printSummary(PipelineSummary s, IOSink out) {
    out.writeln('\nLocalization Automator — summary');
    out.writeln('  files scanned  : ${s.filesScanned}');
    out.writeln('  literals found : ${s.totalCandidates}');
    out.writeln('    localize     : ${s.byDecision[Decision.localize] ?? 0}');
    out.writeln('    review       : ${s.byDecision[Decision.review] ?? 0}');
    out.writeln('    skip         : ${s.byDecision[Decision.skip] ?? 0}');
    if (s.appliedChanges) {
      out.writeln('  new keys       : ${s.newKeys}');
      out.writeln('  edits applied  : ${s.editsApplied}');
      out.writeln('  files written  : ${s.filesWritten.length}');
      if (s.backupDir != null) {
        out.writeln('  backup         : ${s.backupDir}');
      }
    } else if (s.editsApplied == 0 && s.filesWritten.isEmpty) {
      out.writeln('  (no changes written)');
    }
  }
}
