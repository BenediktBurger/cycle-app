// Chart painters for the computed evaluation marks (Mode M, ADR-0001).
//
// The USER places the mucus peak, the first higher measurement and the SUZ
// start (sicher unfruchtbare Zeit, from a morning or from an evening).
// The DERIVATION of what the chart paints lives in
// lib/domain/evaluation_overlay.dart — shared with the PDF export so both
// draw layers can never drift — and arrives here as an [EvaluationOverlay];
// this file contains the GLYPHS: the dot painters (rings around the
// circled higher measurements — candidates strictly AFTER the mucus peak
// day, R4 — and the arrow-up glyph for the arrow-marked candidates), the
// dot-painter selection per day ([dotPainterForDay]) and the SUZ arrow
// glyphs. The derivation semantics below stay true of what these painters
// receive: the rings wrap circled candidates (R4, decided PER CANDIDATE by
// the domain), the 1–6 numbers of the six low days feed the in-plot
// bottom-anchored row via the shared per-day placement map
// (chart_marks.dart), the baseline
// SEGMENT (R10: from the left edge of low #6's day column to half a day
// past the last marked candidate's column, mapped by the overlay from the
// domain's baselineSpan; a cycle with no marked candidate draws no
// segment) and the solid peak dot in its own in-plot row above the
// mucus letters row (R6 — the peak never touches the temperature curve;
// the dot hangs on the peak mark, not on a recorded entry, so every
// placed peak renders straight from the marks stream, entry or not).
// The SUZ renders ONLY user-placed marks (a vertical
// bar hanging down from the temperature chart's top border plus a
// right-pointing arrow
// just below it); the computed
// suzBegins drives the sheet's suggestion instead — clean
// compute-only/manual separation. Rendered across fl_chart's dot painters +
// line bars, with the glyph shapes painted by hand where fl_chart has no
// facility (ADR-0004 anticipates this custom-paint fallback — used here
// only for small glyphs; the baseline segment fits inside fl_chart as a
// dashed two-spot bar, so the chart itself stays fl_chart).
//
// Rendering assumptions (see docs/adr/0001-iner-mode-m-hypothesis.md for
// the Mode-M context; the posture is Accepted — the per-item flags below
// are separate, still-open rendering-detail questions):
//
//   TODO(user-review): Days after the SUZ trigger or after a
//   connectedness break render as ordinary temperature dots (the domain
//   lists exactly the marked candidates; there is no automatic
//   continuation — the user re-marks the rise, R2). Candidates beyond
//   their kind's four-cap STAY in the sequence (R4) and render as the
//   ordinary circle/arrow mark, just without a number — the curve never
//   paints candidate ordinals; the day panel's circle-numbering line is
//   the only ordinal surface (circles-only, see cycle_mark_sheet.dart).
//   TODO(user-review): The SUZ glyph's top anchoring — the bar hangs down
//   from the temperature chart's top border by suzBarHangSpanDegrees of
//   the scale and the arrow anchors suzArrowTopInsetDegrees just below
//   that border — is an owner-eyeball placement, not a settled rule (the
//   constants live beside the SUZ glyph section below, shared with the
//   PDF export's mirroring renderer in lib/pdf/cycle_pdf.dart). A
//   temperature dot near the scale top can visually meet the top arrow —
//   accepted, no avoidance logic.
//   (The glyph's SIZE is chosen: shaft 8 px, head 7 x 11 px — see
//   paintSuzArrowGlyph; the
//   original 5 px shaft / 4 px head / Size(9, 8) footprint rendered too
//   small next to the day columns.)

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/evaluation_overlay.dart';

// The glyph's anchoring constants (suzBarHangSpanDegrees /
// suzArrowTopInsetDegrees) live in suz_glyph.dart — pure Dart, shared with
// the PDF export's mirroring renderer (lib/pdf/cycle_pdf.dart) — and are
// re-exported here for the chart surfaces (cycle.dart reads them through
// this import).
export 'suz_glyph.dart' show suzArrowTopInsetDegrees, suzBarHangSpanDegrees;

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
  List<Object?> get props => [...super.props, ringColor, ringGap, ringWidth];
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
/// sits on the dot's edge.)
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
/// solid dot in its own in-plot row (R6). [dayIndex] and [overlay]
/// indexes share one space.
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
/// chart's top-anchored arrow y (just below the temperature chart's top
/// border, inside the hung band — see the SUZ bar code in cycle.dart).
/// Unlike the other dot painters this one
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
/// new cycle's first day; on the recorded range's LEFT edge the mirror
/// holds: the boundary column — the chart's first day, day index 0 —
/// thickens its LEFT border, see _ChartDays.isCycleBoundary in cycle.dart).
/// Shared by every row of the card (day header, signal rows) so the
/// vertical lines run through the whole block.
BorderSide cycleDayCellBorderSide(
  BuildContext context, {
  required bool isCycleBoundary,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return isCycleBoundary
      ? BorderSide(width: 2, color: onSurface)
      : BorderSide(width: 0.5, color: onSurface.withValues(alpha: 0.12));
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
/// vertical bar it hangs from. Placement-INDEPENDENT by design: on the
/// chart the bar hangs down from the temperature chart's top border and
/// the arrow sits just below it, while the legend sample draws the bar
/// across its sample box at full height (the legend shows the glyph's
/// SHAPE, not the chart's vertical anchoring — the sample stays valid
/// through the shared arrow painter).
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
    // a shape sample of the chart's bar, which hangs down from the chart's
    // top border at the SUZ day's column.
    canvas.drawRect(Rect.fromLTWH(0.5, 0, 2, size.height), paint);
    // The arrow, base at the bar (same enlarged glyph shape as the chart's
    // painter — scaled together with it).
    paintSuzArrowGlyph(canvas, Offset(2.5, size.height / 2), color: color);
  }

  @override
  bool shouldRepaint(covariant _SuzArrowGlyphPainter oldDelegate) =>
      color != oldDelegate.color;
}
