import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:l10n_automator/l10n_automator.dart';
import 'package:test/test.dart';

/// Helper: parses [source] and returns every Candidate the extractor produces.
List<Candidate> _extract(String source) {
  final unit = parseString(content: source).unit;
  return StringExtractor(Config())
      .extract('/tmp/test.dart', source, unit);
}

void main() {
  group('Classifier — UI strings (localize)', () {
    test("Text('Hello') is localize", () {
      final cs = _extract('''
        import 'package:flutter/material.dart';
        Widget build(BuildContext context) => Text('Hello');
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'Hello');
      expect(c.decision, Decision.localize);
      expect(c.hasBuildContextInScope, isTrue);
    });

    test('hintText: named arg is localize', () {
      final cs = _extract('''
        Widget f(BuildContext context) => TextField(
              decoration: InputDecoration(hintText: 'Search...'),
            );
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'Search...');
      expect(c.decision, Decision.localize);
    });

    test('SelectableText("...") is localize', () {
      final cs = _extract('''
        Widget f(BuildContext context) => SelectableText('Copy me');
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'Copy me');
      expect(c.decision, Decision.localize);
    });
  });

  group('Classifier — never localize (skip)', () {
    test('Image.asset path is skipped', () {
      final cs = _extract('''
        Widget f() => Image.asset('assets/images/logo.png');
      ''');
      final c = cs.firstWhere((c) => c.literalValue.contains('logo.png'));
      expect(c.decision, Decision.skip);
    });

    test('Navigator.pushNamed route is skipped', () {
      final cs = _extract('''
        void go(BuildContext context) {
          Navigator.pushNamed(context, '/home');
        }
      ''');
      final c = cs.firstWhere((c) => c.literalValue == '/home');
      expect(c.decision, Decision.skip);
    });

    test('debugPrint message is skipped', () {
      final cs = _extract("debugPrint('user clicked');");
      final c = cs.firstWhere((c) => c.literalValue == 'user clicked');
      expect(c.decision, Decision.skip);
    });

    test('URL value is skipped', () {
      final cs = _extract("final url = 'https://api.example.com/v1';");
      final c = cs.first;
      expect(c.decision, Decision.skip);
    });

    test('Map literal key is skipped', () {
      final cs = _extract('''
        final h = {'Content-Type': 'application/json'};
      ''');
      final ct = cs.firstWhere((c) => c.literalValue == 'Content-Type');
      expect(ct.decision, Decision.skip);
    });

    test('Index expression key is skipped', () {
      final cs = _extract('''
        Object? read(Map<String, dynamic> j) => j['userId'];
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'userId');
      expect(c.decision, Decision.skip);
    });

    test('RegExp pattern is skipped', () {
      final cs = _extract("final r = RegExp(r'^[A-Z]+\$');");
      // Raw strings still surface to the extractor.
      expect(cs.any((c) => c.decision == Decision.skip), isTrue);
    });

    test('MethodChannel id is skipped', () {
      final cs = _extract("final c = MethodChannel('com.foo.bar');");
      final c = cs.firstWhere((c) => c.literalValue == 'com.foo.bar');
      expect(c.decision, Decision.skip);
    });

    test('empty string is skipped', () {
      final cs = _extract("Widget f(BuildContext c) => Text('');");
      final c = cs.firstWhere((c) => c.literalValue == '');
      expect(c.decision, Decision.skip);
    });

    test('punctuation-only string is skipped', () {
      final cs = _extract("Widget f(BuildContext c) => Text('---');");
      final c = cs.firstWhere((c) => c.literalValue == '---');
      expect(c.decision, Decision.skip);
    });
  });

  group('Classifier — review queue', () {
    test('throw Exception("msg") is review', () {
      final cs = _extract('''
        void f() { throw Exception('Bad input'); }
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'Bad input');
      expect(c.decision, Decision.review);
    });

    test('top-level const is review', () {
      final cs = _extract("const greeting = 'Hello world';");
      final c = cs.firstWhere((c) => c.literalValue == 'Hello world');
      expect(c.decision, Decision.review);
    });
  });

  group('Directives', () {
    test('// l10n:ignore on preceding line skips the literal entirely', () {
      final cs = _extract('''
        Widget f(BuildContext c) {
          // l10n:ignore
          return Text('Internal label');
        }
      ''');
      expect(cs.any((c) => c.literalValue == 'Internal label'), isFalse);
    });

    test('// l10n:key=customKey is preserved as overrideKey', () {
      final cs = _extract('''
        Widget f(BuildContext c) {
          // l10n:key=loginCta
          return Text('Sign in');
        }
      ''');
      final c = cs.firstWhere((c) => c.literalValue == 'Sign in');
      expect(c.overrideKey, equals('loginCta'));
      expect(c.decision, Decision.localize);
    });
  });

  group('Interpolation', () {
    test("'Hello \$name' → ARB value 'Hello {name}'", () {
      final cs = _extract(r'''
        Widget f(BuildContext c, String name) => Text('Hello $name');
      ''');
      final c = cs.firstWhere((c) => c.literalValue.startsWith('Hello'));
      expect(c.literalValue, equals('Hello {name}'));
      expect(c.interpolationPlaceholders['name'], equals('name'));
      expect(c.hasInterpolation, isTrue);
    });

    test(r"'Total: ${cart.total}' → placeholder name 'cartTotal'", () {
      final cs = _extract(r'''
        Widget f(BuildContext c, dynamic cart) => Text('Total: ${cart.total}');
      ''');
      final c = cs.firstWhere((c) => c.literalValue.startsWith('Total'));
      expect(c.literalValue, equals('Total: {cartTotal}'));
      expect(c.interpolationPlaceholders['cartTotal'], equals('cart.total'));
    });
  });
}
