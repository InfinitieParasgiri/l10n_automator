import 'package:l10n_automator/l10n_automator.dart';
import 'package:test/test.dart';

void main() {
  final config = Config();
  final gen = KeyGenerator(config);

  group('KeyGenerator', () {
    test('camelCase from a normal sentence', () {
      expect(gen.baseKey('Sign in to continue'), equals('signInToContinue'));
    });

    test('handles single word', () {
      expect(gen.baseKey('Hello'), equals('hello'));
    });

    test('strips punctuation', () {
      expect(gen.baseKey('Hello, world!'), equals('helloWorld'));
    });

    test('caps at max length', () {
      final long = 'a' * 100;
      expect(gen.baseKey(long).length, lessThanOrEqualTo(config.keyMaxLength));
    });

    test('leading-digit becomes prefixed', () {
      expect(gen.baseKey('1 item').startsWith('one'), isTrue);
    });

    test('reserved word gets Label suffix', () {
      expect(gen.baseKey('class'), equals('classLabel'));
    });

    test('determinism — same input twice, same key', () {
      expect(gen.baseKey('Save changes'), equals(gen.baseKey('Save changes')));
    });

    test('disambiguate adds 4-hex suffix on collision', () {
      final base = 'foo';
      final taken = <String>{'foo'};
      final result = gen.disambiguate(base, 'a different value', taken);
      expect(result, startsWith('foo_'));
      expect(result, isNot(equals('foo')));
      expect(result.length, greaterThan(base.length));
    });

    test('returns base unchanged when not taken', () {
      expect(gen.disambiguate('foo', 'val', <String>{}), equals('foo'));
    });

    test('strips ICU placeholders before generating key', () {
      // From a string like "Hello {name}".
      expect(gen.baseKey('Hello {name}'), equals('hello'));
    });
  });
}
