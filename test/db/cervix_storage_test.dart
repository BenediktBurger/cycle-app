// Cervix fields (position, opening, firmness), sex timings and their
// storage, plus the export/import document boundary — the whole cervix
// storage family in one file (the former cervix_fields_test.dart and
// cervix_firmness_sex_timings_test.dart; the mucus 'a' (Ausfluss)
// vocabulary group moved to the mucus coverage in cycle_database_test.dart).
//
// Patterns and harnesses match test/db/cycle_database_test.dart: pure Dart
// against NativeDatabase.memory(), one group per vocabulary.
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('Muttermund storage & domain round trip', () {
    test(
      'every position and opening value round-trips the drift layer',
      () async {
        for (var i = 0; i < CervixPosition.values.length; i++) {
          final position = CervixPosition.values[i];
          final opening = CervixOpening.values[i % CervixOpening.values.length];
          final day = DateTime(2026, 8, 1 + i);
          final stored = await db.entriesDao.upsertByDate(
            dailyEntryToCompanion(
              DailyEntry(
                date: day,
                cervixPosition: position,
                cervixOpening: opening,
              ),
            ),
          );
          expect(
            stored.cervixPosition,
            position.name,
            reason: '${position.name} must be stored as its TEXT token',
          );
          expect(
            stored.cervixOpening,
            opening.name,
            reason: '${opening.name} must be stored as its TEXT token',
          );
          final mapped = dailyEntryFromDrift(stored);
          expect(
            mapped.cervixPosition,
            position,
            reason: '${position.name} must map back to the enum member',
          );
          expect(mapped.cervixOpening, opening);
        }
      },
    );

    test(
      'a day without a Muttermund observation reads null for both fields',
      () async {
        final stored = await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 8, 20)),
        );
        expect(stored.cervixPosition, isNull);
        expect(stored.cervixOpening, isNull);
        final mapped = dailyEntryFromDrift(stored);
        expect(mapped.cervixPosition, isNull);
        expect(mapped.cervixOpening, isNull);
      },
    );

    test('position is engine-rejected outside its vocabulary', () async {
      // 'middle' is the OPENING token — a classic mix-up; the CHECK on
      // cervix_position must reject it.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, cervix_position) "
          "VALUES (20000, 'middle')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, cervix_position) "
        "VALUES (20001, 'veryHigh')",
      );
    });

    test('opening is engine-rejected outside its vocabulary', () async {
      // 'medium' is the POSITION token; cervix_opening says 'middle'.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, cervix_opening) "
          "VALUES (20002, 'medium')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, cervix_opening) "
        "VALUES (20003, 'middle')",
      );
    });

    test(
      'full replace clears a previously stored observation (nulls written)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 8, 15),
            cervixPosition: CervixPosition.high,
            cervixOpening: CervixOpening.open,
          ),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 8, 15)),
        );
        final row = (await db.entriesDao.entryFor(DateTime(2026, 8, 15)))!;
        expect(row.cervixPosition, isNull);
        expect(row.cervixOpening, isNull);
      },
    );
  });

  group('Muttermund fields at the export document boundary', () {
    test('export carries the stored tokens and a v4 document round-trips '
        'them to schema_version 6', () async {
      await db.entriesDao.upsertDaily(
        DailyEntry(
          date: DateTime(2026, 4, 2),
          cervixPosition: CervixPosition.veryHigh,
          cervixOpening: CervixOpening.open,
        ),
      );
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 4, 3)));

      final json = await exportDatabaseToJson(db);
      expect(
        json,
        contains('"schema_version": 6'),
        reason:
            "v6 is the sparse-entry/profile-free release; the "
            "additive Muttermund fields still ride the entries",
      );
      expect(json, contains('"cervix_position": "veryHigh"'));
      expect(json, contains('"cervix_opening": "open"'));
      expect(
        json,
        isNot(contains('"cervix_position": null')),
        reason:
            'the sparse shape omits a day without an observation: '
            'the reader treats the missing key as no observation',
      );

      final target = CycleDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      final summary = await importJsonToDatabase(target, json);
      expect(summary.entriesInvalid, 0);
      expect(summary.entriesWritten, 2);
      expect(
        (await target.entriesDao.entryFor(
          DateTime(2026, 4, 2),
        ))!.cervixPosition,
        'veryHigh',
      );
      expect(
        (await target.entriesDao.entryFor(DateTime(2026, 4, 2)))!.cervixOpening,
        'open',
      );
      expect(
        (await target.entriesDao.entryFor(
          DateTime(2026, 4, 3),
        ))!.cervixPosition,
        isNull,
      );
    });

    test(
      'out-of-vocabulary tokens collapse to null WITHOUT dropping the row',
      () async {
        // The writer principle shared with mucus: a corrupt token can never
        // kill the whole day, it only loses that one field.
        const doc =
            '{"schema_version": 4, '
            '"exported_at": "2026-04-01T00:00:00Z", '
            '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
            '"entries": [{'
            '"profile_id": 1, "date": "2026-05-01", "bleeding": 2, '
            '"cervix_position": "dangling", "cervix_opening": 42}, '
            '{"profile_id": 1, "date": "2026-05-02", "bleeding": 2, '
            '"cervix_position": "low"}], '
            '"marks": []}';
        final summary = await importJsonToDatabase(db, doc);
        expect(summary.entriesInvalid, 0, reason: 'no row may be dropped here');
        expect(summary.entriesWritten, 2);

        final first = (await db.entriesDao.entryFor(DateTime(2026, 5, 1)))!;
        expect(first.cervixPosition, isNull);
        expect(
          first.cervixOpening,
          isNull,
          reason: 'non-string/opening tokens are not data',
        );
        final second = (await db.entriesDao.entryFor(DateTime(2026, 5, 2)))!;
        expect(second.cervixPosition, 'low');
        expect(second.cervixOpening, isNull);
      },
    );
  });

  group('cervix firmness storage & domain round trip', () {
    test(
      'every firmness value round-trips the drift layer as its TEXT token',
      () async {
        for (var i = 0; i < CervixFirmness.values.length; i++) {
          final firmness = CervixFirmness.values[i];
          final day = DateTime(2026, 8, 1 + i);
          final stored = await db.entriesDao.upsertByDate(
            dailyEntryToCompanion(
              DailyEntry(date: day, cervixFirmness: firmness),
            ),
          );
          expect(
            stored.cervixFirmness,
            firmness.name,
            reason: '${firmness.name} must be stored as its TEXT token',
          );
          final mapped = dailyEntryFromDrift(stored);
          expect(
            mapped.cervixFirmness,
            firmness,
            reason: '${firmness.name} must map back to the enum member',
          );
        }
      },
    );

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
          "INSERT INTO cycle_entries (date, cervix_firmness) "
          "VALUES (20000, 'middle')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, cervix_firmness) "
        "VALUES (20001, 'halfSoft')",
      );
    });

    test(
      'full replace clears a previously stored firmness (null written)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 8, 15),
            cervixFirmness: CervixFirmness.hard,
          ),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 8, 15)),
        );
        final row = (await db.entriesDao.entryFor(DateTime(2026, 8, 15)))!;
        expect(row.cervixFirmness, isNull);
      },
    );
  });

  group('sex timings storage & domain round trip', () {
    test(
      'every mask 0..7 round-trips the drift layer as the INTEGER mask',
      () async {
        for (var mask = 0; mask <= 7; mask++) {
          final day = DateTime(2026, 7, 1 + mask);
          final stored = await db.entriesDao.upsertByDate(
            dailyEntryToCompanion(DailyEntry(date: day, sexTimings: mask)),
          );
          expect(
            stored.sexTimings,
            mask,
            reason: 'mask $mask must survive storage verbatim',
          );
          expect(dailyEntryFromDrift(stored).sexTimings, mask);
        }
      },
    );

    test(
      'each SexTiming bit is representable alone (by bit, never by index)',
      () async {
        for (final timing in SexTiming.values) {
          final day = DateTime(2026, 7, 10 + timing.index);
          final stored = await db.entriesDao.upsertDaily(
            DailyEntry(date: day, sexTimings: timing.bit),
          );
          expect(
            stored.sexTimings,
            timing.bit,
            reason:
                '${timing.name} stores its bit (${timing.bit}), not its '
                'declaration index (${timing.index})',
          );
        }
      },
    );

    test('a fresh day defaults to 0 — no sex recorded', () async {
      await db
          .into(db.cycleEntries)
          .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 7, 20)));
      final row = await db.entriesDao.entryFor(DateTime(2026, 7, 20));
      expect(row!.sexTimings, 0);
      final raw = await db
          .customSelect('SELECT sex_timings FROM cycle_entries')
          .getSingle();
      expect(raw.data['sex_timings'], 0, reason: 'the column default is 0');
    });

    test('sex_timings is engine-rejected outside 0..7', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (date, sex_timings) '
          'VALUES (20000, 8)',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (date, sex_timings) '
          'VALUES (20002, -1)',
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-range mask goes through.
      await db.customStatement(
        'INSERT INTO cycle_entries (date, sex_timings) '
        'VALUES (20003, 7)',
      );
    });

    test(
      'full replace clears a previously stored mask (default 0 written)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 7, 15), sexTimings: 3),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 7, 15)),
        );
        final row = (await db.entriesDao.entryFor(DateTime(2026, 7, 15)))!;
        expect(row.sexTimings, 0);
      },
    );
  });
}
