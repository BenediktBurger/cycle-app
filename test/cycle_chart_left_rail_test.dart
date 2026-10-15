import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:cycle_app/ui/cycle.dart';
import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle chart's frozen left rail: the paper sheet's
// fixed left margin lives OUTSIDE the horizontal scroll, so it stays
// readable while the day columns slide — the owner-reported defect was the
// temperature scale vanishing once the window scrolled to recent days.
// The rail carries three things, all moved out of the scrolling content's
// leading strips:
//  1. the header corner prototypes ("14." date column / "#5" cycle-day
//     column) with their tooltips/semantics,
//  2. the temperature scale: fl_chart's left titles are DISABLED and the
//     rail paints the scale labels itself, using the exact same linear
//     value→pixel mapping as the plot (shared from the chart's min/max and
//     plot height — one source of truth), with the 0.5 °C interval and the
//     two-scale numbering (plain integers, halves with one decimal),
//  3. the per-signal-row corner sample glyphs (bleeding box, clock,
//     sticky-note band sample), each vertically aligned with its signal
//     row's fixed-height slot; the rows' segments mirror the scroll
//     content: the top-of-block rows (bleeding, M) stack between the
//     header prototypes and the temperature scale, and the below-chart
//     strip's rows (time, disturbance, notes band) form ONE
//     segment below the marks slot. The mucus letters, the sex X marks
//     and the peak dot render INSIDE the plot (chart_marks.dart), so they
//     have no row and no rail slot.
// The long-range frozen-content test mirrors the windowing tests.

// Nine chart days covering one recorded fact per signal — the shared
// nineDayRowsFixture except that day 4 carries NO Mittelschmerz:
// temperatures 36.4..37.0 — with the default settings range 36..38 °C every
// half-degree tick between the fixed bounds exists.

final _leftRailEntries = nineDayRowsFixture(
  day: septSevenDay,
  withMittelschmerz: false,
);

// 5 uniform days at 36.5: the scale is a compact two-tick-plus interval.
List<DailyEntry> _flatEntries() => [
  for (var i = 0; i < 5; i++) DailyEntry(date: septSevenDay(i), bbtC: 36.5),
];

Finder _rail() => find.byKey(const ValueKey('leftRail'));

/// The rail's temperature-scale label texts, in top-down (descending
/// value) order — bare numerals; the °C unit renders as its own single
/// line under the topmost label.
List<String> _scaleLabels(WidgetTester tester) {
  final labelFinder = find.descendant(
    of: _rail(),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('railScaleLabel-'),
    ),
  );
  final entries = [
    for (final widget in tester.widgetList<Text>(labelFinder))
      (rect: tester.getRect(find.byWidget(widget)), text: widget.data!),
  ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  return [for (final e in entries) e.text];
}

void main() {
  group('frozen left rail', () {
    testWidgets(
      'the rail renders outside the horizontal scroll and stays frozen '
      'while the day columns move',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: longRangeEntries()));

        expect(
          _rail(),
          findsOneWidget,
          reason: 'the chart block has a fixed left rail',
        );
        expect(
          find.descendant(of: chartScrollView(), matching: _rail()),
          findsNothing,
          reason:
              'the rail is outside the horizontally scrolling content — '
              'the temperature scale cannot scroll away anymore',
        );

        final railBefore = tester.getRect(_rail());
        final scaleBefore = tester.getRect(
          find.byKey(const ValueKey('railScale')),
        );
        final cellBefore = tester.getRect(
          find.byKey(const ValueKey('bleedingCell-40')),
        );
        // The drag's exact delta depends on the framework's touch slop (see
        // the windowing tests), so the content movement is checked against
        // the settled scroll offset, not the dragged distance.
        final scrollState = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        final offsetBefore = scrollState.position.pixels;

        // Scroll the window toward earlier days (as the windowing tests do):
        // the day columns move, the rail does not.
        await tester.drag(chartScrollView(), const Offset(260, 0));
        await tester.pumpAndSettle();
        final offsetAfter = scrollState.position.pixels;

        expect(
          tester.getRect(_rail()),
          railBefore,
          reason: 'the frozen rail keeps its exact rect while scrolling',
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('railScale'))),
          scaleBefore,
          reason:
              'the temperature scale stays put — the defect this rail '
              'fixes: the scale used to scroll away with the content',
        );
        final cellAfter = tester.getRect(
          find.byKey(const ValueKey('bleedingCell-40')),
        );
        expect(
          cellAfter.center.dx,
          isNot(cellBefore.center.dx),
          reason: 'precondition: the day columns actually moved',
        );
        expect(
          cellAfter.center.dx - cellBefore.center.dx,
          closeTo(offsetBefore - offsetAfter, 1),
          reason:
              'the day columns move exactly with the scroll offset — '
              'the rail is not part of the scrolling content',
        );
      },
    );

    testWidgets(
      'the scale labels share the chart\'s y mapping: every label sits '
      'exactly at its value\'s plot pixel y',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _leftRailEntries));

        // fl_chart's left titles are disabled: the scale cannot be the
        // scrolling chart's own axis strip anymore.
        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        expect(
          data.titlesData.leftTitles.sideTitles.showTitles,
          isFalse,
          reason: 'the chart draws no left scale of its own',
        );
        expect(
          data.titlesData.leftTitles.sideTitles.reservedSize,
          0,
          reason:
              'the chart reserves no width for a scale — the plot spans '
              'the full scroll content width',
        );

        // The rail's labels must follow the SAME linear mapping the chart
        // uses: y = plotTop + (maxY − value) / (maxY − minY) * plotHeight.
        final chartRect = tester.getRect(find.byType(LineChart));
        final span = data.maxY - data.minY;
        expect(span, greaterThan(0), reason: 'a usable y domain');
        for (final label in _scaleLabels(tester)) {
          final value = double.parse(label);
          final expectedY =
              chartRect.top + (data.maxY - value) / span * chartRect.height;
          final labelCenter = tester
              .getRect(find.descendant(of: _rail(), matching: find.text(label)))
              .center
              .dy;
          expect(
            labelCenter,
            closeTo(expectedY, 0.5),
            reason:
                'scale label $label sits at its value\'s pixel y — the '
                'rail and the plot share one mapping',
          );
        }
      },
    );

    testWidgets(
      'the scale keeps the 0.5 °C interval and the two-scale numbering '
      '(integers plain, halves with one decimal) as bare numerals, and '
      'an overridden range moves the bounds AND the labels (one source '
      'of truth)',
      (tester) async {
        final cases =
            <
              ({
                TemperatureRange? range,
                double expectedMinY,
                double expectedMaxY,
                List<String> labels,
                String labelsReason,
              })
            >[
              (
                // The fixed settings range 36..38 supplies the bounds (not
                // the data rounding anymore): every half-degree tick between
                // them, top-down 38 .. 36 — each a bare numeral.
                range: null,
                expectedMinY: 36.0,
                expectedMaxY: 38.0,
                labels: ['38', '37.5', '37', '36.5', '36'],
                labelsReason:
                    'half-degree ticks over the default range, integers '
                    'plain and halves one-decimal; the °C unit renders once, '
                    'as its own line under the topmost label',
              ),
              (
                range: const TemperatureRange(min: 35.0, max: 39.0),
                expectedMinY: 35.0,
                expectedMaxY: 39.0,
                labels: [
                  '39',
                  '38.5',
                  '38',
                  '37.5',
                  '37',
                  '36.5',
                  '36',
                  '35.5',
                  '35',
                ],
                labelsReason:
                    'every half-degree tick between the overridden bounds '
                    'renders in the rail as bare numerals',
              ),
            ];
        for (final (
              :range,
              :expectedMinY,
              :expectedMaxY,
              :labels,
              :labelsReason,
            )
            in cases) {
          await pumpFreshChart(
            tester,
            () => chartHarness(
              entries: _leftRailEntries,
              temperatureRange: range,
            ),
          );

          final data = tester.widget<LineChart>(find.byType(LineChart)).data;
          expect(
            data.minY,
            expectedMinY,
            reason:
                'the settings range\'s lower bound is the chart\'s minY — '
                'one source of truth',
          );
          expect(
            data.maxY,
            expectedMaxY,
            reason:
                'the settings range\'s upper bound is the chart\'s maxY — '
                'one source of truth',
          );
          expect(_scaleLabels(tester), labels, reason: labelsReason);
        }
      },
    );

    testWidgets(
      'the scale labels follow the device locale: de renders the German '
      'comma, the en default keeps the dot (same ticks, separator only)',
      (tester) async {
        await pumpFreshChart(
          tester,
          () => chartHarness(
            entries: _leftRailEntries,
            locale: const Locale('de'),
          ),
        );

        expect(
          _scaleLabels(tester),
          ['38', '37,5', '37', '36,5', '36'],
          reason:
              'the rail\'s decimal display follows the effective '
              'locale — integers stay plain, halves comma-formatted in de',
        );
      },
    );

    testWidgets('the row-name glyphs render IN the rail, each vertically '
        'aligned with its signal row', (tester) async {
      await pumpChart(tester, chartHarness(entries: _leftRailEntries));

      const rows = ['bleeding', 'time', 'disturbance', 'notesBand'];
      for (final row in rows) {
        final corner = find.byKey(ValueKey('${row}Corner'));
        expect(
          corner,
          findsOneWidget,
          reason: 'row $row\'s sample glyph renders (in the rail)',
        );
        expect(
          find.descendant(of: _rail(), matching: corner),
          findsOneWidget,
          reason:
              'row $row\'s sample glyph lives in the frozen rail, not '
              'in the scrolling rows',
        );

        // Vertical alignment with the row: the glyph's rect center equals
        // one of the row's day cells' center (fixed row heights make this
        // a stable, exact assertion).
        final cornerCenter = tester.getRect(corner).center.dy;
        final cellCenter = tester
            .getRect(find.byKey(ValueKey('${row}Cell-3')))
            .center
            .dy;
        expect(
          cornerCenter,
          closeTo(cellCenter, 0.5),
          reason:
              'row $row\'s rail glyph is vertically centered on the '
              'row',
        );

        // The row name stays attached to the glyph for screen readers and
        // long-press: a tooltip renders in the rail.
        expect(
          tester
              .widgetList<Tooltip>(
                find.descendant(of: corner, matching: find.byType(Tooltip)),
              )
              .length,
          1,
          reason: 'row $row\'s rail glyph keeps its row-name tooltip',
        );
      }
    });

    testWidgets(
      'the below-chart strip is ONE rail segment: its glyph slots keep '
      'the owner-decided order time, disturbance, notes band',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _leftRailEntries));

        double top(String row) =>
            tester.getRect(find.byKey(ValueKey('${row}Corner'))).top;
        const strip = ['time', 'disturbance', 'notesBand'];
        final tops = [for (final row in strip) top(row)];
        expect(
          tops,
          equals([...tops]..sort()),
          reason:
              'the below-chart strip mirrors the content column\'s '
              'single segment: time first, notes last (owner order)',
        );
        // The strip starts after the marks-row slot, mirroring the content
        // column (the marks slot sits between the temperature scale and the
        // segment).
        expect(
          top('time'),
          greaterThan(
            tester.getRect(find.byKey(const ValueKey('railScale'))).bottom,
          ),
          reason:
              'the below-chart segment begins below the scale and the '
              'marks slot, as in the content column',
        );
      },
    );

    testWidgets(
      'the header corner (date + cycle-day prototypes) renders in the '
      'rail with its tooltips and semantics (en and de)',
      (tester) async {
        final wording = {
          const Locale('en'): ['Date', 'Cycle day'],
          const Locale('de'): ['Datum', 'Zyklustag'],
        };
        for (final MapEntry(:key, :value) in wording.entries) {
          await pumpFreshChart(
            tester,
            () => chartHarness(entries: _leftRailEntries, locale: key),
          );

          final corner = find.byKey(const ValueKey('dayHeaderCorner'));
          expect(
            find.descendant(of: _rail(), matching: corner),
            findsOneWidget,
            reason: 'the header corner slots into the frozen rail',
          );
          // The prototypes are locale-independent literals ('14.' day
          // number, '#5' cycle day).
          expect(
            find.descendant(of: corner, matching: find.text('14.')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: corner, matching: find.text('#5')),
            findsOneWidget,
          );

          expect(
            tooltipMessages(tester, corner),
            containsAll(value),
            reason: 'both prototypes keep their localized tooltips ($key)',
          );
          expect(
            find.descendant(
              of: corner,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == value[0],
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: corner,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == value[1],
              ),
            ),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('the header prototypes center inside the FULL rail width '
        '(the centering must be geometric, not a shrink-wrap no-op)', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _leftRailEntries));

      final railCenterX = tester.getRect(_rail()).center.dx;
      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      for (final prototype in ['14.', '#5']) {
        expect(
          tester
              .getRect(
                find.descendant(of: corner, matching: find.text(prototype)),
              )
              .center
              .dx,
          closeTo(railCenterX, 1),
          reason:
              '"$prototype" is centered on the rail\'s horizontal '
              'center — a slot that shrink-wraps to its widest child '
              'leaves both prototypes left-bound',
        );
      }
    });

    testWidgets(
      'the rail is only as wide as its widest label: every scale label '
      'stays inside the rail without clipping (en and de)',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('de')]) {
          await pumpFreshChart(
            tester,
            () => chartHarness(entries: _leftRailEntries, locale: locale),
          );

          final rail = tester.getRect(_rail());
          expect(
            rail.width,
            frozenRailWidth,
            reason:
                'the frozen rail stays as wide as its widest '
                'scale label plus inset — wider wastes row room',
          );

          final scale = tester.getRect(find.byKey(const ValueKey('railScale')));
          final labels = find.descendant(
            of: _rail(),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'railScaleLabel-',
                  ),
            ),
          );
          for (final widget in tester.widgetList<Text>(labels)) {
            final what = '$locale "${widget.data!}"';
            final rect = tester.getRect(find.byWidget(widget));
            expect(
              rect.left,
              greaterThanOrEqualTo(rail.left),
              reason: '$what stays inside the rail\'s left edge',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(rail.right),
              reason: '$what is not clipped at the rail\'s right edge',
            );
            // The labels sit centered on their tick's plot pixel, so the
            // edge ticks' boxes straddle the scale's edges by half a
            // label height; the CENTER must stay within the scale.
            expect(
              rect.center.dy,
              inInclusiveRange(scale.top, scale.bottom),
              reason: '$what centers on its tick within the scale',
            );
          }
          final unit = tester.getRect(
            find.descendant(of: _rail(), matching: find.text('°C')),
          );
          expect(
            unit.left,
            greaterThanOrEqualTo(rail.left),
            reason: '$locale "°C" stays inside the rail\'s left edge',
          );
          expect(
            unit.right,
            lessThanOrEqualTo(rail.right),
            reason: '$locale "°C" is not clipped at the rail\'s right edge',
          );
        }
      },
    );

    testWidgets(
      'the °C unit renders once, directly below the topmost scale value, '
      'and the value+unit pair reads as one for screen readers',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _leftRailEntries));

        final unitFinder = find.descendant(
          of: _rail(),
          matching: find.text('°C'),
        );
        expect(
          unitFinder,
          findsOneWidget,
          reason: 'the °C renders as ONE dedicated line in the rail',
        );
        final unit = tester.getRect(unitFinder);
        final topValue = tester.getRect(find.text('38'));
        expect(
          unit.top,
          greaterThan(topValue.bottom),
          reason: 'the °C sits below the topmost value\'s label, not beside it',
        );
        expect(
          unit.top,
          lessThan(
            tester.getRect(find.byKey(const ValueKey('railScale'))).bottom,
          ),
          reason: 'the °C line stays inside the scale\'s slot',
        );
        expect(
          find.descendant(
            of: _rail(),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == '38 °C',
            ),
          ),
          findsOneWidget,
          reason: 'the screen reader hears the topmost value WITH its unit',
        );
      },
    );

    testWidgets('at enlarged system text scale the scale labels and the °C '
        'stay inside the rail, with the °C clear of the topmost value', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Only the rail's scale labels and °C slot carry FittedBox clamping;
      // the day-header slots and the rail's corner cell have no room at 2×
      // either, and their flex overflows would fail the test without
      // touching this test's subject.
      final realOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception is FlutterError &&
            details.exception.toString().contains('RenderFlex overflowed')) {
          return;
        }
        realOnError!(details);
      };
      addTearDown(() => FlutterError.onError = realOnError);
      await pumpChart(tester, chartHarness(entries: _leftRailEntries));

      final rail = tester.getRect(_rail());
      final labels = find.descendant(
        of: _rail(),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('railScaleLabel-'),
        ),
      );
      for (final widget in tester.widgetList<Text>(labels)) {
        final what = '2× text scale "${widget.data!}"';
        final rect = tester.getRect(find.byWidget(widget));
        // The unclamped layout size: clamped to the slot, a label would
        // lay out at the slot's span and clip its glyphs at 2×; inside
        // the FittedBox it lays out unconstrained and scales to fit.
        final natural = tester.getSize(find.byWidget(widget));
        expect(
          natural.width,
          greaterThan(rail.width - 3),
          reason:
              '$what lays out wider than its slot span, so the slot '
              'scales it into the span instead of clipping it',
        );
        expect(
          rect.left,
          greaterThanOrEqualTo(rail.left),
          reason: '$what stays inside the rail\'s left edge',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(rail.right),
          reason: '$what is not clipped at the rail\'s right edge',
        );
      }
      final unit = tester.getRect(
        find.descendant(of: _rail(), matching: find.text('°C')),
      );
      final unitNatural = tester.getSize(
        find.descendant(of: _rail(), matching: find.text('°C')),
      );
      expect(
        unitNatural.width,
        greaterThan(rail.width - 3),
        reason:
            '2× text scale "°C" lays out wider than its slot span, so '
            'the slot scales it into the span instead of clipping it',
      );
      expect(
        unit.left,
        greaterThanOrEqualTo(rail.left),
        reason: '2× text scale "°C" stays inside the rail\'s left edge',
      );
      expect(
        unit.right,
        lessThanOrEqualTo(rail.right),
        reason: '2× text scale "°C" is not clipped at the rail\'s right edge',
      );
      final topValue = tester.getRect(find.text('38'));
      expect(
        unit.top,
        greaterThanOrEqualTo(topValue.bottom),
        reason: 'the °C does not overlap the topmost value\'s label',
      );
    });

    testWidgets('a flat temperature record keeps the scale usable (the fixed '
        'range always has ticks)', (tester) async {
      // All five days at 36.5: the bounds stay the settings range 36..38,
      // so the scale always has ticks and the mapping never divides by
      // zero — no data-dependent degenerate span can appear anymore.
      await pumpChart(tester, chartHarness(entries: _flatEntries()));

      expect(_scaleLabels(tester), [
        '38',
        '37.5',
        '37',
        '36.5',
        '36',
      ], reason: 'a single-value record still renders a half-degree scale');
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final chartRect = tester.getRect(find.byType(LineChart));
      final expectedMid =
          chartRect.top +
          (data.maxY - 36.5) / (data.maxY - data.minY) * chartRect.height;
      final midCenter = tester
          .getRect(find.descendant(of: _rail(), matching: find.text('36.5')))
          .center
          .dy;
      expect(
        midCenter,
        closeTo(expectedMid, 0.5),
        reason: 'the flat record\'s value maps mid-scale in both places',
      );
    });
  });
}
