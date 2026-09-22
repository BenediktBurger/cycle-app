// Widget smoke test of the app shell: the four navigation destinations plus
// the database gating (an in-memory drift database is injected, so the test
// stays file-free and platform-channel-free).
//
// `flutter test` runs gen-l10n automatically (l10n.yaml), so the generated
// AppLocalizations import resolves on first run.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/fixtures.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

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

  testWidgets(
    'wide/landscape shell (800x400) shows a NavigationRail with the four '
    'destinations and tapping it switches tabs',
    (WidgetTester tester) async {
      useViewportSize(tester, const Size(800, 400));
      await tester.pumpWidget(appScope(locale: const Locale('de')));
      await tester.pumpAndSettle();

      // The adaptive shell: a NavigationRail instead of the bottom bar, with
      // the same four destinations.
      expect(
        find.byType(NavigationRail),
        findsOneWidget,
        reason: 'at a wide/landscape size the shell renders a NavigationRail',
      );
      final rail = find.byType(NavigationRail);
      const labels = ['Tagebuch', 'Zyklus', 'Statistik', 'Einstellungen'];
      for (final label in labels) {
        expect(
          find.descendant(of: rail, matching: find.text(label)),
          findsOneWidget,
          reason: 'rail destination "$label" should be present',
        );
      }

      // Tapping a rail destination switches the shown screen (tabIndex).
      await tester.tap(
        find.descendant(of: rail, matching: find.text('Zyklus')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Zyklus'),
        findsWidgets,
        reason: 'after tapping the rail destination the Zyklus screen shows',
      );
      await tester.tap(
        find.descendant(of: rail, matching: find.text('Statistik')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Statistik'),
        findsWidgets,
        reason:
            'after tapping the rail destination the Statistik screen '
            'shows',
      );
    },
  );

  testWidgets(
    'phone-portrait shell (480x800) keeps the bottom NavigationBar and '
    'no rail',
    (WidgetTester tester) async {
      // Not a narrow phone width on purpose: the diary's date row still
      // overflows under widget-test font metrics at 320–412 dp (the
      // documented narrow-width bug, docs/roadmap.md Bugs section — a plain
      // bullet, out of scope here). The shell test only pins the SHELL
      // surface; 480x800 is above the tab's own overflow threshold and far
      // below the rail's breakpoint.
      useViewportSize(tester, const Size(480, 800));
      await tester.pumpWidget(appScope(locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: 'at a phone-portrait size the bottom NavigationBar stays',
      );
      expect(
        find.byType(NavigationRail),
        findsNothing,
        reason: 'no NavigationRail at a phone-portrait size',
      );
    },
  );

  testWidgets('Zyklus screen lays out without overflow at the landscape size', (
    WidgetTester tester,
  ) async {
    useViewportSize(tester, const Size(800, 400));
    await tester.pumpWidget(
      appScope(
        locale: const Locale('de'),
        entriesStream: Stream.value(evaluationScenarioEntries()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Zyklus'));
    await tester.pumpAndSettle();

    expect(
      find.byType(LineChart),
      findsOneWidget,
      reason: 'the temperature curve renders at the landscape size',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'no layout overflow (RenderFlex / viewport) at 800x400',
    );
  });

  testWidgets('mucus form: sign picker with conditional quality picker', (
    WidgetTester tester,
  ) async {
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
      'ns',
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

  testWidgets('PIN lock stub is visible and non-interactive', (
    WidgetTester tester,
  ) async {
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

    final pinSwitch = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(pinSwitch.value, isFalse);
    expect(pinSwitch.onChanged, isNull);
  });
}
