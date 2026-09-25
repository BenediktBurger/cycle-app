// Widget smoke test of the app shell: the four navigation destinations plus
// the database gating (an in-memory drift database is injected, so the test
// stays file-free and platform-channel-free).
//
// `flutter test` runs gen-l10n automatically (l10n.yaml), so the generated
// AppLocalizations import resolves on first run.
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:cycle_app/ui/settings.dart';
import 'package:cycle_app/ui/statistics.dart';
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

    // The quality row stays hidden until the sign S is selected; the row
    // wrapper is keyed mucusQualityRow, so the key (not the caption) is
    // what pins the picker's visibility.
    expect(find.byKey(const ValueKey('mucusQualityRow')), findsNothing);
    await tester.ensureVisible(diaryChip('mucusSign', 's'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('mucusSign', 's'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mucusQualityRow')), findsOneWidget);
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
    await tester.ensureVisible(diaryChip('mucusQuality', 'ew'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('mucusQuality', 'ew'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mucusQualityRow')), findsOneWidget);
    await tester.ensureVisible(diaryChip('mucusSign', 'nothing'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('mucusSign', 'nothing'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mucusQualityRow')), findsNothing);
  });

  /// The (label, screen-type) pairs of the shell's four destinations in
  /// navigation order — [navLabel] taps and the visible-screen pin follow
  /// the same vocabulary.
  const tabs = <(String, Type)>[
    ('Tagebuch', TagebuchScreen),
    ('Zyklus', ZyklusScreen),
    ('Statistik', StatistikScreen),
    ('Einstellungen', EinstellungenScreen),
  ];

  /// Drives the real diary save path (AppBar action) far enough that the
  /// confirmation snackbar is fully shown: one pump starts the async save,
  /// the next flags it in, the timed pump lets the entrance animation run
  /// out so the final rect is the docked one. The snackbar's seconds-long
  /// display timer keeps running — deliberately, the scenarios below act
  /// WHILE it is visible.
  Future<void> showDiarySavedSnackbar(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('diarySaveAction')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('PIN lock stub is visible and non-interactive', (
    WidgetTester tester,
  ) async {
    // The stub must be visibly NOT interactive (onChanged: null) — flipping
    // it would falsely signal an existing protection (ADR-0005).
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    // The settings list keeps growing with the data it carries: the PIN
    // stub can sit below the scroll's initial cache extent, so bring the
    // list down until the stub renders instead of pinning a drag amount.
    var guard = 0;
    while (tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .length <
        2) {
      guard++;
      assert(
        guard < 10,
        'the settings pane never revealed the PIN stub surface',
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    // The PIN stub is the FIRST switch on the pane (the PDF-export card's
    // anonymize toggle renders after the data-entry cards).
    final pinSwitch = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .first;
    expect(pinSwitch.value, isFalse);
    expect(pinSwitch.onChanged, isNull);
  });

  testWidgets('phone portrait: the save snackbar never drapes the bottom '
      'NavigationBar and tabs stay tappable while it shows', (
    WidgetTester tester,
  ) async {
    useViewportSize(tester, const Size(480, 800));
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();

    await showDiarySavedSnackbar(tester);

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'the save flow shows its confirmation snackbar',
    );
    // The geometric invariant: the NavigationBar's top edge sits at or
    // below the snackbar's bottom edge — the bar is never covered by the
    // snackbar's rect, so its destination taps cannot be intercepted.
    final barTop = tester.getRect(find.byType(NavigationBar)).top;
    final snackbarBottom = tester.getRect(find.byType(SnackBar)).bottom;
    expect(
      barTop,
      greaterThanOrEqualTo(snackbarBottom),
      reason:
          'the snackbar must dock at or above the NavigationBar '
          '(bar top $barTop vs snackbar bottom $snackbarBottom)',
    );

    // Behavioral invariant on top: with the snackbar still on screen, a
    // destination tap really lands on the NavigationBar.
    // Sequential snackbars: saving again while the first one shows must
    // not re-drape the bar either (the second save queues or replaces —
    // either way the visible snackbar keeps the dock-above geometry).
    await showDiarySavedSnackbar(tester);
    expect(
      tester.getRect(find.byType(NavigationBar)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(SnackBar)).bottom),
      reason: 'a second save must not re-drape the NavigationBar',
    );

    await tester.tap(navLabel('Zyklus'));
    await tester.pumpAndSettle();
    expect(
      find.byType(ZyklusScreen),
      findsOneWidget,
      reason: 'the Cycle tab is tappable while the snackbar shows',
    );
    expect(
      find.byType(TagebuchScreen),
      findsNothing,
      reason: 'the tap must have actually switched the shown tab',
    );
  });

  testWidgets(
    'wide shell with rail: all four destinations stay tappable while the '
    'save snackbar shows',
    (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(appScope(locale: const Locale('de')));
      await tester.pumpAndSettle();

      await showDiarySavedSnackbar(tester);

      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'the save flow shows its confirmation snackbar',
      );

      // The rail groups its destinations near the top, far above the
      // snackbar's bottom strip, so every destination must carry through
      // while the snackbar is visible.
      for (final (label, screenType) in tabs) {
        await tester.tap(navLabel(label));
        await tester.pumpAndSettle();
        expect(
          find.byType(screenType),
          findsOneWidget,
          reason:
              'rail destination "$label" is tappable while the snackbar '
              'shows',
        );
      }
    },
  );
}
