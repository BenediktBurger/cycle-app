// Widget tests of the cycle chart card's vertical lines: the chart draws
// hairline vertical day lines (the paper's day columns), every row cell of
// the card carries a matching hairline right border, and every cycle start
// draws a THICK solid line through the whole card — as the chart's extra
// line at x = nextCycleStart − 0.5 and as a thick right border on the cell
// before the new cycle's first day in every row. The boundary predicate is
// derived once from the domain's mark-driven cycle grouping (lib/domain/
// cycle_grouping.dart): no line before the first cycleStart mark (the
// leading group), and a boundary is drawn even across untracked gap days.
//
// Same harness pattern as test/cycle_chart_rows_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

// 2026-09-07 is a Monday: a 12-day run Mon .. Fri (next week).
DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

/// One cycle group per cycleStart mark: marks at day indexes 5 and 9,
/// none before the first — the leading group (indexes 0..4) predates the
/// first mark. The bleeding values keep the PAPER row populated; the
/// boundaries themselves come from the marks.
final _twoCycleEntries = <DailyEntry>[
  for (var i = 0; i < 12; i++)
    DailyEntry(
        date: _day(i),
        bbtC: 36.5,
        bleeding: i == 5 || i == 9 ? Bleeding.heavy : Bleeding.none),
];

/// The cycleStart marks of the two-cycle scenario (at the marked days 5
/// and 9 — the same days that used to be bleeding onsets).
final _twoCycleMarks = <CycleMark>[
  CycleMark(date: _day(5), type: CycleMarkTypes.cycleStart),
  CycleMark(date: _day(9), type: CycleMarkTypes.cycleStart),
];

/// A gap scenario: day 0 tracked, days 1..4 untracked, a cycleStart mark
/// on an untracked gap day (say day 3) — the next tracked day 5 opens the
/// new cycle, and the boundary is drawn across the untracked gap days.
final _gapEntries = <DailyEntry>[
  DailyEntry(date: _day(0), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: _day(5), bbtC: 36.5, bleeding: Bleeding.heavy),
];

final _gapMarks = <CycleMark>[
  CycleMark(date: _day(3), type: CycleMarkTypes.cycleStart),
];

Finder _cell(int i, String row) => find.byKey(ValueKey('${row}Cell-$i'));

Widget _chartHarness(
        {required List<DailyEntry> entries,
        List<CycleMark> marks = const []}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(marks)),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: ZyklusScreen()),
      ),
    );

LineChartData _chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

ColorScheme _scheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme;

/// The card-row border container inside the cell of [index]/[row]: the
/// cell's decoration border is a non-uniform Border (right side only),
/// unlike every glyph's own decoration (uniform Border.all or none).
Border _cellRightBorder(WidgetTester tester, int index, String row) {
  final containers = tester.widgetList<Container>(
      find.descendant(of: _cell(index, row), matching: find.byType(Container)));
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<Border>()
      .firstWhere((b) => !b.isUniform,
          orElse: () => fail('no cell border found in cell $index of $row'));
}

void main() {
  group('vertical day lines', () {
    testWidgets(
        'the chart draws hairline vertical grid lines with interval 1 '
        'aligned to the shifted domain\'s column boundaries', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final grid = _chartData(tester).gridData;
      expect(grid.drawVerticalLine, isTrue,
          reason: 'the day columns are separated by vertical lines');
      expect(grid.verticalInterval, 1, reason: 'one line per day column');
      // The domain is half a column shifted (minX −0.5); with the baseline
      // at minX the interval-1 lines land on the interior column
      // boundaries 0.5, 1.5, … dayCount − 1.5.
      expect(_chartData(tester).baselineX, -0.5,
          reason: 'the grid baseline sits at the domain start so interval-1 '
              'lines land on column boundaries');
      final line = grid.getDrawingVerticalLine(0.5);
      expect(line.strokeWidth, lessThanOrEqualTo(1),
          reason: 'day lines are hairlines');
      expect(line.color, _scheme(tester).onSurface.withValues(alpha: 0.12),
          reason: 'the hairline is a subtle onSurface tint');
    });

    testWidgets(
        'every signal row\'s day cells carry a matching hairline right '
        'border, and the header row does too', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final onSurface = _scheme(tester).onSurface;
      for (final row in const [
        'bleeding',
        'mucus',
        'cervix',
        'sex',
        'pain',
        'time',
      ]) {
        final border = _cellRightBorder(tester, 1, row);
        expect(border.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: a hairline right border on the day cell');
        expect(border.right.color, onSurface.withValues(alpha: 0.12),
            reason: 'row $row: the border matches the chart\'s day line '
                'style');
      }

      // The header row's cells carry the same hairline (the day/cycle
      // header belongs to the card).
      final headerBorder = tester
          .widgetList<Container>(find.descendant(
              of: find.byKey(const ValueKey('dayLabel-1')),
              matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere((b) => !b.isUniform,
              orElse: () => fail('no header '
                  'cell border found'));
      expect(headerBorder.right.width, closeTo(0.5, 0.01));
    });

    testWidgets(
        'cycle starts draw thick solid lines: the chart\'s extra line at '
        'nextCycleStart − 0.5 and the thick right border on the cell '
        'before the new cycle in every row', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final onSurface = _scheme(tester).onSurface;
      final verticalLines = _chartData(tester).extraLinesData.verticalLines;
      final boundaryXs = verticalLines.map((l) => l.x).toSet();
      expect(boundaryXs, {4.5, 8.5},
          reason: 'the marked days at indexes 5 and 9 draw their separator '
              'at x = start − 0.5');
      for (final line in verticalLines) {
        expect(line.strokeWidth, closeTo(2, 0.01),
            reason: 'cycle-start lines are thick');
        expect(line.color, onSurface,
            reason: 'cycle-start lines are solid onSurface');
        expect(line.dashArray, isNull, reason: 'the line is solid, not dashed');
      }

      // The thick border sits on the cell BEFORE the new cycle (its right
      // edge is the separator), in every signal row.
      for (final row in const [
        'bleeding',
        'mucus',
        'cervix',
        'sex',
        'pain',
        'time',
      ]) {
        final thick = _cellRightBorder(tester, 4, row);
        expect(thick.right.width, closeTo(2, 0.01),
            reason: 'row $row: the boundary cell carries the thick border');
        expect(thick.right.color, onSurface,
            reason: 'row $row: the boundary border is solid onSurface');
        // The neighboring cells keep the hairline.
        final thinBefore = _cellRightBorder(tester, 3, row);
        expect(thinBefore.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: only the boundary cell is thick');
        final thinAfter = _cellRightBorder(tester, 5, row);
        expect(thinAfter.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: the new cycle\'s first day carries no thick '
                'border (the separator is to its LEFT)');
      }
    });

    testWidgets(
        'no cycle-start line before the first cycleStart mark (the '
        'leading group)', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final verticalLines = _chartData(tester).extraLinesData.verticalLines;
      expect(verticalLines.map((l) => l.x), isNot(contains(-0.5)),
          reason: 'the leading group\'s start is not a cycle-start line');

      // The first cell of every row keeps the plain hairline.
      final onSurface = _scheme(tester).onSurface;
      for (final row in const ['bleeding', 'mucus', 'time']) {
        final border = _cellRightBorder(tester, 0, row);
        expect(border.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: no thick border on the leading group\'s last '
                'cell');
        expect(border.right.color, onSurface.withValues(alpha: 0.12));
      }
    });

    testWidgets('a boundary across untracked gap days is still drawn',
        (tester) async {
      await tester
          .pumpWidget(_chartHarness(entries: _gapEntries, marks: _gapMarks));
      await tester.pumpAndSettle();

      final verticalLines = _chartData(tester).extraLinesData.verticalLines;
      expect(verticalLines.map((l) => l.x), contains(4.5),
          reason: 'the group opened across the untracked gap days draws '
              'its separator across the gap');
    });
  });
}
