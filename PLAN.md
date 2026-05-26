# Flutter Localization Automator — Plan

A Dart package (distributable via Git) that scans a Flutter project's `lib/`, extracts hardcoded UI strings into an `.arb` (or `.json` for `easy_localization`) file, and rewrites the source to use the project's localization API — while smart-merging with existing translations and skipping things that should never be localized.

---

## 1. Is this fully possible to automate?

**Short answer: ~85% automatable. The remaining 15% needs human judgment.**

What the tool can do safely on its own:
- Walk files, parse Dart ASTs, generate stable keys, write `.arb` / `.json`, perform basic widget rewrites.
- Skip the obvious non-UI categories (URLs, asset paths, debug logs, routes, JSON map keys, regex patterns, generated files).
- Merge new keys into an existing `en.arb` without overwriting human-translated values in `es.arb`, `fr.arb`, etc.

What the tool cannot decide on its own and must defer to the user:
- Whether `Exception("…")` / `ArgumentError("…")` strings reach the UI.
- Plural and gender forms — heuristics get ~70%; the rest need eyes.
- Strings assembled from variables or method calls (`"$prefix-${user.name}"`) — often need restructuring before they can be localized.
- Whether a top-of-file `const greeting = "Hi"` is a UI label or a config constant.
- Places where no `BuildContext` is in scope (services, models, static methods) using `flutter_localizations` — a refactoring decision.

Recommended workflow: **`--auto` mode handles the safe 85%; interactive mode handles the ambiguous 15%; a `doctor` command reports the backlog.**

---

## 2. Distribution model

A Dart package added to a target Flutter project as a dev dependency, pulled from Git:

```yaml
# In the target Flutter project's pubspec.yaml
dev_dependencies:
  localization_automator:
    git:
      url: https://github.com/<user>/localization_automator.git
      ref: main
```

Then run from the project root:

```bash
dart run localization_automator init        # one-time: create .localizator.yaml
dart run localization_automator scan        # dry-run report
dart run localization_automator extract     # interactive run (default)
dart run localization_automator extract --auto
dart run localization_automator doctor      # validate config & report backlog
```

---

## 3. Architecture

### Package layout

```
localization_automator/
├── bin/
│   └── localization_automator.dart        # CLI entry point (args package)
├── lib/
│   ├── localization_automator.dart        # public library exports
│   └── src/
│       ├── config/
│       │   ├── config_loader.dart         # reads .localizator.yaml
│       │   └── stack_detector.dart        # detects flutter_localizations vs easy_localization
│       ├── scanner/
│       │   ├── file_walker.dart           # walks lib/, respects gitignore + config excludes
│       │   └── dart_ast_scanner.dart      # uses package:analyzer
│       ├── extractor/
│       │   ├── string_extractor.dart      # finds StringLiteral nodes in AST
│       │   ├── interpolation_handler.dart # handles ${var} → ICU placeholders
│       │   └── classifier.dart            # decides: localize, skip, or flag for review
│       ├── key_gen/
│       │   └── key_generator.dart         # deterministic camelCase keys
│       ├── arb/
│       │   ├── arb_reader.dart
│       │   ├── arb_writer.dart
│       │   └── arb_merger.dart            # smart merge: reuse existing keys, never clobber translations
│       ├── rewriter/
│       │   ├── code_rewriter.dart         # analyzer source edits, never regex
│       │   ├── import_injector.dart       # adds AppLocalizations / easy_localization imports
│       │   └── context_resolver.dart      # checks BuildContext availability at call site
│       ├── adapters/                      # the "which l10n stack?" abstraction
│       │   ├── adapter.dart               # interface
│       │   ├── flutter_l10n_adapter.dart  # AppLocalizations.of(context)!.foo
│       │   └── easy_localization_adapter.dart # 'foo'.tr()
│       ├── review/
│       │   └── interactive_review.dart    # accept/skip/edit per string
│       ├── backup/
│       │   └── backup_manager.dart        # snapshot before changes, rollback on failure
│       └── report/
│           └── reporter.dart              # summary table, diff output, doctor report
├── test/
│   ├── unit/
│   ├── integration/
│   └── fixtures/                          # mini Flutter projects as golden tests
├── example/
│   └── sample_app/                        # demo Flutter app showing before/after
├── pubspec.yaml
└── README.md
```

### Pipeline (5 stages)

1. **Detect** — locate `pubspec.yaml`, identify l10n stack, load `.localizator.yaml`, read existing `.arb` / `.json`.
2. **Scan** — walk `lib/`, parse every `.dart` file with `package:analyzer` into an AST.
3. **Extract & classify** — visit every `StringLiteral` node, classify it as `localize | skip | review`, attach context (call site, parent widget, whether `BuildContext` is in scope).
4. **Plan** — generate keys, build a change-set object: `[ {file, range, oldText, newText, key, value, placeholders} ]`. In interactive mode, prompt the user per item.
5. **Apply** — merge into ARB files, rewrite source files via analyzer source edits, inject imports, run `dart format`, run `dart analyze` as a post-check, and optionally `flutter gen-l10n`.

### Adapter abstraction

```dart
abstract class L10nAdapter {
  String get name;
  bool detect(ProjectMeta project);
  String renderCall(String key, Map<String, String> placeholders, RewriteContext ctx);
  String requiredImport();
  bool needsBuildContext();
  ArbLikeWriter writerFor(File file);
}
```

Concrete implementations:
- `FlutterL10nAdapter` → emits `AppLocalizations.of(context)!.myKey`, writes `.arb`, requires `BuildContext`.
- `EasyLocalizationAdapter` → emits `'my_key'.tr()` or `'my_key'.tr(args: ['x'])`, writes `.json`, no `BuildContext` needed.

---

## 4. Classification rules

### LOCALIZE — clear UI strings

- First positional `String` arg to `Text`, `SelectableText`, `RichText`, `TextSpan`.
- Named args: `title`, `label`, `hintText`, `helperText`, `errorText`, `labelText`, `tooltip`, `semanticsLabel`, `prefixText`, `suffixText`, `counterText`, `placeholder`.
- `SnackBar(content: Text("…"))`, `AlertDialog(title:, content:)`, `showDialog`, `showModalBottomSheet`.
- Material/Cupertino widgets that accept user-facing strings (`AppBar.title`, `ListTile.title/subtitle`, `Chip.label`, `Tab.text`, `BottomNavigationBarItem.label`, etc.).

### SKIP — definitely not localizable

| Category | Examples |
|---|---|
| URLs / endpoints | `"https://api.example.com"`, `"/api/v1/users"`, `"mailto:…"` |
| Asset paths | `"assets/images/logo.png"`, anything ending `.png .jpg .svg .json .lottie .mp3 .mp4 .webp .ttf .otf` |
| Asset constructors | `Image.asset`, `SvgPicture.asset`, `Lottie.asset`, `AssetImage`, `rootBundle.loadString` |
| Routes | `Navigator.pushNamed(…, "/home")`, GoRouter `path:`, route map keys |
| Logging | `print(…)`, `debugPrint(…)`, `developer.log(…)`, `Logger().d/i/e(…)`, `talker.log(…)` |
| Annotations | `@JsonKey(name:)`, `@SerialName(…)`, `@Deprecated(…)` |
| Regex | `RegExp("…")`, `Pattern` literals |
| MethodChannel / EventChannel | `MethodChannel("com.x.y")` |
| Env vars / secrets | `String.fromEnvironment("…")`, strings matching long alphanumeric/api-key heuristics |
| Date format patterns | `DateFormat("yyyy-MM-dd")` |
| HTTP headers / content types | `headers: {"Content-Type": "application/json"}` |
| Map / JSON keys used as lookups | `data["userId"]`, `json["name"]` |
| SQL / DB | `database.query("users", …)`, raw SQL fragments |
| Asserts | `assert(x, "…")` |
| Generated files | `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, `*.config.dart`, `build/`, `.dart_tool/` |
| Empty / whitespace / punctuation-only | `""`, `" "`, `"-"`, `"|"`, `"  •  "` |
| Single char (configurable) | `"X"`, `"A"` |
| Imports | `import "package:…"` (not in scope anyway) |

### REVIEW — ambiguous, requires user decision

- `throw Exception("…")`, `ArgumentError("…")`, custom exceptions — sometimes shown to users via error widgets.
- Top-of-file `const foo = "…"` and `static const` strings — could be UI labels or config.
- Strings inside ternary expressions returning to a Text widget.
- String concatenation: `"Hello " + name` — needs rewrite to interpolation, then ICU placeholder.
- String built with `StringBuffer` — usually skip but flag.
- Strings used as both UI text and identifier (rare but happens).

---

## 5. Edge cases

### String content
- **Interpolation**: `"Hello $name"` → ARB `"hello": "Hello {name}"` with `@hello.placeholders.name` metadata.
- **Multiple placeholders**: `"User $name has $count items"` → 2 placeholders, types inferred (String, num).
- **Object interpolation**: `"Total: ${cart.total}"` — extract `cart.total` to a local variable named `total`, then placeholder; if not possible, flag for review.
- **Adjacent literals**: `"foo" "bar"` (Dart concatenates at compile time) → treat as one string.
- **Raw strings**: `r"..."` — preserve raw semantics; in `.arb` they become normal strings with escaping recomputed.
- **Multi-line strings**: `'''…'''` and `"""…"""` — preserve newlines in ARB value.
- **Escapes**: `"It\'s great"` — JSON-escape correctly in ARB.
- **Unicode / emoji** — must round-trip byte-for-byte.
- **Leading/trailing whitespace** — preserve exactly.
- **Empty string** — never localize.

### Pluralization & gender
- `count == 1 ? "1 item" : "$count items"` is a plural pattern. Heuristic: detect `?:` with `count == 1` / `length == 1` and propose ICU:
  ```
  "itemCount": "{count, plural, =1{1 item} other{{count} items}}"
  ```
  Flag for review — confidence is not high enough to apply silently.
- Gender is rarely auto-detectable; require `// l10n:gender` hint.

### Code structure
- **Cross-file constants**: `const greeting = "Hi"` in one file, `Text(greeting)` in another. v1: leave both alone, flag the const in the doctor report. v2 (optional): inline + localize.
- **Generated code**: skip by pattern, by `// GENERATED` header, by `part of` directive pointing to a generated file.
- **`@Deprecated("…")`**: skip.
- **Already-localized**: `AppLocalizations.of(context)!.foo` and `'foo'.tr()` — leave alone.
- **Mixed**: partial localization in a file — fine, only rewrite the hardcoded ones.

### Context dependency
- For `flutter_localizations`, `AppLocalizations.of(context)` needs a `BuildContext` in scope. Tool walks up the AST to find an enclosing `BuildContext` parameter or `context` local. If absent: in interactive mode, prompt ("skip / extract to a helper that takes context"); in auto mode, skip and log to the doctor report.
- For `easy_localization`, `.tr()` works without context — no problem.

### Key naming
- Style: camelCase by default, configurable (`snake_case`, `SCREAMING_SNAKE`).
- Source: derived from the string content — first 4–6 significant words, max 40 chars, deterministic.
  - `"Sign in to continue"` → `signInToContinue`
  - `"You have exceeded the maximum number of attempts"` → `youHaveExceededTheMaximum`
- Reserved words / leading digits handled: `"1 item"` → `oneItem` or `n1Item`.
- Collisions: if two distinct strings would generate the same key, append a deterministic 4-hex suffix from the string hash.
- Same string twice in code → same key (reuse).
- Existing key in `en.arb` with the same value → reuse key.
- Existing key in `en.arb` with different value → never overwrite; mint a new key.

### ARB file
- Preserve `@@locale`, `@@last_modified`, all `@key` metadata.
- For other locales (`es.arb`, etc.): add the new key with the English value prefixed by `"[TODO] "` (configurable) so translators can find untranslated entries. Never overwrite an existing translation.
- Stable key order: alphabetical by key, metadata entries grouped after their key.
- Trailing newline + 2-space indent (or honor existing file style).

### File I/O
- Preserve line endings (CRLF vs LF), indentation style, trailing newline policy.
- Handle BOM.
- Refuse non-UTF-8 files with a clear error.
- Read-only files: error early, don't partially apply.

---

## 6. Safety rules — to avoid breaking existing code

1. **AST, not regex.** Use `package:analyzer` for both detection and rewriting. Regex misses string-in-comment, string-in-doc-comment, escapes, multi-line, and concatenation cases.
2. **Clean git tree required.** Refuse to run if `git status --porcelain` is non-empty, unless `--force` passed. This guarantees `git diff` shows the tool's changes alone.
3. **Backup snapshot.** Before applying, copy every file the tool will touch to `.localizator/backup/<timestamp>/`. Provide `localization_automator rollback` to restore.
4. **Skip generated code by default.** `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, `*.config.dart`, anything matching `// GENERATED CODE`, and the entire `.dart_tool/` and `build/` trees.
5. **Honor opt-out directives:**
   - File-level: `// localization_automator:ignore_for_file` at the top of a file → skip the file entirely.
   - Line-level: `// l10n:ignore` on the line above a string → leave it alone.
   - Override: `// l10n:key=mySpecificKey` → use this key instead of the generated one.
6. **Post-write validation.** Run `dart analyze` after rewriting. If new errors appear, roll back and report.
7. **Run formatter.** `dart format` on every modified file so diffs stay minimal.
8. **Preserve other-locale translations.** Never write translated values; only insert keys with a `[TODO]` placeholder.
9. **Idempotent.** Running the tool twice produces no changes on the second run. Achieved by checking for the adapter's call pattern before classifying.
10. **Don't introduce a context dependency.** For `flutter_localizations`, skip strings without `BuildContext` in scope.
11. **Don't touch test files** (`test/`, `integration_test/`) by default — tests often assert on literal English strings. Configurable.
12. **Import deduplication.** If `AppLocalizations` is already imported, don't add a second import.
13. **Atomic apply.** Build the complete change-set in memory, then write all files in one pass. Any failure mid-pass triggers full rollback.
14. **Dry-run + diff output for CI.** `--dry-run --output-diff l10n.patch` produces a unified diff and exits non-zero if changes would occur. Use as a pre-commit / PR check.
15. **Telemetry-free.** No network calls, no usage reporting.

---

## 7. Test plan

### Unit tests
- **Classifier** — one positive and one negative test per category in the table above (URLs, assets, routes, debug logs, generated files, etc.).
- **Key generator** — determinism, collision suffix, reserved-word handling, length cap, leading-digit handling.
- **Interpolation handler** — single var, multiple vars, object access (`${cart.total}`), nested interpolation, escapes.
- **ARB merger** — new key, existing key same value (reuse), existing key different value (mint new), metadata preservation, multi-locale preservation.
- **Adapter** — correct call rendering for each stack.
- **Context resolver** — detects `BuildContext` in scope, in a parent function, absent.

### Integration tests (fixture-based)
- Sample Flutter app with ~30 representative strings → snapshot test against golden output.
- Existing `en.arb` with 5 keys → merge correctly, reuse 2, add 3.
- Existing `es.arb` → not modified except for new keys with `[TODO]` placeholder.
- `easy_localization` project → emits `.tr()` and JSON.
- File with `// l10n:ignore` and `// l10n:key=foo` directives → respected.
- Project with `*.g.dart` files → skipped.
- Project with mixed already-localized + hardcoded strings → only hardcoded touched.
- Idempotency: run twice, second run produces zero changes.
- Compile test: `flutter analyze` exits clean after rewrite.

### End-to-end test
- Clone a small open-source Flutter app, run the tool, manually verify the diff.

### Regression / negative tests
- Dirty git tree → tool refuses without `--force`.
- Read-only file in path → clean error, no partial writes.
- Malformed `.arb` → clean error, no writes.
- Non-UTF-8 file → skipped with warning.

---

## 8. CLI surface

```
dart run localization_automator <command> [options]

Commands:
  init       Create .localizator.yaml in project root
  scan       Dry-run: report what would change
  extract    Run extract + rewrite (interactive by default)
  doctor     Validate config; report ambiguous/skipped/review-needed strings
  rollback   Restore the most recent backup snapshot

Common options:
  --config <path>          Default: .localizator.yaml
  --auto                   Skip interactive prompts; apply safe-only rewrites
  --stack <flutter|easy>   Override auto-detected stack
  --dry-run                Show changes, don't apply
  --output-diff <path>     Write unified diff instead of applying
  --include <glob>         Include glob (repeatable)
  --exclude <glob>         Exclude glob (repeatable)
  --no-backup              Skip backup snapshot
  --force                  Run on dirty git tree
  --verbose
```

### Config file (`.localizator.yaml`)

```yaml
stack: auto                       # auto | flutter_localizations | easy_localization

arb_dir: lib/l10n                 # for flutter_localizations
template_arb_file: app_en.arb
output_class: AppLocalizations

# for easy_localization
translations_dir: assets/translations
fallback_locale: en

key_naming:
  style: camelCase                # camelCase | snake_case
  max_length: 40
  prefix: ""                      # global key prefix
  word_separator: ""

ignore:
  files:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/generated/**"
    - "**/test/**"
  patterns:
    - "^https?://"
    - "^/api/"
    - "\\.(png|jpg|svg|json|mp4)$"
    - "^[A-Z0-9_]{16,}$"          # likely env keys
  widgets:
    skip_in: ["Image.asset", "SvgPicture.asset", "MethodChannel"]

review:
  exceptions: true                # flag throw Exception("…") for review
  top_level_consts: true

context:
  on_missing_build_context: skip  # skip | error | prompt

locales:
  fill_missing_from_template: true
  placeholder_prefix: "[TODO] "

post_actions:
  run_formatter: true
  run_analyzer: true
  run_gen_l10n: true              # only for flutter_localizations
```

---

## 9. Build phases

### Phase 1 — MVP (foundation)
- Package skeleton, CLI scaffolding, config loader, stack detector.
- File walker (respects gitignore + excludes), AST scanner.
- Classifier covering the SKIP-by-pattern categories + `Text()` detection.
- Key generator, ARB reader/writer (flutter_localizations only).
- Rewriter for the simplest case: `Text("foo")` → `Text(AppLocalizations.of(context)!.foo)`.
- `scan` (dry-run) and `extract --auto` commands.

### Phase 2 — Robustness
- String interpolation → ICU placeholders.
- Smart merge with existing `en.arb`.
- Preserve non-English locale files.
- `// l10n:ignore` / `// l10n:key=` directives.
- Idempotency guarantee + tests.
- Backup + rollback + git-clean check.
- Post-write `dart analyze` validation.

### Phase 3 — Second stack + interactive mode
- `easy_localization` adapter (.json output, `.tr()` syntax).
- Stack auto-detection from pubspec.
- Interactive review CLI (accept / skip / edit / set-key per string).
- Diff/patch output mode for CI.

### Phase 4 — Edge cases & polish
- Plural detection heuristic.
- `BuildContext` availability analysis.
- Concatenation rewriting (`"x " + y` → interpolation, then ICU).
- Per-line `// l10n:key=` overrides.
- Comprehensive test suite + `example/` Flutter app.
- README + usage docs + GitHub Actions example.

---

## 10. Open questions before implementation

1. **Default behavior for `Exception("…")` strings**: localize, skip, or always review? (Recommendation: review.)
2. **Default behavior for `assert(x, "…")` messages**: skip entirely? (Recommendation: skip.)
3. **Top-level / class-level `const String` UI labels**: try to detect their usage in widgets and localize, or always leave them and flag in doctor? (Recommendation: doctor-flag in v1; auto-handle in v3.)
4. **Default minimum string length to consider**: 2 chars? 3? (Recommendation: 2, configurable.)
5. **Should the tool also run `flutter pub get` + `flutter gen-l10n` automatically at the end?** (Recommendation: yes, behind a config flag, default on.)
6. **License + repo**: MIT? Apache 2.0? Public or private repo?
7. **Minimum Dart SDK version** to support? (Recommendation: 3.0+, since `package:analyzer` evolves quickly.)
