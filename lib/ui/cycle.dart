// Zyklus screen: the recorded temperature curve plus the bleeding/mucus
// symbol row underneath, plus the COMPUTED evaluation overlay (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks, the app
// derives the rest for DISPLAY ONLY — peak circle, circled higher
// measurements, arrow-up for pre-peak rises, the 1–6 low numbering and the
// baseline (lib/ui/cycle_marks.dart over evaluateCycles). No derived
// artifact is persisted, and no fertility statement is made (SUZ arithmetic
// stays domain-only; see lib/domain/evaluation.dart).
//
// Tapping a chart day or a symbol cell opens the day's mark-entry bottom
// sheet (lib/ui/cycle_mark_sheet.dart): edit day (jumps to the Tagebuch
// form with that date pre-selected, via selectedDateProvider +
// tabIndexProvider), the contextual mark toggles and the computed info
// line.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'cycle_curve.dart';
import 'cycle_mark_sheet.dart';
import 'cycle_marks.dart';
import 'mucus_symbol.dart';

class ZyklusScreen extends ConsumerWidget {
  const ZyklusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(dailyEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navZyklus)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text(l10n.loadFailed)),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.zyklusNoData),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CycleChart(entries: entries),
              const SizedBox(height: 12),
              const _Legend(),
              const SizedBox(height: 4),
              Text(
                l10n.zyklusArithmeticNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The chart data view model for one recorded range: day index -> signal.
final class _ChartDays {
  _ChartDays(List<DailyEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));
    firstDay = DateOnly.normalize(sorted.first.date);
    dayCount =
        DateOnly.daysBetween(DateOnly.normalize(sorted.last.date), firstDay) +
            1;
    for (final e in sorted) {
      byIndex[DateOnly.daysBetween(DateOnly.normalize(e.date), firstDay)] = e;
    }
  }

  /// UTC-midnight of the first recorded day (day index 0).
  late final DateTime firstDay;

  /// Index range length (>= number of recorded days; gaps included).
  late final int dayCount;

  final Map<int, DailyEntry> byIndex = {};

  DateTime dayAt(int index) => DateOnly.addDays(firstDay, index);
}

/// fl_chart line chart over all measured days plus a per-day symbol row.
///
/// The x axis is a plain day index over the recorded range: calendar gaps
/// (days without any measurement) stay honest as distance, not compressed.
/// Y bounds are rounded to the nearest half degree so the gridlines carry
/// typical 0.25 °C steps without a "good range" being implied.
final class _CycleChart extends ConsumerStatefulWidget {
  const _CycleChart({required this.entries});

  final List<DailyEntry> entries;

  @override
  ConsumerState<_CycleChart> createState() => _CycleChartState();
}

final class _CycleChartState extends ConsumerState<_CycleChart> {
  late final _ChartDays _days;

  @override
  void initState() {
    super.initState();
    _days = _ChartDays(widget.entries);
  }

  void _openDaySheet(int index) {
    // Tapping the curve, the marks row or a symbol cell opens the day's
    // mark-entry sheet; the form jump ("edit day") lives inside the sheet.
    showCycleDaySheet(context, day: _days.dayAt(index));
  }

  @override
  Widget build(BuildContext context) {
    // The evaluation artifacts (peak circle, circled higher measurements,
    // arrow-up, 1–6 numbering, baseline) are computed at render time from
    // the entries plus the user-placed marks — never persisted, so a mark
    // change live-updates the whole overlay (ADR-0001). The marks stream is
    // watched only here: the curve itself never depends on it.
    final marksAsync = ref.watch(marksProvider);
    final marks = marksAsync.valueOrNull ?? const <CycleMark>[];
    final overlay = buildEvaluationOverlay(
      evaluations: evaluateCycles(widget.entries, marks),
      firstDay: _days.firstDay,
      dayCount: _days.dayCount,
    );

    // The curve is split into runs of adjacent measured days (curve helpers,
    // lib/ui/cycle_curve.dart): the line connects two temperatures only when
    // their calendar days are adjacent, so a day without a temperature
    // (missing entry or entry without bbtC) breaks the line.
    final runs = curveRuns(_days.byIndex);
    final segments = curveSegments(runs);
    final points = [for (final run in runs) ...run.points];

    if (points.isEmpty) {
      return Text(
        AppLocalizations.of(context).zyklusNoData,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final yValues = [for (final point in points) point.bbtC];
    var yMin = _floorToHalf(yValues.reduce((a, b) => a < b ? a : b) - 0.4)
        .clamp(34.0, 40.0);
    var yMax = _ceilToHalf(yValues.reduce((a, b) => a > b ? a : b) + 0.4)
        .clamp(35.5, 42.0);
    if (yMax <= yMin) {
      // Never let degenerate bounds through to the chart.
      yMax = yMin + 0.5;
    }

    final xInterval = (_days.dayCount / 8).ceil().toDouble().max(1);
    // Interrupted (excluded) TEMPERATURES read lighter: the scheme color at
    // a fraction of the alpha. The dark scheme's primary is a bright color,
    // so the dimmed tint still keeps darkness-readable contrast (asserted
    // by the dark-mode chart tests).
    final temperatureColor = Theme.of(context).colorScheme.primary;
    final interruptedColor = temperatureColor.withValues(alpha: 0.4);
    final interruptedByIndex = <int, bool>{
      for (final point in points) point.dayIndex: point.excluded,
    };
    // The baseline is theme-derived too (secondary: the one scheme color the
    // temperature/bleeding/mucus rendering does not use — see _Legend).
    final baselineColor = Theme.of(context).colorScheme.secondary;
    // fl_chart requires minX < maxX; a single recorded day gets a 1-day
    // tick window instead of a degenerate zero-width axis.
    final maxX = _days.dayCount <= 1 ? 1.0 : (_days.dayCount - 1).toDouble();

    // Weekend highlighting (owner decision: temperature curve only, not the
    // Tagebuch list). A subtle vertical band behind each weekend day's chart
    // column (Saturday/Sunday by calendar date via DateOnly.isWeekend, never
    // by column index). fl_chart's rangeAnnotations paints these regions
    // behind the grid, line and dots — the lightest-touch approach. The tint
    // is the theme's on-color at a whisper of opacity, so it works on the
    // light as well as the dark surface (dark: light overlay).
    final weekendBandColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);
    final lastX = (_days.dayCount - 1).toDouble();
    final weekendBands = <VerticalRangeAnnotation>[];
    for (var i = 0; i < _days.dayCount; i++) {
      if (!DateOnly.isWeekend(_days.dayAt(i))) continue;
      // Half a day left and right of the day's x position, clipped to the
      // really recorded range (edge days keep a narrower band).
      var x1 = (i - 0.5).clamp(0, lastX).toDouble();
      var x2 = (i + 0.5).clamp(0, lastX).toDouble();
      // Single-day chart: maxX widens to 1.0 while lastX is 0, so the clamp
      // collapses the band to zero width — extend the right edge instead so
      // the weekend still shows (left of the day lies outside minX 0).
      if (x2 <= x1) x2 = x1 + 0.5;
      weekendBands.add(
        VerticalRangeAnnotation(x1: x1, x2: x2, color: weekendBandColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              lineBarsData: [
                // The line: one two-spot bar per adjacent-day pair, so a
                // segment touching an interrupted (excluded) day can render
                // lighter while the others keep the full-strength color.
                // Dots are painted afterwards by the dot bars below.
                for (final segment in segments)
                  LineChartBarData(
                    spots: [
                      FlSpot(segment.a.dayIndex.toDouble(), segment.a.bbtC),
                      FlSpot(segment.b.dayIndex.toDouble(), segment.b.bbtC),
                    ],
                    isCurved: false,
                    barWidth: 1.6,
                    color:
                        segment.lighter ? interruptedColor : temperatureColor,
                    dotData: const FlDotData(show: false),
                  ),
                // The dots: invisible-line bars (transparent color) holding
                // each run's spots, so the per-spot dot painter can render
                // an interrupted day's dot lighter than the others.
                for (final run in runs)
                  LineChartBarData(
                    spots: [
                      for (final point in run.points)
                        FlSpot(point.dayIndex.toDouble(), point.bbtC),
                    ],
                    color: Colors.transparent,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, bar, __) =>
                          dotPainterForDay(
                        dayIndex: spot.x.round(),
                        dotColor:
                            interruptedByIndex[spot.x.round()] ?? false
                                ? interruptedColor
                                : temperatureColor,
                        colorScheme: Theme.of(context).colorScheme,
                        overlay: overlay,
                      ),
                    ),
                  ),
              ],
              minX: 0,
              maxX: maxX,
              minY: yMin,
              maxY: yMax,
              rangeAnnotations: RangeAnnotations(
                verticalRangeAnnotations: weekendBands,
              ),
              // The baseline: one dashed horizontal line per evaluated
              // cycle, through the highest of its six low measurements
              // (theme-derived color, dashed so it never reads as a
              // gridline or as curve data). Spans the full chart width —
              // see the TODO(user-review) in cycle_marks.dart.
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  for (final y in overlay.baselineValues)
                    HorizontalLine(
                      y: y,
                      color: baselineColor,
                      strokeWidth: 1,
                      dashArray: const [6, 4],
                    ),
                ],
              ),
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    reservedSize: 44,
                    showTitles: true,
                    interval: 0.5,
                    getTitlesWidget: _yTitle,
                  ),
                ),
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    reservedSize: 22,
                    showTitles: true,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) => _xTitle(
                      value,
                      meta,
                      firstDay: _days.firstDay,
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: false,
                touchCallback: (event, response) {
                  final tapLike =
                      event is FlTapUpEvent || event is FlLongPressEnd;
                  if (!tapLike) return;
                  final touched = response?.lineBarSpots;
                  if (touched == null || touched.isEmpty) return;
                  final index =
                      touched.first.x.round().clamp(0, _days.dayCount - 1);
                  _openDaySheet(index);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // The 1–6 low numbering, directly under the chart day columns.
        EvaluationMarksRow(
          dayCount: _days.dayCount,
          numbersByIndex: overlay.numbersByIndex,
          onDayTap: _openDaySheet,
        ),
        const SizedBox(height: 4),
        _SymbolRow(days: _days, onDayTap: _openDaySheet),
      ],
    );
  }
}

/// One narrow cell per calendar day under the chart, aligned by the same
/// even day spacing as the chart: bleeding marker on top, the recorded
/// fertility sign (`Sᴱᵂ` style) below. Pure recording, no interpretation.
final class _SymbolRow extends StatelessWidget {
  const _SymbolRow({required this.days, required this.onDayTap});

  final _ChartDays days;
  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The cell key exposes the whole tappable per day index for the
        // widget tests (same convention as marksCell-$i above the chart).
        for (var i = 0; i < days.dayCount; i++)
          Expanded(
            child: InkWell(
              key: ValueKey('symbolCell-$i'),
              onTap: () => onDayTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _SymbolCell(entry: days.byIndex[i]),
              ),
            ),
          ),
      ],
    );
  }
}

final class _SymbolCell extends StatelessWidget {
  const _SymbolCell({required this.entry});

  final DailyEntry? entry;

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return const SizedBox(height: 26);
    }
    // Bleeding marker (top): none draws nothing; spotting is the hollow
    // ring; light..heavy fill the circle with the error color at the same
    // graded opacity as the diary day tiles (light 0.6 / medium 0.8 /
    // heavy 1.0), so the heaviness reads the same in both views.
    final bleedingColor = Theme.of(context).colorScheme.error;
    final bleeding = entry!.bleeding;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bleeding.level >= 2
                ? bleedingColor.withValues(
                    alpha: switch (bleeding) {
                      // none/spotting are guarded by level >= 2 above.
                      Bleeding.none || Bleeding.spotting => 1.0,
                      Bleeding.light => 0.6,
                      Bleeding.medium => 0.8,
                      Bleeding.heavy => 1.0,
                    },
                  )
                : Colors.transparent,
            border: Border.all(
              width: 1.5,
              color: bleeding == Bleeding.none
                  ? Colors.transparent
                  : bleedingColor,
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Fertility sign (bottom, superscript quality style); the fixed
        // slot height keeps all cells aligned even with no sign recorded.
        SizedBox(
          height: 12,
          child: Align(
            alignment: Alignment.topCenter,
            child: MucusSymbolText(
              display: mucusDisplay(
                sign: entry!.mucusSign,
                quality: entry!.mucusQuality,
              ),
              fontSize: 9,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ),
      ],
    );
  }
}

final class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendDot(
          color: scheme.primary,
          label: AppLocalizations.of(context).zyklusLegendTemperature,
          shape: _LegendShape.dot,
        ),
        _LegendDot(
          color: scheme.error,
          label: AppLocalizations.of(context).zyklusLegendBleeding,
          shape: _LegendShape.ring,
        ),
        _LegendDot(
          color: scheme.tertiary,
          label: AppLocalizations.of(context).zyklusLegendMucus,
          shape: _LegendShape.text,
        ),
        _LegendDot(
          color: scheme.tertiary,
          label: AppLocalizations.of(context).zyklusLegendMucusPeak,
          shape: _LegendShape.ring,
        ),
        _LegendDot(
          color: scheme.primary,
          label: AppLocalizations.of(context).zyklusLegendFirstHigher,
          shape: _LegendShape.circledDot,
        ),
        _LegendDot(
          color: scheme.primary,
          label: AppLocalizations.of(context).zyklusLegendRiseBeforePeak,
          shape: _LegendShape.arrowUp,
        ),
        _LegendDot(
          color: scheme.secondary,
          label: AppLocalizations.of(context).zyklusLegendBaseline,
          shape: _LegendShape.line,
        ),
      ],
    );
  }
}

enum _LegendShape { dot, ring, text, circledDot, arrowUp, line }

final class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.shape,
  });

  final Color color;
  final String label;
  final _LegendShape shape;

  @override
  Widget build(BuildContext context) {
    final Widget symbol = switch (shape) {
      _LegendShape.dot => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      _LegendShape.ring => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(width: 1.5, color: color),
          ),
        ),
      _LegendShape.text => MucusSymbolText(
          // Sample observation: S with the EW quality qualifier, exactly
          // how a recorded mucus day renders in the symbol row above.
          display: mucusDisplay(sign: MucusSign.s, quality: MucusQuality.ew),
          fontSize: 10,
          color: color,
        ),
      _LegendShape.circledDot => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(width: 1.5, color: color),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      _LegendShape.arrowUp => ArrowUpGlyph(color: color),
      _LegendShape.line => Container(width: 16, height: 2, color: color),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        symbol,
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// --- axis title helpers ----------------------------------------------------

/// Y axis: plain degree labels ("36.5" — numeric, sidebar-localized).
Widget _yTitle(double value, TitleMeta meta) => Text(
      _formatHalfDegree(value),
      style: const TextStyle(fontSize: 10),
    );

/// X axis: day-of-month labels ("14.") at the interval ticks.
Widget _xTitle(double value, TitleMeta meta, {required DateTime firstDay}) {
  final i = value.round();
  if (value != i.toDouble() || i < 0) return const SizedBox.shrink();
  final day = DateOnly.addDays(firstDay, i);
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '${day.day}.',
      style: const TextStyle(fontSize: 10),
    ),
  );
}

String _formatHalfDegree(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

double _floorToHalf(double v) => (v * 2).floorToDouble() / 2;

double _ceilToHalf(double v) => (v * 2).ceilToDouble() / 2;

extension _MaxNum on num {
  double max(num other) => this > other ? toDouble() : other.toDouble();
}
