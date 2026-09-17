// DB-integration tests for the drip CSV import write path: the domain
// mapper output (dripCsvToExportJson, lib/domain/drip_import.dart) is fed
// through the EXISTING importJsonToDatabase (lib/db/export_adapter.dart) and
// the STORED rows are asserted — proving that no second db writer is needed
// and that re-importing the same CSV is idempotent.
//
// Pure Dart against NativeDatabase.memory() — no platform channels, no web
// (same pattern as test/db/cycle_database_test.dart).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/drip_import.dart';
import 'package:cycle_app/domain/export_import.dart' show formatIsoDay;
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/models.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  final fixtureRaw =
      File('test/fixtures/drip-export-sample.csv').readAsStringSync();

  /// All stored rows mapped to the domain object, ordered ascending by date
  /// (DailyEntry == compares every entry field + the day, no timestamps —
  /// created_at/updated_at bookkeeping is excluded from equality this way).
  Future<List<DailyEntry>> storedEntries() async {
    final rows = await db.entriesDao.allEntriesForAllProfiles();
    final list = rows.map(dailyEntryFromDrift).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// The stored day row for an ISO date, as the domain object.
  Future<DailyEntry> dayRow(String iso) async {
    final rows = await db.entriesDao.allEntriesForAllProfiles();
    return rows.map(dailyEntryFromDrift).singleWhere(
          (e) => formatIsoDay(e.date) == iso,
        );
  }

  group('drip csv through importJsonToDatabase', () {
    test('first import stores exactly the 27 mapped days under the main '
        'profile', () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      final summary = await importJsonToDatabase(db, mapping.json);

      // Full accounting: nothing invalid, nothing new beyond the new days.
      expect(summary.entriesInvalid, 0);
      expect(summary.entriesNew, 27);
      expect(summary.entriesOverwritten, 0);
      expect(summary.entriesWritten, 27);
      expect(summary.marksNew, 0);
      expect(summary.profilesToInsert, 0,
          reason: 'document profile 1 is the seeded main profile');

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(27),
          reason: '27 data rows, 46 blank calendar days skipped');
      expect(rows.every((r) => r.profileId == 1), isTrue,
          reason: 'drip has no multi-profile concept');

      // The seeded profile is still alone and unmodified.
      final profiles = await db.profilesDao.allProfiles();
      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'main');
      expect(profiles.single.id, 1);
    });

    test('exact stored field values for the pinned days', () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      await importJsonToDatabase(db, mapping.json);

      // 2026-07-15: mucus day — drip nfp value 2 wins over the 2+1 parts →
      // sign f, no quality (the amended number-level mapping), firmness
      // index 2 clamps to soft.
      final mucusDay = await dayRow('2026-07-15');
      expect(mucusDay.mucusSign, MucusSign.f);
      expect(mucusDay.mucusQuality, isNull);
      expect(mucusDay.cervix, 'medium, soft, medium');
      expect(mucusDay.bbtC, isNull);
      expect(mucusDay.bleeding, Bleeding.none);
      expect(mucusDay.excludeOther, isFalse);

      // 2026-07-09: bleeding value 1 (light) with bleeding.exclude=true →
      // the level is the +1-shifted stored level (light); the PER-SYMPTOM
      // exclusion is
      // dropped (no storage), so no day-level exclude flag is set.
      final bleedingDay = await dayRow('2026-07-09');
      expect(bleedingDay.bleeding, Bleeding.light);
      expect(bleedingDay.excludeOther, isFalse,
          reason: 'bleeding.exclude has no storage and is dropped');
      expect(bleedingDay.excludeIllness, isFalse);

      // 2026-09-13: excluded temperature day — value kept, day-level
      // excludeOther set, temperature note under the [temp] prefix.
      final tempDay = await dayRow('2026-09-13');
      expect(tempDay.bbtC, 36.7);
      expect(tempDay.excludeOther, isTrue);
      expect(tempDay.notes, '[temp] measured late');
      expect(tempDay.bleeding, Bleeding.none);

      // 2026-09-15: note-only day — rides in because the note is data.
      final noteOnlyDay = await dayRow('2026-09-15');
      expect(noteOnlyDay.notes, 'cramps again, expecting menses soon.');
      expect(noteOnlyDay.bbtC, isNull);
      expect(noteOnlyDay.bleeding, Bleeding.none);
      expect(noteOnlyDay.painBreast, isFalse,
          reason: 'note.value is the plain day note, not a pain flag');

      // 2026-08-25: drip's tender-breasts kind → the breast (B) option.
      final breastDay = await dayRow('2026-08-25');
      expect(breastDay.painBreast, isTrue);
      expect(breastDay.painMittelschmerz, isFalse);
      expect(breastDay.notes, '[pain] tender in the evening');

      // 2026-07-17: partner sex WITH a condom — the sex observation stays
      // unset (only partner sex without contraception maps); the [sex]
      // note and the desire flag still make it a data row.
      final condomDay = await dayRow('2026-07-17');
      expect(condomDay.sex, isFalse,
          reason: 'partner sex with contraception is not the mapped variant');
      expect(condomDay.desire, isTrue);
      expect(condomDay.notes, '[sex] with condom, quite good');

      // 2026-09-12: solo sex with a note — note rides in, sex stays unset.
      final soloDay = await dayRow('2026-09-12');
      expect(soloDay.sex, isFalse, reason: 'solo is not partner sex');
      expect(soloDay.notes, '[sex] morning');
    });

    test('blank calendar days are absent from the database', () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      await importJsonToDatabase(db, mapping.json);
      final rows = await db.entriesDao.allEntriesForAllProfiles();

      final dates = rows.map((r) => formatIsoDay(r.date)).toSet();
      // 2026-07-10..14, 19, 21, 22 are all-empty rows in the fixture.
      // 2026-08-16 (partner sex, ambiguous contraceptive info) carries no
      // mappable data either under the sex rule — it must not be stored.
      for (final blank in [
        '2026-07-10',
        '2026-07-11',
        '2026-07-12',
        '2026-07-13',
        '2026-07-14',
        '2026-07-19',
        '2026-07-21',
        '2026-07-22',
        '2026-08-16',
      ]) {
        expect(dates.contains(blank), isFalse,
            reason: '$blank is an empty drip day and must not be stored');
      }
      expect(dates, hasLength(27));
    });

    test('temperature measurement times persist through the import → db '
        'round trip', () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      await importJsonToDatabase(db, mapping.json);

      // The two fixture rows carrying temperature.time values.
      expect((await dayRow('2026-07-05')).measuredAtMinutes, 7 * 60 + 15);
      expect((await dayRow('2026-08-02')).measuredAtMinutes, 6 * 60 + 50);
      // A temperature day without a time cell: null, never fabricated.
      expect((await dayRow('2026-09-13')).measuredAtMinutes, isNull);

      // The full-row equality re-import test below additionally proves the
      // times survive a second import untouched.
    });

    test('drip bleeding scale reads back from the db as the shifted levels',
        () async {
      // Synthetic CSV covering every drip bleeding value; the stored levels
      // are the drip scale shifted by +1 (an explicit none=0 exists here).
      // The out-of-range row carries a temperature so the day still imports
      // (proving out-of-range means "no observation", not "no row").
      final rows = [
        'date,temperature.value,bleeding.value',
        '2026-01-01,,0',
        '2026-01-02,,1',
        '2026-01-03,,2',
        '2026-01-04,,3',
        '2026-01-05,36.2,7',
      ].join('\n');
      final mapping = dripCsvToExportJson(rows);
      expect(mapping.stats.rowsInvalid, 0);
      final summary = await importJsonToDatabase(db, mapping.json);
      expect(summary.entriesWritten, 5);
      expect(summary.entriesInvalid, 0);

      expect((await dayRow('2026-01-01')).bleeding, Bleeding.spotting);
      expect((await dayRow('2026-01-02')).bleeding, Bleeding.light);
      expect((await dayRow('2026-01-03')).bleeding, Bleeding.medium);
      expect((await dayRow('2026-01-04')).bleeding, Bleeding.heavy);
      expect((await dayRow('2026-01-05')).bleeding, Bleeding.none,
          reason: 'out-of-range means no observation → neutral level');
    });

    test('fixture bleeding days store their shifted levels (light/medium)',
        () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      await importJsonToDatabase(db, mapping.json);

      // drip value 1 (light) on four days, value 2 (medium) on the rest —
      // the fixture carries no spotting/heavy, pinned per day below.
      expect((await dayRow('2026-07-05')).bleeding, Bleeding.medium);
      expect((await dayRow('2026-07-08')).bleeding, Bleeding.light);
      expect((await dayRow('2026-08-31')).bleeding, Bleeding.medium);
      expect((await dayRow('2026-09-01')).bleeding, Bleeding.light);
    });

    test('full-row equality of every stored day across a double import',
        () async {
      final mapping = dripCsvToExportJson(fixtureRaw);
      await importJsonToDatabase(db, mapping.json);
      final afterFirst = await storedEntries();
      expect(afterFirst, isNotEmpty, reason: 'guard: the import stored data');

      final summary2 = await importJsonToDatabase(
        db,
        dripCsvToExportJson(fixtureRaw).json,
      );

      // Idempotence in the counters: nothing new, everything merged.
      expect(summary2.entriesNew, 0);
      expect(summary2.entriesOverwritten, 27);
      expect(summary2.entriesInvalid, 0);
      expect(summary2.marksNew, 0);

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(27), reason: 'no duplicates on re-import');

      final afterSecond = await storedEntries();
      // Full-row equality for EVERY affected day, list-ordered.
      expect(afterSecond, afterFirst);
    });

    test('a resident unrelated cycle-app day survives the drip import',
        () async {
      final resident = dailyEntryFromDrift(await db.entriesDao.upsertDaily(
        DailyEntry(
          date: DateTime(2025, 2, 1),
          bbtC: 36.4,
          bleeding: Bleeding.medium,
          notes: 'my own diary note',
        ),
      ));

      final mapping = dripCsvToExportJson(fixtureRaw);
      final summary = await importJsonToDatabase(db, mapping.json);

      // The drip days overwrite/merge independently of the resident day.
      expect(summary.entriesNew, 27);
      expect(summary.entriesOverwritten, 0);

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(28),
          reason: '27 drip days + the unrelated pre-existing day');
      final storedList = rows.map(dailyEntryFromDrift).toList();

      final kept = storedList
          .singleWhere((e) => DateOnly.sameDay(e.date, DateTime(2025, 2, 1)));
      expect(kept, resident, reason: 'the pre-existing day is untouched');
    });
  });
}
