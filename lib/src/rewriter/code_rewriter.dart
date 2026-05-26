import 'dart:io';

import '../adapters/l10n_adapter.dart';
import '../extractor/candidate.dart';
import 'import_injector.dart';

/// A single, atomic edit: replace [offset..end] in [filePath] with [newText].
class SourceEdit {
  SourceEdit({
    required this.filePath,
    required this.offset,
    required this.end,
    required this.newText,
  });
  final String filePath;
  final int offset;
  final int end;
  final String newText;
}

class RewriteResult {
  RewriteResult({required this.filesWritten, required this.editCount});
  final List<String> filesWritten;
  final int editCount;
}

/// Applies source edits to files in a single atomic pass.
class CodeRewriter {
  CodeRewriter(this.adapter);
  final L10nAdapter adapter;

  /// Build edits for a set of candidates that have been assigned final keys
  /// by the ARB merger.
  ///
  /// [keyByValue] maps the candidate's ARB value -> final key.
  List<SourceEdit> buildEdits({
    required List<Candidate> candidates,
    required Map<String, String> keyByValue,
  }) {
    final edits = <SourceEdit>[];
    for (final c in candidates) {
      final key = keyByValue[c.literalValue];
      if (key == null) continue;
      final replacement =
          adapter.renderCall(key, c.interpolationPlaceholders);
      edits.add(SourceEdit(
        filePath: c.filePath,
        offset: c.node.offset,
        end: c.node.end,
        newText: replacement,
      ));
    }
    return edits;
  }

  /// Apply [edits] grouped by file, also injecting the adapter's required
  /// import once per file. Reads the file fresh from disk so the offsets in
  /// [edits] are still valid.
  RewriteResult apply(List<SourceEdit> edits) {
    final byFile = <String, List<SourceEdit>>{};
    for (final e in edits) {
      byFile.putIfAbsent(e.filePath, () => []).add(e);
    }
    for (final list in byFile.values) {
      // Apply later edits first so earlier offsets stay valid.
      list.sort((a, b) => b.offset.compareTo(a.offset));
    }

    final filesWritten = <String>[];
    var editCount = 0;
    byFile.forEach((path, list) {
      final file = File(path);
      var source = file.readAsStringSync();
      for (final e in list) {
        source = source.replaceRange(e.offset, e.end, e.newText);
        editCount++;
      }
      // Inject the import last so it doesn't shift the edit offsets above.
      source = ImportInjector.inject(source, adapter.requiredImport);
      file.writeAsStringSync(source);
      filesWritten.add(path);
    });
    return RewriteResult(filesWritten: filesWritten, editCount: editCount);
  }
}
