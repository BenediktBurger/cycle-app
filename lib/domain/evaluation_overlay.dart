// The shared evaluation-overlay derivation (Mode M, ADR-0001): the pure
// per-day artifacts the cycle chart AND the PDF export draw from — the
// candidate circles/arrows and the 1–6 numbering and the baseline segment
// from evaluateCycles (lib/domain/evaluation.dart), the solid peak dots and
// the SUZ bars straight from the MARKS STREAM, and the ignored-day indexes
// of the temperature-ignore marks. Nothing is persisted: a render-time
// mapping of already-computed artifacts onto a day-index space, with no
// interpretation of its own.
//
// The USER places the mucus peak, the first higher measurement and the SUZ
// start (sicher unfruchtbare Zeit, from a morning or from an evening).
// Derived at render time: the rings around the circled higher measurements
// (candidates strictly AFTER the mucus peak day), the arrow-up glyph for
// the arrow-marked candidates (candidate day at or before the peak day, or
// the peak unset — R4, decided PER CANDIDATE by the domain), the 1–6
// numbering under the six low days, the baseline SEGMENT (R10: from the
// left edge of low #6's day column to half a day past the last marked
// candidate's column, from the domain's baselineSpan; a cycle with no
// marked candidate draws no segment) and the solid peak dot ABOVE the
// mucus entry in the mucus row (R6 — the peak no longer touches the
// temperature curve; EVERY placed peak renders, driven from the marks
// stream so peaks render even when no evaluation exists). The SUZ renders
// ONLY user-placed marks (a vertical bar hanging down from the temperature
// chart's top border plus a right-pointing arrow just below it); the
// computed suzBegins drives the sheet's suggestion instead — clean
// compute-only/manual separation.
//
// Rendering assumptions (see docs/adr/0001-iner-mode-m-hypothesis.md for
// the Mode-M context; the posture is Accepted — the per-item flags below
// are separate, still-open rendering-detail questions):
//
//   TODO(user-review): A peak day without a recorded entry renders NO dot
//   in the mucus row (the rows show recorded observations only). The
//   old chart-anchored question is gone with the curve ring: the peak
//   dot lives in the mucus row, where a day without an entry has no
//   cell content to hang it on.
//   TODO(user-review): Days after the SUZ trigger or after a
//   connectedness break render as ordinary temperature dots (the domain
//   lists exactly the marked candidates; there is no automatic
//   continuation — the user re-marks the rise, R2). Candidates beyond
//   their kind's four-cap STAY in the sequence (R4) and render as the
//   ordinary circle/arrow mark, just without a number — the curve never
//   paints candidate ordinals; the day panel's circle-numbering line is
//   the only ordinal surface (circles-only, see cycle_mark_sheet.dart).
//   TODO(user-review): The SUZ glyph's top anchoring — the bar hangs down
//   from the temperature chart's top border by a fixed °C drop and the
//   arrow anchors just below that border — is an owner-eyeball placement,
//   not a settled rule (the constants live beside the chart's SUZ bar
//   code in cycle.dart; the old baseline anchor is retired). A
//   temperature dot near the scale top can visually meet the top arrow —
//   accepted, no avoidance logic.
//   (The glyph's SIZE is chosen: shaft 8 px, head 7 x 11 px — see the
//   paintSuzArrowGlyph painter in lib/ui/cycle_marks.dart; the original
//   5 px shaft / 4 px head / Size(9, 8) footprint rendered too small next
//   to the day columns.)
//
// Day-index space: day index i is the CALENDAR day firstDay + i — the same
// space [buildEvaluationOverlay] and [ignoredDayIndexes] emit indexes into
// (and the cycle chart's _ChartDays derives globally). A gapless tracked
// range makes the calendar-day index identical to the position in the
// tracked-day list, which is the PDF layout's window space.

import 'cycle_grouping.dart';
import 'date_only.dart';
import 'evaluation.dart';
import 'marks.dart';

/// One drawn baseline segment, mapped onto the day-index space of the
/// overlay that carries it (R10). The drawing layer puts it from the LEFT
/// EDGE of [startIndex]'s day column to HALF A DAY past [endIndex]'s
/// column, clamped to the recorded range; the extent itself comes straight
/// from the domain's [BaselineSpan] (no-candidate cycles carry no segment).
final class BaselineSegment {
  const BaselineSegment({
    required this.startIndex,
    required this.endIndex,
    required this.value,
  });

  /// Day index of the segment's start day (low #6 when six lows exist; the
  /// domain's fallback applies otherwise — see its file-header TODO).
  final int startIndex;

  /// Day index of the segment's end day (the last marked candidate of the
  /// cycle's sequence).
  final int endIndex;

  /// The baseline y-value the segment runs through.
  final double value;
}

/// One user-placed SUZ mark, mapped onto the day-index space of the
/// overlay that carries it. The drawing layers place a VERTICAL bar
/// hanging down from the temperature chart's top border (x = column START
/// `dayIndex − 0.5` for `suzMorning`, column MIDDLE `dayIndex` for
/// `suzEvening`) plus a right-pointing arrow whose base starts at the bar,
/// just below that border. Only the x anchoring and the morning/evening
/// VARIANT live here — the vertical placement stays the chart's
/// top-anchored constants (see the SUZ bar code in cycle.dart).
final class SuzOverlayMark {
  const SuzOverlayMark({required this.dayIndex, required this.morning});

  /// The marked day's index (the bar's x anchor derives from it: see
  /// [morning]).
  final int dayIndex;

  /// True for `suzMorning` (bar at the column START, x − 0.5), false for
  /// `suzEvening` (bar at the column MIDDLE, x).
  final bool morning;

  /// The bar/arrow x anchor in the day-index space: the column
  /// START (dayIndex − 0.5) for suzMorning, the column MIDDLE (dayIndex)
  /// for suzEvening. The draw layers clamp it to the recorded range.
  double get barX => morning ? dayIndex - 0.5 : dayIndex.toDouble();
}

/// The per-day evaluation artifacts, mapped onto a day-index space
/// ([buildEvaluationOverlay]'s `firstDay`/`dayCount`). Anything the
/// arithmetic could not derive for a day is simply absent from these
/// collections — partial evaluations render partially.
final class EvaluationOverlay {
  const EvaluationOverlay({
    this.peakIndexes = const {},
    this.circledIndexes = const {},
    this.arrowIndexes = const {},
    this.numbersByIndex = const {},
    this.baselineSegments = const [],
    this.suzMarks = const [],
  });

  /// Day indexes carrying a mucus-peak mark. R6: the peak renders as a
  /// solid dot ABOVE the mucus glyph in the symbol row — the curve never
  /// rings the peak day (the curve's rings wrap only circled candidates).
  /// Driven from the MARKS STREAM (every placed peak), not from the
  /// evaluation's single anchored peak, so multiple peaks (delayed
  /// ovulation) all render — even when no evaluation exists (no rise
  /// marked).
  final Set<int> peakIndexes;
  final Set<int> circledIndexes;
  final Set<int> arrowIndexes;
  final Map<int, int> numbersByIndex;

  /// The baseline segments (R10), one per evaluated cycle with a marked
  /// candidate; a cycle without candidates has none.
  final List<BaselineSegment> baselineSegments;

  /// The user-placed SUZ marks (suzMorning/suzEvening), one overlay entry
  /// per mark inside an evaluated cycle. ONLY user-placed SUZ marks are
  /// listed — the computed suzBegins drives the sheet's suggestion
  /// and never renders here.
  final List<SuzOverlayMark> suzMarks;
}

/// Flattens [evaluations] (one per cycle group) plus the raw [marks] stream
/// into per-day-index artifacts for the day-index space
/// `[firstDay, firstDay + dayCount)`. Dates outside the recorded range are
/// skipped defensively.
EvaluationOverlay buildEvaluationOverlay({
  required List<CycleEvaluation> evaluations,
  required List<CycleMark> marks,
  required DateTime firstDay,
  required int dayCount,
}) {
  int? indexFor(DateTime date) {
    final i = DateOnly.daysBetween(date, firstDay);
    return i >= 0 && i < dayCount ? i : null;
  }

  final peaks = <int>{};
  final circled = <int>{};
  final arrows = <int>{};
  final numbers = <int, int>{};
  final segments = <BaselineSegment>[];
  final suz = <SuzOverlayMark>[];

  // The peak dots come straight from the marks stream: EVERY placed
  // mucus-peak mark renders as a solid dot (multiple peaks arise from
  // delayed ovulation), independent of any evaluation.
  for (final mark in marks) {
    if (mark.type != CycleMarkTypes.mucusPeakDay) continue;
    final i = indexFor(mark.date);
    if (i != null) peaks.add(i);
  }

  for (var e = 0; e < evaluations.length; e++) {
    final evaluation = evaluations[e];
    // The SUZ marks belong to the cycle whose attribution window contains
    // them (isDayInCycleWindow — the shared window helper above). Their
    // vertical placement is the chart's top anchoring, so the evaluation
    // only decides WHICH marks render — their y no longer derives from
    // the cycle's baseline.
    for (final mark in marks) {
      final isSuz =
          mark.type == CycleMarkTypes.suzEvening ||
          mark.type == CycleMarkTypes.suzMorning;
      if (!isSuz) continue;
      if (!isDayInCycleWindow(evaluations, e, mark.date)) continue;
      final day = DateOnly.normalize(mark.date);
      final i = indexFor(day);
      if (i == null) continue;
      suz.add(
        SuzOverlayMark(
          dayIndex: i,
          morning: mark.type == CycleMarkTypes.suzMorning,
        ),
      );
    }

    for (final low in evaluation.numberedLows) {
      final i = indexFor(low.date);
      if (i != null) numbers[i] = low.number;
    }
    for (final higher in evaluation.higherMeasurements) {
      final i = indexFor(higher.date);
      if (i == null) continue;
      // The mark kind is decided PER CANDIDATE by the domain (R4: arrow
      // at or before the peak day or with the peak unset, circle strictly
      // after it) — the draw layers carry no decision logic of their own
      // and map the kind onto the matching glyph. Beyond-cap candidates
      // carry a null ordinal but stay in the sequence: they render as the
      // same mark, just unnumbered (the curve paints no candidate
      // ordinals).
      switch (higher.markKind) {
        case MarkKind.circle:
          circled.add(i);
        case MarkKind.arrow:
          arrows.add(i);
      }
    }
    // R10: the baseline SEGMENT extent comes straight from the domain
    // (start = low #6, end = the last marked candidate, defensively
    // clamped there; null when the cycle has no marked candidate) — the
    // overlay only maps the span's days onto the day-index space.
    final span = evaluation.baselineSpan;
    final baseline = evaluation.baseline;
    if (span != null && baseline != null) {
      final start = indexFor(span.startDay);
      final end = indexFor(span.endDay);
      if (start != null && end != null) {
        segments.add(
          BaselineSegment(
            startIndex: start,
            endIndex: end,
            value: baseline.value,
          ),
        );
      }
    }
  }

  return EvaluationOverlay(
    peakIndexes: peaks,
    circledIndexes: circled,
    arrowIndexes: arrows,
    numbersByIndex: numbers,
    baselineSegments: segments,
    suzMarks: suz,
  );
}

/// Whether [day] falls inside the attribution window of the cycle at
/// [index] in [evaluations]: the window is `[cycle.startDate, next cycle's
/// startDate)` — half-open, so the next menstruation start itself belongs
/// to the NEXT cycle — and the LAST cycle's window is open-ended. The
/// bounds and [day] are compared as normalized UTC-midnight values
/// (DateOnly convention).
///
/// This mirrors the attribution the domain's evaluateCycles applies to its
/// own mark lookups (the `_latestMarkOf` filtering in
/// lib/domain/evaluation.dart); the draw layers reuse this helper so the
/// chart overlay, the day options panel and the PDF subset cannot drift
/// from the domain's window semantics.
bool isDayInCycleWindow(
  List<CycleEvaluation> evaluations,
  int index,
  DateTime day,
) {
  final windowStart = DateOnly.normalize(evaluations[index].cycle.startDate);
  final windowEnd = index + 1 < evaluations.length
      ? DateOnly.normalize(evaluations[index + 1].cycle.startDate)
      : null;
  final d = DateOnly.normalize(day);
  if (d.isBefore(windowStart)) return false;
  if (windowEnd != null && !d.isBefore(windowEnd)) return false;
  return true;
}

/// The day indexes of [cycle] whose day carries a temperature-ignore mark:
/// for every `ignoreTemperature` mark whose normalized date equals a
/// TRACKED day of [cycle], the index the drawing layers use for that day —
/// the cycle-local analogue of the cycle chart's ignored-day derivation
/// (see _ChartDays in lib/ui/cycle.dart, owner decision 2026-09-19: the
/// MARK is the curve's rendering key; the raw disturbance mask is
/// read-only display input elsewhere). Index i is the calendar day
/// `cycle.startDate + i` (see the file-header note on the index space).
/// A mark on an untracked gap day maps to no tracked day — excluded here,
/// where the chart's version lists it harmlessly because it can never
/// reach a curve point.
Set<int> ignoredDayIndexes({
  required Cycle cycle,
  required List<CycleMark> marks,
}) {
  final start = DateOnly.normalize(cycle.startDate);
  final tracked = {for (final day in cycle.days) DateOnly.normalize(day.date)};
  return {
    for (final mark in marks)
      if (mark.type == CycleMarkTypes.ignoreTemperature &&
          tracked.contains(DateOnly.normalize(mark.date)))
        DateOnly.daysBetween(DateOnly.normalize(mark.date), start),
  };
}
