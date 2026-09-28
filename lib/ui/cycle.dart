// Zyklus screen: the paper-style temperature curve with the day/cycle
// header above it and the per-day recording rows inside the top of the
// temperature block (bleeding, mucus with the reserved peak-dot slot, the
// Mittelschmerz letter M on its own row, sex); under the curve the 1–6
// numbering and the single below-chart strip (measurement time,
// disturbance letters, cervix, pain, day-note indicator). The COMPUTED
// evaluation overlay (Mode M, ADR-0001) draws the user's mucus-peak and
// first-higher marks' derived artifacts for DISPLAY ONLY — never persisted;
// it is derived in lib/domain/evaluation_overlay.dart over evaluateCycles
// and painted by lib/ui/cycle_marks.dart (the SUZ arithmetic stays
// domain-only; a manual SUZ mark never alters it).
//
// Tapping a chart day or a signal-row cell shows the day options in the
// NON-MODAL panel the screen owns (lib/ui/cycle_mark_sheet.dart,
// cycleDayPanelProvider); tapping another day retargets it in place.
//
// The chart renders a VIEWPORT-LIMITED WINDOW of days: day columns keep a
// minimum usable width (see _CycleChartState.minDayColumnWidth), so long
// recorded ranges scroll horizontally as one unit while a FROZEN LEFT RAIL
// (the paper sheet's fixed left margin) carries the header prototypes, the
// temperature scale and the rows' name glyphs. Data outside the window is
// not built; a jump-to-date affordance moves the window onto a picked day.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/cervix.dart';
import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/decimal_display.dart';
import '../domain/disturbances.dart';
import '../domain/evaluation.dart';
import '../domain/evaluation_overlay.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../domain/temperature_range.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'bleeding_symbol.dart';
import 'cycle_curve.dart';
import 'cycle_help_sheet.dart';
import 'cycle_mark_sheet.dart';
import 'cycle_marks.dart';
import 'mucus_symbol.dart';
import 'stream_error.dart';

class ZyklusScreen extends ConsumerWidget {
  const ZyklusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(dailyEntriesProvider);
    // The jump-to-date affordance sits in the AppBar actions; its callback
    // is registered by the chart state while mounted — cycleChartJumpProvider.
    final jumpToDate = ref.watch(cycleChartJumpProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCycle),
        actions: [
          if (jumpToDate != null)
            IconButton(
              key: const ValueKey('calendarJumpButton'),
              icon: const Icon(Icons.date_range),
              tooltip: l10n.cycleJumpToDate,
              onPressed: () => jumpToDate(context),
            ),
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
        error: (e, s) => StreamLoadError(
          scope: 'entries',
          onRetry: () => ref.invalidate(dailyEntriesProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.cycleNoData),
              ),
            );
          }
          // Unmasked so a failed marks stream surfaces in place of the
          // chart block; the panel below stays mounted regardless.
          final marksAsync = ref.watch(marksProvider);
          return _liveCycleList(context, ref, entries, marksAsync);
        },
      ),
    );
  }

  /// The live list of one recorded range — chart, day-options panel and
  /// evaluation note, computed from the shared derived pass. On a failed
  /// marks stream the chart block is replaced by the retry surface instead
  /// of painting an overlay over silently-empty data.
  Widget _liveCycleList(
    BuildContext context,
    WidgetRef ref,
    List<DailyEntry> entries,
    AsyncValue<List<CycleMark>> marksAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    final marks = marksAsync.valueOrNull ?? const <CycleMark>[];
    // This is the screen's ONLY marks watch — the whole screen rebuilds on
    // a mark change, the overlay recomputes from the shared derived pass.
    // The settings values are watched here because the chart takes them as
    // constructor data (no riverpod dependency of its own).
    final temperatureRange = ref.watch(temperatureRangeProvider);
    final derived = ref.watch(derivedCycleDataProvider);
    final observedCyclesOutsideApp = ref.watch(
      observedCyclesOutsideAppProvider,
    );
    final panelDay = ref.watch(cycleDayPanelProvider);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        marksAsync.when(
          loading: () => _CycleChart(
            entries: entries,
            marks: marks,
            evaluations: derived.evaluations,
            cycles: derived.cycles,
            range: temperatureRange,
            observedCyclesOutsideApp: observedCyclesOutsideApp,
          ),
          error: (e, s) => StreamLoadError(
            scope: 'marks',
            onRetry: () => ref.invalidate(marksProvider),
          ),
          data: (markers) => _CycleChart(
            entries: entries,
            marks: markers,
            evaluations: derived.evaluations,
            cycles: derived.cycles,
            range: temperatureRange,
            observedCyclesOutsideApp: observedCyclesOutsideApp,
          ),
        ),
        const SizedBox(height: 12),
        if (panelDay != null)
          CycleDayPanel(
            key: const ValueKey('cycleDayPanel'),
            day: panelDay,
            onClose: () =>
                ref.read(cycleDayPanelProvider.notifier).state = null,
          ),
        if (panelDay != null) const SizedBox(height: 12),
        Text(
          l10n.cycleArithmeticNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The chart data view model for one recorded range: day index -> signal.
final class _ChartDays {
  _ChartDays(
    List<DailyEntry> entries,
    List<CycleMark> marks,
    List<Cycle> cycles,
    this.observedCyclesOutsideApp,
  ) {
    final sorted = [...entries]
      ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));
    firstDay = DateOnly.normalize(sorted.first.date);
    dayCount =
        DateOnly.daysBetween(DateOnly.normalize(sorted.last.date), firstDay) +
        1;
    for (final e in sorted) {
      byIndex[DateOnly.daysBetween(DateOnly.normalize(e.date), firstDay)] = e;
    }
    ignoredDayIndexes = {
      for (final mark in marks)
        if (mark.type == CycleMarkTypes.ignoreTemperature)
          DateOnly.daysBetween(DateOnly.normalize(mark.date), firstDay),
    };
    // Cycle mapping over the whole index range, from the cycle groups the
    // screen shares with Tagebuch/Statistik (the derived pass): every day
    // counts into the cycle with the LATEST group start on or before it, so
    // untracked gap days keep counting from the last start. A group opens
    // at a user-placed cycleStart mark, anchored at the MARK's own date.
    final starts = [for (final g in cycles) DateOnly.normalize(g.startDate)];
    cycleStartDates = {
      for (final g in cycles)
        if (g.startsAtMenstruation) DateOnly.normalize(g.startDate),
    };
    // Ordinals at the mark-opened boundaries via the shared ordinal rule
    // (shifted by the outside-app setting).
    var markOpenedIndex = 0;
    cycleOrdinalByStart = {
      for (final g in cycles)
        if (g.startsAtMenstruation)
          DateOnly.normalize(g.startDate): cycleOrdinalNumber(
            markOpenedIndex++,
            observedCyclesOutsideApp,
          ),
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

  /// The chart day indexes whose temperature is IGNORED, from the
  /// `ignoreTemperature` MARKS — the marks, not the raw disturbance mask,
  /// are the curve's rendering key.
  late final Set<int> ignoredDayIndexes;

  /// UTC-midnight of the first recorded day (day index 0).
  late final DateTime firstDay;

  /// Index range length (>= number of recorded days; gaps included).
  late final int dayCount;

  final Map<int, DailyEntry> byIndex = {};

  /// Day of cycle (1, 2, 3 …) per day index, counted from the start of the
  /// cycle group the day belongs to.
  final Map<int, int> cycleDayByIndex = {};

  /// The recorded dates at which a cycle group opens at a user-placed
  /// cycleStart mark (startsAtMenstruation) — the cycle separators. Never
  /// contains the leading group's start (it predates the first mark).
  late final Set<DateTime> cycleStartDates;

  /// The observed-cycles count the ordinals shift by (the settings value
  /// the screen watches; see [cycleOrdinalNumber]).
  final int observedCyclesOutsideApp;

  /// The "Zyklus N" ordinal for every mark-opened cycle start (the same
  /// dates as [cycleStartDates], keyed by their UTC-midnight date).
  late final Map<DateTime, int> cycleOrdinalByStart;

  DateTime dayAt(int index) => DateOnly.addDays(firstDay, index);

  /// Whether day [index] opens a new cycle (the cycleStart mark's own date
  /// — the shared boundary predicate for the thick separator lines). A mark
  /// on the FIRST tracked day is also a boundary (its separator is the
  /// first cells' thick LEFT border; the in-plot line starts at index 1),
  /// and a mark on an untracked gap day keeps its own date as the boundary.
  bool isCycleBoundary(int index) => cycleStartDates.contains(dayAt(index));
}

/// fl_chart line chart over all measured days plus a per-day symbol row.
///
/// X is a plain day index over the recorded range, half a column SHIFTED
/// (minX −0.5 .. maxX − 0.5) so day i's dot lands on its column's center —
/// calendar gaps stay honest as distance. Y bounds are the settings-selected
/// temperature range, a fixed scale: out-of-range values clip at the
/// boundary (cycle_curve.dart), an outlier never stretches it.
final class _CycleChart extends StatefulWidget {
  const _CycleChart({
    required this.entries,
    required this.marks,
    required this.evaluations,
    required this.cycles,
    required this.range,
    required this.observedCyclesOutsideApp,
  });

  final List<DailyEntry> entries;

  /// The user-placed marks (the ignore-temperature keys and the drawn mark
  /// glyphs ride on them directly).
  final List<CycleMark> marks;

  /// The per-cycle evaluations the overlay draws from — part of the shared
  /// derived pass the screen watches, never re-derived here.
  final List<CycleEvaluation> evaluations;

  /// The cycle groups of the SAME derived pass as [evaluations]
  /// (index-aligned): the day/cycle mapping comes from them.
  final List<Cycle> cycles;

  /// The settings-selected temperature display range: the chart's FIXED y
  /// bounds (and, via the shared scale, the rail's labels).
  final TemperatureRange range;

  /// The outside-app observed-cycles setting: the boundary ordinals' shift.
  final int observedCyclesOutsideApp;

  @override
  State<_CycleChart> createState() => _CycleChartState();
}

final class _CycleChartState extends State<_CycleChart> {
  /// Narrowest day column still considered usable — below this the labels
  /// would overlap, so a longer recorded range scrolls (never shrink-squeezes).
  static const double minDayColumnWidth = 24;

  /// The frozen left rail's width (the paper sheet's fixed left margin).
  /// The chart reserves NO axis width; the scroll content holds day columns
  /// only and the plot spans its full width.
  static const double frozenRailWidth = 44;

  /// The fixed height of the day/cycle header segment (day of month above,
  /// day of cycle underneath) — shared between the scrolling header row and
  /// the rail's prototype slot so both stay vertically in step.
  static const double dayHeaderRowHeight = 28;

  static const Duration _scrollDuration = Duration(milliseconds: 300);

  late _ChartDays _days;
  final ScrollController _scrollController = ScrollController();

  /// Layout snapshot of the last build, for the scroll listener's window
  /// math and the jump-to-date target computation.
  double? _viewportWidth;
  double? _columnWidth;

  /// The day-index window currently built (inclusive bounds). It PARKS with
  /// an extra screen-width of margin past the visible edges and stays put
  /// while the content slides, so a fling covers a whole screen-width
  /// between two rebuilds instead of one day column.
  int _windowStart = 0;
  int _windowEnd = 0;

  /// The one-time initial auto-scroll: on the FIRST data frame the viewport
  /// jumps to the newest days (content's right edge); a later re-emit never
  /// re-jumps, the user's position survives.
  bool _didInitialAutoScroll = false;

  /// Whether an auto-scroll attempt is scheduled but not yet run (prevents
  /// initState + didUpdateWidget stacking duplicate post-frame callbacks).
  bool _initialAutoScrollScheduled = false;

  /// The jump affordance lives in the AppBar (above this state) but needs
  /// this state's scroll hooks, so the state registers its callback in
  /// [cycleChartJumpProvider] while mounted. Riverpod forbids provider
  /// writes inside the widget life-cycle methods: registration and
  /// unregister run post-frame.
  StateController<void Function(BuildContext context)?>? _jumpRegistration;

  /// Registers [_jumpToDate] as the AppBar's jump affordance; post-frame so
  /// the provider write happens after the build sweep.
  void _registerJumpAffordance() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registration = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(cycleChartJumpProvider.notifier);
      registration.state = _jumpToDate;
      _jumpRegistration = registration;
    });
  }

  /// Clears the AppBar registration; post-frame so the provider write
  /// happens outside the teardown sweep. The clear is STAMPED: it only
  /// nulls the registration while it still holds its OWN callback, so a
  /// later chart that re-registered in between keeps its affordance.
  void _unregisterJumpAffordance() {
    final registration = _jumpRegistration;
    _jumpRegistration = null;
    if (registration == null) return;
    final myCallback = _jumpToDate; // tear-off equal to the registered one
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!registration.mounted) return;
      if (registration.state == myCallback) registration.state = null;
    });
  }

  /// Schedules the one-time initial auto-scroll; post-frame so the scroll
  /// view is laid out when the jump happens.
  void _scheduleInitialAutoScroll() {
    if (_didInitialAutoScroll || _initialAutoScrollScheduled) return;
    if (widget.entries.isEmpty) return; // no data frame yet — nothing to show
    _initialAutoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAutoScrollScheduled = false;
      if (_didInitialAutoScroll || !mounted || !_scrollController.hasClients) {
        // No client yet: the next data frame retries.
        return;
      }
      _didInitialAutoScroll = true;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollController.jumpTo(max);
    });
  }

  @override
  void initState() {
    super.initState();
    _days = _ChartDays(
      widget.entries,
      widget.marks,
      widget.cycles,
      widget.observedCyclesOutsideApp,
    );
    _scrollController.addListener(_onScrolled);
    _registerJumpAffordance();
    // Data may already be present at mount time.
    _scheduleInitialAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _CycleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A re-emitted stream changes the mapping, so re-window instead of
    // rendering stale data.
    if (!identical(oldWidget.entries, widget.entries) ||
        !identical(oldWidget.marks, widget.marks) ||
        !identical(oldWidget.cycles, widget.cycles) ||
        oldWidget.observedCyclesOutsideApp != widget.observedCyclesOutsideApp) {
      _days = _ChartDays(
        widget.entries,
        widget.marks,
        widget.cycles,
        widget.observedCyclesOutsideApp,
      );
      // Only the FIRST data frame (an initial auto-scroll still pending)
      // may trigger the jump here; once it ran, a later re-emit never
      // re-jumps and the user's position survives.
      _scheduleInitialAutoScroll();
    }
  }

  @override
  void dispose() {
    _unregisterJumpAffordance();
    _scrollController.removeListener(_onScrolled);
    _scrollController.dispose();
    super.dispose();
  }

  void _openDaySheet(int index) {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(cycleDayPanelProvider.notifier).state = _days.dayAt(
      index,
    );
  }

  /// The leftmost day with any pixel on screen: day cell i spans
  /// [i * colW, (i + 1) * colW) in the stripless scroll content.
  int _firstVisibleDay(int dayCount) {
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    return (offset / colW).floor().clamp(0, dayCount - 1);
  }

  /// The day-index window to build for the current scroll offset. Returns
  /// the PARKED window while it still covers the visible range plus the
  /// one-day seam margin; otherwise it re-parks (visible columns plus
  /// [windowMarginDays] of margin each side), so a rebuild happens at most
  /// once per extra screen-width of travel and never leaves the viewport
  /// edge without a built column.
  (int, int) _windowFor(int dayCount) {
    final viewport = _viewportWidth ?? 0;
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final firstVisible = _firstVisibleDay(dayCount);
    // The last column with any pixel on screen: the largest i with
    // i < (offset + viewport) / colW — the ceil's minus one.
    final lastVisible = (((offset + viewport) / colW).ceil() - 1).clamp(
      firstVisible,
      dayCount - 1,
    );
    final parkedStart = math.min(_windowStart, dayCount - 1);
    final parkedEnd = math.min(_windowEnd, dayCount - 1);
    final leftNeeded = math.max(0, firstVisible - 1);
    final rightNeeded = math.min(dayCount - 1, lastVisible + 1);
    if (parkedStart < parkedEnd &&
        leftNeeded >= parkedStart &&
        rightNeeded <= parkedEnd) {
      return (parkedStart, parkedEnd);
    }
    final margin = windowMarginDays(viewport, colW);
    return (
      math.max(0, firstVisible - 1 - margin),
      math.min(dayCount - 1, lastVisible + 1 + margin),
    );
  }

  /// The window margin in day columns: one extra screen-width rounded UP to
  /// whole columns, derived from the LIVE viewport rather than a constant —
  /// phone and desktop window carry the same one-screen lead.
  static int windowMarginDays(double viewport, double columnWidth) =>
      columnWidth <= 0 ? 0 : (viewport / columnWidth).ceil();

  void _onScrolled() {
    final (start, end) = _windowFor(_days.dayCount);
    if (start != _windowStart || end != _windowEnd) {
      setState(() {
        _windowStart = start;
        _windowEnd = end;
      });
    }
  }

  /// Translates a tap on the plot area into a day index and opens the day's
  /// sheet: the half-column-shifted domain maps the tap's local x linearly
  /// onto a fractional day index whose integer parts are the columns'
  /// centers; the nearest day column wins.
  void _openDayAtLocalX(double localX, double plotWidth) {
    final t = (localX / plotWidth).clamp(0.0, 1.0);
    final d = -0.5 + t * _days.dayCount;
    final index = d.round().clamp(0, _days.dayCount - 1);
    _openDaySheet(index);
  }

  /// Opens the date picker bounded to the recorded range and centers the
  /// picked day in the viewport.
  Future<void> _jumpToDate(BuildContext context) async {
    if (!mounted) return;
    final viewport = _viewportWidth;
    final colW = _columnWidth;
    if (viewport == null || colW == null) return;
    final firstDay = _days.firstDay;
    final lastDay = _days.dayAt(_days.dayCount - 1);
    // Initial pick: the leftmost VISIBLE day, not the marined window's
    // start — the picker should open on the day the user is looking at.
    final initial = _days.dayAt(_firstVisibleDay(_days.dayCount));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDay,
      lastDate: lastDay,
    );
    if (picked == null) return;
    // The dialog rides the root navigator while the screen body (and this
    // state) can unmount above it — a resolved pick may still arrive after
    // the dispose.
    if (!mounted) return;
    final index = DateOnly.daysBetween(
      DateOnly.normalize(picked),
      firstDay,
    ).clamp(0, _days.dayCount - 1);
    if (!_scrollController.hasClients) return;
    // Center the picked day's column: its center sits at
    // (index + 0.5) * colW in the stripless scroll content, and centering
    // places it at the viewport's middle.
    final target = ((index + 0.5) * colW - viewport / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The evaluation artifacts are computed at render time from entries
    // plus marks — never persisted, so a mark change live-updates the
    // overlay (ADR-0001).
    final overlay = buildEvaluationOverlay(
      evaluations: widget.evaluations,
      marks: widget.marks,
      firstDay: _days.firstDay,
      dayCount: _days.dayCount,
    );

    // Runs of adjacent measured days: the line connects two temperatures
    // only when their calendar days are adjacent (curve helpers,
    // lib/ui/cycle_curve.dart). The points keep the RAW temperatures —
    // whether a dot or line piece is drawable inside the fixed range is
    // decided in the chart config below.
    final runs = curveRuns(
      _days.byIndex,
      ignoredDayIndexes: _days.ignoredDayIndexes,
    );
    final points = [for (final run in runs) ...run.points];

    if (points.isEmpty) {
      return Text(
        l10n.cycleNoData,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    // Out-of-range values are simply not rendered: the point filter and the
    // segment clipper keep dots and line pieces inside the window. No
    // degenerate-span guard is needed — the settings card enforces
    // min < max by construction.
    final yMin = widget.range.min;
    final yMax = widget.range.max;

    // The plot height adapts to the y-span; the constants below are tuned
    // values. TODO(user-review): growth rate and cap are display
    // heuristics, not rules from the cheat sheet.
    const chartBaseHeight = 260.0;
    const chartHeightCap = 400.0;
    const comfortableYSpan = 3.0;
    final chartHeight =
        (chartBaseHeight + math.max(0.0, yMax - yMin - comfortableYSpan) * 80.0)
            .clamp(chartBaseHeight, chartHeightCap);

    // One source of truth for the temperature scale chart config and rail
    // labels alike.
    final scale = _TemperatureScale(
      min: yMin,
      max: yMax,
      plotHeight: chartHeight,
      locale: Localizations.localeOf(context).toString(),
    );

    // SUZ glyph anchoring in °C value units (independent of the plot's
    // pixel height), constants shared with the PDF export via
    // suz_glyph.dart. TODO(user-review): both values are owner-eyeball
    // rendering details.
    final temperatureColor = Theme.of(context).colorScheme.primary;
    final interruptedColor = temperatureColor.withValues(
      alpha: ignoredTemperatureAlpha,
    );
    // The evaluation-artifact accent: scheme secondary, the one color the
    // regular temperature/bleeding/mucus rendering does not use — it feeds
    // the dashed R10 baseline segment bars AND the user-placed SUZ bars.
    final evaluationColor = Theme.of(context).colorScheme.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final scrollViewport = viewport - frozenRailWidth;
        _viewportWidth = scrollViewport;
        final dayCount = _days.dayCount;
        // At most as many days as fit the scroll viewport at the minimum
        // usable width; a longer range keeps that width and scrolls.
        final overflow = dayCount * minDayColumnWidth > scrollViewport;
        final colW = overflow ? minDayColumnWidth : scrollViewport / dayCount;
        _columnWidth = colW;
        // The explicit fitting-case viewport keeps the no-scroll case free
        // of floating-point slack a recomputed sum could introduce.
        final contentWidth = overflow ? dayCount * colW : scrollViewport;
        final (winStart, winEnd) = _windowFor(dayCount);
        _windowStart = winStart;
        _windowEnd = winEnd;

        // The window's data slice, at the curve's GLOBAL x positions: the
        // axis range never changes with the scroll, so a window rebuild
        // only adds/removes points in place.
        final winByIndex = {
          for (final entry in _days.byIndex.entries)
            if (entry.key >= winStart && entry.key <= winEnd)
              entry.key: entry.value,
        };
        final winRuns = curveRuns(
          winByIndex,
          ignoredDayIndexes: _days.ignoredDayIndexes,
        );
        final winSegments = curveSegments(winRuns);
        final interruptedByIndex = <int, bool>{
          for (final run in winRuns)
            for (final point in run.points) point.dayIndex: point.excluded,
        };

        // Weekend bands behind the day columns, built for the window only;
        // the on-color whisper works on light and dark surfaces alike.
        final weekendBandColor = Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.07);
        // The half-column-shifted domain: the ±0.5 offsets below and in the
        // baseline/SUZ drawing mean exactly "column bounds".
        final lastX = (dayCount - 0.5).toDouble();
        final weekendBands = <VerticalRangeAnnotation>[];
        for (var i = winStart; i <= winEnd; i++) {
          if (!DateOnly.isWeekend(_days.dayAt(i))) continue;
          var x1 = (i - 0.5).clamp(-0.5, lastX).toDouble();
          var x2 = (i + 0.5).clamp(-0.5, lastX).toDouble();
          weekendBands.add(
            VerticalRangeAnnotation(x1: x1, x2: x2, color: weekendBandColor),
          );
        }

        final maxX = (dayCount - 0.5).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The paper sheet's layout: the frozen left rail next to the
            // sliding day columns — the scale never scrolls away.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LeftRail(scale: scale),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DayHeaderRow(
                            days: _days,
                            cellWidth: colW,
                            windowStart: winStart,
                            windowEnd: winEnd,
                          ),
                          const SizedBox(height: 4),
                          // The paper sheet's grid rows above the temperature
                          // body: bleeding, mucus, Mittelschmerz M, sex — no
                          // gap between the rows and the plot, they read as
                          // one block.
                          _SignalRows(
                            kinds: _topSignalKinds,
                            days: _days,
                            cellWidth: colW,
                            windowStart: winStart,
                            windowEnd: winEnd,
                            peakIndexes: overlay.peakIndexes,
                            onDayTap: _openDaySheet,
                          ),
                          SizedBox(
                            height: chartHeight,
                            child: Stack(
                              children: [
                                LineChart(
                                  LineChartData(
                                    lineBarsData: [
                                      // One two-spot bar per CLIPPED span of a
                                      // segment, so a span touching an
                                      // interrupted day can render lighter
                                      // while the others keep full strength.
                                      for (final span in visibleCurveSegments(
                                        winSegments,
                                        widget.range,
                                      ))
                                        LineChartBarData(
                                          spots: [
                                            FlSpot(span.startX, span.startY),
                                            FlSpot(span.endX, span.endY),
                                          ],
                                          isCurved: false,
                                          barWidth: 1.6,
                                          color: span.lighter
                                              ? interruptedColor
                                              : temperatureColor,
                                          dotData: const FlDotData(show: false),
                                        ),
                                      // The dots as invisible-line bars so the
                                      // per-spot painter can render an
                                      // interrupted day's dot lighter. Only
                                      // IN-RANGE points get a spot: skipping
                                      // the spot skips the whole painter (dot,
                                      // circled-higher ring, arrow-up glyph).
                                      for (final run in winRuns)
                                        if (run.points.any(
                                          (point) => isBbtCInRange(
                                            point.bbtC,
                                            widget.range,
                                          ),
                                        ))
                                          LineChartBarData(
                                            spots: [
                                              for (final point in run.points)
                                                if (isBbtCInRange(
                                                  point.bbtC,
                                                  widget.range,
                                                ))
                                                  FlSpot(
                                                    point.dayIndex.toDouble(),
                                                    point.bbtC,
                                                  ),
                                            ],
                                            color: Colors.transparent,
                                            dotData: FlDotData(
                                              show: true,
                                              getDotPainter:
                                                  (
                                                    spot,
                                                    _,
                                                    bar,
                                                    __,
                                                  ) => dotPainterForDay(
                                                    dayIndex: spot.x.round(),
                                                    dotColor:
                                                        interruptedByIndex[spot
                                                                .x
                                                                .round()] ??
                                                            false
                                                        ? interruptedColor
                                                        : temperatureColor,
                                                    colorScheme: Theme.of(
                                                      context,
                                                    ).colorScheme,
                                                    overlay: overlay,
                                                  ),
                                            ),
                                          ),
                                      // The baseline segments (R10), drawn
                                      // LAST so they paint above curve and
                                      // dots; clamped to the plot bounds
                                      // like the weekend bands.
                                      for (final segment
                                          in overlay.baselineSegments)
                                        LineChartBarData(
                                          spots: [
                                            FlSpot(
                                              math.max(
                                                -0.5,
                                                segment.startIndex - 0.5,
                                              ),
                                              segment.value,
                                            ),
                                            FlSpot(
                                              math.min(
                                                lastX,
                                                segment.endIndex + 0.5,
                                              ),
                                              segment.value,
                                            ),
                                          ],
                                          isCurved: false,
                                          barWidth: 1,
                                          color: evaluationColor,
                                          dashArray: const [6, 4],
                                          dotData: const FlDotData(show: false),
                                        ),
                                      // The user-placed SUZ marks: a vertical
                                      // bar hanging down from the chart's top
                                      // border plus a right-pointing arrow —
                                      // only user-placed marks render, the
                                      // computed suzBegins never draws here.
                                      for (final suz in overlay.suzMarks) ...[
                                        LineChartBarData(
                                          spots: [
                                            // Column start (x − 0.5) for
                                            // suzMorning, column middle for
                                            // suzEvening.
                                            FlSpot(
                                              suz.barX.clamp(-0.5, lastX),
                                              yMax,
                                            ),
                                            FlSpot(
                                              suz.barX.clamp(-0.5, lastX),
                                              yMax - suzBarHangSpanDegrees,
                                            ),
                                          ],
                                          isCurved: false,
                                          barWidth: 2,
                                          color: evaluationColor,
                                          dotData: const FlDotData(show: false),
                                        ),
                                        // The arrow glyph: a single-spot bar
                                        // whose painter draws it inside the
                                        // hung band.
                                        LineChartBarData(
                                          spots: [
                                            FlSpot(
                                              suz.barX.clamp(-0.5, lastX),
                                              yMax - suzArrowTopInsetDegrees,
                                            ),
                                          ],
                                          color: Colors.transparent,
                                          dotData: FlDotData(
                                            show: true,
                                            getDotPainter: (_, __, ___, ____) =>
                                                SuzArrowDotPainter(
                                                  color: evaluationColor,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                    minX: -0.5,
                                    maxX: maxX,
                                    minY: scale.min,
                                    maxY: scale.max,
                                    rangeAnnotations: RangeAnnotations(
                                      verticalRangeAnnotations: weekendBands,
                                    ),
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
                                      // The NER temperature grid: a line every
                                      // 0.1 K — solid at whole degrees, dashed
                                      // at the 0.5 midpoints, hairline between.
                                      // Classifying via the ×10 integer: the
                                      // 0.1 values are not exactly
                                      // representable, float equality would
                                      // misclassify.
                                      drawHorizontalLine: true,
                                      horizontalInterval: 0.1,
                                      getDrawingHorizontalLine: (value) {
                                        final tenths = (value * 10).round();
                                        final emphasized = Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.45);
                                        final onSurface = Theme.of(
                                          context,
                                        ).colorScheme.onSurface;
                                        if (tenths % 10 == 0) {
                                          return FlLine(
                                            color: emphasized,
                                            strokeWidth: 1.2,
                                          );
                                        }
                                        if (tenths % 5 == 0) {
                                          return FlLine(
                                            color: emphasized,
                                            strokeWidth: 1.2,
                                            dashArray: const [4, 3],
                                          );
                                        }
                                        return FlLine(
                                          color: onSurface.withValues(
                                            alpha: 0.12,
                                          ),
                                          strokeWidth: 0.5,
                                        );
                                      },
                                    ),
                                    baselineX: -0.5,
                                    // Thick cycle-start separators at the
                                    // boundary day's column start; a boundary
                                    // on the FIRST tracked day draws no extra
                                    // line (its x = −0.5 clamps at the plot —
                                    // it paints through the first cells' thick
                                    // LEFT border instead).
                                    extraLinesData: ExtraLinesData(
                                      verticalLines: [
                                        for (
                                          var i = math.max(winStart, 1);
                                          i <= winEnd;
                                          i++
                                        )
                                          if (_days.isCycleBoundary(i))
                                            VerticalLine(
                                              x: i - 0.5,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              strokeWidth: 2,
                                            ),
                                      ],
                                    ),
                                    borderData: FlBorderData(show: false),
                                    titlesData: FlTitlesData(
                                      // The frozen rail paints the scale (no
                                      // reserved width) and _DayHeaderRow the
                                      // per-day labels — every column label,
                                      // not just sparse axis ticks.
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          reservedSize: 0,
                                          showTitles: false,
                                        ),
                                      ),
                                      topTitles: const AxisTitles(),
                                      rightTitles: const AxisTitles(),
                                      bottomTitles: const AxisTitles(),
                                    ),
                                    // Gesture-transparent: the horizontal
                                    // scroll owns drags; the tap overlay above
                                    // the chart maps tap/long-press to columns.
                                    lineTouchData: const LineTouchData(
                                      enabled: false,
                                      handleBuiltInTouches: false,
                                    ),
                                  ),
                                ),
                                _CycleOrdinalBadges(
                                  days: _days,
                                  cellWidth: colW,
                                  windowStart: winStart,
                                  windowEnd: winEnd,
                                ),
                                // The tap overlay covers the whole scroll
                                // content and maps taps/long-presses to day
                                // columns.
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) => _openDayAtLocalX(
                                      details.localPosition.dx,
                                      contentWidth,
                                    ),
                                    onLongPressStart: (details) =>
                                        _openDayAtLocalX(
                                          details.localPosition.dx,
                                          contentWidth,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          EvaluationMarksRow(
                            dayCount: dayCount,
                            cellWidth: colW,
                            numbersByIndex: overlay.numbersByIndex,
                            onDayTap: _openDaySheet,
                            isCycleBoundary: _days.isCycleBoundary,
                            windowStart: winStart,
                            windowEnd: winEnd,
                          ),
                          const SizedBox(height: 4),
                          // The below-chart strip: measurement time,
                          // disturbance letters, cervix, pain, day-note
                          // indicator. TODO(user-review): the experts may
                          // want the Mittelschmerz M rendered in the pain
                          // row as well.
                          _SignalRows(
                            kinds: _belowChartKinds,
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
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The top block's grid rows (paper sheet order): bleeding → mucus →
/// Mittelschmerz M → sex. TODO(user-review): the M letter's home (own row
/// beneath the mucus row; clinicians may prefer it in the pain row too) is
/// an owner-eyeball choice.
const _topSignalKinds = <_SignalKind>[
  _SignalKind.bleeding,
  _SignalKind.mucus,
  _SignalKind.mittelschmerz,
  _SignalKind.sex,
];

/// The below-chart strip's rows (owner-decided order): measurement time →
/// disturbance → cervix → pain → day-note indicator. TODO(user-review): the
/// note's home in the strip's last row is an owner-eyeball choice.
const _belowChartKinds = <_SignalKind>[
  _SignalKind.time,
  _SignalKind.disturbance,
  _SignalKind.cervix,
  _SignalKind.pain,
  _SignalKind.note,
];

/// One recording row per segment signal, top-down in segment order. The
/// rows hold ONLY day cells (name glyphs live in the frozen left rail) and
/// render every day, windowed at the curve's global column positions.
final class _SignalRows extends StatelessWidget {
  const _SignalRows({
    required this.kinds,
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
    required this.peakIndexes,
    required this.onDayTap,
  });

  final List<_SignalKind> kinds;

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  /// Day indexes carrying the mucus-peak mark: they render the solid peak
  /// dot above the mucus glyph.
  final Set<int> peakIndexes;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final kind in kinds)
        Padding(
          padding: EdgeInsets.only(
            top: kind == kinds.first ? 0 : _signalRowGap,
          ),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// The recording rows' fixed heights, shared between the scrolling rows and
/// the frozen left rail — a layout change here must move both sides or the
/// rail's alignment test fails.
const double _signalRowGap = 2;

/// The fixed height a signal row's day cells occupy: mucus and disturbance
/// reserve the peak-dot slot / two letter slots respectively; the time row
/// the height of a vertically written HH:mm text (see _timeContent).
double _signalRowHeight(_SignalKind kind) => switch (kind) {
  _SignalKind.mucus || _SignalKind.disturbance => 24,
  _SignalKind.time => 30,
  _ => 12,
};

double _signalRowTop(_SignalKind kind, List<_SignalKind> kinds) {
  var top = 0.0;
  for (final k in kinds) {
    if (k == kind) break;
    top += _signalRowHeight(k) + _signalRowGap;
  }
  return top;
}

/// A segment's total height — the rail's glyph segment must match it.
double _signalSegmentHeight(List<_SignalKind> kinds) =>
    kinds.fold(0.0, (h, kind) => h + _signalRowHeight(kind) + _signalRowGap) -
    (kinds.isEmpty ? 0 : _signalRowGap);

enum _SignalKind {
  bleeding,
  mucus,
  mittelschmerz,
  sex,
  time,
  disturbance,
  cervix,
  pain,
  note,
}

/// Test-visible key prefix of a row's day cells.
String _signalKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCell',
  _SignalKind.mucus => 'mucusCell',
  _SignalKind.mittelschmerz => 'mittelschmerzCell',
  _SignalKind.sex => 'sexCell',
  _SignalKind.cervix => 'cervixCell',
  _SignalKind.pain => 'painCell',
  _SignalKind.disturbance => 'disturbanceCell',
  _SignalKind.time => 'timeCell',
  _SignalKind.note => 'noteCell',
};

/// Test-visible key prefix of a row's 44 px corner slot.
String _signalCornerKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCorner',
  _SignalKind.mucus => 'mucusCorner',
  _SignalKind.mittelschmerz => 'mittelschmerzCorner',
  _SignalKind.sex => 'sexCorner',
  _SignalKind.cervix => 'cervixCorner',
  _SignalKind.pain => 'painCorner',
  _SignalKind.disturbance => 'disturbanceCorner',
  _SignalKind.time => 'timeCorner',
  _SignalKind.note => 'noteCorner',
};

/// The localized row name for a signal (corner tooltip/semantics label).
// TODO(user-review): the row-name wording is a first draft mirroring the
// entry form's vocabulary; the experts may want different names.
String _signalRowName(_SignalKind kind, AppLocalizations l10n) =>
    switch (kind) {
      _SignalKind.bleeding => l10n.termBleeding,
      _SignalKind.mucus => l10n.termMucus,
      _SignalKind.mittelschmerz => l10n.termMittelschmerz,
      _SignalKind.sex => l10n.termSex,
      _SignalKind.cervix => l10n.cycleRowCervix,
      _SignalKind.pain => l10n.termBreastPain,
      _SignalKind.disturbance => l10n.cycleRowDisturbance,
      _SignalKind.time => l10n.termMeasurementTime,
      _SignalKind.note => l10n.cycleRowNote,
    };

/// A signal row's sample glyph, rendered in the frozen left rail at the
/// row's vertical slot.
Widget _signalCornerSample(BuildContext context, _SignalKind kind) {
  final scheme = Theme.of(context).colorScheme;
  return switch (kind) {
    _SignalKind.bleeding => SizedBox(
      width: 10,
      height: 10,
      child: BleedingSymbol(
        bleeding: Bleeding.spotting,
        color: scheme.error,
        borderColor: scheme.error,
      ),
    ),
    _SignalKind.mucus => MucusSymbolText(
      display: mucusDisplay(sign: MucusSign.s),
      fontSize: 10,
      color: scheme.tertiary,
    ),
    _SignalKind.cervix => Text(
      cervixPositionSymbol(CervixPosition.medium),
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.mittelschmerz => Text(
      'M',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.sex => Text(
      'X',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.pain => Text(
      'B',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.disturbance => Text(
      'kr',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.time => Icon(Icons.schedule, size: 12, color: scheme.onSurface),
    _SignalKind.note => Icon(
      Icons.sticky_note_2_outlined,
      size: 12,
      color: scheme.onSurface,
    ),
  };
}

/// The day-column width boundary between the time row's HORIZONTAL and
/// VERTICAL rendering: below it the HH:mm text renders rotated so the time
/// stays visible even at the minimum usable column width.
// TODO(user-review): the threshold is a tuned display heuristic, not a
// rule from the cheat sheet.
const double _timeCellMinColumnWidth = 32;

/// One signal's recording row: the window's day cells only — the row's
/// name glyph lives in the frozen left rail (see _LeftRail), at this row's
/// vertical slot.
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

  /// Day indexes carrying the mucus-peak mark (only read by the mucus row).
  final Set<int> peakIndexes;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('${_signalKeyPrefix(kind)}-$i'),
            width: cellWidth,
            child: InkWell(
              onTap: () => onDayTap(i),
              // The day-cell separator, thickened to the solid cycle-start
              // line when the NEXT day opens a cycle (the first tracked day
              // thickens its LEFT border: the domain-edge separator would
              // clamp at the plot's left edge).
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: i == 0
                        ? cycleDayCellBorderSide(
                            context,
                            isCycleBoundary: days.isCycleBoundary(0),
                          )
                        : BorderSide.none,
                    right: cycleDayCellBorderSide(
                      context,
                      isCycleBoundary: days.isCycleBoundary(i + 1),
                    ),
                  ),
                ),
                child: _cell(context, i),
              ),
            ),
          ),
      ],
    );
  }

  /// The fixed height each row's day cell occupies — keeps a row's empty
  /// cells at the recorded cells' height (the shared height the frozen
  /// rail's glyph slot mirrors).
  double get _cellHeight => _signalRowHeight(kind);

  /// One day's cell content.
  Widget _cell(BuildContext context, int index) {
    final day = days.byIndex[index];
    return SizedBox(
      height: _cellHeight,
      child: Center(
        child: switch (kind) {
          _SignalKind.bleeding => _bleedingContent(context, day),
          _SignalKind.mucus => _mucusContent(context, index, day),
          _SignalKind.mittelschmerz => _mittelschmerzContent(context, day),
          _SignalKind.sex => _sexContent(context, day),
          _SignalKind.cervix => _cervixContent(context, day),
          _SignalKind.pain => _painContent(context, day),
          _SignalKind.disturbance => _disturbanceContent(context, day),
          _SignalKind.time => _timeContent(context, day),
          _SignalKind.note => _noteContent(context, day),
        },
      ),
    );
  }

  /// Bleeding: the shared square-box symbol fills the day cell (the
  /// shared bottom-anchored fill-fraction convention; spotting dotted).
  static Widget _bleedingContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    return BleedingSymbol(bleeding: day.bleeding);
  }

  /// Mucus: the reserved peak-dot slot above the glyph, reserved in every
  /// cell so the row keeps its rhythm regardless of which day is the peak.
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

  /// Cervix: position letter, firmness shorthand beside it; the OPENING is
  /// deliberately not displayed (entry-form-only field). Raw observation
  /// display only, never a fertility conclusion (ADR-0001); neutral
  /// on-surface ink (no scheme hue claimed).
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

  /// Sex: one X glyph per recorded time slot, each at its third of the day
  /// column (more slots render side by side — "sex happened, time unknown"
  /// is deliberately not representable, DailyEntry.sexTimings). No
  /// collision with the disturbance codes: interrupted days render only as
  /// lighter curve points. TODO(user-review): the X and its thirds
  /// placement are provisional/eyeball choices.
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

  /// Pain: the letter B (uppercase, distinguishable from the lowercase
  /// cervix letters; neutral on-surface ink). TODO(user-review): the letter
  /// mirrors the entry-form ("Brustschmerzen (B)") vocabulary — the same
  /// ad-hoc glyph caveat as the cervix letters applies.
  static Widget _painContent(BuildContext context, DailyEntry? day) {
    if (day == null || !day.painBreast) return const SizedBox.shrink();
    return Text(
      'B',
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// Mittelschmerz: the letter M in its own row beneath the mucus row.
  static Widget _mittelschmerzContent(BuildContext context, DailyEntry? day) {
    if (day == null || !day.painMittelschmerz) return const SizedBox.shrink();
    return Text(
      'M',
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// Disturbance: the stacked letter codes of the day's temperature
  /// disturbances ([disturbanceLetters]) — neutral on-surface ink. These
  /// letters only NAME the recorded disturbances; the interrupted curve
  /// rendering is keyed to the ignoreTemperature MARK (cycle_curve.dart).
  static Widget _disturbanceContent(BuildContext context, DailyEntry? day) {
    final letters = disturbanceLetters(day);
    if (letters.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final letter in letters)
            Text(
              letter,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  /// Measurement time: the localized HH:mm text, vertical in narrow
  /// columns (below [_timeCellMinColumnWidth]), horizontal in wide ones.
  /// measuredAtMinutes exists only together with bbtC (the DailyEntry
  /// constructor drops a time without a temperature), so the text never
  /// claims a time for a temperature-free day.
  Widget _timeContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final minutes = day.measuredAtMinutes;
    if (minutes == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final time = DateTime.utc(2000).add(Duration(minutes: minutes));
    final text = Text(
      DateFormat.Hm(locale).format(time),
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    if (cellWidth < _timeCellMinColumnWidth) {
      // The rotated text's width becomes its cell height — the row-height
      // constant reserves that space (see _signalRowHeight).
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: RotatedBox(quarterTurns: 3, child: text),
      );
    }
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }

  /// Note indicator: a small sticky-note glyph for a day whose entry
  /// carries a NON-EMPTY notes text; the note is edited in the Diary form.
  static Widget _noteContent(BuildContext context, DailyEntry? day) {
    if (day == null || day.notes == null || day.notes!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Icon(
      Icons.sticky_note_2_outlined,
      size: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// Horizontal placement of a sex slot's X glyph: each slot's X sits at the
/// center of its third of the column (-2/3, 0, +2/3), so slot placement
/// stays visible and several slots never overlap.
Alignment _sexTimingAlignment(SexTiming timing) => switch (timing) {
  SexTiming.start => const Alignment(-2 / 3, 0),
  SexTiming.middle => Alignment.center,
  SexTiming.end => const Alignment(2 / 3, 0),
};

/// The localized short month name for [date]'s calendar month, spelled like
/// intl's date FORMAT abbreviations (de "Jan." with period). The plain
/// DateFormat.MMM constant resolves to the STANDALONE abbreviated months
/// (de "Jan", no period) — hence the direct read from the symbol set.
String _shortMonthLabel(DateTime date, String locale) =>
    DateFormat('d', locale).dateSymbols.SHORTMONTHS[date.month - 1];

/// The day/cycle header line above the chart: day of month on top (the
/// first-of-month column shows the localized short month instead — a
/// CALENDAR-based, not cycle-based rule), day of cycle underneath. The
/// "Zyklus N" ordinal renders inside the plot as a badge
/// (_CycleOrdinalBadges). TODO(user-review): the column prototypes
/// ("14.", "#5", in the rail's header slot) are ad-hoc samples.
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('dayLabel-$i'),
            width: cellWidth,
            height: _CycleChartState.dayHeaderRowHeight,
            child: Container(
              // The day-cell separator, same as the signal rows.
              decoration: BoxDecoration(
                border: Border(
                  left: i == 0
                      ? cycleDayCellBorderSide(
                          context,
                          isCycleBoundary: days.isCycleBoundary(0),
                        )
                      : BorderSide.none,
                  right: cycleDayCellBorderSide(
                    context,
                    isCycleBoundary: days.isCycleBoundary(i + 1),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Only the FIRST day of a calendar month carries the
                  // month, so the form stays scannable without crowding
                  // every narrow column.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      days.dayAt(i).day == 1
                          ? _shortMonthLabel(days.dayAt(i), locale)
                          : '${days.dayAt(i).day}.',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  // Day of cycle: subtle on-surface ink (the 1–6 numbering
                  // below is the evaluation artifact in the primary color);
                  // FittedBox squeezes long three-digit numbers in.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${days.cycleDayByIndex[i]}',
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One prototype cell in the frozen rail's header slot: the sample glyph
/// with its tooltip (long-press) and its semantics label.
Widget _columnPrototype({required String prototype, required String label}) =>
    Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(prototype, style: const TextStyle(fontSize: 10)),
          ),
        ),
      ),
    );

/// The in-plot "Zyklus N" chips: at every mark-opened cycle boundary a
/// small chip renders pinned to the top of the boundary day's column, below
/// the opaque tap overlay so day mapping is untouched. The boundary
/// separator at domain x = i − 0.5 sits at pixel i · cellWidth — the chip's
/// left edge pins there with an inset. The chip is free to shrink to its
/// label; its cycle's column span is only the FittedBox's max width.
///
/// TODO(user-review): the chip's look is an owner-eyeball rendering detail.
/// TODO(user-review): known overlap — a user-placed SUZ bar on the cycle's
/// first day hangs from the plot top and sits under the chip (opaque
/// background covers it).
const double _cycleBadgeColumnInset = 2;
const double _cycleBadgeTopInset = 3;
const double _cycleBadgeHeight = 14;

final class _CycleOrdinalBadges extends StatelessWidget {
  const _CycleOrdinalBadges({
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];
    for (var i = windowStart; i <= windowEnd; i++) {
      if (!days.isCycleBoundary(i)) continue;
      var nextBoundary = days.dayCount;
      for (var j = i + 1; j < days.dayCount; j++) {
        if (days.isCycleBoundary(j)) {
          nextBoundary = j;
          break;
        }
      }
      final rightIndex = math.min(nextBoundary, windowEnd + 1);
      chips.add(
        Positioned(
          left: i * cellWidth + _cycleBadgeColumnInset,
          top: _cycleBadgeTopInset,
          height: _cycleBadgeHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  (rightIndex - i) * cellWidth - 2 * _cycleBadgeColumnInset,
            ),
            child: Container(
              key: ValueKey('cycleOrdinalChip-$i'),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.cycleOrdinal(days.cycleOrdinalByStart[days.dayAt(i)]!),
                  key: ValueKey('cycleOrdinal-$i'),
                  style: TextStyle(fontSize: 9, color: scheme.primary),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(children: chips);
  }
}
// --- temperature scale (chart domain + frozen-rail labels) ------------------

/// The temperature scale's single source of truth: the chart's y domain
/// over the plot height feeds BOTH the chart config (minY/maxY) and the
/// frozen rail's scale labels ([pixelFor] uses the identical linear map).
final class _TemperatureScale {
  const _TemperatureScale({
    required this.min,
    required this.max,
    required this.plotHeight,
    required this.locale,
  });

  /// The chart's lower y bound in °C (the settings range's min).
  final double min;

  /// The chart's upper y bound in °C (the settings range's max).
  final double max;

  /// The plot area's height in pixels.
  final double plotHeight;

  /// The resolved display locale — the rail labels format decimals through
  /// it, so the rail and the rest of the app cannot disagree.
  final String locale;

  /// The pixel y (from the plot's TOP edge) of a temperature value — the
  /// same linear map fl_chart's painter applies.
  double pixelFor(double value) => (max - value) / (max - min) * plotHeight;

  /// The scale's tick values: every half degree across the domain (the
  /// settings step granularity keeps both bounds half-degree-aligned).
  List<double> get ticks => [
    for (var k = 0; k <= ((max - min) * 2).round(); k++) min + k * 0.5,
  ];

  /// The tick label with the °C unit on every label (the PDF's axis-label
  /// convention): numerals via the shared locale-aware display formatter,
  /// whole degrees plain, halves with one decimal (see
  /// lib/domain/decimal_display.dart).
  String labelFor(double value) =>
      '${_formatHalfDegree(value, locale: locale)} °C';
}

// --- frozen left rail --------------------------------------------------------

/// The frozen left rail: the paper sheet's fixed left margin, rendered
/// OUTSIDE the horizontal scroll. It carries the header prototypes, the
/// temperature scale and the rows' name glyphs in vertical slots mirroring
/// the scroll content's segment heights (shared constants; alignment is
/// pinned by the rail's widget test). TODO(user-review): the rail's
/// right-edge hairline is an owner-eyeball rendering detail.
final class _LeftRail extends StatelessWidget {
  const _LeftRail({required this.scale});

  /// The shared scale: min/max over the plot height, exactly what the
  /// chart config consumes.
  final _TemperatureScale scale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      key: const ValueKey('leftRail'),
      width: _CycleChartState.frozenRailWidth,
      child: DecoratedBox(
        // The rail's right-edge hairline, mirroring the day-grid hairlines.
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              width: 0.5,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The header slot: the two column prototypes.
            SizedBox(
              key: const ValueKey('dayHeaderCorner'),
              height: _CycleChartState.dayHeaderRowHeight,
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
            const SizedBox(height: 4),
            _railSignalSegment(context, l10n, _topSignalKinds),
            // The temperature scale: one label per half degree at its
            // value's plot pixel y (the shared mapping).
            SizedBox(
              key: const ValueKey('railScale'),
              height: scale.plotHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final value in scale.ticks)
                    Positioned(
                      left: 0,
                      width: _CycleChartState.frozenRailWidth,
                      top: scale.pixelFor(value) - 6,
                      height: 12,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Text(
                            scale.labelFor(value),
                            key: ValueKey(
                              'railScaleLabel-${scale.labelFor(value)}',
                            ),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The marks-row slot: empty in the rail (the 1–6 numbering is
            // per-day content), kept so the glyph segment below starts
            // exactly where the below-chart strip starts.
            const SizedBox(height: 4),
            SizedBox(height: EvaluationMarksRow.cellHeight),
            const SizedBox(height: 4),
            _railSignalSegment(context, l10n, _belowChartKinds),
          ],
        ),
      ),
    );
  }

  /// The rail glyph stack for one row segment: the segment's name glyphs,
  /// each vertically centered on the row's slot.
  Widget _railSignalSegment(
    BuildContext context,
    AppLocalizations l10n,
    List<_SignalKind> kinds,
  ) {
    return SizedBox(
      height: _signalSegmentHeight(kinds),
      child: Stack(
        children: [
          for (final kind in kinds)
            Positioned(
              left: 0,
              right: 0,
              top: _signalRowTop(kind, kinds),
              height: _signalRowHeight(kind),
              child: SizedBox(
                key: ValueKey(_signalCornerKeyPrefix(kind)),
                child: Semantics(
                  label: _signalRowName(kind, l10n),
                  child: Tooltip(
                    message: _signalRowName(kind, l10n),
                    child: Center(child: _signalCornerSample(context, kind)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- half-degree formatting ---------------------------------------------------

/// The rail's tick-label numerals: integers plain ("37"), halves with one
/// locale-correct decimal ("36.5" en / "36,5" de). The °C unit is appended
/// by [_TemperatureScale.labelFor], not here.
String _formatHalfDegree(double value, {required String locale}) {
  final rounded = (value * 100).round() / 100;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : formatDecimal(rounded, locale: locale, decimalDigits: 1);
}
