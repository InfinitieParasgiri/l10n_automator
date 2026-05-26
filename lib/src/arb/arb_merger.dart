import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../key_gen/key_generator.dart';
import 'arb_file.dart';

/// Represents a single string we want in the ARB output.
class ArbEntry {
  ArbEntry({
    required this.value,
    required this.placeholders,
    this.description,
    this.preferredKey,
  });

  final String value;
  final Map<String, String> placeholders;
  final String? description;

  /// If set, the generator will try to use this exact key (overrides
  /// key generation). Used by `// l10n:key=foo` directives.
  final String? preferredKey;
}

/// Result of merging: maps the *value* to the *final key* used in the ARB.
class MergeResult {
  MergeResult({required this.keyByValue, required this.newKeyCount});
  final Map<String, String> keyByValue;
  final int newKeyCount;
}

/// Merges a set of [ArbEntry]s into the template ARB (en) plus all other
/// locale files in the same directory. Never overwrites existing
/// translations; new keys get a [TODO] placeholder in non-template locales.
class ArbMerger {
  ArbMerger(this.config) : keyGen = KeyGenerator(config);

  final Config config;
  final KeyGenerator keyGen;

  MergeResult mergeIntoFlutterL10n({
    required String projectRoot,
    required List<ArbEntry> entries,
  }) {
    final arbDir = p.normalize(p.join(projectRoot, config.arbDir));
    final templatePath = p.join(arbDir, config.templateArbFile);
    final template = ArbFile.load(templatePath);
    template.locale ??= _localeFromFilename(config.templateArbFile) ?? 'en';

    final taken = template.entries.keys
        .where((k) => !k.startsWith('@'))
        .toSet();
    final keyByValue = <String, String>{};
    var newCount = 0;

    for (final entry in entries) {
      // 1) If the same value already exists, reuse the key.
      final existing = template.findKeyByValue(entry.value);
      if (existing != null) {
        keyByValue[entry.value] = existing;
        continue;
      }

      // 2) Use preferred key (from // l10n:key=) if available and free.
      String key;
      if (entry.preferredKey != null && !taken.contains(entry.preferredKey)) {
        key = entry.preferredKey!;
      } else {
        final base = keyGen.baseKey(entry.value);
        key = keyGen.disambiguate(base, entry.value, taken);
      }

      template.upsert(
        key,
        value: entry.value,
        description: entry.description,
        placeholders: entry.placeholders,
      );
      taken.add(key);
      keyByValue[entry.value] = key;
      newCount++;
    }

    template.save();
    _mirrorIntoOtherLocales(arbDir, template, keyByValue);
    return MergeResult(keyByValue: keyByValue, newKeyCount: newCount);
  }

  MergeResult mergeIntoEasyLocalization({
    required String projectRoot,
    required List<ArbEntry> entries,
  }) {
    // For easy_localization we use a flat JSON keyed by string id, mirrored
    // into one file per locale under `translations_dir`. Same merge logic.
    final dir = p.normalize(p.join(projectRoot, config.translationsDir));
    final templatePath =
        p.join(dir, '${config.fallbackLocale}.json');
    final template = ArbFile.load(templatePath);
    template.locale ??= config.fallbackLocale;

    final taken = template.entries.keys
        .where((k) => !k.startsWith('@'))
        .toSet();
    final keyByValue = <String, String>{};
    var newCount = 0;

    for (final entry in entries) {
      final existing = template.findKeyByValue(entry.value);
      if (existing != null) {
        keyByValue[entry.value] = existing;
        continue;
      }
      String key;
      if (entry.preferredKey != null && !taken.contains(entry.preferredKey)) {
        key = entry.preferredKey!;
      } else {
        final base = keyGen.baseKey(entry.value);
        key = keyGen.disambiguate(base, entry.value, taken);
      }
      // easy_localization doesn't use ARB metadata; just write the value.
      template.entries[key] = entry.value;
      taken.add(key);
      keyByValue[entry.value] = key;
      newCount++;
    }

    template.save();
    _mirrorIntoOtherLocales(dir, template, keyByValue,
        fileSuffix: '.json');
    return MergeResult(keyByValue: keyByValue, newKeyCount: newCount);
  }

  // ---------------------------------------------------------------------------

  void _mirrorIntoOtherLocales(
    String dir,
    ArbFile template,
    Map<String, String> keyByValue, {
    String fileSuffix = '.arb',
  }) {
    if (!config.fillMissingFromTemplate) return;
    final dirEntity = Directory(dir);
    if (!dirEntity.existsSync()) return;
    for (final f in dirEntity.listSync()) {
      if (f is! File) continue;
      if (!f.path.endsWith(fileSuffix)) continue;
      if (p.equals(f.path, template.path)) continue;
      final other = ArbFile.load(f.path);
      var changed = false;
      for (final value in keyByValue.keys) {
        final key = keyByValue[value]!;
        if (!other.entries.containsKey(key)) {
          other.upsertIfMissing(
            key,
            value: '${config.placeholderPrefix}$value',
          );
          changed = true;
        }
      }
      if (changed) other.save();
    }
  }

  String? _localeFromFilename(String filename) {
    // Matches `app_en.arb` -> `en`; `en.arb` -> `en`.
    final m = RegExp(r'(?:^|_)([a-z]{2}(?:_[A-Z]{2})?)\.arb$').firstMatch(filename);
    return m?.group(1);
  }
}
