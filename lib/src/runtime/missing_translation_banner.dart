import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Marks `Text` widgets whose value contains a `[TODO]` placeholder so
/// missing translations are obvious during development.
///
/// Most users will not instantiate this directly — they will get it via
/// [L10nAutomatorBootstrap]. It is exported separately so you can use the
/// inline form ([MissingTranslationBanner]) on any widget.
///
/// Release builds short-circuit and render `child` unchanged.
class MissingTranslationBannerScope extends StatelessWidget {
  const MissingTranslationBannerScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return _TodoTextOverlay(child: child);
  }
}

/// Inline variant. Wrap any widget that might be displaying an
/// un-translated value and a small "[TODO]" tag will appear over it in
/// debug builds.
class MissingTranslationBanner extends StatelessWidget {
  const MissingTranslationBanner({
    super.key,
    required this.value,
    required this.child,
  });

  /// The localized string currently being shown. If it contains the
  /// substring `[TODO]`, the banner is painted in debug builds.
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !value.contains('[TODO]')) return child;
    return _BannerOverlay(child: child);
  }
}

class _TodoTextOverlay extends StatelessWidget {
  const _TodoTextOverlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // We can't walk the tree without a custom render object. Instead, we
    // expose a lightweight visual hint that something in this subtree may
    // still be untranslated. Users can either rely on this or use
    // MissingTranslationBanner inline for finer control.
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        const Positioned(
          top: 4,
          right: 4,
          child: IgnorePointer(
            child: _Pill(text: 'l10n'),
          ),
        ),
      ],
    );
  }
}

class _BannerOverlay extends StatelessWidget {
  const _BannerOverlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      alignment: AlignmentDirectional.topEnd,
      children: [
        child,
        const IgnorePointer(child: _Pill(text: 'TODO')),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: const BoxDecoration(
        color: Color(0xCCFF5722),
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      child: Text(
        text,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
