// DB-layer tests of EntriesDao.latestTemperatureBefore: the diary's
// "suggestion" source query — the newest earlier day that carries a
// temperature. Pure Dart against NativeDatabase.memory(), like
// cycle_database_test.dart.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/db/cycle_database.dart';

void main() {
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<void> seedTemperature(DateTime day, double bbtC) {
    return db.entriesDao.upsertDaily(DailyEntry(date: day, bbtC: bbtC));
  }

  group('EntriesDao.latestTemperatureBefore', () {
    test('returns the newest earlier day that carries a temperature', () async {
      await seedTemperature(DateTime(2026, 3, 1), 36.2);
      await seedTemperature(DateTime(2026, 3, 2), 36.5);
      // A later row without a temperature must not shadow day -1's value,
      // but day -1 (the newest WITH one) must win over day -2.
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 3)));

      final row = await db.entriesDao.latestTemperatureBefore(
        DateTime(2026, 3, 4),
      );
      expect(row!.date, DateTime.utc(2026, 3, 2));
      expect(row.bbtC, 36.5);
    });

    test('the selected day itself is excluded', () async {
      await seedTemperature(DateTime(2026, 3, 2), 36.4);
      await seedTemperature(DateTime(2026, 3, 3), 36.8);

      final row = await db.entriesDao.latestTemperatureBefore(
        DateTime(2026, 3, 3),
      );
      expect(row!.date, DateTime.utc(2026, 3, 2));
      expect(row.bbtC, 36.4);
    });

    test('null on an empty database', () async {
      expect(
        await db.entriesDao.latestTemperatureBefore(DateTime(2026, 3, 3)),
        isNull,
      );
    });

    test('null when every earlier day is temperature-less', () async {
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 1)));
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 2)));
      expect(
        await db.entriesDao.latestTemperatureBefore(DateTime(2026, 3, 3)),
        isNull,
      );
    });

    test(
      'null when temperatures exist only on or after the selected day',
      () async {
        await seedTemperature(DateTime(2026, 3, 3), 36.5);
        await seedTemperature(DateTime(2026, 3, 4), 36.7);
        expect(
          await db.entriesDao.latestTemperatureBefore(DateTime(2026, 3, 3)),
          isNull,
        );
      },
    );

    test('skips over gap days back to the last measured day', () async {
      await seedTemperature(DateTime(2026, 2, 26), 36.1);
      // Days 27, 28, 1, 2 untracked — the query must not stop at the gap.
      await seedTemperature(DateTime(2026, 3, 2), 36.6);

      final row = await db.entriesDao.latestTemperatureBefore(
        DateTime(2026, 3, 3),
      );
      expect(row!.date, DateTime.utc(2026, 3, 2));
      expect(row.bbtC, 36.6);
    });

    test('the argument is normalized to its calendar day', () async {
      await seedTemperature(DateTime(2026, 3, 2), 36.4);
      // Same day, evening time-of-day, non-UTC representation: must behave
      // exactly like the midnight query.
      final row = await db.entriesDao.latestTemperatureBefore(
        DateTime(2026, 3, 3, 17, 30),
      );
      expect(DateOnly.sameDay(row!.date, DateTime(2026, 3, 2)), isTrue);
    });
  });
}
