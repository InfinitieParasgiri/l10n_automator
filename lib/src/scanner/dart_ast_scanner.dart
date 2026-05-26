import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Result of parsing a single .dart file.
class ParsedFile {
  ParsedFile({
    required this.path,
    required this.source,
    required this.unit,
  });

  final String path;
  final String source;
  final CompilationUnit unit;
}

/// Parses Dart source into an AST using `package:analyzer`. We use the
/// parse-only path (no resolution) because it's fast and sufficient for
/// finding string literals + their syntactic context.
class DartAstScanner {
  ParsedFile? parseFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final source = file.readAsStringSync();
    final result = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    return ParsedFile(path: path, source: source, unit: result.unit);
  }
}
