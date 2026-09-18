// Computed evaluation marks on the cycle chart (Mode M, ADR-0001).
//
// The USER places the mucus peak, the first higher measurement and the SUZ
// start (sicher unfruchtbare Zeit, from a morning or from an evening).
// Everything rendered from this file is DERIVED at render time — the
// candidate circles/arrows and the 1–6 numbering and the baseline segment
// from evaluateCycles (lib/domain/evaluation.dart); the solid peak dots and
// the SUZ bars straight from the MARKS STREAM. Nothing is persisted:
// the rings around the circled higher measurements (candidates strictly
// AFTER the mucus peak day), the arrow-up glyph for the arrow-marked
// candidates (candidate day at or before the peak day, or the peak unset —
// R4, decided PER CANDIDATE by the domain), the 1–6 numbering under the six
// low days, the baseline SEGMENT (R10: from the left edge of low #6's day
// column to half a day past the last marked candidate's column, from the
// domain's baselineSpan; a cycle with no marked candidate draws no segment)
// and the solid peak dot ABOVE the mucus entry in the mucus row (R6 — the
// peak no longer touches the temperature curve; EVERY placed peak renders,
// driven from the marks stream so peaks render even when no evaluation
// exists). The SUZ renders ONLY user-placed marks (a vertical bar spanning
// the plot height plus a right-pointing arrow from the bar); the computed
// suzBegins drives the sheet's suggestion instead — clean
// compute-only/manual separation. Rendered across fl_chart's dot painters +
// line bars, with the glyph shapes painted by hand where fl_chart has no
// facility (ADR-0004 anticipates this custom-paint fallback — used here
// only for small glyphs; the baseline segment fits inside fl_chart as a
// dashed two-spot bar, so the chart itself stays fl_chart).
//
// Rendering assumptions (validate with an expert reviewer, see
// docs/adr/0001-iner-mode-m-hypothesis.md, status: Hypothesis):
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
//   paints candidate ordinals; the sheet's circle-numbering line is the
//   only ordinal surface (circles-only, see cycle_mark_sheet.dart).
//   TODO(user-review): The SUZ arrow's vertical anchor — the cycle's
//   baseline value when one exists, else the plot middle — is an
//   owner-eyeball rendering detail, not a settled rule. (The glyph's SIZE
//   is chosen: shaft 8 px, head 7 x 11 px — see paintSuzArrowGlyph; the
//   original 5 px shaft / 4 px head / Size(9, 8) footprint rendered too
//   small next to the day columns.)

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/marks.dart';
import 'cycle_mark_window.dart';

/// One drawn baseline segment, mapped onto the chart's day-index space
/// (R10). The chart draws it from the LEFT EDGE of [startIndex]'s day
/// column to HALF A DAY past [endIndex]'s column, clamped to the recorded
/// range; the extent itself comes straight from the domain's
/// [BaselineSpan] (no-candidate cycles carry no segment).
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

/// One user-placed SUZ mark, mapped onto the chart's day-index space. The
/// chart draws a VERTICAL bar spanning the plot height (x = column START
/// `dayIndex − 0.5` for `suzMorning`, column MIDDLE `dayIndex` for
/// `suzEvening`) plus a right-pointing arrow whose base starts at the bar.
final class SuzOverlayMark {
  const SuzOverlayMark({
    required this.dayIndex,
    required this.morning,
    this.arrowValueY,
  });

  /// The marked day's chart index (the bar's x anchor derives from it: see
  /// [morning]).
  final int dayIndex;

  /// True for `suzMorning` (bar at the column START, x − 0.5), false for
  /// `suzEvening` (bar at the column MIDDLE, x).
  final bool morning;

  /// The bar/arrow x anchor in the chart's day-index space: the column
  /// START (dayIndex − 0.5) for suzMorning, the column MIDDLE (dayIndex)
  /// for suzEvening. The chart clamps it to the recorded range.
  double get barX => morning ? dayIndex - 0.5 : dayIndex.toDouble();

  /// The y value the arrow glyph anchors at: the cycle's baseline value
  /// when one exists, else null (the chart falls back to the plot middle).
  /// TODO(user-review): the arrow's vertical anchor is an owner-eyeball
  /// rendering detail.
  final double? arrowValueY;
}

/// The per-day evaluation artifacts, mapped onto the chart's day-index
/// space (day index 0 = the first recorded day, see _ChartDays in
/// cycle.dart). Anything the arithmetic could not derive for a day is
/// simply absent from these collections — partial evaluations render
/// partially.
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
/// into per-day-index artifacts for the chart overlay. Dates outside the
/// recorded range [firstDay, firstDay + dayCount) are skipped defensively.
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
    // them (isDayInCycleWindow — the shared UI-side helper).
    final arrowValueY = evaluation.baseline?.value;
    for (final mark in marks) {
      final isSuz = mark.type == CycleMarkTypes.suzEvening ||
          mark.type == CycleMarkTypes.suzMorning;
      if (!isSuz) continue;
      if (!isDayInCycleWindow(evaluations, e, mark.date)) continue;
      final day = DateOnly.normalize(mark.date);
      final i = indexFor(day);
      if (i == null) continue;
      suz.add(SuzOverlayMark(
        dayIndex: i,
        morning: mark.type == CycleMarkTypes.suzMorning,
        arrowValueY: arrowValueY,
      ));
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
      // after it) — the UI carries no decision logic of its own and maps
      // the kind onto the matching painter. Beyond-cap candidates carry a
      // null ordinal but stay in the sequence: they render as the same
      // mark, just unnumbered (the curve paints no candidate ordinals).
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
    // overlay only maps the span's days onto the chart's day-index space.
    final span = evaluation.baselineSpan;
    final baseline = evaluation.baseline;
    if (span != null && baseline != null) {
      final start = indexFor(span.startDay);
      final end = indexFor(span.endDay);
      if (start != null && end != null) {
        segments.add(BaselineSegment(
          startIndex: start,
          endIndex: end,
          value: baseline.value,
        ));
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

// --- dot painters -----------------------------------------------------------

/// Paints the temperature dot plus a RING around it, with a small gap so
/// the value stays readable: the CIRCLED higher measurements — every
/// candidate strictly after the mucus peak day (R4, decided per
/// candidate by the domain; the peak day itself never gets a ring, R6).
/// Candidates beyond the circle kind's four-cap stay circled too, just
/// unnumbered (the curve paints no ordinals).
final class RingDotPainter extends FlDotCirclePainter {
  RingDotPainter({
    required super.color,
    required this.ringColor,
    this.ringGap = 2.5,
    this.ringWidth = 1.5,
  });

  final Color ringColor;
  final double ringGap;
  final double ringWidth;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    super.draw(canvas, spot, offsetInCanvas);
    canvas.drawCircle(
      offsetInCanvas,
      radius + ringGap,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
    );
  }

  @override
  Size getSize(FlSpot spot) => Size.fromRadius(radius + ringGap + ringWidth);

  @override
  List<Object?> get props => [
        ...super.props,
        ringColor,
        ringGap,
        ringWidth,
      ];
}

/// Paints the temperature dot plus an ARROW-UP glyph BELOW it: a marked
/// candidate whose day is at or before the mucus peak day, or one of a
/// cycle with the peak unset (R4, decided per candidate by the domain) —
/// higher, but explicitly NOT circled per the rule that only candidates
/// after the peak get circled. Beyond the arrow kind's four-cap the
/// candidate stays arrowed too, just unnumbered.
///
/// The glyph paints below the dot on purpose: the paper sheet writes the
/// upward arrow UNDER the column's dot. This is a position change, not an
/// orientation change — the arrow keeps pointing UP at the dot it marks
/// (see [arrowUpTipFor], the pure placement seam). [getSize] reserves the
/// glyph's extent on both sides of the dot for hit-testing either way.
final class ArrowUpDotPainter extends FlDotCirclePainter {
  ArrowUpDotPainter({
    required super.color,
    required this.arrowColor,
    this.arrowHeight = 8.0,
  });

  final Color arrowColor;
  final double arrowHeight;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    super.draw(canvas, spot, offsetInCanvas);
    paintArrowUpGlyph(
      canvas,
      arrowUpTipFor(offsetInCanvas, radius: radius),
      color: arrowColor,
    );
  }

  @override
  Size getSize(FlSpot spot) => Size.fromRadius(radius + arrowHeight);

  @override
  List<Object?> get props => [...super.props, arrowColor];
}

/// The tip position of the arrow-up glyph for a temperature dot painted at
/// [dotCenter] with [radius]: the glyph hangs BELOW the dot, flush at its
/// bottom edge — the paper sheet writes the upward arrow under the column's
/// dot. The head keeps pointing UP at the dot it marks: a position-below
/// placement, not an orientation change. (The glyph's own extent
/// — the height [ArrowUpDotPainter.arrowHeight] reserves — hangs downward
/// from the tip and only feeds the painters' size math; the tip itself
/// always sits on the dot's edge, exactly the way the glyph used to hang
/// flush from the dot's TOP edge.)
Offset arrowUpTipFor(Offset dotCenter, {required double radius}) =>
    Offset(dotCenter.dx, dotCenter.dy + radius);

/// Paints an upward arrow (triangle head + short stem) with the 8px
/// total height used by [ArrowUpDotPainter]; [tip] is the apex. Shared
/// between the chart painter and the [ArrowUpGlyph] legend widget so
/// both show the exact same shape.
void paintArrowUpGlyph(Canvas canvas, Offset tip, {required Color color}) {
  final paint = Paint()..color = color;
  final head = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - 3, tip.dy + 4)
    ..lineTo(tip.dx + 3, tip.dy + 4)
    ..close();
  canvas.drawPath(head, paint);
  canvas.drawRect(Rect.fromLTWH(tip.dx - 0.75, tip.dy + 3, 1.5, 5), paint);
}

/// Chooses the dot painter for one chart day: plain dot, dot with a ring
/// (circled higher measurement) or dot with an arrow-up glyph (arrowed
/// candidate). The mucus peak never reaches the curve — it renders as a
/// solid dot in the symbol row (R6). [dayIndex] and [overlay] indexes
/// share one space.
FlDotPainter dotPainterForDay({
  required int dayIndex,
  required Color dotColor,
  required ColorScheme colorScheme,
  required EvaluationOverlay overlay,
}) {
  if (overlay.circledIndexes.contains(dayIndex)) {
    return RingDotPainter(color: dotColor, ringColor: colorScheme.primary);
  }
  if (overlay.arrowIndexes.contains(dayIndex)) {
    return ArrowUpDotPainter(color: dotColor, arrowColor: colorScheme.primary);
  }
  return FlDotCirclePainter(color: dotColor);
}

// --- SUZ mark glyph ----------------------------------------------------------

/// Paints a RIGHT-POINTING arrow whose base starts at [base]: an 8 px
/// horizontal shaft followed by a triangular head (7 px long, 11 px high),
/// used as the companion glyph of the SUZ vertical bar (the bar marks the
/// SUZ start's column, the arrow points toward the fertile-barren boundary
/// it opens). The size matches the paper sheet's clearly readable SUZ
/// arrow — enlarged from the original 5 px shaft / 4 px head, which
/// rendered too small next to the day columns.
/// TODO(user-review): the exact geometry (shaft length, head size) stays
/// an owner-eyeball rendering detail, not a settled rule.
void paintSuzArrowGlyph(Canvas canvas, Offset base, {required Color color}) {
  final paint = Paint()..color = color;
  canvas.drawRect(Rect.fromLTWH(base.dx, base.dy - 1, 8, 2), paint);
  final head = Path()
    ..moveTo(base.dx + 15, base.dy)
    ..lineTo(base.dx + 8, base.dy - 5.5)
    ..lineTo(base.dx + 8, base.dy + 5.5)
    ..close();
  canvas.drawPath(head, paint);
}

/// The SUZ arrow glyph as a fl_chart dot painter: fl_chart's painters paint
/// at spots, and the SUZ arrow's anchor is exactly one spot — the bar's x
/// (column start for suzMorning, column middle for suzEvening) at the
/// arrow's y value (the cycle's baseline value, or the plot middle — see
/// [SuzOverlayMark.arrowValueY]). Unlike the other dot painters this one
/// paints NO temperature dot underneath: the SUZ mark is its own artifact,
/// not a temperature rendering.
final class SuzArrowDotPainter extends FlDotPainter {
  const SuzArrowDotPainter({required this.color});

  final Color color;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    paintSuzArrowGlyph(canvas, offsetInCanvas, color: color);
  }

  @override
  Size getSize(FlSpot spot) => const Size(15, 11);

  @override
  Color get mainColor => color;

  @override
  List<Object?> get props => [color];

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;
}

// --- widget-level pieces ----------------------------------------------------

/// The day-cell separator of the chart card's rows: a hairline matching
/// the chart's vertical day grid lines (a subtle onSurface tint), thickened
/// to the SOLID cycle-start line on cycle boundaries (the separator sits at
/// x = nextCycleStart − 0.5 — i.e. on the RIGHT edge of the cell before the
/// new cycle's first day). Shared by every row of the card (day header,
/// signal rows, the 1–6 numbering row) so the vertical lines run through
/// the whole card.
BorderSide cycleDayCellBorderSide(BuildContext context,
    {required bool isCycleBoundary}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return isCycleBoundary
      ? BorderSide(width: 2, color: onSurface)
      : BorderSide(width: 0.5, color: onSurface.withValues(alpha: 0.12));
}

/// The 1–6 numbering under the chart: one narrow tappable cell per
/// calendar day, aligned by the same even day spacing as the chart and
/// the signal rows (mirrors the rows in cycle.dart). LIKE those rows, only
/// the scroll window's cells are built (windowStart..windowEnd, inclusive;
/// a leading spacer keeps them at their global column positions) — day cell
/// i is centered at (i + 0.5) * cellWidth, exactly where the chart draws
/// day i's dot. Days outside the six-low windows render an empty
/// fixed-height slot. The cells carry the card's day-cell separators
/// (hairline, thickened on cycle boundaries) so the vertical lines run
/// through the whole card; the numbering semantics themselves stay
/// untouched (the windowing only decides WHICH cells are built, never which
/// number a cell carries).
final class EvaluationMarksRow extends StatelessWidget {
  const EvaluationMarksRow({
    super.key,
    required this.dayCount,
    required this.cellWidth,
    required this.numbersByIndex,
    required this.onDayTap,
    required this.windowStart,
    required this.windowEnd,
    this.isCycleBoundary,
  });

  final int dayCount;

  /// The row's fixed cell height: the frozen left rail (cycle.dart) keeps
  /// an empty slot of this height so its segments stay vertically in step
  /// with the scroll content.
  static const double cellHeight = 14;

  final double cellWidth;
  final Map<int, int> numbersByIndex;
  final void Function(int index) onDayTap;

  /// The built window's inclusive day-index bounds ([windowStart..windowEnd] —
  /// the caller's scroll window; clamped to the recorded range here). The
  /// leading window spacer keeps the built cells at their global column
  /// positions (mirrors the header row's and the signal rows' spacers), so
  /// a window rebuild only adds/removes cells in place.
  final int windowStart;
  final int windowEnd;

  /// The shared cycle-boundary predicate (see _ChartDays.isCycleBoundary
  /// in cycle.dart): when given, cell i's right border thickens on the
  /// cell before a cycle start (day i + 1 opens a cycle).
  final bool Function(int index)? isCycleBoundary;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The window spacer keeps the cells at their global column
        // positions (mirrors the header row's and the signal rows'
        // spacers).
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        for (var i = math.max(windowStart, 0);
            i <= math.min(windowEnd, dayCount - 1);
            i++)
          SizedBox(
            width: cellWidth,
            child: InkWell(
              onTap: () => onDayTap(i),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: cycleDayCellBorderSide(context,
                        isCycleBoundary: isCycleBoundary?.call(i + 1) ?? false),
                  ),
                ),
                child: _NumberCell(
                  key: ValueKey('marksCell-$i'),
                  number: numbersByIndex[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({super.key, this.number});

  final int? number;

  @override
  Widget build(BuildContext context) {
    // The fixed slot height keeps all cells aligned with and without a
    // number (same trick as the signal rows' fixed cell heights).
    return SizedBox(
      height: EvaluationMarksRow.cellHeight,
      child: Center(
        child: number == null
            ? null
            : Text(
                '$number',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
      ),
    );
  }
}

/// The arrow-up glyph as a standalone widget for the legend, painted with
/// the exact shape the chart's [ArrowUpDotPainter] uses.
final class ArrowUpGlyph extends StatelessWidget {
  const ArrowUpGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 8),
      painter: _ArrowUpGlyphPainter(color: color),
    );
  }
}

class _ArrowUpGlyphPainter extends CustomPainter {
  const _ArrowUpGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintArrowUpGlyph(canvas, Offset(size.width / 2, 0), color: color);
  }

  @override
  bool shouldRepaint(covariant _ArrowUpGlyphPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// The SUZ glyph as a standalone widget for the legend: the same
/// right-pointing arrow the chart's [SuzArrowDotPainter] paints, plus the
/// vertical bar it hangs from (the bar spans the plot height on the chart;
/// here it is drawn to fit the legend's sample box).
final class SuzArrowGlyph extends StatelessWidget {
  const SuzArrowGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // The sample box carries the enlarged chart glyph (paintSuzArrowGlyph:
    // 15 px wide — 8 px shaft + 7 px head — and 11 px high) next to its
    // bar.
    return CustomPaint(
      size: const Size(18, 16),
      painter: _SuzArrowGlyphPainter(color: color),
    );
  }
}

class _SuzArrowGlyphPainter extends CustomPainter {
  const _SuzArrowGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // The vertical bar: full sample height, at the sample's left edge —
    // the chart's bar spans the plot height at the SUZ day's column.
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0, 2, size.height),
      paint,
    );
    // The arrow, base at the bar (same enlarged glyph shape as the chart's
    // painter — scaled together with it).
    paintSuzArrowGlyph(canvas, Offset(2.5, size.height / 2), color: color);
  }

  @override
  bool shouldRepaint(covariant _SuzArrowGlyphPainter oldDelegate) =>
      color != oldDelegate.color;
}
