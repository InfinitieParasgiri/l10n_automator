import 'dart:io';

import 'package:path/path.dart' as p;

import 'adapters/l10n_adapter.dart';
import 'arb/arb_merger.dart';
import 'config/config.dart';
import 'config/stack_detector.dart';
import 'extractor/candidate.dart';
import 'extractor/string_extractor.dart';
import 'review/interactive_review.dart';
import 'rewriter/code_rewriter.dart';
import 'safety/backup_manager.dart';
import 'safety/git_check.dart';
import 'safety/post_validator.dart';
import 'scanner/dart_ast_scanner.dart';
import 'scanner/file_walker.dart';

/// Summary of a pipeline run. Returned to commands for reporting.
class PipelineSummary {
  PipelineSummary({
    required this.filesScanned,
    required this.totalCandidates,
    required this.byDecision,
    required this.newKeys,
    required this.editsApplied,
    required this.filesWritten,
    this.backupDir,
    this.analyzeError,
    this.appliedChanges = false,
  });

  final int filesScanned;
  final int totalCandidates;
  final Map<Decision, int> byDecision;
  final int newKeys;
  final int editsApplied;
  final List<String> filesWritten;
  final String? backupDir;
  final String? analyzeError;
  final bool appliedChanges;
}

/// Orchestrates the full scan → classify → merge → rewrite pipeline.
class Pipeline {
  Pipeline({
    required this.projectRoot,
    required this.config,
    this.auto = false,
    this.dryRun = false,
    this.force = false,
    this.takeBackup = true,
  });

  final String projectRoot;
  final Config config;
  final bool auto;
  final bool dryRun;
  final bool force;
  final bool takeBackup;

  Future<PipelineSummary> run() async {
    // 1. Git-clean check.
    if (!dryRun && !force) {
      final git = GitCheck.inspect(projectRoot);
      if (git.isRepo && !git.isClean) {
        throw StateError(
          'Refusing to run on a dirty git tree. Commit/stash changes first, '
          'or pass --force.\nDirty files:\n  ${git.dirtyFiles.take(10).join("\n  ")}',
        );
      }
    }

    // 2. Resolve adapter for the detected/configured stack.
    final stack = StackDetector.resolve(config, projectRoot);
    final adapter = L10nAdapter.forStack(stack, config);

    // 3. Walk + parse.
    final scanRoot = p.join(projectRoot, 'lib');
    final walker = FileWalker(
      projectRoot: projectRoot,
      scanRoot: scanRoot,
      excludes: config.ignoreFileGlobs,
    );
    final scanner = DartAstScanner();
    final extractor = StringExtractor(config);

    final allCandidates = <Candidate>[];
    var filesScanned = 0;
    for (final path in walker.walk()) {
      filesScanned++;
      final parsed = scanner.parseFile(path);
      if (parsed == null) continue;
      allCandidates
          .addAll(extractor.extract(parsed.path, parsed.source, parsed.unit));
    }

    final byDecision = <Decision, int>{
      for (final d in Decision.values) d: 0,
    };
    for (final c in allCandidates) {
      byDecision[c.decision] = (byDecision[c.decision] ?? 0) + 1;
    }

    // 4. Pick the set we'll actually rewrite.
    var toRewrite = allCandidates
        .where((c) => c.decision == Decision.localize)
        .toList();
    final reviewQueue = allCandidates
        .where((c) => c.decision == Decision.review)
        .toList();

    final overrides = <Candidate, String?>{};

    if (!auto && !dryRun && reviewQueue.isNotEmpty) {
      final review = InteractiveReview(projectRoot: projectRoot);
      final decisions = review.review(reviewQueue);
      for (final d in decisions) {
        if (d.choice == ReviewChoice.accept) {
          toRewrite.add(d.candidate);
          overrides[d.candidate] = d.customKey;
        }
      }
    }

    // 5. Drop candidates whose adapter requires BuildContext but none is in scope.
    if (adapter.needsBuildContext) {
      toRewrite = toRewrite
          .where((c) =>
              c.hasBuildContextInScope ||
              config.onMissingContext == OnMissingContext.error)
          .toList();
    }

    // 6. Dry run? Stop here and report.
    if (dryRun) {
      return PipelineSummary(
        filesScanned: filesScanned,
        totalCandidates: allCandidates.length,
        byDecision: byDecision,
        newKeys: toRewrite.length,
        editsApplied: 0,
        filesWritten: const [],
        appliedChanges: false,
      );
    }

    if (toRewrite.isEmpty) {
      return PipelineSummary(
        filesScanned: filesScanned,
        totalCandidates: allCandidates.length,
        byDecision: byDecision,
        newKeys: 0,
        editsApplied: 0,
        filesWritten: const [],
        appliedChanges: false,
      );
    }

    // 7. Backup.
    String? backupDir;
    if (takeBackup) {
      final touched = toRewrite.map((c) => c.filePath).toSet();
      backupDir = BackupManager(projectRoot).snapshot(touched);
    }

    // 8. Merge into ARB / JSON.
    final entries = <ArbEntry>[];
    for (final c in toRewrite) {
      entries.add(ArbEntry(
        value: c.literalValue,
        placeholders: c.interpolationPlaceholders,
        preferredKey: overrides[c] ?? c.overrideKey,
      ));
    }
    final merger = ArbMerger(config);
    final mergeResult = stack == L10nStack.easyLocalization
        ? merger.mergeIntoEasyLocalization(
            projectRoot: projectRoot, entries: entries)
        : merger.mergeIntoFlutterL10n(
            projectRoot: projectRoot, entries: entries);

    // 9. Rewrite source.
    final rewriter = CodeRewriter(adapter);
    final edits = rewriter.buildEdits(
      candidates: toRewrite,
      keyByValue: mergeResult.keyByValue,
    );
    final rewriteResult = rewriter.apply(edits);

    // 10. Format + analyze + (optionally) gen-l10n.
    String? analyzeError;
    if (config.runFormatter) {
      await PostValidator.format(projectRoot, rewriteResult.filesWritten);
    }
    if (config.runAnalyzer) {
      analyzeError = await PostValidator.analyze(projectRoot);
      if (analyzeError != null && takeBackup && backupDir != null) {
        // Restore from backup on analyze failure.
        BackupManager(projectRoot).restore(backupDir);
      }
    }
    if (analyzeError == null &&
        config.runGenL10n &&
        stack == L10nStack.flutterLocalizations) {
      await PostValidator.genL10n(projectRoot);
    }

    return PipelineSummary(
      filesScanned: filesScanned,
      totalCandidates: allCandidates.length,
      byDecision: byDecision,
      newKeys: mergeResult.newKeyCount,
      editsApplied: rewriteResult.editCount,
      filesWritten: rewriteResult.filesWritten,
      backupDir: backupDir,
      analyzeError: analyzeError,
      appliedChanges: analyzeError == null,
    );
  }

  /// Dry-run scan only — no writes. Used by `scan` and `doctor` commands.
  PipelineSummary scanOnly() {
    final stack = StackDetector.resolve(config, projectRoot);
    final scanRoot = p.join(projectRoot, 'lib');
    if (!Directory(scanRoot).existsSync()) {
      return PipelineSummary(
        filesScanned: 0,
        totalCandidates: 0,
        byDecision: {for (final d in Decision.values) d: 0},
        newKeys: 0,
        editsApplied: 0,
        filesWritten: const [],
      );
    }
    final walker = FileWalker(
      projectRoot: projectRoot,
      scanRoot: scanRoot,
      excludes: config.ignoreFileGlobs,
    );
    final scanner = DartAstScanner();
    final extractor = StringExtractor(config);
    final all = <Candidate>[];
    var files = 0;
    for (final path in walker.walk()) {
      files++;
      final parsed = scanner.parseFile(path);
      if (parsed == null) continue;
      all.addAll(extractor.extract(parsed.path, parsed.source, parsed.unit));
    }
    final byDecision = <Decision, int>{
      for (final d in Decision.values) d: 0,
    };
    for (final c in all) {
      byDecision[c.decision] = (byDecision[c.decision] ?? 0) + 1;
    }
    // Silence unused-variable warning for stack; it's available if a future
    // version of scanOnly wants stack-specific reporting.
    assert(stack == stack);
    return PipelineSummary(
      filesScanned: files,
      totalCandidates: all.length,
      byDecision: byDecision,
      newKeys: byDecision[Decision.localize] ?? 0,
      editsApplied: 0,
      filesWritten: const [],
    );
  }

  /// Scan and return the raw candidates (for doctor's detailed report).
  List<Candidate> collectCandidates() {
    final scanRoot = p.join(projectRoot, 'lib');
    if (!Directory(scanRoot).existsSync()) return const [];
    final walker = FileWalker(
      projectRoot: projectRoot,
      scanRoot: scanRoot,
      excludes: config.ignoreFileGlobs,
    );
    final scanner = DartAstScanner();
    final extractor = StringExtractor(config);
    final all = <Candidate>[];
    for (final path in walker.walk()) {
      final parsed = scanner.parseFile(path);
      if (parsed == null) continue;
      all.addAll(extractor.extract(parsed.path, parsed.source, parsed.unit));
    }
    return all;
  }
}
