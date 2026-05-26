import 'dart:io';

import 'package:path/path.dart' as p;

import '../extractor/candidate.dart';
import '../pipeline.dart';

class Reporter {
  static void printSummary(
    PipelineSummary s,
    IOSink out, {
    bool byFile = false,
    int topN = 50,
    String? projectRoot,
    bool includeSkip = false,
  }) {
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

    if (byFile && s.byFile.isNotEmpty) {
      _printByFile(s, out,
          topN: topN, projectRoot: projectRoot, includeSkip: includeSkip);
    }
  }

  static void _printByFile(
    PipelineSummary s,
    IOSink out, {
    required int topN,
    required String? projectRoot,
    required bool includeSkip,
  }) {
    // Sort by candidates worth a human's attention (localize + review),
    // descending. Files with only skipped literals would otherwise drown
    // out the interesting ones in a large project.
    final entries = s.byFile.entries.toList()
      ..sort((a, b) {
        final aw = a.value.localize + a.value.review;
        final bw = b.value.localize + b.value.review;
        if (bw != aw) return bw.compareTo(aw);
        return b.value.total.compareTo(a.value.total);
      });

    // If --include-skip is off and a file has no localize/review hits,
    // hide it — there's nothing to act on.
    final visible = entries
        .where(
            (e) => includeSkip || e.value.localize > 0 || e.value.review > 0)
        .toList();

    final shown = topN > 0 && visible.length > topN
        ? visible.sublist(0, topN)
        : visible;

    if (shown.isEmpty) {
      out.writeln('\n(no files with localize/review candidates)');
      return;
    }

    // Compute path column width — cap at 60 so very long paths don't blow
    // up the layout.
    final paths = shown
        .map((e) => _relPath(e.key, projectRoot))
        .toList(growable: false);
    final pathWidth =
        paths.map((s) => s.length).reduce((a, b) => a > b ? a : b).clamp(20, 60);

    out.writeln('\nBy file (top ${shown.length} of ${visible.length}):');
    final header = '  ${'file'.padRight(pathWidth)}  '
        'localize  review  ${includeSkip ? 'skip  ' : ''}total';
    out.writeln(header);
    out.writeln('  ${'-' * pathWidth}  --------  ------  '
        '${includeSkip ? '------  ' : ''}-----');

    for (var i = 0; i < shown.length; i++) {
      final fb = shown[i].value;
      final pathCell = _truncatePath(paths[i], pathWidth).padRight(pathWidth);
      final localizeCell = fb.localize.toString().padLeft(8);
      final reviewCell = fb.review.toString().padLeft(6);
      final skipCell = includeSkip ? '${fb.skip.toString().padLeft(6)}  ' : '';
      final totalCell = fb.total.toString().padLeft(5);
      out.writeln('  $pathCell  $localizeCell  $reviewCell  $skipCell$totalCell');
    }

    if (visible.length > shown.length) {
      out.writeln('  … ${visible.length - shown.length} more file(s) hidden '
          '(use --top 0 to show all)');
    }
  }

  static String _relPath(String absPath, String? projectRoot) {
    if (projectRoot == null) return absPath;
    try {
      return p.relative(absPath, from: projectRoot);
    } catch (_) {
      return absPath;
    }
  }

  /// Truncates from the left, keeping the file name and immediate parent
  /// visible — most useful when scanning deep `lib/features/.../view/`
  /// trees.
  static String _truncatePath(String path, int width) {
    if (path.length <= width) return path;
    return '…${path.substring(path.length - (width - 1))}';
  }
}
