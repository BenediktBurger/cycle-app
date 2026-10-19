// DB-layer tests: the schema CHECK-constraint matrix, DAO CRUD round trips
// and the vocabulary tripwires (mucus tokens, bleeding levels, mark types).
// On-disk migration choreography and the export document boundary live in
// test/db/migration_test.dart / export_adapter_test.dart.
//
// Pure Dart against NativeDatabase.memory() — no platform channels, no web.
// Runs with a normal `flutter pub get && flutter test` (on Linux, package
// sqlite3 additionally needs the system sqlite library — see the apt step in
// .github/workflows/ci.yml; macOS ships it, Linux CI/dev hosts install it).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/db/converters.dart';
import 'package:cycle_app/db/cycle_database.dart';
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
    test('temp_disturbances CHECK rejects masks outside 0..15; the column '
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
      await db
          .into(db.cycleEntries)
          .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 6, 20)));
      final row = await db.entriesDao.entryFor(DateTime(2026, 6, 20));
      expect(
        row!.tempDisturbances,
        0,
        reason: 'no-disturbance is the default, not an error',
      );
    });

    test("mucus_sign CHECK accepts the 'fs' token and rejects display "
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
    });

    test(
      'a bare one-day row inserts (the entries upsert key is the day)',
      () async {
        await db
            .into(db.cycleEntries)
            .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)));
        final row = await db.entriesDao.entryFor(DateTime(2026, 3, 1));
        expect(
          row,
          isNotNull,
          reason: 'the day alone identifies the row (no profile dimension)',
        );
      },
    );

    test(
      'out-of-vocabulary mucus_sign is rejected by its CHECK constraint',
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
      },
    );

    test(
      'mucus_quality is engine-rejected with every sign other than s',
      () async {
        // Quality-requires-s, engine-level: every non-'s' storage token must
        // never carry a quality qualifier. Each case gets its own day so a
        // broken CHECK cannot hide behind a duplicate-key failure on a reused
        // day. ('fs' contains s but is its own sign, deliberately quality-free.)
        var day = 20000;
        for (final sign in MucusSign.values) {
          if (sign == MucusSign.s) continue;
          await expectLater(
            db.customStatement(
              "INSERT INTO cycle_entries (date, mucus_sign, "
              "mucus_quality) VALUES ($day, '${sign.name}', 'w')",
            ),
            throwsA(isA<Exception>()),
            reason:
                "'${sign.name}' is not the S sign — it never carries a quality",
          );
          day++;
        }
        // Quality with s but outside the quality vocabulary: rejected as well.
        await expectLater(
          db.customStatement(
            "INSERT INTO cycle_entries (date, mucus_sign, "
            "mucus_quality) VALUES ($day, 's', 'stretchy')",
          ),
          throwsA(isA<Exception>()),
        );
        // Sanity: s with an in-vocabulary quality goes through.
        await db.customStatement(
          "INSERT INTO cycle_entries (date, mucus_sign, "
          "mucus_quality) VALUES (${day + 1}, 's', 'ew')",
        );
      },
    );

    test('bleeding round-trips as each of the six levels', () async {
      for (final (index, level) in Bleeding.values.indexed) {
        final day = DateTime(2026, 6).add(Duration(days: index));
        await db.entriesDao.upsertDaily(DailyEntry(date: day, bleeding: level));
        final row = await db.entriesDao.entryFor(day);
        expect(
          row!.bleeding,
          level,
          reason:
              '${level.name} (level ${level.level}) must survive the '
              'db round trip by its stored number',
        );
      }
    });

    test('raw SQL INSERT stores integer levels that read back by level, not '
        'declaration order', () async {
      // Hand-written SQL (e.g. a future import path) stores the int directly:
      // the member must resolve by LEVEL — by declaration index, 4 would be
      // the wrong member entirely. Distinct days per case: on a reused day
      // a later insert could fail on UNIQUE instead of its own assertion,
      // masking which level actually misread.
      // Day 20000 = 2024-10-04; +n days per level n.
      const byLevel = <int, Bleeding>{4: Bleeding.heavy, 5: Bleeding.maximum};
      for (final MapEntry(:key, :value) in byLevel.entries) {
        await db.customStatement(
          'INSERT INTO cycle_entries (date, bleeding) '
          'VALUES (${20000 + key}, $key)',
        );
        final row = await db.entriesDao.entryFor(
          DateTime(2024, 10, 4 + key),
        ); // day 20000 + key
        expect(row!.bleeding, value);
      }

      // Writing a raw-read member back must store its level again.
      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2024, 10, 10), bleeding: Bleeding.maximum),
      );
      final raw = await db
          .customSelect('SELECT bleeding FROM cycle_entries WHERE date = 20006')
          .getSingle();
      expect(
        raw.data['bleeding'],
        5,
        reason: 'the converter writes the top level as integer 5',
      );
    });

    test(
      'bleeding is stored as the numeric level, never a string token',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 6, 15), bleeding: Bleeding.heavy),
        );
        final raw = await db
            .customSelect('SELECT bleeding FROM cycle_entries')
            .getSingle();
        expect(
          raw.data['bleeding'],
          Bleeding.heavy.level,
          reason:
              'the decided storage representation is the integer level '
              '(4), not a vocabulary name',
        );
      },
    );

    test('the engine-level bleeding CHECK rejects levels outside 0..5, raw SQL '
        'path', () async {
      // Raw SQL (e.g. a future import path) bypasses the Dart converter:
      // the column's own CHECK is what keeps an impossible level out of
      // the table.
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (date, bleeding) '
          'VALUES (20000, 6)',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO cycle_entries (date, bleeding) '
          'VALUES (20001, -1)',
        ),
        throwsA(isA<Exception>()),
      );
      // Sanity: every level of the shared 6-step scale goes through the
      // raw SQL path.
      for (final level in Bleeding.values) {
        await db.customStatement(
          'INSERT INTO cycle_entries (date, bleeding) '
          'VALUES (${20002 + level.level}, ${level.level})',
        );
        await expectLater(
          db.entriesDao.entryFor(DateTime(2024, 10, 6 + level.level)),
          completion(
            predicate<CycleEntry>((row) => row.bleeding.level == level.level),
          ),
        );
      }
    });

    test('an unknown stored level is surfaced as an error, not silently '
        'mapped', () async {
      // 6 is the smallest out-of-range level now that the scale tops out
      // at 5; anything above it must fail the same way. The engine CHECK
      // already rejects writing such a value (pinned above), so the pin
      // here is the converter itself: the fail-loud read side stays for
      // rows that could enter by another path — no graceful degradation,
      // ever.
      expect(
        () => const BleedingLevelConverter().fromSql(6),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => const BleedingLevelConverter().fromSql(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'epoch-day storage normalizes any time-of-day into the calendar day',
      () async {
        await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 3, 4)));
        // Same calendar day, other time-of-day: must hit the same row.
        final row = await db.entriesDao.entryFor(
          DateTime(2026, 3, 4, 17, 30).toUtc(),
        );
        expect(row, isNotNull);
        expect(row!.date.year, 2026);
        expect(row.date.month, 3);
        expect(row.date.day, 4);
      },
    );

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
  });

  group('app_settings key-value store', () {
    test(
      're-writing the same key replaces the value (one row per key)',
      () async {
        final dao = db.settingsDao;
        await dao.writeValue('themeMode', 'light');
        await dao.writeValue('themeMode', 'dark');

        final rows = await db.select(db.appSettings).get();
        expect(
          rows,
          hasLength(1),
          reason: 'the key is the primary key — an upsert, not a second row',
        );
        expect(rows.single.value, 'dark');
        expect(await dao.readValue('themeMode'), 'dark');
      },
    );

    test('deleteValue removes the row; an absent key reads as null', () async {
      await db.settingsDao.writeValue('locale', 'de');
      expect(await db.settingsDao.readValue('locale'), 'de');

      await db.settingsDao.deleteValue('locale');
      expect(await db.settingsDao.readValue('locale'), isNull);
      expect(await db.select(db.appSettings).get(), isEmpty);

      // Deleting a key that never existed must not throw.
      await db.settingsDao.deleteValue('neverWritten');
      expect(await db.settingsDao.readValue('neverWritten'), isNull);
    });

    test('distinct keys are independent rows', () async {
      final dao = db.settingsDao;
      await dao.writeValue('locale', 'en');
      await dao.writeValue('temperatureRange', '{"min":35.0,"max":39.0}');

      expect(await dao.readValue('locale'), 'en');
      expect(
        await dao.readValue('temperatureRange'),
        '{"min":35.0,"max":39.0}',
      );
      expect(await db.select(db.appSettings).get(), hasLength(2));
    });

    test('an empty key is rejected', () async {
      await expectLater(
        db.settingsDao.writeValue('', 'whatever'),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.select(db.appSettings).get(), isEmpty);
    });
  });

  group('EntriesDao.upsertByDate', () {
    test('inserts one row on the first write of a day', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(
          date: DateTime(2026, 3, 1),
        ).copyWith(bleeding: const Value(Bleeding.medium)),
      );
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(rows.single.bleeding, Bleeding.medium);
      expect(rows.single.createdAt, rows.single.updatedAt);
    });

    test('re-upsert keeps exactly one row, same id, replaces fields, keeps '
        'created_at and bumps updated_at', () async {
      final past = DateTime.utc(2020, 1, 1);
      final seededId = await db
          .into(db.cycleEntries)
          .insert(
            CycleEntriesCompanion.insert(
              date: DateTime(2026, 3, 1),
              bleeding: const Value(Bleeding.medium),
              bbtC: const Value(36.1),
              createdAt: Value(past),
              updatedAt: Value(past),
            ),
          );

      final seeded = (await db.entriesDao.entryFor(DateTime(2026, 3, 1)))!;

      final second = await db.entriesDao.upsertByDate(
        dailyEntryToCompanion(
          DailyEntry(
            date: DateTime(2026, 3, 1),
            bleeding: Bleeding.none,
            bbtC: 36.8,
            notes: 'changed',
          ),
        ),
      );

      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));

      expect(second.id, seededId);
      expect(second.bbtC, 36.8);
      expect(second.bleeding, Bleeding.none);
      expect(second.notes, 'changed');
      expect(second.createdAt, seeded.createdAt);
      expect(
        second.updatedAt.isAfter(seeded.updatedAt),
        isTrue,
        reason: 'the re-save bumps updated_at',
      );
    });

    test('a duplicate same-day insert that bypasses the upsert hits '
        'the unique index', () async {
      await db.entriesDao.upsertByDate(
        CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
      );
      await expectLater(
        db
            .into(db.cycleEntries)
            .insert(CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1))),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(await db.entriesDao.allEntries(), hasLength(1));
    });
  });

  group('EntriesDao round trip (drift <-> domain)', () {
    test(
      'upsertDaily stores every domain field and maps back identical',
      () async {
        final input = DailyEntry(
          date: DateTime(2026, 6, 15),
          bbtC: 36.55,
          bleeding: Bleeding.spotting,
          tempDisturbances:
              TempDisturbance.sp.bit |
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
          sexTimings: SexTiming.morning.bit | SexTiming.evening.bit,
          notes: 'Notiz am Rande.',
        );

        final stored = await db.entriesDao.upsertDaily(input);
        final mapped = dailyEntryFromDrift(stored);

        expect(mapped, input); // DailyEntry == compares all fields + same day
        expect(
          stored.cervixFirmness,
          'soft',
          reason: 'the firmness is stored as its TEXT enum-name token',
        );
        expect(
          stored.sexTimings,
          5,
          reason: 'the timings are stored as the INTEGER mask',
        );
        final rawMask = await db
            .customSelect('SELECT temp_disturbances FROM cycle_entries')
            .getSingle();
        expect(
          rawMask.data['temp_disturbances'],
          15,
          reason: 'the mask is stored as the INTEGER OR of the flag bits',
        );
        expect(stored.date.year, 2026);
        expect(stored.date.month, 6);
        expect(stored.date.day, 15);
      },
    );

    test(
      'a mixed disturbance mask round-trips as the raw INTEGER mask',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            tempDisturbances: TempDisturbance.alk.bit, // 4
          ),
        );
        await db.customStatement(
          'UPDATE cycle_entries SET temp_disturbances = 10', // a | kr = 2 | 8
        );
        final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
        expect(
          row.tempDisturbances,
          10,
          reason:
              'the engine stores the raw mask; the mapper reads '
              'verbatim — no per-bit conversion anywhere',
        );
      },
    );

    test('pain options B and M persist as separate boolean columns', () async {
      // Breast (B) set, Mittelschmerz (M) not: the two options are
      // independent per-day flags like the exclusion columns, not one
      // generic flag.
      final stored = await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 6, 15), painBreast: true),
      );
      final raw = await db
          .customSelect(
            'SELECT pain_breast, pain_mittelschmerz FROM cycle_entries',
          )
          .getSingle();
      expect(
        raw.data['pain_breast'],
        1,
        reason: 'B is stored as its own boolean column',
      );
      expect(
        raw.data['pain_mittelschmerz'],
        0,
        reason: 'M stays unset when only B was recorded',
      );
      final mapped = dailyEntryFromDrift(stored);
      expect(mapped.painBreast, isTrue);
      expect(mapped.painMittelschmerz, isFalse);
    });

    test(
      'explicit nulls are written on full replace (no stale values left)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            mucusSign: MucusSign.s,
            mucusQuality: MucusQuality.ew,
            cervixFirmness: CervixFirmness.halfSoft,
            sexTimings: 6,
            notes: 'old note',
          ),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 6, 15)),
        );

        final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
        expect(row.mucusQuality, isNull);
        expect(row.mucusSign, isNull);
        expect(row.cervixFirmness, isNull);
        expect(
          row.sexTimings,
          0,
          reason:
              'the mask column resets to its default 0, not to a stale '
              'value',
        );
        expect(row.notes, isNull);
      },
    );

    test(
      'measured time round-trips as minutes since midnight (or stays null)',
      () async {
        final measured = await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            bbtC: 36.4,
            measuredAtMinutes: 407, // 06:47
          ),
        );
        expect(measured.measuredAtMinutes, 407);
        final mapped = dailyEntryFromDrift(measured);
        expect(mapped.measuredAtMinutes, 407);

        final unmeasured = await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 6, 16), bbtC: 36.0),
        );
        expect(unmeasured.measuredAtMinutes, isNull);
      },
    );

    test('a time without a temperature stores null', () async {
      await db.entriesDao.upsertDaily(
        DailyEntry(
          date: DateTime(2026, 6, 15),
          measuredAtMinutes: 407, // 06:47
        ),
      );

      final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
      expect(row.bbtC, isNull);
      expect(
        row.measuredAtMinutes,
        isNull,
        reason:
            'the measurement time belongs to the temperature; a '
            'mucus-only day stores no time',
      );
    });

    test(
      'updating a day without a measured time clears it (full replace)',
      () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            bbtC: 36.4,
            measuredAtMinutes: 407,
          ),
        );
        // The replacement has no temperature either — the old time must not
        // survive as a stray value without its measurement.
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 6, 15)),
        );

        final row = (await db.entriesDao.entryFor(DateTime(2026, 6, 15)))!;
        expect(row.bbtC, isNull);
        expect(row.measuredAtMinutes, isNull);
      },
    );

    test(
      'S with quality round-trips through the stored tokens and the mapper',
      () async {
        final stored = await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 6, 15),
            mucusSign: MucusSign.s,
            mucusQuality: MucusQuality.gl,
          ),
        );
        final rawSign = await db
            .customSelect("SELECT mucus_sign, mucus_quality FROM cycle_entries")
            .getSingle();
        expect(
          rawSign.data['mucus_sign'],
          's',
          reason: 'TEXT token, not a glyph',
        );
        expect(rawSign.data['mucus_quality'], 'gl');

        final mapped = dailyEntryFromDrift(stored);
        expect(mapped.mucusSign, MucusSign.s);
        expect(mapped.mucusQuality, MucusQuality.gl);
      },
    );

    test(
      'mapper/guard drops a quality that arrived without the S sign',
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
      },
    );
    group('mucus sign A (Ausfluss) storage vocabulary', () {
      test(
        "'a' is accepted by the engine and round-trips as its token",
        () async {
          // Raw SQL write (e.g. a future import path) proves the column's CHECK
          // admits the new token.
          await db.customStatement(
            "INSERT INTO cycle_entries (date, mucus_sign) "
            "VALUES (20000, 'a')",
          );
          final row = await db.entriesDao.entryFor(
            DateTime(2024, 10, 4),
          ); // day 20000
          expect(row!.mucusSign, 'a');

          // The DAO write path stores the enum name, not a glyph.
          final stored = await db.entriesDao.upsertDaily(
            DailyEntry(date: DateTime(2026, 8, 5), mucusSign: MucusSign.a),
          );
          expect(stored.mucusSign, 'a', reason: 'TEXT token, not a glyph');
          expect(dailyEntryFromDrift(stored).mucusSign, MucusSign.a);
        },
      );
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
      final rows = await db.entriesDao.range(
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 8),
      );
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
      expect(events, [
        <CycleEntry>[],
      ], reason: 'initial snapshot of an empty table');

      await db.entriesDao.upsertDaily(
        DailyEntry(date: DateTime(2026, 1, 10), bleeding: Bleeding.spotting),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[1].length, 1);
      expect(events[1].single.bleeding, Bleeding.spotting);
      await sub.cancel();
    });
  });

  group('MarksDao', () {
    test(
      'addMark persists with default author user and lists per day',
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
      },
    );

    test('addMark is idempotent per (date, type)', () async {
      final a = await db.marksDao.addMark(
        DateTime(2026, 3, 12),
        MarkTypes.mucusPeakDay,
      );
      final b = await db.marksDao.addMark(
        DateTime(2026, 3, 12),
        MarkTypes.mucusPeakDay,
      );
      expect(
        a.id,
        b.id,
        reason:
            'the (date, mark_type) unique index makes the add a '
            'no-op',
      );
      expect(
        await db.marksDao.marksForDay(DateTime(2026, 3, 12)),
        hasLength(1),
      );
    });

    test('a duplicate (date, mark_type) insert bypassing addMark hits the '
        'unique index', () async {
      await db.marksDao.addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
      await expectLater(
        db
            .into(db.userMarks)
            .insert(
              UserMarksCompanion.insert(
                entryDate: DateTime(2026, 3, 12),
                markType: MarkTypes.mucusPeakDay,
              ),
            ),
        throwsA(isA<Exception>()), // UNIQUE constraint failed
      );
      expect(
        await db.marksDao.marksForDay(DateTime(2026, 3, 12)),
        hasLength(1),
      );
    });

    test('toggleMark adds then removes, reporting the new presence', () async {
      final date = DateTime(2026, 4, 9);
      expect(
        await db.marksDao.toggleMark(date, MarkTypes.mucusPeakDay),
        isTrue,
      );
      expect(await db.marksDao.marksForDay(date), hasLength(1));
      expect(
        await db.marksDao.toggleMark(date, MarkTypes.mucusPeakDay),
        isFalse,
      );
      expect(await db.marksDao.marksForDay(date), isEmpty);
    });

    test('deleteMark reports removed rows', () async {
      final date = DateTime(2026, 4, 10);
      await db.marksDao.addMark(date, MarkTypes.mucusPeakDay);
      expect(await db.marksDao.deleteMark(date, MarkTypes.mucusPeakDay), 1);
      expect(await db.marksDao.deleteMark(date, MarkTypes.mucusPeakDay), 0);
    });

    test(
      'custom open-vocabulary mark types are storable (future tools)',
      () async {
        final date = DateTime(2026, 4, 11);
        await db.marksDao.addMark(date, 'adhocFutureTool');
        final marks = await db.marksDao.marksForDay(date);
        expect(marks.single.markType, 'adhocFutureTool');
      },
    );
  });

  group('MarksDao <-> CycleMark round trip (mapper)', () {
    final day = DateTime(2026, 3, 12);

    test('toggleMark add/remove round-trips through the mapper', () async {
      final expected = CycleMark(date: day, type: CycleMarkTypes.mucusPeakDay);
      expect(await db.marksDao.toggleMark(day, expected.type), isTrue);

      final stored = (await db.marksDao.marksForDay(day)).single;
      expect(
        cycleMarkFromDrift(stored),
        expected,
        reason:
            'the stored row maps back to the domain mark the write '
            'was made from',
      );

      expect(await db.marksDao.toggleMark(day, expected.type), isFalse);
      expect(
        await db.marksDao.marksForDay(day),
        isEmpty,
        reason:
            'the removal is observable through the mapper too: no row, '
            'no domain mark',
      );
    });

    test(
      'the epoch-day converter normalizes any time-of-day into the day',
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
        expect(
          mapped.date.isUtc,
          isTrue,
          reason: 'domain dates are UTC midnight',
        );
        expect(mapped.date.hour, 0);
        expect(mapped.date.minute, 0);

        // Same calendar day from another timezone representation: same row,
        // no duplicate (uniqueness is on the normalized day).
        await db.marksDao.addMark(
          afternoon.toUtc().add(const Duration(hours: 2)),
          CycleMarkTypes.firstHigherMeasurement,
        );
        expect(await db.marksDao.marksForDay(day), hasLength(1));
      },
    );

    test(
      'companion helper writes every domain field and maps back identical',
      () async {
        final mark = CycleMark(
          date: day,
          type: 'adhocFutureTool',
          author: 'assist',
        );
        await db.into(db.userMarks).insert(cycleMarkToCompanion(mark));

        final stored = (await db.marksDao.marksForDay(day)).single;
        expect(cycleMarkFromDrift(stored), mark);
      },
    );

    test('the domain mark vocabulary mirrors the stored tokens', () {
      // The domain layer must never import lib/db, so the token strings are
      // duplicated into CycleMarkTypes — this test is the tripwire keeping
      // the two definitions in sync.
      expect(CycleMarkTypes.mucusPeakDay, MarkTypes.mucusPeakDay);
      expect(
        CycleMarkTypes.firstHigherMeasurement,
        MarkTypes.firstHigherMeasurement,
      );
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
        reason:
            'the removed legacy mark types must stay out of the '
            'vocabulary constants',
      );
    });

    test(
      'watchAll streams all marks as they are toggled (date-keyed)',
      () async {
        // Buffered events, not emit counting: the initial empty snapshot must
        // be observed BEFORE the write so its ordering stays meaningful (same
        // pattern as the watchRange test above).
        final events = <List<UserMark>>[];
        final sub = db.marksDao.watchAll().listen(events.add);
        addTearDown(sub.cancel);

        await Future<void>.delayed(Duration.zero);
        expect(events, [
          <UserMark>[],
        ], reason: 'initial snapshot of an empty mark table');

        final otherDay = DateTime(2026, 3, 13);
        await db.marksDao.addMark(
          otherDay,
          CycleMarkTypes.firstHigherMeasurement,
        );
        await db.marksDao.addMark(day, CycleMarkTypes.mucusPeakDay);
        await Future<void>.delayed(Duration.zero);

        // Content, not event counting: drift re-emits on ANY write to the
        // watched table, so the number of events is not a stable assertion —
        // the latest snapshot is.
        expect(
          events.last,
          hasLength(2),
          reason:
              'the stream carries the mark table with no profile '
              'dimension',
        );
        expect(
          [for (final m in events.last) m.markType],
          [CycleMarkTypes.mucusPeakDay, CycleMarkTypes.firstHigherMeasurement],
          reason: 'ordered by day, then type',
        );
        expect(
          events.last.first.entryDate.isBefore(events.last.last.entryDate),
          isTrue,
        );

        await db.marksDao.deleteMark(
          otherDay,
          CycleMarkTypes.firstHigherMeasurement,
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.last.single.markType, CycleMarkTypes.mucusPeakDay);
      },
    );
  });
}
