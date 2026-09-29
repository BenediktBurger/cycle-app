// Zyklus screen: the paper-style temperature curve with the day/cycle
// header above it, bleeding as the one recording row above the plot and
// the raw-observation glyphs INSIDE the temperature plot (sex X marks,
// mucus sign letters, mucus peak dot, the Mittelschmerz M and the
// evaluation 1–6 day numbering — chart_marks.dart, _InPlotGlyphRows).
// Under the curve comes the single below-chart strip (measurement time,
// disturbance letters, cervix, pain, day-note indicator) — as with every
// row the raw observations are pure recordings. The COMPUTED
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
    final marks = marksAsync.value ?? const <CycleMark>[];
    // This is the screen's ONLY marks watch — the whole screen rebuilds on
    // a mark change, the overlay recomputes from the shared derived pass.
    // The settings values are watched here because the chart takes them as
    // constructor data (no riverpod dependency of its own).
    final temperatureRange = ref.watch(temperatureRangeProvider);
    final derived = ref.watch(derivedCycleDataProvider);
    // The chart's day mapping alone stops at the last tracked entry, while
    // the shared derived pass's cycle day lists already carry the span
    // rule's placeholder days out to today (lib/domain/cycle_grouping.dart)
    // — the same lists the diary tab renders. Merging them gives the chart
    // the shared range instead of re-deriving a "today" end in the UI; a
    // tracked entry keeps its date's slot, so a placeholder never covers
    // real data.
    final byDay = <DateTime, DailyEntry>{
      for (final cycle in derived.cycles)
        for (final day in cycle.days) DateOnly.normalize(day.date): day,
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
    return ListView(
      padding: const EdgeInsets.all(12),
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
        if (panelDay != null)
          CycleDayPanel(
            key: const ValueKey('cycleDayPanel'),
            day: panelDay,
            onClose: () => ref.read(cycleDayPanelProvider.notifier).set(null),
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
