import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the temperature-disturbance letters in the cycle
// chart's below-chart strip: a day carrying one of the NER disturbance
// flags (late to bed, night awakening, alcohol, illness) renders its
// letter code in the disturbance row — in the day's column, keyed like the
// other rows — while plain days render nothing. The letters are the raw
// TempDisturbance tokens of the day's tempDisturbances mask, read
// through a single letter-mapping seam (see the comment on
// disturbanceLetters in lib/domain/disturbances.dart). The interrupted curve
// rendering is keyed to the ignoreTemperature MARK, not this mask —
// pinned by the temperature-curve tests in
// cycle_chart_temperature_test.dart.
//

// Six chart days:
//  0: plain temperature, no disturbance flag   -> nothing in the row
//  1: illness (kr bit)                         -> kr
//  2: alcohol (alk bit)                        -> alk
//  3: late to bed (sp bit)                     -> sp
//  4: night awakening (a bit)                  -> a
//  5: all four flags together                  -> kr, alk, sp, a stacked
final _disturbanceEntries = <DailyEntry>[
  DailyEntry(date: septSevenDay(0), bbtC: 36.5),
  DailyEntry(
    date: septSevenDay(1),
    bbtC: 36.6,
    tempDisturbances: TempDisturbance.kr.bit,
  ),
  DailyEntry(
    date: septSevenDay(2),
    bbtC: 36.7,
    tempDisturbances: TempDisturbance.alk.bit,
  ),
  DailyEntry(
    date: septSevenDay(3),
    bbtC: 36.4,
    tempDisturbances: TempDisturbance.sp.bit,
  ),
  DailyEntry(
    date: septSevenDay(4),
    bbtC: 36.5,
    tempDisturbances: TempDisturbance.a.bit,
  ),
  DailyEntry(
    date: septSevenDay(5),
    bbtC: 36.8,
    tempDisturbances: TempDisturbance.values.fold(0, (mask, d) => mask | d.bit),
  ),
];

void main() {
  testWidgets(
    'each set temperature-disturbance flag renders its letter token in '
    'the disturbance row of the below-chart strip, in the day\'s column',
    (tester) async {
      await pumpChart(tester, chartHarness(entries: _disturbanceEntries));

      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      for (final entry in {1: 'kr', 2: 'alk', 3: 'sp', 4: 'a'}.entries) {
        final cellRect = tester.getRect(chartCell(entry.key, 'disturbance'));
        expect(
          cellRect.top,
          greaterThan(chartBottom),
          reason:
              'the disturbance row is part of the below-chart strip, '
              'below the curve',
        );
        expect(
          chartCellContent(entry.key, 'disturbance', find.text(entry.value)),
          findsOneWidget,
          reason:
              'day ${entry.key} carries its disturbance flag\'s letter '
              'code (${entry.value}) in the day\'s column',
        );
        // The letter sits inside its day column horizontally (same column
        // geometry as every other row).
        final curveCell = tester.getRect(chartCell(entry.key, 'bleeding'));
        expect(
          cellRect.left,
          closeTo(curveCell.left, 0.5),
          reason: 'the disturbance cell shares the day column geometry',
        );
      }
    },
  );

  testWidgets('plain days render nothing in the disturbance row', (
    tester,
  ) async {
    await pumpChart(tester, chartHarness(entries: _disturbanceEntries));

    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      expect(
        chartCellContent(0, 'disturbance', find.text(letter)),
        findsNothing,
        reason: 'a plain day shows no letter code',
      );
    }
  });

  testWidgets('a multi-flag day renders its letters stacked in one cell', (
    tester,
  ) async {
    await pumpChart(tester, chartHarness(entries: _disturbanceEntries));

    final cell = tester.getRect(chartCell(5, 'disturbance'));
    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      final rects = chartCellContent(5, 'disturbance', find.text(letter))
          .evaluate()
          .map((element) {
            final box = element.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) & box.size;
          })
          .toList();
      expect(
        rects,
        hasLength(1),
        reason: 'the $letter code renders exactly once',
      );
      final rect = rects.single;
      expect(rect.left, greaterThanOrEqualTo(cell.left - 0.5));
      expect(
        rect.right,
        lessThanOrEqualTo(cell.right + 0.5),
        reason: 'the stacked letters stay inside the day column',
      );
    }
    // Stacked: the letters render at DIFFERENT vertical positions (the
    // paper sheet writes disturbance codes one under the other). Render
    // order follows the mask's token order — alk (bit 4) stacks above
    // kr (bit 8).
    final krRect = tester.getRect(
      chartCellContent(5, 'disturbance', find.text('kr')),
    );
    final alkRect = tester.getRect(
      chartCellContent(5, 'disturbance', find.text('alk')),
    );
    expect(
      alkRect.bottom,
      lessThanOrEqualTo(krRect.top),
      reason: 'the stacked letters do not overlap',
    );
  });

  testWidgets('tapping a disturbance cell opens the day sheet', (tester) async {
    await pumpChart(tester, chartHarness(entries: _disturbanceEntries));

    await tester.tap(chartCell(1, 'disturbance'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cycleDayPanel(), findsOneWidget);
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(
      sheet.day,
      septSevenDay(1),
      reason: 'the tapped disturbance cell owns day 1',
    );
  });

  testWidgets(
    'the disturbance row has a rail corner slot with the localized row '
    'name (en and de)',
    (tester) async {
      final wording = {
        const Locale('en'): 'Disturbed measurement',
        const Locale('de'): 'Messstörung',
      };
      for (final MapEntry(:key, :value) in wording.entries) {
        await pumpFreshChart(
          tester,
          () => chartHarness(entries: _disturbanceEntries, locale: key),
        );

        expect(chartCellCorner('disturbance'), findsOneWidget);
        expect(tooltipMessages(tester, chartCellCorner('disturbance')), [
          value,
        ], reason: '$key: the corner carries the localized row name');

        // Vertical alignment with its row (shared row heights, like every
        // other rail glyph).
        final cornerCenter = tester
            .getRect(chartCellCorner('disturbance'))
            .center
            .dy;
        final cellCenter = tester
            .getRect(chartCell(3, 'disturbance'))
            .center
            .dy;
        expect(
          cornerCenter,
          closeTo(cellCenter, 0.5),
          reason:
              'the disturbance rail glyph is vertically centered on the '
              'row',
        );
      }
    },
  );
}
