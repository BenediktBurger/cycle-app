// Zyklus screen: the recorded temperature curve plus the bleeding/mucus
// symbol row underneath, purely as signals. NOTHING is evaluated here —
// no baseline, no coverline, no fertile-window hints. That analysis is
// Mode-M territory (user-placed marks), deferred past this milestone per
// ADR-0001 (status: Hypothesis).
//
// Tapping a chart day or a symbol cell jumps to the Tagebuch form with that
// date pre-selected (shared via selectedDateProvider + tabIndexProvider).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/date_only.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
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

  void _openDayInForm(int index) {
    // Tapping the curve means: edit (or at least review) that day.
    ref.read(selectedDateProvider.notifier).state = _days.dayAt(index);
    ref.read(tabIndexProvider.notifier).state = 0; // Tagebuch tab
  }

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (final entry in _days.byIndex.entries)
        if (entry.value.bbtC != null)
          FlSpot(entry.key.toDouble(), entry.value.bbtC!),
    ];

    if (spots.isEmpty) {
      return Text(
        AppLocalizations.of(context).zyklusNoData,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final values = spots.map((s) => s.y).toList();
    var yMin = _floorToHalf(values.reduce((a, b) => a < b ? a : b) - 0.4)
        .clamp(34.0, 40.0);
    var yMax = _ceilToHalf(values.reduce((a, b) => a > b ? a : b) + 0.4)
        .clamp(35.5, 42.0);
    if (yMax <= yMin) {
      // Never let degenerate bounds through to the chart.
      yMax = yMin + 0.5;
    }

    final xInterval = (_days.dayCount / 8).ceil().toDouble().max(1);
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
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 1.6,
                  color: Theme.of(context).colorScheme.primary,
                  dotData: const FlDotData(show: true),
                ),
              ],
              minX: 0,
              maxX: maxX,
              minY: yMin,
              maxY: yMax,
              rangeAnnotations: RangeAnnotations(
                verticalRangeAnnotations: weekendBands,
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
                  _openDayInForm(index);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SymbolRow(days: _days, onDayTap: _openDayInForm),
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
        for (var i = 0; i < days.dayCount; i++)
          Expanded(
            child: InkWell(
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
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendDot(
          color: Theme.of(context).colorScheme.primary,
          label: AppLocalizations.of(context).zyklusLegendTemperature,
          shape: _LegendShape.dot,
        ),
        _LegendDot(
          color: Theme.of(context).colorScheme.error,
          label: AppLocalizations.of(context).zyklusLegendBleeding,
          shape: _LegendShape.ring,
        ),
        _LegendDot(
          color: Theme.of(context).colorScheme.tertiary,
          label: AppLocalizations.of(context).zyklusLegendMucus,
          shape: _LegendShape.text,
        ),
      ],
    );
  }
}

enum _LegendShape { dot, ring, text }

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
