// Widget tests for the time-of-measurement feature on the Tagebuch screen.
//
// Covers the user-visible behaviours: a fresh day prefills the picker
// control with the current time, a stored time stays when the day is
// re-opened for editing, clearing the time is possible, and the day tiles
// show the stored time.
//
// The clock is pinned through the nowProvider override (the real wall clock
// would make the prefill assertion race with the minute boundary); the
// database is an in-memory override, same pattern as test/app_shell_test.dart.
// The German locale is pinned (like the sibling widget tests) so the 24 h
// format assertions stay deterministic.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Injected "now" for every test in this file.
final _fixedNow = DateTime(2026, 4, 10, 14, 35); // 14:35

// The day pre-selected in the entry form (override of selectedDateProvider).
final _selectedDay = DateOnly.normalize(_fixedNow);

/// The database instance created by the scope's override (set on first
/// watch), so tests can assert what was actually STORED.
CycleDatabase? _db;

ProviderScope _scope({Future<void> Function(CycleDatabase db)? seed}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async {
        final db = CycleDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        );
        _db = db;
        ref.onDispose(db.close);
        // Seeding inside the database future guarantees the form (which
        // reads only through databaseProvider.future) sees the seeded day.
        await seed?.call(db);
        return db;
      }),
      nowProvider.overrideWith((ref) => _fixedNow),
      selectedDateProvider.overrideWith((ref) => _selectedDay),
      localeProvider.overrideWith((ref) => const Locale('de')),
    ],
    child: const CycleApp(),
  );
}

void main() {
  /// Enlarges the test surface: the form is tall, and the day tiles plus the
  /// save button sit BELOW the default 800x600 test viewport — with the
  /// lazy ListView they are not even built there, so finders miss them.
  void tallSurface(WidgetTester tester, {double height = 2400}) {
    tester.view.physicalSize = Size(800, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a fresh day prefills the form with the CURRENT time',
      (WidgetTester tester) async {
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    expect(find.text('Gemessen um'), findsOneWidget,
        reason: 'the time-of-measurement row is visible on the form');
    expect(find.text('14:35'), findsOneWidget,
        reason: 'the picker button shows the injected current time');
    expect(find.text('06:47'), findsNothing,
        reason: 'no time was stored yet — only the prefill is shown');
  });

  testWidgets('a stored time stays on re-open for editing (no re-prefill)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _selectedDay,
        measuredAtMinutes: 407, // 06:47 — measured in the early morning
      ));
    }));
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);
    // The injected "now" (14:35) must NOT overwrite the stored morning time.
    expect(find.text('14:35'), findsNothing);
  });

  testWidgets('clearing the time is possible and stores null',
      (WidgetTester tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _selectedDay,
        measuredAtMinutes: 407,
      ));
    }));
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);

    // The clear affordance is the trailing close button of the time row.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('06:47'), findsNothing);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stored = (await _db!.entriesDao.entryFor(1, _selectedDay))!;
    expect(stored.measuredAtMinutes, isNull,
        reason: 'a day without time entry is legal; nothing is invented');
  });

  testWidgets('the day tile shows the stored time',
      (WidgetTester tester) async {
    // The time lives on a DIFFERENT day than the selected one, so the only
    // possible source of the string is the tile, not the form.
    tallSurface(tester);
    await tester.pumpWidget(_scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 1, 5),
        measuredAtMinutes: 407,
      ));
    }));
    await tester.pumpAndSettle();

    // The cycle-group tiles start collapsed; open the group first.
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget,
        reason: 'the measured time appears on the day tile');
  });
}
