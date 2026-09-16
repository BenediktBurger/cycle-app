// DB-layer tests: schema, DAOs, constraints.
//
// Pure Dart against NativeDatabase.memory() — no platform channels, no web.
// Runs with a normal `flutter pub get && flutter test` (on Linux, package
// sqlite3 additionally needs the system sqlite library — see the apt step in
// .github/workflows/ci.yml; macOS ships it, Linux CI/dev hosts install it).

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/db/tables.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('schema & migration (v2)', () {
    test('seeds exactly one profile named main', () async {
      final profiles = await db.profilesDao.allProfiles();
      expect(profiles, hasLength(1));
      expect(profiles.single.name, 'main');
      expect(profiles.single.ordinal, 0);
      expect(profiles.single.id, 1);
    });

    test('profileId default references the seeded profile', () async {
      await db
          .into(db.cycleEntries)
          .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)));
      final row = await db.entriesDao.entryFor(1, DateTime(2026, 3, 1));
      expect(row, isNotNull);
      expect(row!.profileId, 1);
    });

    test('out-of-vocabulary mucus_sign is rejected by its CHECK constraint',
        () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, mucus_sign) "
          "VALUES (1, 20000, 'wet')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary sign goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, mucus_sign) "
        "VALUES (1, 20001, 's')",
      );
    });

    test(
        'mucus_quality is engine-rejected without an S sign and outside the '
        'vocabulary', () async {
      // Quality with any sign other than s: rejected (quality-requires-s).
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, mucus_sign, "
          "mucus_quality) VALUES (1, 20000, 'f', 'w')",
        ),
        throwsA(isA<Exception>()),
      );
      // Quality with s but outside the vocabulary: rejected as well.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (profile_id, date, mucus_sign, "
          "mucus_quality) VALUES (1, 20002, 's', 'stretchy')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: s with an in-vocabulary quality goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, mucus_sign, "
        "mucus_quality) VALUES (1, 20003, 's', 'ew')",
      );
    });

    test('bleeding is stored and read as the drift enum vocabulary', () async {
      await db.customStatement(
        "INSERT INTO cycle_entries (profile_id, date, bleeding) "
        "VALUES (1, 20000, 'period')",
      );
      final row =
          await db.entriesDao.entryFor(1, DateTime(2024, 10, 4)); // day 20000
      expect(row!.bleeding, Bleeding.period);
    });

    test('cycle entries reference existing profiles (foreign keys on)',
        () async {
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(
                date: DateTime(2026, 3, 1),
                profileId: const Value(99),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('epoch-day storage normalizes any time-of-day into the calendar day',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 4)));
      // Same calendar day, other time-of-day: must hit the same row.
      final row =
          await db.entriesDao.entryFor(1, DateTime(2026, 3, 4, 17, 30).toUtc());
      expect(row, isNotNull);
      expect(row!.date.year, 2026);
      expect(row.date.month, 3);
      expect(row.date.day, 4);
    });
  });

  group('migration v1 -> v2 (mucus column rebuild)', () {
    late Directory tempDir;
    late File dbFile;
    CycleDatabase? migrated;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cycle_migration_fixt_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      dbFile = File('${tempDir.path}/v1.db');
      addTearDown(() async {
        await migrated?.close();
        migrated = null;
      });
      // The group-level `db` (fresh in-memory instance every test, see the
      // outer setUp) is unused here — the fixture opens its own file-backed
      // databases. Closing the unused one first avoids drift's
      // multiple-databases warning (idempotent: the outer tearDown is a
      // no-op afterwards).
      db.close();
    });

    /// Builds the REAL v1-era database on disk: the schema as drift generated
    /// it before the fertility-sign rework, with seeded rows and the file's
    /// drift user_version pinned to 1 — so opening it through CycleDatabase
    /// (schema version 2) runs the table-rebuild onUpgrade.
    Future<void> buildV1Database() async {
      createV1Schema(Database raw) {
        raw.execute(
          'CREATE TABLE "profiles" ("id" INTEGER PRIMARY KEY AUTOINCREMENT '
          'NOT NULL, "name" TEXT NOT NULL, "ordinal" INTEGER NOT NULL '
          'DEFAULT 0);',
        );
        raw.execute(
          'CREATE TABLE "user_marks" ("id" INTEGER PRIMARY KEY AUTOINCREMENT '
          'NOT NULL, "profile_id" INTEGER NOT NULL DEFAULT 1 '
          'REFERENCES profiles (id), "entry_date" INTEGER NOT NULL, '
          '"mark_type" TEXT NOT NULL, "author" TEXT NOT NULL DEFAULT \'user\');',
        );
        raw.execute(
          'CREATE TABLE "cycle_entries" ("id" INTEGER PRIMARY KEY '
          'AUTOINCREMENT NOT NULL, "profile_id" INTEGER NOT NULL DEFAULT 1 '
          'REFERENCES profiles (id), "date" INTEGER NOT NULL, '
          '"bbt_c" REAL NULL, "bleeding" TEXT NOT NULL DEFAULT \'none\', '
          '"exclude_illness" INTEGER NOT NULL DEFAULT 0 '
          'CHECK ("exclude_illness" IN (0, 1)), '
          '"exclude_alcohol" INTEGER NOT NULL DEFAULT 0 '
          'CHECK ("exclude_alcohol" IN (0, 1)), '
          '"exclude_travel" INTEGER NOT NULL DEFAULT 0 '
          'CHECK ("exclude_travel" IN (0, 1)), '
          '"exclude_other" INTEGER NOT NULL DEFAULT 0 '
          'CHECK ("exclude_other" IN (0, 1)), '
          '"mucus_feeling" TEXT NULL, '
          // Historical constraint, written inline by drift (customConstraint):
          '"mucus_nfp" INTEGER NULL '
          'CHECK (mucus_nfp IS NULL OR (mucus_nfp BETWEEN 0 AND 4)), '
          '"cervix" TEXT NULL, '
          '"pain" INTEGER NOT NULL DEFAULT 0 CHECK ("pain" IN (0, 1)), '
          '"mood" INTEGER NOT NULL DEFAULT 0 CHECK ("mood" IN (0, 1)), '
          '"desire" INTEGER NOT NULL DEFAULT 0 CHECK ("desire" IN (0, 1)), '
          '"sex" INTEGER NOT NULL DEFAULT 0 CHECK ("sex" IN (0, 1)), '
          '"notes" TEXT NULL, '
          '"created_at" INTEGER NOT NULL '
          'DEFAULT (strftime(\'%s\', CURRENT_TIMESTAMP)), '
          '"updated_at" INTEGER NOT NULL '
          'DEFAULT (strftime(\'%s\', CURRENT_TIMESTAMP)));',
        );
        raw.execute(
          'CREATE UNIQUE INDEX cycle_entries_profile_date_unique '
          'ON cycle_entries (profile_id, date);',
        );
        raw.execute(
          'CREATE UNIQUE INDEX user_marks_profile_date_type_unique '
          'ON user_marks (profile_id, entry_date, mark_type);',
        );
      }

      final raw = sqlite3.open(dbFile.path);
      try {
        createV1Schema(raw);
        raw.execute(
          'INSERT INTO profiles (id, name, ordinal) '
          "VALUES (1, 'main', 0), (2, 'zweit', 3);",
        );
        raw.execute(
          'INSERT INTO cycle_entries '
          '(id, profile_id, date, bbt_c, bleeding, exclude_travel, '
          'mucus_feeling, mucus_nfp, pain, notes, created_at, updated_at) '
          'VALUES (101, 2, 20000, 36.55, \'period\', 1, \'milky\', 2, 1, '
          "'v1 note', 1700000000, 1700000001), "
          '(102, 1, 20001, NULL, \'none\', 0, NULL, NULL, 0, NULL, '
          '1700000002, 1700000002);',
        );
        raw.execute(
          'INSERT INTO user_marks (id, profile_id, entry_date, mark_type, '
          "author) VALUES (201, 1, 20001, 'baseline', 'user');",
        );
        raw.execute('PRAGMA user_version = 1;');
      } finally {
        raw.close();
      }
    }

    Future<CycleDatabase> openThroughAppSchema() async {
      final db = CycleDatabase(NativeDatabase(dbFile));
      migrated = db;
      // Opening a query forces the executor to open, which runs the
      // v1 -> v2 upgrade before the first statement completes.
      await db.profilesDao.allProfiles();
      return db;
    }

    test('rebuild preserves rows and non-mucus fields; new columns enter '
        'as NULL', () async {
      await buildV1Database();
      final db = await openThroughAppSchema();

      final profiles = await db.profilesDao.allProfiles();
      expect(profiles.map((p) => p.name), ['main', 'zweit']);
      expect(profiles.singleWhere((p) => p.id == 2).ordinal, 3);

      final entries = await db.entriesDao.allEntriesForAllProfiles();
      expect(entries, hasLength(2), reason: 'both v1 rows survive');

      final oldDay = entries.singleWhere((e) => e.id == 101);
      expect(oldDay.profileId, 2);
      expect(oldDay.date.day, 4, reason: 'day 20000 = 2024-10-04');
      expect(oldDay.bbtC, 36.55);
      expect(oldDay.bleeding, Bleeding.period);
      expect(oldDay.excludeTravel, isTrue);
      expect(oldDay.pain, isTrue);
      expect(oldDay.notes, 'v1 note');
      expect(oldDay.mucusSign, isNull,
          reason: 'v1 mucus values are dropped without data migration');
      expect(oldDay.mucusQuality, isNull);

      final emptyDay = entries.singleWhere((e) => e.id == 102);
      expect(emptyDay.bleeding, Bleeding.none);
      expect(emptyDay.mucusSign, isNull);

      final marks = await db.marksDao.allMarksForAllProfiles();
      expect(marks, hasLength(1));
      expect(marks.single.id, 201);
    });

    test('schema is physically rebuilt: new columns + CHECKs present, old '
        'columns gone', () async {
      await buildV1Database();
      final db = await openThroughAppSchema();

      final userVersion = await db.customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersion.data['user_version'], 2,
          reason: 'drift records the run upgrade');

      final ddl = await db
          .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' AND "
              "name = 'cycle_entries'")
          .getSingle();
      final sql = ddl.data['sql']! as String;
      expect(sql, contains('mucus_sign'), reason: 'new column exists');
      expect(sql, contains('mucus_quality'));
      expect(sql, isNot(contains('mucus_feeling')),
          reason: 'retired columns are removed from the DDL');
      expect(sql, isNot(contains('mucus_nfp')));
      expect(sql, contains("mucus_sign IS NULL OR mucus_sign IN"),
          reason: 'the engine-level vocabulary CHECK is present post-migration');

      // The unique index was lost with the old table and must exist again:
      final indexCount = await db.customSelect(
              "SELECT COUNT(*) AS count FROM sqlite_master WHERE type = "
              "'index' AND name = 'cycle_entries_profile_date_unique'")
          .getSingle();
      expect(indexCount.data['count'], 1);
    });

    test('upsert and the recreated unique index work on the migrated rows',
        () async {
      await buildV1Database();
      final db = await openThroughAppSchema();

      // EntriesDao (stream/upsert flows) works on the rebuilt table.
      await db.entriesDao.upsertDaily(
        DailyEntry(
          date: DateTime(2026, 6, 15),
          mucusSign: MucusSign.s,
          mucusQuality: MucusQuality.ew,
        ),
      );
      final row = (await db.entriesDao.allEntriesForAllProfiles())
          .singleWhere((e) => e.date.month == 6);
      // CycleEntry exposes the raw TEXT tokens (enum mapping happens in the
      // mapper layer, tested above).
      expect(row.mucusSign, 's');
      expect(row.mucusQuality, 'ew');

      // A duplicate (profile, date) insert still hits the unique index.
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(date: DateTime(2026, 6, 15)),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('foreign keys stay enabled across the migration and a fresh reopen',
        () async {
      await buildV1Database();
      Future<Object?> foreignKeyState(CycleDatabase d) async => (await d
              .customSelect('PRAGMA foreign_keys')
              .getSingle())
          .data['foreign_keys'];

      final db = await openThroughAppSchema();
      expect(await foreignKeyState(db), 1);

      // The app schema's FK is intact: an unknown profile is rejected.
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(
                date: DateTime(2026, 7, 1),
                profileId: const Value(99),
              ),
            ),
        throwsA(isA<Exception>()),
      );

      // Reopen the settled v2 file with a fresh connection: the pragma is
      // re-enabled by the app's beforeOpen hook, and the rebuild must NOT
      // rerun (drift sees user_version == 2).
      await db.close();
      migrated = null;
      final reopened = CycleDatabase(NativeDatabase(dbFile));
      migrated = reopened;
      await reopened.profilesDao.allProfiles();
      expect(await foreignKeyState(reopened), 1);
      expect(await reopened.entriesDao.allEntriesForAllProfiles(), hasLength(2),
          reason: 'the rebuild ran exactly once');
    });

    test('the engine enforces the new CHECKs on a migrated database',
        () async {
      await buildV1Database();
      final db = await openThroughAppSchema();

      await expectLater(
        db.customStatement(
            "INSERT INTO cycle_entries (profile_id, date, mucus_sign) "
            "VALUES (1, 30000, 'wet')"),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
            "INSERT INTO cycle_entries (profile_id, date, mucus_sign, "
            "mucus_quality) VALUES (1, 30001, 'f', 'w')"),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('EntriesDao.upsertByDate', () {
    test('inserts one row on the first write of a day', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)).copyWith(
          bleeding: const Value(Bleeding.period),
        ),
      );
      final rows = await db.entriesDao.allEntries(1);
      expect(rows, hasLength(1));
      expect(rows.single.bleeding, Bleeding.period);
    });

    test(
        're-upsert keeps exactly one row, same id, replaces fields, keeps '
        'created_at and bumps updated_at', () async {
      final first = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(DailyEntry(
          date: DateTime(2026, 3, 1),
          bleeding: Bleeding.period,
          bbtC: 36.1,
        )),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final second = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(DailyEntry(
          date: DateTime(2026, 3, 1),
          bleeding: Bleeding.none,
          bbtC: 36.8,
          notes: 'changed',
        )),
      );

      final rows = await db.entriesDao.allEntries(1);
      expect(rows, hasLength(1)); // still exactly one row for the day

      expect(second.id, first.id); // stable identity
      expect(second.bbtC, 36.8); // replaced
      expect(second.bleeding, Bleeding.none); // replaced
      expect(second.notes, 'changed'); // replaced
      // created_at is kept (drift stores DateTimes with second precision,
      // so direct equality with "now" cannot be asserted reliably):
      expect(!second.createdAt.isBefore(first.createdAt), isTrue);
      expect(!second.updatedAt.isBefore(second.createdAt), isTrue);
    });

    test(
        'a duplicate (profile, date) insert that bypasses the upsert hits '
        'the unique index', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
      );
      await expectLater(
        db.into(db.cycleEntries).insert(
              CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
            ),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(await db.entriesDao.allEntries(1), hasLength(1));
    });

    test('same day across different profiles does not collide (partner mode)',
        () async {
      await db.profilesDao.addProfile('partner'); // id 2
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 1, 10), bleeding: Bleeding.none),
      );
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 1, 10), bbtC: 36.2, profileId: 2),
      );
      expect((await db.entriesDao.entryFor(1, DateTime(2026, 1, 10)))!.bbtC,
          isNull);
      expect(
          (await db.entriesDao.entryFor(2, DateTime(2026, 1, 10)))!.bbtC, 36.2);
    });
  });

  group('EntriesDao round trip (drift <-> domain)', () {
    test('upsertDaily stores every domain field and maps back identical',
        () async {
      final input = DailyEntry(
        date: DateTime(2026, 6, 15),
        profileId: 1,
        bbtC: 36.55,
        bleeding: Bleeding.spotting,
        excludeIllness: true,
        excludeAlcohol: true,
        excludeTravel: true,
        excludeOther: true,
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.ew,
        cervix: 'closed, low',
        pain: true,
        mood: true,
        desire: true,
        sex: true,
        notes: 'Notiz am Rande.',
      );

      final stored = await db.entriesDao.upsertDaily(input);
      final mapped = dailyEntryFromDrift(stored);

      expect(mapped, input); // DailyEntry == compares all fields + same day
      expect(stored.date.year, 2026);
      expect(stored.date.month, 6);
      expect(stored.date.day, 15);
    });

    test('explicit nulls are written on full replace (no stale values left)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.ew,
        notes: 'old note',
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15)),
      );

      final row = (await db.entriesDao.entryFor(1, DateTime(2026, 6, 15)))!;
      expect(row.mucusQuality, isNull);
      expect(row.mucusSign, isNull);
      expect(row.notes, isNull);
    });

    test('S with quality round-trips through the stored tokens and the mapper',
        () async {
      final stored = await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.gl,
      ));
      final rawSign = await db
          .customSelect("SELECT mucus_sign, mucus_quality FROM cycle_entries")
          .getSingle();
      expect(rawSign.data['mucus_sign'], 's',
          reason: 'TEXT token, not a glyph');
      expect(rawSign.data['mucus_quality'], 'gl');

      final mapped = dailyEntryFromDrift(stored);
      expect(mapped.mucusSign, MucusSign.s);
      expect(mapped.mucusQuality, MucusQuality.gl);
    });

    test('mapper/guard drops a quality that arrived without the S sign',
        () async {
      // The SQL CHECK makes such a pair unwritable through the engine, so the
      // mapper-side guard is defense in depth for rows that enter via another
      // path; pinned here on a hand-built row to guarantee the mapper can
      // never emit the impossible pair (quality collapses to null, the sign
      // itself is kept).
      final mismatched = CycleEntry(
        id: 1,
        profileId: 1,
        date: DateTime(2026, 6, 15),
        bleeding: Bleeding.none,
        excludeIllness: false,
        excludeAlcohol: false,
        excludeTravel: false,
        excludeOther: false,
        mucusSign: 'f',
        mucusQuality: 'w',
        pain: false,
        mood: false,
        desire: false,
        sex: false,
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 15),
      );
      final mapped = dailyEntryFromDrift(mismatched);
      expect(mapped.mucusSign, MucusSign.f);
      expect(mapped.mucusQuality, isNull);
    });
  });

  group('EntriesDao.range / watch / delete', () {
    test('range returns only inclusive-range rows, sorted ascending', () async {
      for (final day in [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 20),
      ]) {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: day, bleeding: Bleeding.none),
        );
      }
      final rows = await db.entriesDao
          .range(1, DateTime(2026, 1, 3), DateTime(2026, 1, 8));
      expect(rows.map((r) => r.date.day).toList(), [3, 5, 8]);
    });

    test('watchRange emits rows as they are upserted', () async {
      // Buffer events instead of emit-counting matchers: drift delivers the
      // stream snapshot asynchronously, and the initial (empty) snapshot must
      // be observed BEFORE the write below to keep its ordering meaningful.
      final events = <List<CycleEntry>>[];
      final sub = db.entriesDao
          .watchRange(1, DateTime(2026, 1, 1), DateTime(2026, 1, 31))
          .listen(events.add);
      // Failure-safe: the subscription is cancelled by the test harness even
      // if an assertion above fails and abandons the test body.
      addTearDown(sub.cancel);

      // One event-loop turn is enough for NativeDatabase.memory() (which
      // executes synchronously once scheduled) to deliver the snapshot.
      await Future<void>.delayed(Duration.zero);
      expect(events, [<CycleEntry>[]],
          reason: 'initial snapshot of an empty table');

      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 1, 10),
        bleeding: Bleeding.spotting,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[1].length, 1);
      expect(events[1].single.bleeding, Bleeding.spotting);
      await sub.cancel();
    });
  });

  group('MarksDao', () {
    test('addMark persists with default author user and lists per day',
        () async {
      final mark = await db.marksDao.addMark(
        1,
        DateTime(2026, 3, 12),
        MarkTypes.mucusPeakDay,
      );
      expect(mark.author, 'user');
      expect(mark.markType, MarkTypes.mucusPeakDay);
      expect(mark.entryDate.day, 12);

      final dayMarks = await db.marksDao.marksForDay(1, DateTime(2026, 3, 12));
      expect(dayMarks, hasLength(1));
    });

    test('addMark is idempotent per (profile, date, type)', () async {
      final a = await db.marksDao
          .addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      final b = await db.marksDao
          .addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      expect(a.id, b.id);
      expect(
        await db.marksDao.marksForDay(1, DateTime(2026, 3, 12)),
        hasLength(1),
      );
    });

    test('same day + same type stay distinct across profiles', () async {
      await db.profilesDao.addProfile('partner'); // id 2
      await db.marksDao.addMark(1, DateTime(2026, 3, 12), MarkTypes.baseline);
      await db.marksDao.addMark(2, DateTime(2026, 3, 12), MarkTypes.baseline);
      final p1 = await db.marksDao
          .marksInRange(1, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      final p2 = await db.marksDao
          .marksInRange(2, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      expect(p1, hasLength(1));
      expect(p2, hasLength(1));
    });

    test('toggleMark adds then removes, reporting the new presence', () async {
      final date = DateTime(2026, 4, 9);
      expect(
        await db.marksDao.toggleMark(1, date, MarkTypes.fertileWindow),
        isTrue,
      );
      expect(
        await db.marksDao.marksForDay(1, date),
        hasLength(1),
      );
      expect(
        await db.marksDao.toggleMark(1, date, MarkTypes.fertileWindow),
        isFalse,
      );
      expect(
        await db.marksDao.marksForDay(1, date),
        isEmpty,
      );
    });

    test('deleteMark reports removed rows', () async {
      final date = DateTime(2026, 4, 10);
      await db.marksDao.addMark(1, date, MarkTypes.baseline);
      expect(await db.marksDao.deleteMark(1, date, MarkTypes.baseline), 1);
      expect(await db.marksDao.deleteMark(1, date, MarkTypes.baseline), 0);
    });

    test('custom open-vocabulary mark types are storable (future tools)',
        () async {
      final date = DateTime(2026, 4, 11);
      await db.marksDao.addMark(1, date, 'adhocFutureTool');
      final marks = await db.marksDao.marksForDay(1, date);
      expect(marks.single.markType, 'adhocFutureTool');
    });
  });

  group('ProfilesDao', () {
    test('profileNames lists ordinal-ordered names', () async {
      final p = await db.profilesDao.addProfile('zweit', ordinal: 1);
      expect(p.id, greaterThan(1));
      expect(await db.profilesDao.profileNames(), ['main', 'zweit']);
      expect((await db.profilesDao.byId(p.id))!.name, 'zweit');
      expect(await db.profilesDao.byId(404), isNull);
    });
  });

  group('export adapter: profile-id remap on import', () {
    // Document referencing profile id 4 (unknown on the device: 1 = main,
    // 2 = fixture profile). Re-creation assigns the next AUTO id (3), so
    // every write for that document id must use the ACTUAL id — remapping
    // the document id is the adapter's job during the import writes.
    ExportBlob remapDoc() => ExportBlob(
          exportedAt: DateTime.utc(2026, 4, 1),
          profiles: const [
            {'id': 1, 'name': 'main', 'ordinal': 0},
            {'id': 4, 'name': 'partner-doc', 'ordinal': 1},
          ],
          entries: [
            {'profile_id': 4, 'date': '2026-04-02', 'bleeding': 'period'},
            {
              'profile_id': 1,
              'date': '2026-04-10',
              'bleeding': 'period',
              'bbt_c': 36.4,
            },
          ],
          marks: [
            {
              'profile_id': 4,
              'entry_date': '2026-04-20',
              'mark_type': 'peak',
              'author': 'user',
            },
          ],
        );

    test('re-created profiles: document ids are remapped to the actual ids',
        () async {
      final resident = await db.profilesDao.addProfile('resident', ordinal: 1);
      expect(resident.id, 2, reason: 'fixture: device ids are 1 and 2');

      final summary =
          await importJsonToDatabase(db, buildExportJson(remapDoc()));
      expect(summary.entriesNew, 2);
      expect(summary.profilesToInsert, 1);
      expect(summary.marksNew, 1);

      final partner = (await db.profilesDao.allProfiles())
          .singleWhere((p) => p.name == 'partner-doc');
      expect(partner.id, isNot(4),
          reason: 're-created profiles carry their own AUTO id');

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(2));
      final fromDoc = rows
          .singleWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 2)));
      expect(fromDoc.profileId, partner.id,
          reason: 'document profile id 4 is written under the actual id 3');
      final own = rows
          .singleWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 10)));
      expect(own.profileId, 1,
          reason: 'ids known on the device keep addressing that profile');
      expect(own.bbtC, 36.4);

      final mark = (await db.marksDao.allMarksForAllProfiles()).single;
      expect(mark.profileId, partner.id,
          reason: 'marks are remapped the same way');
      expect(DateOnly.sameDay(mark.entryDate, DateTime(2026, 4, 20)), isTrue);
    });

    test('numeric-string profile ids import exactly once (tolerant ids)',
        () async {
      // Some exporters/tools serialize ids as strings; the merge planner
      // accepts int or numeric-string ids, so the writer must too — a
      // mismatch would count rows in the summary while silently skipping
      // the actual writes.
      ExportBlob stringIdDoc() => ExportBlob(
            exportedAt: DateTime.utc(2026, 4, 1),
            profiles: const [
              {'id': '1', 'name': 'main', 'ordinal': 0},
            ],
            entries: [
              {'profile_id': '1', 'date': '2026-04-02', 'bleeding': 'period'},
            ],
            marks: [
              {
                'profile_id': '1',
                'entry_date': '2026-04-03',
                'mark_type': 'baseline',
                'author': 'user',
              },
            ],
          );

      final summary =
          await importJsonToDatabase(db, buildExportJson(stringIdDoc()));
      expect(summary.entriesNew, 1,
          reason: 'the plan counts the row, so it must be written too');
      expect(summary.marksNew, 1);

      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(1),
          reason: 'string id "1" addresses the known device profile 1');
      expect(rows.single.profileId, 1);
      expect(await db.marksDao.allMarksForAllProfiles(), hasLength(1));
      expect(await db.profilesDao.allProfiles(), hasLength(1),
          reason: 'no duplicate profile is created for the string id');
    });

    test('unparsable bleeding rows are reported invalid and NOT written',
        () async {
      // The counting-vs-writing guarantee for field-level gates: the plan
      // counts exactly the rows the writer produces, so a row the writer
      // drops (unknown bleeding vocabulary) must appear in the invalid
      // bucket and must not reach the database.
      final doc = buildExportJson(ExportBlob(
        exportedAt: DateTime.utc(2026, 4, 1),
        profiles: const [],
        entries: [
          {'profile_id': 1, 'date': '2026-05-01', 'bleeding': 'heavy'},
          {'profile_id': 1, 'date': '2026-05-02', 'bleeding': 'period'},
        ],
        marks: [
          {
            'profile_id': 1,
            'entry_date': '2026-05-03',
            'mark_type': 'baseline',
            'author': 'user',
          },
        ],
      ));

      final summary = await planDatabaseImport(db, doc);
      expect(summary.entriesInvalid, 1);
      expect(summary.entriesNew, 1);
      expect(summary.entriesWritten, 1);

      final summary2 = await importJsonToDatabase(db, doc);
      expect(summary2.entriesInvalid, 1);
      expect(summary2.entriesNew, 1);
      final rows = await db.entriesDao.allEntriesForAllProfiles();
      expect(rows, hasLength(1),
          reason: 'the unparsable-bleeding row is never stored');
      expect(DateOnly.sameDay(rows.single.date, DateTime(2026, 5, 2)), isTrue);
      // The mark row was untouched by the entry gate.
      expect(await db.marksDao.allMarksForAllProfiles(), hasLength(1));
    });

    test('unexpected errors surface as ImportFailedException', () async {
      // Nothing half-imported survives a mid-transaction/prepare failure:
      // the wrapper turns any engine error into the typed failure the UI
      // can message instead of a raw crash. The engine fails here because
      // the database is closed.
      // The `broken` instance is alive next to the per-test `db` for this one
      // test, so drift's singleton debug warning would print on every run —
      // scope-limited suppression. The flag must be set BEFORE the database
      // is constructed (the warning fires at construction time) and is
      // restored by the harness afterwards.
      final previousWarningFlag =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningFlag);
      final broken = CycleDatabase(NativeDatabase.memory());
      // Ensure the lazy native executor has actually opened before closing —
      // closing a never-opened database is a no-op for drift, and the import
      // below would casually reopen it.
      await broken.profilesDao.allProfiles();
      await broken.close();
      await expectLater(
        importJsonToDatabase(broken, buildExportJson(remapDoc())),
        throwsA(isA<ImportFailedException>()),
      );
    });
  });
}
