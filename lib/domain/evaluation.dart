// NER evaluation arithmetic (docs/cheatsheet.md §Auswertung): derive the
// evaluation artifacts from tracked entries plus user-placed marks.
//
// HARD RULE (ADR-0001, Mode M): the user places marks, the app computes,
// never interprets. Everything is COMPUTED ONLY at render time — nothing is
// persisted (no drift types, no Flutter imports). User-placed inputs: the
// mucus peak and the first higher measurement; the 1–6 numbering, the
// baseline, the circled/arrowed candidates, the baseline segment and the
// SUZ start are derived. The full R1–R10 rule list and the owner-settled
// interpretations live in docs/dev-notes.md ("NER evaluation rules").
//
// The temperature-IGNORE marks (CycleMarkTypes.ignoreTemperature — the mark
// token, not the raw disturbance mask) are the only analysis input: a marked
// day behaves like an unmeasured one in every rule. They leave the
// foreign-import cycleStart replay untouched (bleeding continuity — see
// lib/domain/drip_import.dart).

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// Circle when strictly after the mucus peak day, arrow otherwise (R4).
enum MarkKind { circle, arrow }

/// Which SUZ rule determined the SUZ start — the D→evening / E→morning
/// mapping IS the time-of-day semantics (the domain reports only the day,
/// see [CycleEvaluation.suzBegins]): [d] is the 3rd circled candidate
/// ≥ 0.2 K above the baseline, [e] the 4th circled candidate at any margin.
enum SuzRule { d, e }

/// One of the (up to) six numbered low measurements before the first higher
/// measurement.
final class NumberedLow {
  const NumberedLow({
    required this.number,
    required this.date,
    required this.value,
  });

  /// The 1–6 calendar-offset number: the measured, not-excluded day at
  /// rise−i carries number i; an omitted or excluded window day gets no
  /// number and its number is skipped ("6 5 _ 3 _ 1").
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

/// The x-extent of the drawn baseline segment (R10), null when the cycle
/// has no marked candidate (no segment is drawn). The baseline's y-value is
/// [CycleEvaluation.baseline].value; the chart painter adds the half-day
/// padding past [endDay]'s column when drawing.
final class BaselineSpan {
  const BaselineSpan({required this.startDay, required this.endDay});

  /// The earliest numbered low day (low #6 when six lows exist, the oldest
  /// available low otherwise).
  final DateTime startDay;

  /// The last marked candidate day (arrow or circle).
  final DateTime endDay;
}

/// One marked candidate of the connected candidate sequence (R1–R4): a
/// measured day strictly above the baseline, from the marked rise day
/// onward, complete at the SUZ trigger.
final class HigherMeasurement {
  const HigherMeasurement({
    required this.date,
    required this.value,
    required this.markKind,
    required this.ordinal,
    required this.differenceK,
  });

  final DateTime date;
  final double value;

  /// Circle or arrow, decided PER CANDIDATE (R4): arrow when the mucus peak
  /// is unset or the day is at or before the peak day, circle strictly
  /// after the peak day.
  final MarkKind markKind;

  /// The 1-based position WITHIN this candidate's own mark kind (circles
  /// 1–4 drive the SUZ rules D/E; null beyond the kind's four-cap — the
  /// candidate stays part of the sequence but unnumbered, R4).
  final int? ordinal;

  /// value minus the baseline value, always > 0 (R7 difference display
  /// input; the UI formats it).
  final double differenceK;
}

/// The earliest circle candidate's day (rule R4 — the circles the chart and
/// PDF rings draw), null when the sequence has no circle.
DateTime? firstCircledCandidateDay(CycleEvaluation evaluation) {
  for (final candidate in evaluation.higherMeasurements) {
    if (candidate.markKind == MarkKind.circle) return candidate.date;
  }
  return null;
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
    required this.baselineSpan,
    required this.suzBegins,
    required this.suzRule,
    required this.evaluationStopped,
    required this.riseMarkConsistent,
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

  /// The marked candidate sequence, chronological: the measured days
  /// strictly above the baseline from the marked rise day onward (R1/R3),
  /// each carrying its per-candidate [HigherMeasurement.markKind] and
  /// within-kind [HigherMeasurement.ordinal]. Empty when the rise is
  /// unmarked, the baseline is unknown, or the sequence has not started.
  final List<HigherMeasurement> higherMeasurements;

  /// The baseline segment extent (R10), or null when the cycle has no
  /// marked candidate (no segment is drawn).
  final BaselineSpan? baselineSpan;

  /// The day the sicher unfruchtbare Zeit begins — the SUZ-EVENING under
  /// rule D, the SUZ-MORNING under rule E (the rule-to-time mapping lives
  /// on [SuzRule]) — or null when no rule has triggered.
  final DateTime? suzBegins;

  /// [SuzRule.d] or [SuzRule.e], null while the SUZ is not determined.
  final SuzRule? suzRule;

  /// Whether the marked first-higher day carries a measured,
  /// not-marked-excluded temperature STRICTLY above the baseline (owner
  /// decision 2026-09-17: when not, the UI warns the user may have chosen
  /// a wrong day; the wording states the arithmetic fact, never a verdict).
  /// Null when the mark or the baseline is missing (the check is undefined);
  /// false when the marked day has no usable temperature or is not strictly
  /// above; true otherwise.
  final bool? riseMarkConsistent;

  /// True when R2 stopped the automatic evaluation mid-sequence (more than
  /// one intervening gap day — no re-search, the user re-marks the rise).
  /// False when the sequence ran out of data, completed at the SUZ trigger,
  /// or never started.
  final bool evaluationStopped;
}

/// Rule D margin: the 3rd circled candidate must lie at least this far above
/// the baseline.
const double _suzRuleDAboveBaselineK = 0.2;

/// Per-kind ordinal cap (R4): beyond four arrows / four circles, candidates
/// stay in the sequence unnumbered.
const int _marksPerKindCap = 4;

/// Comparison tolerance for the rule-D boundary: `baseline + 0.2` is not
/// exactly representable as a double, so an exact +0.2 measurement would be
/// wrongly rejected without it.
const double _epsilon = 1e-9;

/// Computes the evaluation artifacts for every cycle group.
///
/// The cycle windows are MARK-driven (see groupIntoCycles): a group opens
/// at the first tracked day on/after a user-placed cycleStart mark, and its
/// window starts at the MARK's own date ([Cycle.startDate] — which may lie
/// on an untracked gap day before the first tracked day).
///
/// Marks attach by date to the cycle whose
/// [Cycle.startDate, next cycle start) window contains them (the last
/// cycle's window is open-ended); marks before the first group are ignored.
///
/// [today] is the grouping's injected clock for the last-cycle span rule
/// (see lib/domain/cycle_grouping.dart).
List<CycleEvaluation> evaluateCycles(
  List<DailyEntry> entries,
  List<CycleMark> marks, {
  DateTime? today,
}) {
  // The ignored-day set: a marked-ignored day behaves like an unmeasured
  // day in every rule below.
  final excludedDays = <DateTime>{
    for (final mark in marks)
      if (mark.type == CycleMarkTypes.ignoreTemperature)
        DateOnly.normalize(mark.date),
  };

  final cycles = groupIntoCycles(entries, marks, today: today);

  final windows = <_LowWindow>[];
  for (var i = 0; i < cycles.length; i++) {
    windows.add(
      _lowWindowFor(cycles[i], marks, excludedDays, _nextStart(cycles, i)),
    );
  }

  final evaluations = <CycleEvaluation>[];
  for (var i = 0; i < cycles.length; i++) {
    final nextWindowStart = i + 1 < cycles.length
        ? windows[i + 1].startDay
        : null;
    evaluations.add(
      _evaluateCycle(
        cycles[i],
        marks,
        excludedDays,
        windows[i],
        _nextStart(cycles, i),
        nextWindowStart,
      ),
    );
  }
  return evaluations;
}

/// The start of the NEXT cycle's date window, or null for the last cycle.
/// Windows span [mark date, next mark date) — the MARK's own date anchors
/// the window, so an untracked gap between the mark and the group's first
/// tracked day belongs to the mark-opening cycle.
DateTime? _nextStart(List<Cycle> cycles, int index) => index + 1 < cycles.length
    ? DateOnly.normalize(cycles[index + 1].startDate)
    : null;

/// The most recent mark of [type] inside the cycle's [start, nextStart)
/// window, if any (owner rule: re-marking supersedes — delayed ovulation
/// and re-marked rises are expected; earlier duplicates stay stored but
/// stop anchoring; their removal is the mark sheet's toggle concern).
DateTime? _latestMarkOf(
  Cycle cycle,
  List<CycleMark> marks,
  String type,
  DateTime? nextCycleStart,
) {
  final cycleStart = DateOnly.normalize(cycle.startDate);
  DateTime? found;
  for (final mark in marks) {
    if (mark.type != type) continue;
    final day = DateOnly.normalize(mark.date);
    if (day.isBefore(cycleStart)) continue;
    if (nextCycleStart != null && !day.isBefore(nextCycleStart)) continue;
    if (found == null || day.isAfter(found)) found = day;
  }
  return found;
}

/// The six-low window of one cycle: the numbered lows, the baseline through
/// their highest, and the window's earliest day (the R10 segment start).
final class _LowWindow {
  const _LowWindow({
    required this.firstHigherDay,
    required this.numberedLows,
    required this.baseline,
  });

  static const empty = _LowWindow(
    firstHigherDay: null,
    numberedLows: [],
    baseline: null,
  );

  final DateTime? firstHigherDay;
  final List<NumberedLow> numberedLows;
  final BaselinePoint? baseline;

  /// The earliest numbered low day (low #6 when the window is fully
  /// measured, the oldest available low otherwise) — the R10
  /// baseline-segment START. Null when no usable low measurement exists.
  DateTime? get startDay {
    DateTime? earliest;
    for (final low in numberedLows) {
      if (earliest == null || low.date.isBefore(earliest)) earliest = low.date;
    }
    return earliest;
  }
}

_LowWindow _lowWindowFor(
  Cycle cycle,
  List<CycleMark> marks,
  Set<DateTime> excludedDays,
  DateTime? nextCycleStart,
) {
  final firstHigherDay = _latestMarkOf(
    cycle,
    marks,
    CycleMarkTypes.firstHigherMeasurement,
    nextCycleStart,
  );
  if (firstHigherDay == null) return _LowWindow.empty;

  // The six-low window is the six previous calendar days before the marked
  // rise, intersected with the group's tracked days; numbering belongs to
  // CALENDAR positions (the day at rise−i carries number i, gaps skip
  // theirs — "zurücknummerieren"). Truncation at the group's first tracked
  // day is conscious (owner: "should never happen physically").
  final byDay = {for (final e in cycle.days) DateOnly.normalize(e.date): e};
  final lows = <NumberedLow>[];
  for (var offset = 1; offset <= 6; offset++) {
    final day = DateOnly.addDays(firstHigherDay, -offset);
    final entry = byDay[day];
    // The day occupies its calendar position but contributes nothing.
    if (entry == null || entry.bbtC == null || excludedDays.contains(day)) {
      continue;
    }
    lows.add(NumberedLow(number: offset, date: day, value: entry.bbtC!));
  }

  BaselinePoint? baseline;
  if (lows.isNotEmpty) {
    var best = lows.first;
    for (final low in lows) {
      // Strictly greater keeps the EARLIEST maximum on ties.
      if (low.value > best.value) best = low;
    }
    baseline = BaselinePoint(date: best.date, value: best.value);
  }

  return _LowWindow(
    firstHigherDay: firstHigherDay,
    numberedLows: List.unmodifiable(lows),
    baseline: baseline,
  );
}

CycleEvaluation _evaluateCycle(
  Cycle cycle,
  List<CycleMark> marks,
  Set<DateTime> excludedDays,
  _LowWindow lowWindow,
  DateTime? nextCycleStart,
  DateTime? nextWindowStart,
) {
  final peakDay = _latestMarkOf(
    cycle,
    marks,
    CycleMarkTypes.mucusPeakDay,
    nextCycleStart,
  );

  final numberedLows = lowWindow.numberedLows;
  final baseline = lowWindow.baseline;
  final firstHigherDay = lowWindow.firstHigherDay;

  // Walk CALENDAR days from the marked rise so untracked days count as the
  // gaps they are. Unmeasured, mark-excluded and at/below-baseline days are
  // gaps just the same (R2); one gap day between candidates is tolerated,
  // two stop the automatic evaluation. The gap counting spans the whole
  // sequence, including the arrow→circle transition.
  final higherMeasurements = <HigherMeasurement>[];
  var evaluationStopped = false;
  DateTime? suzBegins;
  SuzRule? suzRule;
  BaselineSpan? baselineSpan;

  final byDay = {for (final e in cycle.days) DateOnly.normalize(e.date): e};
  bool? riseMarkConsistent;
  if (firstHigherDay != null && baseline != null) {
    final markedEntry = byDay[firstHigherDay];
    riseMarkConsistent =
        markedEntry == null ||
            markedEntry.bbtC == null ||
            excludedDays.contains(firstHigherDay)
        ? false
        : markedEntry.bbtC! > baseline.value;
  }

  if (baseline != null && firstHigherDay != null) {
    final lastDay = DateOnly.normalize(cycle.endDate);

    var sequenceStarted = false;
    var gapRun = 0;
    var arrowCount = 0;
    var circleCount = 0;

    for (
      var day = firstHigherDay;
      !day.isAfter(lastDay);
      day = DateOnly.addDays(day, 1)
    ) {
      final entry = byDay[day];

      if (entry == null ||
          entry.bbtC == null ||
          excludedDays.contains(day) ||
          entry.bbtC! <= baseline.value) {
        // A gap day before the first candidate does not count — nothing to
        // be connected to yet.
        if (sequenceStarted) gapRun++;
        continue;
      }

      if (sequenceStarted && gapRun > 1) {
        // R2: more than one intervening gap day — the evaluation stops.
        evaluationStopped = true;
        break;
      }

      sequenceStarted = true;
      gapRun = 0;

      final value = entry.bbtC!;
      // R4: arrow when the peak is unset or the day is at/before it;
      // circle strictly after it.
      final markKind =
          peakDay == null || DateOnly.daysBetween(peakDay, day) >= 0
          ? MarkKind.arrow
          : MarkKind.circle;

      final int? ordinal;
      switch (markKind) {
        case MarkKind.arrow:
          ordinal = arrowCount < _marksPerKindCap ? ++arrowCount : null;
        case MarkKind.circle:
          ordinal = circleCount < _marksPerKindCap ? ++circleCount : null;
      }

      higherMeasurements.add(
        HigherMeasurement(
          date: day,
          value: value,
          markKind: markKind,
          ordinal: ordinal,
          differenceK: value - baseline.value,
        ),
      );

      // R5: the SUZ fires on CIRCLED candidates only (the circle ordinal).
      if (markKind == MarkKind.circle && ordinal != null) {
        if (ordinal == 3) {
          if (value >= baseline.value + _suzRuleDAboveBaselineK - _epsilon) {
            // Rule D fired — SUZ begins this evening.
            suzBegins = day;
            suzRule = SuzRule.d;
            break;
          }
          // Below the margin: rule E may still fire at the 4th circle.
        } else if (ordinal == 4) {
          // Rule E: the 3rd circle was below the margin, so the 4th circle
          // — any margin — fires, SUZ this morning.
          suzBegins = day;
          suzRule = SuzRule.e;
          break;
        }
      }
    }

    // R10: baseline segment — earliest numbered low day to last marked
    // candidate, clamped to the next cycle start / six-low window.
    final spanStart = lowWindow.startDay;
    if (spanStart != null && higherMeasurements.isNotEmpty) {
      var spanEnd = higherMeasurements.last.date;
      if (nextCycleStart != null && nextCycleStart.isBefore(spanEnd)) {
        spanEnd = nextCycleStart;
      }
      if (nextWindowStart != null && nextWindowStart.isBefore(spanEnd)) {
        spanEnd = nextWindowStart;
      }
      baselineSpan = BaselineSpan(startDay: spanStart, endDay: spanEnd);
    }
  }

  return CycleEvaluation(
    cycle: cycle,
    mucusPeakDay: peakDay,
    firstHigherDay: firstHigherDay,
    numberedLows: numberedLows,
    baseline: baseline,
    higherMeasurements: List.unmodifiable(higherMeasurements),
    baselineSpan: baselineSpan,
    suzBegins: suzBegins,
    suzRule: suzRule,
    evaluationStopped: evaluationStopped,
    riseMarkConsistent: riseMarkConsistent,
  );
}
