import 'dart:io';

import 'package:l10n_automator/l10n_automator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('larb_');
    Directory(p.join(tmp.path, 'lib', 'l10n')).createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('creates a fresh template ARB with new keys', () {
    final merger = ArbMerger(Config());
    final result = merger.mergeIntoFlutterL10n(
      projectRoot: tmp.path,
      entries: [
        ArbEntry(value: 'Hello', placeholders: const {}),
        ArbEntry(value: 'Goodbye', placeholders: const {}),
      ],
    );
    expect(result.newKeyCount, 2);
    final arb = ArbFile.load(p.join(tmp.path, 'lib', 'l10n', 'app_en.arb'));
    expect(arb.value(result.keyByValue['Hello']!), equals('Hello'));
    expect(arb.value(result.keyByValue['Goodbye']!), equals('Goodbye'));
  });

  test('reuses existing key when value matches', () {
    final path = p.join(tmp.path, 'lib', 'l10n', 'app_en.arb');
    File(path).writeAsStringSync('''
{
  "@@locale": "en",
  "welcome": "Hello"
}
''');
    final result = ArbMerger(Config()).mergeIntoFlutterL10n(
      projectRoot: tmp.path,
      entries: [ArbEntry(value: 'Hello', placeholders: const {})],
    );
    expect(result.newKeyCount, 0);
    expect(result.keyByValue['Hello'], equals('welcome'));
  });

  test('does not overwrite non-English locale translations', () {
    File(p.join(tmp.path, 'lib', 'l10n', 'app_en.arb')).writeAsStringSync('''
{
  "@@locale": "en",
  "welcome": "Hello"
}
''');
    File(p.join(tmp.path, 'lib', 'l10n', 'app_es.arb')).writeAsStringSync('''
{
  "@@locale": "es",
  "welcome": "Hola"
}
''');
    ArbMerger(Config()).mergeIntoFlutterL10n(
      projectRoot: tmp.path,
      entries: [
        ArbEntry(value: 'Hello', placeholders: const {}),
        ArbEntry(value: 'Goodbye', placeholders: const {}),
      ],
    );
    final es = ArbFile.load(p.join(tmp.path, 'lib', 'l10n', 'app_es.arb'));
    expect(es.value('welcome'), equals('Hola'),
        reason: 'existing Spanish translation must not be overwritten');
    // New key (for "Goodbye") should appear in es.arb with [TODO] prefix.
    final newKeys = es.translatableKeys.where((k) => k != 'welcome').toList();
    expect(newKeys, isNotEmpty);
    final newVal = es.value(newKeys.first)!;
    expect(newVal, startsWith('[TODO] '));
  });

  test('uses preferred key from directive when free', () {
    final result = ArbMerger(Config()).mergeIntoFlutterL10n(
      projectRoot: tmp.path,
      entries: [
        ArbEntry(value: 'Sign in', placeholders: const {}, preferredKey: 'loginCta'),
      ],
    );
    expect(result.keyByValue['Sign in'], equals('loginCta'));
  });
}
