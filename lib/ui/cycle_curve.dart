// Pure curve-structure helpers for the Zyklus temperature chart: which
// days form drawable line runs (adjacent-day connectivity) and which
// segments are interrupted (ignored) and must render lighter. No Flutter
// or chart types here — the widget layer (lib/ui/cycle.dart) maps these
// onto fl_chart bars; tests assert the rule set directly.
import '../domain/models.dart';

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
