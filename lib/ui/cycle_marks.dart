// Computed evaluation marks on the cycle chart (Mode M, ADR-0001).
//
// The USER places only the mucus peak and the first higher measurement;
// everything rendered from this file is DERIVED at render time from
// evaluateCycles (lib/domain/evaluation.dart) and is never persisted:
// the ring on the mucus-peak day and around the (up to) three circled
// higher measurements, the arrow-up glyph for higher measurements before
// the peak, the 1–6 numbering under the six low days and the baseline
// line. Rendered across fl_chart's dot painters + extra lines, with the
// glyph shapes painted by hand where fl_chart has no facility
// (ADR-0004 anticipates this custom-paint fallback — used here only for
// small glyphs, the chart itself stays fl_chart).
//
// Rendering assumptions (validate with an expert reviewer, see
// docs/adr/0001-iner-mode-m-hypothesis.md, status: Hypothesis):
//
//   TODO(user-review): A peak day without a measured temperature has no
//   dot on the chart and therefore renders NO circle. Anchoring a
//   floating glyph in an empty chart column (e.g. at the column top) is
//   not attempted — the chart's y position would be arbitrary.
//   TODO(user-review): When the peak is unmarked, a higher measurement's
//   position is unknowable (HigherMeasurement.position is null); it
//   renders arrow-up (treated like "before the peak"), nothing circled.
//   TODO(user-review): Higher measurements AFTER the peak beyond the
//   third circled one render as ordinary temperature dots (the cheat
//   sheet circles exactly three).
//   TODO(user-review): The baseline spans the FULL chart width. The
//   cheat sheet does not bound the line's span; fl_chart's HorizontalLine
//   has no x-range either, and a region-limited line would need the
//   ADR-0004 custom-painter fallback for the one piece.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';

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
    this.baselineValues = const [],
  });

  final Set<int> peakIndexes;
  final Set<int> circledIndexes;
  final Set<int> arrowIndexes;
  final Map<int, int> numbersByIndex;
  final List<double> baselineValues;
}

/// Flattens [evaluations] (one per cycle group) into per-day-index
/// artifacts for the chart overlay. Dates outside the recorded range
/// [firstDay, firstDay + dayCount) are skipped defensively.
EvaluationOverlay buildEvaluationOverlay({
  required List<CycleEvaluation> evaluations,
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
  final baselines = <double>[];

  for (final evaluation in evaluations) {
    if (evaluation.mucusPeakDay != null) {
      final i = indexFor(evaluation.mucusPeakDay!);
      if (i != null) peaks.add(i);
    }
    for (final low in evaluation.numberedLows) {
      final i = indexFor(low.date);
      if (i != null) numbers[i] = low.number;
    }
    for (final higher in evaluation.higherMeasurements) {
      final i = indexFor(higher.date);
      if (i == null) continue;
      // Circle (1st–3rd after the peak) and arrow (before the peak, or
      // position unknowable) are mutually exclusive by construction.
      if (higher.circleOrd != null) {
        circled.add(i);
      } else if (higher.position == HigherPosition.beforePeak ||
          higher.position == null) {
        arrows.add(i);
      }
    }
    final baseline = evaluation.baseline;
    if (baseline != null) baselines.add(baseline.value);
  }

  return EvaluationOverlay(
    peakIndexes: peaks,
    circledIndexes: circled,
    arrowIndexes: arrows,
    numbersByIndex: numbers,
    baselineValues: baselines,
  );
}

// --- dot painters -----------------------------------------------------------

/// Paints the temperature dot plus a RING around it, with a small gap so
/// the value stays readable: the mucus-peak day (ring in the mucus
/// color) and the circled higher measurements (ring in the temperature
/// color).
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

/// Paints the temperature dot plus an ARROW-UP glyph above it: a higher
/// measurement before the peak (or with the peak unmarked) — higher, but
/// explicitly NOT circled per the rule that only the first higher
/// measurement after the peak gets circled.
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
      Offset(offsetInCanvas.dx, offsetInCanvas.dy - radius - arrowHeight),
      color: arrowColor,
    );
  }

  @override
  Size getSize(FlSpot spot) => Size.fromRadius(radius + arrowHeight);

  @override
  List<Object?> get props => [...super.props, arrowColor];
}

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

/// Chooses the dot painter for one chart day: plain dot, dot with a
/// ring (mucus peak / circled higher measurement) or dot with an
/// arrow-up glyph. [dayIndex] and [overlay] indexes share one space.
FlDotPainter dotPainterForDay({
  required int dayIndex,
  required Color dotColor,
  required ColorScheme colorScheme,
  required EvaluationOverlay overlay,
}) {
  if (overlay.peakIndexes.contains(dayIndex)) {
    return RingDotPainter(color: dotColor, ringColor: colorScheme.tertiary);
  }
  if (overlay.circledIndexes.contains(dayIndex)) {
    return RingDotPainter(color: dotColor, ringColor: colorScheme.primary);
  }
  if (overlay.arrowIndexes.contains(dayIndex)) {
    return ArrowUpDotPainter(color: dotColor, arrowColor: colorScheme.primary);
  }
  return FlDotCirclePainter(color: dotColor);
}

// --- widget-level pieces ----------------------------------------------------

/// The 1–6 numbering under the chart: one narrow tappable cell per
/// calendar day, aligned by the same even day spacing as the chart and
/// the symbol row (mirrors _SymbolRow in cycle.dart). Days outside the
/// six-low windows render an empty fixed-height slot.
final class EvaluationMarksRow extends StatelessWidget {
  const EvaluationMarksRow({
    super.key,
    required this.dayCount,
    required this.numbersByIndex,
    required this.onDayTap,
  });

  final int dayCount;
  final Map<int, int> numbersByIndex;
  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < dayCount; i++)
          Expanded(
            child: InkWell(
              onTap: () => onDayTap(i),
              child: _NumberCell(
                key: ValueKey('marksCell-$i'),
                number: numbersByIndex[i],
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
    // number (same trick as _SymbolCell's sign slot).
    return SizedBox(
      height: 14,
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
