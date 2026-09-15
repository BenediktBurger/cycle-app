// Domain tests: statistics arithmetic. NO fertility interpretation —
// lengths, averages, and histograms only (see lib/domain/statistics.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/statistics.dart';

DailyEntry d(
  int year,
  int month,
  int day, {
  Bleeding bleeding = Bleeding.none,
}) {
  return DailyEntry(date: DateTime(year, month, day), bleeding: bleeding);
}

/// Three clean cycles: onsets Mar 2 / Mar 30 / Apr 27 / May 25.
/// Consecutive lengths: 28, 28, 28.
List<DailyEntry> threeCycleData() => [
      d(2026, 3, 2, bleeding: Bleeding.period),
      d(2026, 3, 3, bleeding: Bleeding.period),
      d(2026, 3, 4),
      d(2026, 3, 30, bleeding: Bleeding.period),
      d(2026, 4, 1),
      d(2026, 4, 10, bleeding: Bleeding.spotting),
      d(2026, 4, 27, bleeding: Bleeding.period),
      d(2026, 5, 1),
      d(2026, 5, 25, bleeding: Bleeding.period),
      d(2026, 5, 26, bleeding: Bleeding.period),
    ];

void main() {
  group('cycleLengthsInDays', () {
    test('counts days between consecutive menstruation onsets', () {
      expect(cycleLengthsInDays(threeCycleData()), [28, 28, 28]);
    });

    test('excludes interrupted (excluded) bleeding days as boundaries', () {
      final entries = [
        d(2026, 4, 1, bleeding: Bleeding.period),
        // interrupted period day shortly before the real next onset:
        DailyEntry(
          date: DateTime(2026, 4, 28),
          bleeding: Bleeding.period,
          excludeIllness: true,
        ),
        d(2026, 4, 29, bleeding: Bleeding.period), // true onset
      ];
      // Apr 29 is the only later onset -> single length from Apr 1 to Apr 29.
      expect(cycleLengthsInDays(entries), [28]);
    });

    test('incomplete trailing cycle contributes no length', () {
      final entries = [
        d(2026, 1, 5, bleeding: Bleeding.period),
        d(2026, 2, 2, bleeding: Bleeding.period),
        // no known next onset: cycle 2 is open-ended
      ];
      expect(cycleLengthsInDays(entries), [28]);
    });

    test('no onsets -> no lengths', () {
      expect(cycleLengthsInDays([d(2026, 1, 1)]), isEmpty);
      expect(cycleLengthsInDays(const []), isEmpty);
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
      final lengths = cycleLengthsInDays(threeCycleData());
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
      final byLabel = <String, int>{
        for (final b in buckets) b.label: b.count,
      };
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
