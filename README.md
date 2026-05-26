# l10n_automator

A Flutter package that scans your `lib/`, extracts hardcoded UI strings into
an ARB (or JSON) localization file, and rewrites the source to call your
localization API. Supports both `flutter_localizations` and
`easy_localization`. Uses `package:analyzer` for AST-based detection and
rewriting — never regex on Dart source.

Ships with:

- a CLI (`dart run l10n_automator …`) for one-shot extraction, and
- runtime Flutter helpers (`L10nAutomatorBootstrap`, `MissingTranslationBanner`)
  that surface forgotten / `[TODO]` translations during development.

## Install (from Git)

In your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  l10n_automator:
    git:
      url: https://github.com/InfinitieParasgiri/l10n_automator.git
      ref: main
```

Then:

```bash
flutter pub get
dart run l10n_automator init     # writes .localizator.yaml
dart run l10n_automator scan     # dry-run report
dart run l10n_automator extract  # interactive run
```

> Tip: if you only need the CLI and don't want the runtime helpers shipped to
> production, put it under `dev_dependencies` instead of `dependencies`.

## Runtime helper (optional)

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

In debug builds, the wrapper logs unresolved review items and overlays a
small `[TODO]` badge over `Text` widgets you wrap with
`MissingTranslationBanner(value: …, child: …)`. In release builds it
short-circuits to a transparent no-op.

## Commands

| Command | What it does |
|---|---|
| `init` | Create `.localizator.yaml` in the project root with default settings. |
| `scan` | Walk `lib/`, classify every string literal, print a summary. No writes. |
| `extract` | Run the full pipeline: extract → merge into ARB → rewrite source → format → analyze. Interactive by default. |
| `doctor` | Validate config, report the detected stack, list the review queue. |
| `rollback` | Restore source files from the most recent backup snapshot. |

### `extract` flags

| Flag | Effect |
|---|---|
| `--path`, `-p <file-or-glob>` | Limit the run to one file, directory, or glob (relative to project root). Repeatable. When omitted, the whole `lib/` directory is scanned. |
| `--by-file`, `-f` | After the summary, print a per-file table of localize / review counts (sorted by actionable hits). |
| `--top <N>` | With `--by-file`, show at most N rows. Use `0` to show all. Default `50`. |
| `--include-skip` | With `--by-file`, also include files whose only hits are skipped literals. |
| `--auto` | No interactive prompts. Only apply rewrites the classifier is confident about. |
| `--dry-run` | Show what would change, but write nothing. |
| `--no-backup` | Skip the backup snapshot. Not recommended. |
| `--force` | Run even on a dirty git tree. |
| `--config <path>` | Use a different config file. |

### Scanning specific files

By default `scan` / `extract` / `doctor` walk all of `lib/`. To target a
single screen, a folder, or any glob, pass one or more `--path` arguments
(also available as `-p`):

```bash
# one file
dart run l10n_automator extract --path lib/screens/login_page.dart

# a whole folder
dart run l10n_automator extract -p lib/screens

# a glob — note the quotes so your shell doesn't expand it
dart run l10n_automator scan -p 'lib/features/**/view/*.dart'

# multiple targets in one run
dart run l10n_automator extract \
  -p lib/screens/login_page.dart \
  -p lib/screens/signup_page.dart
```

The exclude rules from `.localizator.yaml` (generated files, tests, etc.)
still apply on top of `--path`, so you can safely point it at a parent
directory without dragging in `*.g.dart` siblings.

### Per-file breakdown

Big projects produce big totals. Add `--by-file` (`-f`) to see which files
actually contain the work:

```bash
dart run l10n_automator scan --by-file
dart run l10n_automator scan -f --top 20
dart run l10n_automator scan -f --include-skip   # show "nothing to do" files too
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
  file                                                  localize  review  total
  ----------------------------------------------------  --------  ------  -----
  lib/features/news/view/news_detail_page.dart                12     184    196
  lib/features/onboarding/view/welcome_page.dart               6      71     77
  …
```

Rows are sorted by `localize + review` (descending), so the files that need
your attention surface at the top — files whose only hits were skipped are
hidden unless you pass `--include-skip`.

## How it works

1. **Detect** — read `pubspec.yaml` to figure out which l10n stack the project
   uses, load `.localizator.yaml`, read the existing `app_en.arb`.
2. **Scan** — walk `lib/` (honoring excludes), parse each file with
   `package:analyzer`.
3. **Classify** — every string literal is tagged `localize`, `skip`, or
   `review` based on its surrounding context.
4. **Plan** — generate keys, build a change-set, prompt the user for review
   items (or skip them in `--auto`).
5. **Apply** — smart-merge into ARB (reuses existing keys with matching values,
   never overwrites translations in non-English files), rewrite source via AST
   edits, inject the required import, run `dart format`, run `dart analyze`,
   roll back on any new analyzer error.

## What gets localized vs skipped

**Localized:**

- First positional `String` arg to `Text`, `SelectableText`, `RichText`,
  `TextSpan`.
- Named String args: `hintText`, `helperText`, `errorText`, `labelText`,
  `prefixText`, `suffixText`, `counterText`, `tooltip`, `semanticsLabel`,
  `message`.

**Never localized (skipped automatically):**

- URLs, asset paths, file extensions like `.png .svg .json`.
- Strings inside `Image.asset`, `SvgPicture.asset`, `Lottie.asset`,
  `AssetImage`, `rootBundle.load*`.
- Routes — strings passed to `Navigator.pushNamed`, `pushReplacementNamed`,
  GoRouter paths.
- `print(...)`, `debugPrint(...)`, `developer.log(...)`, `logger.d/i/w/e(...)`,
  `talker.info(...)`.
- `RegExp(...)`, `DateFormat(...)`, `MethodChannel(...)`, `EventChannel(...)`,
  `Uri.parse(...)`, `String.fromEnvironment(...)`.
- Strings in annotations: `@JsonKey(name: ...)`, `@Deprecated(...)`.
- Map literal keys and index lookups: `{'Content-Type': ...}`, `j['userId']`.
- Empty strings, whitespace-only strings, strings with no letters.
- Generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`,
  `*.config.dart`, `generated/`, `.dart_tool/`, `build/`.
- Test files (`test/`, `integration_test/`) — translations would break
  assertion-on-literal tests.

**Flagged for review (skipped in `--auto`, prompted in interactive mode):**

- Strings inside `throw Exception("…")` and similar — may or may not surface
  to the UI.
- Top-level `const` strings — could be a UI label or a config constant.
- String concatenation with `+` — needs rewriting to interpolation first.
- Anything the classifier doesn't have a positive UI signal for.

## Inline directives

Override the tool's decisions with comments on the line above a string:

```dart
// l10n:ignore
final secret = 'AAAA-BBBB-CCCC';

// l10n:key=loginCta
Text('Sign in');
```

To opt out of an entire file, put this at the top:

```dart
// l10n_automator:ignore_for_file
```

The legacy `// localization_automator:ignore_for_file` spelling is also
accepted.

## Smart ARB merge

When the tool generates a new key:

- If the same value already exists in `app_en.arb` under any key, that key is
  **reused** — no duplicate entries.
- Existing keys in `app_en.arb` are **never renamed** by re-running the tool.
- Translations in `app_es.arb`, `app_fr.arb`, etc. are **never overwritten**.
- New keys are mirrored into other-locale files with a `[TODO]` prefix so
  translators can find what needs work.
- `@@locale`, `@@last_modified`, and `@key.description` metadata is preserved.

The tool is **idempotent** — running it twice in a row produces no second-run
changes.

## Safety guarantees

- Refuses to run on a dirty git tree unless you pass `--force`.
- Backs up every file it's about to touch to `.localizator/backup/<timestamp>/`.
  `rollback` restores from the most recent snapshot.
- Runs `dart analyze` after rewriting. If new errors appear, the run is
  automatically rolled back from the backup.
- Runs `dart format` on every modified file so diffs stay minimal.
- Never introduces a `BuildContext` dependency where one didn't exist. For
  `flutter_localizations` (which needs `AppLocalizations.of(context)`), strings
  in places without `BuildContext` in scope are skipped and reported via the
  `doctor` command.

## Configuration

The defaults are sensible; see `.localizator.yaml` after running `init` for the
full schema. The main knobs:

```yaml
stack: auto                       # auto | flutter_localizations | easy_localization

arb_dir: lib/l10n
template_arb_file: app_en.arb
output_class: AppLocalizations

translations_dir: assets/translations   # easy_localization only
fallback_locale: en

key_naming:
  style: camelCase
  max_length: 40
  prefix: ""

min_string_length: 2

ignore:
  files: [...]      # glob list
  patterns: [...]   # regex list
  widgets: [...]    # callee names to skip

review:
  exceptions: true
  top_level_consts: true

context:
  on_missing_build_context: skip

post_actions:
  run_formatter: true
  run_analyzer: true
  run_gen_l10n: true
```

## Pushing this package to GitHub

The package is structured as a standard Flutter package and can be published
straight from this folder:

```bash
cd path/to/Localization\ Automator
git init
git add .
git commit -m "Initial commit: l10n_automator 0.1.0"
git branch -M main
git remote add origin https://github.com/InfinitieParasgiri/l10n_automator.git
git push -u origin main
```

Then any Flutter project can depend on it via the `git:` block shown in the
**Install** section above.

## Limitations

- Uses `parseString` (syntactic only — no type resolution), so the classifier
  works from naming heuristics rather than the actual static type. In practice
  the safety rules + interactive review compensate; in `--auto` mode, anything
  ambiguous is left alone.
- Plural / gender ICU forms aren't auto-detected. Wrap them by hand using the
  generated key as a starting point.
- Strings built from multiple variables (`'$a $b'`) work via interpolation
  placeholders, but if the expressions are complex, the generated placeholder
  names may need a manual rename.
- Doesn't handle cross-file `const` references — top-level constants are
  flagged for review rather than inlined.

## License

MIT.
