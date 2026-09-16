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

import 'package:cycle_app/domain/cycle_grouping.dart';
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
  final profiles = await db.profilesDao.allProfiles();
  check(profiles.length == 1 && profiles.single.name == 'main',
      'seeds exactly one profile named main');

  var rejected = false;
  try {
    await db.customStatement(
        'INSERT INTO cycle_entries (profile_id, date, mucus_sign) '
        "VALUES (1, 20000, 'wet')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'mucus_sign CHECK rejects out-of-vocabulary token');
  rejected = false;
  try {
    await db.customStatement(
        'INSERT INTO cycle_entries (profile_id, date, mucus_sign, '
        "mucus_quality) VALUES (1, 20003, 'f', 'w')");
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'mucus_quality CHECK rejects quality without the S sign');
  // Sanity: in-vocabulary writes go through (S with a quality qualifier).
  await db.customStatement(
      'INSERT INTO cycle_entries (profile_id, date, mucus_sign, '
      "mucus_quality) VALUES (1, 20001, 's', 'ew')");

  rejected = false;
  try {
    await db.into(db.cycleEntries).insert(
          CycleEntriesCompanion.insert(
            date: DateTime(2026, 3, 1),
            profileId: const Value(99),
          ),
        );
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'foreign key rejects unknown profile');

  // --- EntriesDao upsert -----------------------------------------------
  final first = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
    DailyEntry(
      date: DateTime(2026, 3, 1),
      bleeding: Bleeding.medium,
      bbtC: 36.1,
    ),
  ));
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  final second = await db.entriesDao.upsertByDate(dailyEntryToCompanion(
    DailyEntry(
      date: DateTime(2026, 3, 1),
      bleeding: Bleeding.none,
      bbtC: 36.8,
      notes: 'changed',
    ),
  ));
  // NOTE: the earlier mucus-CHECK probe inserted an extra row for another
  // day, so assert on the specific day's row count, not the whole table.
  final marFirstRows = (await db.entriesDao.allEntries(1))
      .where((r) => r.date.day == 1 && r.date.month == 3)
      .toList();
  check(marFirstRows.length == 1, 're-upsert keeps one row per day');
  check(second.id == first.id, 'upsert keeps the row id');
  check(second.bbtC == 36.8 && second.bleeding == Bleeding.none,
      'upsert fully replaces fields');
  check(!second.updatedAt.isBefore(second.createdAt),
      'updated_at >= created_at after replace');

  rejected = false;
  try {
    await db.into(db.cycleEntries).insert(
          CycleEntriesCompanion.insert(date: DateTime(2026, 3, 1)),
        );
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'unique (profile,date) index rejects duplicate insert');

  // --- daily round trip -------------------------------------------------
  final input = DailyEntry(
    date: DateTime(2026, 6, 15),
    bbtC: 36.55,
    bleeding: Bleeding.spotting,
    excludeIllness: true,
    excludeAlcohol: true,
    excludeTravel: true,
    excludeOther: true,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.gl,
    cervix: 'closed, low',
    pain: true,
    mood: true,
    desire: true,
    sex: true,
    notes: 'Notiz am Rande.',
  );
  final mappedBack =
      dailyEntryFromDrift(await db.entriesDao.upsertDaily(input));
  check(mappedBack == input, 'domain round trip via drift preserves entry');

  // --- MarksDao ----------------------------------------------------------
  final mark = await db.marksDao
      .addMark(1, DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
  check(mark.author == 'user', 'mark default author is user');
  final again = await db.marksDao
      .addMark(1, DateTime(2026, 3, 12), MarkTypes.mucusPeakDay);
  check(mark.id == again.id, 'addMark is idempotent');
  check(
      await db.marksDao.toggleMark(1, DateTime(2026, 4, 9), MarkTypes.baseline),
      'toggleMark adds');
  check(
      !await db.marksDao
          .toggleMark(1, DateTime(2026, 4, 9), MarkTypes.baseline),
      'toggleMark removes');

  // --- cycle grouping ------------------------------------------------------
  DailyEntry d(int y, int m, int day,
      {Bleeding bleeding = Bleeding.none, bool interrupted = false}) {
    return DailyEntry(
      date: DateTime(y, m, day),
      bleeding: bleeding,
      excludeIllness: interrupted && bleeding == Bleeding.medium,
      excludeTravel: interrupted && bleeding != Bleeding.medium,
    );
  }

  final entries = [
    d(2026, 3, 2, bleeding: Bleeding.medium),
    d(2026, 3, 3, bleeding: Bleeding.medium),
    d(2026, 3, 4),
    d(2026, 3, 30, bleeding: Bleeding.medium),
    d(2026, 4, 10, bleeding: Bleeding.spotting),
    d(2026, 4, 27, bleeding: Bleeding.medium),
    d(2026, 4, 28),
  ];
  final cycles = groupIntoCycles(entries);
  check(cycles.length == 3, 'three cycles grouped');
  check(cycles.every((c) => c.startsAtMenstruation), 'all cycles bounded');
  check(
    eq(menstruationOnsetDates(entries).map((e) => e.day).toList(), [2, 30, 27]),
    'onsets: spotting day is NOT a boundary (${menstruationOnsetDates(entries)})',
  );

  // interrupted period day does not start a cycle
  final interrupted = [
    d(2026, 4, 1, bleeding: Bleeding.medium),
    d(2026, 4, 29, bleeding: Bleeding.medium, interrupted: true),
    d(2026, 4, 30, bleeding: Bleeding.medium),
  ];
  check(
    menstruationOnsetDates(interrupted).length == 2 &&
        menstruationOnsetDates(interrupted)[1].day == 30,
    'excluded bleeding day does not start a cycle',
  );

  // --- statistics ---------------------------------------------------------
  // 28-day entries have 3 onsets -> 2 interval lengths; add a 4th onset to
  // exercise the third interval (mirrors threeCycleData in the test suite).
  final statsEntries = [...entries, d(2026, 5, 25, bleeding: Bleeding.medium)];
  final lengths = cycleLengthsInDays(statsEntries);
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
