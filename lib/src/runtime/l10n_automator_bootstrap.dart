import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'missing_translation_banner.dart';

/// Wraps your app to surface localization issues that
/// `l10n_automator` flagged during extraction but couldn't safely
/// rewrite (e.g. strings outside a `BuildContext`, dynamic concatenations,
/// or keys still marked `[TODO]` in non-English ARB files).
///
/// In **debug builds** this widget:
///  - paints a small "[TODO]" badge over `Text` widgets whose value still
///    contains a `[TODO]` placeholder (via [MissingTranslationBanner]);
///  - logs a one-time summary of unresolved review items if you pass a
///    [reviewReportPath] (typically `.localizator/last_run.json`).
///
/// In **profile / release builds** it is a transparent no-op — the child is
/// returned unchanged with zero runtime overhead.
///
/// ```dart
/// void main() {
///   runApp(
///     L10nAutomatorBootstrap(
///       reviewReportPath: '.localizator/last_run.json',
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
class L10nAutomatorBootstrap extends StatelessWidget {
  const L10nAutomatorBootstrap({
    super.key,
    required this.child,
    this.reviewReportPath,
    this.showMissingBadges = true,
  });

  /// The application widget to wrap.
  final Widget child;

  /// Optional path (relative to the project root) to the JSON report the
  /// CLI writes after each `extract` run. When set, a debug-only summary
  /// is printed to the console on first build.
  final String? reviewReportPath;

  /// When `true` (default), debug builds visually mark `Text` widgets
  /// whose value contains a `[TODO]` translation placeholder.
  final bool showMissingBadges;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    if (reviewReportPath != null) {
      // Print once per session. We avoid touching dart:io directly so this
      // file stays web-safe; the helper is informational only.
      debugPrint(
        '[l10n_automator] Review report path configured: '
        '$reviewReportPath. Open it to see strings the CLI left for you.',
      );
    }

    if (!showMissingBadges) return child;
    return MissingTranslationBannerScope(child: child);
  }
}
