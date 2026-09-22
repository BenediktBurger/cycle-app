// Pure curve-structure helpers for the Zyklus temperature chart: which
// days form drawable line runs (adjacent-day connectivity), which
// segments are interrupted (ignored) and must render lighter, and which
// portions of a segment lie inside the chart's visible value range.
// CurvePoints keep the RAW measured temperature: whether a point or a
// piece of a line is visible is decided by the value-range helpers below,
// never by rewriting the measured value. No Flutter or chart types here —
// the widget layer (lib/ui/cycle.dart) maps these onto fl_chart bars;
// tests assert the rule set directly.
import '../domain/models.dart';
import '../domain/temperature_range.dart';

/// The alpha the IGNORED temperatures render with (owner decision
/// 2026-09-19: the ignoreTemperature mark is the rendering key; marked
/// days render lighter).
/// Hoisted here so the chart's lighter color (lib/ui/cycle.dart) and the
/// help sheet's lighter-dot glossary sample derive from ONE constant and
/// cannot drift.
const double ignoredTemperatureAlpha = 0.4;

/// One drawable point of the temperature curve: a measured temperature on
/// its chart x position (day index), flagged when the day carries the
/// ignoreTemperature MARK (the rendering is keyed to the MARK, NOT to the
/// raw `tempDisturbances` mask — owner decision 2026-09-19) and thus
/// renders lighter.
final class CurvePoint {
  const CurvePoint({
    required this.dayIndex,
    required this.bbtC,
    required this.excluded,
  });

  /// Chart x position: the plain day index over the recorded range.
  final int dayIndex;

  /// Measured temperature in °C.
  final double bbtC;

  /// True when the day carries the ignoreTemperature mark (passed in as
  /// the ignored-day-index set): measured, but lighter. The raw mask is
  /// NOT consulted — a flagged day whose mark was removed renders
  /// normally, and a marked day without flags renders lighter.
  final bool excluded;
}

/// A maximal run of adjacent measured days. The line is drawn WITHIN runs
/// only: a day without a temperature (no entry, or entry without bbtC)
/// starts a new run, so no line segment ever spans such a day.
final class CurveRun {
  const CurveRun(this.points);

  final List<CurvePoint> points;
}

/// One drawable straight segment between two adjacent points of a run.
final class CurveSegment {
  const CurveSegment(this.a, this.b);

  final CurvePoint a;
  final CurvePoint b;

  /// A segment touching an interrupted (ignored) day must render lighter.
  bool get lighter => a.excluded || b.excluded;
}

/// One drawable line span of the temperature curve: a piece of a
/// [CurveSegment] that lies inside the chart's visible value range.
/// The line coordinates carry the day index as x (fractional where the
/// straight segment crosses a range boundary) and the °C temperature as
/// y — in-range data keeps its raw values, only boundary crossings land
/// exactly on a bound.
final class VisibleCurveSegment {
  const VisibleCurveSegment._(
    this.startX,
    this.startY,
    this.endX,
    this.endY,
    this.source,
  );

  /// x (day index) of the span's first drawn point.
  final double startX;

  /// y (°C) of the span's first drawn point.
  final double startY;

  /// x (day index) of the span's last drawn point.
  final double endX;

  /// y (°C) of the span's last drawn point.
  final double endY;

  /// The parent segment the span was clipped from (a [CurveSegment]
  /// between two adjacent measured days).
  final CurveSegment source;

  /// A span derived from a segment touching an interrupted (ignored) day
  /// must render lighter, like its parent segment.
  bool get lighter => source.lighter;
}

/// Whether a measured temperature lies inside the chart's visible value
/// range. The bounds are INCLUSIVE: a value exactly at the bottom or top
/// boundary counts as visible, so a boundary measurement keeps drawing its
/// dot without being half-cut. This predicate is the single visibility
/// rule — the segment clipper and the dot filter both consult it.
bool isBbtCInRange(double value, TemperatureRange displayRange) =>
    value >= displayRange.min && value <= displayRange.max;

/// Clips each segment's straight line against the visible value range and
/// returns the drawable spans. A segment is visible wherever its linear
/// interpolation between the two raw endpoint values stays inside
/// [displayRange] — the segment shortens at the boundary crossings (the
/// x position there is fractional: the crossing sits BETWEEN the days).
/// Something is drawable only when the line actually passes through the
/// value window: segments entirely outside produce nothing, and a segment
/// that merely TOUCHES a boundary in one point produces no line either
/// (its boundary measurement is still drawn as a dot — see
/// [isBbtCInRange]). Spans inherit [CurveSegment.lighter] from their
/// parent segment.
List<VisibleCurveSegment> visibleCurveSegments(
  List<CurveSegment> segments,
  TemperatureRange displayRange,
) {
  final spans = <VisibleCurveSegment>[];
  for (final segment in segments) {
    // (x, y) move linearly with t ∈ [0, 1] from a to b. Clip t against
    // both value bounds; empty or single-point intersections drop out.
    var tStart = 0.0;
    var tEnd = 1.0;
    var visible = true;

    void constrainTo(double boundary, {required bool keepAbove}) {
      if (!visible) return;
      final y0 = segment.a.bbtC;
      final dy = segment.b.bbtC - y0;
      if (dy == 0.0) {
        // Flat line: inside the window everywhere or nowhere.
        final inside = keepAbove ? y0 >= boundary : y0 <= boundary;
        if (!inside) visible = false;
        return;
      }
      final t = (boundary - y0) / dy;
      // The side of t where y satisfies the bound: increasing towards the
      // bound's inside means t >= crossing, decreasing means t <= crossing.
      final boundIsLower = keepAbove == (dy > 0.0);
      if (boundIsLower) {
        if (t > tStart) tStart = t;
      } else {
        if (t < tEnd) tEnd = t;
      }
    }

    constrainTo(displayRange.min, keepAbove: true);
    constrainTo(displayRange.max, keepAbove: false);

    if (!visible || tStart > tEnd) continue;

    final startX = _xAt(segment, tStart);
    final startY = _yAt(segment, tStart);
    final endX = _xAt(segment, tEnd);
    final endY = _yAt(segment, tEnd);
    // A touching point (start == end) is not a drawable line.
    if (startX == endX && startY == endY) continue;

    spans.add(VisibleCurveSegment._(startX, startY, endX, endY, segment));
  }
  return spans;
}

double _xAt(CurveSegment segment, double t) =>
    segment.a.dayIndex + t * (segment.b.dayIndex - segment.a.dayIndex);

double _yAt(CurveSegment segment, double t) =>
    segment.a.bbtC + t * (segment.b.bbtC - segment.a.bbtC);

/// Splits the recorded days into maximal runs of adjacent-day measurements.
///
/// [entriesByDayIndex] maps day index -> entry over the chart range (see
/// _ChartDays). Days WITHOUT a temperature — no entry at all, or an entry
/// that carries no bbtC — break the line; a day with a temperature counts
/// as measured even when it is marked ignored. [ignoredDayIndexes] names
/// the chart's day indexes whose temperature is IGNORED (computed by the
/// chart from the ignoreTemperature marks — owner decision 2026-09-19:
/// the mark is the rendering key). A marked day renders lighter whether
/// or not it
/// carries raw disturbance flags; a flagged day whose mark was removed
/// renders normally (the mask is the diary badge's input, not the
/// curve's).
///
/// Every point keeps its RAW measured value — an out-of-range reading is
/// not rewritten here. Connectivity (adjacency) is decided by the calendar
/// days alone, so such a day still joins its neighbors into one run; what
/// becomes drawable of it is decided later by [visibleCurveSegments].
List<CurveRun> curveRuns(
  Map<int, DailyEntry> entriesByDayIndex, {
  Set<int> ignoredDayIndexes = const {},
}) {
  final measured = <CurvePoint>[
    for (final MapEntry(:key, value: entry) in entriesByDayIndex.entries)
      if (entry.bbtC != null)
        CurvePoint(
          dayIndex: key,
          bbtC: entry.bbtC!,
          excluded: ignoredDayIndexes.contains(key),
        ),
  ]..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));

  final runs = <CurveRun>[];
  final run = <CurvePoint>[];
  for (final point in measured) {
    if (run.isNotEmpty && point.dayIndex != run.last.dayIndex + 1) {
      runs.add(CurveRun(List.unmodifiable(run)));
      run.clear();
    }
    run.add(point);
  }
  if (run.isNotEmpty) runs.add(CurveRun(List.unmodifiable(run)));
  return runs;
}

/// All line segments to draw: consecutive point pairs within each run.
List<CurveSegment> curveSegments(List<CurveRun> runs) => [
      for (final run in runs)
        for (var i = 0; i < run.points.length - 1; i++)
          CurveSegment(run.points[i], run.points[i + 1]),
    ];
