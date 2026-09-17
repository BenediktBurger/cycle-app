// Computed evaluation marks on the cycle chart (Mode M, ADR-0001).
//
// The USER places only the mucus peak and the first higher measurement;
// everything rendered from this file is DERIVED at render time from
// evaluateCycles (lib/domain/evaluation.dart) and is never persisted:
// the rings around the circled higher measurements (candidates strictly
// AFTER the mucus peak day), the arrow-up glyph for the arrow-marked
// candidates (candidate day at or before the peak day, or the peak unset —
// R4, decided PER CANDIDATE by the domain), the 1–6 numbering under the six
// low days, the baseline SEGMENT (R10: from the left edge of low #6's day
// column to half a day past the last marked candidate's column, from the
// domain's baselineSpan; a cycle with no marked candidate draws no segment)
// and the solid peak dot ABOVE the mucus entry in the symbol row (R6 — the
// peak no longer touches the temperature curve). Rendered across fl_chart's
// dot painters + dashed bar segments, with the glyph shapes painted by hand
// where fl_chart has no facility (ADR-0004 anticipates this custom-paint
// fallback — used here only for small glyphs; the baseline segment fits
// inside fl_chart as a dashed two-spot bar, so the chart itself stays
// fl_chart).
//
// Rendering assumptions (validate with an expert reviewer, see
// docs/adr/0001-iner-mode-m-hypothesis.md, status: Hypothesis):
//
//   TODO(user-review): A peak day without a recorded entry renders NO dot
//   in the symbol row (the row shows recorded observations only). The
//   old chart-anchored question is gone with the curve ring: the peak
//   dot lives in the symbol row, where a day without an entry has no
//   cell content to hang it on.
//   TODO(user-review): Days after the SUZ trigger or after a
//   connectedness break render as ordinary temperature dots (the domain
//   lists exactly the marked candidates; there is no automatic
//   continuation — the user re-marks the rise, R2). Candidates beyond
//   their kind's four-cap STAY in the sequence (R4) and render as the
//   ordinary circle/arrow mark, just without a number — the curve never
//   paints candidate ordinals; the sheet's circle-numbering line is the
//   only ordinal surface (circles-only, see cycle_mark_sheet.dart).

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';

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
  });

  /// Day indexes carrying the mucus-peak mark. R6: the peak renders as a
  /// solid dot ABOVE the mucus glyph in the symbol row — the curve never
  /// rings the peak day (the curve's rings wrap only circled candidates).
  final Set<int> peakIndexes;
  final Set<int> circledIndexes;
  final Set<int> arrowIndexes;
  final Map<int, int> numbersByIndex;

  /// The baseline segments (R10), one per evaluated cycle with a marked
  /// candidate; a cycle without candidates has none.
  final List<BaselineSegment> baselineSegments;
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
  final segments = <BaselineSegment>[];

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

/// Paints the temperature dot plus an ARROW-UP glyph above it: a marked
/// candidate whose day is at or before the mucus peak day, or one of a
/// cycle with the peak unset (R4, decided per candidate by the domain) —
/// higher, but explicitly NOT circled per the rule that only candidates
/// after the peak get circled. Beyond the arrow kind's four-cap the
/// candidate stays arrowed too, just unnumbered.
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
