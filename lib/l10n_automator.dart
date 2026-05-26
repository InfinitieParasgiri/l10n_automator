/// Public library entry point.
///
/// `l10n_automator` is primarily a CLI tool —
/// run `dart run l10n_automator <cmd>` from a Flutter project's
/// root to scan, extract, and rewire hardcoded strings.
///
/// At runtime, the package also exposes small Flutter-side helpers
/// ([L10nAutomatorBootstrap], [MissingTranslationBanner]) that surface
/// forgotten / missing translations during development.
///
/// The CLI building blocks are exported here too, so you can compose them
/// in your own Dart scripts or tests.
library;

// Runtime (Flutter) helpers.
export 'src/runtime/l10n_automator_bootstrap.dart';
export 'src/runtime/missing_translation_banner.dart';

// CLI building blocks.
export 'src/adapters/l10n_adapter.dart';
export 'src/arb/arb_file.dart';
export 'src/arb/arb_merger.dart';
export 'src/config/config.dart';
export 'src/config/stack_detector.dart';
export 'src/extractor/candidate.dart';
export 'src/extractor/classifier.dart';
export 'src/extractor/interpolation_handler.dart';
export 'src/extractor/string_extractor.dart';
export 'src/key_gen/key_generator.dart';
export 'src/pipeline.dart';
export 'src/review/interactive_review.dart';
export 'src/rewriter/code_rewriter.dart';
export 'src/rewriter/import_injector.dart';
export 'src/safety/backup_manager.dart';
export 'src/safety/git_check.dart';
export 'src/safety/post_validator.dart';
export 'src/scanner/dart_ast_scanner.dart';
export 'src/scanner/file_walker.dart';
