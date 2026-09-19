// Widget tests of the cycle chart's grid alignment invariant: day i's
// temperature dot lands exactly at the horizontal CENTER of its day column
// — the same center the day-label row, the signal rows and the evaluation
// marks row use. The chart block's scroll content holds ONLY the day
// columns (the temperature scale and the corner prototypes live in the
// frozen left rail outside the scroll), so column i's cell is centered at
// (i + 0.5) * cellWidth from the content's left edge; the chart's x domain
// is half a column shifted (minX −0.5 .. maxX dayCount − 0.5) so the
// curve's dot for day i meets that same center.
//
// Also pins the degenerate single-day chart: its domain stays a usable
// non-zero-width window (−0.5..0.5) and taps still map to the one recorded
// day.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chart_pump.dart';

// 2026-09-03 is a Thursday: a five-day Thu..Mon range fits the viewport.
DateTime _day(int index) => DateTime.utc(2026, 9, 3).add(Duration(days: index));

List<DailyEntry> _entries(int count) => [
      for (var i = 0; i < count; i++)
        DailyEntry(date: _day(i), bbtC: 36.5 + (i % 5) * 0.1),
    ];

/// The rendered global x of day [dayIndex]'s chart dot: the chart maps its
/// x domain linearly onto the plot area, which spans the chart widget's
/// full width — the stripless scroll content starts at the plot's left
/// edge (the frozen rail sits outside).
double _dotX(WidgetTester tester, int dayIndex) {
  final rect = tester.getRect(find.byType(LineChart));
  final data = tester.widget<LineChart>(find.byType(LineChart)).data;
  final t = (dayIndex - data.minX) / (data.maxX - data.minX);
  return rect.left + t * rect.width;
}

double _cellCenterX(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key))).center.dx;

Widget _chartHarness({required List<DailyEntry> entries}) =>
    chartHarness(entries: entries);

void main() {
  testWidgets(
      'day i\'s chart dot lands at the center of its label, marks and '
      'symbol cell', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries(5)));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      final dotX = _dotX(tester, i);
      expect(dotX, closeTo(_cellCenterX(tester, 'bleedingCell-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the bleeding row\'s '
              'cell horizontal center');
      expect(dotX, closeTo(_cellCenterX(tester, 'mucusCell-$i'), 0.5),
          reason: 'day $i: the top-of-block mucus row keeps the shared '
              'column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'mittelschmerzCell-$i'), 0.5),
          reason: 'day $i: the Mittelschmerz row under the mucus row keeps '
              'the shared column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'sexCell-$i'), 0.5),
          reason: 'day $i: the top-of-block sex row keeps the shared '
              'column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'dayLabel-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the day label cell\'s '
              'horizontal center');
      expect(dotX, closeTo(_cellCenterX(tester, 'marksCell-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the marks cell\'s '
              'horizontal center');
    }
  });

  testWidgets(
      'a single recorded day keeps a usable domain and maps taps to '
      'that day', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries(1)));
    await tester.pumpAndSettle();

    // The lone day's dot sits at its column center — the domain is kept at
    // −0.5..0.5 (one full column wide) instead of collapsing.
    expect(
        _dotX(tester, 0), closeTo(_cellCenterX(tester, 'bleedingCell-0'), 0.5),
        reason: 'the single day\'s column center matches its dot');

    // Tapping the plot area opens the one recorded day's sheet.
    final rect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'a tap on the single-day chart opens the day sheet');
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _day(0),
        reason: 'the single recorded day owns the whole plot');
  });
}
