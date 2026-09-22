// Locale semantics (language default + fallback): with no explicit language chosen in the
// settings (the "System" option), the app follows the platform's language
// when it is one of the supported languages (de/en) and falls back to
// English otherwise — never German (ADR-0007). An explicit settings choice
// wins over the platform regardless of what language the device reports.
//
// The platform locale is simulated through the test binding's platform
// dispatcher; the app itself is unchanged: in-memory drift database
// override, no platform channels (same pattern as app_shell_test.dart, now merged with the former
// l10n_fallback_test.dart into this single locale file — the two
// concerns stay in distinct groups).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

/// App scope for the language tests. A null [locale] means: leave the
/// provider at its real default (the "System" option); anything else is an
/// explicit settings choice.
ProviderScope _appScope({Locale? locale}) => appScope(locale: locale);

/// App scope for the fallback tests: an active language that exists in
/// neither supported language — what the app *resolves it to* is the
/// fallback under test.
ProviderScope _fallbackAppScope(Locale locale) => appScope(locale: locale);

void main() {
  group('default-locale resolution', () {
    testWidgets('system-default on a German device resolves to German UI',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      await tester.pumpWidget(_appScope());
      await tester.pumpAndSettle();

      expect(find.text('Tagebuch'), findsWidgets,
          reason:
              'The system language German must be picked up for de devices');
      expect(find.text('Diary'), findsNothing,
          reason:
              'The fallback must not kick in for a supported device locale');
    });

    testWidgets('system-default on a French device resolves to English UI',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('fr')]);

      await tester.pumpWidget(_appScope());
      await tester.pumpAndSettle();

      expect(find.text('Diary'), findsWidgets,
          reason: 'An unsupported device locale must fall back to English');
      expect(find.text('Tagebuch'), findsNothing,
          reason: 'German is never the automatic fallback (ADR-0007)');
    });

    testWidgets('explicit German choice wins over a French device locale',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('fr')]);

      await tester.pumpWidget(_appScope(locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(find.text('Tagebuch'), findsWidgets,
          reason: 'An explicit language choice must beat the device locale');
      expect(find.text('Diary'), findsNothing);
    });

    testWidgets('explicit English choice wins over a German device locale',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      await tester.pumpWidget(_appScope(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Diary'), findsWidgets,
          reason: 'An explicit language choice must beat the device locale');
      expect(find.text('Tagebuch'), findsNothing);
    });

    testWidgets(
        'settings switcher renders System/Deutsch/English and switches between them',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      await tester.pumpWidget(_appScope());
      await tester.pumpAndSettle();
      // Tap through the shared navigation finder: all tabs stay mounted
      // (IndexedStack), so the 'Einstellungen' label also matches the
      // offstage screen's AppBar — and in tree order that AppBar precedes
      // the shell's navigation surface, so a bare .first tap would miss.
      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      // Scope to the language switcher: the settings screen now also carries a
      // theme-mode switcher whose "System" segment would otherwise collide
      // with the language option of the same name.
      final languageSwitcher = find.byType(SegmentedButton<String>);
      expect(languageSwitcher, findsOneWidget);

      // All three options are offered.
      for (final option in ['System', 'Deutsch', 'English']) {
        expect(
          find.descendant(of: languageSwitcher, matching: find.text(option)),
          findsOneWidget,
          reason: 'Language option "$option" must be offered',
        );
      }
      final switcher = tester.widget<SegmentedButton<String>>(languageSwitcher);
      expect(switcher.selected, {'system'},
          reason: 'The default selection must be "System"');

      // Switching to an explicit language applies it immediately.
      await tester.tap(find.descendant(
          of: languageSwitcher, matching: find.text('English')));
      await tester.pumpAndSettle();
      // With the shell keeping every tab mounted, the label appears in the
      // navigation bar AND in the (offstage) diary screen's AppBar.
      expect(find.text('Diary'), findsWidgets,
          reason: 'Selecting English must switch the UI to English');
      final switcher2 =
          tester.widget<SegmentedButton<String>>(languageSwitcher);
      expect(switcher2.selected, {'en'});

      // Back to the system default: the German device locale returns.
      await tester.tap(
          find.descendant(of: languageSwitcher, matching: find.text('System')));
      await tester.pumpAndSettle();
      expect(find.text('Tagebuch'), findsWidgets,
          reason: 'Selecting System must follow the device locale again');
      final switcher3 =
          tester.widget<SegmentedButton<String>>(languageSwitcher);
      expect(switcher3.selected, {'system'});
    });
  });

  // ─── fallback behavior: the former test/l10n_fallback_test.dart ───
  //
  // Localization fallback tests: a missing translation term for the active
  // locale must fall back to *English* (not the German template text), and
  // an active locale outside the supported de/en set must resolve to
  // English as well (see docs/adr/0007-language-policy.md: multilingual
  // app, English as the fallback language so non-Germans are never exposed
  // to German).
  //
  // The per-term fallback itself is a *codegen-time* mechanism: gen-l10n
  // bakes the template ARB's text into a locale class for any key missing
  // from that locale's ARB. Which key is missing therefore cannot be
  // simulated at runtime; what these tests pin is the two real levers:
  //  - the template ARB is the English one (l10n.yaml
  //    `template-arb-file`),
  //  - an unsupported active language falls back to English via
  //    resolution, i.e. English is the first/last supported locale.
  group('fallback behavior', () {
    testWidgets('unsupported active language resolves to English, not German',
        (WidgetTester tester) async {
      await tester.pumpWidget(_fallbackAppScope(const Locale('fr')));
      await tester.pumpAndSettle();

      expect(
        find.text('Diary'),
        findsWidgets,
        reason: 'An unsupported active locale must fall back to English',
      );
      expect(
        find.text('Tagebuch'),
        findsNothing,
        reason: 'German is never the fallback for an unknown locale',
      );
    });

    test('untranslated keys fall back to English: the template ARB is English',
        () {
      // gen-l10n fills missing terms with the template ARB's text; the
      // fallback language is therefore determined by which ARB is the
      // template.
      final l10nYaml = File('l10n.yaml').readAsStringSync();
      expect(
        l10nYaml,
        contains('template-arb-file: app_en.arb'),
        reason: 'Untranslated terms must fall back to English, i.e. app_en.arb '
            'must be the gen-l10n template',
      );
    });
  });
}
