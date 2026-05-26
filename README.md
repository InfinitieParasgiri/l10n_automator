# l10n_automator

> **Find every hardcoded string in your Flutter app, move it to ARB, and rewire the source — without writing regex over your code.**

`l10n_automator` is a Flutter package + CLI that:

1. **Scans** your `lib/` with `package:analyzer` (an AST, not regex).
2. **Classifies** every string as something to translate, something to skip, or something for you to review.
3. **Extracts** the keepers into your ARB / JSON localization files and **rewrites** the source to call your localization API.
4. **Verifies** with `dart format` + `dart analyze`, and rolls back automatically if anything breaks.

Works with both `flutter_localizations` (the official ARB stack) and `easy_localization`.

---

## Table of contents

- [Install](#install)
- [60-second quickstart](#60-second-quickstart)
- [Recommended workflow on a big project](#recommended-workflow-on-a-big-project)
- [The three buckets: localize / review / skip](#the-three-buckets-localize--review--skip)
- [Commands](#commands)
- [Scanning specific files](#scanning-specific-files)
- [Per-file breakdown](#per-file-breakdown)
- [Inline directives](#inline-directives)
- [Recommended `.localizator.yaml`](#recommended-localizatoryaml)
- [Runtime helper (optional)](#runtime-helper-optional)
- [Safety guarantees](#safety-guarantees)
- [FAQ / troubleshooting](#faq--troubleshooting)
- [Limitations](#limitations)
- [License](#license)

---

## Install

In your Flutter project's `pubspec.yaml`:

```yaml
dev_dependencies:
  l10n_automator:
    git:
      url: https://github.com/InfinitieParasgiri/l10n_automator.git
      ref: main
```

Then:

```bash
flutter pub get
```

> **Why `dev_dependencies`?** The CLI is only used during development. Putting it under `dev_dependencies` keeps the package out of your release build. If you also want the runtime helper widgets (`L10nAutomatorBootstrap`, `MissingTranslationBanner`), move it to `dependencies` instead.

---

## 60-second quickstart

```bash
# 1. Drop a config file at the project root
dart run l10n_automator init

# 2. See what's hardcoded, file by file
dart run l10n_automator scan --by-file

# 3. One-shot extraction on one folder — no flags to remember
dart run l10n_automator go -p lib/screens/<folder>

# 4. If anything looks wrong, undo the last run
dart run l10n_automator rollback
```

`go` is the friction-free wrapper: it runs `extract --auto`, only refuses
on dirty files *inside the scan target*, and prints a clean summary at
the end. For more control (interactive prompts, dry-runs, custom keys)
use `extract` directly — see the [Commands](#commands) section.

Don't run `go` over your whole `lib/` on the first try — see the next section.

---

## Recommended workflow on a big project

Running `extract` over thousands of files on day one is overwhelming and produces a noisy diff. Here's a sane order:

**Step 1 — Get a feel for the codebase.**

```bash
dart run l10n_automator scan -f
```

Look at the per-file table. If you see files at the top that you'd never want to translate (generated localization files, JSON models, route definitions, API endpoint constants), they're noise. Two ways to drop them:

- **Quick and global:** add their paths to `ignore.files` in `.localizator.yaml`.
- **Per-file:** add `// l10n_automator:ignore_for_file` at the top of the file.

See [Recommended `.localizator.yaml`](#recommended-localizatoryaml) for a starter set of ignore globs that handles the usual suspects.

**Step 2 — Inspect anything suspicious.**

```bash
dart run l10n_automator doctor -p lib/Model/some_model.dart
```

`doctor` prints the actual string values plus the reason the classifier left them in the review queue. If they're all JSON keys like `"id"`, `"name"`, `"created_at"`, exclude the file.

**Step 3 — Extract one screen at a time.**

```bash
dart run l10n_automator extract -p lib/screens/login_page.dart
```

You'll be prompted for each `review` candidate. Accept, skip, or give it a custom key. Commit the diff. Move on to the next screen.

**Step 4 — Once the noise is gone, do an unattended sweep.**

```bash
dart run l10n_automator extract --auto
```

`--auto` only rewrites the high-confidence `localize` bucket. Anything the classifier wasn't sure about is left untouched.

---

## The three buckets: localize / review / skip

Every string literal in your code falls into exactly one of these:

### `localize` — rewritten automatically

The classifier has a positive UI signal. Examples:

```dart
Text('Welcome back')                                 // ← positional arg to Text
TextField(decoration: InputDecoration(
  hintText: 'Search...',                             // ← known UI named arg
  labelText: 'Query',
))
SelectableText('Tap below to continue')
Tooltip(message: 'Close')
```

Rewritten into:

```dart
Text(AppLocalizations.of(context)!.welcomeBack)
```

…plus a new entry in `app_en.arb` (and `[TODO]` placeholders in your other locales).

### `skip` — left alone, never asked about

The classifier has a positive *non-UI* signal:

- Asset paths: `Image.asset('assets/logo.png')`, `SvgPicture.asset(...)`, `Lottie.asset(...)`, `AssetImage(...)`, `rootBundle.load*(...)`
- Routes: `Navigator.pushNamed(context, '/details')`, GoRouter path strings
- Logs: `print(...)`, `debugPrint(...)`, `developer.log(...)`, `logger.d/i/w/e(...)`, `talker.info(...)`
- System APIs: `RegExp(...)`, `DateFormat(...)`, `MethodChannel(...)`, `EventChannel(...)`, `Uri.parse(...)`, `String.fromEnvironment(...)`
- Annotations: `@JsonKey(name: 'foo')`, `@Deprecated('reason')`
- Map keys and index lookups: `{'Content-Type': 'application/json'}`, `json['userId']`
- URLs (`https://...`, `mailto:...`), file extensions, env-style `ALL_CAPS_TOKENS`
- Empty / whitespace-only / no-letters strings
- Generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, `*.config.dart`, anything under `generated/`, `.dart_tool/`, `build/`
- Test files: `test/`, `integration_test/`

### `review` — you decide

The classifier has *no* signal either way. Examples:

```dart
throw Exception('User not found');     // might be a user-facing error, might not
const errorMessage = 'Login failed';   // top-level const — UI label? config?
final greeting = 'Hi ' + user.name;    // concat — needs rewriting to interpolation first
```

Interactive `extract` prompts you for each one. `extract --auto` skips them all.

> **Heads-up:** the classifier is *syntactic* — it doesn't know types. A string like `"id"` inside a `Map<String, dynamic>` constructor can look the same as a UI label. If you see model-file noise in the review queue, exclude those files (see the [recommended config](#recommended-localizatoryaml)).

---

## Commands

| Command | What it does |
|---|---|
| `init` | Create `.localizator.yaml` in the project root with default settings. Add `--force` to overwrite an existing file. |
| `scan` | Walk `lib/` (or `--path` targets), classify every string literal, print a summary. Never writes. |
| `go` | One-shot wrapper around `extract --auto`. Only refuses on dirty files *inside the scan target* — unrelated uncommitted changes don't block it. Use this when you want to type one command per folder. |
| `extract` | Run the full pipeline: extract → merge into ARB → rewrite source → format → analyze. Interactive by default, supports `--auto`, `--dry-run`, custom paths. |
| `doctor` | Validate config, report the detected stack, dump the review queue with each string's value and the reason it was flagged. |
| `rollback` | Restore source files from the most recent backup snapshot. |

### `scan` / `extract` flags

| Flag | Default | Effect |
|---|---|---|
| `--path`, `-p <file-or-glob>` | scan all of `lib/` | Limit the run to one file, directory, or glob (relative to project root). Repeatable. |
| `--by-file`, `-f` | off | Print a per-file table after the summary, sorted by actionable hits. |
| `--top <N>` | `50` | With `--by-file`, cap the table at N rows. `0` = no cap. |
| `--include-skip` | off | With `--by-file`, also include files whose only hits are skipped. |
| `--auto` (extract only) | off | No prompts. Only rewrite the high-confidence `localize` bucket. |
| `--dry-run` (extract only) | off | Show what would change, write nothing. |
| `--no-backup` (extract only) | on | Skip the backup snapshot. Not recommended. |
| `--force` (extract only) | off | Run even on a dirty git tree. |
| `--config <path>` | `.localizator.yaml` | Use a different config file. |

---

## Scanning specific files

By default `scan` / `extract` / `doctor` walk all of `lib/`. To target a single screen, a folder, or any glob, pass one or more `--path` (`-p`) arguments — it's repeatable:

```bash
# one file
dart run l10n_automator extract -p lib/screens/login_page.dart

# a whole folder
dart run l10n_automator extract -p lib/screens

# a glob — quote it so your shell doesn't expand it first
dart run l10n_automator scan -p 'lib/features/**/view/*.dart'

# multiple targets in one run
dart run l10n_automator extract \
  -p lib/screens/login_page.dart \
  -p lib/screens/signup_page.dart
```

The exclude rules from `.localizator.yaml` still apply on top of `--path`, so pointing at a parent folder won't drag in `*.g.dart` siblings.

---

## Per-file breakdown

Big projects produce big totals. `--by-file` (`-f`) shows where the work actually lives:

```bash
dart run l10n_automator scan -f                  # top 50 most actionable
dart run l10n_automator scan -f --top 20         # cap at 20
dart run l10n_automator scan -f --top 0          # show everything
dart run l10n_automator scan -f --include-skip   # also show files with only skipped hits
```

Sample output:

```
Localization Automator — summary
  files scanned  : 529
  literals found : 13579
    localize     : 36
    review       : 4856
    skip         : 8687
  (no changes written)

By file (top 50 of 312):
  file                                              localize  review  total
  ------------------------------------------------  --------  ------  -----
  lib/features/news/view/news_detail_page.dart           12     184    196
  lib/features/onboarding/view/welcome_page.dart          6      71     77
  …
```

Rows are sorted by `localize + review` (descending). Files whose only hits were skipped are hidden by default — the top of the list is always the files you'd actually want to act on.

---

## Inline directives

Override the tool's classification with line-level or file-level comments:

```dart
// Skip this single string, no matter what the classifier thinks.
// l10n:ignore
final secret = 'AAAA-BBBB-CCCC';

// Force this string into a specific key.
// l10n:key=loginCta
Text('Sign in');
```

Skip an entire file (put this anywhere in the first 10 lines):

```dart
// l10n_automator:ignore_for_file
```

The legacy spelling `// localization_automator:ignore_for_file` is also accepted.

---

## Recommended `.localizator.yaml`

`dart run l10n_automator init` writes a sensible default. For a real-world Flutter project, here's a starter that drops the usual noise (generated localization files, JSON models, routes/config constants):

```yaml
stack: auto                       # auto | flutter_localizations | easy_localization

# flutter_localizations options (ignored when stack resolves to easy_localization)
arb_dir: lib/l10n
template_arb_file: app_en.arb
output_class: AppLocalizations

# easy_localization options (ignored when stack resolves to flutter_localizations)
translations_dir: assets/translations
fallback_locale: en

# Optional: override the AppLocalizations import URI. Leave empty to let
# the tool auto-detect (reads l10n.yaml + pubspec.yaml). Set this if
# auto-detection picks the wrong path.
localizations_import: ""

key_naming:
  style: camelCase                # camelCase | snake_case
  max_length: 40
  prefix: ""

min_string_length: 2

ignore:
  files:
    # Generated code
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.gr.dart"
    - "**/*.mocks.dart"
    - "**/*.config.dart"
    - "**/generated/**"
    - "**/.dart_tool/**"
    - "**/build/**"
    # Tests — would break assert-on-literal tests
    - "**/test/**"
    - "**/integration_test/**"
    # Output of `flutter gen-l10n` — these ARE the translations
    - "lib/l10n/**"
    - "**/app_localizations*.dart"
    # JSON / API model classes — strings are field names, not UI
    - "lib/Model/**"
    - "lib/**/model/**"
    - "lib/**/models/**"
    - "lib/**/*_model.dart"
    # Routes & config constants
    - "lib/routes/**"
    - "lib/config/**"

  patterns:
    - "^https?://"                # URLs
    - "^/api/"                    # API paths
    - "^mailto:"
    - "\\.(png|jpg|jpeg|gif|webp|svg|json|mp3|mp4|webm|ttf|otf|lottie)$"
    - "^[A-Z0-9_]{16,}$"          # long ALL_CAPS_TOKENS (API keys, env)

review:
  exceptions: true                # ask about strings inside throw Exception(...)
  top_level_consts: true          # ask about top-level const strings

context:
  on_missing_build_context: skip  # skip | error | prompt

post_actions:
  run_formatter: true             # dart format on touched files
  run_analyzer: true              # dart analyze; rollback on new errors
  run_gen_l10n: true              # flutter gen-l10n after merging into ARB
```

Drop that into `.localizator.yaml` at your project root and run `dart run l10n_automator scan -f` again — the table will be dramatically shorter.

---

## Runtime helper (optional)

The package also exports two tiny Flutter widgets that help you catch missing translations during development. They're a no-op in release builds.

```dart
import 'package:flutter/material.dart';
import 'package:l10n_automator/l10n_automator.dart';

void main() {
  runApp(
    const L10nAutomatorBootstrap(
      reviewReportPath: '.localizator/last_run.json',
      child: MyApp(),
    ),
  );
}
```

In debug builds:

- `L10nAutomatorBootstrap` logs a one-line reminder pointing at the review report from your last CLI run.
- `MissingTranslationBanner(value: someLocalized, child: Text(someLocalized))` paints a tiny `[TODO]` pill over any widget whose `value` still contains a `[TODO]` placeholder (the prefix the CLI writes into non-English ARB files for untranslated keys).

In profile / release builds, both widgets short-circuit and just return their child.

> If you don't want the runtime widgets in your release binary, put the package under `dev_dependencies` and don't import it from `lib/`.

---

## Safety guarantees

- **Refuses to run on a dirty git tree** unless you pass `--force`.
- **Snapshots** every file before touching it to `.localizator/backup/<timestamp>/`. `rollback` restores from the most recent snapshot.
- **Runs `dart analyze`** after rewriting; if any new analyzer error appears, the whole run is rolled back automatically.
- **Runs `dart format`** on every modified file so the diff stays minimal.
- **Never invents a `BuildContext`.** For `flutter_localizations` (which needs `AppLocalizations.of(context)`), strings in places without a `BuildContext` in scope are left alone and reported in `doctor`.
- **Smart ARB merge:** reuses existing keys when the value matches (no duplicates), never renames existing keys, never overwrites translations in non-English ARB files. Re-running the tool produces no new diff.

---

## FAQ / troubleshooting

**Q: I pushed new code to GitHub but my Flutter project keeps using the old version.**
A: `flutter pub get` won't re-fetch a `git:` dependency on a moving ref. Force-refresh with:

```bash
flutter pub upgrade l10n_automator
# if that doesn't pick it up:
rm -rf ~/.pub-cache/git/l10n_automator-*
flutter pub get
```

Confirm the new build is loaded by running `dart run l10n_automator scan --help` and looking for the new flags.

**Q: My `lib/l10n/app_localizations_*.dart` files are showing up in the review queue.**
A: Those are the *output* of `flutter gen-l10n` — they're already your translations. Add `lib/l10n/**` and `**/app_localizations*.dart` to `ignore.files` in `.localizator.yaml`.

**Q: A `*_model.dart` file shows hundreds of `review` hits.**
A: They're almost certainly JSON map keys (`json['id']`, `'name':`, etc.), not UI text. Confirm with `dart run l10n_automator doctor -p path/to/that_model.dart`. If everything in the review queue is short snake_case identifiers, exclude the file (or your whole model folder) in `ignore.files`.

**Q: After `extract`, `dart analyze` failed with `Target of URI doesn't exist: 'package:flutter_gen/gen_l10n/app_localizations.dart'` and the run was rolled back.**
A: Your project has `synthetic-package: false` in `l10n.yaml` (or your Flutter version defaults to it), so `AppLocalizations` lives on disk at `lib/<output-dir>/app_localizations.dart`, not under the synthetic `flutter_gen` package. Versions 0.1.1+ auto-detect this. If you're stuck on an older build, pin the import explicitly in `.localizator.yaml`:

```yaml
localizations_import: 'package:<your_pubspec_name>/l10n/app_localizations.dart'
```

**Q: After `extract`, `dart analyze` said `The getter '<key>' isn't defined for the type 'AppLocalizations'` and the run was rolled back.**
A: This was a pipeline ordering bug — `dart analyze` ran before `flutter gen-l10n`, so the analyzer didn't see the new getters yet. Fixed in 0.1.2+. If you're on 0.1.1, manually re-run with `--no-backup --force` then run `flutter gen-l10n && dart analyze` yourself — but upgrading is easier.

**Q: After `extract`, `dart analyze` complained `Invalid constant value` and rolled back.**
A: The string was inside a `const ...` expression (e.g. `const Text('Hi')`). A rewrite to `AppLocalizations.of(context)!.foo` is non-const, which breaks `const`. Versions 0.1.1+ classify these as `review` automatically. Either drop the surrounding `const`, or accept the prompt in interactive mode after you've removed it.

**Q: I ran `extract --auto` and the diff was tiny. Where are the rest of my strings?**
A: `--auto` only rewrites the `localize` bucket. Anything the classifier wasn't sure about is in `review` and was deliberately left alone. Drop `--auto` for an interactive run, or use `doctor` to look at the review queue and decide what to do per-file.

**Q: I want to undo a run.**
A: `dart run l10n_automator rollback` restores from the most recent backup snapshot. Backups live under `.localizator/backup/<timestamp>/`.

**Q: My git tree is dirty but I want to run anyway.**
A: Pass `--force`. The clean-tree check is there to make sure you can always `git diff` to inspect what the tool changed — if you bypass it, you're mixing your own edits with the tool's.

**Q: How do I pin to a specific commit instead of `main`?**
A:
```yaml
l10n_automator:
  git:
    url: https://github.com/InfinitieParasgiri/l10n_automator.git
    ref: <commit-sha-or-tag>
```

---

## Limitations

- **Syntactic-only.** The classifier uses `parseString` (no type resolution), so it works from naming heuristics rather than the actual static type of an expression. This is why model-file false positives happen.
- **No ICU plural/gender auto-detect.** You'll need to wrap pluralized strings by hand using the generated key as a starting point.
- **Complex interpolations** (`'$a $b'` works fine; `'${user.profile?.displayName ?? "Guest"}'` may produce a placeholder name you'd want to rename manually).
- **No cross-file `const` inlining.** Top-level constants are flagged for review rather than chased across files.

---

## License

MIT.
