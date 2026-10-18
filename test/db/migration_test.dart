// Migration tests: the schema-version pin and the incremental upgrade
// choreography from old on-disk files (v9/v10/v12 → the current schema).
//
// Pure Dart against drift's NativeDatabase — no platform channels. Same
// Linux system-sqlite note as test/db/cycle_database_test.dart.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/models.dart';

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('the schema version is 14 (the custom_marks column)', () async {
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(
      version.data['user_version'],
      14,
      reason:
          'v14 adds the custom_marks column to cycle_entries; an '
          'existing install gains it through the incremental addColumn, '
          'so the step is a real migration',
    );
  });
  group('incremental upgrade from an older schemaVersion', () {
    late Directory tempDir;
    late File dbFile;
    CycleDatabase? upgraded;
    // The CURRENT DDL, dumped from the fresh in-memory `db` in setUp (the
    // rows carry 'type' + 'name' + the CREATE statement).
    List<Map<String, Object?>> currentDdl = const [];

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('cycle_upgrade_fixt_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      dbFile = File('${tempDir.path}/old.db');
      addTearDown(() async {
        await upgraded?.close();
        upgraded = null;
      });
      // Dump the CURRENT DDL instead of hand-writing it: the fixture
      // executes these statements into the temp file, so it tracks the
      // schema as it evolves. Auto-indexes (sql IS NULL) are skipped —
      // they are created implicitly together with their tables.
      currentDdl = [
        for (final r
            in await db
                .customSelect(
                  "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT "
                  "NULL AND tbl_name IN "
                  "('cycle_entries', 'user_marks', 'app_settings', "
                  "'measurement_methods')",
                )
                .get())
          {
            'type': r.data['type']! as String,
            'name': r.data['name']! as String,
            'sql': r.data['sql']! as String,
          },
      ];
      // The outer `db` is now unused — this group works on its own
      // file-backed database — so close it here to avoid drift's
      // multiple-databases warning (idempotent: the outer tearDown is a
      // no-op afterwards).
      await db.close();
    });

    /// Builds a temp-file database stamped with the stale [from]
    /// user_version, whose DDL is the CURRENT schema (dumped in setUp) with
    /// up to TWO rewrites: pre-v12 files do not carry the bleeding column's
    /// engine-level CHECK, so the replayed `cycle_entries` statement is
    /// stripped back to the plain `NOT NULL DEFAULT 0` column (the regex
    /// matches the column definition up to the next comma, whatever the
    /// rest of the statement looks like), and pre-v14 files do not carry
    /// the `custom_marks` column at all, so it is stripped from the
    /// replayed `cycle_entries` statement the same way (the migration's
    /// addColumn is what must create it). Per the documented history, the
    /// remaining DDL of a v9/v10/v11/v12/v13-shaped file is the current
    /// DDL — v9→v10 adds only `app_settings`, v10→v11 changes no SQL,
    /// v11→v12 touches only the bleeding column, the `measurement_methods`
    /// snapshot table is NEW in v13 (so no pre-v13 file carries it; the
    /// fixture never replays it), and v13→v14 adds only `custom_marks`.
    /// These deltas are all the fixture controls. The seeded user data is
    /// written with raw SQL and explicit
    /// created_at/updated_at values so the rows are individually
    /// identifiable (a table recreated from the current schema cannot
    /// answer them, which is what makes the data-preservation pin
    /// meaningful).
    Future<CycleDatabase> openMigrationFixture(
      int from, {
      required bool withAppSettings,
      int seedBleeding = 4,
    }) async {
      // Pre-v14 files carry no custom_marks column: it is stripped from
      // the replayed DDL so the migration's addColumn is the step that
      // creates it (same trick as the bleeding CHECK strip).
      String cycleEntriesSql(String sql) {
        final bleedingStripped = sql.replaceAllMapped(
          RegExp(r'"bleeding" INTEGER[^,]*'),
          (_) => '"bleeding" INTEGER NOT NULL DEFAULT 0',
        );
        return from < 14
            ? bleedingStripped.replaceAll(
                RegExp(r',\s*"custom_marks" TEXT[^,]*'),
                '',
              )
            : bleedingStripped;
      }

      final statements = [
        for (final r in currentDdl)
          if ((withAppSettings || r['name'] != 'app_settings') &&
              // All of the methods table's DDL (its index included) is the
              // v13 delta — no pre-v13 file carries any of it.
              r['name'] != 'measurement_methods' &&
              r['name'] != 'measurement_methods_date_unique')
            (
              tableFirst: r['type'] == 'table' ? 0 : 1,
              sql: r['type'] == 'table' && r['name'] == 'cycle_entries'
                  ? cycleEntriesSql(r['sql']! as String)
                  : r['sql']! as String,
            ),
      ]..sort((a, b) => a.tableFirst - b.tableFirst); // tables before indexes
      final raw = sqlite3.open(dbFile.path);
      try {
        for (final stmt in statements) {
          raw.execute(stmt.sql);
        }
        raw.execute(
          'INSERT INTO cycle_entries (date, temp_disturbances, bbt_c, '
          'measured_at_minutes, bleeding, mucus_sign, mucus_quality, '
          'cervix_position, cervix_opening, cervix_firmness, pain_breast, '
          'pain_mittelschmerz, sex_timings, notes, created_at, updated_at) '
          "VALUES (20000, 5, 36.55, 405, $seedBleeding, 's', 'ew', 'high', "
          "'middle', 'soft', 1, 0, 5, 'seeded row', 1767225600, 1767229200)",
        );
        raw.execute(
          "INSERT INTO user_marks (entry_date, mark_type, author) "
          "VALUES (20001, 'cycleStart', 'user')",
        );
        raw.execute('PRAGMA user_version = $from;');
      } finally {
        raw.close();
      }
      final db = CycleDatabase(NativeDatabase(dbFile));
      upgraded = db;
      // The migration runs lazily on the first query, so the caller forces
      // the open (or — in the migration-failure test — asserts on the
      // thrown failure) itself.
      return db;
    }

    Future<void> expectPreserved(CycleDatabase db) async {
      // The seeded entry row survives row-for-row, read through the normal
      // DAO (not raw SQL): the migration must not discard user data.
      final row = await db.entriesDao.entryFor(DateTime(2024, 10, 4));
      expect(row, isNotNull, reason: 'day 20000 carries the seeded row');
      expect(row!.bleeding, Bleeding.heavy, reason: 'level 4 is preserved');
      expect(row.bbtC, 36.55);
      expect(row.tempDisturbances, 5);
      expect(row.measuredAtMinutes, 405);
      expect(row.mucusSign, 's');
      expect(row.mucusQuality, 'ew');
      expect(row.cervixPosition, 'high');
      expect(row.cervixOpening, 'middle');
      expect(row.cervixFirmness, 'soft');
      expect(row.painBreast, isTrue);
      expect(row.painMittelschmerz, isFalse);
      expect(row.sexTimings, 5);
      expect(row.notes, 'seeded row');
      expect(
        dailyEntryFromDrift(row).customMarks,
        isEmpty,
        reason: 'the seeded pre-v14 row carries no custom marks',
      );
      expect(
        row.createdAt.isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
        isTrue,
        reason: 'the explicit created_at survives the migration verbatim',
      );
      expect(
        row.updatedAt.isAtSameMomentAs(DateTime.utc(2026, 1, 1, 1)),
        isTrue,
        reason: 'the explicit updated_at survives the migration verbatim',
      );

      // The table recreation must not lose the unique index the EntriesDao
      // upsert path relies on.
      final indexNames = [
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index' AND "
                  "name = 'cycle_entries_date_unique'",
                )
                .get())
          r.data['name']! as String,
      ];
      expect(
        indexNames,
        hasLength(1),
        reason: 'the day-keyed unique index survives the table recreation',
      );

      // A day upsert after the upgrade still replaces the row IN PLACE: it
      // must hit the surviving unique index (no second row, stable id).
      final updated = await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2024, 10, 4), bleeding: Bleeding.spotting),
      );
      expect(
        updated.id,
        row.id,
        reason:
            'the upsert keyed by the surviving unique index replaces '
            'the same row',
      );
      expect(
        await db.entriesDao.allEntries(),
        hasLength(1),
        reason: 'no second row appeared for the already-tracked day',
      );
      expect(
        (await db.entriesDao.entryFor(DateTime(2024, 10, 4)))!.bleeding,
        Bleeding.spotting,
      );

      // The seeded mark survives too.
      final marks = await db.marksDao.marksForDay(DateTime(2024, 10, 5));
      expect(
        marks,
        hasLength(1),
        reason: 'the (entry_date, mark_type) row is preserved',
      );
      expect(marks.single.markType, 'cycleStart');
      expect(marks.single.author, 'user');

      // beforeOpen keeps foreign-keys enforcement after an upgrade.
      final foreignKeys = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(foreignKeys.data['foreign_keys'], 1);
    }

    test('a v10 file migrates incrementally: seeded data preserved, nothing '
        'dropped or recreated', () async {
      final db = await openMigrationFixture(10, withAppSettings: true);
      await expectPreserved(db);
    });

    test('a v9 file migrates incrementally: data preserved and settings '
        'storage works immediately after', () async {
      final db = await openMigrationFixture(9, withAppSettings: false);
      await expectPreserved(db);

      // Settings storage works immediately after the upgrade.
      await db.settingsDao.writeValue('themeMode', 'dark');
      expect(await db.settingsDao.readValue('themeMode'), 'dark');
    });

    test(
      'a v12 file migrates incrementally: the methods table appears with '
      'its day key, vocabulary CHECK and the tracked data preserved',
      () async {
        final db = await openMigrationFixture(12, withAppSettings: true);
        await expectPreserved(db);

        final indexNames = [
          for (final r
              in await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index' AND "
                    "name = 'measurement_methods_date_unique'",
                  )
                  .get())
            r.data['name']! as String,
        ];
        expect(
          indexNames,
          hasLength(1),
          reason: 'the day key is unique — one snapshot per calendar day',
        );

        // The engine CHECK survives the incremental create: foreign data
        // cannot write an impossible route into a migrated file.
        final rawDate = 20000;
        await expectLater(
          db.customStatement(
            "INSERT INTO measurement_methods (date, method) "
            "VALUES ($rawDate, 'anal')",
          ),
          throwsA(isA<Exception>()),
        );
        await db.customStatement(
          "INSERT INTO measurement_methods (date, method) "
          "VALUES ($rawDate, 'oral')",
        );
        expect(
          await db.measurementMethodsDao.snapshotFor(DateTime(2024, 10, 4)),
          isNotNull,
          reason: 'the migrated table answers the DAO immediately',
        );
      },
    );

    test('a v13 file migrates incrementally: the custom_marks column appears '
        'with the tracked data preserved', () async {
      final db = await openMigrationFixture(13, withAppSettings: true);
      await expectPreserved(db);

      final columns = [
        for (final r
            in await db.customSelect('PRAGMA table_info(cycle_entries)').get())
          r.data['name']! as String,
      ];
      expect(
        columns,
        contains('custom_marks'),
        reason: 'the v13→v14 step adds the nullable column in place',
      );
      final raw = await db
          .customSelect('SELECT custom_marks FROM cycle_entries')
          .getSingle();
      expect(
        raw.data['custom_marks'],
        isNull,
        reason: 'the migrated pre-v14 row carries no custom marks',
      );

      // The new column round-trips through the normal DAO immediately
      // after the upgrade.
      const marks = {
        'Sport': ['Joggen', 'Kraft'],
      };
      await db.entriesDao.upsertDaily(
        DailyEntry(
          date: DateTime(2024, 10, 4),
          bleeding: Bleeding.heavy,
          customMarks: marks,
        ),
      );
      final row = (await db.entriesDao.entryFor(DateTime(2024, 10, 4)))!;
      expect(dailyEntryFromDrift(row).customMarks, marks);
    });

    test('a pre-existing out-of-range bleeding row fails the migration '
        'loudly', () async {
      // The old-shape file admits such a corrupt row (its bleeding column
      // still carries no CHECK). The migration copies the rows into the
      // CHECK-shaped table and must FAIL on the corrupt one — no clamping,
      // no dropping, no silent continuation: the streams reading that
      // converter were already broken, so surfacing the failure on the
      // database gate is the consistent posture.
      final db = await openMigrationFixture(
        10,
        withAppSettings: true,
        seedBleeding: 6,
      );
      // The first query forces the open; the upgrade must reject it there.
      await expectLater(db.entriesDao.allEntries(), throwsA(isA<Exception>()));
    });
  });
}
