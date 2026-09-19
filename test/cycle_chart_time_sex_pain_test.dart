// Widget tests of the cycle tab's recorded-fact glyphs in the per-signal
// rows under the temperature curve: the measurement time renders as
// localized HH:mm text in its OWN row BELOW the chart block — rotated
// vertically when the day column is narrower than the text (never dropped,
// the old space-constraint bug), horizontal in wide columns (the old
// per-day clock glyph is gone — the clock lives only in the row corner),
// the sex time slots (one X glyph per SET SexTiming bit, drawn at
// that slot's third of the day column — multiple bits render multiple X
// marks), and the letter-coded pain flags B (breast, in the pain row) and
// M (Mittelschmerz, in its own row beneath the mucus row). Days without
// the respective fact render nothing. Same harness pattern as
// test/cycle_chart_cervix_test.dart (localized en, plus a de wording
// check).
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

import 'support/chart_pump.dart';

DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

// Seven-plus-one chart days:
//  0: temperature WITH a recorded measurement time (6:30) -> clock glyph
//  1: temperature WITHOUT a recorded time                  -> no clock
//  2: sex at the START slot, no temperature                -> X (start third)
//  3: breast pain only                                     -> B, no M
//  4: Mittelschmerz only                                   -> M, no B
//  5: sex at TWO slots AND both pains                      -> X, X, B, M
//  6: plain temperature day                                -> nothing new
//  7: cervix FIRMNESS only (no position) -> firmness glyph, no position
//     letters
List<DailyEntry> _entries() => [
      DailyEntry(
        date: _day(0),
        bbtC: 36.5,
        measuredAtMinutes: 6 * 60 + 30,
      ),
      DailyEntry(date: _day(1), bbtC: 36.4),
      DailyEntry(date: _day(2), sexTimings: SexTiming.start.bit),
      DailyEntry(date: _day(3), painBreast: true),
      DailyEntry(date: _day(4), painMittelschmerz: true),
      DailyEntry(
        date: _day(5),
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
        painBreast: true,
        painMittelschmerz: true,
      ),
      DailyEntry(date: _day(6), bbtC: 36.6),
      DailyEntry(
        date: _day(7),
        cervixFirmness: CervixFirmness.soft,
      ),
    ];

Widget _chartHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

void main() {
  group('measurement time — its own row below the chart block', () {
    testWidgets(
        'the time row renders BELOW the chart block, below the '
        'below-curve rows, for every day with a recorded measurement time',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries()));
      await tester.pumpAndSettle();

      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      // Own row below the block: the time row starts after the chart, and
      // after the below-curve rows (cervix, pain, disturbance).
      expect(tester.getRect(chartCell(0, 'time')).top, greaterThan(chartBottom),
          reason: 'the time row is not part of the chart block');
      for (final row in ['cervix', 'pain']) {
        expect(tester.getRect(chartCell(0, 'time')).top,
            greaterThan(tester.getRect(chartCell(0, row)).bottom),
            reason: 'the time row renders below the $row row');
      }
      // Every day with a recorded time renders its HH:mm (the fixture's
      // only recorded time is day 0).
      expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
    });

    testWidgets(
        'at minimum column width the time STILL renders — rotated '
        'vertically in its cell (regression: the time used to be dropped '
        'entirely at the space constraint)', (tester) async {
      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), far below the horizontal text threshold.
      // Give EVERY day a recorded measurement time so the narrow check
      // exercises the row everywhere.
      final entries = [
        for (var i = 0; i < 60; i++)
          DailyEntry(
            date: _day(i),
            bbtC: 36.5,
            measuredAtMinutes: 6 * 60 + 30,
          ),
      ];
      await tester.pumpWidget(_chartHarness(entries: entries));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(59, 'time')).width, closeTo(24, 0.5),
          reason: 'precondition: columns at the minimum usable width');

      Finder timeCells() => find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('timeCell-'));

      // The time text survives the space constraint: every rendered time
      // cell carries the rotated HH:mm text (RotatedBox), never empty.
      final rotated = find.descendant(
          of: find.byWidgetPredicate((w) =>
              w is RotatedBox && w.quarterTurns != 0),
          matching: find.text('06:30'));
      expect(rotated, findsWidgets,
          reason: 'at the minimum column width the time renders vertically '
              '— it is NEVER dropped');
      expect(
          find.descendant(of: timeCells(), matching: find.byType(RotatedBox)),
          findsWidgets,
          reason: 'the narrow cells rotate the time text');
    });

    testWidgets(
        'between the minimum and the threshold the time renders vertically '
        'too', (tester) async {
      // 25 days fit the viewport but leave only ~29 px per column — below
      // the threshold, so still vertical.
      final entries = [
        for (var i = 0; i < 25; i++)
          DailyEntry(
            date: _day(i),
            bbtC: 36.5,
            measuredAtMinutes: 6 * 60 + 30,
          ),
      ];
      await tester.pumpWidget(_chartHarness(entries: entries));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(24, 'time')).width, closeTo(29, 1.5),
          reason: 'precondition: narrow, non-minimum column width');
      expect(
          find.descendant(
              of: chartCell(24, 'time'),
              matching: find.descendant(
                  of: find.byWidgetPredicate(
                      (w) => w is RotatedBox && w.quarterTurns != 0),
                  matching: find.text('06:30'))),
          findsOneWidget,
          reason: 'a ~29 px column also renders the time vertically');
    });

    testWidgets('wide columns render the time horizontally, unrotated',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries()));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(0, 'time')).width, greaterThan(32),
          reason: 'precondition: a wide column');
      expect(
          find.descendant(
              of: chartCell(0, 'time'), matching: find.byType(RotatedBox)),
          findsNothing,
          reason: 'a wide column keeps the horizontal HH:mm text');
      expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
    });
  });
  testWidgets('the measurement time renders localized HH:mm text on days '
      'with a recorded measurement time — and nothing elsewhere',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    // 8+1 chart days fit the viewport comfortably, so the columns are wide
    // enough for the time text.
    expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget,
        reason: 'the temperature day WITH a recorded time shows the HH:mm '
            'text in its own time cell');
    expect(chartCellContent(1, 'time', find.text('06:30')), findsNothing,
        reason: 'a temperature WITHOUT a recorded time shows no time text');
    expect(chartCellContent(2, 'time', find.byType(Text)), findsNothing,
        reason: 'a temperature-free day can never carry a measurement time '
            '(the domain drops the time without a temperature)');
    expect(chartCellContent(6, 'time', find.byType(Text)), findsNothing,
        reason: 'a plain temperature day without a time shows nothing');
    expect(chartCellContent(2, 'time', find.byIcon(Icons.schedule)), findsNothing,
        reason: 'no per-day clock icon — the clock lives only in the row '
            'corner slot');
  });

  testWidgets('sex renders X marks only on days with recorded time slots',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(2, 'sex', find.text('X')), findsOneWidget,
        reason: 'the sex day shows the X glyph in its own cell');
    expect(chartCellContent(0, 'sex', find.text('X')), findsNothing,
        reason: 'no X on a temperature day without sex');
    expect(chartCellContent(6, 'sex', find.text('X')), findsNothing);
  });

  testWidgets('every set sex time slot renders its own X — multiple slots '
      'render multiple X marks on one day', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(5, 'sex', find.text('X')), findsNWidgets(2),
        reason: 'two recorded slots (start + end) render two X marks');
    expect(chartCellContent(2, 'sex', find.text('X')), findsOneWidget,
        reason: 'a single recorded slot renders exactly one X');
  });

  testWidgets('each X sits at its slot\'s third of the day column',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    double fractionOf(Rect cell, Rect glyph) =>
        (glyph.center.dx - cell.left) / cell.width;

    final cell2 = tester.getRect(chartCell(2, 'sex'));
    final startX = tester.getRect(chartCellContent(2, 'sex', find.text('X')));
    expect(fractionOf(cell2, startX), closeTo(1 / 6, 0.05),
        reason: 'a start-slot X renders in the START third (center ~1/6) of '
            'the day column');

    final cell5 = tester.getRect(chartCell(5, 'sex'));
    final xRects = chartCellContent(5, 'sex', find.text('X')).evaluate().map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList()
      ..sort((a, b) => a.center.dx.compareTo(b.center.dx));
    expect(xRects, hasLength(2),
        reason: 'both X marks must sit inside their own day column');
    expect(fractionOf(cell5, xRects.first), closeTo(1 / 6, 0.05),
        reason: 'the first X belongs to the start slot (left third)');
    expect(fractionOf(cell5, xRects.last), closeTo(5 / 6, 0.05),
        reason: 'the second X belongs to the end slot (right third)');
  });

  testWidgets('pain renders B in its row; Mittelschmerz renders M in its '
      'own row beneath the mucus row', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(3, 'pain', find.text('B')), findsOneWidget,
        reason: 'breast pain shows the B letter in the pain row');
    expect(chartCellContent(3, 'pain', find.text('M')), findsNothing,
        reason: 'no Mittelschmerz letter without the flag — and the M '
            'letter home is its own row anyway');
    expect(chartCellContent(4, 'mittelschmerz', find.text('M')), findsOneWidget,
        reason: 'Mittelschmerz shows the M letter in its own row beneath '
            'the mucus row (flagged TODO(user-review) in the chart code)');
    expect(chartCellContent(4, 'pain', find.text('M')), findsNothing,
        reason: 'the M letter no longer renders in the below-curve pain '
            'row');
    expect(chartCellContent(4, 'pain', find.text('B')), findsNothing,
        reason: 'no breast letter without the flag');
    expect(chartCellContent(5, 'pain', find.text('B')), findsOneWidget);
    expect(chartCellContent(5, 'mittelschmerz', find.text('M')), findsOneWidget);
    expect(chartCellContent(6, 'pain', find.text('B')), findsNothing,
        reason: 'a plain day shows no pain letter');
    expect(chartCellContent(6, 'mittelschmerz', find.text('M')), findsNothing);
  });

  testWidgets('a combined day carries the sex X marks alongside both pain '
      'letters (B in the pain row, M beneath the mucus row)',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(5, 'sex', find.text('X')), findsNWidgets(2),
        reason: 'the sex X marks render in their own row');
    expect(chartCellContent(5, 'pain', find.text('B')), findsOneWidget,
        reason: 'the pain letter renders in its own row beside the sex '
            'row');
    expect(chartCellContent(5, 'mittelschmerz', find.text('M')), findsOneWidget,
        reason: 'the Mittelschmerz letter renders in its own row beneath '
            'the mucus row');
  });

  testWidgets('a firmness-only day renders its glyph with no position '
      'letters', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(7, 'cervix', find.text('w')), findsOneWidget,
        reason: 'the soft-firmness glyph (paper shorthand w) renders in its '
            'own cell');
    for (final glyph in ['t', 'm', 'h', 'sh', 'u']) {
      expect(chartCellContent(7, 'cervix', find.text(glyph)), findsNothing,
          reason: 'no position letter ($glyph) without a position '
              'observation');
    }
  });

  testWidgets('the help sheet names the measurement time, sex, firmness, '
      'and the pain letters', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    // The on-screen legend moved into the help sheet.
    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(find.text('Measurement time'), findsOneWidget,
        reason: 'the clock glyph needs a legend entry');
    expect(find.text('Sex (X per time of day)'), findsOneWidget,
        reason: 'the X glyph needs a legend entry; the wording mentions the '
            'per-slot X now that a day can carry several');
    expect(find.text('Cervix firmness'), findsOneWidget,
        reason: 'the firmness glyph needs a legend entry, parallel to the '
            'position entry');
    expect(find.text('Breast pain (B)'), findsOneWidget,
        reason: 'the B letter keeps its legend entry (the M letter has '
            'its own row and its own entry)');
    expect(find.text('Mittelschmerz (M)'), findsOneWidget,
        reason: 'the M letter has its own legend entry — it renders in '
            'its own row beneath the mucus row');
  });

  testWidgets('the German help sheet uses the German wording',
      (tester) async {
    await tester.pumpWidget(_chartHarness(
        entries: _entries(), locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(find.text('Messzeitpunkt'), findsOneWidget);
    expect(find.text('Sex (X je Zeitpunkt)'), findsOneWidget,
        reason: 'the diary already uses "Sex" in the German vocabulary');
    expect(find.text('Muttermund-Festigkeit'), findsOneWidget);
    expect(find.text('Brustschmerz (B)'), findsOneWidget);
    expect(find.text('Mittelschmerz (M)'), findsOneWidget);
  });
}
