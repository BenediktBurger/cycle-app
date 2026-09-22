// Shared finders and chart-view-state helpers for the widget tests — the
// interaction helpers the chart and shell tests kept copy-pasting.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The navigation shell carries each tab's label exactly once per surface;
/// scoping the taps here keeps them unambiguous even though every screen
/// (and its AppBar) is mounted at once — the shell keeps all tabs mounted in
/// an IndexedStack, so a bare find.text(label) matches the bar's/rail's
/// destination AND the mounted screen's AppBar title (tree order puts the
/// AppBar first, so a bare .first tap would miss). Both adaptive surfaces
/// match: the bottom NavigationBar (phone portrait) and the NavigationRail
/// (wide/landscape shell, width >= 720) — the shell test pins which one
/// renders at which size, this finder only needs to tap through either.
Finder navLabel(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail),
  matching: find.text(label),
);

/// The non-modal day options panel on the cycle screen (the converted
/// former modal bottom sheet): keyed wrapper the Zyklus screen renders
/// below the chart while a tapped day's options are showing.
Finder cycleDayPanel() => find.byKey(const ValueKey('cycleDayPanel'));

/// The Zyklus screen's vertical list scroller (the horizontal chart
/// scroller is excluded by direction). Offstage tabs are skipped
/// by default, so in the full-app scope this still matches once — if a
/// tree carries more than one vertical scroller in view, scope the finder
/// to the screen's descendant.
Finder cycleListScroller() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// The horizontal scroll view that carries the chart block. Callers that
/// share the tree with other screens (the tab shell keeps every tab
/// mounted) wrap this in a ZyklusScreen-scoped descendant finder.
Finder chartScrollView() => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

/// A chart-block recording-row cell: [row] = signal key (e.g. `bleeding`,
/// `cervix`, `disturbance`), [index] = the day column.
Finder chartCell(int index, String row) =>
    find.byKey(ValueKey('${row}Cell-$index'));

/// The row's header-corner prototype cell outside the day columns.
Finder chartCellCorner(String row) => find.byKey(ValueKey('${row}Corner'));

/// A finder scoped inside a chart-block cell.
Finder chartCellContent(int index, String row, Finder inner) =>
    find.descendant(of: chartCell(index, row), matching: inner);

/// The color-scheme brightness actually materialized by the running app,
/// taken from the shell's Scaffold (below the MaterialApp theme wiring).
Brightness materializedBrightness(WidgetTester tester) {
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  return Theme.of(scaffoldContext).colorScheme.brightness;
}

/// The full LineChartData of the (single) chart on screen.
LineChartData chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

/// The Material scheme the chart renders with (the app's ThemeData from
/// the harness MaterialApp).
ColorScheme chartScheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme;

/// The dot-only bars (invisible line) whose per-spot dot painters decide
/// how each temperature renders.
List<LineChartBarData> dotBars(WidgetTester tester) =>
    chartData(tester).lineBarsData.where((bar) {
      final color = bar.color;
      return color == null || color.a == 0;
    }).toList();

/// The dot painter for a day index, or null when the day has no temperature
/// point on the chart.
FlDotPainter? dotPainterOrNull(WidgetTester tester, int dayIndex) {
  for (final bar in dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final spot = bar.spots[i];
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, i);
      }
    }
  }
  return null;
}

/// The dot painter the chart would use for the temperature dot of [dayIndex]
/// (fails when that day has no temperature point on the chart).
FlDotPainter dotPainter(WidgetTester tester, int dayIndex) {
  final painter = dotPainterOrNull(tester, dayIndex);
  if (painter == null) fail('no temperature dot at day index $dayIndex');
  return painter;
}
