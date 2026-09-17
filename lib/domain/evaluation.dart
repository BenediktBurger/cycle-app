// Evaluation arithmetic: derive the NER evaluation artifacts (docs/
// cheatsheet.md §Auswertung) from tracked entries plus user-placed marks.
//
// HARD RULE (ADR-0001, Mode M): the user places marks, the app computes,
// never interprets. Everything produced here is COMPUTED ONLY at render
// time — nothing in this file is persisted (no drift types, no Flutter
// imports). The user-placed inputs are the mucus peak
// (CycleMarkTypes.mucusPeakDay) and the first higher measurement
// (CycleMarkTypes.firstHigherMeasurement); the 1–6 numbering, the baseline,
// the circled/arrowed higher measurements, the baseline segment and the SUZ
// evening date are derived.
//
// Rules implemented here (owner-reviewed; the per-candidate mark kinds and
// the baseline segment are the latest owner corrections):
//
//   R1  Candidacy: every measured day STRICTLY ABOVE the baseline is a
//       candidate, regardless of the margin. The 0.2 K margin survives only
//       inside SUZ rule D.
//   R2  Connectedness: between consecutive candidates at most ONE
//       intervening day may be missing (no measured temperature), excluded,
//       or at/below the baseline. With more than one such day the automatic
//       evaluation STOPS (evaluationStopped): no SUZ, and nothing further is
//       marked — there is no automatic re-search; the user is expected to
//       place a NEW first-higher-measurement mark at the next higher
//       measurement. The rule applies across the WHOLE candidate sequence,
//       INCLUDING the arrow→circle transition — mixed sequences are one
//       sequence for gap counting.
//   R3  Candidate region: candidates exist only from the marked rise day
//       (first higher measurement) onward. The rise anchor is the MOST
//       RECENT firstHigherMeasurement mark of the cycle (owner-confirmed:
//       re-marking supersedes — after a broken Hochlage or a delayed
//       second peak the user re-marks the rise; the earlier mark stays
//       stored and, lying before the walk region, renders no candidate).
//       Above-baseline values before the rise are user error or a
//       separately-handled disturbance and never become candidates.
//   R4  Arrow vs circle, PER CANDIDATE: each candidate is an ARROW when the
//       mucus peak is not set at all, or the candidate day is at or before
//       the peak day (the peak day's own above-baseline temperature is an
//       ARROW); every candidate AFTER the peak day is a CIRCLE. The peak
//       anchor is the MOST RECENT marked peak of the cycle
//       ("Höhepunkt = letzter Tag mit der besten Qualität"): multiple
//       peaks arise from delayed ovulation — a peak subsides and a later
//       one appears — so the last marked peak is the ovulation that
//       counts here. When a later peak is added, earlier candidates flip
//       from circles back to arrows automatically (compute-only
//       re-evaluation, no mark changes).
//       Chronologically arrows precede circles — no interleaving. The caps
//       are PER KIND: up to four arrows carry arrow ordinals 1–4, then up
//       to four circles carry circle ordinals 1–4. Candidates beyond their
//       kind's cap stay part of the connected sequence UNNUMBERED (ordinal
//       null), so a late peak does not swallow the circles that follow it.
//   R5  SUZ rules D and E count CIRCLED measurements only (the cheat sheet
//       speaks of the "umrandete" — circled — higher measurement; the
//       circle ordinal within its own kind drives the trigger, arrows never
//       start the SUZ). D: the 3rd CIRCLE at least 0.2 K above the baseline
//       starts the SUZ that evening ("gegen Abendessen"). E: when the 3rd
//       circle is below that margin, the 4th CIRCLE — ANY margin — starts
//       the SUZ that evening. Both require R2 connectedness; a break before
//       the trigger leaves the SUZ undetermined. Once a rule fires the
//       sequence is complete — later candidates stay unmarked.
//   R7  Every marked candidate carries its difference to the baseline
//       (differenceK) so the UI can render it without arithmetic.
//   R9  The six-low numbering and the baseline are unchanged (see the
//       interpretive assumptions below).
//   R10 Baseline SEGMENT: the evaluation reports the x-extent the drawn
//       baseline line covers (baselineSpan). START: the earliest numbered
//       low day (low #6; see the TODO below for the fewer-than-six case).
//       END: the last marked candidate day (arrow or circle), defensively
//       clamped by the next menstruation start and by the next cycle's
//       six-low window start per R10's min() definition — under the current
//       grouping both clamps cannot bind (the next cycle always starts
//       after this cycle's days); they are kept because R10 defines them.
//       The "+ half a day" R10 padding past the end day's column is a
//       rendering concern of the chart, not domain arithmetic. A cycle with
//       NO marked candidate draws no segment (null span).
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
//   TODO(user-review): Untracked days (data gaps) and unmeasured days
//   consume no 1–6 slot. Symmetrically, an excluded day is never a marked
//   candidate either — a disturbed day cannot prove the rise (the cheat
//   sheet brackets "Zacken" instead of circling them).
//   TODO(user-review): Numbering counts BACKWARDS from the first higher
//   measurement ("zurücknummerieren"): the low directly before it is 1.
//   The chronological alternative (1..6 ending right before the rise) is
//   plausible; only the [NumberedLow.number] field is affected.
//   TODO(user-review): An EXCLUDED day inside the candidate sequence is
//   treated like a missing day (it consumes the one-gap allowance of R2).
//   The owner's rules text only covers "missing or at/below baseline";
//   excluded-as-missing is this implementation's interpretation.
//   TODO(user-review): The SUZ (rules D and E) is declared only from
//   CIRCLED measurements — the cheat sheet's rule wording speaks of the
//   "umrandete höhere Messung" (the circled higher measurement), and the
//   owner confirmed that reading. Circles exist only AFTER the mucus peak
//   day (R4), so an arrow sequence (peak unset, or all candidates at or
//   before the peak) never yields an SUZ. The flag stays until expert
//   review; it is not declared resolved here.
//   TODO(user-review): R10 with fewer than six numbered lows: the segment
//   START falls on the earliest AVAILABLE low day instead of a low #6 that
//   does not exist. R10 defines only the six-low case; the fallback is this
//   implementation's choice (the segment simply starts at the left edge of
//   whatever low window exists).
//   TODO(user-review): R10 end-of-segment handling: the end day is the last
//   marked candidate; the "+ half a day" padding past that day's column is
//   applied by the chart painter, and the min() clamps (cycle end, next
//   six-low window) are defensive — under the current cycle grouping they
//   can never bind. If a future grouping change makes them bind, revisit.
//   TODO(user-review): The user-marked first higher measurement is taken
//   verbatim for the six-low window and the baseline, even when the
//   marked day itself is not above the baseline. The candidate search
//   then starts at the next strictly-above measurement from the mark
//   onward (R3); on noisy data the mark and the candidates can disagree —
//   the UI shows what the arithmetic says.
//   No open assumption, settled rule: multiple peak / first-higher marks
//   inside one cycle are EXPECTED, not a user-data problem (delayed
//   ovulation; re-marking after a broken Hochlage). The MOST RECENT mark
//   of each type anchors the evaluation (owner-confirmed — see R3/R4);
//   earlier duplicates stay stored, render no candidate, and are removed
//   only through the sheet's mark toggles.
//
// Input contract: [evaluateCycles] expects entries and marks of ONE profile
// (pass [evaluateCycles.profileId] to have foreign-profile data filtered
// out defensively; the UI providers already deliver per-profile data).

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// How a marked candidate renders (R4, decided PER CANDIDATE): a CIRCLE for
/// every candidate strictly after the mucus peak day; an UP-POINTING ARROW
/// when the peak is unset or the candidate day is at or before the peak day
/// (the peak day's own above-baseline candidate is an arrow).
enum MarkKind { circle, arrow }

/// Which SUZ rule determined the SUZ evening: D (3rd circled candidate
/// ≥ 0.2 K above the baseline) or E (4th circled candidate at any margin,
/// after a 3rd circle below that margin). Null while the SUZ is not yet
/// determined.
enum SuzRule { d, e }

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

/// The x-extent of the drawn baseline segment (R10): the line runs from the
/// earliest numbered low day to the last marked candidate day. The
/// baseline's y-value is [CycleEvaluation.baseline].value. Null when the
/// cycle has no marked candidate — R10 draws no segment there.
final class BaselineSpan {
  const BaselineSpan({required this.startDay, required this.endDay});

  /// The earliest numbered low day (low #6 when six lows exist; the oldest
  /// available low otherwise — see the file-header TODO on the
  /// fewer-than-six case).
  final DateTime startDay;

  /// The last marked candidate day (arrow or circle), clamped per R10 by
  /// the next menstruation start and the next cycle's six-low window start
  /// (defensive — see the file-header TODO). The chart painter adds the
  /// "+ half a day" padding past this day's column when drawing.
  final DateTime endDay;
}

/// One marked candidate of the connected candidate sequence (R1–R4): a
/// measured day strictly above the baseline, from the marked rise day
/// onward. Candidates after the SUZ trigger are NOT listed — the sequence
/// is complete there.
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

  /// The 1-based position WITHIN this candidate's own mark kind: the circle
  /// ordinal counts circles only (1–4) and drives the SUZ rules D/E; the
  /// arrow ordinal counts arrows only (1–4) and expresses the arrow cap.
  /// Null when the candidate lies beyond its kind's four-cap — it stays
  /// part of the connected sequence but is unnumbered (R4).
  ///
  /// For the sheet's info line: CIRCLES show this circle ordinal
  /// ("3. umrandete Messung"); ARROW ordinals are curve-rendering input
  /// only — the sheet does not display them.
  final int? ordinal;

  /// value minus the baseline value, always > 0 (R7: the difference display
  /// input; the UI formats it, no arithmetic there).
  final double differenceK;
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
    required this.suzBeginsEvening,
    required this.suzRule,
    required this.evaluationStopped,
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
  /// within-kind [HigherMeasurement.ordinal] (null beyond the kind's
  /// four-cap). Empty when the rise is unmarked, the baseline is unknown,
  /// or the sequence has not started.
  final List<HigherMeasurement> higherMeasurements;

  /// The baseline segment extent (R10), or null when the cycle has no
  /// marked candidate (no segment is drawn).
  final BaselineSpan? baselineSpan;

  /// The evening date on which the sicher unfruchtbare Zeit begins, or null
  /// when rules D and E have not triggered (fewer than three/four CIRCLED
  /// candidates, a sequence without circles, or a connectedness break).
  final DateTime? suzBeginsEvening;

  /// Which rule determined [suzBeginsEvening]: D (3rd circled candidate
  /// ≥ 0.2 K) or E (4th circled candidate at any margin). Null while the
  /// SUZ is not determined.
  final SuzRule? suzRule;

  /// True when the automatic evaluation stopped mid-sequence (R2: more
  /// than one intervening missing/at-or-below day between two candidates —
  /// across the whole sequence, including the arrow→circle transition).
  /// No automatic re-search happens — the user re-marks the rise. False
  /// when the sequence simply ran out of data, completed at the SUZ
  /// trigger, or never started.
  final bool evaluationStopped;
}

/// SUZ rule D margin: the 3rd circled candidate must lie at least this far
/// above the baseline. (Rule E needs no margin — any amount above the
/// baseline suffices for the 4th circle.)
const double _suzRuleDAboveBaselineK = 0.2;

/// Per-kind cap (R4): up to four arrows carry ordinals, then up to four
/// circles; candidates beyond their kind's cap stay in the sequence
/// unnumbered.
const int _marksPerKindCap = 4;

/// Comparison tolerance for the rule-D boundary: temperatures are recorded
/// with two fraction digits, but `baseline + 0.2` is
/// binary-floating-point-imprecise (36.4 + 0.2 evaluates above the nearest
/// double to 36.6), which would wrongly reject an exact +0.2 measurement
/// without the tolerance.
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

  // Pre-pass: the six-low window per cycle. The R10 segment-end clamps need
  // the NEXT cycle's window start, so the windows are computed before the
  // per-cycle evaluations.
  final windows = <_LowWindow>[];
  for (var i = 0; i < cycles.length; i++) {
    windows.add(_lowWindowFor(cycles[i], profileMarks, _nextStart(cycles, i)));
  }

  final evaluations = <CycleEvaluation>[];
  for (var i = 0; i < cycles.length; i++) {
    final nextWindowStart =
        i + 1 < cycles.length ? windows[i + 1].startDay : null;
    evaluations.add(_evaluateCycle(
      cycles[i],
      profileMarks,
      windows[i],
      _nextStart(cycles, i),
      nextWindowStart,
    ));
  }
  return evaluations;
}

/// The start of the NEXT cycle's date window, or null for the last cycle.
DateTime? _nextStart(List<Cycle> cycles, int index) =>
    index + 1 < cycles.length
        ? DateOnly.normalize(cycles[index + 1].startDate)
        : null;

/// The most recent mark of [type] inside this cycle's date window, if any
/// (owner-confirmed anchor rule: re-marking supersedes). Multiple mucus
/// peaks arise from delayed ovulation — "Höhepunkt = letzter Tag mit der
/// besten Qualität", so the LAST marked peak anchors the evaluation — and
/// the first higher measurement is re-markable too (after a broken
/// Hochlage or a delayed second peak). Earlier duplicate marks stay
/// STORED (the domain does not filter them; their removal is the mark
/// sheet's toggle concern) — they simply stop anchoring and render no
/// candidate (an earlier rise mark lies before the walk region, R3).
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

  /// The earliest numbered low day (low #6 when six lows exist, the oldest
  /// available low otherwise) — the R10 baseline-segment START. Null when
  /// no usable low measurement exists. Computed as the earliest DATE (not
  /// "the lowest number") so a future numbering-direction flip does not
  /// silently move the segment's left edge.
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
  DateTime? nextCycleStart,
) {
  final firstHigherDay = _latestMarkOf(
    cycle,
    marks,
    CycleMarkTypes.firstHigherMeasurement,
    nextCycleStart,
  );
  if (firstHigherDay == null) return _LowWindow.empty;

  // Usable measurements: temperature recorded and no exclusion flag (see
  // the file-header assumptions for the exclusion rule).
  // cycle.days is sorted ascending by groupIntoCycles.
  final usable = cycle.days
      .where((e) => e.bbtC != null && !e.isExcluded)
      .toList(growable: false);

  // Six low measurements before the first higher, counting BACK (number 1
  // = the low immediately before the first higher).
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

  BaselinePoint? baseline;
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

  return _LowWindow(
    firstHigherDay: firstHigherDay,
    numberedLows: List.unmodifiable(lows),
    baseline: baseline,
  );
}

CycleEvaluation _evaluateCycle(
  Cycle cycle,
  List<CycleMark> marks,
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

  // The marked candidate sequence (R1–R5): walk CALENDAR days from the
  // marked rise onward so that untracked days (data gaps) count as the
  // missing days they are. Unmeasured and excluded days are gaps too (R8,
  // see the file-header TODO); a day at or below the baseline is a gap as
  // well. One gap day between two candidates is tolerated; two in a row
  // stop the automatic evaluation (no re-search, no automatic restart).
  // The gap counting spans the WHOLE sequence, including the arrow→circle
  // transition — the kind changes per candidate, the connectedness does not.
  final higherMeasurements = <HigherMeasurement>[];
  var evaluationStopped = false;
  DateTime? suzBeginsEvening;
  SuzRule? suzRule;
  BaselineSpan? baselineSpan;

  if (baseline != null && firstHigherDay != null) {
    final byDay = {
      for (final e in cycle.days) DateOnly.normalize(e.date): e,
    };
    final lastDay = DateOnly.normalize(cycle.endDate);

    var sequenceStarted = false;
    var gapRun = 0;
    var arrowCount = 0;
    var circleCount = 0;

    for (var day = firstHigherDay;
        !day.isAfter(lastDay);
        day = DateOnly.addDays(day, 1)) {
      final entry = byDay[day];

      if (entry == null ||
          entry.bbtC == null ||
          entry.isExcluded ||
          entry.bbtC! <= baseline.value) {
        // Missing, excluded, or at/below the baseline: a gap day (R2/R8).
        // Gap days before the first candidate do not count — the sequence
        // has nothing to be connected to yet.
        if (sequenceStarted) gapRun++;
        continue;
      }

      if (sequenceStarted && gapRun > 1) {
        // R2: more than one intervening gap day — the automatic evaluation
        // stops here. This candidate is NOT marked; nothing after it is
        // searched automatically (the user re-marks the rise).
        evaluationStopped = true;
        break;
      }

      sequenceStarted = true;
      gapRun = 0;

      final value = entry.bbtC!;
      // R4, per candidate: an ARROW when the peak is unset or the day is
      // at or before the peak day (the peak day's own candidate included);
      // a CIRCLE strictly after the peak day.
      final markKind =
          peakDay == null || DateOnly.daysBetween(peakDay, day) >= 0
              ? MarkKind.arrow
              : MarkKind.circle;

      // Per-kind four-cap (R4): the ordinal counts within the candidate's
      // OWN kind; beyond the cap the candidate stays in the sequence
      // unnumbered (ordinal null).
      final int? ordinal;
      switch (markKind) {
        case MarkKind.arrow:
          ordinal = arrowCount < _marksPerKindCap ? ++arrowCount : null;
        case MarkKind.circle:
          ordinal = circleCount < _marksPerKindCap ? ++circleCount : null;
      }

      higherMeasurements.add(HigherMeasurement(
        date: day,
        value: value,
        markKind: markKind,
        ordinal: ordinal,
        differenceK: value - baseline.value,
      ));

      // R5: rules D and E count CIRCLED measurements only — the circle
      // ordinal drives the trigger; arrows never start the SUZ (see the
      // file-header TODO(user-review) citing the "umrandete" wording).
      if (markKind == MarkKind.circle && ordinal != null) {
        if (ordinal == 3) {
          if (value >= baseline.value + _suzRuleDAboveBaselineK - _epsilon) {
            // Rule D: the 3rd circled candidate is at least 0.2 K above
            // the baseline — SUZ begins this evening ("gegen Abendessen").
            suzBeginsEvening = day;
            suzRule = SuzRule.d;
            break;
          }
          // Below the margin: rule E may still fire at the 4th circle.
        } else if (ordinal == 4) {
          // Rule E: the 3rd circle was below the margin (rule D would have
          // fired and ended the sequence otherwise), so the 4th circle —
          // ANY margin — starts the SUZ.
          suzBeginsEvening = day;
          suzRule = SuzRule.e;
          break;
        }
      }
    }

    // R10: the baseline segment. Start at the earliest numbered low day;
    // end at the last marked candidate (the SUZ trigger day when a rule
    // fired there), clamped defensively by the next menstruation start and
    // the next cycle's six-low window start. No marked candidate → no
    // segment.
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
    suzBeginsEvening: suzBeginsEvening,
    suzRule: suzRule,
    evaluationStopped: evaluationStopped,
  );
}
