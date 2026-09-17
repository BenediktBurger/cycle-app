// Widget test of the cycle chart's weekend highlighting: weekend days
// (Saturday/Sunday, derived from the real calendar dates) get a subtle
// background band behind their chart column, weekdays get none. The band
// color is theme-derived so it stays readable in light AND dark mode.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-03 is a Thursday: Thu, Fri, Sat, Sun, Mon — a run that starts and
// ends on a weekday with the weekend in the middle (indexes 2 and 3).
final _thu = DateTime.utc(2026, 9, 3);
final _fri = DateTime.utc(2026, 9, 4);
final _sat = DateTime.utc(2026, 9, 5);
final _sun = DateTime.utc(2026, 9, 6);
final _mon = DateTime.utc(2026, 9, 7);

final _entries = <DailyEntry>[
  DailyEntry(date: _thu, bbtC: 36.5),
  DailyEntry(date: _fri, bbtC: 36.6),
  DailyEntry(date: _sat, bbtC: 36.7),
  DailyEntry(date: _sun, bbtC: 36.8),
  DailyEntry(date: _mon, bbtC: 36.6),
];

Widget _chartHarness({List<DailyEntry>? entries, DateTime? selected}) =>
    MaterialApp(
      // Same seed scheme wiring as CycleApp (lib/main.dart) so the dark
      // test below exercises the dark scheme, not a themeless MaterialApp.
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4), brightness: Brightness.dark),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ProviderScope(
        overrides: [
          dailyEntriesProvider
              .overrideWith((ref) => Stream.value(entries ?? _entries)),
          selectedDateProvider.overrideWith((ref) => selected ?? _thu),
        ],
        child: Scaffold(body: ZyklusScreen()),
      ),
    );

/// The weekend background bands currently configured on the chart, in
/// ascending x order.
List<VerticalRangeAnnotation> _weekendBands(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .rangeAnnotations
    .verticalRangeAnnotations;

/// The band color, asserted non-null before use (the chart is configured
/// with an explicit color, never a gradient).
Color _bandColor(VerticalRangeAnnotation band) {
  final color = band.color;
  expect(color, isNotNull,
      reason: 'bands are configured by color, not gradient');
  return color!;
}

void main() {
  testWidgets('weekend columns get background bands, weekday columns none',
      (WidgetTester tester) async {
    await tester.pumpWidget(_chartHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester).toList()
      ..sort((a, b) => a.x1.compareTo(b.x1));

    // Exactly the two weekend days (Sat & Sun) are band, nothing else.
    expect(bands, hasLength(2));
    // Day i sits at chart x = i with a half-day band width around it.
    expect(bands[0].x1, closeTo(1.5, 1e-9), reason: 'Saturday (day index 2)');
    expect(bands[0].x2, closeTo(2.5, 1e-9));
    expect(bands[1].x1, closeTo(2.5, 1e-9), reason: 'Sunday (day index 3)');
    expect(bands[1].x2, closeTo(3.5, 1e-9));
  });

  // Degenerate case: one recorded day, and it is a weekend day. The chart
  // keeps a one-column-wide domain window (−0.5..0.5), so the lone day's
  // full column (−0.5..0.5) lies inside the plot and the band keeps its
  // full width — no clamp may collapse it to zero.
  testWidgets('single-day weekend chart still renders one band, positive width',
      (WidgetTester tester) async {
    await tester.pumpWidget(_chartHarness(
      entries: [DailyEntry(date: _sat, bbtC: 36.7)],
      selected: _sat,
    ));
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, hasLength(1), reason: 'the lone Saturday gets its band');
    // fl_chart requires x1 < x2; zero width would paint nothing.
    expect(bands.single.x2, greaterThan(bands.single.x1));
    expect(bands.single.x1, closeTo(-0.5, 1e-9),
        reason: 'the lone column spans −0.5..0.5 in the shifted domain');
    expect(bands.single.x2, closeTo(0.5, 1e-9));
  });

  // Edge clamps: the band annotation clamps to the shifted plot bounds
  // (−0.5 .. dayCount − 0.5). A weekend on the FIRST day extends to the
  // plot's left edge, a weekend on the LAST day to the plot's right edge —
  // both keep their full column width instead of being cut back to the
  // day indexes.
  testWidgets('a weekend on the first day extends to the plot\'s left edge',
      (WidgetTester tester) async {
    // Sat (first day) .. Sun (last day): both bands touch a plot edge.
    await tester.pumpWidget(_chartHarness(
      entries: [
        DailyEntry(date: _sat, bbtC: 36.7),
        DailyEntry(date: _sun, bbtC: 36.7)
      ],
      selected: _sat,
    ));
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester).toList()
      ..sort((a, b) => a.x1.compareTo(b.x1));
    expect(bands, hasLength(2));
    expect(bands[0].x1, closeTo(-0.5, 1e-9),
        reason: 'the first day\'s band reaches the plot\'s left edge (−0.5)');
    expect(bands[0].x2, closeTo(0.5, 1e-9));
    expect(bands[1].x1, closeTo(0.5, 1e-9),
        reason: 'the last day\'s band reaches the plot\'s right edge '
            '(dayCount − 0.5 = 1.5)');
    expect(bands[1].x2, closeTo(1.5, 1e-9));
  });

  testWidgets('band color is a subtle tint that follows the theme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_chartHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, isNotEmpty);
    for (final band in bands) {
      // A whisper, not a wallpaper: mostly transparent over the surface.
      final color = _bandColor(band);
      expect(color.a, greaterThan(0.0));
      expect(color.a, lessThan(0.15));
    }
  });

  // Dark mode as its own test: the platform brightness is set BEFORE the
  // first pump (same pattern as test/theme_brightness_test.dart, since a
  // mid-test dispatcher change does not rebuild the theme in the test env).
  testWidgets('dark mode: the band tint is a light overlay on the dark scheme',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_chartHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, isNotEmpty);
    for (final band in bands) {
      final color = _bandColor(band);
      expect(color.a, greaterThan(0.0));
      expect(color.a, lessThan(0.15));
      // Dark-mode tint is a light overlay (high relative luminance), so it
      // contrasts against the dark chart surface instead of disappearing.
      expect(
        color.computeLuminance(),
        greaterThan(0.3),
        reason: 'dark-mode weekend tint should lean on the dark scheme',
      );
    }
  });
}
