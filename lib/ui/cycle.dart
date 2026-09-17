// Zyklus screen: the recorded temperature curve plus the bleeding/mucus
// symbol row underneath, plus the COMPUTED evaluation overlay (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks, the app
// derives the rest for DISPLAY ONLY — circled higher measurements (every
// candidate strictly after the peak day), arrow-up glyphs for candidates at
// or before the peak day or with the peak unset (decided PER CANDIDATE by
// the domain, R4), the solid peak dot ABOVE the mucus entry in the symbol
// row (the peak never touches the curve), the 1–6 low numbering and the
// baseline SEGMENT from low #6 to the last marked candidate (R10;
// lib/ui/cycle_marks.dart over evaluateCycles). No derived artifact is
// persisted, and no fertility statement is made (SUZ arithmetic stays
// domain-only; see lib/domain/evaluation.dart).
//
// Tapping a chart day or a symbol cell opens the day's mark-entry bottom
// sheet (lib/ui/cycle_mark_sheet.dart): edit day (jumps to the Tagebuch
// form with that date pre-selected, via selectedDateProvider +
// tabIndexProvider), the contextual mark toggles and the computed info
// line.
//
// The chart block renders a VIEWPORT-LIMITED WINDOW of days: day columns
// keep at least a minimum usable width (see _CycleChartState's
// minDayColumnWidth), so a long
// recorded range is not squeezed onto one screen — the whole block (curve,
// per-day column labels, marks row, symbol row) scrolls horizontally as one
// unit, and a jump-to-date affordance moves the window onto a picked
// calendar day. Data outside the window is not built: the curve carries
// only the window's points (at their global x positions, so windows slide
// seamlessly) and the label/symbol rows build only the window's cells.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/cervix.dart';
import '../domain/cycle_grouping.dart';
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
    // Cycle mapping over the whole index range, from the domain's cycle
    // grouping (same groups the Tagebuch list and the evaluation use):
    // every calendar day counts in the cycle whose start is the LATEST
    // group start on or before it — a cycle only ends at the next onset,
    // so untracked gap days keep counting from the last start. The first
    // (leading) group starts at the first recorded day, so every index is
    // covered.
    // TODO(user-review): before the first real onset (a leading group of
    // days that predate the first recorded period) the count starts at the
    // first TRACKED day — the true cycle start is unknowable there.
    final groups = groupIntoCycles(sorted);
    final starts = [for (final g in groups) DateOnly.normalize(g.startDate)];
    var group = 0;
    for (var i = 0; i < dayCount; i++) {
      final date = dayAt(i);
      while (group + 1 < starts.length && !starts[group + 1].isAfter(date)) {
        group++;
      }
      cycleDayByIndex[i] = DateOnly.daysBetween(date, starts[group]) + 1;
    }
  }

  /// UTC-midnight of the first recorded day (day index 0).
  late final DateTime firstDay;

  /// Index range length (>= number of recorded days; gaps included).
  late final int dayCount;

  final Map<int, DailyEntry> byIndex = {};

  /// Day of cycle (1, 2, 3 …) per day index, counted from the start of the
  /// cycle group the day belongs to (see the mapping note above).
  final Map<int, int> cycleDayByIndex = {};

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
  /// Narrowest day column still considered usable. Below this width the
  /// day-of-month labels ("28.") and the symbol cells would overlap, so a
  /// recorded range longer than one screen scrolls instead of shrinking
  /// further — the day count shown at once derives from the actual layout
  /// width, never from a hard-coded number.
  static const double minDayColumnWidth = 24;

  /// The y-axis title strip the chart reserves on its left edge (fl_chart's
  /// leftTitles reservation, mirrored in the chart config below). The tap
  /// mapping needs the same figure: the curve's plot area starts right of
  /// this strip.
  static const double leftAxisReservedSize = 44;

  static const Duration _scrollDuration = Duration(milliseconds: 300);

  late _ChartDays _days;
  final ScrollController _scrollController = ScrollController();

  /// Layout snapshot of the last build, for the scroll listener's window
  /// math and the jump-to-date target computation.
  double? _viewportWidth;
  double? _columnWidth;

  /// The day-index window currently built (inclusive bounds). It carries one
  /// day of margin past each visible edge: as the content slides, data that
  /// has not scrolled fully into view is already present, so a window
  /// rebuild never introduces a visual seam at the viewport edge.
  int _windowStart = 0;
  int _windowEnd = 0;

  @override
  void initState() {
    super.initState();
    _days = _ChartDays(widget.entries);
    _scrollController.addListener(_onScrolled);
  }

  @override
  void didUpdateWidget(covariant _CycleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live entry write re-emits the entries stream while this state is
    // alive: recompute the day mapping so a changed range re-windows
    // instead of rendering stale data.
    if (!identical(oldWidget.entries, widget.entries)) {
      _days = _ChartDays(widget.entries);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrolled);
    _scrollController.dispose();
    super.dispose();
  }

  void _openDaySheet(int index) {
    // Tapping the curve, the marks row or a symbol cell opens the day's
    // mark-entry sheet; the form jump ("edit day") lives inside the sheet.
    showCycleDaySheet(context, day: _days.dayAt(index));
  }

  /// The day-index window to build for the current scroll offset: every
  /// column that is at least partially on screen, plus the one-day margin
  /// of [_windowStart]/[_windowEnd].
  (int, int) _windowFor(int dayCount) {
    final viewport = _viewportWidth ?? 0;
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final visible = (viewport / colW).ceil().clamp(1, dayCount);
    final firstVisible = (offset / colW).floor().clamp(0, dayCount - 1);
    return (
      math.max(0, firstVisible - 1),
      math.min(dayCount - 1, firstVisible + visible),
    );
  }

  void _onScrolled() {
    final (start, end) = _windowFor(_days.dayCount);
    if (start != _windowStart || end != _windowEnd) {
      setState(() {
        _windowStart = start;
        _windowEnd = end;
      });
    }
  }

  /// Translates a tap on the chart's plot area into a day index and opens
  /// the day's sheet. The overlay starts at the plot's left edge (right of
  /// the y-axis strip); day indexes map linearly onto the plot width (0 at
  /// the left edge, maxX at its right edge — fl_chart's pixel mapping). The
  /// nearest day column wins, exactly like the row cells underneath.
  void _openDayAtLocalX(double localX, double contentWidth) {
    final plotWidth = contentWidth - leftAxisReservedSize;
    final maxX = _days.dayCount <= 1 ? 1.0 : (_days.dayCount - 1).toDouble();
    final t = (localX / plotWidth).clamp(0.0, 1.0);
    final index = (t * maxX).round().clamp(0, _days.dayCount - 1);
    _openDaySheet(index);
  }

  /// The jump-to-date affordance: opens the material date picker bounded to
  /// the recorded range and scrolls the window so the picked day is centered.
  Future<void> _jumpToDate(BuildContext context) async {
    final viewport = _viewportWidth;
    final colW = _columnWidth;
    if (viewport == null || colW == null) return;
    final firstDay = _days.firstDay;
    final lastDay = _days.dayAt(_days.dayCount - 1);
    // Initial pick: the leftmost day of the window currently on screen —
    // the day the user is looking at, not a hidden default.
    final initial = _days.dayAt(math.min(_windowStart, _days.dayCount - 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDay,
      lastDate: lastDay,
    );
    if (picked == null) return;
    final index = DateOnly.daysBetween(DateOnly.normalize(picked), firstDay)
        .clamp(0, _days.dayCount - 1);
    if (!_scrollController.hasClients) return;
    final target = (index * colW - (viewport - colW) / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    await _scrollController.animateTo(
      target,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
    // (missing entry or entry without bbtC) breaks the line. This global
    // structure feeds the Y bounds: the scale must cover the whole recorded
    // range so scrolling never rescales the curve.
    final runs = curveRuns(_days.byIndex);
    final points = [for (final run in runs) ...run.points];

    if (points.isEmpty) {
      return Text(
        l10n.zyklusNoData,
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

    // Interrupted (excluded) TEMPERATURES read lighter: the scheme color at
    // a fraction of the alpha. The dark scheme's primary is a bright color,
    // so the dimmed tint still keeps darkness-readable contrast (asserted
    // by the dark-mode chart tests).
    final temperatureColor = Theme.of(context).colorScheme.primary;
    final interruptedColor = temperatureColor.withValues(alpha: 0.4);
    // The baseline is theme-derived too (secondary: the one scheme color the
    // temperature/bleeding/mucus rendering does not use — see _Legend). It
    // feeds the dashed R10 segment bars below, not a full-width line.
    final baselineColor = Theme.of(context).colorScheme.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        _viewportWidth = viewport;
        final dayCount = _days.dayCount;
        // Useful day columns: at most as many days as fit the viewport at
        // the minimum usable width; a longer range keeps that width and
        // scrolls horizontally instead of squeezing.
        final overflow = dayCount * minDayColumnWidth > viewport;
        final colW = overflow ? minDayColumnWidth : viewport / dayCount;
        _columnWidth = colW;
        final contentWidth = dayCount * colW;
        final (winStart, winEnd) = _windowFor(dayCount);
        _windowStart = winStart;
        _windowEnd = winEnd;

        // The window's data slice, at the curve's GLOBAL x positions: the
        // axis range (minX..maxX) never changes with the scroll, so a
        // window rebuild only adds/removes points in place — the content
        // slides seamlessly instead of jumping.
        final winByIndex = {
          for (final entry in _days.byIndex.entries)
            if (entry.key >= winStart && entry.key <= winEnd)
              entry.key: entry.value,
        };
        final winRuns = curveRuns(winByIndex);
        final winSegments = curveSegments(winRuns);
        final interruptedByIndex = <int, bool>{
          for (final run in winRuns)
            for (final point in run.points) point.dayIndex: point.excluded,
        };

        // Weekend highlighting (owner decision: temperature curve only, not
        // the Tagebuch list). A subtle vertical band behind each weekend
        // day's chart column (Saturday/Sunday by calendar date via
        // DateOnly.isWeekend, never by column index), built for the window
        // only. fl_chart's rangeAnnotations paints these regions behind the
        // grid, line and dots — the lightest-touch approach. The tint is
        // the theme's on-color at a whisper of opacity, so it works on the
        // light as well as the dark surface (dark: light overlay).
        final weekendBandColor =
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);
        final lastX = (dayCount - 1).toDouble();
        final weekendBands = <VerticalRangeAnnotation>[];
        for (var i = winStart; i <= winEnd; i++) {
          if (!DateOnly.isWeekend(_days.dayAt(i))) continue;
          // Half a day left and right of the day's x position, clipped to
          // the really recorded range (edge days keep a narrower band).
          var x1 = (i - 0.5).clamp(0, lastX).toDouble();
          var x2 = (i + 0.5).clamp(0, lastX).toDouble();
          // Single-day chart: maxX widens to 1.0 while lastX is 0, so the
          // clamp collapses the band to zero width — extend the right edge
          // instead so the weekend still shows (left of the day lies
          // outside minX 0).
          if (x2 <= x1) x2 = x1 + 0.5;
          weekendBands.add(
            VerticalRangeAnnotation(x1: x1, x2: x2, color: weekendBandColor),
          );
        }

        // fl_chart requires minX < maxX; a single recorded day gets a 1-day
        // tick window instead of a degenerate zero-width axis.
        final maxX = dayCount <= 1 ? 1.0 : (dayCount - 1).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const ValueKey('calendarJumpButton'),
                icon: const Icon(Icons.date_range),
                tooltip: l10n.zyklusJumpToDate,
                onPressed: () => _jumpToDate(context),
              ),
            ),
            SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 260,
                      child: Stack(
                        children: [
                          LineChart(
                            LineChartData(
                              lineBarsData: [
                                // The line: one two-spot bar per
                                // adjacent-day pair, so a segment touching
                                // an interrupted (excluded) day can render
                                // lighter while the others keep the
                                // full-strength color. Dots are painted
                                // afterwards by the dot bars below. Only
                                // the window's segments are carried — the
                                // x positions stay global.
                                for (final segment in winSegments)
                                  LineChartBarData(
                                    spots: [
                                      FlSpot(segment.a.dayIndex.toDouble(),
                                          segment.a.bbtC),
                                      FlSpot(segment.b.dayIndex.toDouble(),
                                          segment.b.bbtC),
                                    ],
                                    isCurved: false,
                                    barWidth: 1.6,
                                    color: segment.lighter
                                        ? interruptedColor
                                        : temperatureColor,
                                    dotData: const FlDotData(show: false),
                                  ),
                                // The dots: invisible-line bars (transparent
                                // color) holding each run's spots, so the
                                // per-spot dot painter can render an
                                // interrupted day's dot lighter than the
                                // others.
                                for (final run in winRuns)
                                  LineChartBarData(
                                    spots: [
                                      for (final point in run.points)
                                        FlSpot(point.dayIndex.toDouble(),
                                            point.bbtC),
                                    ],
                                    color: Colors.transparent,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter: (spot, _, bar, __) =>
                                          dotPainterForDay(
                                        dayIndex: spot.x.round(),
                                        dotColor: interruptedByIndex[
                                                    spot.x.round()] ??
                                                false
                                            ? interruptedColor
                                            : temperatureColor,
                                        colorScheme:
                                            Theme.of(context).colorScheme,
                                        overlay: overlay,
                                      ),
                                    ),
                                  ),
                                // The baseline segments (R10): one dashed
                                // two-spot bar per evaluated cycle, drawn
                                // LAST so it paints above the curve and the
                                // dots (the full-width HorizontalLine it
                                // replaces was drawn on top too). Extent per
                                // the domain's baselineSpan: from the left
                                // edge of low #6's day column to half a day
                                // past the last marked candidate's column,
                                // clamped to the recorded range (mirror of
                                // the weekend-band clamping). Keeps the
                                // dashed style and the theme-derived
                                // secondary color, without spanning the
                                // whole plot — no ADR-0004 custom painter
                                // needed, the segment fits inside fl_chart.
                                for (final segment in overlay.baselineSegments)
                                  LineChartBarData(
                                    spots: [
                                      FlSpot(
                                          math.max(
                                              0.0, segment.startIndex - 0.5),
                                          segment.value),
                                      FlSpot(
                                          math.min(
                                              lastX, segment.endIndex + 0.5),
                                          segment.value),
                                    ],
                                    isCurved: false,
                                    barWidth: 1,
                                    color: baselineColor,
                                    dashArray: const [6, 4],
                                    dotData: const FlDotData(show: false),
                                  ),
                              ],
                              minX: 0,
                              maxX: maxX,
                              minY: yMin,
                              maxY: yMax,
                              rangeAnnotations: RangeAnnotations(
                                verticalRangeAnnotations: weekendBands,
                              ),
                              gridData:
                                  const FlGridData(drawVerticalLine: false),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    reservedSize: leftAxisReservedSize,
                                    showTitles: true,
                                    interval: 0.5,
                                    getTitlesWidget: _yTitle,
                                  ),
                                ),
                                topTitles: const AxisTitles(),
                                rightTitles: const AxisTitles(),
                                // The per-day column labels (day of month +
                                // day of cycle) render in _DayLabelRow
                                // UNDER the chart instead of fl_chart's
                                // bottom axis: every day column gets a
                                // label, not just the sparse interval
                                // ticks, and the row builds windowed.
                                bottomTitles: const AxisTitles(),
                              ),
                              // Touch handling: the chart itself is
                              // gesture-transparent (enabled: false) so the
                              // horizontal scroll owns drags; the overlay
                              // above it catches tap-like pointers only and
                              // maps them to day columns (same tap AND
                              // long-press behavior the built-in touch
                              // callback used to provide).
                              lineTouchData: const LineTouchData(
                                enabled: false,
                                handleBuiltInTouches: false,
                              ),
                            ),
                          ),
                          Positioned(
                            left: leftAxisReservedSize,
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) => _openDayAtLocalX(
                                  details.localPosition.dx, contentWidth),
                              onLongPressStart: (details) => _openDayAtLocalX(
                                  details.localPosition.dx, contentWidth),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Per-day column labels: day of month on top (the
                    // first of a month in the short month form), day of
                    // cycle underneath — windowed, at their global x
                    // positions.
                    _DayLabelRow(
                      days: _days,
                      cellWidth: colW,
                      windowStart: winStart,
                      windowEnd: winEnd,
                    ),
                    const SizedBox(height: 8),
                    // The 1–6 low numbering, directly under the chart day
                    // columns. Full range: the row renders an empty slot per
                    // day and belongs to the in-progress evaluation-marks
                    // feature (lib/ui/cycle_marks.dart) — kept unwindowed on
                    // purpose to keep that file untouched; the cells are
                    // cheap and stay at their global positions.
                    EvaluationMarksRow(
                      dayCount: dayCount,
                      numbersByIndex: overlay.numbersByIndex,
                      onDayTap: _openDaySheet,
                    ),
                    const SizedBox(height: 4),
                    _SymbolRow(
                      days: _days,
                      cellWidth: colW,
                      windowStart: winStart,
                      windowEnd: winEnd,
                      peakIndexes: overlay.peakIndexes,
                      onDayTap: _openDaySheet,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One narrow cell per calendar day under the chart, aligned by the same
/// even day spacing as the chart: bleeding marker on top, the recorded
/// fertility sign (`Sᴱᵂ` style) below. Pure recording, no interpretation.
///
/// Only the window's cells are built: days outside
/// [windowStart]..[windowEnd] stay unbuilt, and the leading spacer keeps the
/// window cells at their global positions (cell i is centered at
/// (i + 0.5) * cellWidth, the same even spacing the full row used before).
final class _SymbolRow extends StatelessWidget {
  const _SymbolRow({
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
    required this.peakIndexes,
    required this.onDayTap,
  });

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  /// Day indexes carrying the mucus-peak mark (R6): they render the solid
  /// peak dot above the mucus glyph.
  final Set<int> peakIndexes;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: windowStart * cellWidth),
        // The cell key exposes the whole tappable per day index for the
        // widget tests (same convention as marksCell-$i above the chart).
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            width: cellWidth,
            child: InkWell(
              key: ValueKey('symbolCell-$i'),
              onTap: () => onDayTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _SymbolCell(
                  entry: days.byIndex[i],
                  isPeak: peakIndexes.contains(i),
                  peakDotKey: ValueKey('peakDot-$i'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _SymbolCell extends StatelessWidget {
  const _SymbolCell({
    required this.entry,
    this.isPeak = false,
    this.peakDotKey,
  });

  final DailyEntry? entry;

  /// Whether this day carries the mucus-peak mark (R6: solid dot above
  /// the mucus glyph).
  final bool isPeak;

  /// The test-visible key of the peak dot (null when the day is not the
  /// peak, so no keyed widget exists there).
  final Key? peakDotKey;

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return const SizedBox(height: 38);
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
        // Mucus-peak slot (R6, classic NER position): a SOLID dot in the
        // mucus color family directly ABOVE the mucus glyph. The slot is
        // reserved in every cell (same fixed-slot trick as the fertility
        // sign below) so the bleeding/mucus/cervix lines stay aligned
        // across the row regardless of which day is the peak.
        // TODO(user-review): the peak dot renders only on days WITH a
        // recorded entry — an entirely untracked day renders an empty
        // symbol cell (the row shows recorded observations only), so a
        // peak mark on an untracked day has no dot to render.
        SizedBox(
          height: 10,
          child: isPeak
              ? Center(
                  child: Container(
                    key: peakDotKey,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
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
        const SizedBox(height: 2),
        // Muttermund position glyph (third line). Raw observation display
        // only, never a fertility conclusion (ADR-0001); the letters are
        // the German vocabulary's initial letters — see the
        // TODO(user-review) in cervix.dart. Neutral on-surface ink: no
        // scheme hue is claimed, so the glyph cannot be confused with the
        // temperature/bleeding/mucus/baseline signal colors.
        if (entry!.cervixPosition != null)
          SizedBox(
            height: 10,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                cervixPositionSymbol(entry!.cervixPosition!),
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 10),
      ],
    );
  }
}

/// The localized short month name for [date]'s calendar month, in the same
/// abbreviated month form intl's date formats spell (en "Jan" / de "Jan." —
/// with the German trailing period, like the old DateFormat.MMMd labels).
/// The plain DateFormat.MMM constant would NOT do: it resolves to the
/// STANDALONE abbreviated months (de "Jan", no period) via the CLDR
/// availableFormats table, so the label is read from the locale's month
/// symbol set directly.
String _shortMonthLabel(DateTime date, String locale) =>
    DateFormat('d', locale).dateSymbols.SHORTMONTHS[date.month - 1];

/// Per-day column labels under the chart: every day column shows its day
/// of month ("14.") on top and its day of cycle (1, 2, 3 …, counted from
/// the cycle start in _ChartDays) underneath. On the FIRST day of a
/// calendar month the day-of-month label is REPLACED by the localized
/// short month form (de "Jan." / en "Jan") — the month home the otherwise
/// bare day numbers need. The rule is CALENDAR-based, not cycle-based:
/// a cycle start mid-month keeps its plain day number (owner decision).
/// Mirrors _SymbolRow's windowed
/// layout: only the window's cells are built, and the leading spacer keeps
/// them at their global x positions.
final class _DayLabelRow extends StatelessWidget {
  const _DayLabelRow({
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
  });

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: windowStart * cellWidth),
        // The cell key exposes the whole label column per day index for the
        // widget tests (same convention as symbolCell-$i in _SymbolRow).
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('dayLabel-$i'),
            width: cellWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Day of month — only the FIRST day of a calendar month
                // carries the month, so the form is scannable without
                // crowding every narrow column. FittedBox squeezes even
                // the German "Jan." into the minimum usable column width.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    days.dayAt(i).day == 1
                        ? _shortMonthLabel(days.dayAt(i), locale)
                        : '${days.dayAt(i).day}.',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                // Day of cycle: subtler than the 1–6 numbering (that one
                // is an evaluation artifact in the primary color).
                Text(
                  '${days.cycleDayByIndex[i]}',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
          // R6: the peak renders as a SOLID dot above the mucus glyph in
          // the symbol row — the old curve-ring glyph is gone.
          shape: _LegendShape.dot,
        ),
        _LegendDot(
          color: scheme.primary,
          label: AppLocalizations.of(context).zyklusLegendCircledHigher,
          shape: _LegendShape.circledDot,
        ),
        _LegendDot(
          color: scheme.primary,
          label: AppLocalizations.of(context).zyklusLegendArrowHigher,
          shape: _LegendShape.arrowUp,
        ),
        _LegendDot(
          color: scheme.onSurface,
          label: AppLocalizations.of(context).zyklusLegendCervix,
          shape: _LegendShape.cervix,
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

enum _LegendShape { dot, ring, text, circledDot, arrowUp, line, cervix }

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
      // Sample Muttermund glyph: the "medium" letter, exactly how a
      // recorded cervix day renders in the symbol row above.
      _LegendShape.cervix => Text(
          cervixPositionSymbol(CervixPosition.medium),
          style: TextStyle(fontSize: 10, color: color),
        ),
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

String _formatHalfDegree(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

double _floorToHalf(double v) => (v * 2).floorToDouble() / 2;

double _ceilToHalf(double v) => (v * 2).ceilToDouble() / 2;
