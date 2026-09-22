// Widget smoke test of the app shell: the four navigation destinations plus
// the database gating (an in-memory drift database is injected, so the test
// stays file-free and platform-channel-free).
//
// `flutter test` runs gen-l10n automatically (l10n.yaml), so the generated
// AppLocalizations import resolves on first run.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';

/// The tests pin the German language explicitly: the app's real default is
/// the system language (nullable localeProvider) and the test runner
/// exposes an English device — so the German-string assertions below have
/// to manage German explicitly (how the locale travels — system device vs.
/// switcher choice — is covered by the locale tests, test/locale_test.dart).

void main() {
  testWidgets('app shell shows the four navigation destinations (German)', (
    WidgetTester tester,
  ) async {
    // Explicit German pin so the German labels below hold; how German is
    // *reached* (system device vs. switcher choice) is tested in
    // test/locale_test.dart.
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    // Let the gated shell resolve the (already-synchronous-ish) database
    // future, then settle screens and any transcription animations.
    await tester.pumpAndSettle();

    const labels = ['Tagebuch', 'Zyklus', 'Statistik', 'Einstellungen'];
    for (final label in labels) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'Navigation destination "$label" should be present',
      );
    }

    // Switching tabs shows the corresponding screen (each has an AppBar
    // carrying the same localized name as its label).
    const switchTargets = ['Zyklus', 'Statistik', 'Einstellungen', 'Tagebuch'];
    for (final label in switchTargets) {
      await tester.tap(navLabel(label));
      await tester.pumpAndSettle();
      expect(
        find.text(label),
        findsWidgets,
        reason: 'After tapping "$label" its screen should be shown',
      );
    }
  });

  testWidgets('mucus form: sign picker with conditional quality picker',
      (WidgetTester tester) async {
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Tagebuch'));
    await tester.pumpAndSettle();

    // The sign picker offers the unset option plus the four glyphs
    // t / Ø / f / S (glyphs are the display, per cheat-sheet convention).
    const signGlyphs = ['—', 't', 'Ø', 'f', 'S'];
    for (final glyph in signGlyphs) {
      expect(
        find.text(glyph),
        findsWidgets,
        reason: 'Sign segment "$glyph" should be present',
      );
    }

    // The quality picker stays hidden until the sign S is selected.
    expect(find.text('Qualität'), findsNothing);
    await tester.ensureVisible(find.text('S'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();
    expect(find.text('Qualität'), findsOneWidget);
    const qualityTokens = [
      'w',
      'mi',
      'cr',
      'kl',
      'glb',
      'g',
      'EW',
      'gl',
      'fl',
      'ns'
    ];
    for (final token in qualityTokens) {
      expect(
        find.text(token),
        findsOneWidget,
        reason: 'Quality chip "$token" should be offered on S',
      );
    }

    // Selecting a quality keeps the picker; switching to another sign
    // hides it again (a quality only exists together with S).
    await tester.ensureVisible(find.text('EW'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EW'));
    await tester.pumpAndSettle();
    expect(find.text('Qualität'), findsOneWidget);
    await tester.ensureVisible(find.text('Ø'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ø'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Qualität'), findsNothing);
  });

  testWidgets('PIN lock stub is visible and non-interactive',
      (WidgetTester tester) async {
    // The stub must be visibly NOT interactive (onChanged: null) — flipping
    // it would falsely signal an existing protection (ADR-0005).
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    // The settings list has grown (the temperature-range card sits first):
    // the PIN stub can start below the scroll's initial cache extent, so
    // bring the list down until the stub renders.
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    final pinSwitch =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(pinSwitch.value, isFalse);
    expect(pinSwitch.onChanged, isNull);
  });
}
