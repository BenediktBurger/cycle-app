// Zyklus screen: the recorded temperature curve, paper-style: the
// day/cycle header line ABOVE it, and INSIDE the top of the temperature
// block the per-day recording rows bleeding, mucus (with the reserved
// solid peak-dot slot above the glyph), the Mittelschmerz letter M on its
// own row directly beneath the mucus row (TODO(user-review): the exact
// home of the M letter is an owner-eyeball choice — the paper sheet writes
// it under the mucus letters; clinicians may want it twice, with the
// below-block pain row) and sex — pure recording, no interpretation; the
// curve runs through the main body BELOW those rows. UNDER the curve come
// the 1–6 numbering, the rows not on the paper sheet's grid (cervix,
// remaining pain) and — at the very bottom of the block — the
// disturbance-letter row for the day's temperature-disturbance (exclusion)
// flags; below the block come the measurement-time row (vertical text in
// narrow columns) and — at the very bottom, the paper sheet's remarks
// home — the day-note indicator row. The COMPUTED evaluation overlay
// (Mode M, ADR-0001): the user places the mucus-peak
// and first-higher marks, the app
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
// recorded range is not squeezed onto one screen — the day columns (header,
// curve, per-signal rows, marks row) scroll horizontally as one unit, while
// a FROZEN LEFT RAIL (the paper sheet's fixed left margin) sits outside the
// scroll and carries everything that must never slide away: the header
// prototypes, the temperature scale and the rows' name glyphs. A
// jump-to-date affordance moves the window onto a picked calendar day.
// Data outside the window is not built: the curve carries
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
    // The jump-to-date affordance sits in the AppBar actions, next to the
    // info action (a standalone row above the chart wasted vertical
    // space). Its callback is registered by the chart state while the
    // chart block is mounted — see cycleChartJumpProvider.
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
          // persisted. This is the screen's ONLY marks watch: the
          // evaluations and the raw marks are computed once and handed to
          // both the chart overlay and the table below.
          final marks =
              ref.watch(marksProvider).valueOrNull ?? const <CycleMark>[];
          final evaluations = evaluateCycles(entries, marks);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _CycleChart(
                entries: entries,
                marks: marks,
                evaluations: evaluations,
              ),
              const SizedBox(height: 12),
              // The paper's bottom summary: the evaluation table, one row
              // per attribute, one column per cycle group.
              CycleSummaryTable(evaluations: evaluations),
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
  _ChartDays(List<DailyEntry> entries, List<CycleMark> marks) {
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
    // Cycle mapping over the whole index range, from the domain's cycle
    // grouping (same groups the Tagebuch list and the evaluation use):
    // every calendar day counts in the cycle whose start is the LATEST
    // group start on or before it — a cycle only ends at the next cycle
    // start, so untracked gap days keep counting from the last start. A
    // group opens at the first tracked day on/after a user-placed
    // cycleStart mark; a mark on an untracked gap day opens the group at
    // the next tracked day (the boundary line still drawn across the gap).
    // The first (leading) group starts at the first recorded day before
    // the first mark, so every index is covered.
    final groups = groupIntoCycles(sorted, marks);
    final starts = [for (final g in groups) DateOnly.normalize(g.startDate)];
    cycleStartDates = {
      // Only mark-opened groups are cycle boundaries; the leading group
      // (predating the first cycleStart mark) is not.
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

  /// The chart day indexes whose temperature is IGNORED: computed from the
  /// `ignoreTemperature` marks (owner decision 2026-09-19 — the mark is
  /// the curve's rendering key; the raw disturbance mask is the diary
  /// badge's input, not
  /// the curve's). A mark on an untracked gap day yields no entry, hence no
  /// curve point — harmless.
  late final Set<int> ignoredDayIndexes;

  /// UTC-midnight of the first recorded day (day index 0).
  late final DateTime firstDay;

  /// Index range length (>= number of recorded days; gaps included).
  late final int dayCount;

  final Map<int, DailyEntry> byIndex = {};

  /// Day of cycle (1, 2, 3 …) per day index, counted from the start of the
  /// cycle group the day belongs to (see the mapping note above).
  final Map<int, int> cycleDayByIndex = {};

  /// The recorded dates at which an individual cycle group opens at a
  /// user-placed cycleStart mark (startsAtMenstruation) — the cycle
  /// separators. Never contains the leading group's start (it predates the
  /// first mark).
  late final Set<DateTime> cycleStartDates;

  DateTime dayAt(int index) => DateOnly.addDays(firstDay, index);

  /// Whether day [index] opens a new cycle (a user-placed cycleStart mark
  /// opens its group there — the shared "is cycle boundary" predicate
  /// driving the card's thick separator lines). The very first recorded
  /// day is never a boundary: there is no line at the recorded range's
  /// left edge (a leading pre-mark group is not a mark-opened group
  /// either). Untracked gap days before a marked day do not hide the
  /// boundary: the grouping opens the group at the next tracked day, and
  /// the predicate matches that day's calendar date wherever it falls.
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
final class _CycleChart extends StatefulWidget {
  const _CycleChart({
    required this.entries,
    required this.marks,
    required this.evaluations,
  });

  final List<DailyEntry> entries;

  /// The user-placed marks, evaluated with [evaluations] by the screen (at
  /// render time, ADR-0001) and shared here with the summary table.
  final List<CycleMark> marks;

  /// The per-cycle evaluations the overlay draws its artifacts from —
  /// computed once per screen build, never re-derived here.
  final List<CycleEvaluation> evaluations;

  @override
  State<_CycleChart> createState() => _CycleChartState();
}

final class _CycleChartState extends State<_CycleChart> {
  /// Narrowest day column still considered usable. Below this width the
  /// day-header labels and the row glyphs would overlap, so a
  /// recorded range longer than one screen scrolls instead of shrinking
  /// further — the day count shown at once derives from the actual layout
  /// width, never from a hard-coded number.
  static const double minDayColumnWidth = 24;

  /// The frozen left rail's width (the paper sheet's fixed left margin):
  /// the rail sits LEFT of the horizontal scroll and carries the header
  /// prototypes, the temperature scale and the rows' name glyphs. The
  /// chart itself reserves NO axis width (left titles are disabled) and
  /// the scrolling content holds only day columns — the tap mapping and
  /// the scroll math are stripless and the plot spans the full content
  /// width.
  static const double frozenRailWidth = 44;

  /// The fixed height of the day/cycle header segment: shared between the
  /// scrolling header row's cells and the rail's prototype slot so both
  /// sides stay vertically in step (the rail's scale segment must start
  /// exactly where the plot starts).
  static const double dayHeaderRowHeight = 28;

  static const Duration _scrollDuration = Duration(milliseconds: 300);

  late _ChartDays _days;
  final ScrollController _scrollController = ScrollController();

  /// Layout snapshot of the last build, for the scroll listener's window
  /// math and the jump-to-date target computation.
  double? _viewportWidth;
  double? _columnWidth;

  /// The day-index window currently built (inclusive bounds). The window
  /// PARKS with an extra screen-width of margin past each visible edge
  /// (the drawn margin rides on the one-day seam margin) and stays put
  /// while the content slides — the scroll-window check below only
  /// rebuilds when the visible edge would run into the margin, so a fling
  /// travels a whole extra screen-width between two window rebuilds
  /// instead of one day column.
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

  /// The jump-to-date affordance lives up in the AppBar actions; the
  /// AppBar sits ABOVE this state in the tree while the jump logic needs
  /// this state's scroll hooks, so this state registers its action in
  /// [cycleChartJumpProvider] while mounted (cleared again on dispose).
  /// Riverpod forbids provider writes inside the widget life-cycle methods,
  /// so both the registration and the unregister run post-frame.
  StateController<void Function(BuildContext context)?>? _jumpRegistration;

  /// Registers [_jumpToDate] as the AppBar's jump affordance (see
  /// [_jumpRegistration]). Post-frame so the provider write happens after
  /// the build sweep; the AppBar picks the callback up on its next rebuild.
  void _registerJumpAffordance() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registration = ProviderScope.containerOf(context, listen: false)
          .read(cycleChartJumpProvider.notifier);
      registration.state = _jumpToDate;
      _jumpRegistration = registration;
    });
  }

  /// Clears the AppBar registration (see [_jumpRegistration]).
  /// Post-frame so the provider write happens outside the teardown sweep;
  /// skipped when the container is gone already (test scope disposal).
  void _unregisterJumpAffordance() {
    final registration = _jumpRegistration;
    _jumpRegistration = null;
    if (registration == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!registration.mounted) return;
      registration.state = null;
    });
  }

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
    _days = _ChartDays(widget.entries, widget.marks);
    _scrollController.addListener(_onScrolled);
    // Register the AppBar's jump affordance (see [_jumpRegistration]).
    _registerJumpAffordance();
    // Data may already be present at mount time: schedule the one-time
    // initial auto-scroll for the end of this frame.
    _scheduleInitialAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _CycleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live entry or mark write re-emits the respective stream while this
    // state is alive: recompute the day mapping so a changed range (or a
    // changed boundary mark) re-windows instead of rendering stale data.
    if (!identical(oldWidget.entries, widget.entries) ||
        !identical(oldWidget.marks, widget.marks)) {
      _days = _ChartDays(widget.entries, widget.marks);
      // Only the FIRST data frame (an initial auto-scroll still pending)
      // may trigger the jump here; once it ran, a later re-emit never
      // re-jumps and the user's position survives.
      _scheduleInitialAutoScroll();
    }
  }

  @override
  void dispose() {
    // The chart is going away — the AppBar must not keep an affordance
    // whose scroll hooks are being disposed.
    _unregisterJumpAffordance();
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

  /// The leftmost day with any pixel on screen (no margin): day cell i
  /// spans [i * colW, (i + 1) * colW) in the stripless scroll content, so
  /// the offset maps straight onto the column grid.
  int _firstVisibleDay(int dayCount) {
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    return (offset / colW).floor().clamp(0, dayCount - 1);
  }

  /// The day-index window to build for the current scroll offset. The
  /// scroll content leads directly with day column 0 (the temperature
  /// scale and the corner glyphs live in the frozen rail outside the
  /// scroll), so the offset maps straight onto the column grid: day cell
  /// i spans [i * colW, (i + 1) * colW).
  ///
  /// Returns the PARKED window ([_windowStart.._windowEnd]) while it still
  /// covers the visible range with the one-day seam margin to spare —
  /// keeping a sufficient window avoids a rebuild for nothing. Otherwise
  /// (fresh state, first scroll, or the visible edge reached the parked
  /// window's margin) it re-parks around the current position: every
  /// column at least partially on screen plus [windowMarginDays] of
  /// margin on each side. A rebuild therefore happens at most once per
  /// extra screen-width of travel, and never leaves the viewport edge
  /// without a built column (the seam guarantee).
  (int, int) _windowFor(int dayCount) {
    final viewport = _viewportWidth ?? 0;
    final colW = _columnWidth ?? minDayColumnWidth;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final firstVisible = _firstVisibleDay(dayCount);
    // The last column with any pixel on screen: day i's column START is
    // left of the viewport's right edge — i.e. i < (offset + viewport) /
    // colW, so the largest such i is one below that quotient's ceil (a
    // quotient landing exactly on an integer excludes the column starting
    // exactly at the right edge — nothing of it is visible).
    final lastVisible = (((offset + viewport) / colW).ceil() - 1)
        .clamp(firstVisible, dayCount - 1);
    final parkedStart = math.min(_windowStart, dayCount - 1);
    final parkedEnd = math.min(_windowEnd, dayCount - 1);
    // Still sufficient? The parked window must cover the visible range
    // plus the one-day seam margin on each side — where such a column
    // exists at all (at the range's edges there is nothing beyond the
    // first/last day to cover, so the check clamps there too).
    final leftNeeded = math.max(0, firstVisible - 1);
    final rightNeeded = math.min(dayCount - 1, lastVisible + 1);
    if (parkedStart < parkedEnd &&
        leftNeeded >= parkedStart &&
        rightNeeded <= parkedEnd) {
      return (parkedStart, parkedEnd);
    }
    // Re-park around the current position.
    final margin = windowMarginDays(viewport, colW);
    return (
      math.max(0, firstVisible - 1 - margin),
      math.min(dayCount - 1, lastVisible + 1 + margin),
    );
  }

  /// The window margin in day columns: one extra screen-width (what the
  /// viewport shows) rounded UP to whole columns, so the parked window is
  /// re-built only after the content travels a full extra screen — during
  /// a fling that means a handful of rebuilds instead of one per column.
  /// A fresh park always carries the margin past the visible edge; the
  /// one-day seam margin rides on top, so a rebuild also never introduces
  /// a seam at the viewport edge. Derived from the LIVE viewport and
  /// column width rather than a fixed constant: a phone and a wide
  /// desktop window then both carry the same one-screen lead, and no
  /// constant guess at a maximum viewport width wastes cells.
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

  /// Translates a tap on the chart's plot area into a day index and opens
  /// the day's sheet. The overlay covers the whole scroll content (the
  /// plot spans it fully — the scale lives in the frozen rail outside the
  /// scroll); the chart's x domain is half a column SHIFTED
  /// (minX −0.5 .. maxX dayCount − 0.5), so the tap's local x maps linearly
  /// onto a fractional day index d whose integer parts are the columns'
  /// centers: day i's column spans d in [i − 0.5, i + 0.5). The nearest
  /// day column wins, exactly like the row cells underneath.
  void _openDayAtLocalX(double localX, double plotWidth) {
    final t = (localX / plotWidth).clamp(0.0, 1.0);
    final d = -0.5 + t * _days.dayCount;
    final index = d.round().clamp(0, _days.dayCount - 1);
    _openDaySheet(index);
  }

  /// The jump-to-date affordance (the AppBar's date-range button, see
  /// [cycleChartJumpProvider]): opens the material date picker bounded to
  /// the recorded range and scrolls the window so the picked day is centered.
  Future<void> _jumpToDate(BuildContext context) async {
    if (!mounted) return;
    final viewport = _viewportWidth;
    final colW = _columnWidth;
    if (viewport == null || colW == null) return;
    final firstDay = _days.firstDay;
    final lastDay = _days.dayAt(_days.dayCount - 1);
    // Initial pick: the leftmost VISIBLE day, not the marined window's
    // start — the window carries an extra screen-width of margin past the
    // visible edge, and the picker should open on the day the user is
    // looking at (see [_firstVisibleDay]).
    final initial = _days.dayAt(
        math.min(_firstVisibleDay(_days.dayCount), _days.dayCount - 1));
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
    // (index + 0.5) * colW in the stripless scroll content, and centering
    // places it at the viewport's middle.
    final target = ((index + 0.5) * colW - viewport / 2)
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
    // watched once in the screen, which also derives the evaluations the
    // summary table shows; both arrive as widget fields, so the curve
    // itself still never depends on a mark change beyond a screen rebuild.
    final overlay = buildEvaluationOverlay(
      evaluations: widget.evaluations,
      marks: widget.marks,
      firstDay: _days.firstDay,
      dayCount: _days.dayCount,
    );

    // The curve is split into runs of adjacent measured days (curve helpers,
    // lib/ui/cycle_curve.dart): the line connects two temperatures only when
    // their calendar days are adjacent, so a day without a temperature
    // (missing entry or entry without bbtC) breaks the line. This global
    // structure feeds the Y bounds: the scale must cover the whole recorded
    // range so scrolling never rescales the curve.
    final runs =
        curveRuns(_days.byIndex, ignoredDayIndexes: _days.ignoredDayIndexes);
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
    final chartHeight =
        (chartBaseHeight + math.max(0.0, yMax - yMin - comfortableYSpan) * 80.0)
            .clamp(chartBaseHeight, chartHeightCap);

    // One source of truth for the temperature scale: the chart's y domain
    // over the plot height feeds BOTH the chart config and the frozen
    // rail's scale labels (see _TemperatureScale).
    final scale =
        _TemperatureScale(min: yMin, max: yMax, plotHeight: chartHeight);

    // Ignored (marked) TEMPERATURES read lighter: the scheme color at the
    // shared lighter alpha (owner decision 2026-09-19: the
    // ignoreTemperature mark is the rendering key). The dark scheme's
    // primary is a bright color, so
    // the dimmed tint still keeps darkness-readable contrast (asserted by
    // the dark-mode chart tests).
    final temperatureColor = Theme.of(context).colorScheme.primary;
    final interruptedColor =
        temperatureColor.withValues(alpha: ignoredTemperatureAlpha);
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
        // The scroll viewport: the full block width minus the frozen rail
        // that sits left of the scroll view.
        final scrollViewport = viewport - frozenRailWidth;
        _viewportWidth = scrollViewport;
        final dayCount = _days.dayCount;
        // Useful day columns: at most as many days as fit the scroll
        // viewport at the minimum usable width; a longer range keeps that
        // width and scrolls horizontally instead of squeezing. The scroll
        // content holds only day columns (the rail is outside).
        final overflow = dayCount * minDayColumnWidth > scrollViewport;
        final colW = overflow ? minDayColumnWidth : scrollViewport / dayCount;
        _columnWidth = colW;
        // The scroll content: one column per day. In the fitting case that
        // is exactly the scroll viewport (nothing scrolls); the explicit
        // viewport keeps the no-scroll case free of floating-point slack
        // that a recomputed sum could introduce.
        final contentWidth = overflow ? dayCount * colW : scrollViewport;
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
        final winRuns =
            curveRuns(winByIndex, ignoredDayIndexes: _days.ignoredDayIndexes);
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
            // The paper sheet's layout: the fixed left margin (the frozen
            // rail) next to the sliding day columns. The rail carries the
            // header prototypes, the temperature scale and the rows' name
            // glyphs — everything that used to sit in the scrolling
            // content's leading 44 px strips, so the scale never scrolls
            // away (the owner-reported defect).
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
                          // The day/cycle header ABOVE the curve (the
                          // paper's header row): day of month + day of
                          // cycle per column; the prototypes live in the
                          // rail.
                          _DayHeaderRow(
                            days: _days,
                            cellWidth: colW,
                            windowStart: winStart,
                            windowEnd: winEnd,
                          ),
                          const SizedBox(height: 4),
                          // INSIDE the top of the temperature block (the
                          // paper sheet's grid rows above the temperature
                          // body): bleeding, mucus (with the reserved solid
                          // peak-dot slot above the glyph), the
                          // Mittelschmerz letter M on its own row directly
                          // beneath the mucus row, and sex. No gap between
                          // the rows and the plot: the paper's rows ARE
                          // part of the temperature grid, so the rows and
                          // the curve read as one block (the rows carry the
                          // same day-cell separators as the chart's vertical
                          // grid lines).
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
                                            FlSpot(
                                                segment.a.dayIndex.toDouble(),
                                                segment.a.bbtC),
                                            FlSpot(
                                                segment.b.dayIndex.toDouble(),
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
                                      for (final segment
                                          in overlay.baselineSegments)
                                        LineChartBarData(
                                          spots: [
                                            FlSpot(
                                                math.max(-0.5,
                                                    segment.startIndex - 0.5),
                                                segment.value),
                                            FlSpot(
                                                math.min(lastX,
                                                    segment.endIndex + 0.5),
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
                                            FlSpot(suz.barX.clamp(-0.5, lastX),
                                                yMin),
                                            FlSpot(suz.barX.clamp(-0.5, lastX),
                                                yMax),
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
                                            FlSpot(
                                                suz.barX.clamp(-0.5, lastX),
                                                suz.arrowValueY ??
                                                    (yMin + yMax) / 2),
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
                                    minY: scale.min,
                                    maxY: scale.max,
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
                                    // use). No line before the first
                                    // cycleStart mark (the leading group is
                                    // not a boundary), and a boundary opened
                                    // after untracked gap days is drawn
                                    // across the gap.
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
                                      // The temperature scale does NOT render
                                      // here anymore: the frozen rail paints it
                                      // (from the shared _TemperatureScale), so
                                      // it stays fixed while the columns scroll.
                                      // No width is reserved — the plot spans the
                                      // full scroll content width.
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          reservedSize: 0,
                                          showTitles: false,
                                        ),
                                      ),
                                      topTitles: const AxisTitles(),
                                      rightTitles: const AxisTitles(),
                                      // The per-day column labels (day of month +
                                      // day of cycle) render in _DayHeaderRow
                                      // ABOVE the chart instead of fl_chart's
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
                                // The tap overlay covers the whole scroll
                                // content: the plot spans it fully (no axis
                                // strip left of the plot — the scale lives in
                                // the frozen rail outside the scroll).
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) => _openDayAtLocalX(
                                        details.localPosition.dx, contentWidth),
                                    onLongPressStart: (details) =>
                                        _openDayAtLocalX(
                                            details.localPosition.dx,
                                            contentWidth),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // The 1–6 low numbering, directly under the chart
                          // day columns. Like the signal rows it renders only
                          // the scroll window's cells — the window spacer
                          // keeps them at the global column positions, so a
                          // window rebuild only adds/removes cells in place;
                          // the numbering semantics are untouched
                          // (lib/ui/cycle_marks.dart builds the row).
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
                          // BELOW the curve, outside the paper sheet's grid:
                          // the rows the sheet does not carry (cervix and
                          // the breast pain letter B; the Mittelschmerz
                          // letter M moved into the top block above —
                          // TODO(user-review): the experts may want M
                          // rendered here as well).
                          _SignalRows(
                            kinds: _belowCurveKinds,
                            days: _days,
                            cellWidth: colW,
                            windowStart: winStart,
                            windowEnd: winEnd,
                            peakIndexes: overlay.peakIndexes,
                            onDayTap: _openDaySheet,
                          ),
                          const SizedBox(height: 4),
                          // The measurement-time row, its own row BELOW the
                          // chart block (the paper's strip under the grid;
                          // narrow columns write the time vertically).
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

/// The paper layout's row segments: INSIDE the top of the temperature
/// block the sheet's grid rows — bleeding, mucus (with the reserved solid
/// peak-dot slot above the glyph), the Mittelschmerz letter M directly
/// beneath the mucus row, and sex (the same order the rows render in).
/// TODO(user-review): the M letter's home (own row beneath the mucus row)
/// is an owner-eyeball choice; the paper writes it under the mucus letters
/// and clinicians may prefer it in the below-block pain row too.
const _topSignalKinds = <_SignalKind>[
  _SignalKind.bleeding,
  _SignalKind.mucus,
  _SignalKind.mittelschmerz,
  _SignalKind.sex,
];

/// Below the curve, outside the paper grid: the rows the sheet does not
/// carry — cervix and the breast pain letter B — and at the very bottom
/// of the chart block the disturbance row (the paper writes its
/// disturbance codes low inside the temperature block).
const _belowCurveKinds = <_SignalKind>[
  _SignalKind.cervix,
  _SignalKind.pain,
  _SignalKind.disturbance,
];

/// BELOW the chart block entirely (the paper's strip under the grid):
/// the measurement time, and — at the very bottom, the paper sheet's
/// remarks ("Bemerkungen") home — the day-note indicator.
/// TODO(user-review): the note indicator's home (own row below the time
/// row, mirroring the paper sheet's bottom remarks block) is an
/// owner-eyeball choice; the experts may prefer it elsewhere (e.g. in the
/// day-header column).
const _belowChartKinds = <_SignalKind>[_SignalKind.time, _SignalKind.note];

/// One recording row per segment signal, top-down in segment order. Every
/// row renders for every day (auto-hide of unused rows is deferred),
/// aligned by the same even day spacing as the chart: the rows hold ONLY
/// day cells (their name glyphs and the localized row names live in the
/// frozen left rail, positioned over each row's vertical slot via the
/// shared height constants below), and the windowed day cells sit at the
/// curve's global column positions (cell i is centered at
/// (i + 0.5) * cellWidth — exactly where the chart draws day i's dot).
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

  /// The segment's rows, top-down (paper sheet order within the segment).
  final List<_SignalKind> kinds;

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
      for (final kind in kinds)
        Padding(
          padding: EdgeInsets.only(
              top: kind == kinds.first ? 0 : _signalRowGap),
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

/// The recording rows' fixed heights, shared between the scrolling rows and
/// the frozen left rail: the rail positions each row's name glyph at the
/// row's vertical slot, so a layout change here must move both sides or the
/// rail's alignment test fails.
const double _signalRowGap = 2;

/// The fixed height a signal row's day cells occupy (mucus reserves the
/// solid peak-dot slot above the glyph, R6: dot slot 10 + gap 2 + glyph 12;
/// the disturbance row reserves two letter slots so a two-code day renders
/// unscaled — more codes shrink to fit, see _disturbanceContent; the time
/// row reserves the height of a VERTICALLY written HH:mm text — its width
/// becomes the cell height when the column is narrow, see _timeContent).
double _signalRowHeight(_SignalKind kind) => switch (kind) {
      _SignalKind.mucus || _SignalKind.disturbance => 24,
      _SignalKind.time => 30,
      _ => 12,
    };

/// The vertical offset of a row's top inside its segment: the rows stack
/// top-down with the shared gap between them (mirrors _SignalRows'
/// inter-row padding).
double _signalRowTop(_SignalKind kind, List<_SignalKind> kinds) {
  var top = 0.0;
  for (final k in kinds) {
    if (k == kind) break;
    top += _signalRowHeight(k) + _signalRowGap;
  }
  return top;
}

/// A segment's total height — the rail's glyph segment must match it.
double _signalSegmentHeight(List<_SignalKind> kinds) => kinds.fold(
    0.0, (h, kind) => h + _signalRowHeight(kind) + _signalRowGap) -
    (kinds.isEmpty ? 0 : _signalRowGap);

/// The recording signals, with the row ORDER grouped by segment (paper
/// order within each segment: the top block bleeding → mucus → M → sex;
/// below the curve cervix → pain; below the chart block the measurement
/// time). The enum's declaration order matches the full render order.
enum _SignalKind {
  bleeding,
  mucus,
  mittelschmerz,
  sex,
  cervix,
  pain,
  disturbance,
  time,
  note,
}

/// Test-visible key prefix of a row's day cells: `bleedingCell-3`,
/// `mucusCell-3`, …
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

/// Test-visible key prefix of a row's 44 px corner slot: `bleedingCorner`,
/// `mucusCorner`, …
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

/// The localized row name for a signal (the corner tooltip/semantics
/// label).
// TODO(user-review): the row-name wording is a first draft mirroring the
// entry form's vocabulary; the experts may want different names.
String _signalRowName(_SignalKind kind, AppLocalizations l10n) =>
    switch (kind) {
      _SignalKind.bleeding => l10n.cycleRowBleeding,
      _SignalKind.mucus => l10n.cycleRowMucus,
      _SignalKind.mittelschmerz => l10n.cycleRowMittelschmerz,
      _SignalKind.sex => l10n.cycleRowSex,
      _SignalKind.cervix => l10n.cycleRowCervix,
      _SignalKind.pain => l10n.cycleRowPain,
      _SignalKind.disturbance => l10n.cycleRowDisturbance,
      _SignalKind.time => l10n.cycleRowMeasurementTime,
      _SignalKind.note => l10n.cycleRowNote,
    };

/// A signal row's sample glyph, rendered in the frozen left rail at the
/// row's vertical slot.
Widget _signalCornerSample(BuildContext context, _SignalKind kind) {
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
    // Sample glyph: plain S, matching the sign glyph a recorded mucus day
    // renders (no quality qualifier).
    _SignalKind.mucus => MucusSymbolText(
        display: mucusDisplay(sign: MucusSign.s),
        fontSize: 10,
        color: scheme.tertiary,
      ),
    // Sample Muttermund glyph: the "medium" letter, exactly how a
    // recorded cervix day renders in the row's cells.
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
    // Sample disturbance glyph: the first letter code of today's
    // vocabulary (disturbanceLetters below) — the per-day cells stack one
    // code per set exclusion flag.
    _SignalKind.disturbance => Text(
        'kr',
        style: TextStyle(fontSize: 10, color: scheme.onSurface),
      ),
    // The rail keeps a clock icon sample; the per-day cells show the
    // recorded time as text (wide columns) or vertically (narrow ones).
    _SignalKind.time => Icon(Icons.schedule, size: 12, color: scheme.onSurface),
    // Sample note glyph: the same sticky-note icon a noted day renders in
    // its cell.
    _SignalKind.note => Icon(
        Icons.sticky_note_2_outlined,
        size: 12,
        color: scheme.onSurface,
      ),
  };
}

/// The day-column width boundary between the measurement-time row's
/// HORIZONTAL and VERTICAL rendering: below it the HH:mm text renders
/// rotated (RotatedBox), so the recorded time stays visible even at the
/// minimum usable column width (24 px) — the old behavior dropped the
/// text entirely there (the space-constraint bug; see _timeContent).
// TODO(user-review): the threshold is a tuned display heuristic, not a
// rule from the cheat sheet.
const double _timeCellMinColumnWidth = 32;

/// The temperature-disturbance letter codes of a day, one per set
/// exclusion flag, in the render order the disturbance row stacks them:
/// TODAY'S vocabulary — illness → "kr", alcohol → "alk", travel → "R"
/// (the paper sheet writes "Reise" in full, narrow columns shorten it to
/// R), other → "a".
///
/// THE single seam for the letter vocabulary: the pending NER-scheme
/// data-entry item re-models the exclusion flags (sp/a/alk/kr, Reise
/// dropped, intflag field) — it retargets THIS function (and the glossary
/// entry), nothing else on the chart. Nothing on the chart interprets the
/// letters; they are raw-observation display only (ADR-0001).
/// TODO(user-review): the letter vocabulary mirrors the paper sheet's
/// disturbance codes; the experts may want different ones.
List<String> disturbanceLetters(DailyEntry? day) => day == null
    ? const []
    : [
        if (day.excludeIllness) 'kr',
        if (day.excludeAlcohol) 'alk',
        if (day.excludeTravel) 'R',
        if (day.excludeOther) 'a',
      ];

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

  /// Day indexes carrying the mucus-peak mark (R6): they render the solid
  /// peak dot above the mucus glyph. Only read by the mucus row.
  final Set<int> peakIndexes;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          color: bleeding == Bleeding.none ? Colors.transparent : bleedingColor,
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
  /// No collision with the disturbance codes: interrupted days render as
  /// LIGHTER CURVE POINTS in the plot, and their letter codes live in the
  /// disturbance row at the bottom of the chart block — never in this
  /// cell.
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

  /// Pain: the breast pain letter B — the letter-coded pain option of the
  /// cheat sheet that still renders in this below-curve row. The
  /// Mittelschmerz letter M renders in its OWN row directly beneath the
  /// mucus row, inside the top of the temperature block (the paper sheet
  /// writes M under the mucus letters; TODO(user-review): the M's home is
  /// an owner-eyeball choice, the below-block row here could carry it too
  /// if the experts want it twice). The UPPERCASE letter keeps it
  /// distinguishable from the lowercase cervix letters in the cervix row
  /// below; the row shares the same neutral on-surface ink (no scheme hue
  /// claimed).
  /// TODO(user-review): the letter mirrors the vocabulary of the entry
  /// form ("Brustschmerzen (B)") — the same ad-hoc glyph caveat as the
  /// cervix letters applies.
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

  /// Mittelschmerz: the letter M of the cheat sheet, rendered in its own
  /// row directly beneath the mucus row inside the top of the temperature
  /// block (the paper sheet writes M under the mucus letters — this home
  /// is flagged TODO(user-review) on the segment constants above).
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

/// Disturbance: the stacked letter codes of the day's exclusion flags
/// ([disturbanceLetters]) — the paper sheet writes disturbance codes one
/// under the other. Neutral on-surface ink. The row's fixed height fits
/// two codes unscaled; more codes shrink to fit (FittedBox) rather than
/// overflow or drop. The excluded temperatures themselves keep rendering
/// as LIGHTER curve dots in the plot (unchanged curve behavior; these
/// letters only NAME the reason).
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

  /// Measurement time: the localized HH:mm text of a recorded
  /// temperature-measurement time, rendered in the time row BELOW the
  /// chart block. Narrow day columns (below [_timeCellMinColumnWidth],
  /// including the 24 px minimum) write the time VERTICALLY (RotatedBox,
  /// reading bottom-to-top like the paper's vertical strip handwriting)
  /// so the time is never dropped at the space constraint; wide columns
  /// keep the horizontal text. measuredAtMinutes is normalized to exist
  /// only together with bbtC (the DailyEntry constructor drops a time
  /// without a temperature), so the text never claims a time for a
  /// temperature-free day. The per-day clock icon is gone — the icon
  /// lives only in the row's corner sample.
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
      // Vertical: the rotated text needs roughly the text's WIDTH as its
      // cell height, so the row height constant reserves that space
      // (_signalRowHeight for the time kind); FittedBox keeps any
      // unexpectedly long text inside the cell.
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: RotatedBox(quarterTurns: 3, child: text),
      );
    }
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }

  /// Note indicator: a small sticky-note glyph for a day whose entry
  /// carries a NON-EMPTY notes text (empty/absent render nothing). The
  /// row sits below the measurement-time row — the paper sheet's remarks
  /// (Bemerkungen) block is the very bottom (TODO(user-review): flagged
  /// on _belowChartKinds). Tapping the cell opens the day's mark-entry
  /// sheet like every other cell; the note text itself is edited in the
  /// Tagebuch form (the sheet's "edit day" jump).
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
/// plain day number (owner decision). The two column prototypes (date
/// sample "14.", cycle-day sample "#5") live in the frozen left rail's
/// header slot (see _LeftRail).
/// TODO(user-review): the prototypes ("14.", "#5") are ad-hoc column
/// samples; the experts may want different header prototypes.
/// Mirrors the signal rows' windowed layout: the window spacer puts the
/// cells at their global positions (cell i is centered at
/// (i + 0.5) * cellWidth — exactly where the chart draws day i's dot), and
/// only the window's cells are built. The row's cells share the fixed
/// [_CycleChartState.dayHeaderRowHeight] with the rail's header slot so
/// the segments stay vertically in step.
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
        // The window spacer keeps the header cells at their global column
        // positions (mirrors the other rows' window offset).
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        // The cell key exposes the whole label column per day index for the
        // widget tests (same convention as the signal-row cells below).
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('dayLabel-$i'),
            width: cellWidth,
            height: _CycleChartState.dayHeaderRowHeight,
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
}

/// One prototype cell in the frozen rail's header slot: the sample glyph
/// with its tooltip (long-press) and its semantics label.
Widget _columnPrototype({
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
// --- temperature scale (chart domain + frozen-rail labels) ------------------

/// The temperature scale's single source of truth: the chart's y domain
/// (rounded half degrees) over the plot height feeds BOTH the chart config
/// (minY/maxY) and the frozen rail's scale labels, so the rail's labels and
/// the curve can never disagree about where a value sits. fl_chart maps
/// values linearly over the plot area, and the rail uses the identical
/// mapping ([pixelFor] — the plot reserves no axis width because its left
/// titles are disabled, so the plot rect is the chart widget's rect).
final class _TemperatureScale {
  const _TemperatureScale({
    required this.min,
    required this.max,
    required this.plotHeight,
  });

  /// The chart's lower y bound (a rounded half degree, ≥ 34).
  final double min;

  /// The chart's upper y bound (a rounded half degree, ≤ 42).
  final double max;

  /// The plot area's height in pixels.
  final double plotHeight;

  /// The pixel y (measured from the plot's TOP edge) of a temperature
  /// value: the same linear map fl_chart's painter applies
  /// (pixelY = plotHeight − (value − min) / span * plotHeight).
  double pixelFor(double value) => (max - value) / (max - min) * plotHeight;

  /// The scale's tick values: every half degree across the domain (both
  /// bounds are rounded half degrees upstream, so the step count is exact;
  /// the degenerate single-value record is guarded by min < max in the
  /// bounds computation).
  List<double> get ticks =>
      [for (var k = 0; k <= ((max - min) * 2).round(); k++) min + k * 0.5];

  /// The two-scale label for a tick: integers plain ("37"), halves with one
  /// decimal ("36.5") — the numbering the chart's own axis titles used.
  String labelFor(double value) => _formatHalfDegree(value);
}

// --- frozen left rail --------------------------------------------------------

/// The frozen left rail: the paper sheet's fixed left margin, rendered
/// OUTSIDE the horizontal scroll next to the day columns. It carries
/// everything that must never slide away with the content — the header
/// prototypes, the temperature scale (from the shared [_TemperatureScale])
/// and the signal rows' name glyphs — each in a vertical slot mirroring the
/// scroll content's segment heights (the header slot, the marks row slot
/// and the per-row heights are shared constants, so the rail's glyphs stay
/// aligned with their rows; the alignment is pinned by the rail's widget
/// test).
/// TODO(user-review): the rail's right-edge hairline (mirroring the day
/// grid's hairline style) is an owner-eyeball rendering detail — the paper
/// sheet's margin rule is heavier.
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
        // The rail's right-edge hairline, mirroring the day-grid hairlines
        // so the scrolling content meets the rail cleanly.
        // TODO(user-review): border style/thickness is an owner-eyeball
        // rendering detail.
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              width: 0.5,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The header slot: the two column prototypes (same tooltips and
            // semantics labels as before — the corner slot moved here from
            // the scrolling header row).
            SizedBox(
              key: const ValueKey('dayHeaderCorner'),
              height: _CycleChartState.dayHeaderRowHeight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _columnPrototype(
                      prototype: '14.', label: l10n.cycleColumnDate),
                  _columnPrototype(
                      prototype: '#5', label: l10n.cycleColumnCycleDay),
                ],
              ),
            ),
            // The gap between the header segment and the rows inside the
            // top of the temperature block, mirroring the content column's
            // spacer.
            const SizedBox(height: 4),
            // The name glyphs of the rows INSIDE the top of the temperature
            // block (bleeding, mucus, M, sex — paper sheet order), above
            // the temperature scale, mirroring the content column.
            _railSignalSegment(context, l10n, _topSignalKinds),
            // The temperature scale: one label per half degree, positioned
            // at its value's plot pixel y (the shared mapping) — the
            // owner-reported defect this rail fixes: the scale no longer
            // scrolls away with the day columns. The scale starts exactly
            // where the plot bar starts (right after the top rows).
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
                                'railScaleLabel-${scale.labelFor(value)}'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The marks-row slot: empty in the rail (the 1–6 numbering is
            // per-day content), but kept so the glyph segment below starts
            // exactly where the rows below the curve start.
            const SizedBox(height: 4),
            SizedBox(height: EvaluationMarksRow.cellHeight),
            const SizedBox(height: 4),
            // The name glyphs of the rows BELOW the curve (cervix, pain —
            // the rows the paper sheet does not carry in its grid),
            // mirroring the content column's below-curve segment.
            _railSignalSegment(context, l10n, _belowCurveKinds),
            const SizedBox(height: 4),
            // The name glyphs of the rows BELOW the chart block (the
            // measurement time and, at the very bottom, the day-note
            // indicator — the paper's strip under the grid and its remarks
            // block).
            _railSignalSegment(context, l10n, _belowChartKinds),
          ],
        ),
      ),
    );
  }

  /// The rail glyph stack for one row segment: the segment's name glyphs,
  /// each vertically centered on the row's slot (shared row heights, same
  /// offsets the scrolling rows stack with).
  Widget _railSignalSegment(
      BuildContext context, AppLocalizations l10n, List<_SignalKind> kinds) {
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
                    child: Center(
                      child: _signalCornerSample(context, kind),
                    ),
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

String _formatHalfDegree(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

double _floorToHalf(double v) => (v * 2).floorToDouble() / 2;

double _ceilToHalf(double v) => (v * 2).ceilToDouble() / 2;
