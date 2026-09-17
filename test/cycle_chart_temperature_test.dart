// Widget tests of the temperature curve's connectivity and exclusion
// rendering: the line connects two temperatures ONLY when their calendar
// days are adjacent; excluded (interrupted) temperatures count as measured
// days, keep the line continuous, but render lighter (dot AND touching
// segments). Same harness pattern as test/cycle_chart_weekend_test.dart.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-03 is a Thursday: Thu..Sun as a compact adjacent-day strip.
final _thu = DateTime.utc(2026, 9, 3);
final _fri = DateTime.utc(2026, 9, 4);
final _sat = DateTime.utc(2026, 9, 5);
final _sun = DateTime.utc(2026, 9, 6);

final _seedColor = const Color(0xFF6750A4);

Widget _chartHarness({required List<DailyEntry> entries}) => MaterialApp(
      themeMode: ThemeMode.system,
      theme:
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor, brightness: Brightness.dark),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ProviderScope(
        overrides: [
          dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          selectedDateProvider.overrideWith((ref) => entries.first.date),
        ],
        child: Scaffold(body: ZyklusScreen()),
      ),
    );

List<LineChartBarData> _bars(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;

/// The line bars the chart draws its polyline with, one entry per run of
/// adjacent days (dot-only bars, whose line is invisible, are ignored).
List<LineChartBarData> _segmentBars(WidgetTester tester) => [
      for (final bar in _bars(tester))
        if (bar.color != null && bar.color!.a > 0) bar,
    ];

/// True when some visible polyline bar connects exactly the two day indexes.
bool _connects(WidgetTester tester, int a, int b) =>
    _segmentBars(tester).any((bar) =>
        bar.spots.length == 2 &&
        bar.spots[0].x == a.toDouble() &&
        bar.spots[1].x == b.toDouble());

/// True when any visible polyline bar holds spots whose day indexes are NOT
/// adjacent — i.e. the (single-path) bar paints across a day gap.
bool _spansAGap(WidgetTester tester) => _segmentBars(tester).any((bar) {
      final xs = bar.spots.map((s) => s.x.round()).toList()..sort();
      for (var i = 1; i < xs.length; i++) {
        if (xs[i] != xs[i - 1] + 1) return true;
      }
      return false;
    });

ThemeData _themeOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

void main() {
  group('adjacent-day connectivity', () {
    testWidgets('two readings on adjacent days connect', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.6),
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'adjacent calendar days are drawn as one segment');
    });

    testWidgets('a day with no temperature between readings breaks the line',
        (tester) async {
      // Saturday has an entry, but WITHOUT a temperature, and a Sunday with
      // no entry at all behind it: neither gap may be bridged by the curve.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bleeding: Bleeding.medium),
        DailyEntry(date: _sat, bbtC: 36.7),
        DailyEntry(date: _sun, bbtC: 36.8),
      ]));
      await tester.pumpAndSettle();

      expect(_spansAGap(tester), isFalse,
          reason: 'a measured day without temperature still breaks the line');
      // The measured days BEHIND the gap stay connected among themselves.
      expect(_connects(tester, 2, 3), isTrue,
          reason: 'adjacent readings after the gap still connect');
    });

    testWidgets('a day with no entry at all breaks the line too',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _sat, bbtC: 36.7),
      ]));
      await tester.pumpAndSettle();

      // Both days are lone dots; nothing connects index 0 to index 2.
      expect(_spansAGap(tester), isFalse,
          reason: 'gap between day 0 and day 2: no segment may be drawn');
      expect(_connects(tester, 0, 2), isFalse);
    });
  });

  group('excluded temperatures render lighter', () {
    // Thu and Sat: ordinary measurements; Fri: temperature with an
    // exclusion flag (illness) — measured, but interrupted.
    final excludedMiddle = <DailyEntry>[
      DailyEntry(date: _thu, bbtC: 36.5),
      DailyEntry(date: _fri, bbtC: 36.6, excludeIllness: true),
      DailyEntry(date: _sat, bbtC: 36.7),
    ];

    /// The scheme color the chart derives its normal (opaque) color from.
    Color normalColor(WidgetTester tester) =>
        _themeOf(tester).colorScheme.primary;

    testWidgets('line stays continuous through the excluded day',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: excludedMiddle));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'excluded temperature counts as a measured day');
      expect(_connects(tester, 1, 2), isTrue,
          reason: 'the line continues through the excluded day');
    });

    testWidgets('segments touching the excluded day render lighter',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: excludedMiddle));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        final color = bar.color!;
        expect(color.a, closeTo(0.4, 1e-6),
            reason: 'both segments touch the excluded day -> lighter tint');
        // Lighter = theme color at reduced alpha, not a different hue.
        expect(color.r, normalColor(tester).r);
        expect(color.g, normalColor(tester).g);
        expect(color.b, normalColor(tester).b);
      }
    });

    testWidgets('the excluded dot renders lighter, normal dots stay opaque',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: excludedMiddle));
      await tester.pumpAndSettle();

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      final painterByIndex = <int, Color>{};
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final spot = dotBars.first.spots[i];
        final painter = dotBars.first.dotData
            .getDotPainter(spot, 0, dotBars.first, i) as FlDotCirclePainter;
        painterByIndex[spot.x.round()] = painter.color;
      }
      expect(painterByIndex[0]!.a, 1.0,
          reason: 'an ordinary measurement keeps the full-strength dot');
      final excluded = painterByIndex[1]!;
      expect(excluded.a, closeTo(0.4, 1e-6),
          reason: 'the excluded dot renders lighter');
      expect(excluded.r, normalColor(tester).r);
      expect(excluded.g, normalColor(tester).g);
      expect(excluded.b, normalColor(tester).b);
    });

    testWidgets('two consecutive excluded days connect with a lighter segment',
        (tester) async {
      // Thu and Fri both measured AND both excluded: one segment, but every
      // part of it — line and both dots — renders lighter.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5, excludeIllness: true),
        DailyEntry(date: _fri, bbtC: 36.6, excludeIllness: true),
      ]));
      await tester.pumpAndSettle();

      expect(_segmentBars(tester), hasLength(1),
          reason: 'the two adjacent excluded days form exactly one segment');
      final segment = _segmentBars(tester).single;
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment between two excluded days is lighter');
      expect(segment.color!.r, normalColor(tester).r);
      expect(segment.color!.g, normalColor(tester).g);
      expect(segment.color!.b, normalColor(tester).b);

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final painter = dotBars.first.dotData
            .getDotPainter(dotBars.first.spots[i], 0, dotBars.first, i)
            as FlDotCirclePainter;
        expect(painter.color.a, closeTo(0.4, 1e-6),
            reason: 'excluded dot ${dotBars.first.spots[i].x.round()} '
                'renders lighter');
        expect(painter.color.r, normalColor(tester).r);
        expect(painter.color.g, normalColor(tester).g);
        expect(painter.color.b, normalColor(tester).b);
      }
    });

    testWidgets('excluded dot at a run edge connects to the adjacent normal day',
        (tester) async {
      // Fri: excluded; Sat: normal. The excluded edge day is still drawn
      // connected — adjacency, not exclusion, decides connectivity.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.2, excludeTravel: true),
        DailyEntry(date: _sat, bbtC: 37.0),
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 1, 2), isTrue,
          reason: 'excluded run-edge day connects to its adjacent day');
      final segment = _segmentBars(tester)
          .firstWhere((bar) => bar.spots.length == 2 && bar.spots[0].x == 1);
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment touching the excluded edge day is lighter');
    });

    testWidgets('excluded-temp segments stay dark in dark mode',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpWidget(_chartHarness(entries: excludedMiddle));
      await tester.pumpAndSettle();

      final darkScheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme;
      expect(_segmentBars(tester).map((b) => b.color!),
          everyElement(equals(darkScheme.primary.withValues(alpha: 0.4))),
          reason: 'dark scheme: light primary at reduced alpha, still led by '
              'the (bright) scheme color — readable on the dark surface');
      expect(darkScheme.primary.computeLuminance(), greaterThan(0.3),
          reason: 'the lighter segments keep darkness-readable contrast');
    });
  });

  group('adaptive chart height', () {
    double chartHeight(WidgetTester tester) =>
        tester.getRect(find.byType(LineChart)).height;

    testWidgets('a small y-span keeps the base height of 260',
        (tester) async {
      // Five days around 36.5: the rounded bounds span 1 °C.
      await tester.pumpWidget(_chartHarness(entries: [
        for (var i = 0; i < 5; i++)
          DailyEntry(date: _thu.add(Duration(days: i)), bbtC: 36.5),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(260, 0.5),
          reason: 'a comfortable ~1 °C span needs the base height');
    });

    testWidgets('the height grows with the y-span', (tester) async {
      // 36.5 .. 40.0 → rounded bounds 36.0..40.5 (span 4.5 °C): 260 base
      // plus 1.5 °C beyond the comfortable 3 °C at 80 px per degree.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 40.0),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(380, 0.5),
          reason: 'a 4.5 °C span grows the plot: 260 + (4.5 − 3) × 80');
    });

    testWidgets('the height is capped — a wide span does not grow without '
        'bounds', (tester) async {
      // 34.5 .. 41.5 → rounded bounds 34.0..42.0 (span 8 °C, far past the
      // growth range).
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 34.5),
        DailyEntry(date: _fri, bbtC: 41.5),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(400, 0.5),
          reason: 'the growth is capped at 400');
    });
  });
}
