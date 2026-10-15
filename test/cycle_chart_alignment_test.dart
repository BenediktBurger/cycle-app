import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle chart's grid alignment invariant: day i's
// temperature dot lands exactly at the horizontal CENTER of its day column
// — the same center the day-label row and the signal rows use. The chart
// block's scroll content holds ONLY the day
// columns (the temperature scale and the corner prototypes live in the
// frozen left rail outside the scroll), so column i's cell is centered at
// (i + 0.5) * cellWidth from the content's left edge; the chart's x domain
// is half a column shifted (minX −0.5 .. maxX dayCount − 0.5) so the
// curve's dot for day i meets that same center.
//
// Also pins the degenerate single-day chart: its domain stays a usable
// non-zero-width window (−0.5..0.5) and taps still map to the one recorded
// day.

List<DailyEntry> _alignmentEntries(int count) => [
  for (var i = 0; i < count; i++)
    DailyEntry(date: septThreeDay(i), bbtC: 36.5 + (i % 5) * 0.1),
];

double _cellCenterX(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key))).center.dx;

void main() {
  testWidgets('day i\'s chart dot lands at the center of its label and '
      'signal cells', (tester) async {
    await pumpChart(tester, chartHarness(entries: _alignmentEntries(5)));

    for (var i = 0; i < 5; i++) {
      final dotX = chartDotX(tester, i);
      expect(
        dotX,
        closeTo(_cellCenterX(tester, 'bleedingCell-$i'), 0.5),
        reason:
            'day $i: the chart dot must sit at the bleeding row\'s '
            'cell horizontal center',
      );
      expect(
        dotX,
        closeTo(_cellCenterX(tester, 'dayLabel-$i'), 0.5),
        reason:
            'day $i: the chart dot must sit at the day label cell\'s '
            'horizontal center',
      );
      // The below-chart strip's rows keep the shared center too (their
      // windowed cells sit at the same global column positions).
      for (final row in ['time', 'disturbance', 'notesBand']) {
        expect(
          dotX,
          closeTo(_cellCenterX(tester, '${row}Cell-$i'), 0.5),
          reason:
              'day $i: the below-chart strip\'s $row row keeps the '
              'shared column center',
        );
      }
    }
  });

  testWidgets('a single recorded day keeps a usable domain and maps taps to '
      'that day', (tester) async {
    await pumpChart(tester, chartHarness(entries: _alignmentEntries(1)));

    // The lone day's dot sits at its column center — the domain is kept at
    // −0.5..0.5 (one full column wide) instead of collapsing.
    expect(
      chartDotX(tester, 0),
      closeTo(_cellCenterX(tester, 'bleedingCell-0'), 0.5),
      reason: 'the single day\'s column center matches its dot',
    );

    // Tapping the plot area opens the one recorded day's sheet.
    final rect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      cycleDayPanel(),
      findsOneWidget,
      reason: 'a tap on the single-day chart opens the day options panel',
    );
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(
      sheet.day,
      septThreeDay(0),
      reason: 'the single recorded day owns the whole plot',
    );
  });
}
