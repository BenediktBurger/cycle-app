// NER evaluation arithmetic: derive the evaluation artifacts from tracked
// entries plus user-placed marks. The book rule vocabulary is
// docs/NER/rules.md; the app conventions and owner-settled interpretations
// are docs/NER/app-conventions.md.
//
// HARD RULE (ADR-0001, Mode M): the user places marks, the app computes,
// never interprets. Everything is COMPUTED ONLY at render time — nothing is
// persisted (no drift types, no Flutter imports). User-placed inputs: the
// mucus peak and the temperature rise; the 1–6 numbering, the
// baseline, the circled/arrowed candidates, the baseline segment and the
// „Sicher unfruchtbare Zeit“ start are derived.
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

/// „Höhere Messung“ vs „Pfeilmessung“: circle strictly after the mucus peak
/// day, arrow at or before it (or with the peak unset) — app convention
/// "candidate walk".
enum MarkKind { circle, arrow }

/// Which book case determined the „Sicher unfruchtbare Zeit“ start.
/// [evening]: „Sicher unfruchtbare Zeit am Abend“ — the 3rd circled candidate
/// lies at least 0.2 K above the Basislinie; the quoted book text starts it
/// that evening.
/// [morning]: the „Erster Sonderfall“ — the book awaits a 4th higher
/// measurement. The higher measurements are waking temperatures, so the 4th
/// is read in the morning and the „Sicher unfruchtbare Zeit“ begins that
/// morning (derived, see docs/NER/rules.md).
enum SuzRule { evening, morning }

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

/// The x-extent of the drawn baseline segment (app convention "baseline
/// line extent"), null when the cycle has no marked candidate (no segment
/// is drawn). The baseline's y-value is [CycleEvaluation.baseline].value;
/// the chart painter adds the half-day padding past [endDay]'s column when
/// drawing.
final class BaselineSpan {
  const BaselineSpan({required this.startDay, required this.endDay});

  /// The earliest numbered low day (low #6 when six lows exist, the oldest
  /// available low otherwise).
  final DateTime startDay;

  /// The last marked candidate day (arrow or circle).
  final DateTime endDay;
}

/// One marked candidate of the connected candidate sequence („Höhere
/// Messung“ / „Pfeilmessung“; app convention "candidate walk"): a measured
/// day strictly above the baseline, from the marked rise day onward,
/// complete at the „Sicher unfruchtbare Zeit“ trigger.
///
/// Named app-neutrally because the book's „höhere Messung“ is the circled
/// measurement and its arrows are „Pfeilmessungen“, while this sequence
/// carries both kinds until the per-candidate [markKind] decides.
final class CandidateMeasurement {
  const CandidateMeasurement({
    required this.date,
    required this.value,
    required this.markKind,
    required this.ordinal,
    required this.differenceK,
  });

  final DateTime date;
  final double value;

  /// Circle or arrow, decided PER CANDIDATE („Höhere Messung“ vs
  /// „Pfeilmessung“, app convention "candidate walk"): arrow when the mucus
  /// peak is unset or the day is at or before the peak day, circle strictly
  /// after the peak day.
  final MarkKind markKind;

  /// The 1-based position WITHIN this candidate's own mark kind (circles
  /// 1–4 drive „Sicher unfruchtbare Zeit am Abend“ / „Erster Sonderfall“;
  /// null beyond the kind's four-cap — the candidate stays part of the
  /// sequence but unnumbered, app convention "per-kind cap").
  final int? ordinal;

  /// value minus the baseline value, always > 0 (app convention "baseline
  /// difference"; the UI formats it).
  final double differenceK;
}

/// The earliest circle candidate's day („Höhere Messung“ — the circles the
/// chart and PDF rings draw), null when the sequence has no circle.
DateTime? firstCircledCandidateDay(CycleEvaluation evaluation) {
  for (final candidate in evaluation.candidateMeasurements) {
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
    required this.candidateMeasurements,
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

  /// The user-placed temperature rise (the marked anchor), or null when
  /// unmarked.
  final DateTime? firstHigherDay;

  /// Up to six numbered low measurements before the first higher
  /// measurement, ordered by number (1 = closest to the first higher).
  final List<NumberedLow> numberedLows;

  /// Baseline through the highest of the six lows, or null when no usable
  /// low measurement exists (no first-higher mark, or none measured).
  final BaselinePoint? baseline;

  /// The marked candidate sequence, chronological: the measured days
  /// strictly above the baseline from the marked rise day onward
  /// („Temperaturanstieg“ / „Höhere Messung“; app conventions "candidate
  /// walk" and "latest-mark anchor"), each carrying its per-candidate
  /// [CandidateMeasurement.markKind] and within-kind
  /// [CandidateMeasurement.ordinal]. Empty when the rise is unmarked, the
  /// baseline is unknown, or the sequence has not started.
  final List<CandidateMeasurement> candidateMeasurements;

  /// The baseline segment extent (app convention "baseline line extent"),
  /// or null when the cycle has no marked candidate (no segment is drawn).
  final BaselineSpan? baselineSpan;

  /// The day the „Sicher unfruchtbare Zeit“ begins — the day of the circled
  /// candidate that triggered it — or null while no case has triggered. The
  /// domain reports the trigger day; [SuzRule.morning]'s start is that
  /// morning, [SuzRule.evening]'s that evening.
  final DateTime? suzBegins;

  /// [SuzRule.evening] or [SuzRule.morning], null while the
  /// „Sicher unfruchtbare Zeit“ is not determined.
  final SuzRule? suzRule;

  /// Whether the marked first-higher day carries a measured,
  /// not-marked-excluded temperature STRICTLY above the baseline (owner
  /// decision 2026-09-17: when not, the UI warns the user may have chosen
  /// a wrong day; the wording states the arithmetic fact, never a verdict).
  /// Null when the mark or the baseline is missing (the check is undefined);
  /// false when the marked day has no usable temperature or is not strictly
  /// above; true otherwise.
  final bool? riseMarkConsistent;

  /// True when app convention "gap tolerance" stopped the automatic
  /// evaluation mid-sequence: a second excluded day ended the run at the
  /// next above-baseline day (no re-search, the user re-marks the rise).
  /// False when the sequence ran out of data, completed at the „Sicher
  /// unfruchtbare Zeit“ trigger, or never started.
  final bool evaluationStopped;
}

/// „Sicher unfruchtbare Zeit am Abend“: the 3rd circled measurement must
/// lie at least this far (0.2 K) above the Basislinie.
const double _suzEveningMarginK = 0.2;

/// Per-kind ordinal cap (app convention "per-kind cap"): beyond four arrows
/// / four circles, candidates stay in the sequence unnumbered.
const int _marksPerKindCap = 4;

/// Comparison tolerance for the „Sicher unfruchtbare Zeit am Abend“
/// boundary: `baseline + 0.2` is not exactly representable as a double, so
/// an exact +0.2 measurement would be wrongly rejected without it.
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
    final nextLowWindowStart = i + 1 < cycles.length
        ? windows[i + 1].startDay
        : null;
    evaluations.add(
      _evaluateCycle(
        cycles[i],
        marks,
        excludedDays,
        windows[i],
        _nextStart(cycles, i),
        nextLowWindowStart,
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
/// their highest, and the window's earliest day (the baseline-segment
/// start).
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
  /// measured, the oldest available low otherwise) — the baseline
  /// segment's START. Null when no usable low measurement exists.
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

/// The day's measured temperature when it is usable and strictly above
/// [baselineValue]; null for untracked, unmeasured, excluded and
/// at/below-baseline days — the gap class of app convention "gap
/// tolerance".
double? _candidateValue(
  Map<DateTime, DailyEntry> byDay,
  DateTime day,
  Set<DateTime> excludedDays,
  double baselineValue,
) {
  final entry = byDay[day];
  if (entry == null || entry.bbtC == null || excludedDays.contains(day)) {
    return null;
  }
  final value = entry.bbtC!;
  return value > baselineValue ? value : null;
}

SuzRule? _suzRuleFor({
  required int ordinal,
  required double value,
  required double baselineValue,
}) {
  if (ordinal == 3) {
    if (value >= baselineValue + _suzEveningMarginK - _epsilon) {
      // „Sicher unfruchtbare Zeit am Abend“: it begins this evening.
      return SuzRule.evening;
    }
    // Below the margin: the „Erster Sonderfall“ may still fire at the 4th
    // circle.
    return null;
  }
  if (ordinal == 4) {
    // „Erster Sonderfall“ (vierte höhere Messung): the 3rd circle was below
    // the margin, so the 4th circle — any margin above the Basislinie —
    // fires. The 4th is a waking temperature, so the start is its morning
    // (derived, see SuzRule).
    return SuzRule.morning;
  }
  return null;
}

CycleEvaluation _evaluateCycle(
  Cycle cycle,
  List<CycleMark> marks,
  Set<DateTime> excludedDays,
  _LowWindow lowWindow,
  DateTime? nextCycleStart,
  DateTime? nextLowWindowStart,
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
  // gaps they are. Unmeasured, mark-excluded and at/below-baseline days form
  // one gap class (app convention "gap tolerance"). The run tolerates ONE
  // such day in total: a second one ends the search at the next
  // above-baseline day, so the budget spans arrows and circles and is not
  // refreshed by a candidate. Gap days before the first candidate consume
  // nothing — the sequence has not started.
  final candidateMeasurements = <CandidateMeasurement>[];
  var evaluationStopped = false;
  DateTime? suzBegins;
  SuzRule? suzRule;
  BaselineSpan? baselineSpan;

  final byDay = {for (final e in cycle.days) DateOnly.normalize(e.date): e};
  bool? riseMarkConsistent;

  if (baseline != null && firstHigherDay != null) {
    riseMarkConsistent =
        _candidateValue(byDay, firstHigherDay, excludedDays, baseline.value) !=
        null;
    final lastDay = DateOnly.normalize(cycle.endDate);

    var sequenceStarted = false;
    var gapDays = 0;
    var arrowCount = 0;
    var circleCount = 0;

    for (
      var day = firstHigherDay;
      !day.isAfter(lastDay);
      day = DateOnly.addDays(day, 1)
    ) {
      final value = _candidateValue(byDay, day, excludedDays, baseline.value);

      if (value == null) {
        // A gap day before the first candidate does not count — nothing to
        // be connected to yet.
        if (sequenceStarted) gapDays++;
        continue;
      }

      if (sequenceStarted && gapDays > 1) {
        evaluationStopped = true;
        break;
      }

      sequenceStarted = true;

      // App convention "candidate walk" („Höhere Messung“ vs
      // „Pfeilmessung“): arrow when the peak is unset or the day is
      // at/before it; circle strictly after it.
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

      candidateMeasurements.add(
        CandidateMeasurement(
          date: day,
          value: value,
          markKind: markKind,
          ordinal: ordinal,
          differenceK: value - baseline.value,
        ),
      );

      // „Sicher unfruchtbare Zeit am Abend“ / „Erster Sonderfall“: the
      // trigger fires on CIRCLED candidates only (the circle ordinal).
      final rule = markKind == MarkKind.circle && ordinal != null
          ? _suzRuleFor(
              ordinal: ordinal,
              value: value,
              baselineValue: baseline.value,
            )
          : null;
      if (rule != null) {
        suzBegins = day;
        suzRule = rule;
        break;
      }
    }

    // App convention "baseline line extent": baseline segment — earliest
    // numbered low day to last marked candidate, clamped to the next cycle
    // start / the next cycle's six-low window start.
    final spanStart = lowWindow.startDay;
    if (spanStart != null && candidateMeasurements.isNotEmpty) {
      var spanEnd = candidateMeasurements.last.date;
      if (nextCycleStart != null && nextCycleStart.isBefore(spanEnd)) {
        spanEnd = nextCycleStart;
      }
      if (nextLowWindowStart != null && nextLowWindowStart.isBefore(spanEnd)) {
        spanEnd = nextLowWindowStart;
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
    candidateMeasurements: List.unmodifiable(candidateMeasurements),
    baselineSpan: baselineSpan,
    suzBegins: suzBegins,
    suzRule: suzRule,
    evaluationStopped: evaluationStopped,
    riseMarkConsistent: riseMarkConsistent,
  );
}
