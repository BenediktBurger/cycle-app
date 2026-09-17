// Evaluation arithmetic: derive the NER evaluation artifacts (docs/
// cheatsheet.md §Auswertung) from tracked entries plus user-placed marks.
//
// HARD RULE (ADR-0001, Mode M): the user places marks, the app computes,
// never interprets. Everything produced here is COMPUTED ONLY at render
// time — nothing in this file is persisted (no drift types, no Flutter
// imports). The user-placed inputs are the mucus peak
// (CycleMarkTypes.mucusPeakDay) and the first higher measurement
// (CycleMarkTypes.firstHigherMeasurement); the 1–6 numbering, the baseline,
// the circled higher measurements and the SUZ evening date are derived.
//
// Interpretive assumptions (validate with an expert reviewer, see
// docs/adr/0001-iner-mode-m-hypothesis.md, status: Hypothesis):
//
//   TODO(user-review): A "low" measurement is any usable day (temperature
//   measured, no exclusion flag) strictly before the user-marked first
//   higher measurement. The cheat sheet does not define "tief" beyond the
//   numbering rule; a high pre-rise temperature can therefore legitimately
//   sit inside the six-low window and set the baseline when the user
//   marked the first higher late (the textbook "Zacken" are usually
//   excluded days anyway). The peak day itself counts as a low when it
//   falls into the window — its mucus role does not exempt its temperature.
//   TODO(user-review): Excluded days and untracked days (data gaps)
//   consume no 1–6 slot. Symmetrically, an excluded day is never a circled
//   higher measurement either — a disturbed day cannot prove the rise
//   (the cheat sheet brackets "Zacken" instead of circling them).
//   TODO(user-review): Numbering counts BACKWARDS from the first higher
//   measurement ("zurücknummerieren"): the low directly before it is 1.
//   The chronological alternative (1..6 ending right before the rise) is
//   plausible; only the [NumberedLow.number] field is affected.
//   TODO(user-review): "Higher" is the locked working definition: value
//   >= baseline + 0.2 K. A day exactly at the baseline is NOT higher. The
//   peak day itself is never a higher candidate (mucus and temperature
//   peaks rarely coincide, and the peak's own temperature has no role in
//   the cheat-sheet rules).
//   TODO(user-review): The SUZ evening date is the day of the 3rd circled
//   higher measurement, assumed to be the trigger even when fewer/more
//   preceding circled measurements exist than the textbook pattern. Given
//   the locked "higher" definition, the cheat sheet's ">= 0.2 K above the
//   baseline" condition is implied by being circled at all.
//   TODO(user-review): The user-marked first higher measurement is taken
//   verbatim for the six-low window and the baseline, even when it is not
//   itself >= baseline + 0.2 K. The circled set is computed independently
//   from the arithmetic, so on noisy data the mark and the circles can
//   disagree — the UI shows what the arithmetic says.
//   TODO(user-review): Several peak / first-higher marks inside one cycle
//   are a user-data problem; the earliest mark wins.
//
// Input contract: [evaluateCycles] expects entries and marks of ONE profile
// (pass [evaluateCycles.profileId] to have foreign-profile data filtered
// out defensively; the UI providers already deliver per-profile data).

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// Where a higher measurement sits relative to the user-placed mucus peak —
/// the fact the UI needs to choose between circling (after the peak) and
/// the arrow-up glyph (before the peak).
enum HigherPosition { beforePeak, afterPeak }

/// One of the (up to) six numbered low measurements before the first higher
/// measurement.
final class NumberedLow {
  const NumberedLow({
    required this.number,
    required this.date,
    required this.value,
  });

  /// The 1–6 number (counting BACK from the first higher measurement, see
  /// the file-header assumption).
  final int number;

  final DateTime date;
  final double value;
}

/// The baseline: drawn through the HIGHEST of the six low measurements.
final class BaselinePoint {
  const BaselinePoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

/// One measured day at least 0.2 K above the baseline ("höhere Messung").
final class HigherMeasurement {
  const HigherMeasurement({
    required this.date,
    required this.value,
    required this.position,
    required this.circleOrd,
  });

  final DateTime date;
  final double value;

  /// Relative to the mucus peak. Null when the cycle has no peak mark —
  /// the position is then unknowable and the UI can decide to draw nothing.
  final HigherPosition? position;

  /// 1, 2 or 3 when this is one of the three circled higher measurements
  /// after the peak; null otherwise (before the peak, or a later higher
  /// measurement beyond the 3rd circle).
  final int? circleOrd;
}

/// The computed evaluation of ONE cycle group. Every field is derivable —
/// anything the user has not marked (or the arithmetic cannot decide) is
/// null/empty, letting the UI render partial evaluations.
final class CycleEvaluation {
  const CycleEvaluation({
    required this.cycle,
    required this.mucusPeakDay,
    required this.firstHigherDay,
    required this.numberedLows,
    required this.baseline,
    required this.higherMeasurements,
    required this.suzBeginsEvening,
  });

  /// The cycle group this evaluation belongs to (start/end for UI framing).
  final Cycle cycle;

  /// The user-placed mucus peak day, or null when unmarked.
  final DateTime? mucusPeakDay;

  /// The user-placed first higher measurement, or null when unmarked.
  final DateTime? firstHigherDay;

  /// Up to six numbered low measurements before the first higher
  /// measurement, ordered by number (1 = closest to the first higher).
  final List<NumberedLow> numberedLows;

  /// Baseline through the highest of the six lows, or null when no usable
  /// low measurement exists (no first-higher mark, or none measured).
  final BaselinePoint? baseline;

  /// Every measured day at least 0.2 K above the baseline, chronological.
  final List<HigherMeasurement> higherMeasurements;

  /// The evening date on which the sicher unfruchtbare Zeit begins, or null
  /// when fewer than three higher measurements were circled after the peak.
  final DateTime? suzBeginsEvening;
}

/// Working definition locked with the owner: a later measurement counts as
/// *higher* when it is at least 0.2 K above the baseline.
const double _riseAboveBaselineK = 0.2;

/// Comparison tolerance: temperatures are recorded with two fraction
/// digits, but `baseline + 0.2` is binary-floating-point-imprecise (36.4 +
/// 0.2 evaluates above the nearest double to 36.6), which would wrongly
/// reject an exact +0.2 measurement without the tolerance.
const double _epsilon = 1e-9;

/// Computes the evaluation artifacts for every cycle group (see
/// groupIntoCycles for the boundary rule).
///
/// Marks are attached to a cycle by date: a mark belongs to the cycle whose
/// [Cycle.startDate, next cycle start) window contains it (the last cycle's
/// window is open-ended); marks before the first group are ignored.
List<CycleEvaluation> evaluateCycles(
  List<DailyEntry> entries,
  List<CycleMark> marks, {
  int? profileId,
}) {
  final profileEntries = profileId == null
      ? entries
      : entries.where((e) => e.profileId == profileId).toList();
  final profileMarks = profileId == null
      ? marks
      : marks.where((m) => m.profileId == profileId).toList();

  final cycles = groupIntoCycles(profileEntries);
  final evaluations = <CycleEvaluation>[];
  for (var i = 0; i < cycles.length; i++) {
    final nextCycleStart =
        i + 1 < cycles.length ? DateOnly.normalize(cycles[i + 1].startDate) : null;
    evaluations.add(_evaluateCycle(cycles[i], profileMarks, nextCycleStart));
  }
  return evaluations;
}

CycleEvaluation _evaluateCycle(
  Cycle cycle,
  List<CycleMark> marks,
  DateTime? nextCycleStart,
) {
  final cycleStart = DateOnly.normalize(cycle.startDate);

  /// The earliest mark of [type] inside this cycle's date window, if any.
  DateTime? earliestMarkOf(String type) {
    DateTime? found;
    for (final mark in marks) {
      if (mark.type != type) continue;
      final day = DateOnly.normalize(mark.date);
      if (day.isBefore(cycleStart)) continue;
      if (nextCycleStart != null && !day.isBefore(nextCycleStart)) continue;
      if (found == null || day.isBefore(found)) found = day;
    }
    return found;
  }

  final peakDay = earliestMarkOf(CycleMarkTypes.mucusPeakDay);
  final firstHigherDay = earliestMarkOf(CycleMarkTypes.firstHigherMeasurement);

  // Usable measurements: temperature recorded and no exclusion flag (see
  // the file-header assumptions for the symmetric exclusion rule).
  // cycle.days is sorted ascending by groupIntoCycles.
  final usable = cycle.days
      .where((e) => e.bbtC != null && !e.isExcluded)
      .toList(growable: false);

  // Six low measurements before the first higher, counting BACK (number 1
  // = the low immediately before the first higher).
  var numberedLows = const <NumberedLow>[];
  BaselinePoint? baseline;
  if (firstHigherDay != null) {
    final prior = usable
        .where((e) => DateOnly.daysBetween(firstHigherDay, e.date) > 0)
        .toList();
    final window = prior.length > 6 ? prior.sublist(prior.length - 6) : prior;

    final lows = <NumberedLow>[];
    for (var i = window.length - 1, number = 1; i >= 0; i--, number++) {
      lows.add(NumberedLow(
        number: number,
        date: DateOnly.normalize(window[i].date),
        value: window[i].bbtC!,
      ));
    }
    numberedLows = List.unmodifiable(lows);

    if (window.isNotEmpty) {
      var best = window.first;
      for (final e in window) {
        // Strictly greater keeps the EARLIEST maximum on ties.
        if (e.bbtC! > best.bbtC!) best = e;
      }
      baseline = BaselinePoint(
        date: DateOnly.normalize(best.date),
        value: best.bbtC!,
      );
    }
  }

  // Higher measurements: every usable day at least 0.2 K above the
  // baseline. Position relative to the peak decides circle vs arrow-up;
  // only the first three after-peak measurements are circled.
  final higherMeasurements = <HigherMeasurement>[];
  DateTime? suzBeginsEvening;
  if (baseline != null) {
    final threshold = baseline.value + _riseAboveBaselineK - _epsilon;
    var circled = 0;
    for (final e in usable) {
      final value = e.bbtC!;
      if (value < threshold) continue;

      final day = DateOnly.normalize(e.date);
      HigherPosition? position;
      if (peakDay != null) {
        final daysFromPeak = DateOnly.daysBetween(day, peakDay);
        if (daysFromPeak < 0) {
          position = HigherPosition.beforePeak;
        } else if (daysFromPeak > 0) {
          position = HigherPosition.afterPeak;
        } else {
          continue; // the peak day itself is never a higher candidate
        }
      }

      int? circleOrd;
      if (position == HigherPosition.afterPeak) {
        circled++;
        if (circled <= 3) {
          circleOrd = circled;
          if (circled == 3) suzBeginsEvening = day;
        }
      }
      higherMeasurements.add(HigherMeasurement(
        date: day,
        value: value,
        position: position,
        circleOrd: circleOrd,
      ));
    }
  }

  return CycleEvaluation(
    cycle: cycle,
    mucusPeakDay: peakDay,
    firstHigherDay: firstHigherDay,
    numberedLows: numberedLows,
    baseline: baseline,
    higherMeasurements: List.unmodifiable(higherMeasurements),
    suzBeginsEvening: suzBeginsEvening,
  );
}
