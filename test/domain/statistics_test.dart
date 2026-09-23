// Domain tests: statistics arithmetic. NO fertility interpretation —
// lengths, averages, and histograms only (see lib/domain/statistics.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/statistics.dart';

import 'mark_fixtures.dart';
import '../support/fixtures.dart' show evaluationScenarioEntries;

DailyEntry d(
  int year,
  int month,
  int day, {
  Bleeding bleeding = Bleeding.none,
}) {
  return DailyEntry(date: DateTime(year, month, day), bleeding: bleeding);
}

// start/excludedDay: the shared domain mark fixtures (mark_fixtures.dart).

/// A user-placed mucus-peak mark on (year, month, day) — the statistics
/// layer only consumes it to pick the earliest candidate strictly after the
/// peak (never as a fertility statement).
CycleMark mucusPeak(int year, int month, int day) => CycleMark(
  date: DateTime(year, month, day),
  type: CycleMarkTypes.mucusPeakDay,
);

/// A user-placed first-higher-measurement mark on (year, month, day).
CycleMark firstHigher(int year, int month, int day) => CycleMark(
  date: DateTime(year, month, day),
  type: CycleMarkTypes.firstHigherMeasurement,
);

/// Three clean cycles: marked starts Mar 2 / Mar 30 / Apr 27 / May 25.
/// Consecutive lengths: 28, 28, 28.
List<DailyEntry> threeCycleData() => [
  d(2026, 3, 2, bleeding: Bleeding.medium),
  d(2026, 3, 3, bleeding: Bleeding.medium),
  d(2026, 3, 4),
  d(2026, 3, 30, bleeding: Bleeding.medium),
  d(2026, 4, 1),
  d(2026, 4, 10, bleeding: Bleeding.spotting),
  d(2026, 4, 27, bleeding: Bleeding.medium),
  d(2026, 5, 1),
  d(2026, 5, 25, bleeding: Bleeding.medium),
  d(2026, 5, 26, bleeding: Bleeding.medium),
];

List<CycleMark> threeCycleStarts() => [
  start(2026, 3, 2),
  start(2026, 3, 30),
  start(2026, 4, 27),
  start(2026, 5, 25),
];

void main() {
  group('cycleLengthsInDays', () {
    test('counts days between consecutive marked cycle starts', () {
      expect(cycleLengthsInDays(threeCycleData(), threeCycleStarts()), [
        28,
        28,
        28,
      ]);
    });

    test('lengths are mark-driven, not bleeding-driven', () {
      // The old rule split at menstruation-level bleeding onsets; now only
      // the user-placed cycleStart marks anchor the lengths — the bleeding
      // pattern below would have produced different boundaries. (Raw
      // disturbance flags on the middle day would not matter either:
      // statistics are purely mark-driven.)
      final entries = [
        d(2026, 4, 1, bleeding: Bleeding.medium),
        DailyEntry(date: DateTime(2026, 4, 28), bleeding: Bleeding.medium),
        d(2026, 4, 29, bleeding: Bleeding.medium),
      ];
      // Marks on Apr 1 and Apr 29: a single length from Apr 1 to Apr 29.
      expect(
        cycleLengthsInDays(entries, [start(2026, 4, 1), start(2026, 4, 29)]),
        [28],
      );
      // Without marks there are no boundaries and no lengths at all.
      expect(cycleLengthsInDays(entries, const []), isEmpty);
    });

    test('a mark in an untracked gap anchors the length at the mark date', () {
      final entries = [
        d(2026, 3, 1),
        // Mar 2–3 untracked — the Mar 2 mark sits INSIDE the gap.
        for (var day = 4; day <= 12; day++) d(2026, 3, day),
        // Tracked days around the second mark, so the next cycle exists.
        d(2026, 4, 3),
        d(2026, 4, 4),
        d(2026, 4, 5),
      ];
      // The last mark has NO tracked day on/after it: it opens no group and
      // contributes neither an onset nor a length.
      final marks = [start(2026, 3, 2), start(2026, 4, 4), start(2026, 6, 1)];

      // Length = mark date to mark date: Mar 2 → Apr 4 = 33 days, even
      // though the first tracked day of the cycle is Mar 4.
      expect(cycleLengthsInDays(entries, marks), [33]);
      // The onsets are the mark dates themselves (the Mar 2 onset is an
      // untracked gap day).
      expect(menstruationOnsetDates(entries, marks), [
        DateOnly.normalize(DateTime(2026, 3, 2)),
        DateOnly.normalize(DateTime(2026, 4, 4)),
      ]);
    });

    test('a mark on an excluded day anchors a length too', () {
      final entries = [
        d(2026, 4, 1, bleeding: Bleeding.medium),
        DailyEntry(date: DateTime(2026, 4, 28), bleeding: Bleeding.medium),
        d(2026, 4, 29, bleeding: Bleeding.medium),
      ];
      // The Apr 28 mark sits on an EXCLUDED day (the analysis exclusion is
      // the ignoreTemperature mark — raw flags do not exclude); the
      // cycle-start mark binds wherever placed (no exclusion interplay),
      // so it anchors a length.
      final lengths = cycleLengthsInDays(entries, [
        start(2026, 4, 1),
        excludedDay(2026, 4, 28),
        start(2026, 4, 28),
        start(2026, 4, 29),
      ]);
      expect(lengths, [27, 1]);
    });

    test('incomplete trailing cycle contributes no length', () {
      final entries = [
        d(2026, 1, 5, bleeding: Bleeding.medium),
        d(2026, 2, 2, bleeding: Bleeding.medium),
        // no known next start: cycle 2 is open-ended
      ];
      expect(
        cycleLengthsInDays(entries, [start(2026, 1, 5), start(2026, 2, 2)]),
        [28],
      );
    });

    test('no marks -> no lengths', () {
      expect(cycleLengthsInDays([d(2026, 1, 1)], const []), isEmpty);
      expect(cycleLengthsInDays(const [], const []), isEmpty);
    });
  });

  group('summarizeCycleLengths', () {
    test('average, min, max over the length list', () {
      final summary = summarizeCycleLengths(const [26, 28, 30, 28]);
      expect(summary.lengths, [26, 28, 30, 28]);
      expect(summary.average, closeTo(28.0, 0.0001));
      expect(summary.shortest, 26);
      expect(summary.longest, 30);
    });

    test('empty input yields null scalars without throwing', () {
      final summary = summarizeCycleLengths(const []);
      expect(summary.lengths, isEmpty);
      expect(summary.average, isNull);
      expect(summary.shortest, isNull);
      expect(summary.longest, isNull);
    });

    test('integrated with grouping: three clean cycles', () {
      final lengths = cycleLengthsInDays(threeCycleData(), threeCycleStarts());
      final summary = summarizeCycleLengths(lengths);
      expect(summary.lengths, [28, 28, 28]);
      expect(summary.average, closeTo(28, 0.0001));
      expect(summary.shortest, 28);
      expect(summary.longest, 28);
    });
  });

  group('cycleLengthDistribution', () {
    test('counts lengths into the fixed buckets', () {
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
      final byLabel = <String, int>{for (final b in buckets) b.label: b.count};
      expect(byLabel['<=20'], 1); // 18
      expect(byLabel['21-25'], 2); // 21, 25
      expect(byLabel['26-30'], 2); // 26, 30
      expect(byLabel['31-35'], 1); // 31
      expect(byLabel['36-40'], 2); // 36, 40
      expect(byLabel['41+'], 2); // 41, 45
    });

    test('all buckets are returned even when empty', () {
      final buckets = cycleLengthDistribution(const [28]);
      expect(buckets.map((b) => b.count), containsAll([1]));
      final total = buckets.fold<int>(0, (sum, b) => sum + b.count);
      expect(total, 1);
    });

    test('empty input -> all counts zero', () {
      final buckets = cycleLengthDistribution(const []);
      for (final b in buckets) {
        expect(b.count, 0);
      }
    });
  });

  group('cycleFacts', () {
    test('one fact per mark-opened cycle: start, bleeding days, length', () {
      final facts = cycleFacts(threeCycleData(), threeCycleStarts());
      expect(facts, hasLength(4));

      expect(facts[0].cycleStart, DateTime.utc(2026, 3, 2));
      expect(facts[0].bleedingDays, 2); // Mar 2 + Mar 3
      expect(facts[0].lengthDays, 28);

      // The spotting day on Apr 10 counts as a bleeding day as well
      // TODO(user-review): level >= 1 (spotting included) is a flagged
      // owner decision pending confirmation with INER experts.
      expect(facts[1].cycleStart, DateTime.utc(2026, 3, 30));
      expect(facts[1].bleedingDays, 2); // Mar 30 + Apr 10 spotting
      expect(facts[1].lengthDays, 28);

      expect(facts[2].cycleStart, DateTime.utc(2026, 4, 27));
      expect(facts[2].bleedingDays, 1); // Apr 27
      expect(facts[2].lengthDays, 28);

      // Trailing cycle: bleeding days are counted, length stays null.
      expect(facts[3].cycleStart, DateTime.utc(2026, 5, 25));
      expect(facts[3].bleedingDays, 2); // May 25 + May 26
      expect(facts[3].lengthDays, isNull);
    });

    test('the leading pre-mark group produces no fact', () {
      final entries = [
        d(2026, 1, 5, bleeding: Bleeding.medium),
        d(2026, 1, 6, bleeding: Bleeding.medium),
        ...threeCycleData(),
      ];
      final facts = cycleFacts(entries, threeCycleStarts());
      expect(facts, hasLength(4));
      expect(facts.first.cycleStart, DateTime.utc(2026, 3, 2));
    });

    test('first higher facts are null without first-higher marks', () {
      final facts = cycleFacts(threeCycleData(), threeCycleStarts());
      for (final fact in facts) {
        expect(fact.firstHigherDay, isNull);
        expect(fact.firstHigherUntilCycleEndDays, isNull);
      }
    });

    test('marked first-higher day (no peak) is the fallback truth', () {
      // No mucus peak and no measured temperatures in the low window: no
      // candidates can exist, so the user-placed mark day IS the first
      // higher fact (arithmetic fallback, no interpretation).
      final facts = cycleFacts(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
      ]);
      expect(facts[0].firstHigherDay, DateTime.utc(2026, 3, 20));
      // Cycle end exclusive is the next start (Mar 30): Mar 30 - Mar 20.
      expect(facts[0].firstHigherUntilCycleEndDays, 10);
      // The other cycles are untouched.
      expect(facts[1].firstHigherDay, isNull);
      expect(facts[3].firstHigherDay, isNull);
    });

    test('the earliest candidate strictly after the mucus peak wins over '
        'the marked day', () {
      // The shared evaluation scenario (test/support/fixtures.dart),
      // September 2026, with a cycle-start mark on its first tracked day:
      // the first-higher MARK sits on Sep 14 BEFORE the peak on Sep 15, so
      // the first candidate is an arrow; the earliest CIRCLE (a candidate
      // strictly after the peak) is Sep 16 — the resolved first higher.
      final facts = cycleFacts(evaluationScenarioEntries(), [
        start(2026, 9, 6),
        mucusPeak(2026, 9, 15),
        firstHigher(2026, 9, 14),
      ]);
      expect(facts, hasLength(1));
      expect(facts.single.cycleStart, DateTime.utc(2026, 9, 6));
      expect(facts.single.firstHigherDay, DateTime.utc(2026, 9, 16));
      // Trailing cycle: end exclusive is one day past the last tracked
      // day (Sep 16), so the first higher until the cycle end is 1 day
      // (Sep 16 itself, inclusively counted).
      expect(facts.single.firstHigherUntilCycleEndDays, 1);
      // The scenario carries no bleeding: zero bleeding days.
      expect(facts.single.bleedingDays, 0);
    });
  });

  group('cycleStatistics', () {
    test('no cycles -> empty aggregates without throwing', () {
      final stats = cycleStatistics(const [], const []);
      expect(stats.facts, isEmpty);
      expect(stats.cycleCount, 0);
      expect(stats.cycleLengths.min, isNull);
      expect(stats.cycleLengths.max, isNull);
      expect(stats.cycleLengths.average, isNull);
      expect(stats.cycleLengths.stdDev, isNull);
      expect(stats.bleedingDays.average, isNull);
      expect(stats.firstHigherUntilCycleEnd.average, isNull);
      expect(stats.earliestFirstHigherDayOfCycle, isNull);
    });

    test('aggregates min/max/avg/population std over the three metrics', () {
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
      ]);
      expect(stats.cycleCount, 4);

      // Lengths [28, 28, 28] (the trailing cycle contributes none).
      expect(stats.cycleLengths.min, 28);
      expect(stats.cycleLengths.max, 28);
      expect(stats.cycleLengths.average, closeTo(28.0, 0.0001));
      expect(stats.cycleLengths.stdDev, closeTo(0.0, 0.0001));

      // Bleeding days [2, 2, 1, 2]: population std = sqrt(0.1875).
      expect(stats.bleedingDays.min, 1);
      expect(stats.bleedingDays.max, 2);
      expect(stats.bleedingDays.average, closeTo(1.75, 0.0001));
      expect(stats.bleedingDays.stdDev, closeTo(0.4330127, 0.0001));

      // First higher until cycle end: only cycle 1 has one (10 days).
      expect(stats.firstHigherUntilCycleEnd.min, 10);
      expect(stats.firstHigherUntilCycleEnd.max, 10);
      expect(stats.firstHigherUntilCycleEnd.average, closeTo(10.0, 0.0001));
      expect(stats.firstHigherUntilCycleEnd.stdDev, closeTo(0.0, 0.0001));

      // Earliest first higher as 1-based day-of-cycle: Mar 20 is offset 18
      // from the Mar 2 start, so the chart-convention day number is 19.
      expect(stats.earliestFirstHigherDayOfCycle, 19);
    });

    test('earliest first higher prefers the smallest day-of-cycle offset', () {
      // Cycle 1: mark Mar 20 (day 20); cycle 3 (Apr 27..): mark May 1
      // (offset 4, day 5) — the fifth day wins.
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
        firstHigher(2026, 5, 1),
      ]);
      expect(stats.earliestFirstHigherDayOfCycle, 5);
    });

    test('day-of-cycle numbers match the chart convention (1-based)', () {
      // The chart's day-of-cycle number for the first higher mark day:
      // daysBetween(mark, cycleStart) + 1 — here Mar 2..Mar 20 = 19 days.
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
      ]);
      expect(
        DateOnly.daysBetween(
          DateTime.utc(2026, 3, 20),
          DateTime.utc(2026, 3, 2),
        ),
        18,
      );
      expect(stats.earliestFirstHigherDayOfCycle, 19);
    });
  });
}
