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
//  3. the per-signal-row corner sample glyphs (bleeding blob, S,
//     Mittelschmerz M, X, cervix letter, B, clock), each vertically
//     aligned with its signal row's fixed-height slot; the rows' segments
//     mirror the scroll content: the top-of-block rows (bleeding, mucus,
//     M, sex) stack between the header prototypes and the temperature
//     scale, the below-curve rows (cervix, pain) below the marks slot,
//     and the below-block rows (time, note) at the rail's tail.
// Same harness pattern as test/cycle_chart_rows_test.dart (long-range
// frozen-content test mirrors test/cycle_chart_windowing_test.dart).
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

import 'support/finders.dart';

import 'support/chart_pump.dart';

// Nine chart days covering one recorded fact per signal (the per-signal
// rows fixture of test/cycle_chart_rows_test.dart, shifted a year later):
// temperatures 36.4..37.0, so the scale spans 36..37.5 and every 0.5 step
// tick exists. Unlike the rows fixture, day 4 carries NO Mittelschmerz.
DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

final _entries = nineDayRowsFixture(day: _day, withMittelschmerz: false);

// 5 uniform days at 36.5: the scale is a compact two-tick-plus interval.
List<DailyEntry> _flatEntries() => [
      for (var i = 0; i < 5; i++) DailyEntry(date: _day(i), bbtC: 36.5),
    ];

Finder _rail() => find.byKey(const ValueKey('leftRail'));

/// The rail's temperature-scale label texts, in top-down (descending
/// value) order.
List<String> _scaleLabels(WidgetTester tester) {
  final labelFinder = find.descendant(
      of: _rail(),
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('railScaleLabel-')));
  final entries = [
    for (final widget in tester.widgetList<Text>(labelFinder))
      (rect: tester.getRect(find.byWidget(widget)), text: widget.data!),
  ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  return [for (final e in entries) e.text];
}

Widget _chartHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

void main() {
  group('frozen left rail', () {
    testWidgets(
        'the rail renders outside the horizontal scroll and stays frozen '
        'while the day columns move', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      expect(_rail(), findsOneWidget,
          reason: 'the chart block has a fixed left rail');
      expect(find.descendant(of: chartScrollView(), matching: _rail()),
          findsNothing,
          reason: 'the rail is outside the horizontally scrolling content — '
              'the temperature scale cannot scroll away anymore');

      final railBefore = tester.getRect(_rail());
      final scaleBefore =
          tester.getRect(find.byKey(const ValueKey('railScale')));
      final cellBefore =
          tester.getRect(find.byKey(const ValueKey('bleedingCell-40')));
      // The drag's exact delta depends on the framework's touch slop (see
      // the windowing tests), so the content movement is checked against
      // the settled scroll offset, not the dragged distance.
      final scrollState = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      final offsetBefore = scrollState.position.pixels;

      // Scroll the window toward earlier days (as the windowing tests do):
      // the day columns move, the rail does not.
      await tester.drag(chartScrollView(), const Offset(260, 0));
      await tester.pumpAndSettle();
      final offsetAfter = scrollState.position.pixels;

      expect(tester.getRect(_rail()), railBefore,
          reason: 'the frozen rail keeps its exact rect while scrolling');
      expect(
          tester.getRect(find.byKey(const ValueKey('railScale'))), scaleBefore,
          reason: 'the temperature scale stays put — the defect this rail '
              'fixes: the scale used to scroll away with the content');
      final cellAfter =
          tester.getRect(find.byKey(const ValueKey('bleedingCell-40')));
      expect(cellAfter.center.dx, isNot(cellBefore.center.dx),
          reason: 'precondition: the day columns actually moved');
      expect(cellAfter.center.dx - cellBefore.center.dx,
          closeTo(offsetBefore - offsetAfter, 1),
          reason: 'the day columns move exactly with the scroll offset — '
              'the rail is not part of the scrolling content');
    });

    testWidgets(
        'the scale labels share the chart\'s y mapping: every label sits '
        'exactly at its value\'s plot pixel y', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // fl_chart's left titles are disabled: the scale cannot be the
      // scrolling chart's own axis strip anymore.
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.titlesData.leftTitles.sideTitles.showTitles, isFalse,
          reason: 'the chart no longer draws its own left scale');
      expect(data.titlesData.leftTitles.sideTitles.reservedSize, 0,
          reason: 'the chart reserves no width for a scale — the plot spans '
              'the full scroll content width');

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
        expect(labelCenter, closeTo(expectedY, 0.5),
            reason: 'scale label $label sits at its value\'s pixel y — the '
                'rail and the plot share one mapping');
      }
    });

    testWidgets(
        'the scale keeps the 0.5 °C interval and the two-scale numbering '
        '(integers plain, halves with one decimal)', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // Values 36.4..37.0 → rounded bounds 36..37.5 → every half-degree
      // tick, top-down 37.5 .. 36.
      expect(_scaleLabels(tester), ['37.5', '37', '36.5', '36'],
          reason: 'half-degree ticks with integers plain and halves '
              'one-decimal');
    });

    testWidgets(
        'the six row-name glyphs render IN the rail, each vertically '
        'aligned with its signal row', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      const rows = [
        'bleeding',
        'mucus',
        'mittelschmerz',
        'sex',
        'cervix',
        'pain',
        'disturbance',
        'time',
        'note',
      ];
      for (final row in rows) {
        final corner = find.byKey(ValueKey('${row}Corner'));
        expect(corner, findsOneWidget,
            reason: 'row $row\'s sample glyph renders (in the rail)');
        expect(find.descendant(of: _rail(), matching: corner), findsOneWidget,
            reason: 'row $row\'s sample glyph lives in the frozen rail, not '
                'in the scrolling rows');

        // Vertical alignment with the row: the glyph's rect center equals
        // one of the row's day cells' center (fixed row heights make this
        // a stable, exact assertion).
        final cornerCenter = tester.getRect(corner).center.dy;
        final cellCenter =
            tester.getRect(find.byKey(ValueKey('${row}Cell-3'))).center.dy;
        expect(cornerCenter, closeTo(cellCenter, 0.5),
            reason: 'row $row\'s rail glyph is vertically centered on the '
                'row');

        // The row name stays attached to the glyph for screen readers and
        // long-press: a tooltip renders in the rail.
        expect(
            tester
                .widgetList<Tooltip>(
                    find.descendant(of: corner, matching: find.byType(Tooltip)))
                .length,
            1,
            reason: 'row $row\'s rail glyph keeps its row-name tooltip');
      }
    });

    testWidgets(
        'the header corner (date + cycle-day prototypes) renders in the '
        'rail with its tooltips and semantics', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      expect(find.descendant(of: _rail(), matching: corner), findsOneWidget,
          reason: 'the header corner slots into the frozen rail');
      expect(find.descendant(of: corner, matching: find.text('14.')),
          findsOneWidget);
      expect(find.descendant(of: corner, matching: find.text('#5')),
          findsOneWidget);

      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Date', 'Cycle day']),
          reason: 'both prototypes keep their localized tooltips');
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Date')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Cycle day')),
        findsOneWidget,
      );
    });

    testWidgets('the corner prototypes use the German wording in de',
        (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Datum', 'Zyklustag']));
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Datum')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Zyklustag')),
        findsOneWidget,
      );
    });

    testWidgets(
        'a flat temperature record keeps the scale usable (degenerate '
        'span guard)', (tester) async {
      // All five days at 36.5: the rounded bounds stay 36..37 so the
      // scale has ticks and the mapping never divides by zero.
      await tester.pumpWidget(_chartHarness(entries: _flatEntries()));
      await tester.pumpAndSettle();

      expect(_scaleLabels(tester), ['37', '36.5', '36'],
          reason: 'a single-value record still renders a half-degree scale');
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final chartRect = tester.getRect(find.byType(LineChart));
      final expectedMid = chartRect.top +
          (data.maxY - 36.5) / (data.maxY - data.minY) * chartRect.height;
      final midCenter = tester
          .getRect(find.descendant(of: _rail(), matching: find.text('36.5')))
          .center
          .dy;
      expect(midCenter, closeTo(expectedMid, 0.5),
          reason: 'the flat record\'s value maps mid-scale in both places');
    });
  });
}
