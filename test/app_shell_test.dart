// Widget smoke test of the app shell: the four navigation destinations plus
// the database gating (an in-memory drift database is injected, so the test
// stays file-free and platform-channel-free).
//
// `flutter test` runs gen-l10n automatically (l10n.yaml), so the generated
// AppLocalizations import resolves on first run.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One test database override shared by the widget smoke tests.
///
/// `closeStreamsSynchronously: true` is drift's documented remedy for widget
/// tests failing with "A Timer is still pending even after the widget tree
/// was disposed": without it, drift delays query-stream cancellation by one
/// event-loop turn (Timer.run), and streams cancelled while Riverpod disposes
/// the ProviderScope during tree teardown can never reach that turn in the
/// test's fake async zone.
///
/// [locale] pins an explicit app language for the duration of the test: the
/// app's real default is the system language (nullable localeProvider), and
/// unpinned the test runner exposes an English device — so the German-string
/// assertions below have to request German explicitly (the system-follow
/// default itself is covered by locale_default_test.dart).
ProviderScope _appScope([Locale? locale]) => ProviderScope(
      overrides: [
        // In-memory database: no files, no platform channels, no FFI paths.
        // ref.onDispose closes it together with the test's ProviderScope
        // (same closing semantics as the production provider).
        databaseProvider.overrideWith(
          (ref) {
            final db = CycleDatabase(
              DatabaseConnection(
                NativeDatabase.memory(),
                closeStreamsSynchronously: true,
              ),
            );
            ref.onDispose(db.close);
            return db;
          },
        ),
        if (locale != null) localeProvider.overrideWith((ref) => locale),
      ],
      child: const CycleApp(),
    );

void main() {
  testWidgets('app shell shows the four navigation destinations (German)', (
    WidgetTester tester,
  ) async {
    // Explicit German pin so the German labels below hold; how German is
    // *reached* (system device vs. switcher choice) is tested in
    // locale_default_test.dart.
    await tester.pumpWidget(_appScope(const Locale('de')));
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
      await tester.tap(find.text(label));
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
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tagebuch').first);
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
    const qualityTokens = ['w', 'mi', 'cr', 'kl', 'glb', 'g', 'EW', 'gl', 'fl', 'ns'];
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
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen').first);
    await tester.pumpAndSettle();

    final pinSwitch =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(pinSwitch.value, isFalse);
    expect(pinSwitch.onChanged, isNull);
  });
}
