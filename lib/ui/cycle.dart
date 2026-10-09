// Zyklus screen: the paper-style temperature curve with the day/cycle
// header above it, bleeding as the one recording row above the plot and
// the raw-observation glyphs INSIDE the temperature plot (sex X marks,
// mucus sign letters, mucus peak dot, the Mittelschmerz M and the
// evaluation 1–6 day numbering — chart_marks.dart, _InPlotGlyphRows).
// Under the curve comes the single below-chart strip (measurement time,
// disturbance letters, then the merged notes band) — as with
// every row the raw observations are pure recordings. The COMPUTED
// evaluation overlay (Mode M, ADR-0001) draws the user's mucus-peak and
// first-higher marks' derived artifacts for DISPLAY ONLY — never persisted;
// it is derived in lib/domain/evaluation_overlay.dart over evaluateCycles
// and painted by lib/ui/cycle_marks.dart (the SUZ arithmetic stays
// domain-only; a manual SUZ mark never alters it).
//
// Tapping a chart day or a signal-row cell shows the day options in the
// NON-MODAL panel the screen owns (lib/ui/cycle_mark_sheet.dart,
// cycleDayPanelProvider), docked at the bottom of the screen as a fixed
// card in front of the chart list — a day tap never scrolls the list,
// tapping another day retargets the dock in place.
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
import '../domain/temperature_range.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'bleeding_symbol.dart';
import 'chart_marks.dart';
import 'cycle_curve.dart';
import 'cycle_help_sheet.dart';
import 'cycle_mark_sheet.dart';
import 'cycle_marks.dart';
import 'mucus_symbol.dart';
import 'stream_error.dart';

part 'cycle_day_mapping.dart';
part 'cycle_recording_rows.dart';
part 'cycle_chart.dart';

class ZyklusScreen extends ConsumerStatefulWidget {
  const ZyklusScreen({super.key});

  @override
  ConsumerState<ZyklusScreen> createState() => _ZyklusScreenState();
}

final class _ZyklusScreenState extends ConsumerState<ZyklusScreen> {
  /// The open dock's measure probe: its laid-out height feeds the chart
  /// list's bottom padding (the rows the dock covers stay reachable by
  /// scrolling the list, which a day tap never does).
  final GlobalKey _dockKey = GlobalKey();

  /// The dock's last measured height (null before the first measure or
  /// right after a retarget's next frame); as list padding a stale value
  /// costs one imprecise frame, never a jump.
  double? _dockHeight;

  @override
  Widget build(BuildContext context) {
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
          // Unmasked so a failed marks stream surfaces in place of the
          // chart block; the docked panel stays mounted regardless.
          final marksAsync = ref.watch(marksProvider);
          return _liveCycleList(context, ref, entries, marksAsync);
        },
      ),
    );
  }

  /// The live list of one recorded range — chart plus the day-options
  /// dock fixed in front of it, computed from the shared derived pass. The
  /// dock overlays the bottom of the surface at a constant scroll offset
  /// (the chart region's size never changes with a day tap); the covered
  /// rows stay reachable through the list's bottom padding, which tracks
  /// the dock's measured height. On a failed marks stream the chart block
  /// is replaced by the retry surface instead of painting an overlay over
  /// silently-empty data.
  Widget _liveCycleList(
    BuildContext context,
    WidgetRef ref,
    List<DailyEntry> entries,
    AsyncValue<List<CycleMark>> marksAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    final marks = marksAsync.value ?? const <CycleMark>[];
    // This is the screen's ONLY marks watch — the whole screen rebuilds on
    // a mark change, the overlay recomputes from the shared derived pass.
    // The settings values are watched here because the chart takes them as
    // constructor data (no riverpod dependency of its own).
    final temperatureRange = ref.watch(temperatureRangeProvider);
    final derived = ref.watch(derivedCycleDataProvider);
    // The chart's day mapping covers only the entries it is given, so the
    // merge feeds it each derived cycle's full calendar span
    // ([cycleSpanDays] — lib/domain/cycle_grouping.dart), the same span
    // lists the diary tab renders. That keeps the shared span rule's end
    // instead of re-deriving a "today" end in the UI; a tracked entry
    // keeps its date's slot, so a data-less span day never covers real
    // data.
    final byDay = <DateTime, DailyEntry>{
      for (final cycle in derived.cycles)
        for (final day in cycleSpanDays(cycle))
          DateOnly.normalize(day.date): day,
    };
    for (final entry in entries) {
      byDay[DateOnly.normalize(entry.date)] = entry;
    }
    final chartEntries = [...byDay.values];
    if (chartEntries.isEmpty) {
      // Error beats "no data": with entries empty the ListView's marks
      // error branch never renders, so surface the retry here.
      if (marksAsync.hasError) {
        return StreamLoadError(
          scope: 'marks',
          onRetry: () => ref.invalidate(marksProvider),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.cycleNoData),
        ),
      );
    }
    final observedCyclesOutsideApp = ref.watch(
      observedCyclesOutsideAppProvider,
    );
    final panelDay = ref.watch(cycleDayPanelProvider);
    if (panelDay != null) _scheduleDockMeasure();
    return LayoutBuilder(
      builder: (context, constraints) {
        // The dock's height cap: ~60% of the body space above its bottom
        // offset — from the layout constraints (an AppBar- or
        // keyboard-shrunk body counts), which MediaQuery.sizeOf would miss.
        final dockBottom = 12 + MediaQuery.paddingOf(context).bottom;
        final maxDockHeight = math.max(
          0.0,
          (constraints.maxHeight - dockBottom) * 0.6,
        );
        return Stack(
          children: [
            Positioned.fill(
              // Chart content only: an open dock is not a list child, so the
              // list keeps its scroll offset across opens, retargets and mark
              // writes that re-render the chart. While the dock shows, the
              // bottom padding clears the dock (its measured height, plus the
              // 12 dp margin and gap) so the covered rows stay reachable by
              // scrolling.
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  panelDay == null ? 12 : (_dockHeight ?? 0) + 24,
                ),
                children: [
                  marksAsync.when(
                    loading: () => _CycleChart(
                      entries: chartEntries,
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
                      entries: chartEntries,
                      marks: markers,
                      evaluations: derived.evaluations,
                      cycles: derived.cycles,
                      range: temperatureRange,
                      observedCyclesOutsideApp: observedCyclesOutsideApp,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (panelDay != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: dockBottom,
                child: KeyedSubtree(
                  key: _dockKey,
                  child: CycleDayPanel(
                    key: const ValueKey('cycleDayPanel'),
                    day: panelDay,
                    maxHeight: maxDockHeight,
                    onClose: () =>
                        ref.read(cycleDayPanelProvider.notifier).set(null),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Reads the dock's laid-out height after the current build sweep and
  /// publishes it into [_dockHeight] (only on change, so mark writes that
  /// re-render the panel do not rebuild the screen).
  void _scheduleDockMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dockHeight = _dockKey.currentContext?.size?.height;
      if (dockHeight == null || dockHeight == _dockHeight) return;
      setState(() => _dockHeight = dockHeight);
    });
  }
}
