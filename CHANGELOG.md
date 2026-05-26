# Changelog

## 0.1.1

- **Fix:** `flutter_localizations` adapter now detects projects that use
  `synthetic-package: false` (or any `l10n.yaml` that generates
  `app_localizations.dart` to disk under `lib/`). The injected import is
  now `package:<your_app>/<output-dir>/<output-file>` instead of the
  synthetic `package:flutter_gen/...` path.
- **Fix:** strings inside `const` expressions (e.g. `const Text('Hi')`,
  `const SomeWidget(label: 'Hi')`) are now classified as `review`
  instead of `localize`, so `--auto` won't break const-ness with a
  non-const `AppLocalizations.of(context)!...` call.
- Optional override: set `localizations_import:` in `.localizator.yaml`
  to pin a specific package URI when auto-detection isn't enough.

## 0.1.0

Initial release as `l10n_automator` (Flutter package + CLI).

- AST-based string extractor (uses `package:analyzer`, never regex).
- Classifier with built-in skip rules for URLs, asset paths, routes, debug logs,
  RegExp, MethodChannel, annotations, env vars, JSON map keys, generated files.
- Smart ARB merge: reuses existing keys when value matches, never overwrites
  non-English translations, inserts `[TODO]` placeholders for new keys in other
  locales.
- Adapters for `flutter_localizations` (`AppLocalizations.of(context)!.key`) and
  `easy_localization` (`'key'.tr()`).
- String interpolation → ICU placeholder conversion.
- Opt-out directives: `// l10n:ignore` (line), `// l10n:key=…` (override),
  `// l10n_automator:ignore_for_file` (whole file; the legacy
  `// localization_automator:ignore_for_file` spelling is still accepted).
- Safety: clean-git-tree check, backup snapshot + rollback, post-write
  `dart analyze`, `dart format`, optional `flutter gen-l10n`.
- CLI: `init`, `scan`, `extract` (interactive default, `--auto` flag),
  `doctor`, `rollback`.
- `scan` / `extract` / `doctor` accept `--path` / `-p` (repeatable) to
  target a specific file, folder, or glob instead of the whole `lib/`.
- `scan` / `extract` accept `--by-file` / `-f` to print a per-file
  breakdown of localize / review counts after the summary, with `--top N`
  and `--include-skip` modifiers.
- Runtime helpers: `L10nAutomatorBootstrap`, `MissingTranslationBanner` —
  debug-only badges/log for `[TODO]` translations, no-op in release builds.
