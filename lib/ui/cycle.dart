// Zyklus screen: the recorded temperature curve plus, paper-style, the
// day/cycle header line ABOVE it and one recording row per signal BELOW it
// (bleeding, mucus, cervix, sex, pain, measurement time — pure recording,
// no interpretation), plus the COMPUTED evaluation overlay (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks, the app
// derives the rest for DISPLAY ONLY — circled higher measurements (every
// candidate strictly after the peak day), arrow-up glyphs for candidates at
// or before the peak day or with the peak unset (decided PER CANDIDATE by
// the domain, R4), the solid peak dot ABOVE the mucus entry in the mucus
// row (the peak never touches the curve; EVERY placed peak renders, driven
// from the marks stream), the 1–6 low numbering, the baseline SEGMENT from
// low #6 to the last marked candidate (R10) and the user-placed SUZ bars
// (sicher unfruchtbare Zeit; ONLY user-placed marks render — the computed
// suzBegins drives the sheet's suggestion instead).
// lib/ui/cycle_marks.dart over evaluateCycles. No derived artifact is
// persisted; the SUZ arithmetic stays domain-only and a manual SUZ mark
// never alters it (see lib/domain/evaluation.dart).
//
// Tapping a chart day or a signal-row cell opens the day's mark-entry
// bottom sheet (lib/ui/cycle_mark_sheet.dart): edit day (jumps to the
// Tagebuch form with that date pre-selected, via selectedDateProvider +
// tabIndexProvider), the contextual mark toggles and the computed info
// line.
//
// The chart block renders a VIEWPORT-LIMITED WINDOW of days: day columns
// keep at least a minimum usable width (see _CycleChartState's
// minDayColumnWidth), so a long
// recorded range is not squeezed onto one screen — the whole block (header,
// curve, per-signal rows, marks row) scrolls horizontally as one
// unit, and a jump-to-date affordance moves the window onto a picked
// calendar day. Data outside the window is not built: the curve carries
// only the window's points (at their global x positions, so windows slide
// seamlessly) and the header/rows build only the window's cells.
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
import 'cycle_help_sheet.dart';
import 'cycle_mark_sheet.dart';
import 'cycle_marks.dart';
import 'cycle_summary.dart';
import 'mucus_symbol.dart';

class ZyklusScreen extends ConsumerWidget {
  const ZyklusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(dailyEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCycle),
        actions: [
          // The symbol glossary: the on-screen legend moved into this
          // bottom sheet, opened from the AppBar's info action.
          IconButton(
            key: const ValueKey('cycleHelpAction'),
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.cycleHelpShow,
            onPressed: () => showCycleHelpSheet(context),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text(l10n.loadFailed)),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.cycleNoData),
              ),
            );
          }
          // The evaluation table's input, like the chart overlay's: the
          // entries plus the user-placed marks, evaluated at render time
          // (ADR-0001). Watching the marks stream here makes a mark change
          // rebuild the whole screen — the table recomputes, nothing is
          // persisted.
          final marks = ref.watch(marksProvider).valueOrNull ??
              const <CycleMark>[];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CycleChart(entries: entries),
              const SizedBox(height: 12),
              // The paper's bottom summary: the evaluation table, one row
              // per attribute, one column per cycle group.
              CycleSummaryTable(
                evaluations: evaluateCycles(entries, marks),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.cycleArithmeticNote,
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
    cycleStartDates = {
      // Only groups that START at a menstruation onset are cycle
      // boundaries; the leading group (predating the first recorded
      // onset) is not.
      for (final g in groups)
        if (g.startsAtMenstruation) DateOnly.normalize(g.startDate),
    };
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

  /// The recorded dates on which a cycle group starts at a menstruation
  /// onset (startsAtMenstruation) — the cycle separators. Never contains
  /// the leading group's start (it predates the first recorded onset).
  late final Set<DateTime> cycleStartDates;

  DateTime dayAt(int index) => DateOnly.addDays(firstDay, index);

  /// Whether day [index] opens a new cycle (a menstruation-level bleeding
  /// onset starts its group there — the shared "is cycle boundary"
  /// predicate driving the card's thick separator lines). The very first
  /// recorded day is never a boundary: there is no line at the recorded
  /// range's left edge (a leading pre-onset group is not an onset group
  /// either). Untracked gap days before an onset do not hide the boundary:
  /// the predicate matches the ONSET's calendar date wherever it falls.
  bool isCycleBoundary(int index) =>
      index > 0 && cycleStartDates.contains(dayAt(index));
}

/// fl_chart line chart over all measured days plus a per-day symbol row.
///
/// The x axis is a plain day index over the recorded range, half a column
/// SHIFTED (minX −0.5 .. maxX dayCount − 0.5) so day i's dot lands exactly
/// on its day column's center — the column geometry the label, marks and
/// symbol rows share: calendar gaps (days without any measurement) stay
/// honest as distance, not compressed.
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
  /// day-header labels and the row glyphs would overlap, so a
  /// recorded range longer than one screen scrolls instead of shrinking
  /// further — the day count shown at once derives from the actual layout
  /// width, never from a hard-coded number.
  static const double minDayColumnWidth = 24;

  /// The y-axis title strip the chart reserves on its left edge (fl_chart's
  /// leftTitles reservation, mirrored in the chart config below). Every
  /// aligned row (day labels, marks, symbols) leads with a strip of this
  /// width too, so its day cells line up with the curve's columns; the tap
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

  /// The one-time initial auto-scroll: on the first data frame of the
  /// chart's lifetime the viewport jumps (instantly, no animation) to the
  /// maximum scroll extent so the MOST RECENT recorded days fill the
  /// window — the newest days sit at the content's right edge. A later
  /// entries re-emit (e.g. a diary save while the tab is mounted) must
  /// never re-jump: the user's scrolled position survives.
  bool _didInitialAutoScroll = false;

  /// Whether an initial-auto-scroll attempt is already scheduled and has
  /// not run yet (keeps initState + didUpdateWidget from stacking
  /// duplicate post-frame callbacks). A skipped attempt — no scroll client
  /// yet — unsets this again, so the next data frame can retry.
  bool _initialAutoScrollScheduled = false;

  /// Schedules the one-time initial auto-scroll (see
  /// [_didInitialAutoScroll]). Runs post-frame so the scroll view is laid
  /// out (hasClients, maxScrollExtent) when the jump happens; the jump goes
  /// through the controller, whose scroll listener re-windows to the last
  /// visible days — no window math here.
  void _scheduleInitialAutoScroll() {
    if (_didInitialAutoScroll || _initialAutoScrollScheduled) return;
    if (widget.entries.isEmpty) return; // no data frame yet — nothing to show
    _initialAutoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAutoScrollScheduled = false;
      if (_didInitialAutoScroll || !mounted || !_scrollController.hasClients) {
        // No client yet (first frame not laid out): the next data frame
        // retries. Once an attempt ran, the flag is final — a later
        // entries re-emit never re-jumps.
        return;
      }
      _didInitialAutoScroll = true;
      // A short range fits the viewport: max extent 0, nothing to jump.
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollController.jumpTo(max);
    });
  }

  @override
  void initState() {
    super.initState();
    _days = _ChartDays(widget.entries);
    _scrollController.addListener(_onScrolled);
    // Data may already be present at mount time: schedule the one-time
    // initial auto-scroll for the end of this frame.
    _scheduleInitialAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _CycleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live entry write re-emits the entries stream while this state is
    // alive: recompute the day mapping so a changed range re-windows
    // instead of rendering stale data.
    if (!identical(oldWidget.entries, widget.entries)) {
      _days = _ChartDays(widget.entries);
      // Only the FIRST data frame (an initial auto-scroll still pending)
      // may trigger the jump here; once it ran, a later re-emit never
      // re-jumps and the user's position survives.
      _scheduleInitialAutoScroll();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrolled);
    _scrollController.dispose();
    super.dispose();
  }

  void _openDaySheet(int index) {
    // Tapping the curve, the marks row or a signal-row cell opens the
    // day's mark-entry sheet; the form jump ("edit day") lives inside the
    // sheet.
    showCycleDaySheet(context, day: _days.dayAt(index));
  }

  /// The day-index window to build for the current scroll offset: every
  /// column that is at least partially on screen, plus the one-day margin
  /// of [_windowStart]/[_windowEnd]. The scroll content leads with the
  /// y-axis strip: day cell i spans
  /// [leftAxisReservedSize + i * colW, leftAxisReservedSize + (i + 1) * colW),
  /// so the strip is subtracted at BOTH edges before the offset is mapped
  /// onto the column grid — the visible-column count is strip-aware, not
  /// the bare viewport count.
  (int, int) _windowFor(int dayCount) {
    final viewport = _viewportWidth ?? 0;
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final firstVisible =
        ((offset - leftAxisReservedSize) / colW).floor().clamp(0, dayCount - 1);
    // The last column with any pixel on screen: day i's column START is
    // left of the viewport's right edge — i.e. i < (offset + viewport −
    // strip) / colW, so the largest such i is one below that quotient's
    // ceil (a quotient landing exactly on an integer excludes the column
    // starting exactly at the right edge — nothing of it is visible).
    final lastVisible =
        (((offset + viewport - leftAxisReservedSize) / colW).ceil() - 1)
            .clamp(firstVisible, dayCount - 1);
    return (
      math.max(0, firstVisible - 1),
      math.min(dayCount - 1, lastVisible + 1),
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
  /// the y-axis strip); the chart's x domain is half a column SHIFTED
  /// (minX −0.5 .. maxX dayCount − 0.5), so the tap's local x maps linearly
  /// onto a fractional day index d whose integer parts are the columns'
  /// centers: day i's column spans d in [i − 0.5, i + 0.5). The nearest
  /// day column wins, exactly like the row cells underneath.
  void _openDayAtLocalX(double localX, double contentWidth) {
    final plotWidth = contentWidth - leftAxisReservedSize;
    final t = (localX / plotWidth).clamp(0.0, 1.0);
    final d = -0.5 + t * _days.dayCount;
    final index = d.round().clamp(0, _days.dayCount - 1);
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
    // Center the picked day's column: its center sits at
    // leftAxisReservedSize + (index + 0.5) * colW in the scroll content,
    // and centering places it at the viewport's middle.
    final target = (leftAxisReservedSize + (index + 0.5) * colW - viewport / 2)
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
      marks: marks,
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
        l10n.cycleNoData,
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

    // The chart plot's height adapts to the y-span (the paper's sheet gives
    // wider temperature ranges more room): a comfortable ~3 °C span fits
    // the 260 px base height; beyond that every extra degree adds 80 px,
    // capped so extreme ranges cannot stretch the sheet endlessly. The
    // y bounds logic itself stays untouched.
    // TODO(user-review): the growth rate (80 px/°C) and the 400 px cap are
    // tuned display heuristics, not rules from the cheat sheet.
    const chartBaseHeight = 260.0;
    const chartHeightCap = 400.0;
    const comfortableYSpan = 3.0;
    final chartHeight = (chartBaseHeight +
            math.max(0.0, yMax - yMin - comfortableYSpan) * 80.0)
        .clamp(chartBaseHeight, chartHeightCap);

    // Interrupted (excluded) TEMPERATURES read lighter: the scheme color at
    // a fraction of the alpha. The dark scheme's primary is a bright color,
    // so the dimmed tint still keeps darkness-readable contrast (asserted
    // by the dark-mode chart tests).
    final temperatureColor = Theme.of(context).colorScheme.primary;
    final interruptedColor = temperatureColor.withValues(alpha: 0.4);
    // The evaluation-artifact accent is theme-derived too (secondary: the
    // one scheme color the temperature/bleeding/mucus rendering does not
    // use — see the help sheet's glossary in cycle_help_sheet.dart). It
    // feeds the dashed R10 baseline segment bars
    // (not a full-width line) AND the user-placed SUZ bars — both are
    // derived evaluation artifacts, so they share the family color; the
    // segment is dashed-horizontal, the SUZ bar solid-vertical.
    final evaluationColor = Theme.of(context).colorScheme.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        _viewportWidth = viewport;
        final dayCount = _days.dayCount;
        // Useful day columns: at most as many days as fit the viewport at
        // the minimum usable width; a longer range keeps that width and
        // scrolls horizontally instead of squeezing. The viewport hosts the
        // y-axis strip first, then the day columns — a column is "usable"
        // when the columns plus the strip still fit.
        final overflow =
            leftAxisReservedSize + dayCount * minDayColumnWidth > viewport;
        final colW = overflow
            ? minDayColumnWidth
            : (viewport - leftAxisReservedSize) / dayCount;
        _columnWidth = colW;
        // The scroll content: the strip plus one column per day. In the
        // fitting case that is exactly the viewport (nothing scrolls); the
        // explicit viewport keeps the no-scroll case free of floating-point
        // slack that a recomputed sum could introduce.
        final contentWidth =
            overflow ? leftAxisReservedSize + dayCount * colW : viewport;
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
        // The chart's x domain spans one column per day, half a column
        // SHIFTED so day i's dot lands on its column center: the domain
        // runs from minX −0.5 to maxX dayCount − 0.5 (day i's column is
        // [i − 0.5, i + 0.5] in domain units). The ±0.5 offsets below and
        // in the baseline/SUZ drawing therefore mean exactly "column
        // bounds"; the range annotations clamp to those bounds, so edge
        // columns keep their full half-day band.
        final lastX = (dayCount - 0.5).toDouble();
        final weekendBands = <VerticalRangeAnnotation>[];
        for (var i = winStart; i <= winEnd; i++) {
          if (!DateOnly.isWeekend(_days.dayAt(i))) continue;
          // Half a day left and right of the day's x position, clipped to
          // the plot bounds (a first/last-day weekend keeps its full
          // column width instead of being cut back to the day index).
          var x1 = (i - 0.5).clamp(-0.5, lastX).toDouble();
          var x2 = (i + 0.5).clamp(-0.5, lastX).toDouble();
          weekendBands.add(
            VerticalRangeAnnotation(x1: x1, x2: x2, color: weekendBandColor),
          );
        }

        // The domain bounds per the alignment note above: a single
        // recorded day keeps the −0.5..0.5 one-column window for free
        // (fl_chart requires minX < maxX, satisfied for every dayCount ≥ 1).
        final maxX = (dayCount - 0.5).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const ValueKey('calendarJumpButton'),
                icon: const Icon(Icons.date_range),
                tooltip: l10n.cycleJumpToDate,
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
                    // The day/cycle header ABOVE the curve (the paper's
                    // header row): day of month + day of cycle per column,
                    // with the two column prototypes in the corner slot.
                    _DayHeaderRow(
                      days: _days,
                      cellWidth: colW,
                      windowStart: winStart,
                      windowEnd: winEnd,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: chartHeight,
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
                                // clamped to the plot bounds (mirror of
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
                                              -0.5, segment.startIndex - 0.5),
                                          segment.value),
                                      FlSpot(
                                          math.min(
                                              lastX, segment.endIndex + 0.5),
                                          segment.value),
                                    ],
                                    isCurved: false,
                                    barWidth: 1,
                                    color: evaluationColor,
                                    dashArray: const [6, 4],
                                    dotData: const FlDotData(show: false),
                                  ),
                                // The user-placed SUZ marks: a VERTICAL
                                // bar spanning the plot height at the SUZ
                                // day's column (column START x − 0.5 for
                                // suzMorning, column MIDDLE x for
                                // suzEvening) plus a right-pointing arrow
                                // whose base starts at the bar. Only
                                // user-placed marks render — the computed
                                // suzBegins drives the sheet's
                                // suggestion instead, never the chart.
                                // The bar rides inside fl_chart as a
                                // two-spot bar; only the small arrow glyph
                                // is hand-painted (ADR-0004 fallback).
                                for (final suz in overlay.suzMarks) ...[
                                  LineChartBarData(
                                    spots: [
                                      // The bar: column START (x − 0.5) for
                                      // suzMorning, column MIDDLE (x) for
                                      // suzEvening, clamped to the plot
                                      // bounds like the weekend bands (the
                                      // edge columns keep their full width).
                                      FlSpot(suz.barX.clamp(-0.5, lastX), yMin),
                                      FlSpot(suz.barX.clamp(-0.5, lastX), yMax),
                                    ],
                                    isCurved: false,
                                    barWidth: 2,
                                    color: evaluationColor,
                                    dotData: const FlDotData(show: false),
                                  ),
                                  // The arrow: a single-spot dot bar whose
                                  // painter draws the glyph — base at the
                                  // bar, anchored at the cycle's baseline
                                  // value when one exists, else the plot
                                  // middle (TODO(user-review): the
                                  // arrow's vertical anchor is an
                                  // owner-eyeball rendering detail).
                                  LineChartBarData(
                                    spots: [
                                      FlSpot(suz.barX.clamp(-0.5, lastX),
                                          suz.arrowValueY ?? (yMin + yMax) / 2),
                                    ],
                                    color: Colors.transparent,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter: (_, __, ___, ____) =>
                                          SuzArrowDotPainter(
                                              color: evaluationColor),
                                    ),
                                  ),
                                ],
                              ],
                              minX: -0.5,
                              maxX: maxX,
                              minY: yMin,
                              maxY: yMax,
                              rangeAnnotations: RangeAnnotations(
                                verticalRangeAnnotations: weekendBands,
                              ),
                              // The vertical day lines: hairlines at
                              // interval 1 over the half-column-shifted
                              // domain with the baseline AT the domain
                              // start (−0.5), so the lines land on the
                              // column BOUNDARIES (0.5, 1.5, …) behind
                              // curve and dots — the paper's day columns
                              // through the whole card (the rows carry
                              // matching cell borders, see the row
                              // widgets below).
                              gridData: FlGridData(
                                drawVerticalLine: true,
                                verticalInterval: 1,
                                getDrawingVerticalLine: (_) => FlLine(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.12),
                                  strokeWidth: 0.5,
                                ),
                              ),
                              baselineX: -0.5,
                              // The cycle-start separators: a THICK solid
                              // line at x = nextCycleStart − 0.5 (the
                              // boundary day's column start), one per
                              // boundary inside the window, derived from
                              // the shared cycle-boundary predicate (the
                              // same one the row cells' thick borders
                              // use). No line before the first recorded
                              // onset (the leading group is not a
                              // boundary), and a boundary after untracked
                              // gap days is drawn across the gap.
                              extraLinesData: ExtraLinesData(
                                verticalLines: [
                                  for (var i = winStart; i <= winEnd; i++)
                                    if (_days.isCycleBoundary(i))
                                      VerticalLine(
                                        x: i - 0.5,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        strokeWidth: 2,
                                      ),
                                ],
                              ),
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
                    // The 1–6 low numbering, directly under the chart day
                    // columns. Full range: the row renders an empty slot per
                    // day and belongs to the in-progress evaluation-marks
                    // feature (lib/ui/cycle_marks.dart) — kept unwindowed on
                    // purpose to keep that feature's numbering semantics
                    // untouched; the cells are cheap and stay at their
                    // global positions (same leading-strip alignment as the
                    // rows above).
                    EvaluationMarksRow(
                      dayCount: dayCount,
                      leadingStrip: leftAxisReservedSize,
                      cellWidth: colW,
                      numbersByIndex: overlay.numbersByIndex,
                      onDayTap: _openDaySheet,
                      isCycleBoundary: _days.isCycleBoundary,
                    ),
                    const SizedBox(height: 4),
                    // One recording row per signal: bleeding, mucus,
                    // cervix, sex, pain, measurement time — with the
                    // solid peak-dot slot reserved in the mucus row.
                    _SignalRows(
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

/// One recording row per signal BELOW the chart (the paper's rows):
/// bleeding, mucus (with the reserved solid peak-dot slot above the glyph,
/// R6), cervix, sex, pain and measurement time — pure recording, no
/// interpretation. Every row renders for every day (auto-hide of unused
/// rows is deferred), aligned by the same even day spacing as the chart:
/// a leading 44 px corner slot (the y-axis strip's home) carries a sample
/// glyph plus the localized row name (tooltip on long-press + semantics),
/// and the windowed day cells sit at the curve's global column positions
/// (cell i is centered at the strip + (i + 0.5) * cellWidth — exactly
/// where the chart draws day i's dot). Tapping a cell opens the day's
/// mark-entry sheet and the cell keys expose the row/cell pairs for the
/// widget tests (bleedingCell-$i, mucusCell-$i, …).
final class _SignalRows extends StatelessWidget {
  const _SignalRows({
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
    final rows = [
      for (final kind in _SignalKind.values)
        Padding(
          padding: EdgeInsets.only(top: kind == _SignalKind.values.first ? 0 : 2),
          child: _SignalRow(
            kind: kind,
            days: days,
            cellWidth: cellWidth,
            windowStart: windowStart,
            windowEnd: windowEnd,
            peakIndexes: peakIndexes,
            onDayTap: onDayTap,
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// The six recording signals, in the order the rows render (paper order:
/// bleeding/top .. measurement time/bottom).
enum _SignalKind { bleeding, mucus, cervix, sex, pain, time }

/// Test-visible key prefix of a row's day cells: `bleedingCell-3`,
/// `mucusCell-3`, …
String _signalKeyPrefix(_SignalKind kind) => switch (kind) {
      _SignalKind.bleeding => 'bleedingCell',
      _SignalKind.mucus => 'mucusCell',
      _SignalKind.cervix => 'cervixCell',
      _SignalKind.sex => 'sexCell',
      _SignalKind.pain => 'painCell',
      _SignalKind.time => 'timeCell',
    };

/// Test-visible key prefix of a row's 44 px corner slot: `bleedingCorner`,
/// `mucusCorner`, …
String _signalCornerKeyPrefix(_SignalKind kind) => switch (kind) {
      _SignalKind.bleeding => 'bleedingCorner',
      _SignalKind.mucus => 'mucusCorner',
      _SignalKind.cervix => 'cervixCorner',
      _SignalKind.sex => 'sexCorner',
      _SignalKind.pain => 'painCorner',
      _SignalKind.time => 'timeCorner',
    };

/// The localized row name for a signal (the corner tooltip/semantics
/// label).
// TODO(user-review): the row-name wording is a first draft mirroring the
// entry form's vocabulary; the experts may want different names.
String _signalRowName(_SignalKind kind, AppLocalizations l10n) =>
    switch (kind) {
      _SignalKind.bleeding => l10n.cycleRowBleeding,
      _SignalKind.mucus => l10n.cycleRowMucus,
      _SignalKind.cervix => l10n.cycleRowCervix,
      _SignalKind.sex => l10n.cycleRowSex,
      _SignalKind.pain => l10n.cycleRowPain,
      _SignalKind.time => l10n.cycleRowMeasurementTime,
    };

/// The narrowest day column that still carries the measurement-time TEXT
/// ("06:30"). Below it (at the 24 px minimum the cells are empty) the
/// recorded time stays in the day sheet — no data/model change.
// TODO(user-review): the threshold is a tuned display heuristic, not a
// rule from the cheat sheet.
const double _timeCellMinColumnWidth = 32;

/// One signal's recording row: a 44 px corner slot (sample glyph +
/// localized row name) followed by the window's day cells.
final class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.kind,
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
    required this.peakIndexes,
    required this.onDayTap,
  });

  final _SignalKind kind;

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  /// Day indexes carrying the mucus-peak mark (R6): they render the solid
  /// peak dot above the mucus glyph. Only read by the mucus row.
  final Set<int> peakIndexes;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rowName = _signalRowName(kind, l10n);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The corner slot: a sample glyph of the signal plus the row name
        // (tooltip on long-press, semantics label for screen readers).
        SizedBox(
          key: ValueKey(_signalCornerKeyPrefix(kind)),
          width: _CycleChartState.leftAxisReservedSize,
          child: Align(
            alignment: Alignment.center,
            child: Semantics(
              label: rowName,
              child: Tooltip(
                message: rowName,
                child: _cornerSample(context),
              ),
            ),
          ),
        ),
        // The window spacer keeps the cells at their global column
        // positions (mirrors the header row's spacer).
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('${_signalKeyPrefix(kind)}-$i'),
            width: cellWidth,
            child: InkWell(
              onTap: () => onDayTap(i),
              // The day-cell separator: hairline matching the chart's
              // vertical day grid lines, thickened to the solid
              // cycle-start line when the NEXT day opens a cycle (the
              // separator sits on this cell's right edge).
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: cycleDayCellBorderSide(context,
                        isCycleBoundary: days.isCycleBoundary(i + 1)),
                  ),
                ),
                child: _cell(context, i),
              ),
            ),
          ),
      ],
    );
  }

  /// The corner slot's sample glyph.
  // TODO(user-review): the sample glyphs (blob, S, position letter, X, B/M,
  // clock) are ad-hoc column samples mirroring the row's glyphs; the
  // NER cheat sheet defines samples only for some of them.
  Widget _cornerSample(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (kind) {
      _SignalKind.bleeding => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.error,
            border: Border.all(width: 1.5, color: scheme.error),
          ),
        ),
      // Sample observation: S with the EW quality qualifier, exactly how a
      // recorded mucus day renders in the row's cells.
      _SignalKind.mucus => MucusSymbolText(
          display: mucusDisplay(sign: MucusSign.s, quality: MucusQuality.ew),
          fontSize: 10,
          color: scheme.tertiary,
        ),
      // Sample Muttermund glyph: the "medium" letter, exactly how a
      // recorded cervix day renders in the row's cells.
      _SignalKind.cervix => Text(
          cervixPositionSymbol(CervixPosition.medium),
          style: TextStyle(fontSize: 10, color: scheme.onSurface),
        ),
      _SignalKind.sex => Text(
          'X',
          style: TextStyle(fontSize: 10, color: scheme.onSurface),
        ),
      _SignalKind.pain => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('B', style: TextStyle(fontSize: 10, color: scheme.onSurface)),
            const SizedBox(width: 1),
            Text('M', style: TextStyle(fontSize: 10, color: scheme.onSurface)),
          ],
        ),
      // The corner keeps a clock icon sample; the per-day cells show the
      // recorded time as text (wide columns) or nothing (narrow ones).
      _SignalKind.time => Icon(Icons.schedule, size: 12, color: scheme.onSurface),
    };
  }

  /// The fixed height each row's day cell occupies — keeps a row's empty
  /// cells at the recorded cells' height.
  double get _cellHeight => switch (kind) {
        // The mucus row reserves the peak-dot slot ABOVE the glyph (R6):
        // dot slot 10 + gap 2 + glyph 12.
        _SignalKind.mucus => 24,
        _ => 12,
      };

  /// One day's cell content.
  Widget _cell(BuildContext context, int index) {
    final day = days.byIndex[index];
    return SizedBox(
      height: _cellHeight,
      child: Center(
        child: switch (kind) {
          _SignalKind.bleeding => _bleedingContent(context, day),
          _SignalKind.mucus => _mucusContent(context, index, day),
          _SignalKind.cervix => _cervixContent(context, day),
          _SignalKind.sex => _sexContent(context, day),
          _SignalKind.pain => _painContent(context, day),
          _SignalKind.time => _timeContent(context, day),
        },
      ),
    );
  }

  /// Bleeding: the graded-opacity circle convention shared with the diary
  /// day tiles — none draws the invisible circle, spotting the hollow
  /// ring, and light/medium/heavy fill the circle with the error color at
  /// 0.6/0.8/1.0.
  static Widget _bleedingContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final bleedingColor = Theme.of(context).colorScheme.error;
    final bleeding = day.bleeding;
    return Container(
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
    );
  }

  /// Mucus: the reserved solid peak-dot slot above the glyph (R6, classic
  /// NER position). The slot is reserved in every cell so the row keeps
  /// its rhythm regardless of which day is the peak.
  Widget _mucusContent(BuildContext context, int index, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 10,
          child: peakIndexes.contains(index)
              ? Center(
                  child: Container(
                    key: ValueKey('peakDot-$index'),
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
        SizedBox(
          height: 12,
          child: Align(
            alignment: Alignment.topCenter,
            child: MucusSymbolText(
              display: mucusDisplay(
                sign: day.mucusSign,
                quality: day.mucusQuality,
              ),
              fontSize: 9,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ),
      ],
    );
  }

  /// The tallest height the peak-dot slot can occupy so a day carries
  /// its dot above the glyph without shifting the row (mirrors the
  /// fixed-slot trick used before the per-signal rows).
  // (kept for reference in the class docs)

  /// Cervix: position letter first, firmness shorthand beside it; null
  /// renders an empty cell. The OPENING is deliberately not displayed
  /// (entry form only). Raw observation display only, never a fertility
  /// conclusion (ADR-0001); the letters are the German vocabulary's
  /// initial letters / the paper shorthand — see the TODO(user-review) in
  /// cervix.dart. Neutral on-surface ink: no scheme hue is claimed, so
  /// the glyphs cannot be confused with the temperature/bleeding/mucus/
  /// baseline signal colors.
  static Widget _cervixContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final List<String>? cervixLine =
        day.cervixPosition == null && day.cervixFirmness == null
            ? null
            : [
                if (day.cervixPosition case final position?)
                  cervixPositionSymbol(position),
                if (day.cervixFirmness case final firmness?)
                  cervixFirmnessSymbol(firmness),
              ];
    if (cervixLine == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cervixLine.length; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          Text(
            cervixLine[i],
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }

  /// Sex: one X glyph per RECORDED time slot — each set SexTiming bit
  /// draws its X at its third of the day column (start/middle/end), so
  /// multiple slots render multiple X marks side by side. The mask itself
  /// encodes whether sex happened (no bits = no X; "sex happened, time
  /// unknown" is deliberately not representable, DailyEntry.sexTimings).
  /// No collision with an exclusion marker: interrupted days render as
  /// LIGHTER CURVE POINTS, there is no exclusion letter on the chart.
  /// TODO(user-review): the X is the provisional glyph from the product
  /// wishlist, and the third-of-column placement is an ad-hoc geometry
  /// choice — experts may want a different mark/placement.
  static Widget _sexContent(BuildContext context, DailyEntry? day) {
    if (day == null || day.sexTimings == 0) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final timing in SexTiming.values)
          if (day.sexTimings & timing.bit != 0)
            Positioned.fill(
              child: Align(
                alignment: _sexTimingAlignment(timing),
                child: Text(
                  'X',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  /// Pain: the letter-coded pain options of the cheat sheet — B (Brust,
  /// breast tenderness) and M (Mittelschmerz) — each flag its own letter
  /// so a single flag stays legible alone. The UPPERCASE letters keep
  /// them distinguishable from the lowercase cervix letters in the row
  /// above; both rows share the same neutral on-surface ink (no scheme
  /// hue claimed).
  /// TODO(user-review): the letters mirror the vocabulary of the entry
  /// form ("Brustschmerzen (B)" / "Mittelschmerz (M)") — the same ad-hoc
  /// glyph caveat as the cervix letters applies.
  static Widget _painContent(BuildContext context, DailyEntry? day) {
    if (day == null || !(day.painBreast || day.painMittelschmerz)) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (day.painBreast)
          Text(
            'B',
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        if (day.painBreast && day.painMittelschmerz) const SizedBox(width: 1),
        if (day.painMittelschmerz)
          Text(
            'M',
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
      ],
    );
  }

  /// Measurement time: the localized HH:mm text of a recorded
  /// temperature-measurement time — rendered only when the day column is
  /// wide enough ([_timeCellMinColumnWidth]; at the 24 px minimum the
  /// column stays empty). measuredAtMinutes is normalized to exist only
  /// together with bbtC (the DailyEntry constructor drops a time without
  /// a temperature), so the text never claims a time for a
  /// temperature-free day. The per-day clock icon is gone — the icon
  /// lives only in the row's corner sample.
  Widget _timeContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final minutes = day.measuredAtMinutes;
    if (minutes == null) return const SizedBox.shrink();
    if (cellWidth < _timeCellMinColumnWidth) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final time = DateTime.utc(2000).add(Duration(minutes: minutes));
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        DateFormat.Hm(locale).format(time),
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Horizontal placement of a sex time slot's X glyph inside the day column:
/// each slot's X sits at the center of its third (1/6, 3/6, 5/6 of the
/// column width), expressed as an Alignment x of -2/3, 0, +2/3 — so one
/// recorded slot still shows WHERE in the day it happened, and several
/// slots never overlap.
Alignment _sexTimingAlignment(SexTiming timing) => switch (timing) {
      SexTiming.start => const Alignment(-2 / 3, 0),
      SexTiming.middle => Alignment.center,
      SexTiming.end => const Alignment(2 / 3, 0),
    };

/// The localized short month name for [date]'s calendar month, in the same
/// abbreviated month form intl's date formats spell (en "Jan" / de "Jan." —
/// with the German trailing period, like the old DateFormat.MMMd labels).
/// The plain DateFormat.MMM constant would NOT do: it resolves to the
/// STANDALONE abbreviated months (de "Jan", no period) via the CLDR
/// availableFormats table, so the label is read from the locale's month
/// symbol set directly.
String _shortMonthLabel(DateTime date, String locale) =>
    DateFormat('d', locale).dateSymbols.SHORTMONTHS[date.month - 1];

/// The day/cycle header line ABOVE the chart (the paper's header row):
/// every day column shows its day of month ("14.") on top and its day of
/// cycle (1, 2, 3 …, counted from the cycle start in _ChartDays)
/// underneath. On the FIRST day of a calendar month the day-of-month label
/// is REPLACED by the localized short month form (de "Jan." / en "Jan") —
/// the month home the otherwise bare day numbers need. The rule is
/// CALENDAR-based, not cycle-based: a cycle start mid-month keeps its
/// plain day number (owner decision). The leading 44 px corner slot (the
/// y-axis strip's home) shows the two column prototypes: a date sample
/// ("14.") and a cycle-day sample ("#5") so the columns read as a table.
/// TODO(user-review): the prototypes ("14.", "#5") are ad-hoc column
/// samples; the experts may want different header prototypes.
/// Mirrors _SignalRow's windowed layout: the corner slot carries the
/// leading strip and the window spacer puts the cells at their global
/// positions (cell i is centered at the strip + (i + 0.5) * cellWidth —
/// exactly where the chart draws day i's dot), and only the window's
/// cells are built.
final class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
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
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The corner slot: the two column prototypes with their tooltips
        // and semantics labels (the paper's header captions above the
        // sheet's day columns).
        SizedBox(
          key: const ValueKey('dayHeaderCorner'),
          width: _CycleChartState.leftAxisReservedSize,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _columnPrototype(
                prototype: '14.',
                label: l10n.cycleColumnDate,
              ),
              _columnPrototype(
                prototype: '#5',
                label: l10n.cycleColumnCycleDay,
              ),
            ],
          ),
        ),
        // The window spacer keeps the header cells at their global column
        // positions (mirrors the other rows' leading strip + window offset).
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        // The cell key exposes the whole label column per day index for the
        // widget tests (same convention as the signal-row cells below).
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('dayLabel-$i'),
            width: cellWidth,
            child: Container(
              // The day-cell separator, same as the signal rows below
              // (the vertical lines run through the whole card).
              decoration: BoxDecoration(
                border: Border(
                  right: cycleDayCellBorderSide(context,
                      isCycleBoundary: days.isCycleBoundary(i + 1)),
                ),
              ),
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
          ),
      ],
    );
  }

  /// One prototype cell in the header's corner slot: the sample glyph with
  /// its tooltip (long-press) and its semantics label.
  static Widget _columnPrototype({
    required String prototype,
    required String label,
  }) =>
      Semantics(
        label: label,
        child: Tooltip(
          message: label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                prototype,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      );
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
