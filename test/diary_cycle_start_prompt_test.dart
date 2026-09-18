// Widget tests for the cycle-start suggestion on the Tagebuch screen: after
// saving a day whose bleeding SUGGESTS a cycle start (menstruation-level
// bleeding on a not-interrupted day that does not continue the previous
// day's menstruation-level bleeding — see isSuggestedCycleStart in
// lib/domain/cycle_grouping.dart), the app asks "Neuen Zyklus beginnen?" /
// "Start new cycle?" and, on confirmation, places the authoritative
// cycleStart mark through the MarksDao. Bleeding never creates a boundary
// by itself — the user still places the mark (ADR-0008).
//
// Covered: the prompt appears only for a SUGGESTED menstruation-level day
// (level >= 2), confirming persists the user-authored mark, dismissing
// persists nothing, a level-1 day (spotting) prompts nothing, a
// menstruation-level day that continues the previous day's bleeding
// (mid-flow) prompts nothing, and the prompt is keyed PURELY to bleeding
// continuity: the ignoreTemperature mark does NOT suppress it any more
// (owner decision 2026-09-18 — the mark is temperature-evaluation-scoped;
// a marked bleeding day still prompts and still places the cycleStart).
//
// The database is an in-memory override, same pattern as
// test/diary_measured_time_test.dart; the German locale is pinned so the
// dialog wording assertions stay deterministic.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Selected calendar day of the entry form.
final _day = DateTime.utc(2026, 9, 15);
final _previousDay = DateTime.utc(2026, 9, 14);

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
      nowProvider.overrideWith((ref) => () => DateTime(2026, 9, 15, 10, 30)),
      selectedDateProvider.overrideWith((ref) => _day),
      localeProvider.overrideWith((ref) => const Locale('de')),
    ],
    child: const CycleApp(),
  );
}

void main() {
  /// Enlarges the test surface: the form is tall, and the save button sits
  /// BELOW the default 800x600 test viewport — with the lazy ListView it is
  /// not even built there, so finders would miss it.
  void tallSurface(WidgetTester tester, {double height = 2400}) {
    tester.view.physicalSize = Size(800, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Selects the bleeding chip [label] (German: the pinned locale) and
  /// saves the day. The labels used here are unique on the form — the
  /// cervix rows reuse "mittel" for their own chips.
  Future<void> saveWithBleeding(WidgetTester tester, String chipLabel) async {
    await tester.tap(find.widgetWithText(ChoiceChip, chipLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  /// The stored mark types for the selected day, from the REAL database.
  Future<List<String>> storedMarkTypes(DateTime day) async =>
      (await _db!.marksDao.marksForDay(day)).map((m) => m.markType).toList();

  testWidgets(
      'a suggested menstruation-level day prompts for the cycle start; '
      'confirming places the cycleStart mark', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    // First recorded day, bleeding "leicht" (level 2): already
    // menstruation-level, so the suggestion predicate flags it as a cycle
    // start — the prompt does not wait for the central levels.
    await saveWithBleeding(tester, 'leicht');

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'a suggested menstruation-level day asks for the cycle '
            'start instead of placing the mark silently');
    expect(find.text('Neuen Zyklus beginnen?'), findsOneWidget,
        reason: 'the prompt names the suggestion in the pinned locale');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zyklusbeginn setzen')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'confirming closes the prompt');
    final marks = await _db!.marksDao.marksForDay(_day);
    expect(marks.map((m) => m.markType), contains(CycleMarkTypes.cycleStart),
        reason: 'the confirmed suggestion places the authoritative '
            'cycle-boundary mark through the MarksDao');
    final mark =
        marks.singleWhere((m) => m.markType == CycleMarkTypes.cycleStart);
    expect(mark.author, 'user',
        reason: 'the confirmed placement is user-authored');
  });

  testWidgets('dismissing the prompt places no mark', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    await saveWithBleeding(tester, 'stark');

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Nicht jetzt')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'dismissing closes the prompt');
    expect(await storedMarkTypes(_day), isEmpty,
        reason: 'dismissing must not place the mark — bleeding only '
            'suggests, the user decides');
  });

  testWidgets('a spotting day (level 1) shows no prompt', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    await saveWithBleeding(tester, 'Schmierblutung');

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'only menstruation-level bleeding (level >= 2) suggests a '
            'cycle start — spotting does not');
    expect(await storedMarkTypes(_day), isEmpty);
  });

  testWidgets(
      'a menstruation-level day continuing the previous day\'s bleeding '
      '(mid-flow) shows no prompt', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope(seed: (db) async {
      // The previous calendar day already carries an uninterrupted
      // menstruation-level bleeding day: the saved day is mid-flow.
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _previousDay,
        bleeding: Bleeding.medium,
      ));
    }));
    await tester.pumpAndSettle();

    await saveWithBleeding(tester, 'stark');

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'fresh menstruation starts after a break or on the first '
            'day — a continuous menstruation is mid-flow, not a new start');
    expect(await storedMarkTypes(_day), isEmpty);
  });

  testWidgets(
      'an ignoreTemperature mark on the day does NOT suppress the prompt '
      '(a marked bleeding day still suggests)', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope(seed: (db) async {
      // The day already carries the temperature-ignore mark: that mark is
      // scoped to the temperature evaluation and must not swallow the
      // cycle-start suggestion — the suppression is keyed purely to
      // bleeding continuity.
      await db.marksDao.addMark(
        _day,
        CycleMarkTypes.ignoreTemperature,
        author: 'user',
      );
    }));
    await tester.pumpAndSettle();

    await saveWithBleeding(tester, 'leicht');

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'the ignoreTemperature mark no longer suppresses the '
            'suggestion — the marked bleeding day still asks');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zyklusbeginn setzen')));
    await tester.pumpAndSettle();

    final marks = await _db!.marksDao.marksForDay(_day);
    expect(
        marks.map((m) => m.markType),
        unorderedEquals([
          CycleMarkTypes.ignoreTemperature,
          CycleMarkTypes.cycleStart,
        ]),
        reason: 'confirming places the cycleStart mark; the pre-existing '
            'ignoreTemperature mark stays untouched (auto-set only, never '
            'auto-removed)');
    final start =
        marks.singleWhere((m) => m.markType == CycleMarkTypes.cycleStart);
    expect(start.author, 'user',
        reason: 'the confirmed placement is user-authored even on a '
            'marked day');
  });
}
