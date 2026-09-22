// DB-integration canary for the real-world example-cycle.json fixture
// (schema_version 6): the actual export file a user produced imports through
// the EXISTING importJsonToDatabase (lib/db/export_adapter.dart) into a
// NativeDatabase.memory(), and re-importing the same file is idempotent.
//
// Deliberately lean structural sanity — light counts and the pinned spot
// checks only; the comprehensive behavior tests live in the export/import
// suites. This canary's job is to fail loudly when the export/import
// contract breaks for this real-world shape.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/export_import.dart' show formatIsoDay;
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  final fixtureRaw = File(
    'test/fixtures/example-cycle.json',
  ).readAsStringSync();

  /// All stored rows mapped to the domain object, ordered ascending by date
  /// (DailyEntry == compares every entry field + the day, no timestamps —
  /// created_at/updated_at bookkeeping is excluded from equality this way).
  Future<List<DailyEntry>> storedEntries() async {
    final rows = await db.entriesDao.allEntries();
    final list = rows.map(dailyEntryFromDrift).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// The stored day row for an ISO date, as the domain object.
  Future<DailyEntry> dayRow(String iso) async {
    final rows = await db.entriesDao.allEntries();
    return rows
        .map(dailyEntryFromDrift)
        .singleWhere((e) => formatIsoDay(e.date) == iso);
  }

  group('example cycle export through importJsonToDatabase', () {
    test('first import stores the 27 fixture days and the 7 marks', () async {
      final summary = await importJsonToDatabase(db, fixtureRaw);

      // Full accounting: nothing invalid, nothing overwritten on the
      // empty database.
      expect(summary.entriesNew, 27);
      expect(summary.entriesOverwritten, 0);
      expect(summary.entriesInvalid, 0);
      expect(summary.marksNew, 7);
      expect(summary.marksInvalid, 0);

      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(27));

      // The pinned spot-check day: temperature, structured mucus sign and
      // the sex timings mask survive the document → storage round trip.
      final pinnedDay = await dayRow('2026-08-25');
      expect(pinnedDay.bbtC, 36.8);
      expect(pinnedDay.mucusSign, MucusSign.t);
      expect(
        pinnedDay.sexTimings,
        SexTiming.middle.bit,
        reason: 'mask 2 is the middle bit of the sex timings vocabulary',
      );

      // The pinned marks exist with their pinned authors.
      final cycleStartDay = (await db.marksDao.marksForDay(
        DateTime(2026, 9, 16),
      )).where((m) => m.markType == 'cycleStart');
      expect(cycleStartDay, hasLength(1));
      expect(cycleStartDay.single.author, 'import');

      final mucusPeakDay = (await db.marksDao.marksForDay(
        DateTime(2026, 9, 1),
      )).where((m) => m.markType == 'mucusPeakDay');
      expect(mucusPeakDay, hasLength(1));
      expect(mucusPeakDay.single.author, 'user');
    });

    test(
      'full-row equality of every stored day across a double import',
      () async {
        await importJsonToDatabase(db, fixtureRaw);
        final afterFirst = await storedEntries();
        expect(afterFirst, isNotEmpty, reason: 'guard: the import stored data');

        final summary2 = await importJsonToDatabase(db, fixtureRaw);

        // Idempotence in the counters: nothing new, everything merged.
        expect(summary2.entriesNew, 0);
        expect(summary2.entriesOverwritten, 27);
        expect(summary2.entriesInvalid, 0);
        expect(summary2.marksNew, 0);
        expect(
          summary2.marksSkipped,
          7,
          reason: 'all document marks are skip-idempotent on re-import',
        );

        final rows = await db.entriesDao.allEntries();
        expect(rows, hasLength(27), reason: 'no duplicates on re-import');

        final afterSecond = await storedEntries();
        // Full-row equality for EVERY day, list-ordered.
        expect(afterSecond, afterFirst);
      },
    );

    test('the gap day 2026-09-11 stays absent from the stored dates', () async {
      await importJsonToDatabase(db, fixtureRaw);
      final rows = await db.entriesDao.allEntries();

      final dates = rows.map((r) => formatIsoDay(r.date)).toSet();
      expect(
        dates.contains('2026-09-11'),
        isFalse,
        reason:
            'the fixture carries no row for the gap day and the '
            'import must not invent one',
      );
      expect(dates, hasLength(27));
    });
  });
}
