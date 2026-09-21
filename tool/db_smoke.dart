// Database + domain runtime smoke-verification (NOT part of the shipped
// test suite).
//
// Purpose: the drift NativeDatabase backend and lib/domain are pure Dart —
// this host-VM script executes the core assertions of
// test/db/cycle_database_test.dart and test/domain/*_test.dart quickly and
// with fewer moving parts than the test runner (handy when hunting failures;
// see CONTRIBUTING.md §4 for the Linux libsqlite3 prerequisite).
//
// Run from repo root:  ~/flutter/bin/dart run tool/db_smoke.dart
// (flutter analyze calls this production code; it is a CLT tool, prints are
// expected there — lint suppressed locally.)

// ignore_for_file: avoid_print

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/statistics.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/db/tables.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError('SMOKE FAIL: $label');
  print('ok   $label');
}

/// Deep list equality (the plain `==` on Lists is identity in Dart; the
/// flutter_test matchers do this under the hood for the real test suite).
bool eq(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x is List<Object?> && y is List<Object?>) {
      if (!eq(x, y)) return false;
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

Future<void> main() async {
  final db = CycleDatabase(NativeDatabase.memory());

  // --- schema & migration ---------------------------------------------
  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  final tableNames = tables.map((r) => r.data['name'] as String).toSet();
  check(
      tableNames.contains('cycle_entries') &&
          tableNames.contains('user_marks') &&
          !tableNames.contains('profiles'),
      'schema v9 is profile-free (no profiles table)');

  var rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, mucus_sign) '
        "VALUES (20000, 'wet')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'mucus_sign CHECK rejects out-of-vocabulary token');
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, mucus_sign, '
        "mucus_quality) VALUES (20003, 'fs', 'w')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, "mucus_quality CHECK rejects a quality on the 'fs' sign");
  // Sanity: in-vocabulary writes go through (S with a quality qualifier).
  await db.customStatement('INSERT INTO cycle_entries (date, mucus_sign, '
      "mucus_quality) VALUES (20001, 's', 'ew')");

  // temp_disturbances: the engine CHECK keeps the raw mask inside the
  // TempDisturbance vocabulary — exactly the 4 bits, so both 16 and any
  // negative fail; a row written without the field reads the default 0.
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, '
        'temp_disturbances) VALUES (20005, 16)');
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'temp_disturbances CHECK rejects masks above 15');
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, '
        'temp_disturbances) VALUES (20006, -1)');
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'temp_disturbances CHECK rejects negative masks');

  // cervix_firmness: the engine CHECK accepts exactly the CervixFirmness
  // enum-name tokens (or NULL) — nothing else gets in.
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, '
        "cervix_firmness) VALUES (20004, 'squishy')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'cervix_firmness CHECK rejects out-of-vocabulary token');

  // sex_timings: the engine CHECK keeps the mask inside the SexTiming
  // vocabulary — exactly the 3 bits, so both 8 and any negative fail.
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, sex_timings) '
        'VALUES (20007, 8)');
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'sex_timings CHECK rejects masks above 7');
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, sex_timings) '
        'VALUES (20008, -1)');
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'sex_timings CHECK rejects negative masks');

  // Sanity: the Ausfluss sign 'a' is in vocabulary — and carries NO quality
  // (the quality CHECK rejects any quality on a sign other than S).
  await db.customStatement('INSERT INTO cycle_entries (date, mucus_sign) '
      "VALUES (20009, 'a')");
  rejected = false;
  try {
    await db.customStatement('INSERT INTO cycle_entries (date, mucus_sign, '
        "mucus_quality) VALUES (20010, 'a', 'w')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'mucus_quality CHECK rejects a quality on the A sign');

  // A duplicate same-day insert that bypasses the upsert hits the (date)
  // unique index; so does a duplicate (entry_date, mark_type) mark insert.
  await db.entriesDao.upsertByDate(dailyEntryToCompanion(DailyEntry(
    date: DateTime(2026, 3, 1),
    bleeding: Bleeding.medium,
    bbtC: 36.1,
  )));
  rejected = false;
  try {
    await db.into(db.cycleEntries).insert(
          CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
        );
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'unique (date) index rejects duplicate entry insert');

  // --- EntriesDao upsert -----------------------------------------------
  final first =
      await db.entriesDao.upsertByDate(dailyEntryToCompanion(DailyEntry(
    date: DateTime(2026, 3, 1),
    bleeding: Bleeding.medium,
    bbtC: 36.1,
  )));
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  final second =
      await db.entriesDao.upsertByDate(dailyEntryToCompanion(DailyEntry(
    date: DateTime(2026, 3, 1),
    bleeding: Bleeding.none,
    bbtC: 36.8,
    notes: 'changed',
  )));
  // NOTE: the earlier mucus-CHECK probes inserted extra rows for other
  // days, so assert on the specific day's row count, not the whole table.
  final marFirstRows = (await db.entriesDao.allEntries())
      .where((r) => r.date.day == 1 && r.date.month == 3)
      .toList();
  check(marFirstRows.length == 1, 're-upsert keeps one row per day');
  check(second.id == first.id, 'upsert keeps the row id');
  check(second.bbtC == 36.8 && second.bleeding == Bleeding.none,
      'upsert fully replaces fields');
  check(!second.updatedAt.isBefore(second.createdAt),
      'updated_at >= created_at after replace');

  // --- daily round trip -------------------------------------------------
  final input = DailyEntry(
    date: DateTime(2026, 6, 15),
    bbtC: 36.55,
    bleeding: Bleeding.spotting,
    tempDisturbances: TempDisturbance.sp.bit |
        TempDisturbance.a.bit |
        TempDisturbance.alk.bit |
        TempDisturbance.kr.bit,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.gl,
    cervixPosition: CervixPosition.veryHigh,
    cervixOpening: CervixOpening.open,
    painBreast: true,
    painMittelschmerz: true,
    cervixFirmness: CervixFirmness.halfSoft,
    sexTimings: SexTiming.start.bit | SexTiming.end.bit,
    notes: 'Notiz am Rande.',
  );
  final mappedBack =
      dailyEntryFromDrift(await db.entriesDao.upsertDaily(input));
  check(mappedBack == input, 'domain round trip via drift preserves entry');
  // The Muttermund options are stored as their TEXT enum-name tokens (the
  // masks as the raw INTEGER OR of the flag bits).
  final cervixTokens = await db.customSelect(
      'SELECT cervix_position, cervix_opening, cervix_firmness, '
      'sex_timings, temp_disturbances FROM cycle_entries WHERE date = ?',
      variables: [
        Variable.withInt(DateOnly.normalize(DateTime(2026, 6, 15))
            .difference(DateTime.utc(1970))
            .inDays)
      ]).getSingle();
  check(cervixTokens.data['cervix_position'] == 'veryHigh',
      'raw cervix_position token is the enum name');
  check(cervixTokens.data['cervix_opening'] == 'open',
      'raw cervix_opening token is the enum name');
  check(cervixTokens.data['cervix_firmness'] == 'halfSoft',
      'raw cervix_firmness token is the enum name');
  check(
      cervixTokens.data['sex_timings'] ==
          SexTiming.start.bit | SexTiming.end.bit,
      'raw sex_timings is the SexTiming bitmask');
  check(cervixTokens.data['temp_disturbances'] == 15,
      'raw temp_disturbances is the TempDisturbance mask');

  // --- bleeding levels: all six levels round-trip the drift layer --------
  // The stored number is Bleeding.level (0 none … 5 maximum), mapped through
  // the converter — never the Dart declaration index.
  for (var i = 0; i < Bleeding.values.length; i++) {
    final level = Bleeding.values[i];
    final row = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
      DailyEntry(date: DateTime(2026, 7, 1 + i), bleeding: level),
    ));
    check(row.bleeding == level,
        'level ${level.level} round-trips as ${level.name}');
  }
  // Raw SQL writes the int directly; the converter must surface exactly the
  // level it names.
  final heavyDay = DateOnly.normalize(DateTime(2026, 7, 5))
      .difference(DateTime.utc(1970))
      .inDays;
  final rawHeavy = await db.customSelect(
      'SELECT bleeding FROM cycle_entries WHERE date = ?',
      variables: [Variable.withInt(heavyDay)]).getSingle();
  check(rawHeavy.data['bleeding'] == 4,
      'raw stored bleeding value is the numeric level (4 for heavy)');
  await db.customStatement(
    'INSERT INTO cycle_entries (date, bleeding) VALUES (?, ?)',
    // A free day beyond the six loop days above.
    [heavyDay + 7, 3],
  );
  final rawMedium = await db.customSelect(
      'SELECT bleeding FROM cycle_entries WHERE date = ?',
      variables: [Variable.withInt(heavyDay + 7)]).getSingle();
  check(rawMedium.data['bleeding'] == 3,
      'raw int insert (3) is stored verbatim in the int column');

  // --- MarksDao ----------------------------------------------------------
  final mark =
      await db.marksDao.addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
  check(mark.author == 'user', 'mark default author is user');
  final again =
      await db.marksDao.addMark(DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
  check(mark.id == again.id, 'addMark is idempotent per (date, type)');
  check(
    await db.marksDao
        .toggleMark(DateTime(2026, 4, 9), MarkTypes.ignoreTemperature),
    'toggleMark adds',
  );
  check(
    !await db.marksDao
        .toggleMark(DateTime(2026, 4, 9), MarkTypes.ignoreTemperature),
    'toggleMark removes',
  );

  // --- cycle grouping ------------------------------------------------------
  DailyEntry d(int y, int m, int day,
      {Bleeding bleeding = Bleeding.none, int tempDisturbances = 0}) {
    return DailyEntry(
      date: DateTime(y, m, day),
      bleeding: bleeding,
      tempDisturbances: tempDisturbances,
    );
  }

  // Cycle grouping is MARK-driven: a cycleStart mark opens a group wherever
  // it sits; bleeding alone (spotting included) never creates a boundary.
  List<CycleMark> starts(List<(int, int, int)> days) => [
        for (final (y, m, dd) in days)
          CycleMark(date: DateTime(y, m, dd), type: MarkTypes.cycleStart),
      ];

  final entries = [
    d(2026, 3, 2, bleeding: Bleeding.medium),
    d(2026, 3, 3, bleeding: Bleeding.medium),
    d(2026, 3, 4),
    d(2026, 3, 30, bleeding: Bleeding.medium),
    d(2026, 4, 10, bleeding: Bleeding.spotting),
    d(2026, 4, 27, bleeding: Bleeding.medium),
    d(2026, 4, 28),
  ];

  final marks = starts([(2026, 3, 2), (2026, 3, 30), (2026, 4, 27)]);
  final cycles = groupIntoCycles(entries, marks);
  check(cycles.length == 3, 'three cycles grouped at the cycleStart marks');
  check(cycles.every((c) => c.startsAtMenstruation),
      'all cycles opened by marks');
  check(
    eq(menstruationOnsetDates(entries, marks).map((e) => e.day).toList(),
        [2, 30, 27]),
    'onsets: the cycleStart marks anchor the starts',
  );

  // Without marks the bleeding sequence is ONE leading group.
  check(
    groupIntoCycles(entries, const []).length == 1,
    'bleeding alone never opens a group (one group without marks)',
  );

  // A mark on an untracked gap day opens the group at the next tracked day.
  final gapEntries = [d(2026, 3, 1), d(2026, 3, 5)];
  final gapCycles = groupIntoCycles(gapEntries, starts([(2026, 3, 3)]));
  check(
    gapCycles.length == 2 &&
        gapCycles[1].startDate.day == 5 &&
        gapCycles[1].startsAtMenstruation,
    'a mark in an untracked gap opens at the next tracked day',
  );

  // Suggestion suppression is keyed PURELY to bleeding continuity
  // (temperature-only semantics): raw disturbance flags and the
  // ignoreTemperature mark are both invisible to the predicate.
  check(
    isSuggestedCycleStart(
      d(2026, 4, 1, bleeding: Bleeding.medium, tempDisturbances: 15),
      null,
    ),
    'raw disturbance flags never reach the suggestion predicate',
  );
  check(
    isSuggestedCycleStart(d(2026, 4, 1, bleeding: Bleeding.medium), null),
    'an ignoreTemperature-marked day still suggests a cycle start',
  );

  // --- statistics ---------------------------------------------------------
  // The marked starts (3 onsets within the entry range) -> 2 lengths; add a
  // 4th mark to exercise the third interval (mirrors threeCycleData in the
  // test suite).
  final statsEntries = [...entries, d(2026, 5, 25, bleeding: Bleeding.medium)];
  final statsMarks =
      starts([(2026, 3, 2), (2026, 3, 30), (2026, 4, 27), (2026, 5, 25)]);
  final lengths = cycleLengthsInDays(statsEntries, statsMarks);
  check(eq(lengths, [28, 28, 28]), 'cycle lengths 28/28/28 ($lengths)');
  final summary = summarizeCycleLengths(lengths);
  check(
      (summary.average! - 28.0).abs() < 0.0001 &&
          summary.shortest == 28 &&
          summary.longest == 28,
      'summary scalars');
  check(summarizeCycleLengths(const []).average == null, 'empty summary nulls');

  final buckets = cycleLengthDistribution(const [
    18,
    21,
    25,
    26,
    30,
    31,
    36,
    40,
    41,
    45,
  ]);
  final byLabel = {for (final b in buckets) b.label: b.count};
  check(
      byLabel['<=20'] == 1 &&
          byLabel['21-25'] == 2 &&
          byLabel['26-30'] == 2 &&
          byLabel['31-35'] == 1 &&
          byLabel['36-40'] == 2 &&
          byLabel['41+'] == 2,
      'distribution bucket counts');
  check(cycleLengthDistribution(const []).every((b) => b.count == 0),
      'empty distribution all-zero');

  await db.close();
  print('\nAll runtime smoke checks passed.');
}
