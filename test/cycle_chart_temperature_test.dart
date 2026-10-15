import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

// Widget tests of the temperature curve's connectivity and interruption
// rendering: the line connects two temperatures ONLY when their calendar
// days are adjacent; ignored temperatures (a day carrying the
// ignoreTemperature MARK — the rendering is keyed to the mark, NOT to the
// raw disturbance mask, owner decision 2026-09-19) count as measured
// days, keep the line continuous, but render lighter (dot AND touching
// segments). The mark makes the state visible on the graph: a marked day
// without flags renders lighter, and an unmarked flagged day renders at
// full weight.

// 2026-09-03 is a Thursday: Thu..Sun as a compact adjacent-day strip.
final _temperatureThu = septThreeDay(0);
final _temperatureFri = septThreeDay(1);
final _temperatureSat = septThreeDay(2);
final _temperatureSun = septThreeDay(3);

List<LineChartBarData> _bars(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;

/// The line bars the chart draws its polyline with, one entry per run of
/// adjacent days (dot-only bars, whose line is invisible, are ignored).
List<LineChartBarData> _segmentBars(WidgetTester tester) => [
  for (final bar in _bars(tester))
    if (bar.color != null && bar.color!.a > 0) bar,
];

/// True when some visible polyline bar connects exactly the two day indexes.
bool _connects(WidgetTester tester, int a, int b) => _segmentBars(tester).any(
  (bar) =>
      bar.spots.length == 2 &&
      bar.spots[0].x == a.toDouble() &&
      bar.spots[1].x == b.toDouble(),
);

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

Widget _temperatureHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  TemperatureRange? range,
}) => chartHarness(
  entries: entries,
  marks: marks,
  darkTheme: true,
  scopeInsideMaterialApp: true,
  temperatureRange: range,
);
// Widget tests of the measurement-method thermometer glyph inside the
// temperature plot: every day whose date carries a stored snapshot renders
// the SAME thermometer ink for all routes in its
// day column — anchored directly below the day's plotted temperature
// point; a snapshot day without a plotted point (no entry, an entry
// without a temperature, an out-of-range value — the dot's own filter)
// parks the glyph in the fixed bottom-anchored slot above the evaluation
// day numbers, which hides itself when the range is too narrow for it.
// A day without a snapshot renders nothing.

// Five chart days:
//  0: temperature 36.5 (in range) + a snapshot    -> glyph below the point
//  1: temperature 38.2 (out of range) + a snapshot -> fallback slot
//  2: entry WITHOUT a temperature + a snapshot    -> fallback slot
//  3: untracked gap day + a snapshot              -> fallback slot
//  4: plain temperature day, no snapshot          -> nothing
final _methodGlyphEntries = [
  DailyEntry(date: septSevenDay(0), bbtC: 36.5),
  DailyEntry(date: septSevenDay(1), bbtC: 38.2),
  DailyEntry(date: septSevenDay(2)),
  DailyEntry(date: septSevenDay(4), bbtC: 36.5),
];

final _methodGlyphSnapshots = [
  for (final index in [0, 1, 2, 3])
    MeasurementMethodSnapshot(
      date: septSevenDay(index),
      route: MeasurementRoute.vaginal,
    ),
];

void main() {
  group('adjacent-day connectivity', () {
    // One widget-level probe: curveRuns' break matrices are owned by
    // test/cycle_curve_test.dart.
    testWidgets('the curve joins a contiguous run and stops at an unmeasured '
        'day', (tester) async {
      // Friday has an entry, but WITHOUT a temperature: the gap may not be
      // bridged by the curve.
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bleeding: Bleeding.medium),
            DailyEntry(date: _temperatureSat, bbtC: 36.7),
            DailyEntry(date: _temperatureSun, bbtC: 36.8),
          ],
        ),
      );

      expect(
        _spansAGap(tester),
        isFalse,
        reason: 'a measured day without temperature still breaks the line',
      );
      // The measured days BEHIND the gap stay connected among themselves.
      expect(
        _connects(tester, 2, 3),
        isTrue,
        reason: 'adjacent readings after the gap still connect',
      );
    });
  });

  group('ignored temperatures render lighter (mark-keyed)', () {
    // Thu and Sat: ordinary measurements; Fri: a measured day carrying the
    // ignoreTemperature MARK (no raw flags needed — the mark is the
    // rendering key).
    final ignoredMiddle = <DailyEntry>[
      DailyEntry(date: _temperatureThu, bbtC: 36.5),
      DailyEntry(date: _temperatureFri, bbtC: 36.6),
      DailyEntry(date: _temperatureSat, bbtC: 36.7),
    ];
    final friMark = CycleMark(
      date: _temperatureFri,
      type: CycleMarkTypes.ignoreTemperature,
    );

    /// The scheme color the chart derives its normal (opaque) color from.
    Color normalColor(WidgetTester tester) =>
        _themeOf(tester).colorScheme.primary;

    testWidgets('the line stays continuous through the ignored day — and both '
        'segments touching it render lighter', (tester) async {
      await pumpChart(
        tester,
        _temperatureHarness(entries: ignoredMiddle, marks: [friMark]),
      );

      expect(
        _connects(tester, 0, 1),
        isTrue,
        reason: 'ignored temperature counts as a measured day',
      );
      expect(
        _connects(tester, 1, 2),
        isTrue,
        reason: 'the line continues through the ignored day',
      );
      for (final bar in _segmentBars(tester)) {
        final color = bar.color!;
        expect(
          color.a,
          closeTo(0.4, 1e-6),
          reason: 'both segments touch the ignored day -> lighter tint',
        );
        // Lighter = theme color at reduced alpha, not a different hue.
        expect(color.r, normalColor(tester).r);
        expect(color.g, normalColor(tester).g);
        expect(color.b, normalColor(tester).b);
      }
    });

    testWidgets(
      'the ignored dot renders lighter, normal dots stay opaque — the '
      'mark alone dims the curve, no disturbance flags needed',
      (tester) async {
        // Headline new behavior (owner decision 2026-09-19): the mark is
        // the visible state, flags are surfaced by other means (diary
        // badge). Fri carries ONLY the mark — no tempDisturbances — and
        // still renders lighter.
        final unflaggedMarked = <DailyEntry>[
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(date: _temperatureFri, bbtC: 36.6), // mask 0
          DailyEntry(date: _temperatureSat, bbtC: 36.7),
        ];
        await pumpChart(
          tester,
          _temperatureHarness(entries: unflaggedMarked, marks: [friMark]),
        );

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
          final painter =
              dotBars.first.dotData.getDotPainter(spot, 0, dotBars.first, i)
                  as FlDotCirclePainter;
          painterByIndex[spot.x.round()] = painter.color;
        }
        expect(
          painterByIndex[0]!.a,
          1.0,
          reason: 'an ordinary measurement keeps the full-strength dot',
        );
        expect(
          painterByIndex[1]!.a,
          closeTo(0.4, 1e-6),
          reason:
              'the ignored dot renders lighter — a marked day WITHOUT '
              'flags renders lighter (the mark alone dims the curve)',
        );
        expect(painterByIndex[1]!.r, normalColor(tester).r);
        expect(painterByIndex[1]!.g, normalColor(tester).g);
        expect(painterByIndex[1]!.b, normalColor(tester).b);
        for (final bar in _segmentBars(tester)) {
          expect(
            bar.color!.a,
            closeTo(0.4, 1e-6),
            reason: 'both segments touch the marked day -> lighter tint',
          );
        }
      },
    );

    testWidgets('a flagged day WITHOUT the mark renders at FULL alpha '
        '(deleting the mark restores normal rendering)', (tester) async {
      // THE FLIP (owner decision 2026-09-19): the mark can be deleted on
      // the day sheet while the raw flags remain — the curve renders
      // normally again (the flags are surfaced by the diary badge, not
      // the curve).
      final flaggedUnmarked = <DailyEntry>[
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(
          date: _temperatureFri,
          bbtC: 36.6,
          tempDisturbances: TempDisturbance.kr.bit,
        ),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ];
      await pumpChart(tester, _temperatureHarness(entries: flaggedUnmarked));

      for (final bar in _segmentBars(tester)) {
        expect(
          bar.color!.a,
          1.0,
          reason:
              'flags without the mark render at full alpha — the '
              'raw mask is not a rendering input',
        );
      }
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final painter =
            dotBars.single.dotData.getDotPainter(
                  dotBars.single.spots[i],
                  0,
                  dotBars.single,
                  i,
                )
                as FlDotCirclePainter;
        expect(
          painter.color.a,
          1.0,
          reason:
              'the flagged-but-unmarked dot keeps the full-strength '
              'color',
        );
      }
    });

    testWidgets(
      'a marked AND flagged day renders lighter (mark-keyed, even with '
      'raw flags)',
      (tester) async {
        // The typical interrupted day carries both: the raw mask (flags)
        // AND the manually placed ignoreTemperature mark — still lighter
        // (mark-keyed).
        final flaggedMarked = <DailyEntry>[
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(
            date: _temperatureFri,
            bbtC: 36.6,
            tempDisturbances: TempDisturbance.kr.bit,
          ),
          DailyEntry(date: _temperatureSat, bbtC: 36.7),
        ];
        await pumpChart(
          tester,
          _temperatureHarness(entries: flaggedMarked, marks: [friMark]),
        );

        for (final bar in _segmentBars(tester)) {
          expect(
            bar.color!.a,
            closeTo(0.4, 1e-6),
            reason:
                'marked + flagged renders lighter (the mark is the '
                'rendering key)',
          );
        }
      },
    );

    testWidgets('two consecutive ignored days connect with a lighter segment', (
      tester,
    ) async {
      // Thu and Fri both measured AND both ignored (marks): one segment,
      // but every part of it — line and both dots — renders lighter.
      final marks = [
        CycleMark(
          date: _temperatureThu,
          type: CycleMarkTypes.ignoreTemperature,
        ),
        friMark,
      ];
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 36.6),
          ],
          marks: marks,
        ),
      );

      expect(
        _segmentBars(tester),
        hasLength(1),
        reason: 'the two adjacent ignored days form exactly one segment',
      );
      final segment = _segmentBars(tester).single;
      expect(
        segment.color!.a,
        closeTo(0.4, 1e-6),
        reason: 'the segment between two ignored days is lighter',
      );
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
        final painter =
            dotBars.first.dotData.getDotPainter(
                  dotBars.first.spots[i],
                  0,
                  dotBars.first,
                  i,
                )
                as FlDotCirclePainter;
        expect(
          painter.color.a,
          closeTo(0.4, 1e-6),
          reason:
              'ignored dot ${dotBars.first.spots[i].x.round()} '
              'renders lighter',
        );
        expect(painter.color.r, normalColor(tester).r);
        expect(painter.color.g, normalColor(tester).g);
        expect(painter.color.b, normalColor(tester).b);
      }
    });

    testWidgets(
      'ignored dot at a run edge connects to the adjacent normal day',
      (tester) async {
        // Fri: ignored; Sat: normal. The ignored edge day is still drawn
        // connected — adjacency, not the mark, decides connectivity.
        await pumpChart(
          tester,
          _temperatureHarness(
            entries: [
              DailyEntry(date: _temperatureThu, bbtC: 36.5),
              DailyEntry(date: _temperatureFri, bbtC: 36.2),
              DailyEntry(date: _temperatureSat, bbtC: 37.0),
            ],
            marks: [friMark],
          ),
        );

        expect(
          _connects(tester, 1, 2),
          isTrue,
          reason: 'ignored run-edge day connects to its adjacent day',
        );
        final segment = _segmentBars(
          tester,
        ).firstWhere((bar) => bar.spots.length == 2 && bar.spots[0].x == 1);
        expect(
          segment.color!.a,
          closeTo(0.4, 1e-6),
          reason: 'the segment touching the ignored edge day is lighter',
        );
      },
    );

    testWidgets('ignored-temp segments stay dark in dark mode', (tester) async {
      useDarkDeviceBrightness(tester);

      await pumpChart(
        tester,
        _temperatureHarness(entries: ignoredMiddle, marks: [friMark]),
      );

      final darkScheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme;
      expect(
        _segmentBars(tester).map((b) => b.color!),
        everyElement(equals(darkScheme.primary.withValues(alpha: 0.4))),
        reason:
            'dark scheme: light primary at reduced alpha, still led by '
            'the (bright) scheme color — readable on the dark surface',
      );
      expect(
        darkScheme.primary.computeLuminance(),
        greaterThan(0.3),
        reason: 'the lighter segments keep darkness-readable contrast',
      );
    });
  });

  group('adaptive chart height (span of the settings range)', () {
    double chartHeight(WidgetTester tester) =>
        tester.getRect(find.byType(LineChart)).height;

    testWidgets(
      'the plot height holds one base height across the comfortable spans, '
      'grows with wider spans and plateaus at its cap for the widest '
      'selectable spans',
      (tester) async {
        // The base height, the growth rate and the cap are display
        // heuristics (owner-eyeball values), so the test pins the SHAPE
        // only: both comfortable spans share the base height, wider spans
        // strictly grow the plot, and the widest selectable spans plateau
        // at a shared capped height.
        Future<double> height({
          TemperatureRange? range,
          required List<DailyEntry> entries,
        }) async {
          await pumpFreshChart(
            tester,
            () => _temperatureHarness(entries: entries, range: range),
          );
          return chartHeight(tester);
        }

        final defaultSpan = [
          for (var i = 0; i < 5; i++)
            DailyEntry(
              date: _temperatureThu.add(Duration(days: i)),
              bbtC: 36.5,
            ),
        ];
        final baseSpan = await height(entries: defaultSpan);
        final comfortableSpan = await height(
          range: const TemperatureRange(min: 36.0, max: 39.0),
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 38.5),
          ],
        );
        final grownSpan = await height(
          range: const TemperatureRange(min: 36.0, max: 40.5),
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 40.0),
          ],
        );
        final cappedNarrowest = await height(
          range: const TemperatureRange(min: 34.0, max: 41.0),
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 34.5),
            DailyEntry(date: _temperatureFri, bbtC: 40.5),
          ],
        );
        final cappedWidest = await height(
          range: const TemperatureRange(min: 34.0, max: 42.0),
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 34.5),
            DailyEntry(date: _temperatureFri, bbtC: 41.5),
          ],
        );

        expect(
          baseSpan,
          comfortableSpan,
          reason: 'both comfortable spans hold the same base height',
        );
        expect(
          grownSpan,
          greaterThan(comfortableSpan),
          reason: 'a span past the comfortable width grows the plot',
        );
        expect(
          cappedWidest,
          greaterThanOrEqualTo(grownSpan),
          reason: 'a wider span never shrinks the plot',
        );
        expect(
          cappedNarrowest,
          cappedWidest,
          reason:
              'the widest selectable spans plateau at one capped height '
              '(the cap sits inside the settings window)',
        );
      },
    );
  });

  group('fixed display-range bounds', () {
    LineChartData data(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart)).data;

    testWidgets('the y bounds are the provider\'s range (default 36.0..38.0), '
        'never the data', (tester) async {
      // The record dips just below the fixed range's lower bound (35.9
      // vs 36.0) — under the old data-adaptive bounds such a low value
      // dragged the lower edge to the half degree below (35.5 here), so
      // this is where the old rounding would have moved the axis; the
      // settings range pins the bounds 36..38 regardless. Out-of-range
      // readings are simply not rendered (the out-of-range tests below) — they
      // never move the bounds either way.
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 37.0),
            DailyEntry(date: _temperatureSat, bbtC: 35.9),
          ],
        ),
      );

      expect(
        data(tester).minY,
        36.0,
        reason: 'the default range\'s lower bound is the fixed minY',
      );
      expect(
        data(tester).maxY,
        38.0,
        reason: 'the default range\'s upper bound is the fixed maxY',
      );
    });
  });

  // Widget tests of temperatures OUTSIDE the chart's visible value range
  // (the settings-selected display range, default 36–38 °C): such a
  // measurement is NOT rendered at all — its whole per-day dot painter
  // (dot, circled-higher ring, arrow-up glyph) is skipped with its spot.
  // The polyline still connects the adjacent days but is CLIPPED to the
  // value range: the drawable piece runs to the boundary crossing (at a
  // possibly fractional day index BETWEEN the days), so a line running to
  // or along the plot's top/bottom edge tells the reader data lie beyond
  // the visible range. In-range rendering is pixel-for-pixel unchanged, a
  // value exactly AT a boundary counts as in range (its dot renders and its
  // segments pass through raw), and when EVERY measurement is out of range
  // the paper grid renders with no curve (the "no temperature" placeholder
  // still does NOT show — the days carry measurements). Fixture shape and
  // helpers are shared with the temperature-connectivity tests above.

  /// A measured-day strip on the curve tests' Thu..Sat calendar block: day index = list position, temperatures = the given values.
  List<DailyEntry> rangeEntries(List<double> temps) => [
    for (var i = 0; i < temps.length; i++)
      DailyEntry(
        date: _temperatureThu.add(Duration(days: i)),
        bbtC: temps[i],
      ),
  ];

  /// The visible polyline's drawable spans as (start, end) spot pairs —
  /// one pair per visible two-spot line bar (the curve draws one bar per
  /// clipped span).
  List<(FlSpot, FlSpot)> visibleSpans(WidgetTester tester) => [
    for (final bar in _segmentBars(tester))
      if (bar.spots.length == 2) (bar.spots.first, bar.spots.last),
  ];

  /// The (x, y) pair list of [visibleSpans], for exact endpoint comparison.
  List<(double, double, double, double)> spanEndpoints(WidgetTester tester) => [
    for (final (start, end) in visibleSpans(tester))
      (start.x, start.y, end.x, end.y),
  ];

  /// True when some dot-only bar carries a spot at [dayIndex] (day indexes
  /// sit at integral x positions).
  bool hasDotSpot(WidgetTester tester, int dayIndex) => dotBars(
    tester,
  ).any((bar) => bar.spots.any((spot) => spot.x.round() == dayIndex));

  group('out-of-range temperatures against the fixed display-range bounds '
      '(37 / 39 / 37 above, 37 / 38 / 37 at, 37 / 35 / 37 below, '
      '39 / 39.2 / 39 all out)', () {
    testWidgets(
      'a temperature out of range renders no dot and clips the polyline '
      'at the boundary crossing; exactly at the boundary the dot and '
      'raw endpoints render unchanged; an all-out record leaves only '
      'the mounted paper grid',
      (tester) async {
        final boundaryCases =
            <
              (
                String label,
                List<double> values,
                bool boundaryDotRenders,
                List<(double, double, double, double)> endpoints,
                String reason,
                void Function(WidgetTester)? extras,
              )
            >[
              (
                'above the range (37 / 39 / 37)',
                [37.0, 39.0, 37.0],
                false,
                [(0.0, 37.0, 0.5, 38.0), (1.5, 38.0, 2.0, 37.0)],
                'the line to and from the above-range day is clipped at '
                    'the upper boundary 38.0, crossing midway between the days',
                (tester) {
                  expect(
                    dotPainterOrNull(tester, 0),
                    isNotNull,
                    reason: 'the in-range left day keeps its dot painter',
                  );
                  expect(
                    dotPainterOrNull(tester, 2),
                    isNotNull,
                    reason: 'the in-range right day keeps its dot painter',
                  );
                  final spans = visibleSpans(tester);
                  expect(
                    spans,
                    hasLength(2),
                    reason: 'the only visible bars are the two clipped spans',
                  );
                  expect(
                    (spans[0].$1.x, spans[0].$1.y),
                    (0.0, 37.0),
                    reason:
                        'the left bar starts at day 0\'s raw in-range value',
                  );
                  expect(
                    (spans[1].$2.x, spans[1].$2.y),
                    (2.0, 37.0),
                    reason: 'the right bar ends at day 2\'s raw in-range value',
                  );
                  expect(
                    hasDotSpot(tester, 1),
                    isFalse,
                    reason:
                        'the dot bars carry in-range spots only — no spot '
                        'maps to the out-of-range day',
                  );
                },
              ),
              (
                'exactly at the boundary (37 / 38 / 37)',
                [37.0, 38.0, 37.0],
                true,
                [(0.0, 37.0, 1.0, 38.0), (1.0, 38.0, 2.0, 37.0)],
                'the boundary value lies inside the window, so the segments '
                    'keep their raw endpoints (no clipping)',
                null,
              ),
              (
                'below the range (37 / 35 / 37)',
                [37.0, 35.0, 37.0],
                false,
                [(0.0, 37.0, 0.5, 36.0), (1.5, 36.0, 2.0, 37.0)],
                'the line to and from the below-range day is clipped at '
                    'the lower boundary 36.0, crossing midway between the days',
                null,
              ),
            ];

        for (final (
              label,
              values,
              boundaryDotRenders,
              endpoints,
              endpointReason,
              extras,
            )
            in boundaryCases) {
          await pumpFreshChart(
            tester,
            () => _temperatureHarness(entries: rangeEntries(values)),
          );

          if (boundaryDotRenders) {
            expect(
              dotPainterOrNull(tester, 1),
              isNotNull,
              reason:
                  '$label: the boundary value counts as in range — its '
                  'dot renders unchanged',
            );
          } else {
            expect(
              dotPainterOrNull(tester, 1),
              isNull,
              reason:
                  '$label: the middle day\'s dot is skipped with its '
                  'spot (no ring or arrow anchored to it either)',
            );
          }
          if (extras != null) extras(tester);
          expect(spanEndpoints(tester), endpoints, reason: endpointReason);
        }

        // Every measurement out of range: the curve vanishes but the
        // chart still mounts (the paper grid with no curve; the
        // "no temperature" placeholder must NOT show — the days carry
        // measurements).
        await pumpChart(
          tester,
          _temperatureHarness(entries: rangeEntries([39.0, 39.2, 39.0])),
        );
        for (var i = 0; i < 3; i++) {
          expect(
            dotPainterOrNull(tester, i),
            isNull,
            reason: 'day $i is out of range — its dot does not render',
          );
        }
        expect(
          _segmentBars(tester),
          isEmpty,
          reason:
              'no piece of the polyline passes through the visible '
              'range — nothing drawable at all',
        );
        expect(
          find.byType(LineChart),
          findsOneWidget,
          reason: 'the chart still mounts with its paper grid',
        );
        expect(
          find.textContaining('Enter observations or measurements'),
          findsNothing,
          reason:
              'the "no temperature" placeholder does not show — the '
              'days carry measurements',
        );
      },
    );
  });

  group('method-snapshot thermometer glyph', () {
    Finder methodGlyph(int index) =>
        find.byKey(ValueKey('inPlotMethodGlyph-$index'));

    testWidgets('a snapshot day with an in-range temperature anchors the '
        'glyph one pitch below the plotted point, centered in its column', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _methodGlyphEntries,
          methodSnapshots: _methodGlyphSnapshots,
        ),
      );

      final plot = tester.getRect(find.byType(LineChart));
      // The chart's day space spans 9/7..9/11: four entries around the
      // untracked gap day 3 — five day columns wide.
      const dayCount = 5;
      final colW = plot.width / dayCount;

      final glyph = methodGlyph(0);
      expect(
        glyph,
        findsOneWidget,
        reason: 'the snapshot day renders its thermometer glyph',
      );
      expect(
        find.byKey(const ValueKey('inPlotHaloMethodGlyph-0')),
        findsOneWidget,
        reason: 'one halo layer behind the ink',
      );
      // The glyph hangs under its day's plotted point, so it must end up
      // strictly ABOVE the bottom-anchored fallback slot the point-less
      // days park in. The exact pitch under the point is the owner-eyeball
      // row geometry, so the test keeps this ordering relation.
      final underPointY = tester.getRect(glyph).center.dy;
      final fallbackY = tester.getRect(methodGlyph(1)).center.dy;
      expect(
        underPointY,
        lessThan(fallbackY),
        reason:
            'the anchored glyph hangs below its point but stays above the '
            'fixed fallback slot',
      );
      expect(
        underPointY,
        lessThan(plot.bottom),
        reason: 'the anchored glyph stays inside the plot',
      );
      expect(
        tester.getRect(glyph).center.dx,
        closeTo(plot.left + 0.5 * colW, 1),
        reason: 'the glyph centers in its day column',
      );
    });

    testWidgets('a snapshot day without a plotted point parks the glyph in '
        'the fixed fallback slot: out-of-range value, unmeasured entry, '
        'untracked gap day', (tester) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _methodGlyphEntries,
          methodSnapshots: _methodGlyphSnapshots,
        ),
      );

      final plot = tester.getRect(find.byType(LineChart));
      const dayCount = 5;
      final colW = plot.width / dayCount;

      // Every fallback day parks in ONE fixed slot: the same center height
      // on all of them, in the plot's bottom half. The exact slot offset
      // above the scale min is the owner-eyeball row pitch — not pinned.
      final fallbackYs = <double>[];
      for (final index in [1, 2, 3]) {
        final glyph = methodGlyph(index);
        expect(
          glyph,
          findsOneWidget,
          reason:
              'day $index: no plotted point on a snapshot day -> '
              'the fallback slot renders the glyph',
        );
        fallbackYs.add(tester.getRect(glyph).center.dy);
        expect(
          tester.getRect(glyph).center.dx,
          closeTo(plot.left + (index + 0.5) * colW, 1),
          reason: 'day $index: the fallback glyph centers in its column',
        );
      }
      expect(
        fallbackYs,
        everyElement(fallbackYs.first),
        reason: 'every fallback day shares the SAME fixed slot height',
      );
      expect(
        fallbackYs.first,
        greaterThan(plot.center.dy),
        reason: 'the fallback slot parks in the plot\'s bottom half',
      );
    });

    testWidgets('a day without a snapshot renders nothing', (tester) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _methodGlyphEntries,
          methodSnapshots: _methodGlyphSnapshots,
        ),
      );

      expect(
        methodGlyph(4),
        findsNothing,
        reason: 'the plain temperature day carries no snapshot',
      );
      expect(
        find.byKey(const ValueKey('inPlotHaloMethodGlyph-4')),
        findsNothing,
        reason: 'no halo renders without the ink either',
      );
    });

    testWidgets('a snapshot-less range renders no thermometer glyph at all', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _methodGlyphEntries));

      for (var i = 0; i <= _methodGlyphEntries.length; i++) {
        expect(methodGlyph(i), findsNothing);
      }
      expect(
        find.byKey(const ValueKey('inPlotHaloMethodGlyph-0')),
        findsNothing,
      );
    });

    testWidgets('a snapshot stream re-emit re-renders the glyphs', (
      tester,
    ) async {
      // Broadcast: the provider subscribes during the pump, so the emit
      // below reaches it; before that (or without any subscriber) an emit
      // is dropped and the ledger stays glyph-free.
      final snapshots =
          StreamController<List<MeasurementMethodSnapshot>>.broadcast();
      addTearDown(snapshots.close);
      await pumpChart(
        tester,
        chartHarness(
          entries: _methodGlyphEntries,
          methodSnapshotsStream: snapshots.stream,
        ),
      );

      expect(
        methodGlyph(0),
        findsNothing,
        reason: 'the stream has not emitted yet — the start is glyph-free',
      );

      snapshots.add(_methodGlyphSnapshots);
      await tester.pumpAndSettle();
      expect(
        methodGlyph(0),
        findsOneWidget,
        reason: 'the snapshot re-emit renders the day-0 glyph',
      );
      expect(
        methodGlyph(4),
        findsNothing,
        reason: 'the plain day still carries no snapshot',
      );
    });
  });
}
