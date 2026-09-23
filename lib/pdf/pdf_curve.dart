// The PDF curve block's draw-list composition: ONE page's curve + overlay
// drawing, built from the model's cycle evaluation + per-cycle overlay +
// the page window — and DELEGATING the curve structure itself to the
// chart's pure helpers (lib/ui/cycle_curve.dart: curveRuns,
// curveSegments, visibleCurveSegments, isBbtCInRange are imported, never
// reimplemented, so the PDF draws exactly the chart's curve rule set).
//
// Pure display mapping (Mode M, ADR-0001): every overlay artifact comes
// out of the model's per-cycle overlay (built by the shared derivation,
// lib/domain/evaluation_overlay.dart) — this file maps those artifacts
// into draw items, it derives NO rule result of its own.
//
// INDEX SPACES (kept apart, never conflated):
//
// - The model overlay's day indexes are CALENDAR OFFSETS from the cycle's
//   start day (lib/domain/pdf_export_model.dart's header note). The
//   overlay's own dayCount already covers the cycle's full calendar span,
//   so a mark on the last tracked day of a cycle with untracked gap days
//   still reaches this mapping.
// - Page windows slice day-list positions (the layout planner's windows
//   run over Cycle.days — the tracked days plus the grouping's data-less
//   span extension; untracked gap days BETWEEN tracked days stay out of
//   the list).
//
// This helper maps an overlay index through the day list's calendar
// offsets: an index only renders when its calendar offset names a day of
// the list — a mark on an untracked gap day (still not listed) drops out
// instead of sliding onto a neighboring column. While a cycle is tracked
// daily (the common case) both spaces coincide and the mapping is the
// identity.
//
// OUTPUT COORDINATES (column space, window-relative): window day i's
// column spans [i, i+1] — measured dots, the computed-SUZ line and row
// cells center at i + 0.5; a user morning SUZ bar rides the column's left
// edge (x = i), an evening bar the column middle (x = i + 0.5); the R10
// baseline runs from a low column's left edge to half a column past its
// end day. Line pieces carry fractional x at range-boundary crossings;
// cross-window pieces clip at the window edges. The arrow glyph's vertical
// placement is solved at DRAW-LIST time in pt (PdfArrowMark.tipDropPt —
// the dot radius plus the clearance gap, see the constants), so its
// "clear of the dot" semantics are pin-able without the pdf package.
import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/pdf_export_model.dart';
import '../domain/temperature_range.dart';
import '../ui/cycle_curve.dart';

/// One curve dot: a measured, in-window temperature under its window
/// column. The y position derives from the raw value with the axis's
/// clamped yFor — out-of-window dots never reach this list.
final class PdfCurveDot {
  const PdfCurveDot(this.index, this.value, this.ignored);

  /// The window-relative column index (column span [index, index+1]).
  final int index;

  /// The RAW measured temperature (°C) — never rewritten for display.
  final double value;

  /// The day carries the ignoreTemperature mark (renders lighter).
  final bool ignored;
}

/// One drawable straight line piece between adjacent measured days (a
/// range-clipped span of a [CurveSegment]; see visibleCurveSegments).
final class PdfCurvePiece {
  const PdfCurvePiece(
    this.startX,
    this.startValue,
    this.endX,
    this.endValue,
    this.ignored,
  );

  /// Column-space x of the span's ends (fractional at boundary crossings).
  final double startX;
  final double startValue;
  final double endX;
  final double endValue;

  /// The parent segment touches an ignoreTemperature-marked day (dimmed).
  final bool ignored;
}

/// One drawable R10 baseline piece: the dashed line through the baseline's
/// y-value, clipped to the page window (the segment may open on an
/// earlier page and/or continue on the next).
final class PdfBaselinePiece {
  const PdfBaselinePiece(this.startX, this.endX, this.value);

  /// Column-space x of the drawn piece (start = a column's left edge,
  /// end = half a column past the segment's end day, both clamped here).
  final double startX;
  final double endX;

  /// The baseline y-value (°C).
  final double value;
}

/// One user-placed SUZ bar (sicher unfruchtbare Zeit): its x anchor
/// (column start for a morning, column middle for an evening mark) and
/// the variant. The painter draws the bar hanging from the plot's top
/// edge plus its right-pointing arrow — the chart's SUZ glyph pair.
final class PdfSuzBar {
  const PdfSuzBar(this.x, this.morning);

  final double x;
  final bool morning;
}

/// One candidate mark carried to the painter: a circled higher
/// measurement (drawn as a ring around its dot — the ring's center is by
/// construction the DOT's drawn position: same column-center x, same
/// clamped yFor(value) point) or an arrowed one. The dot is identified by
/// column index + RAW value. CHART PARITY (decided): a candidate whose
/// day carries no measured in-range temperature produces NO mark at all —
/// like the chart, whose dot painter never runs for out-of-range spots
/// (nothing clamps onto the plot edge positionlessly).
final class PdfCandidateMark {
  const PdfCandidateMark(this.index, this.value);

  final int index;
  final double value;
}

/// One ARROWED candidate's draw item: [PdfCandidateMark] identity plus the
/// arrow glyph's vertical placement SOLVED at draw-list time (pure Dart,
/// testable) so the painter just paints at the stated coordinates.
final class PdfArrowMark extends PdfCandidateMark {
  const PdfArrowMark(super.index, super.value, this.tipDropPt);

  /// The distance (pt) from the dot's CENTER y (= the clamped
  /// `yFor(value)` point) DOWN to the arrow glyph's tip: the dot's radius
  /// (its bottom edge) PLUS [pdfArrowClearanceBelowDotPt] — the glyph sits
  /// clearly below the dot without touching it.
  final double tipDropPt;
}

/// The PDF curve dot's painted radius (pt) — one constant shared by the
/// dot painter, the ring geometry and the arrow placement above.
const double pdfCurveDotRadiusPt = 1.5;

/// The clearance (pt) between a candidate dot's bottom edge and its
/// arrow-up glyph's tip: the paper writes the arrow under the dot, and it
/// must not touch the dot it marks (owner refinement — the glyph used to
/// hang flush at the edge).
const double pdfArrowClearanceBelowDotPt = 2.5;

/// One computed-SUZ artifact: a thin vertical line at the `suzBegins`
/// day's column middle plus the rule letter (D/E) — visually distinct
/// from the user-placed SUZ bars by shape and stroke.
final class PdfSuzLine {
  const PdfSuzLine(this.x, this.ruleLetter);

  /// Column-space x (the `suzBegins` column's middle). Clamped to the
  /// window's RIGHT edge when the day sits beyond this page (the line
  /// continues on the next one); absent when its column lies BEHIND the
  /// window — the line rides one specific column, so it never shifts onto
  /// a neighboring one.
  final double x;

  /// The rule letter ("D" / "E"), or null when the caller carried no
  /// rule. Pinned: a SUZ without a rule letter is still drawn — null
  /// renders as the letter "S" (the painter's fallback here, not a
  /// behavior to change).
  final String? ruleLetter;
}

/// The complete draw list of one page's curve block. Window-relative
/// column coordinates; the painter maps them onto pt with the pdf_axis
/// geometry.
final class PdfCurveDrawing {
  const PdfCurveDrawing({
    required this.dots,
    required this.pieces,
    required this.baseline,
    required this.suzBars,
    required this.rings,
    required this.arrows,
    required this.lowNumbers,
    required this.peakIndexes,
    required this.suzLine,
  });

  /// The measured, in-window temperature dots (sorted by column index).
  final List<PdfCurveDot> dots;

  /// The drawable line pieces (range-clipped spans).
  final List<PdfCurvePiece> pieces;

  /// The R10 baseline pieces, window-clipped.
  final List<PdfBaselinePiece> baseline;

  /// The user-placed SUZ bars.
  final List<PdfSuzBar> suzBars;

  /// The circled higher measurements (rings around their dots).
  final List<PdfCandidateMark> rings;

  /// The arrow-marked candidates (arrow-up glyphs below their dots).
  final List<PdfArrowMark> arrows;

  /// The 1–6 low numbers by window column index.
  final Map<int, int> lowNumbers;

  /// The placed mucus-peak marks' window column indexes (the solid peak
  /// dots above the mucus glyph).
  final Set<int> peakIndexes;

  /// The computed-SUZ line, or null when the cycle has none (or the day
  /// falls behind this window).
  final PdfSuzLine? suzLine;
}

/// Builds one page window's curve/overlay draw list.
///
/// [cycle] and [overlay] must reference the SAME cycle (as the export
/// model guarantees: `overlays[i]` draws over `cycles[i]`). The window is
/// the tracked-day slice `[windowFirstIndex, windowFirstIndex +
/// windowDayCount)` of the cycle. [computedSuz] carries the evaluation's
/// already-computed `suzBegins`/`suzRule` — the PDF draws them, it does
/// not re-derive the rules.
PdfCurveDrawing pdfCurveDrawing({
  required CycleEvaluation cycle,
  required PdfCycleOverlay overlay,
  required TemperatureRange range,
  required int windowFirstIndex,
  required int windowDayCount,
  required ({DateTime? suzBegins, SuzRule? suzRule}) computedSuz,
}) {
  final days = cycle.cycle.days;
  final cycleStart = DateOnly.normalize(cycle.cycle.startDate);
  final windowEnd = windowFirstIndex + windowDayCount;

  // calendar offset from the cycle's start day -> tracked position
  final trackedPositions = <int, int>{
    for (var i = 0; i < days.length; i++)
      DateOnly.daysBetween(days[i].date, cycleStart): i,
  };
  // calendar offset -> the tracked day's RAW measured temperature
  final trackedValues = <int, double>{
    for (final MapEntry(key: offset, value: position)
        in trackedPositions.entries)
      if (days[position].bbtC case final bbt?) offset: bbt,
  };

  /// An overlay day index (calendar-offset space) mapped onto its
  /// window-relative column index — null when the offset names no tracked
  /// day (untracked gap) or the day lies outside this window.
  int? windowPositionOf(int calendarIndex) {
    final pos = trackedPositions[calendarIndex];
    if (pos == null) return null;
    final windowPos = pos - windowFirstIndex;
    return windowPos >= 0 && windowPos < windowDayCount ? windowPos : null;
  }

  // --- the temperature curve: the chart's rule set over the window's
  // entries (ignored = window-local marked days for the lighter flag).
  final windowRuns = curveRuns(
    {
      for (var i = windowFirstIndex; i < windowEnd; i++)
        i - windowFirstIndex: days[i],
    },
    ignoredDayIndexes: {
      for (final index in overlay.ignoredIndexes)
        if (windowPositionOf(index) case final pos?) pos,
    },
  );

  final dots = [
    for (final run in windowRuns)
      for (final point in run.points)
        if (isBbtCInRange(point.bbtC, range))
          PdfCurveDot(point.dayIndex, point.bbtC, point.excluded),
  ];
  final pieces = [
    for (final span in visibleCurveSegments(curveSegments(windowRuns), range))
      PdfCurvePiece(
        span.startX,
        span.startY,
        span.endX,
        span.endY,
        span.lighter,
      ),
  ];

  // --- the R10 baseline, clipped to the window.
  final baseline = <PdfBaselinePiece>[];
  for (final segment in overlay.baselineSegments) {
    final startPos = trackedPositions[segment.startIndex];
    final endPos = trackedPositions[segment.endIndex];
    if (startPos == null || endPos == null) continue;
    final a = startPos.toDouble().clamp(
      windowFirstIndex.toDouble(),
      windowEnd.toDouble(),
    );
    // The piece ends half a column past the end day — the chart's
    // center-space `endDay + 0.5` padding, i.e. the end day's column
    // RIGHT edge here.
    final b = (endPos + 1.0).clamp(
      windowFirstIndex.toDouble(),
      windowEnd.toDouble(),
    );
    if (b <= a) continue;
    baseline.add(
      PdfBaselinePiece(
        a - windowFirstIndex,
        b - windowFirstIndex,
        segment.value,
      ),
    );
  }

  // --- the user-placed SUZ bars: their bar rides the marked day's own
  // column (start for morning, middle for evening), so only days of THIS
  // window render.
  final suzBars = [
    for (final mark in overlay.suzMarks)
      if (trackedPositions[mark.dayIndex] case final pos?
          when pos >= windowFirstIndex && pos < windowEnd)
        PdfSuzBar(
          (mark.morning ? pos.toDouble() : pos + 0.5) - windowFirstIndex,
          mark.morning,
        ),
  ];

  // --- the computed-SUZ artifact (carried from the evaluation, never
  // re-derived here).
  PdfSuzLine? suzLine;
  if (computedSuz.suzBegins case final begins?) {
    final offset = DateOnly.daysBetween(DateOnly.normalize(begins), cycleStart);
    if (trackedPositions[offset] case final pos? when pos >= windowFirstIndex) {
      final x = (pos + 0.5).clamp(
        windowFirstIndex.toDouble(),
        windowEnd.toDouble(),
      ); // right-edge clamp for page continuation
      final letter = switch (computedSuz.suzRule) {
        null => null,
        SuzRule.d => 'D',
        SuzRule.e => 'E',
      };
      suzLine = PdfSuzLine(x - windowFirstIndex, letter);
    }
  }

  // --- the remaining candidate/mark artifacts, mapped + window-filtered.
  // CHART PARITY: a candidate without a MEASURED IN-RANGE temperature draws
  // no dot — so it draws neither a ring nor an arrow (the chart skips the
  // whole painter for out-of-range spots; drawing a clamped edge ring over
  // a position with no dot would confound the reading).
  final rings = [
    for (final index in overlay.circledIndexes)
      if (windowPositionOf(index) case final pos?)
        if (trackedValues[index] case final value?
            when isBbtCInRange(value, range))
          PdfCandidateMark(pos, value),
  ];
  final arrows = [
    for (final index in overlay.arrowIndexes)
      if (windowPositionOf(index) case final pos?)
        if (trackedValues[index] case final value?
            when isBbtCInRange(value, range))
          PdfArrowMark(
            pos,
            value,
            pdfCurveDotRadiusPt + pdfArrowClearanceBelowDotPt,
          ),
  ];
  final lowNumbers = {
    for (final MapEntry(:key, :value) in overlay.numbersByIndex.entries)
      if (windowPositionOf(key) case final pos?) pos: value,
  };
  final peaks = {
    for (final index in overlay.peakIndexes)
      if (windowPositionOf(index) case final pos?) pos,
  };

  return PdfCurveDrawing(
    dots: dots,
    pieces: pieces,
    baseline: baseline,
    suzBars: suzBars,
    rings: rings,
    arrows: arrows,
    lowNumbers: lowNumbers,
    peakIndexes: peaks,
    suzLine: suzLine,
  );
}
