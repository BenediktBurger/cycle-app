// Shared harness for the widget tests that pump the ZyklusScreen list
// (chart, non-modal day-options panel) directly and write
// through the REAL MarksDao so every write surfaces in the streams that
// re-render the panel and the chart. Used by test/cycle_mark_sheet_test.dart
// and test/cycle_day_panel_test.dart (the same harness both kept two copies
// of before the cleanup), plus the scenario constants both files name.
//
// Locale pinned to en — the panel's labels are asserted in English in the
// callers.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database.dart';
import 'fixtures.dart';

/// The evaluation scenario's September, as a day (the fixtures' prose names
/// the scenario days — 9/6 baseline-window Monday .. 9/16 the SUZ day — so
/// the assertions can read like the day prose).
DateTime scenarioDay(int day) => DateTime.utc(2026, 9, day);

/// The evaluation scenario's data: entries fresh per test use
/// ([evaluationScenarioEntries]), the two user marks as named scenario
/// roles, seeded through the DAO before the UI builds.
final List<DailyEntry> scenarioEntries = evaluationScenarioEntries();

final CycleMark scenarioPeakMark = evaluationScenarioMarks()[0];
final CycleMark scenarioFirstHigherMark = evaluationScenarioMarks()[1];

/// The cycle screen's list (chart, non-modal day-options panel)
/// pumped over an in-memory database whose real MarksDao
/// carries every seeded and test-written mark.
///
/// [seedMarks] are written through `marksDao.addMark` inside the database
/// future; [selectedDate] (default: the scenario's first day) and
/// [initialTab] pin the providers. Returns `(database, container)` — the
/// created database for STORED-state assertions and the container for
/// explicit provider reads (e.g. after a navigation write). Callers that
/// only need one destructure the other as `_`.
///
/// [builder] passes a subclassed database through (fault injection —
/// the same seam the appScope and DiaryHarness tests use); the default
/// stays the plain in-memory instance.
///
/// [marksStreamFactory] replaces the real marks stream: invoked once per
/// provider (re-)subscription, so a stream-error retry test can hand out a
/// failing stream on the first attempt and a valid one afterwards.
Future<(CycleDatabase, ProviderContainer)> pumpCycleList(
  WidgetTester tester, {
  required List<DailyEntry> entries,
  List<CycleMark> seedMarks = const [],
  DateTime? selectedDate,
  int initialTab = 0,
  CycleDatabase Function()? builder,
  Stream<List<CycleMark>> Function()? marksStreamFactory,
}) async {
  final initialSelected = DateOnly.normalize(selectedDate ?? scenarioDay(1));
  CycleDatabase? db;
  final container = ProviderContainer(
    overrides: [
      inMemoryDatabase(
        seed: (db) async {
          for (final mark in seedMarks) {
            await db.marksDao.addMark(
              mark.date,
              mark.type,
              author: mark.author,
            );
          }
        },
        builder: builder,
        onCreated: (created) => db = created,
      ),
      dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      if (marksStreamFactory != null)
        marksProvider.overrideWith((ref) => marksStreamFactory()),
      selectedDateProvider.overrideWith((ref) => initialSelected),
      tabIndexProvider.overrideWith((ref) => initialTab),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: ZyklusScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // A test that overrides BOTH stream providers never touches the real
  // database through them — materialize the instance here so callers that
  // destructure it always get it.
  await container.read(databaseProvider.future);
  return (db!, container);
}

/// Taps the chart day at [index] via the marks row cell under that day.
///
/// `warnIfMissed: false` because the tap point may fall on the cell's
/// Center-with-null-child slot (no number rendered), which does not absorb
/// hits itself — the enclosing InkWell's pointer listener still receives it.
Future<void> tapCycleDay(WidgetTester tester, int index) async {
  await tester.tap(
    find.byKey(ValueKey('marksCell-$index')),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

/// The stored mark types for one calendar day, from the REAL database.
Future<List<String>> storedMarkTypes(CycleDatabase db, DateTime day) async =>
    (await db.marksDao.marksForDay(day)).map((m) => m.markType).toList();
