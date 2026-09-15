// Widget smoke test of the app shell: the four navigation destinations plus
// the database gating (an in-memory drift database is injected, so the test
// stays file-free and platform-channel-free).
//
// `flutter test` runs gen-l10n automatically (l10n.yaml), so the generated
// AppLocalizations import resolves on first run.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell shows the four navigation destinations (German)', (
    WidgetTester tester,
  ) async {
    // German is the default locale for M1; the language switcher is covered
    // by its own (manual) verification — see docs/verification-m1.md.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // In-memory database: no files, no platform channels, no FFI paths.
          // ref.onDispose closes it together with the test's ProviderScope
          // (same closing semantics as the production provider).
          databaseProvider.overrideWith(
            (ref) {
              final db = CycleDatabase(NativeDatabase.memory());
              ref.onDispose(db.close);
              return db;
            },
          ),
        ],
        child: const CycleApp(),
      ),
    );
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

  testWidgets('PIN lock stub is visible and non-interactive',
      (WidgetTester tester) async {
    // The stub must be visibly NOT interactive (onChanged: null) — flipping
    // it would falsely signal an existing protection (ADR-0005).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith(
            (ref) {
              final db = CycleDatabase(NativeDatabase.memory());
              ref.onDispose(db.close);
              return db;
            },
          ),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen').first);
    await tester.pumpAndSettle();

    final pinSwitch =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(pinSwitch.value, isFalse);
    expect(pinSwitch.onChanged, isNull);
  });
}
