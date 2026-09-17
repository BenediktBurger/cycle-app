// Muttermund (cervix) per-day fields: position + opening round trip,
// storage vocabulary, and the export/import document boundary.
//
// Patterns and harnesses match test/db/cycle_database_test.dart: pure Dart
// against NativeDatabase.memory(), one list per namespace.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('Muttermund storage & domain round trip', () {
    test('every position and opening value round-trips the drift layer',
        () async {
      for (var i = 0; i < CervixPosition.values.length; i++) {
        final position = CervixPosition.values[i];
        final opening = CervixOpening.values[
            i % CervixOpening.values.length];
        final day = DateTime(2026, 8, 1 + i);
        final stored = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
          DailyEntry(
            date: day,
            cervixPosition: position,
            cervixOpening: opening,
          ),
        ));
        expect(stored.cervixPosition, position.name,
            reason: '${position.name} must be stored as its TEXT token');
        expect(stored.cervixOpening, opening.name,
            reason: '${opening.name} must be stored as its TEXT token');
        final mapped = dailyEntryFromDrift(stored);
        expect(mapped.cervixPosition, position,
            reason: '${position.name} must map back to the enum member');
        expect(mapped.cervixOpening, opening);
      }
    });

    test('a day without a Muttermund observation reads null for both fields',
        () async {
      final stored = await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 8, 20)),
      );
      expect(stored.cervixPosition, isNull);
      expect(stored.cervixOpening, isNull);
      final mapped = dailyEntryFromDrift(stored);
      expect(mapped.cervixPosition, isNull);
      expect(mapped.cervixOpening, isNull);
    });

    test('position is engine-rejected outside its vocabulary', () async {
      // 'middle' is the OPENING token — a classic mix-up; the CHECK on
      // cervix_position must reject it.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, cervix_position) "
          "VALUES (1, 20000, 'middle')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, cervix_position) "
        "VALUES (1, 20001, 'veryHigh')",
      );
    });

    test('opening is engine-rejected outside its vocabulary', () async {
      // 'medium' is the POSITION token; cervix_opening says 'middle'.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, cervix_opening) "
          "VALUES (1, 20002, 'medium')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary token goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, cervix_opening) "
        "VALUES (1, 20003, 'middle')",
      );
    });

    test('full replace clears a previously stored observation (nulls written)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 8, 15),
        cervixPosition: CervixPosition.high,
        cervixOpening: CervixOpening.open,
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 8, 15)),
      );
      final row = (await db.entriesDao.entryFor(1, DateTime(2026, 8, 15)))!;
      expect(row.cervixPosition, isNull);
      expect(row.cervixOpening, isNull);
    });
  });

  group('Muttermund fields at the export document boundary', () {
    test('export carries the stored tokens and a v4 document round-trips them',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 4, 2),
        cervixPosition: CervixPosition.veryHigh,
        cervixOpening: CervixOpening.open,
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 4, 3)),
      );

      final json = await exportDatabaseToJson(db);
      expect(json, contains('"schema_version": 4'),
          reason: 'the additive fields extend the existing format; no bump');
      expect(json, contains('"cervix_position": "veryHigh"'));
      expect(json, contains('"cervix_opening": "open"'));
      expect(json, contains('"cervix_position": null'),
          reason: 'a day without an observation exports a null field');

      final target = CycleDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      final summary = await importJsonToDatabase(target, json);
      expect(summary.entriesInvalid, 0);
      expect(summary.entriesWritten, 2);
      expect(
        (await target.entriesDao.entryFor(1, DateTime(2026, 4, 2)))!
            .cervixPosition,
        'veryHigh',
      );
      expect(
        (await target.entriesDao.entryFor(1, DateTime(2026, 4, 2)))!
            .cervixOpening,
        'open',
      );
      expect(
        (await target.entriesDao.entryFor(1, DateTime(2026, 4, 3)))!
            .cervixPosition,
        isNull,
      );
    });

    test('out-of-vocabulary tokens collapse to null WITHOUT dropping the row',
        () async {
      // The writer principle shared with mucus: a corrupt token can never
      // kill the whole day, it only loses that one field.
      const doc = '{"schema_version": 4, '
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

      final first = (await db.entriesDao.entryFor(1, DateTime(2026, 5, 1)))!;
      expect(first.cervixPosition, isNull);
      expect(first.cervixOpening, isNull,
          reason: 'non-string/opening tokens are not data');
      final second = (await db.entriesDao.entryFor(1, DateTime(2026, 5, 2)))!;
      expect(second.cervixPosition, 'low');
      expect(second.cervixOpening, isNull);
    });
  });
}
