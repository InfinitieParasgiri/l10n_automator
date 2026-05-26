import 'package:l10n_automator/l10n_automator.dart';
import 'package:test/test.dart';

void main() {
  const importLine = "import 'package:flutter_gen/gen_l10n/app_localizations.dart';";

  test('inserts after the last existing import', () {
    const src = '''
import 'package:flutter/material.dart';

class Foo {}
''';
    final out = ImportInjector.inject(src, importLine);
    expect(out, contains(importLine));
    expect(out.indexOf(importLine),
        greaterThan(out.indexOf("'package:flutter/material.dart'")));
  });

  test('inserts at top when there are no imports', () {
    const src = '// header\n\nclass Foo {}\n';
    final out = ImportInjector.inject(src, importLine);
    expect(out, contains(importLine));
  });

  test('is a no-op if the same import already exists', () {
    final src = '$importLine\nclass Foo {}\n';
    final out = ImportInjector.inject(src, importLine);
    // Count occurrences.
    final count =
        importLine.allMatches(out).length;
    expect(count, 1);
  });
}

extension on String {
  Iterable<Match> allMatches(String source) => RegExp(RegExp.escape(this)).allMatches(source);
}
