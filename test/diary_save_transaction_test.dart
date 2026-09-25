// Widget tests of the Tagebuch save path under write failures: the day
// save (entry upsert + the two mark writes) is one all-or-nothing
// transaction, a failure surfaces through the localized failure SnackBar
// (never as an unhandled zone error), and an unarmed save keeps the
// established success behavior (entry AND marks stored, success SnackBar).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/finders.dart';

/// Fault injection for the save flow: the real in-memory database whose
/// mark writes can be armed to fail AFTER the harness was pumped — the
/// test flips the flag at exactly the point the fault should occur.
class _FaultyDatabase extends CycleDatabase {
  _FaultyDatabase(super.executor);

  bool failMarkWrites = false;

  late final _FaultyMarksDao _faultyMarksDao = _FaultyMarksDao(this);

  @override
  MarksDao get marksDao => _faultyMarksDao;
}

class _FaultyMarksDao extends MarksDao {
  _FaultyMarksDao(this._faulty) : super(_faulty);

  final _FaultyDatabase _faulty;

  @override
  Future<UserMark> addMark(
    DateTime date,
    String markType, {
    String author = 'user',
  }) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.addMark(date, markType, author: author);
  }

  @override
  Future<int> deleteMark(DateTime date, String markType) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.deleteMark(date, markType);
  }
}

_FaultyDatabase _faultyDatabase() {
  return _FaultyDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}

final _harness = DiaryHarness(now: DateTime(2026, 9, 21, 10, 30));

final _cycleStartSwitch = find.byKey(const ValueKey('diaryCycleStartSwitch'));

void main() {
  /// German device over a (possibly faulty-subclassed) in-memory database,
  /// a temperature already entered in the form.
  Future<_FaultyDatabase> pumpDiaryForm(
    WidgetTester tester, {
    required _FaultyDatabase faulty,
  }) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope(builder: () => faulty));
    await tester.pumpAndSettle();

    await tester.enterText(diaryTemperatureField(), '36.5');
    await tester.pumpAndSettle();
    return faulty;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();
  }

  testWidgets('a failing mark write surfaces the failure message — never the '
      'success one, and nothing leaks as an unhandled error', (
    WidgetTester tester,
  ) async {
    final faulty = await pumpDiaryForm(tester, faulty: _faultyDatabase());
    faulty.failMarkWrites = true;

    await save(tester);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the save flow must catch its own failures — nothing may '
          'leak into the zone as an unhandled error',
    );
    expect(
      find.textContaining('Speichern fehlgeschlagen'),
      findsOneWidget,
      reason:
          'the failed save is reported via the localized failure '
          'SnackBar (the same posture as the delete-data and import '
          'flows: nothing was changed)',
    );
    expect(
      find.text('Gespeichert.'),
      findsNothing,
      reason: 'a failed save must not show the success message',
    );
  });

  testWidgets('a failure on the first mark write leaves NO entry row — the '
      'whole save rolled back, never a half-saved day', (
    WidgetTester tester,
  ) async {
    final faulty = await pumpDiaryForm(tester, faulty: _faultyDatabase());
    faulty.failMarkWrites = true;

    await save(tester);

    final (:db, :date) = await savedDayOf(tester);
    expect(
      await db.entriesDao.entryFor(date),
      isNull,
      reason:
          'the entry upsert sits inside the same transaction as the '
          'mark writes, so the failure rolls it back too — the day '
          'is stored either completely or not at all',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'the rollback surfaces through the failure SnackBar, not '
          'as an unhandled error',
    );
  });

  testWidgets('an unarmed save stores the entry AND the marks and reports '
      'via the success SnackBar', (WidgetTester tester) async {
    await pumpDiaryForm(tester, faulty: _faultyDatabase());

    // The cycle-start switch on: the save mirrors it into the
    // authoritative cycleStart mark.
    await tester.ensureVisible(_cycleStartSwitch);
    await tester.pumpAndSettle();
    await tester.tap(_cycleStartSwitch);
    await tester.pumpAndSettle();

    await save(tester);

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'the successful save stores the day');
    expect(row!.bbtC, 36.5, reason: 'the entered temperature is stored');
    expect(
      (await db.marksDao.marksForDay(date)).map((m) => m.markType),
      contains('cycleStart'),
      reason: 'the cycle-start switch writes its mark through the save',
    );
    expect(
      find.text('Gespeichert.'),
      findsOneWidget,
      reason: 'the success message is shown unchanged',
    );
    expect(tester.takeException(), isNull);
  });
}
