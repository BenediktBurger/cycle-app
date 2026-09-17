// Cervix FIRMNESS + sex TIMINGS storage, and the mucus 'a' (Ausfluss)
// vocabulary admission.
//
// Patterns and harnesses match test/db/cervix_fields_test.dart: pure Dart
// against NativeDatabase.memory(), one group per vocabulary.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/mappers.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('cervix firmness storage & domain round trip', () {
    test('every firmness value round-trips the drift layer as its TEXT token',
        () async {
      for (var i = 0; i < CervixFirmness.values.length; i++) {
        final firmness = CervixFirmness.values[i];
        final day = DateTime(2026, 8, 1 + i);
        final stored = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
          DailyEntry(date: day, cervixFirmness: firmness),
        ));
        expect(stored.cervixFirmness, firmness.name,
            reason: '${firmness.name} must be stored as its TEXT token');
        final mapped = dailyEntryFromDrift(stored);
        expect(mapped.cervixFirmness, firmness,
            reason: '${firmness.name} must map back to the enum member');
      }
    });

    test('a day without a firmness observation reads null', () async {
      final stored = await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 8, 20)),
      );
      expect(stored.cervixFirmness, isNull);
      expect(dailyEntryFromDrift(stored).cervixFirmness, isNull);
    });

    test('firmness is engine-rejected outside its vocabulary', () async {
      // 'middle' is the OPENING token — a classic mix-up; the CHECK on
      // cervix_firmness must reject it.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, cervix_firmness) "
          "VALUES (1, 20000, 'middle')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, cervix_firmness) "
        "VALUES (1, 20001, 'halfSoft')",
      );
    });

    test('full replace clears a previously stored firmness (null written)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 8, 15),
        cervixFirmness: CervixFirmness.hard,
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 8, 15)),
      );
      final row = (await db.entriesDao.entryFor(1, DateTime(2026, 8, 15)))!;
      expect(row.cervixFirmness, isNull);
    });
  });

  group('sex timings storage & domain round trip', () {
    test('every mask 0..7 round-trips the drift layer as the INTEGER mask',
        () async {
      for (var mask = 0; mask <= 7; mask++) {
        final day = DateTime(2026, 7, 1 + mask);
        final stored = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
          DailyEntry(date: day, sexTimings: mask),
        ));
        expect(stored.sexTimings, mask,
            reason: 'mask $mask must survive storage verbatim');
        expect(dailyEntryFromDrift(stored).sexTimings, mask);
      }
    });

    test('each SexTiming bit is representable alone (by bit, never by index)',
        () async {
      for (final timing in SexTiming.values) {
        final day = DateTime(2026, 7, 10 + timing.index);
        final stored = await db.entriesDao.upsertDaily(
          DailyEntry(date: day, sexTimings: timing.bit),
        );
        expect(stored.sexTimings, timing.bit,
            reason: '${timing.name} stores its bit (${timing.bit}), not its '
                'declaration index (${timing.index})');
      }
    });

    test('a fresh day defaults to 0 — no sex recorded', () async {
      await db.into(db.cycleEntries).insert(
            CycleEntriesCompanion.insert(date: DateTime(2026, 7, 20)),
          );
      final row = await db.entriesDao.entryFor(1, DateTime(2026, 7, 20));
      expect(row!.sexTimings, 0);
      final raw = await db
          .customSelect('SELECT sex_timings FROM cycle_entries')
          .getSingle();
      expect(raw.data['sex_timings'], 0, reason: 'the column default is 0');
    });

    test('sex_timings is engine-rejected outside 0..7', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (profile_id, date, sex_timings) '
          'VALUES (1, 20000, 8)',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (profile_id, date, sex_timings) '
          'VALUES (1, 20002, -1)',
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-range mask goes through.
      await db.customStatement(
        'INSERT INTO cycle_entries (profile_id, date, sex_timings) '
        'VALUES (1, 20003, 7)',
      );
    });

    test('full replace clears a previously stored mask (default 0 written)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 7, 15),
        sexTimings: 3,
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 7, 15)),
      );
      final row = (await db.entriesDao.entryFor(1, DateTime(2026, 7, 15)))!;
      expect(row.sexTimings, 0);
    });
  });

  group('mucus sign A (Ausfluss) storage vocabulary', () {
    test("'a' is accepted by the engine and round-trips as its token",
        () async {
      // Raw SQL write (e.g. a future import path) proves the column's CHECK
      // admits the new token.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, mucus_sign) "
        "VALUES (1, 20000, 'a')",
      );
      final row =
          await db.entriesDao.entryFor(1, DateTime(2024, 10, 4)); // day 20000
      expect(row!.mucusSign, 'a');

      // The DAO write path stores the enum name, not a glyph.
      final stored = await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 8, 5),
        mucusSign: MucusSign.a,
      ));
      expect(stored.mucusSign, 'a', reason: 'TEXT token, not a glyph');
      expect(dailyEntryFromDrift(stored).mucusSign, MucusSign.a);
    });

    test('a quality token stays engine-rejected on an A sign', () async {
      // Quality remains exclusive to S — the CHECK below still encodes
      // mucus_sign = 's', so 'a' with a quality cannot be written.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, mucus_sign, "
          "mucus_quality) VALUES (1, 20000, 'a', 'w')",
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
