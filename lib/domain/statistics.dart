// Statistics: arithmetic over cycle data — lengths, averages, histograms,
// per-cycle fact rows.
//
// HARD RULE (product scope, see docs/product/vision.md req. 3 and the plan):
// NO fertility interpretation of any kind. The functions here return
// arithmetic facts only (lists of lengths/dates, averages, bucket counts).
// There is deliberately NO status/day classification, NO fertile-window or
// phase computation, and NO textual evaluation in this layer — statistics
// stay arithmetic-only (Mode M, ADR-0001, Accepted): no fertility verdicts.
// Keep it that way in reviews.
//
// The per-cycle facts below REUSE [evaluateCycles]
// (lib/domain/evaluation.dart) for the first-higher truth: the evaluated
// candidates are arithmetic render-time artifacts, and picking the earliest
// candidate strictly after the peak (with the marked-day fallback) is a
// selection, not a statement — the file stays free of any fertility claim.

import 'dart:math' as math;

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'evaluation.dart';
import 'marks.dart';
import 'models.dart';

/// Cycle lengths in days: differences between consecutive mark-driven
/// cycle starts (see lib/domain/cycle_grouping.dart — grouping opens a
/// group at every user-placed cycleStart mark, and the start date is that
/// mark's own date). A trailing cycle start with no known follow-up
/// contributes no length.
List<int> cycleLengthsInDays(List<DailyEntry> entries, List<CycleMark> marks) {
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

// ═══════════ Per-cycle fact rows ═══════════
// One row per mark-opened cycle (see groupIntoCycles); the leading pre-mark
// group produces no row. Everything is arithmetic over tracked days, marks,
// and the evaluated candidate sequence.

/// One per-cycle fact row of the statistics screen's table: start date,
/// bleeding-day count, first higher measurement, cycle length.
final class CycleFact {
  const CycleFact({
    required this.cycleStart,
    required this.bleedingDays,
    required this.firstHigherDay,
    required this.lengthDays,
    required this.firstHigherUntilCycleEndDays,
  });

  /// The cycle's mark-driven start, normalized to UTC midnight (see
  /// DateOnly).
  final DateTime cycleStart;

  /// Counted bleeding days among the cycle's tracked days.
  ///
  /// TODO(user-review): the threshold is level >= 1, so a Schmierblutung
  /// (spotting) counts as a bleeding day — flagged owner decision pending
  /// confirmation with INER experts; a change is data-free (pure
  /// presentation arithmetic).
  final int bleedingDays;

  /// The resolved first higher measurement of this cycle, or null when the
  /// user marked neither a peak nor a first higher measurement.
  ///
  /// Resolution (arithmetic selection): the earliest evaluated candidate
  /// STRICTLY AFTER the mucus peak when one exists — the "real" first
  /// higher measurement (after the peak, per CHEAT SHEET rules) — otherwise
  /// the user-placed firstHigherMeasurement mark day
  /// ([CycleEvaluation.firstHigherDay]). No candidates and no mark → null.
  /// The chosen day stays a fact picked from the tracked/evaluated data;
  /// nothing here claims anything about fertility.
  final DateTime? firstHigherDay;

  /// Days from the cycle start until the NEXT mark-opened start. Null for
  /// the trailing cycle (no known follow-up — this is also how
  /// cycleLengthsInDays handles it) and for any cycle without a next
  /// marked start.
  final int? lengthDays;

  /// Days from the cycle's first higher measurement to the cycle's END,
  /// inclusively counted (the first-higher day itself counts as one): the
  /// cycle end exclusive is the NEXT marked start, or — for the trailing
  /// cycle, whose end is merely observed — one day past the last tracked
  /// day. Null when the cycle has no resolved first higher measurement.
  final int? firstHigherUntilCycleEndDays;
}

/// One fact row per mark-opened cycle (the leading pre-mark group is
/// excluded — it is not a cycle start). Starts sorted ascending, as the
/// grouping produces them.
List<CycleFact> cycleFacts(List<DailyEntry> entries, List<CycleMark> marks) {
  final cycles = groupIntoCycles(entries, marks);
  final evaluations = evaluateCycles(entries, marks);
  if (cycles.length != evaluations.length) {
    // Defensive only — evaluateCycles evaluates every group exactly once.
    throw StateError('cycle/evaluation count mismatch');
  }

  // The mark-opened starts in observation order: the length of one cycle
  // runs until the next mark-opened start, skipping the leading group.
  final starts = <DateTime>[];
  for (var i = 0; i < cycles.length; i++) {
    if (!cycles[i].startsAtMenstruation) continue;
    starts.add(DateOnly.normalize(cycles[i].startDate));
  }

  final facts = <CycleFact>[];
  var startSlot = 0;
  for (var i = 0; i < cycles.length; i++) {
    final cycle = cycles[i];
    if (!cycle.startsAtMenstruation) continue;
    final start = starts[startSlot];
    final nextStart = startSlot + 1 < starts.length
        ? starts[startSlot + 1]
        : null;
    startSlot++;

    var bleedingDays = 0;
    for (final day in cycle.days) {
      if (day.bleeding.level >= 1) bleedingDays++;
    }

    final firstHigher = _resolveFirstHigher(evaluations[i]);
    final endExclusive =
        nextStart ??
        // Observed end: one past the last TRACKED day (untracked days
        // carry nothing to observe).
        DateOnly.addDays(DateOnly.normalize(cycle.endDate), 1);

    facts.add(
      CycleFact(
        cycleStart: start,
        bleedingDays: bleedingDays,
        firstHigherDay: firstHigher,
        lengthDays: nextStart == null
            ? null
            : DateOnly.daysBetween(nextStart, start),
        firstHigherUntilCycleEndDays: firstHigher == null
            ? null
            : DateOnly.daysBetween(endExclusive, firstHigher),
      ),
    );
  }
  return facts;
}

/// The statistics value for one fact's first higher: [MarkKind.circle]
/// candidates lie strictly after the mucus peak (the evaluation classifies
/// per candidate); the earliest circle is the "real" first higher. No
/// circle at all — unknown peak, or the sequence never reached past the
/// peak — falls back to the user-placed mark day.
DateTime? _resolveFirstHigher(CycleEvaluation evaluation) {
  for (final candidate in evaluation.higherMeasurements) {
    if (candidate.markKind == MarkKind.circle) return candidate.date;
  }
  return evaluation.firstHigherDay;
}

/// Min/max/average/population standard deviation over one metric, or all
/// null when the metric has no data at all. Population std dev (÷ n, not
/// n − 1) is the descriptive spread a statistics tab reports.
final class MetricSummary {
  const MetricSummary({
    required this.min,
    required this.max,
    required this.average,
    required this.stdDev,
  });

  const MetricSummary.empty()
    : min = null,
      max = null,
      average = null,
      stdDev = null;

  final int? min;
  final int? max;

  /// Mean of the metric's values, or null when there is no data.
  final double? average;

  /// Population standard deviation (σ), or null when there is no data.
  final double? stdDev;
}

MetricSummary _summarize(List<int> values) {
  if (values.isEmpty) return const MetricSummary.empty();
  final count = values.length;
  final mean = values.fold<int>(0, (sum, v) => sum + v) / count;
  final variance =
      values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) / count;
  return MetricSummary(
    min: values.reduce((a, b) => a < b ? a : b),
    max: values.reduce((a, b) => a > b ? a : b),
    average: mean,
    stdDev: math.sqrt(variance),
  );
}

/// The statistics screen's aggregates over the per-cycle facts.
final class CycleStatistic {
  const CycleStatistic({
    required this.facts,
    required this.cycleCount,
    required this.cycleLengths,
    required this.bleedingDays,
    required this.firstHigherUntilCycleEnd,
    required this.earliestFirstHigherDayOfCycle,
  });

  /// One row per mark-opened cycle — the table data.
  final List<CycleFact> facts;

  /// The number of mark-opened cycles ([facts.length]).
  final int cycleCount;

  final MetricSummary cycleLengths;
  final MetricSummary bleedingDays;
  final MetricSummary firstHigherUntilCycleEnd;

  /// The earliest first higher measurement among all cycles, reported as
  /// the 1-based day-of-cycle number the chart renders
  /// (daysBetween(firstHigherDay, cycleStart) + 1). Null when no cycle has
  /// a resolved first higher measurement.
  final int? earliestFirstHigherDayOfCycle;
}

/// Aggregates the per-cycle facts of [cycleFacts] into the screen's
/// numbers. Pure arithmetic over the facts — the aggregates SKIP
/// facts whose metric is absent (trailing cycle length, missing first
/// higher) rather than treating them as zeros.
CycleStatistic cycleStatistics(
  List<DailyEntry> entries,
  List<CycleMark> marks,
) {
  final facts = cycleFacts(entries, marks);
  final lengths = [
    for (final fact in facts)
      if (fact.lengthDays != null) fact.lengthDays!,
  ];
  final bleedings = [for (final fact in facts) fact.bleedingDays];
  final firstHigherSpans = [
    for (final fact in facts)
      if (fact.firstHigherUntilCycleEndDays != null)
        fact.firstHigherUntilCycleEndDays!,
  ];

  var earliestDayOfCycle = 0;
  for (final fact in facts) {
    if (fact.firstHigherDay == null) continue;
    final dayNumber =
        DateOnly.daysBetween(fact.firstHigherDay!, fact.cycleStart) + 1;
    if (earliestDayOfCycle == 0 || dayNumber < earliestDayOfCycle) {
      earliestDayOfCycle = dayNumber;
    }
  }

  return CycleStatistic(
    facts: facts,
    cycleCount: facts.length,
    cycleLengths: _summarize(lengths),
    bleedingDays: _summarize(bleedings),
    firstHigherUntilCycleEnd: _summarize(firstHigherSpans),
    earliestFirstHigherDayOfCycle: earliestDayOfCycle == 0
        ? null
        : earliestDayOfCycle,
  );
}
