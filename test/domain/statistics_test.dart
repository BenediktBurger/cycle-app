// Domain tests: statistics arithmetic. NO fertility interpretation —
// lengths, averages, and histograms only (see lib/domain/statistics.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
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
  double? bbtC,
}) {
  return DailyEntry(
    date: DateTime(year, month, day),
    bleeding: bleeding,
    bbtC: bbtC,
  );
}

// start/excludedDay: the shared domain mark fixtures (mark_fixtures.dart).

/// A user-placed mucus-peak mark on (year, month, day).
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
      // The last mark has NO tracked day on/after it: under the span rule
      // it opens its own DATA-LESS cycle, so the interval from the previous
      // marked start (Apr 4) to it IS a counted length (that cycle really
      // ended at the fresh mark).
      final marks = [start(2026, 3, 2), start(2026, 4, 4), start(2026, 6, 1)];

      // Length = mark date to mark date: Mar 2 → Apr 4 = 33 days, even
      // though the first tracked day of the cycle is Mar 4; Apr 4 → Jun 1
      // = 58 days into the fresh, data-less cycle.
      expect(cycleLengthsInDays(entries, marks), [33, 58]);
      // The onsets are the mark dates themselves (the Mar 2 onset is an
      // untracked gap day; the Jun 1 onset is the data-less fresh mark).
      expect(menstruationOnsetDates(entries, marks), [
        DateOnly.normalize(DateTime(2026, 3, 2)),
        DateOnly.normalize(DateTime(2026, 4, 4)),
        DateOnly.normalize(DateTime(2026, 6, 1)),
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

    test('a data-less trailing cycle observes no end — the fact row keeps '
        'its start and mark day, the span facts stay null', () {
      // The fresh May 10 mark opens a cycle with no tracked day after it;
      // its first-higher MARK still resolves (May 15), but with no last
      // tracked day there is no observed end to count the span against.
      final entries = [d(2026, 3, 2, bleeding: Bleeding.medium), d(2026, 3, 3)];
      final facts = cycleFacts(entries, [
        start(2026, 3, 2),
        start(2026, 5, 10),
        firstHigher(2026, 5, 15),
      ]);
      expect(facts, hasLength(2));
      expect(facts[1].cycleStart, DateTime.utc(2026, 5, 10));
      expect(facts[1].firstHigherDay, DateTime.utc(2026, 5, 15));
      expect(facts[1].lengthDays, isNull);
      expect(facts[1].firstHigherUntilCycleEndDays, isNull);
      expect(facts[1].bleedingDays, 0);
    });

    test('the cycle before a data-less FRESH mark counts its span to the '
        'fresh mark', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 30),
        d(2026, 3, 31, bbtC: 36.8),
      ];
      final marks = [
        start(2026, 3, 2),
        start(2026, 3, 30),
        start(2026, 5, 10),
        firstHigher(2026, 3, 5),
        firstHigher(2026, 3, 31),
      ];
      final facts = cycleFacts(entries, marks);
      // Cycle 2: rise Mar 31, the fresh May 10 start is its observed
      // cycle end exclusive -> Mar 31..May 9 inclusive = 40 days.
      expect(facts[1].firstHigherUntilCycleEndDays, 40);
      // The fresh data-less cycle itself: no rise, no span.
      expect(facts[2].firstHigherDay, isNull);
      expect(facts[2].firstHigherUntilCycleEndDays, isNull);
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
      expect(stats.firstHigherCycleDays.min, isNull);
      expect(stats.firstHigherCycleDays.max, isNull);
      expect(stats.firstHigherCycleDays.average, isNull);
      expect(stats.firstHigherCycleDays.stdDev, isNull);
      expect(stats.cycleLengths.count, 0);
      expect(stats.bleedingDays.count, 0);
      expect(stats.firstHigherUntilCycleEnd.count, 0);
      expect(stats.firstHigherCycleDays.count, 0);
    });

    test('aggregates min/max/avg/population std over the metrics', () {
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
      ]);
      expect(stats.cycleCount, 4);

      // The per-metric counts are the input lists' lengths — lengths
      // without the open trailing cycle, bleeding across every fact row,
      // the first-higher metrics on their qualifying facts.
      expect(stats.cycleLengths.count, 3);
      expect(stats.bleedingDays.count, 4);
      expect(stats.firstHigherUntilCycleEnd.count, 1);
      expect(stats.firstHigherCycleDays.count, 1);

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

      // First higher day numbers as 1-based day-of-cycle: Mar 20 is
      // offset 18 from the Mar 2 start, so the chart-convention day
      // number is 19 — the only fact row, one value, no spread.
      expect(stats.firstHigherCycleDays.min, 19);
      expect(stats.firstHigherCycleDays.max, 19);
      expect(stats.firstHigherCycleDays.average, closeTo(19.0, 0.0001));
      expect(stats.firstHigherCycleDays.stdDev, closeTo(0.0, 0.0001));
    });

    test('earliest first higher prefers the smallest day-of-cycle offset', () {
      // Cycle 1: mark Mar 20, start Mar 2 -> cycle day 19; cycle 3
      // (Apr 27..): mark May 1 -> cycle day 5 — the fifth day wins.
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
        firstHigher(2026, 5, 1),
      ]);
      expect(stats.firstHigherCycleDays.min, 5);
      expect(stats.firstHigherCycleDays.max, 19);
      expect(stats.firstHigherCycleDays.average, closeTo(12.0, 0.0001));
      expect(stats.firstHigherCycleDays.stdDev, closeTo(7.0, 0.0001));
    });

    test('a three-cycle first-higher day distribution: min, max, mean, '
        'std', () {
      // Cycle 1 (start Mar 2): mark Mar 20 -> day 19; cycle 2 (start
      // Mar 30): mark Apr 6 -> day 8; cycle 3 (start Apr 27): mark May 1
      // -> day 5. Mean 32/3; population std = sqrt(36.2222...).
      final stats = cycleStatistics(threeCycleData(), [
        ...threeCycleStarts(),
        firstHigher(2026, 3, 20),
        firstHigher(2026, 4, 6),
        firstHigher(2026, 5, 1),
      ]);
      expect(stats.firstHigherCycleDays.min, 5);
      expect(stats.firstHigherCycleDays.max, 19);
      expect(stats.firstHigherCycleDays.average, closeTo(32 / 3, 0.0001));
      expect(stats.firstHigherCycleDays.stdDev, closeTo(6.0184877, 0.0001));
    });

    test('a first-higher mark in the leading pre-mark group contributes '
        'no day number', () {
      final entries = [d(2026, 2, 20), ...threeCycleData()];
      final stats = cycleStatistics(entries, [
        firstHigher(2026, 2, 25),
        ...threeCycleStarts(),
      ]);
      // The mark sits inside the leading group (no cycle start to count
      // from); the four mark-opened cycles carry none.
      expect(stats.facts, hasLength(4));
      expect(stats.firstHigherCycleDays.min, isNull);
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
      expect(stats.firstHigherCycleDays.min, 19);
    });
  });

  // The per-cycle statistics scenario: three marked cycles
  //   cycle 1: start Mar 1 — bleeding Mar 1-4 with an interruption on Mar 3
  //            (4 bleeding-window days, interruption counts through), first
  //            higher Mar 14, mucus peak Mar 12; six measured lows Mar 8-13
  //            at 36.4 and the rise day Mar 14 at 36.7 — a circle on the
  //            rise day
  //   cycle 2: start Mar 29 — no bleeding day, first higher Mar 31, mucus
  //            peak Mar 30; one measured low Mar 29 (36.4) and the rise day
  //            Mar 31 at 36.7 — a circle on the rise day
  //   cycle 3: start Apr 27 — bleeding Apr 27-28, no first-higher mark
  // (Mar 3 clear: shows the interruption counting through the span.)
  List<DailyEntry> perCycleEntries() => [
    d(2026, 3, 1, bleeding: Bleeding.heavy),
    d(2026, 3, 2, bleeding: Bleeding.medium),
    d(2026, 3, 3),
    d(2026, 3, 4, bleeding: Bleeding.light),
    d(2026, 3, 8, bbtC: 36.4),
    d(2026, 3, 9, bbtC: 36.4),
    d(2026, 3, 10, bbtC: 36.4),
    d(2026, 3, 11, bbtC: 36.4),
    d(2026, 3, 12, bbtC: 36.4),
    d(2026, 3, 13, bbtC: 36.4),
    d(2026, 3, 14, bbtC: 36.7),
    d(2026, 3, 29, bleeding: Bleeding.none, bbtC: 36.4),
    d(2026, 3, 31, bbtC: 36.7),
    d(2026, 4, 27, bleeding: Bleeding.medium),
    d(2026, 4, 28, bleeding: Bleeding.medium),
  ];

  List<CycleMark> perCycleMarks() => [
    start(2026, 3, 1),
    start(2026, 3, 29),
    start(2026, 4, 27),
    mucusPeak(2026, 3, 12),
    firstHigher(2026, 3, 14),
    mucusPeak(2026, 3, 30),
    firstHigher(2026, 3, 31),
  ];

  List<CycleEvaluation> perCycleEvaluations() => evaluateCycles(
    perCycleEntries(),
    perCycleMarks(),
    today: DateTime(2026, 6, 1),
  );

  group('markDrivenCycleCount', () {
    test('counts the mark-opened cycles of the grouping', () {
      // The threeCycleData scenario has FOUR mark-opened groups (starts
      // Mar 2 / Mar 30 / Apr 27 / May 25 — the last one is the still-open
      // cycle, hence 3 lengths but 4 observed cycles).
      expect(markDrivenCycleCount(threeCycleData(), threeCycleStarts()), 4);
      expect(markDrivenCycleCount(perCycleEntries(), perCycleMarks()), 3);
    });

    test('no marks -> zero cycles', () {
      expect(markDrivenCycleCount(threeCycleData(), const []), 0);
      expect(markDrivenCycleCount(const [], const []), 0);
    });

    test('the leading pre-mark group is not counted', () {
      final entries = [
        d(2026, 2, 25, bleeding: Bleeding.spotting),
        d(2026, 2, 27),
        ...threeCycleData(),
      ];
      // Five groups form, but only the four mark-opened ones count —
      // the leading group (Feb 25-27, before the first cycleStart mark)
      // does not start at a mark.
      expect(markDrivenCycleCount(entries, threeCycleStarts()), 4);
    });
  });

  group('summarizeInts', () {
    test('min, max, average and population std-dev over the list', () {
      // Mean 6; population variance ((4-6)² + 0 + (8-6)² + 0) / 4 = 2,
      // std-dev = sqrt(2). Population (divide by N), because the observed
      // cycles are the whole recorded data set here — a descriptive
      // fact, not a sample-of-a-population estimate.
      final summary = summarizeInts(const [4, 6, 8, 6]);
      expect(summary.minimum, 4);
      expect(summary.maximum, 8);
      expect(summary.average, closeTo(6.0, 0.0001));
      expect(summary.standardDeviation, closeTo(1.4142135, 0.0001));
      expect(summary.count, 4);
    });

    test('a single value has zero std-dev', () {
      final summary = summarizeInts(const [28]);
      expect(summary.minimum, 28);
      expect(summary.maximum, 28);
      expect(summary.average, closeTo(28.0, 0.0001));
      expect(summary.standardDeviation, closeTo(0.0, 0.0001));
      expect(summary.count, 1);
    });

    test('empty input yields nulls without throwing', () {
      final summary = summarizeInts(const []);
      expect(summary.minimum, isNull);
      expect(summary.maximum, isNull);
      expect(summary.average, isNull);
      expect(summary.standardDeviation, isNull);
      expect(summary.count, 0);
    });
  });

  group('bleedingSpanInDays (the per-window helper, directly)', () {
    test('first-to-last inclusive span; null without a bleeding day', () {
      // The helper is the one documented definition behind the per-cycle
      // statistics (see the docstring); these thin asserts pin its
      // contract at the direct call level — the statistics screen passes
      // evaluateCycles() windows in [cycleBleedingDurationsInDays] below.
      // 1st gap case: Mar 1, 2 and 4 bleed, Mar 3 does not — the span is
      // 4 (interruption counts through, "Mensbeginn -> Mensende"); the
      // interruption-free single-day case stays 1.
      expect(
        bleedingSpanInDays([
          d(2026, 3, 1, bleeding: Bleeding.medium),
          d(2026, 3, 2, bleeding: Bleeding.light),
          d(2026, 3, 3, bleeding: Bleeding.none),
          d(2026, 3, 4, bleeding: Bleeding.heavy),
        ]),
        4,
      );
      expect(bleedingSpanInDays([d(2026, 3, 2, bleeding: Bleeding.medium)]), 1);
      expect(
        bleedingSpanInDays([d(2026, 3, 2, bleeding: Bleeding.none)]),
        isNull,
      );
    });
  });

  group('cycleBleedingDurationsInDays (per marked cycle over the spans)', () {
    test('first to last bleeding day, interruptions count through', () {
      // Mar 1, 2, 4 bleed; Mar 3 does not — the span Mar 1..Mar 4 is an
      // INCLUSIVE calendar-day count of 4 (like "Mensbeginn -> Mensende",
      // first-to-last days, not the number of bleeding days itself).
      final summary = summarizeInts(
        cycleBleedingDurationsInDays(
          evaluateCycles(perCycleEntries(), perCycleMarks()),
        ).nonNulls.toList(),
      );
      // Cycle 1: 4, cycle 2: no bleeding -> dropped from the aggregate.
      expect(summary.minimum, 2);
      expect(summary.maximum, 4);
      expect(summary.average, closeTo(3.0, 0.0001));
      // The count follows the feed: only the cycles with a bleeding day
      // (the non-null durations) count, not every fact row.
      expect(summary.count, 2);
    });

    test('a cycle without any bleeding day contributes null', () {
      // perCycleEvaluations(): the third cycle is filtered out above; test
      // the nulls directly. The bleeding day rule: level >= 1 (spotting
      // included) — level 0 (none) is not a bleeding day.
      final durations = cycleBleedingDurationsInDays(perCycleEvaluations());
      expect(durations, [4, null, 2]);
    });

    test('the leading pre-mark group never contributes', () {
      final entries = [
        d(2026, 2, 25, bleeding: Bleeding.heavy),
        d(2026, 2, 26, bleeding: Bleeding.heavy),
        d(2026, 3, 1, bleeding: Bleeding.light),
        d(2026, 3, 29),
      ];
      final marks = [start(2026, 3, 1)];
      // Exactly ONE mark-driven cycle: the leading group's bleeding
      // (Feb 25-26) is not a numbered cycle, exactly as the cycle page's
      // evaluation table shows the dash for it; the Mar 1 group spans the
      // rest (Mar 1..Mar 29, only Mar 1 bleeds -> duration 1).
      expect(cycleBleedingDurationsInDays(evaluateCycles(entries, marks)), [1]);
    });
  });

  group('the data-span extension (cycle runs to the next mark / today)', () {
    // The grouping extends every cycle across its data-less tail; these
    // tests pin what the STATISTICS make of the appended empty entries.
    test('bleeding statistics are untouched by the appended data-less days '
        '(empty entries bleed nothing)', () {
      // perCycleEvaluations pins the clock at Jun 1: cycle 3 (start Apr 27,
      // tracked to Apr 28) extends across data-less Apr 29..May 31 — still
      // a bleeding-free cycle, contributing null.
      expect(cycleBleedingDurationsInDays(perCycleEvaluations()), [4, null, 2]);
    });

    test('a trailing FRESH mark (no data after it) counts its interval: '
        'the previous cycle ran to it, lengths and counts grow', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 30),
      ];
      final marks = [start(2026, 3, 2), start(2026, 3, 30), start(2026, 5, 10)];

      // The fresh May 10 mark opens a data-less cycle; onsets now include
      // it, so one more length is counted (mark-to-mark, Mar 2 -> May 10).
      expect(cycleLengthsInDays(entries, marks), [28, 41]);
      expect(markDrivenCycleCount(entries, marks), 3);
    });
  });

  group('earliestFirstHigherCycleDay', () {
    test('cycle-day minimum, both variants (any and after the mucus peak)', () {
      // Cycle 1: the rise mark Mar 14 IS the first circle (measured 36.7
      // above the 36.4 low baseline, after the peak Mar 12) — cycle day
      // 14. Cycle 2: the rise mark Mar 31 IS the first circle (measured
      // 36.7 above the 36.4 low, after the peak Mar 30) — cycle day 3.
      final earliest = earliestFirstHigherCycleDay(perCycleEvaluations());
      expect(earliest.any, 3, reason: 'the minimum over the marked rises');
      expect(
        earliest.afterMucusPeak,
        3,
        reason: 'the minimum over the first circled candidates',
      );
    });

    test('both variants differ: a rise at/before the mucus peak qualifies '
        'at the first measured above-baseline day after it '
        '(umrandete Messung)', () {
      // Cycle 1: rise mark Mar 4 (cycle day 4), peak Mar 6 — the first
      // measured above-baseline day after the peak is Mar 7 (36.8 above
      // the 36.4 low), so the first circle is cycle day 7 while the mark
      // sits on day 4.
      // Cycle 2: rise Apr 6 (cycle day 9; start Mar 29 = day 1), peak
      // Apr 2 — the rise day is itself measured (36.7) and lies after the
      // peak, so the first circle is the rise day.
      final entries = [
        d(2026, 3, 1, bbtC: 36.4),
        d(2026, 3, 2, bbtC: 36.4),
        d(2026, 3, 3, bbtC: 36.4),
        d(2026, 3, 7, bbtC: 36.8),
        d(2026, 3, 29, bleeding: Bleeding.spotting, bbtC: 36.4),
        d(2026, 4, 2, bbtC: 36.4),
        d(2026, 4, 6, bbtC: 36.7),
      ];
      final marks = [
        start(2026, 3, 1),
        start(2026, 3, 29),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 4),
        mucusPeak(2026, 4, 2),
        firstHigher(2026, 4, 6),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 4, reason: 'the minimum over the marked rises');
      expect(
        earliest.afterMucusPeak,
        7,
        reason:
            'the minimum over the first circled candidates: Mar 7 '
            '(measured above the baseline, the day after the peak) '
            'beats the Apr 6 circle',
      );
    });

    test('a rise ON the mucus peak day qualifies at the measured day after '
        'the peak', () {
      // The rise mark sits ON the peak day (Mar 6): the marked day itself
      // is unmeasured and the day after the peak is measured 36.8 above
      // the 36.4 low — the first circle is Mar 7, cycle day 7.
      final entries = [
        for (var day = 1; day <= 5; day++) d(2026, 3, day, bbtC: 36.4),
        d(2026, 3, 7, bbtC: 36.8),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 6),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 6);
      expect(earliest.afterMucusPeak, 7, reason: 'the first circle: Mar 7');
    });

    test('a rise after the mucus peak qualifies at the rise itself', () {
      // The rise day (Mar 8) is measured 36.7 above the 36.4 low baseline
      // and strictly after the peak — the first circle sits on the mark.
      final entries = [
        for (var day = 2; day <= 7; day++) d(2026, 3, day, bbtC: 36.4),
        d(2026, 3, 8, bbtC: 36.7),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 8),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 8);
      expect(earliest.afterMucusPeak, 8);
    });

    test('a qualifying day can never collide with the next cycle start', () {
      // A circle candidate comes from the evaluation walk, which stops at
      // the cycle's own end = the day before the next mark-driven start:
      // cycle 1 (Mar 1..Mar 5, cycle 2 opens Mar 6) peaks on Mar 4 and
      // its last day Mar 5 measures 36.9 above the baseline — the first
      // circle qualifies at cycle day 5. Peak + 1 (Mar 6) is cycle 2's
      // start and is never counted for cycle 1.
      final entries = [
        d(2026, 3, 1, bbtC: 36.4),
        d(2026, 3, 2, bbtC: 36.4),
        d(2026, 3, 3, bbtC: 36.7),
        d(2026, 3, 4, bbtC: 36.8),
        d(2026, 3, 5, bbtC: 36.9),
      ];
      final marks = [
        start(2026, 3, 1),
        start(2026, 3, 6),
        mucusPeak(2026, 3, 4),
        firstHigher(2026, 3, 3),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 3);
      expect(
        earliest.afterMucusPeak,
        5,
        reason:
            "the day before the next cycle's start is still this "
            "cycle's circle",
      );
    });

    test('the day after the peak without a measured above-baseline '
        'temperature does not qualify — the first later circle does', () {
      // Peak Mar 6, rise mark Mar 5: Mar 7 (peak + 1) is unmeasured, so
      // nothing circles there; the first measured above-baseline day is
      // Mar 8 (36.7 above the 36.4 low) — the first circle, cycle day 8.
      final entries = [
        for (var day = 1; day <= 4; day++) d(2026, 3, day, bbtC: 36.4),
        d(2026, 3, 8, bbtC: 36.7),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 5),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 5);
      expect(earliest.afterMucusPeak, 8);
    });

    test('no measured above-baseline day after the peak: the cycle '
        'qualifies nowhere for the real variant', () {
      // The same mark shape as the fixture above, but nothing is ever
      // measured above the baseline after the peak: no circle exists, so
      // the cycle contributes to the "any" variant only.
      final entries = [
        for (var day = 1; day <= 4; day++) d(2026, 3, day, bbtC: 36.4),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 5),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, 5);
      expect(earliest.afterMucusPeak, isNull);
    });

    test('a gap-stopped evaluation contributes no qualifying day', () {
      // The sequence starts with an arrow (Mar 5, below the late-peak
      // mark of Mar 20) and is R2-stopped by the two gap days Mar 6/7
      // before the next candidate: no candidate after the peak exists,
      // so the first circle (and the qualifying day) is absent — the
      // "any" variant still counts the marked rise day.
      final entries = [
        for (var day = 1; day <= 4; day++) d(2026, 3, day, bbtC: 36.4),
        d(2026, 3, 5, bbtC: 36.7),
        d(2026, 3, 8, bbtC: 36.7),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 20),
        firstHigher(2026, 3, 5),
      ];
      final evaluations = evaluateCycles(entries, marks);
      expect(evaluations.single.evaluationStopped, isTrue);
      final earliest = earliestFirstHigherCycleDay(evaluations);
      expect(earliest.any, 5);
      expect(earliest.afterMucusPeak, isNull);
    });

    test('a rise after the peak whose marked day carries no above-baseline '
        'temperature qualifies at the first circle, not at the mark', () {
      // The rise mark (Mar 8) is after the peak (Mar 6) but unmeasured;
      // the first measured above-baseline day is Mar 9 — the first
      // circle, cycle day 9, not the marked day 8.
      final entries = [
        for (var day = 2; day <= 7; day++) d(2026, 3, day, bbtC: 36.4),
        d(2026, 3, 9, bbtC: 36.7),
      ];
      final marks = [
        start(2026, 3, 1),
        mucusPeak(2026, 3, 6),
        firstHigher(2026, 3, 8),
      ];
      final evaluations = evaluateCycles(entries, marks);
      expect(evaluations.single.riseMarkConsistent, isFalse);
      final earliest = earliestFirstHigherCycleDay(evaluations);
      expect(earliest.any, 8);
      expect(earliest.afterMucusPeak, 9);
    });

    test('null variants when nothing qualifies', () {
      // No first-higher marks at all: both variants null.
      var earliest = earliestFirstHigherCycleDay(
        evaluateCycles(threeCycleData(), threeCycleStarts()),
      );
      expect(earliest.any, isNull);
      expect(earliest.afterMucusPeak, isNull);

      // A rise but no marked peak in the cycle: any stays, real null.
      earliest = earliestFirstHigherCycleDay(
        evaluateCycles(
          [DailyEntry(date: DateTime(2026, 3, 1))],
          [start(2026, 3, 1), firstHigher(2026, 3, 3)],
        ),
      );
      expect(earliest.any, 3);
      expect(earliest.afterMucusPeak, isNull);
    });

    test('the leading pre-mark group is ignored', () {
      final entries = [d(2026, 2, 20), d(2026, 3, 1)];
      final marks = [
        // A first-higher mark BEFORE the first cycleStart mark belongs to
        // the leading group (it does not start at a mark): no cycle day,
        // so it must not contribute (the cycle day would be undefined).
        firstHigher(2026, 2, 25),
        start(2026, 3, 1),
      ];
      final earliest = earliestFirstHigherCycleDay(
        evaluateCycles(entries, marks),
      );
      expect(earliest.any, isNull);
      expect(earliest.afterMucusPeak, isNull);
    });
  });

  group('the one-pass derived bundle', () {
    // The evaluation clock the per-cycle scenario pins (its own longer
    // span extension could otherwise shift nothing, but pinning keeps the
    // derived pass deterministic anyway).
    final perCycleToday = DateTime(2026, 6, 1);

    // CycleFact has no structural equality, so the equivalence assertions
    // pair against plain field records (records compare structurally).
    List<
      ({
        DateTime start,
        int bleedingDays,
        DateTime? firstHigherDay,
        int? lengthDays,
        int? firstHigherUntilCycleEndDays,
      })
    >
    factRecords(List<CycleFact> facts) => [
      for (final fact in facts)
        (
          start: fact.cycleStart,
          bleedingDays: fact.bleedingDays,
          firstHigherDay: fact.firstHigherDay,
          lengthDays: fact.lengthDays,
          firstHigherUntilCycleEndDays: fact.firstHigherUntilCycleEndDays,
        ),
    ];

    test('lengths, onsets, count, facts and aggregates equal the '
        'whole-stream functions', () {
      for (final (entries, marks) in <(List<DailyEntry>, List<CycleMark>)>[
        (threeCycleData(), threeCycleStarts()),
        (
          threeCycleData(),
          [
            ...threeCycleStarts(),
            firstHigher(2026, 3, 20),
            firstHigher(2026, 5, 1),
          ],
        ),
        (perCycleEntries(), perCycleMarks()),
        (
          evaluationScenarioEntries(),
          [start(2026, 9, 6), mucusPeak(2026, 9, 15), firstHigher(2026, 9, 14)],
        ),
      ]) {
        final derived = deriveCycleData(entries, marks, today: perCycleToday);
        final lengths = cycleLengthsInDaysFrom(derived.cycles);
        expect(
          lengths,
          cycleLengthsInDays(entries, marks),
          reason: 'lengths derive from the one pass',
        );
        expect(
          menstruationOnsetDatesFrom(derived.cycles),
          menstruationOnsetDates(entries, marks),
          reason: 'onsets derive from the one pass',
        );
        expect(
          markDrivenCycleCountFrom(derived.cycles),
          markDrivenCycleCount(entries, marks),
          reason: 'the count derives from the one pass',
        );
        expect(
          factRecords(
            cycleFactsFromCycles(derived.cycles, derived.evaluations),
          ),
          factRecords(cycleFacts(entries, marks)),
          reason: 'fact rows pair with the one pass',
        );

        final whole = cycleStatistics(entries, marks);
        final fromPass = cycleStatisticsFromCycles(
          derived.cycles,
          derived.evaluations,
        );
        expect(fromPass.cycleCount, whole.cycleCount);
        expect(
          factRecords(fromPass.facts),
          factRecords(whole.facts),
          reason: 'the aggregates share the whole pass',
        );
        expect(
          (
            fromPass.cycleLengths.min,
            fromPass.cycleLengths.max,
            fromPass.cycleLengths.average,
            fromPass.cycleLengths.stdDev,
            fromPass.cycleLengths.count,
          ),
          (
            whole.cycleLengths.min,
            whole.cycleLengths.max,
            whole.cycleLengths.average,
            whole.cycleLengths.stdDev,
            whole.cycleLengths.count,
          ),
          reason: 'the cycle-length aggregates',
        );
        expect(
          (
            fromPass.bleedingDays.min,
            fromPass.bleedingDays.max,
            fromPass.bleedingDays.average,
            fromPass.bleedingDays.stdDev,
            fromPass.bleedingDays.count,
          ),
          (
            whole.bleedingDays.min,
            whole.bleedingDays.max,
            whole.bleedingDays.average,
            whole.bleedingDays.stdDev,
            whole.bleedingDays.count,
          ),
          reason: 'the bleeding-day aggregates',
        );
        expect(
          (
            fromPass.firstHigherUntilCycleEnd.min,
            fromPass.firstHigherUntilCycleEnd.max,
            fromPass.firstHigherUntilCycleEnd.average,
            fromPass.firstHigherUntilCycleEnd.stdDev,
            fromPass.firstHigherUntilCycleEnd.count,
          ),
          (
            whole.firstHigherUntilCycleEnd.min,
            whole.firstHigherUntilCycleEnd.max,
            whole.firstHigherUntilCycleEnd.average,
            whole.firstHigherUntilCycleEnd.stdDev,
            whole.firstHigherUntilCycleEnd.count,
          ),
          reason: 'the first-higher-until-end aggregates',
        );
        expect(
          (
            fromPass.firstHigherCycleDays.min,
            fromPass.firstHigherCycleDays.max,
            fromPass.firstHigherCycleDays.average,
            fromPass.firstHigherCycleDays.stdDev,
            fromPass.firstHigherCycleDays.count,
          ),
          (
            whole.firstHigherCycleDays.min,
            whole.firstHigherCycleDays.max,
            whole.firstHigherCycleDays.average,
            whole.firstHigherCycleDays.stdDev,
            whole.firstHigherCycleDays.count,
          ),
          reason: 'the first-higher-day aggregates',
        );
      }
    });
  });

  group('the index-paired fact rows (graceful degradation, no throw)', () {
    test('a shorter evaluation list degrades the missing rows to '
        'data-only facts', () {
      final entries = threeCycleData();
      final marks = threeCycleStarts();
      final cycles = groupIntoCycles(entries, marks);
      final evaluations = evaluateCycles(entries, marks);
      expect(cycles, hasLength(4));
      expect(evaluations, hasLength(4));

      final facts = cycleFactsFromCycles(cycles, evaluations.sublist(0, 2));
      expect(facts, hasLength(4));
      // Unaffected rows keep the full values their evaluations resolve.
      expect(facts[0].cycleStart, DateTime.utc(2026, 3, 2));
      expect(facts[0].bleedingDays, 2);
      expect(facts[0].lengthDays, 28);
      expect(facts[1].cycleStart, DateTime.utc(2026, 3, 30));
      expect(facts[1].bleedingDays, 2);
      expect(facts[1].lengthDays, 28);
      // Missing rows keep the data-only facts: bleeding days and length
      // still derive from the cycles; the evaluation-based facts stay null.
      expect(facts[2].cycleStart, DateTime.utc(2026, 4, 27));
      expect(facts[2].bleedingDays, 1);
      expect(facts[2].lengthDays, 28);
      expect(facts[2].firstHigherDay, isNull);
      expect(facts[2].firstHigherUntilCycleEndDays, isNull);
      expect(facts[3].cycleStart, DateTime.utc(2026, 5, 25));
      expect(facts[3].bleedingDays, 2);
      expect(facts[3].lengthDays, isNull);
      expect(facts[3].firstHigherDay, isNull);
    });

    test('a longer evaluation list adds no rows and drops the surplus', () {
      final entries = threeCycleData();
      final marks = threeCycleStarts();
      final cycles = groupIntoCycles(entries, marks);
      final evaluations = evaluateCycles(entries, marks);
      final padded = [...evaluations, evaluations.first];

      final facts = cycleFactsFromCycles(cycles, padded);
      expect(facts, hasLength(4));
      // The surviving rows equal the full-pass pairing of the same fixture.
      final full = [
        for (final fact in cycleFactsFromCycles(cycles, evaluations))
          (
            start: fact.cycleStart,
            bleedingDays: fact.bleedingDays,
            firstHigherDay: fact.firstHigherDay,
            lengthDays: fact.lengthDays,
          ),
      ];
      expect(
        facts.map(
          (fact) => (
            start: fact.cycleStart,
            bleedingDays: fact.bleedingDays,
            firstHigherDay: fact.firstHigherDay,
            lengthDays: fact.lengthDays,
          ),
        ),
        full,
      );
    });
  });
}
