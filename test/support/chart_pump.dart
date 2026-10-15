// Shared chart pump harness: one scope wiring for the cycle-chart widget
// tests. Every chart test pumps the ZyklusScreen with the same three stream
// overrides (daily entries, marks, selected date) plus the app's MaterialApp
// wiring (localization delegates, en locale, seeded color scheme).
//
// The parameters below cover the shapes the tests grew into: ProviderScope
// outside vs. inside the MaterialApp, an optional dark scheme, and
// optionally no theme wiring at all.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'provider_fixtures.dart';

/// The seed color of the app's scheme (lib/main.dart), pinned so tests can
/// reach the same ColorScheme the charts render with.
const chartSeedColor = Color(0xFF6750A4);

/// The R10 baseline bars' dash pattern (an inline literal in
/// lib/ui/cycle_chart.dart; the help sheet's legend glyph repaints the same
/// dashes, so the chart and help-sheet tests assert these numbers).
const baselineDashPattern = [6, 4];

/// Builds the pumpable widget tree for a chart test.
///
///  - [entries], [marks] and [selectedDate] (default: [entries]' first day)
///    are pinned as fixed streams;
///  - [entriesStream] replaces the fixed daily-entries stream wholesale
///    (e.g. an emitting stream controller); [entriesStreamFactory] is
///    invoked once per provider (re-)subscription, so a stream-error retry
///    test can hand out a failing stream on the first attempt and a valid
///    one afterwards (the same pattern for [marksStreamFactory] and marks);
///  - [locale] defaults to English;
///  - [darkTheme] adds the app-shaped dark colorScheme (the dark-scheme
///    tests; ThemeMode.system stays in place so the dispatcher's test
///    brightness decides which scheme materializes);
///  - [themed] = false drops ALL theme wiring (raw MaterialApp — tests that
///    only count rebuilds, not looks);
///  - [withScaffold] = false puts the screen straight into the home
///    (no Scaffold shell);
///  - [scopeInsideMaterialApp] moves the ProviderScope below the
///    MaterialApp — the shape of the dark-scheme variants, so the scope
///    re-creates on theme changes like in the real app;
///  - [temperatureRange] pins the settings temperature range (the display
///    range / y-bounds tests); default null keeps the provider default.
///  - [observedCyclesOutsideApp] pins the prior-cycles count setting (the
///    cycle-page ordinal numbering tests); default 0 keeps the default.
///  - [now] pins the derived pass's `today` ([nowProvider]). Default null:
///    the latest date among [entries] and [marks] — the cycle span then ends
///    AT the last seeded day, so the rendering stays identical to a pre-pin
///    run and cannot drift with the test machine's wall clock. Both lists
///    empty leave the provider at its real default (nothing renders).
///    Tests exercising the span extension pass an explicit pin.
///  - [methodSnapshots] / [methodSnapshotsStream] pin the
///    measurement-method snapshot stream (the chart's thermometer glyphs;
///    a wholesale stream for re-emit tests) the same way [marks] and
///    [marksStreamFactory] do for the marks.
///  - [emptyHome] renders an EMPTY Scaffold body instead of the
///    ZyklusScreen. Routes pushed on the root navigator (the date picker
///    the AppBar's jump affordance opens) survive the body's unmount, which
///    disposes the chart state while the dialog stays open — the shape the
///    jump-to-date unmount test needs.
Widget chartHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  List<MeasurementMethodSnapshot> methodSnapshots = const [],
  Stream<List<MeasurementMethodSnapshot>>? methodSnapshotsStream,
  Stream<List<DailyEntry>>? entriesStream,
  Stream<List<DailyEntry>> Function()? entriesStreamFactory,
  Stream<List<CycleMark>> Function()? marksStreamFactory,
  Locale locale = const Locale('en'),
  bool darkTheme = false,
  bool themed = true,
  bool withScaffold = true,
  bool scopeInsideMaterialApp = false,
  DateTime? selectedDate,
  TemperatureRange? temperatureRange,
  int observedCyclesOutsideApp = 0,
  bool emptyHome = false,
  DateTime Function()? now,
}) {
  // Pin `today` to the latest seeded day: the span extension then ends at
  // that day, so chart widget tests stay wall-clock independent (see the
  // [now] doc).
  DateTime? pinnedToday;
  for (final date in [
    for (final entry in entries) entry.date,
    for (final mark in marks) mark.date,
  ]) {
    if (pinnedToday == null || date.isAfter(pinnedToday)) pinnedToday = date;
  }
  final overrides = [
    dailyEntriesProvider.overrideWith(
      (ref) =>
          entriesStreamFactory?.call() ??
          entriesStream ??
          Stream.value(entries),
    ),
    marksProvider.overrideWith(
      (ref) => marksStreamFactory?.call() ?? Stream.value(marks),
    ),
    measurementMethodsProvider.overrideWith(
      (ref) => methodSnapshotsStream ?? Stream.value(methodSnapshots),
    ),
    selectedDatePin(selectedDate ?? entries.first.date),
    if (now != null)
      nowProvider.overrideWith((ref) => now)
    else if (pinnedToday != null)
      nowProvider.overrideWith(
        (ref) =>
            () => pinnedToday!,
      ),
    if (temperatureRange != null) temperatureRangePin(temperatureRange),
    if (observedCyclesOutsideApp != 0)
      observedCyclesPin(observedCyclesOutsideApp),
  ];
  final screen = withScaffold
      ? Scaffold(body: emptyHome ? null : const ZyklusScreen())
      : const ZyklusScreen();
  final materialApp = MaterialApp(
    themeMode: themed ? ThemeMode.system : null,
    theme: themed
        ? ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: chartSeedColor),
          )
        : null,
    darkTheme: darkTheme
        ? ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: chartSeedColor,
              brightness: Brightness.dark,
            ),
          )
        : null,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: scopeInsideMaterialApp
        ? ProviderScope(overrides: overrides, child: screen)
        : screen,
  );
  return scopeInsideMaterialApp
      ? materialApp
      : ProviderScope(overrides: overrides, child: materialApp);
}

/// Pumps [widget] into the tester and then runs one settling cycle — the
/// standard (pumpWidget, pumpAndSettle) pair every chart test opens with.
///
/// A test that needs extra intermediate frames (stream re-emit timers, dialog
/// animations) keeps its explicit pumps and calls this first, then pumps
/// those frames itself.
Future<void> pumpChart(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

/// Re-pumps a FRESH harness instance: [build] runs per call so changed
/// fixture data materializes as a new subtree under a fresh key.
///
/// A plain same-shaped re-pump (same widget type and children) would only
/// update the const-canonicalized subtree in place — keeping the previous
/// pump's stream/provider/locale state — so re-pump sites with changed
/// streams, marks, ranges, locales or fixtures go through this remount.
Future<void> pumpFreshChart(
  WidgetTester tester,
  Widget Function() build,
) async {
  await pumpChart(tester, KeyedSubtree(key: UniqueKey(), child: build()));
}
