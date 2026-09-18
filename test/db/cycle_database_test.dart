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

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/marks.dart';
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

  group('schema & migration (v9)', () {
    test('no profiles table exists (v9 is profile-free)', () async {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE "
              "type = 'table'")
          .get();
      final names = tables.map((r) => r.data['name'] as String).toSet();
      expect(names, containsAll(['cycle_entries', 'user_marks']));
      expect(names.contains('profiles'), isFalse,
          reason: 'the Profiles table (and any seeding) is gone from v9');
    });

    test('profile_id columns are gone from both tables (no FK, no default)',
        () async {
      for (final table in ['cycle_entries', 'user_marks']) {
        final columns =
            await db.customSelect('PRAGMA table_info($table)').get();
        final names = columns.map((r) => r.data['name'] as String).toSet();
        expect(names.contains('profile_id'), isFalse,
            reason: '$table carries no profile_id column any more');
      }
    });

    test('the schema version is 9 (the NER-alignment bump)', () async {
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 9,
          reason: 'v9 replaces the exclude_* booleans/mood/desire with the '
              'temp_disturbances mask and widens the mucus vocabulary');
    });

    test(
        'temp_disturbances CHECK rejects masks outside 0..15; the column '
        'defaults to 0', () async {
      // 16 (and anything bigger): outside the 4-bit vocabulary.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, temp_disturbances) "
          "VALUES (20000, 16)",
        ),
        throwsA(isA<Exception>()),
      );
      // Negative masks are outside the vocabulary too.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, temp_disturbances) "
          "VALUES (20000, -1)",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: mask 15 (all four flags) goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, temp_disturbances) "
        "VALUES (20001, 15)",
      );
      // The column default: a row written without the field reads 0.
      await db.into(db.cycleEntries).insert(
            CycleEntriesCompanion.insert(date: DateTime(2026, 6, 20)),
          );
      final row = await db.entriesDao.entryFor(DateTime(2026, 6, 20));
      expect(row!.tempDisturbances, 0,
          reason: 'no-disturbance is the default, not an error');
    });

    test(
        "mucus_sign CHECK accepts the 'fs' token and rejects display "
        "glyphs", () async {
      // The new sign f/S ("f vor S an einem Tag") joins the vocabulary as
      // the TEXT token 'fs'.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, mucus_sign) "
        "VALUES (20004, 'fs')",
      );
      // The DISPLAY glyph is never a storage token.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign) "
          "VALUES (20005, 'f/S')",
        ),
        throwsA(isA<Exception>()),
      );
      // Unknown tokens stay rejected.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign) "
          "VALUES (20005, 'wet')",
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
        "mucus_quality is engine-rejected together with an 'fs' sign "
        "(fs carries no quality)", () async {
      // f/S is NOT the S sign: like every non-S sign it must never carry a
      // quality qualifier.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign, "
          "mucus_quality) VALUES (20000, 'fs', 'w')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: fs WITHOUT a quality goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, mucus_sign) "
        "VALUES (20006, 'fs')",
      );
    });

    test(
        'unique indexes are day-keyed (entries (date), marks (entry_date, '
        'mark_type))', () async {
      final indexes = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND "
            "name IN ('cycle_entries_date_unique', "
            "'user_marks_date_type_unique')",
          )
          .get();
      expect(
        indexes.map((r) => r.data['name']).toSet(),
        {'cycle_entries_date_unique', 'user_marks_date_type_unique'},
        reason: 'both day-keyed unique indexes exist (the old '
            'profile-prefixed names are gone)',
      );
      final byName = {
        for (final r in indexes)
          r.data['name']! as String: r.data['sql']! as String,
      };
      expect(byName['cycle_entries_date_unique']!, contains('(date)'));
      expect(
        byName['user_marks_date_type_unique']!,
        contains('(entry_date, mark_type)'),
        reason: 'marks are unique per day and type — no profile dimension',
      );
      expect(byName.values.join(' '), isNot(contains('profile_id')),
          reason: 'no profile column participates in any unique index');
    });

    test('a bare one-day row inserts (the entries upsert key is the day)',
        () async {
      await db
          .into(db.cycleEntries)
          .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)));
      final row = await db.entriesDao.entryFor(DateTime(2026, 3, 1));
      expect(row, isNotNull,
          reason: 'the day alone identifies the row (no profile dimension)');
    });

    test('out-of-vocabulary mucus_sign is rejected by its CHECK constraint',
        () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign) "
          "VALUES (20000, 'wet')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-vocabulary sign goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, mucus_sign) "
        "VALUES (20001, 's')",
      );
    });

    test(
        'mucus_quality is engine-rejected without an S sign and outside the '
        'vocabulary', () async {
      // Quality with any sign other than s: rejected (quality-requires-s).
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign, "
          "mucus_quality) VALUES (20000, 'f', 'w')",
        ),
        throwsA(isA<Exception>()),
      );
      // Quality with s but outside the vocabulary: rejected as well.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign, "
          "mucus_quality) VALUES (20002, 's', 'stretchy')",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: s with an in-vocabulary quality goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, mucus_sign, "
        "mucus_quality) VALUES (20003, 's', 'ew')",
      );
    });

    test('bleeding round-trips as each of the five levels', () async {
      for (final (index, level) in Bleeding.values.indexed) {
        final day = DateTime(2026, 6).add(Duration(days: index));
        await db.entriesDao.upsertDaily(DailyEntry(date: day, bleeding: level));
        final row = await db.entriesDao.entryFor(day);
        expect(row!.bleeding, level,
            reason: '${level.name} (level ${level.level}) must survive the '
                'db round trip by its stored number');
      }
    });

    test('bleeding is stored as the numeric level, never a string token',
        () async {
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15), bleeding: Bleeding.heavy),
      );
      final raw = await db
          .customSelect('SELECT bleeding FROM cycle_entries')
          .getSingle();
      expect(raw.data['bleeding'], Bleeding.heavy.level,
          reason: 'the decided storage representation is the integer level '
              '(4), not a vocabulary name');
    });

    test('bleeding defaults to 0: a row written without it reads none',
        () async {
      await db.into(db.cycleEntries).insert(
            CycleEntriesCompanion.insert(date: DateTime(2026, 6, 20)),
          );
      final row = await db.entriesDao.entryFor(DateTime(2026, 6, 20));
      expect(row!.bleeding, Bleeding.none);
      final raw = await db
          .customSelect('SELECT bleeding FROM cycle_entries')
          .getSingle();
      expect(raw.data['bleeding'], 0, reason: 'the column default is 0');
    });

    test('raw SQL INSERT stores an integer level that reads back heavy',
        () async {
      // Hand-written SQL (e.g. a future import path) stores the int directly:
      // 4 must read back as Bleeding.heavy (by LEVEL, not by declaration
      // index).
      await db.customStatement(
        'INSERT INTO cycle_entries (date, bleeding) '
        'VALUES (20000, 4)',
      );
      final row =
          await db.entriesDao.entryFor(DateTime(2024, 10, 4)); // day 20000
      expect(row!.bleeding, Bleeding.heavy);
    });

    test(
        'an unknown stored level is surfaced as an error, not silently '
        'mapped', () async {
      await db.customStatement(
        'INSERT INTO cycle_entries (date, bleeding) '
        'VALUES (20001, 7)',
      );
      await expectLater(
        db.entriesDao.entryFor(DateTime(2024, 10, 5)), // day 20001
        throwsA(isA<ArgumentError>()),
      );
    });

    test('epoch-day storage normalizes any time-of-day into the calendar day',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 4)));
      // Same calendar day, other time-of-day: must hit the same row.
      final row =
          await db.entriesDao.entryFor(DateTime(2026, 3, 4, 17, 30).toUtc());
      expect(row, isNotNull);
      expect(row!.date.year, 2026);
      expect(row.date.month, 3);
      expect(row.date.day, 4);
    });

    test('measured time-of-day is rejected outside the minute range', () async {
      // Engine-level CHECK, like the mucus constraint: 0–1439 or NULL.
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, measured_at_minutes) "
          "VALUES (20000, 1440)",
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO cycle_entries (date, measured_at_minutes) "
          "VALUES (20000, -1)",
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: an in-range value goes through.
      await db.customStatement(
        "INSERT INTO cycle_entries (date, measured_at_minutes) "
        "VALUES (20001, 405)",
      );
    });

    test(
        'the removed sex bool and free-text cervix columns are gone; firmness '
        'and timings exist', () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        cervixFirmness: CervixFirmness.halfSoft,
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
      ));
      // The old columns must not even be addressable any more.
      await expectLater(
        db.customSelect('SELECT sex FROM cycle_entries').get(),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customSelect('SELECT cervix FROM cycle_entries').get(),
        throwsA(isA<Exception>()),
      );
      // The replacements carry the observation in their decided shapes: the
      // firmness as its TEXT enum-name token, the timings as the mask.
      final raw = await db
          .customSelect(
              'SELECT cervix_firmness, sex_timings FROM cycle_entries')
          .getSingle();
      expect(raw.data['cervix_firmness'], 'halfSoft');
      expect(raw.data['sex_timings'], 5);
    });
  });

  group('destructive upgrade from an older schemaVersion', () {
    late Directory tempDir;
    late File dbFile;
    CycleDatabase? upgraded;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cycle_upgrade_fixt_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      dbFile = File('${tempDir.path}/old.db');
      addTearDown(() async {
        await upgraded?.close();
        upgraded = null;
      });
      // The outer `db` (fresh in-memory instance, see the outer setUp) is
      // unused here — this group works on its own file-backed database.
      // Closing the unused one first avoids drift's multiple-databases
      // warning (idempotent: the outer tearDown is a no-op afterwards).
      db.close();
    });

    /// Builds a file whose drift user_version is stale (1) and whose
    /// cycle_entries has an outdated shape with legacy columns and a junk
    /// row. Not a faithful reconstruction of any historical release schema —
    /// the pre-release upgrade policy discards everything anyway; the point
    /// is that opening through CycleDatabase recreates from the CURRENT
    /// schema instead of migrating.
    Future<CycleDatabase> openThroughAppSchema() async {
      final raw = sqlite3.open(dbFile.path);
      try {
        raw.execute(
          'CREATE TABLE profiles (id INTEGER PRIMARY KEY, '
          'name TEXT NOT NULL, ordinal INTEGER NOT NULL);',
        );
        raw.execute(
          'CREATE TABLE cycle_entries (id INTEGER PRIMARY KEY, '
          'profile_id INTEGER NOT NULL, date INTEGER NOT NULL, '
          'mucus_feeling TEXT NULL);',
        );
        raw.execute("INSERT INTO profiles VALUES (1, 'stale', 0);");
        raw.execute("INSERT INTO cycle_entries VALUES (101, 1, 20000, 'x');");
        raw.execute('PRAGMA user_version = 1;');
      } finally {
        raw.close();
      }
      final db = CycleDatabase(NativeDatabase(dbFile));
      upgraded = db;
      // Opening a query forces the executor to open, which runs the
      // destructive upgrade before the first statement completes.
      await db.entriesDao.allEntries();
      return db;
    }

    test(
        'opening a lower-version file recreates the schema, discarding old '
        'data', () async {
      final db = await openThroughAppSchema();

      final userVersion =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(userVersion.data['user_version'], 9,
          reason: 'drift records the upgrade run');

      // The profiles table is wiped and NOT recreated — no seeding, no
      // profile rows anywhere.
      final tableRows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE "
              "type = 'table'")
          .get();
      final tableNames = tableRows.map((r) => r.data['name'] as String).toSet();
      expect(tableNames.contains('profiles'), isFalse,
          reason: 'the legacy profiles table (from the stale file) is gone '
              'and nothing re-creates or re-seeds it');

      // The rebuilt table has the CURRENT shape: new columns with their
      // engine-level CHECKs, legacy columns gone.
      final ddl = await db
          .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' AND "
              "name = 'cycle_entries'")
          .getSingle();
      final sql = ddl.data['sql']! as String;
      expect(sql, contains('mucus_sign IS NULL OR mucus_sign IN'));
      expect(sql, contains("'fs'"),
          reason: 'the v9 mucus vocabulary includes the fs sign');
      expect(sql, isNot(contains('mucus_feeling')));
      expect(sql, contains('measured_at_minutes'),
          reason: 'the shred-and-recreate upgrade yields the current schema, '
              'including the newest column');
      expect(sql, contains('cervix_position'),
          reason: 'the current schema includes the Muttermund columns');
      expect(sql, contains('temp_disturbances'),
          reason: 'the current schema carries the raw disturbance mask');
      expect(sql, isNot(contains('exclude_illness')),
          reason: 'the old exclusion-reason booleans are gone from v9');
      expect(sql, isNot(contains('mood')),
          reason: 'Stimmung/Lust are gone from v9');
      expect(sql, isNot(contains('desire')));
      expect(sql, isNot(contains('profile_id')),
          reason: 'the profile column (and its FK/default) is gone from v9');

      // Foreign keys are enforced again (beforeOpen) and a normal DAO
      // write works on the day-keyed schema.
      final foreignKeys =
          await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(foreignKeys.data['foreign_keys'], 1);
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 6, 15)));
      final row = await db.entriesDao.entryFor(DateTime(2026, 6, 15));
      expect(row, isNotNull,
          reason: 'the upsert lands on its day with no profile dimension');
    });
  });

  group('EntriesDao.upsertByDate', () {
    test('inserts one row on the first write of a day', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)).copyWith(
          bleeding: const Value(Bleeding.medium),
        ),
      );
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(rows.single.bleeding, Bleeding.medium);
    });

    test(
        're-upsert keeps exactly one row, same id, replaces fields, keeps '
        'created_at and bumps updated_at', () async {
      final first = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(DailyEntry(
          date: DateTime(2026, 3, 1),
          bleeding: Bleeding.medium,
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

      final rows = await db.entriesDao.allEntries();
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
        'a duplicate same-day insert that bypasses the upsert hits '
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
      expect(await db.entriesDao.allEntries(), hasLength(1));
    });
  });

  group('EntriesDao round trip (drift <-> domain)', () {
    test('upsertDaily stores every domain field and maps back identical',
        () async {
      final input = DailyEntry(
        date: DateTime(2026, 6, 15),
        bbtC: 36.55,
        bleeding: Bleeding.spotting,
        tempDisturbances: TempDisturbance.sp.bit |
            TempDisturbance.a.bit |
            TempDisturbance.alk.bit |
            TempDisturbance.kr.bit,
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.ew,
        cervixPosition: CervixPosition.veryHigh,
        cervixOpening: CervixOpening.open,
        cervixFirmness: CervixFirmness.soft,
        painBreast: true,
        painMittelschmerz: true,
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
        notes: 'Notiz am Rande.',
      );

      final stored = await db.entriesDao.upsertDaily(input);
      final mapped = dailyEntryFromDrift(stored);

      expect(mapped, input); // DailyEntry == compares all fields + same day
      expect(stored.cervixFirmness, 'soft',
          reason: 'the firmness is stored as its TEXT enum-name token');
      expect(stored.sexTimings, 5,
          reason: 'the timings are stored as the INTEGER mask');
      final rawMask = await db
          .customSelect('SELECT temp_disturbances FROM cycle_entries')
          .getSingle();
      expect(rawMask.data['temp_disturbances'], 15,
          reason: 'the mask is stored as the INTEGER OR of the flag bits');
      expect(stored.date.year, 2026);
      expect(stored.date.month, 6);
      expect(stored.date.day, 15);
    });

    test('a mixed disturbance mask round-trips as the raw INTEGER mask',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        tempDisturbances: TempDisturbance.alk.bit, // 4
      ));
      await db.customStatement(
        'UPDATE cycle_entries SET temp_disturbances = 10', // a | kr = 2 | 8
      );
      final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
      expect(row.tempDisturbances, 10,
          reason: 'the engine stores the raw mask; the mapper reads '
              'verbatim — no per-bit conversion anywhere');
    });

    test('pain options B and M persist as separate boolean columns', () async {
      // Breast (B) set, Mittelschmerz (M) not: the two options are
      // independent per-day flags like the exclusion columns, not one
      // generic flag.
      final stored = await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        painBreast: true,
      ));
      final raw = await db
          .customSelect(
              'SELECT pain_breast, pain_mittelschmerz FROM cycle_entries')
          .getSingle();
      expect(raw.data['pain_breast'], 1,
          reason: 'B is stored as its own boolean column');
      expect(raw.data['pain_mittelschmerz'], 0,
          reason: 'M stays unset when only B was recorded');
      final mapped = dailyEntryFromDrift(stored);
      expect(mapped.painBreast, isTrue);
      expect(mapped.painMittelschmerz, isFalse);
    });

    test('explicit nulls are written on full replace (no stale values left)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        mucusSign: MucusSign.s,
        mucusQuality: MucusQuality.ew,
        cervixFirmness: CervixFirmness.halfSoft,
        sexTimings: 6,
        notes: 'old note',
      ));
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15)),
      );

      final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
      expect(row.mucusQuality, isNull);
      expect(row.mucusSign, isNull);
      expect(row.cervixFirmness, isNull);
      expect(row.sexTimings, 0,
          reason: 'the mask column resets to its default 0, not to a stale '
              'value');
      expect(row.notes, isNull);
    });

    test('measured time round-trips as minutes since midnight (or stays null)',
        () async {
      final measured = await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        bbtC: 36.4,
        measuredAtMinutes: 407, // 06:47
      ));
      expect(measured.measuredAtMinutes, 407);
      final mapped = dailyEntryFromDrift(measured);
      expect(mapped.measuredAtMinutes, 407);

      final unmeasured = await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 16),
        bbtC: 36.0,
      ));
      expect(unmeasured.measuredAtMinutes, isNull);
    });

    test('a time without a temperature stores null', () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        measuredAtMinutes: 407, // 06:47
      ));

      final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
      expect(row.bbtC, isNull);
      expect(row.measuredAtMinutes, isNull,
          reason: 'the measurement time belongs to the temperature; a '
              'mucus-only day stores no time');
    });

    test('updating a day without a measured time clears it (full replace)',
        () async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 6, 15),
        bbtC: 36.4,
        measuredAtMinutes: 407,
      ));
      // The replacement has no temperature either — the old time must not
      // survive as a stray value without its measurement.
      await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 6, 15)));

      final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
      expect(row.bbtC, isNull);
      expect(row.measuredAtMinutes, isNull);
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
        date: DateTime(2026, 6, 15),
        bleeding: Bleeding.none,
        tempDisturbances: 0,
        mucusSign: 'f',
        mucusQuality: 'w',
        painBreast: false,
        painMittelschmerz: false,
        cervixFirmness: null,
        sexTimings: 0,
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
      final rows =
          await db.entriesDao.range(DateTime(2026, 1, 3), DateTime(2026, 1, 8));
      expect(rows.map((r) => r.date.day).toList(), [3, 5, 8]);
    });

    test('watchRange emits rows as they are upserted', () async {
      // Buffer events instead of emit-counting matchers: drift delivers the
      // stream snapshot asynchronously, and the initial (empty) snapshot must
      // be observed BEFORE the write below to keep its ordering meaningful.
      final events = <List<CycleEntry>>[];
      final sub = db.entriesDao
          .watchRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31))
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
        DateTime(2026, 3, 12),
        MarkTypes.mucusPeakDay,
      );
      expect(mark.author, 'user');
      expect(mark.markType, MarkTypes.mucusPeakDay);
      expect(mark.entryDate.day, 12);

      final dayMarks = await db.marksDao.marksForDay(DateTime(2026, 3, 12));
      expect(dayMarks, hasLength(1));
    });

    test('addMark is idempotent per (date, type)', () async {
      final a = await db.marksDao
          .addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
      final b = await db.marksDao
          .addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
      expect(a.id, b.id,
          reason: 'the (date, mark_type) unique index makes the add a '
              'no-op');
      expect(
        await db.marksDao.marksForDay(DateTime(2026, 3, 12)),
        hasLength(1),
      );
    });

    test(
        'a duplicate (date, mark_type) insert bypassing addMark hits the '
        'unique index', () async {
      await db.marksDao.addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
      await expectLater(
        db.into(db.userMarks).insert(
              UserMarksCompanion.insert(
                  entryDate: DateTime(2026, 3, 12),
                  markType: MarkTypes.mucusPeakDay),
            ),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(
          await db.marksDao.marksForDay(DateTime(2026, 3, 12)), hasLength(1));
    });

    test('toggleMark adds then removes, reporting the new presence', () async {
      final date = DateTime(2026, 4, 9);
      expect(
        await db.marksDao.toggleMark(date, MarkTypes.mucusPeakDay),
        isTrue,
      );
      expect(
        await db.marksDao.marksForDay(date),
        hasLength(1),
      );
      expect(
        await db.marksDao.toggleMark(date, MarkTypes.mucusPeakDay),
        isFalse,
      );
      expect(
        await db.marksDao.marksForDay(date),
        isEmpty,
      );
    });

    test('deleteMark reports removed rows', () async {
      final date = DateTime(2026, 4, 10);
      await db.marksDao.addMark(date, MarkTypes.mucusPeakDay);
      expect(await db.marksDao.deleteMark(date, MarkTypes.mucusPeakDay), 1);
      expect(await db.marksDao.deleteMark(date, MarkTypes.mucusPeakDay), 0);
    });

    test('custom open-vocabulary mark types are storable (future tools)',
        () async {
      final date = DateTime(2026, 4, 11);
      await db.marksDao.addMark(date, 'adhocFutureTool');
      final marks = await db.marksDao.marksForDay(date);
      expect(marks.single.markType, 'adhocFutureTool');
    });
  });

  group('MarksDao <-> CycleMark round trip (mapper)', () {
    final day = DateTime(2026, 3, 12);

    test('toggleMark add/remove round-trips through the mapper', () async {
      final expected = CycleMark(
        date: day,
        type: CycleMarkTypes.mucusPeakDay,
      );
      expect(await db.marksDao.toggleMark(day, expected.type), isTrue);

      final stored = (await db.marksDao.marksForDay(day)).single;
      expect(cycleMarkFromDrift(stored), expected,
          reason: 'the stored row maps back to the domain mark the write '
              'was made from');

      expect(await db.marksDao.toggleMark(day, expected.type), isFalse);
      expect(await db.marksDao.marksForDay(day), isEmpty,
          reason: 'the removal is observable through the mapper too: no row, '
              'no domain mark');
    });

    test('the epoch-day converter normalizes any time-of-day into the day',
        () async {
      // Written with a time-of-day and in a non-UTC representation (the same
      // calendar day in a timezone east of UTC): must land on exactly one
      // row for the calendar day and read back as UTC midnight.
      final afternoon = DateTime(2026, 3, 12, 17, 30);
      final stored = await db.marksDao.addMark(
        afternoon,
        CycleMarkTypes.firstHigherMeasurement,
      );
      final mapped = cycleMarkFromDrift(stored);

      expect(DateOnly.sameDay(mapped.date, day), isTrue);
      expect(mapped.date.isUtc, isTrue,
          reason: 'domain dates are UTC midnight');
      expect(mapped.date.hour, 0);
      expect(mapped.date.minute, 0);

      // Same calendar day from another timezone representation: same row,
      // no duplicate (uniqueness is on the normalized day).
      await db.marksDao.addMark(
        afternoon.toUtc().add(const Duration(hours: 2)),
        CycleMarkTypes.firstHigherMeasurement,
      );
      expect(await db.marksDao.marksForDay(day), hasLength(1));
    });

    test(
        'a duplicate (date, type) insert bypassing addMark hits '
        'the unique index', () async {
      await db.marksDao.addMark(day, CycleMarkTypes.mucusPeakDay);
      await expectLater(
        db.into(db.userMarks).insert(
              cycleMarkToCompanion(
                CycleMark(date: day, type: CycleMarkTypes.mucusPeakDay),
              ),
            ),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(await db.marksDao.marksForDay(day), hasLength(1));
    });

    test('companion helper writes every domain field and maps back identical',
        () async {
      final mark = CycleMark(
        date: day,
        type: 'adhocFutureTool',
        author: 'assist',
      );
      await db.into(db.userMarks).insert(cycleMarkToCompanion(mark));

      final stored = (await db.marksDao.marksForDay(day)).single;
      expect(cycleMarkFromDrift(stored), mark);
    });

    test('the domain mark vocabulary mirrors the stored tokens', () {
      // The domain layer must never import lib/db, so the token strings are
      // duplicated into CycleMarkTypes — this test is the tripwire keeping
      // the two definitions in sync.
      expect(CycleMarkTypes.mucusPeakDay, MarkTypes.mucusPeakDay);
      expect(CycleMarkTypes.firstHigherMeasurement,
          MarkTypes.firstHigherMeasurement);
      // The temperature-ignore mark (the NER-aligned replacement of the
      // old exclude_* raw flags) is part of the shared vocabulary too.
      expect(CycleMarkTypes.ignoreTemperature, MarkTypes.ignoreTemperature);
      // The SUZ start markers (sicher unfruchtbare Zeit, placed by the
      // user from a morning or from an evening) joined the open TEXT
      // vocabulary — both sides must spell the tokens identically.
      expect(CycleMarkTypes.suzEvening, MarkTypes.suzEvening);
      expect(CycleMarkTypes.suzMorning, MarkTypes.suzMorning);
      // The cycleStart mark (the user-placed cycle start; bleeding only
      // suggests) is part of the open TEXT vocabulary too.
      expect(CycleMarkTypes.cycleStart, MarkTypes.cycleStart);
      // The removed unused tokens are GONE from both vocabularies: pinning
      // the strings is the tripwire — if the constants are re-introduced
      // anywhere, this test makes it visible.
      expect(
        CycleMarkTypes.mucusPeakDay,
        isNot(anyOf('baseline', 'fertileWindow', 'interruption')),
        reason: 'the removed legacy mark types must stay out of the '
            'vocabulary constants',
      );
    });

    test('watchAll streams all marks as they are toggled (date-keyed)',
        () async {
      // Buffered events, not emit counting: the initial empty snapshot must
      // be observed BEFORE the write so its ordering stays meaningful (same
      // pattern as the watchRange test above).
      final events = <List<UserMark>>[];
      final sub = db.marksDao.watchAll().listen(events.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      expect(events, [<UserMark>[]],
          reason: 'initial snapshot of an empty mark table');

      final otherDay = DateTime(2026, 3, 13);
      await db.marksDao
          .addMark(otherDay, CycleMarkTypes.firstHigherMeasurement);
      await db.marksDao.addMark(day, CycleMarkTypes.mucusPeakDay);
      await Future<void>.delayed(Duration.zero);

      // Content, not event counting: drift re-emits on ANY write to the
      // watched table, so the number of events is not a stable assertion —
      // the latest snapshot is.
      expect(events.last, hasLength(2),
          reason: 'the stream carries the mark table with no profile '
              'dimension');
      expect(
        [for (final m in events.last) m.markType],
        [CycleMarkTypes.mucusPeakDay, CycleMarkTypes.firstHigherMeasurement],
        reason: 'ordered by day, then type',
      );
      expect(events.last.first.entryDate.isBefore(events.last.last.entryDate),
          isTrue);

      await db.marksDao
          .deleteMark(otherDay, CycleMarkTypes.firstHigherMeasurement);
      await Future<void>.delayed(Duration.zero);
      expect(events.last.single.markType, CycleMarkTypes.mucusPeakDay);
    });
  });

  group('export adapter: import/export without profiles', () {
    // v5 documents carry NO profile keys anywhere — the document root is
    // exactly schema_version / exported_at / entries / marks.
    ExportBlob simpleDoc() => ExportBlob(
          exportedAt: DateTime.utc(2026, 4, 1),
          entries: const [
            {'date': '2026-04-02', 'bleeding': 'period'},
            {'date': '2026-04-10', 'bleeding': 'period', 'bbt_c': 36.4},
          ],
          marks: const [
            {
              'entry_date': '2026-04-20',
              'mark_type': 'mucusPeakDay',
              'author': 'user',
            },
          ],
        );

    test('a profile-free document imports day-keyed, no profile handling',
        () async {
      final summary = await importJsonToDatabase(
        db,
        buildExportJson(simpleDoc()),
      );
      expect(summary.entriesNew, 2);
      expect(summary.marksNew, 1);
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(2));
      final byKey = {
        for (final r in rows) formatIsoDay(r.date): r,
      };
      expect(byKey['2026-04-10']!.bbtC, 36.4,
          reason: 'the row lands on its day, identified by the day alone');
      final mark = (await db.marksDao.allMarks()).single;
      expect(DateOnly.sameDay(mark.entryDate, DateTime(2026, 4, 20)), isTrue);
    });

    test('re-importing the same document is idempotent (day/type keys)',
        () async {
      final doc = buildExportJson(simpleDoc());
      await importJsonToDatabase(db, doc);

      final second = await importJsonToDatabase(db, doc);
      expect(second.entriesNew, 0);
      expect(second.entriesOverwritten, 2);
      expect(second.marksNew, 0);
      expect(second.marksSkipped, 1,
          reason: 'marks are skip-idempotent on the (entry_date, mark_type) '
              'key');

      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(2), reason: 'no duplicate days on re-import');
      expect(await db.marksDao.allMarks(), hasLength(1));
    });

    test('old-document profile keys are accepted and ignored', () async {
      // v1–4 documents carry `profile_id` on every row and a root
      // `profiles` list. The v5 reader tolerates both keys (unknown keys
      // never error) and NEVER reads them: rows merge by day /
      // (entry_date, mark_type) alone.
      const oldJson = '{"schema_version": 3, '
          '"exported_at": "2026-04-01T00:00:00Z", '
          '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
          '"entries": [{"profile_id": 1, "date": "2026-04-02", '
          '"bleeding": 3}], '
          '"marks": [{"profile_id": 1, "entry_date": "2026-04-03", '
          '"mark_type": "mucusPeakDay", "author": "user"}]}';
      final summary = await importJsonToDatabase(db, oldJson);
      expect(summary.entriesNew, 1);
      expect(summary.marksNew, 1);

      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(DateOnly.sameDay(rows.single.date, DateTime(2026, 4, 2)), isTrue,
          reason: 'the day merge key holds regardless of profile_id');
      expect(await db.marksDao.allMarks(), hasLength(1));
    });

    test(
        'old-document exclude_* keys derive an ignoreTemperature mark '
        "(author 'import')", () async {
      // The old-document translation (inside the import transaction):
      // any of the four true exclude_* keys derives the analysis mark for
      // that day — and the current mark token is ignoreTemperature
      // (temperature-evaluation-scoped only — the mark does not affect
      // cycle-start suggestions any more). The derived token is pinned
      // here (a rename of the
      // stored vocabulary is a data-visible change, even with no schema
      // bump).
      const oldJson = '{"schema_version": 3, '
          '"exported_at": "2026-04-01T00:00:00Z", '
          '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
          '"entries": [{"profile_id": 1, "date": "2026-04-02", '
          '"bleeding": 3, "exclude_travel": true}], '
          '"marks": []}';
      final summary = await importJsonToDatabase(db, oldJson);
      expect(summary.entriesNew, 1);
      expect(summary.marksNew, 0,
          reason: 'the derived marks ride inside the transaction without '
              'being counted (document rows only)');

      final marks = await db.marksDao.allMarks();
      expect(marks, hasLength(1),
          reason: 'exclude_travel=true derives the temperature-ignore mark');
      expect(marks.single.markType, CycleMarkTypes.ignoreTemperature,
          reason: 'the derived mark token is the RENAMED one — the old '
              'name is gone from the production vocabulary (an escape '
              'hatch of the open-TEXT column would fail this pin)');
      expect(marks.single.author, 'import');
    });

    test(
        'old rows differing only by profile_id collapse to one day key '
        '(first occurrence wins)', () async {
      // Consequence of ignoring the profile dimension: two same-day rows
      // that differed only by profile_id now share ONE merge key; the plan
      // counts the second as a duplicate and the first occurrence wins.
      final doc = buildExportJson(ExportBlob(
        exportedAt: DateTime.utc(2026, 4, 1),
        entries: [
          {'profile_id': 1, 'date': '2026-04-02', 'bleeding': 3},
          {'profile_id': 3, 'date': '2026-04-02', 'bleeding': 0},
        ],
        marks: const [],
      ));
      final summary = await planDatabaseImport(db, doc);
      expect(summary.duplicateEntryRows, 1,
          reason: 'the (profile, day) key collapsed to the day key');
      expect(summary.entriesNew, 1);

      await importJsonToDatabase(db, doc);
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(rows.single.bleeding, Bleeding.medium,
          reason: 'the FIRST occurrence wins (bleeding level 3 = medium)');
    });

    test('unparsable bleeding rows are reported invalid and NOT written',
        () async {
      // The counting-vs-writing guarantee for field-level gates: the plan
      // counts exactly the rows the writer produces, so a row the writer
      // drops (unknown bleeding vocabulary) must appear in the invalid
      // bucket and must not reach the database.
      final doc = buildExportJson(ExportBlob(
        exportedAt: DateTime.utc(2026, 4, 1),
        entries: [
          {'date': '2026-05-01', 'bleeding': 'heavy'},
          {'date': '2026-05-02', 'bleeding': 'period'},
        ],
        marks: const [
          {
            'entry_date': '2026-05-03',
            'mark_type': 'mucusPeakDay',
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
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1),
          reason: 'the unparsable-bleeding row is never stored');
      expect(DateOnly.sameDay(rows.single.date, DateTime(2026, 5, 2)), isTrue);
      // The mark row was untouched by the entry gate.
      expect(await db.marksDao.allMarks(), hasLength(1));
    });

    group('measured time-of-day in the EXPORT version boundary', () {
      test('export carries the stored minutes; fresh db keeps it on import',
          () async {
        await db.entriesDao.upsertDaily(DailyEntry(
          date: DateTime(2026, 4, 2),
          bbtC: 36.4,
          measuredAtMinutes: 405, // 06:45
        ));

        final json = await exportDatabaseToJson(db);
        expect(json, contains('"measured_at_minutes": 405'));

        final target = CycleDatabase(NativeDatabase.memory());
        addTearDown(target.close);
        final summary = await importJsonToDatabase(target, json);
        expect(summary.entriesNew, 1);
        final row = await target.entriesDao.entryFor(DateTime(2026, 4, 2));
        expect(row!.measuredAtMinutes, 405);
      });

      test('export normalizes a stored time without a temperature to null',
          () async {
        // A legacy-style row (raw SQL): time stored without a temperature,
        // e.g. written before the app enforced the pairing. The export
        // document must not carry the stray time — what it carries is what
        // a re-import would store.
        final legacyDay = DateTime(2026, 6, 20);
        final legacyEpochDay =
            DateOnly.normalize(legacyDay).difference(DateTime.utc(1970)).inDays;
        await db.customStatement(
          'INSERT INTO cycle_entries (date, measured_at_minutes) '
          'VALUES ($legacyEpochDay, 405)',
        );

        final blob = await exportDatabaseToBlob(db);
        final legacyRow = blob.entries.singleWhere(
          (e) => e['date'] == formatIsoDay(legacyDay),
        );
        expect(legacyRow['bbt_c'], isNull);
        expect(legacyRow['measured_at_minutes'], isNull,
            reason: 'the export document never carries a time without its '
                'temperature');
      });

      test('old export documents without the field import with no time',
          () async {
        // A v1 document (shape published before the field existed). Raw
        // JSON on purpose: this pins the backward compatibility of the
        // actual file content (note the old profile keys: tolerated and
        // ignored), not a hand-built blob.
        const oldJson = '{"schema_version": 1, '
            '"exported_at": "2026-04-01T00:00:00Z", '
            '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
            '"entries": [{"profile_id": 1, "date": "2026-05-01", '
            '"bbt_c": 36.4, "bleeding": "none"}], '
            '"marks": []}';
        final summary = await importJsonToDatabase(db, oldJson);
        expect(summary.entriesNew, 1);

        final row = await db.entriesDao.entryFor(DateTime(2026, 5, 1));
        expect(row!.bbtC, 36.4);
        expect(row.measuredAtMinutes, isNull,
            reason: 'pre-field exports carry no time; that must not fail '
                'and must not fabricate one either');
      });
    });

    group('bleeding levels in the export version boundary', () {
      test(
          'export carries numeric bleeding levels and the current schema'
          ' version', () async {
        await db.entriesDao.upsertDaily(DailyEntry(
          date: DateTime(2026, 4, 2),
          bleeding: Bleeding.heavy,
        ));
        await db.entriesDao.upsertDaily(DailyEntry(
          date: DateTime(2026, 4, 3),
          bleeding: Bleeding.none,
        ));

        final json = await exportDatabaseToJson(db);
        expect(json, contains('"schema_version": 5'),
            reason: 'v5 is the NER-alignment release; documents always '
                'stamp their writing shape');
        expect(json, contains('"bleeding": 4'),
            reason: 'heavy is exported as its numeric level');
        expect(json, contains('"bleeding": 0'),
            reason: 'none is exported as its numeric level');
        expect(json, isNot(contains('"bleeding": "')),
            reason: 'documents no longer carry bleeding string tokens');
        // The v5 document carries no profile keys at all.
        expect(json, isNot(contains('profile_id')));
        expect(json, isNot(contains('profiles')));
      });

      test('legacy v1 token documents import and read back as mapped levels',
          () async {
        // A v1 document (published before heaviness existed) with the legacy
        // token vocabulary; the profile keys are tolerated and ignored.
        // Raw JSON on purpose: pins the actual file content of old exports,
        // not a hand-built blob.
        const oldJson = '{"schema_version": 1, '
            '"exported_at": "2026-04-01T00:00:00Z", '
            '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
            '"entries": ['
            '{"profile_id": 1, "date": "2026-05-01", "bleeding": "period"}, '
            '{"profile_id": 1, "date": "2026-05-02", "bleeding": "spotting"}], '
            '"marks": []}';
        final summary = await importJsonToDatabase(db, oldJson);
        expect(summary.entriesInvalid, 0);
        expect(summary.entriesWritten, 2);

        expect((await db.entriesDao.entryFor(DateTime(2026, 5, 1)))!.bleeding,
            Bleeding.medium,
            reason: 'period (generic menstruation) degrades to medium');
        expect((await db.entriesDao.entryFor(DateTime(2026, 5, 2)))!.bleeding,
            Bleeding.spotting);
      });

      test('export → import round trip preserves all five levels exactly',
          () async {
        // One day per level; the heavy/medium days prove there is no
        // medium-degradation through the document.
        final levels = Bleeding.values;
        for (var i = 0; i < levels.length; i++) {
          await db.entriesDao.upsertDaily(DailyEntry(
            date: DateTime(2026, 6, 1 + i),
            bleeding: levels[i],
          ));
        }

        final json = await exportDatabaseToJson(db);
        final target = CycleDatabase(NativeDatabase.memory());
        addTearDown(target.close);
        final summary = await importJsonToDatabase(target, json);
        expect(summary.entriesInvalid, 0);
        expect(summary.entriesWritten, levels.length);

        final sourceRows = await db.entriesDao.allEntries();
        final targetRows = await target.entriesDao.allEntries();
        expect(targetRows, hasLength(levels.length));
        for (var i = 0; i < levels.length; i++) {
          final source = sourceRows.singleWhere(
              (e) => DateOnly.sameDay(e.date, DateTime(2026, 6, 1 + i)));
          final imported = targetRows.singleWhere(
              (e) => DateOnly.sameDay(e.date, DateTime(2026, 6, 1 + i)));
          expect(imported.bleeding, source.bleeding,
              reason: '${levels[i].name} must survive the round trip exactly '
                  '(no degradation to medium)');
        }
      });
    });

    test('unexpected errors surface as ImportFailedException', () async {
      // Nothing half-imported survives a mid-transaction failure: the
      // wrapper turns any engine error into the typed failure the UI can
      // message instead of a raw crash. The engine fails here because the
      // database is closed.
      // The `broken` instance is alive next to the per-test `db` for this
      // one test, so drift's singleton debug warning would print on every
      // run — scope-limited suppression. The flag must be set BEFORE the
      // database is constructed (the warning fires at construction time)
      // and is restored by the harness afterwards.
      final previousWarningFlag =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningFlag);
      final broken = CycleDatabase(NativeDatabase.memory());
      // Ensure the lazy native executor has actually opened before closing —
      // closing a never-opened database is a no-op for drift, and the import
      // below would casually reopen it.
      await broken.entriesDao.allEntries();
      await broken.close();
      await expectLater(
        importJsonToDatabase(broken, buildExportJson(simpleDoc())),
        throwsA(isA<ImportFailedException>()),
      );
    });
  });
}
