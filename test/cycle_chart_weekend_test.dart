import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

// Widget test of the cycle chart's weekend highlighting: weekend days
// (Saturday/Sunday, derived from the real calendar dates) get a subtle
// background band behind their chart column, weekdays get none. The band
// color is theme-derived so it stays readable in light AND dark mode.

// 2026-09-03 is a Thursday: Thu, Fri, Sat, Sun, Mon — a run that starts and
// ends on a weekday with the weekend in the middle (indexes 2 and 3).
final _weekendThu = septThreeDay(0);
final _weekendFri = septThreeDay(1);
final _weekendSat = septThreeDay(2);
final _weekendSun = septThreeDay(3);
final _weekendMon = septThreeDay(4);

final _weekendEntries = <DailyEntry>[
  DailyEntry(date: _weekendThu, bbtC: 36.5),
  DailyEntry(date: _weekendFri, bbtC: 36.6),
  DailyEntry(date: _weekendSat, bbtC: 36.7),
  DailyEntry(date: _weekendSun, bbtC: 36.8),
  DailyEntry(date: _weekendMon, bbtC: 36.6),
];

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
  expect(
    color,
    isNotNull,
    reason: 'bands are configured by color, not gradient',
  );
  return color!;
}

Widget _weekendHarness({List<DailyEntry>? entries, DateTime? selected}) =>
    // Same seed scheme wiring as CycleApp (lib/main.dart) so the dark
    // tests below exercise the dark scheme, not a themeless MaterialApp.
    chartHarness(
      entries: entries ?? _weekendEntries,
      selectedDate: selected ?? _weekendThu,
      darkTheme: true,
      scopeInsideMaterialApp: true,
    );

void main() {
  testWidgets(
    'weekend columns get background bands — exactly the weekend days at '
    'full column width, weekday columns none, clamped to the plot edges',
    (WidgetTester tester) async {
      // One case per fixture shape, all with the same band geometry model
      // (day i sits at chart x = i with a half-day band width around it):
      // the default week strip with the weekend in the middle, the
      // degenerate lone-Saturday day and a Sat..Sun run where both bands
      // touch a plot edge.
      final cases =
          <
            ({
              List<DailyEntry>? entries,
              DateTime? selected,
              String? lengthReason,
              List<(double x1, double x2, String x1Reason)> bands,
            })
          >[
            (
              // Exactly the two weekend days (Sat & Sun) are band, nothing else.
              entries: null,
              selected: null,
              lengthReason: null,
              bands: [
                (1.5, 2.5, 'Saturday (day index 2)'),
                (2.5, 3.5, 'Sunday (day index 3)'),
              ],
            ),
            (
              // Degenerate case: one recorded day, and it is a weekend day. The
              // chart keeps a one-column-wide domain window (−0.5..0.5), so the
              // lone day's full column (−0.5..0.5) lies inside the plot and the
              // band keeps its full width — no clamp may collapse it to zero.
              entries: [DailyEntry(date: _weekendSat, bbtC: 36.7)],
              selected: _weekendSat,
              lengthReason: 'the lone Saturday gets its band',
              bands: [
                (
                  -0.5,
                  0.5,
                  'the lone column spans −0.5..0.5 in the shifted domain',
                ),
              ],
            ),
            (
              // Edge clamps: the band annotation clamps to the shifted plot
              // bounds (−0.5 .. dayCount − 0.5). A weekend on the FIRST day
              // extends to the plot's left edge, a weekend on the LAST day to
              // the plot's right edge — both keep their full column width
              // instead of being cut back to the day indexes.
              entries: [
                DailyEntry(date: _weekendSat, bbtC: 36.7),
                DailyEntry(date: _weekendSun, bbtC: 36.7),
              ],
              selected: _weekendSat,
              lengthReason: null,
              bands: [
                (
                  -0.5,
                  0.5,
                  'the first day\'s band reaches the plot\'s left edge (−0.5)',
                ),
                (
                  0.5,
                  1.5,
                  'the last day\'s band reaches the plot\'s right edge '
                      '(dayCount − 0.5 = 1.5)',
                ),
              ],
            ),
          ];
      for (final (:entries, :selected, :lengthReason, :bands) in cases) {
        await pumpFreshChart(
          tester,
          () => _weekendHarness(entries: entries, selected: selected),
        );

        final actualBands = _weekendBands(tester).toList()
          ..sort((a, b) => a.x1.compareTo(b.x1));
        expect(
          actualBands,
          hasLength(bands.length),
          reason: lengthReason ?? 'exactly one band per weekend day',
        );
        for (var i = 0; i < bands.length; i++) {
          expect(
            actualBands[i].x1,
            closeTo(bands[i].$1, 1e-9),
            reason: bands[i].$3,
          );
          expect(actualBands[i].x2, closeTo(bands[i].$2, 1e-9));
        }
        // fl_chart requires x1 < x2; a zero-width band would paint nothing.
        for (final band in actualBands) {
          expect(band.x2, greaterThan(band.x1));
        }
      }
    },
  );

  testWidgets('the band tint renders in both brightnesses — mostly transparent '
      'over the light surface, a light overlay on the dark scheme', (
    WidgetTester tester,
  ) async {
    for (final dark in [false, true]) {
      // Dark-mode variant: the platform brightness must be set BEFORE
      // that variant's pump (the pump-before-dark trick the theme-mode
      // dark tests use, since a mid-test dispatcher change does not
      // rebuild the theme in the test env).
      if (dark) useDarkDeviceBrightness(tester);

      await pumpFreshChart(tester, _weekendHarness);

      final bands = _weekendBands(tester);
      expect(bands, isNotEmpty);
      for (final band in bands) {
        // A whisper, not a wallpaper: mostly transparent over the surface.
        final color = _bandColor(band);
        expect(color.a, greaterThan(0.0));
        expect(color.a, lessThan(0.15));
      }
      if (dark) {
        for (final band in bands) {
          // Dark-mode tint is a light overlay (high relative luminance),
          // so it contrasts against the dark chart surface instead of
          // disappearing.
          expect(
            _bandColor(band).computeLuminance(),
            greaterThan(0.3),
            reason: 'dark-mode weekend tint should lean on the dark scheme',
          );
        }
      }
    }
  });
}
