// Widget tests of the Tagebuch save path under write failures: the day
// save (entry upsert + the two mark writes) is one all-or-nothing
// transaction, a failure surfaces through the localized failure SnackBar
// (never as an unhandled zone error), and an unarmed save keeps the
// established success behavior (day stored, success SnackBar).
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/faulty_db.dart';
import 'support/finders.dart';

final _harness = DiaryHarness(now: DateTime(2026, 9, 21, 10, 30));

void main() {
  /// German device over a fault-injectable in-memory database, a
  /// temperature already entered in the form.
  Future<FaultyCycleDatabase> pumpDiaryForm(
    WidgetTester tester, {
    required FaultyCycleDatabase faulty,
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
    final faulty = await pumpDiaryForm(tester, faulty: FaultyCycleDatabase());
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
    final faulty = await pumpDiaryForm(tester, faulty: FaultyCycleDatabase());
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

  testWidgets('an unarmed save stores the day and reports via the success '
      'SnackBar', (WidgetTester tester) async {
    await pumpDiaryForm(tester, faulty: FaultyCycleDatabase());

    await save(tester);

    final (:db, :date) = await savedDayOf(tester);
    expect(
      await db.entriesDao.entryFor(date),
      isNotNull,
      reason: 'the successful save stores the day',
    );
    expect(
      find.text('Gespeichert.'),
      findsOneWidget,
      reason: 'the success message is shown unchanged',
    );
    expect(tester.takeException(), isNull);
  });
}
