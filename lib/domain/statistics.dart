// Statistics: arithmetic over cycle data — lengths, averages, histograms.
//
// HARD RULE (product scope, see docs/product/vision.md req. 3 and the plan):
// NO fertility interpretation of any kind. The functions here return
// arithmetic facts only (lists of lengths/dates, averages, bucket counts).
// There is deliberately NO status/day classification, NO fertile-window or
// phase computation, and NO textual evaluation in this layer — such
// conclusions would be Mode-M/INER territory requiring expert validation
// (ADR-0001, status: Hypothesis). Keep it that way in reviews.

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// Cycle lengths in days: differences between consecutive mark-driven
/// cycle starts (see lib/domain/cycle_grouping.dart — grouping opens a
/// group at every user-placed cycleStart mark). A trailing cycle start with
/// no known follow-up contributes no length.
List<int> cycleLengthsInDays(
  List<DailyEntry> entries,
  List<CycleMark> marks,
) {
  final onsets = menstruationOnsetDates(entries, marks);
  final lengths = <int>[];
  for (var i = 0; i + 1 < onsets.length; i++) {
    // Day-component arithmetic (not DateTime.difference): difference()
    // would lose a day across DST changes; onsets are UTC-normalized so
    // the epoch difference IS the calendar-day count.
    // Onsets are sorted ascending, so onsets[i+1] - onsets[i] > 0.
    lengths.add(DateOnly.daysBetween(onsets[i + 1], onsets[i]));
  }
  return lengths;
}

/// Summary scalars over a list of cycle lengths (days).
///
/// Empty input yields empty [lengths] and null scalars — the UI can show
/// "no data" instead of a zero-based misleading average.
final class CycleLengthSummary {
  const CycleLengthSummary({
    required this.lengths,
    required this.average,
    required this.shortest,
    required this.longest,
  });

  /// The input lengths, in the given order.
  final List<int> lengths;

  /// Mean of [lengths], or null when there is no data.
  final double? average;

  /// Shortest length, or null when there is no data.
  final int? shortest;

  /// Longest length, or null when there is no data.
  final int? longest;
}

CycleLengthSummary summarizeCycleLengths(List<int> lengths) {
  if (lengths.isEmpty) {
    return const CycleLengthSummary(
      lengths: [],
      average: null,
      shortest: null,
      longest: null,
    );
  }
  return CycleLengthSummary(
    lengths: List.unmodifiable(lengths),
    average: lengths.fold<int>(0, (sum, l) => sum + l) / lengths.length,
    shortest: lengths.reduce((a, b) => a < b ? a : b),
    longest: lengths.reduce((a, b) => a > b ? a : b),
  );
}

/// One histogram bucket for cycle lengths: [minInclusive, maxExclusive).
/// For the open-ended last bucket the code uses a sentinel maxExclusive;
/// [label] is a plain, language-neutral short label (UI may localize later).
final class CycleLengthBucket {
  const CycleLengthBucket({
    required this.label,
    required this.minInclusive,
    required this.maxExclusive,
    required this.count,
  });

  final String label;
  final int minInclusive;
  final int maxExclusive;
  final int count;
}

// TODO(user-review): bucket edges are a first, pragmatic cut (<21 / 21-25 /
// 26-30 / 31-35 / 36-40 / 41+). Confirm sensible NFP-grade edges with
// experts; changes here are data-free (pure presentation arithmetic).
// Named-field records (not positional ones): reading `bucket.minInclusive`
// directly keeps the loop below free of destructured-but-unused variables,
// which the analyzer would otherwise flag per field.
const List<({String label, int minInclusive, int maxExclusive})>
    _defaultBucketEdges = [
  (label: '<=20', minInclusive: -0x7FFFFFFF, maxExclusive: 21), // < 21 days
  (label: '21-25', minInclusive: 21, maxExclusive: 26),
  (label: '26-30', minInclusive: 26, maxExclusive: 31),
  (label: '31-35', minInclusive: 31, maxExclusive: 36),
  (label: '36-40', minInclusive: 36, maxExclusive: 41),
  (label: '41+', minInclusive: 41, maxExclusive: 0x7FFFFFFF), // open-ended
];

/// Counts the given cycle lengths into the fixed buckets. Every bucket is
/// present in the result, even when its count is 0, so charts stay stable.
List<CycleLengthBucket> cycleLengthDistribution(List<int> lengths) {
  final counts = List<int>.filled(_defaultBucketEdges.length, 0);

  for (final length in lengths) {
    for (final (bucketIndex, bucket) in _defaultBucketEdges.indexed) {
      if (length >= bucket.minInclusive && length < bucket.maxExclusive) {
        counts[bucketIndex]++;
        break;
      }
    }
  }

  return [
    for (final (bucketIndex, bucket) in _defaultBucketEdges.indexed)
      CycleLengthBucket(
        label: bucket.label,
        minInclusive: bucket.minInclusive,
        maxExclusive: bucket.maxExclusive,
        count: counts[bucketIndex],
      ),
  ];
}
