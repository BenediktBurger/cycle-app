// Shared data fixtures for the widget tests — the scenario data blocks the
// chart tests kept copy-pasting between files. Each fixture is a function
// (a fresh list per call) so a test can spread or filter it without leaking
// mutations into a shared static.
import 'dart:io';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';

/// The sample drip CSV export used as import input (the picker override
/// injects it, mirroring a real picked file).
final String sampleDripCsv = File(
  'test/fixtures/drip-export-sample.csv',
).readAsStringSync();

/// The shared evaluation scenario (used by the evaluation section of
/// test/cycle_chart_test.dart and cycle_mark_sheet_test.dart for the
/// write-through): days
/// 2026-09-06..16 with
///
///  - 9/6 (idx 0): the rise BEFORE the marked first higher — never a
///    candidate (R3), renders as an ordinary temperature dot;
///  - 9/7 (idx 1): a 7th-low day outside the six-low window -> no number;
///  - 9/8..9/13 (idx 2..7): the six low measurements, numbered 6..1 counting
///    back from the first higher;
///  - 9/9 (idx 3, 36.4): the HIGHEST of the six lows -> baseline 36.4;
///  - 9/12 (idx 6): mucus-peak mark;
///  - 9/14 (idx 8): first-higher mark (36.9) -> first candidate;
///  - 9/15 (idx 9): 36.9, 9/16 (idx 10): 37.0 (>= +0.2 K -> rule D).
List<DailyEntry> evaluationScenarioEntries() => [
  DailyEntry(date: DateTime.utc(2026, 9, 6), bbtC: 36.9),
  DailyEntry(date: DateTime.utc(2026, 9, 7), bbtC: 36.3),
  DailyEntry(date: DateTime.utc(2026, 9, 8), bbtC: 36.2),
  DailyEntry(date: DateTime.utc(2026, 9, 9), bbtC: 36.4),
  DailyEntry(date: DateTime.utc(2026, 9, 10), bbtC: 36.3),
  DailyEntry(date: DateTime.utc(2026, 9, 11), bbtC: 36.1),
  DailyEntry(date: DateTime.utc(2026, 9, 12), bbtC: 36.2),
  DailyEntry(date: DateTime.utc(2026, 9, 13), bbtC: 36.3),
  DailyEntry(date: DateTime.utc(2026, 9, 14), bbtC: 36.9),
  DailyEntry(date: DateTime.utc(2026, 9, 15), bbtC: 36.9),
  DailyEntry(date: DateTime.utc(2026, 9, 16), bbtC: 37.0),
];

/// The evaluation scenario's user marks: the mucus peak (9/12) LIES BEFORE
/// the first higher measurement (9/14), so the candidates render CIRCLED.
List<CycleMark> evaluationScenarioMarks() => [
  CycleMark(date: DateTime.utc(2026, 9, 12), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(
    date: DateTime.utc(2026, 9, 14),
    type: CycleMarkTypes.firstHigherMeasurement,
  ),
];

/// A long recorded range from 2026-01-01 — [count] days (60 = far too long
/// for one viewport, so the day window matters) in a repeating temperature
/// run; the repeating sequence lets tests verify WHICH day a window shows.
DateTime longRangeDay(int index) =>
    DateTime.utc(2026, 1, 1).add(Duration(days: index));

List<DailyEntry> longRangeEntries([int count = 60]) => [
  for (var i = 0; i < count; i++)
    DailyEntry(date: longRangeDay(i), bbtC: 36.4 + (i % 10) * 0.05),
];

/// Nine chart days covering one recorded fact per signal (the per-signal
/// rows fixture of the chart test's rows section):
///  0: temperature WITH a recorded measurement time (6:30)
///  1: bleeding light
///  2: bleeding spotting
///  3: bleeding heavy
///  4: mucus S with EW quality (+ Mittelschmerz when [withMittelschmerz])
///  5: cervix position low + firmness soft
///  6: sex at the START slot
///  7: breast pain
///  8: entry WITHOUT any facts (untracked-looking day, but recorded)
List<DailyEntry> nineDayRowsFixture({
  required DateTime Function(int index) day,
  required bool withMittelschmerz,
}) => [
  DailyEntry(date: day(0), bbtC: 36.5, measuredAtMinutes: 6 * 60 + 30),
  DailyEntry(date: day(1), bbtC: 36.6, bleeding: Bleeding.light),
  DailyEntry(date: day(2), bbtC: 36.7, bleeding: Bleeding.spotting),
  DailyEntry(date: day(3), bbtC: 36.4, bleeding: Bleeding.heavy),
  DailyEntry(
    date: day(4),
    bbtC: 36.5,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.ew,
    painMittelschmerz: withMittelschmerz,
  ),
  DailyEntry(
    date: day(5),
    bbtC: 36.8,
    cervixPosition: CervixPosition.low,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(date: day(6), bbtC: 37.0, sexTimings: SexTiming.start.bit),
  DailyEntry(date: day(7), bbtC: 36.9, painBreast: true),
  DailyEntry(date: day(8)),
];
