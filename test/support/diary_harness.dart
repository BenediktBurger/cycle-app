// Shared diary harnesses: the two copy-paste shapes of the Tagebuch
// widget tests.
//
//  (a) the selector tests (bleeding/cervix/pain/firmness): the Tagebuch
//      screen over an in-memory database with the locale pinned, plus the
//      saved-day readback through the same database provider the form
//      writes with;
//  (b) the pinned-clock tests (measured time, day navigation, cycle-start
//      switch, disturbance auto-mark): an in-memory (optionally seeded)
//      database, the clock pinned through nowProvider, the form's day pinned
//      through selectedDateProvider, the German locale pinned — plus the
//      wide test surface (the form's save button sits below the default
//      800x600 viewport) and the bleeding-chip save + mark readback helpers.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/diary_track.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database.dart';
import 'finders.dart';
import 'viewport.dart';

/// Entry-form selector scope: the Tagebuch screen over an in-memory
/// database, language pinned to [locale]. An entry-form section pinned off
/// in the What-to-track defaults (cervix) can be re-shown for the tests that
/// exercise it.
ProviderScope diarySelectorScope(Locale locale, {DiaryTrack? diaryTrack}) =>
    diaryScreenScope(locale: locale, diaryTrack: diaryTrack);

/// Reads the saved day back through the database provider — the same
/// instance the entry form writes through, not a second connection.
Future<({CycleDatabase db, DateTime date})> savedDayOf(
  WidgetTester tester,
) async {
  final context = tester.element(find.byType(TagebuchScreen));
  final container = ProviderScope.containerOf(context);
  final db = await container.read(databaseProvider.future);
  return (db: db, date: container.read(selectedDateProvider));
}

/// Pinned-clock harness for the Tagebuch entry-form tests: seeds, clock,
/// selected day and locale are pinned so the (German) form assertions stay
/// deterministic and time-independent.
class DiaryHarness {
  /// The injected "now" for every test (wall-clock independence).
  final DateTime now;

  /// The day pre-selected in the entry form.
  final DateTime selectedDay;

  /// The database instance created by the scope's override (set on first
  /// watch), so tests can assert what was actually STORED.
  CycleDatabase? db;

  DiaryHarness({required this.now, DateTime? selectedDay})
    : selectedDay = selectedDay ?? DateOnly.normalize(now);

  /// The screen scope with the pinned overrides; [seed] runs inside the
  /// database future (the form, reading through databaseProvider.future,
  /// sees the seeded day); a per-call [selectedDay] overrides the harness
  /// default, a per-call [now] overrides the harness clock (for files whose
  /// sections pin different dates on one harness).
  /// [builder] passes a subclassed database through (fault injection —
  /// the same seam delete-data tests use); the default stays the plain
  /// in-memory instance. [fullApp] pumps the whole shell for tests that
  /// exercise lifecycle or navigation wiring.
  ProviderScope scope({
    Future<void> Function(CycleDatabase db)? seed,
    DateTime? selectedDay,
    DiaryTrack? diaryTrack,
    CycleDatabase Function()? builder,
    DateTime? now,
    Locale locale = const Locale('de'),
    bool fullApp = false,
  }) => fullApp
      ? appScope(
          seed: seed,
          builder: builder,
          onCreated: (db) => this.db = db,
          now: () => now ?? this.now,
          selectedDay: selectedDay ?? this.selectedDay,
          diaryTrack: diaryTrack,
          locale: locale,
        )
      : diaryScreenScope(
          seed: seed,
          builder: builder,
          onCreated: (db) => this.db = db,
          now: () => now ?? this.now,
          selectedDay: selectedDay ?? this.selectedDay,
          diaryTrack: diaryTrack,
          locale: locale,
        );

  /// Enlarges the test surface: the form is tall, and the day tiles plus the
  /// save button sit BELOW the default 800x600 test viewport — with the
  /// lazy ListView they are not even built there, so finders miss them.
  /// The surface mechanics live once in support/viewport.dart (the diary
  /// wide/tall surface is the same helper the cycle-list tests use).
  void tallSurface(WidgetTester tester, {double height = 2400}) =>
      useTallSurface(tester, height: height);

  /// Selects the bleeding chip [bleeding] (by key, not by label) and saves
  /// the day through the form's bottom save button.
  Future<void> saveWithBleeding(WidgetTester tester, Bleeding bleeding) async {
    await tester.tap(diaryChip('bleeding', bleeding.name));
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();
  }

  /// The stored mark types for [day], from the REAL database.
  Future<List<String>> storedMarkTypes(DateTime day) async =>
      (await db!.marksDao.marksForDay(day)).map((m) => m.markType).toList();
}
