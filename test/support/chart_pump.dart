// Shared chart pump harness: one scope wiring for the cycle-chart widget
// tests. Every chart test (test/cycle_chart_test.dart) pumps the
// ZyklusScreen with the
// same three stream overrides (daily entries, marks, selected date) plus
// the app's MaterialApp wiring (localization delegates, en locale, seeded
// color scheme); the parameters below cover the shapes the tests grew into —
// ProviderScope outside vs. inside the MaterialApp, an optional dark
// scheme, and optionally no theme wiring at all.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The seed color of the app's scheme (lib/main.dart), pinned so tests can
/// reach the same ColorScheme the charts render with.
const chartSeedColor = Color(0xFF6750A4);

/// Builds the pumpable widget tree for a chart test.
///
///  - [entries], [marks] and [selectedDate] (default: [entries]' first day)
///    are pinned as fixed streams;
///  - [entriesStream] replaces the fixed daily-entries stream wholesale
///    (e.g. an emitting stream controller);
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
Widget chartHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  Stream<List<DailyEntry>>? entriesStream,
  Locale locale = const Locale('en'),
  bool darkTheme = false,
  bool themed = true,
  bool withScaffold = true,
  bool scopeInsideMaterialApp = false,
  DateTime? selectedDate,
  TemperatureRange? temperatureRange,
}) {
  final overrides = [
    dailyEntriesProvider
        .overrideWith((ref) => entriesStream ?? Stream.value(entries)),
    marksProvider.overrideWith((ref) => Stream.value(marks)),
    selectedDateProvider
        .overrideWith((ref) => selectedDate ?? entries.first.date),
    if (temperatureRange != null)
      temperatureRangeProvider.overrideWith((ref) => temperatureRange),
  ];
  final screen = withScaffold
      ? const Scaffold(body: ZyklusScreen())
      : const ZyklusScreen();
  final materialApp = MaterialApp(
    themeMode: themed ? ThemeMode.system : null,
    theme: themed
        ? ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: chartSeedColor))
        : null,
    darkTheme: darkTheme
        ? ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: chartSeedColor, brightness: Brightness.dark))
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
