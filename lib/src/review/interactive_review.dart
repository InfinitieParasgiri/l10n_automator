import 'dart:io';

import 'package:path/path.dart' as p;

import '../extractor/candidate.dart';

/// The decision the user made for a single candidate during interactive review.
enum ReviewChoice { accept, skip, quit }

class ReviewedCandidate {
  ReviewedCandidate(this.candidate, this.choice, {this.customKey});
  final Candidate candidate;
  final ReviewChoice choice;
  final String? customKey;
}

/// Simple stdin/stdout interactive review. One prompt per candidate; the user
/// can accept, skip, override the key, or quit and save what's been decided
/// so far.
class InteractiveReview {
  InteractiveReview({
    required this.projectRoot,
    Stdin? input,
    IOSink? output,
  })  : _in = input ?? stdin,
        _out = output ?? stdout;

  final String projectRoot;
  final Stdin _in;
  final IOSink _out;

  /// Prompt the user for each candidate. Returns the list of decisions
  /// (length may be shorter than [candidates] if the user quits).
  List<ReviewedCandidate> review(List<Candidate> candidates) {
    final decisions = <ReviewedCandidate>[];
    _out.writeln('\nInteractive review — ${candidates.length} candidate(s).');
    _out.writeln(
        '  [y] localize    [n] skip    [k] use custom key    [q] quit\n');
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final rel = p.relative(c.filePath, from: projectRoot);
      final line = _lineOf(c);
      _out.writeln('${i + 1}/${candidates.length}  $rel:$line');
      _out.writeln('  context : ${c.parentContextDescription}');
      _out.writeln('  reason  : ${c.reason}');
      _out.writeln('  value   : ${_truncate(c.literalValue, 80)}');
      _out.write('  > ');
      final raw = _in.readLineSync();
      final input = (raw ?? 'n').trim().toLowerCase();
      if (input == 'q' || input == 'quit') {
        _out.writeln('Quitting review; ${decisions.length} decision(s) saved.');
        break;
      }
      if (input == 'y' || input == 'yes' || input.isEmpty) {
        decisions.add(ReviewedCandidate(c, ReviewChoice.accept));
      } else if (input == 'k' || input == 'key') {
        _out.write('  custom key: ');
        final key = (_in.readLineSync() ?? '').trim();
        decisions.add(ReviewedCandidate(c, ReviewChoice.accept,
            customKey: key.isEmpty ? null : key));
      } else {
        decisions.add(ReviewedCandidate(c, ReviewChoice.skip));
      }
    }
    return decisions;
  }

  int _lineOf(Candidate c) {
    var line = 1;
    for (var i = 0; i < c.node.offset && i < c.source.length; i++) {
      if (c.source.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n - 1)}…';
}
