// Domain tests: statistics arithmetic. NO fertility interpretation —
// lengths, averages, and histograms only (see lib/domain/statistics.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/statistics.dart';

import 'mark_fixtures.dart';

DailyEntry d(
  int year,
  int month,
  int day, {
  Bleeding bleeding = Bleeding.none,
}) {
  return DailyEntry(date: DateTime(year, month, day), bleeding: bleeding);
}

// start/excludedDay: the shared domain mark fixtures (mark_fixtures.dart).

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
}
