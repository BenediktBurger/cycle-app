import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

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

/// One cycle group per cycleStart mark: marks at day indexes 5 and 9,
/// none before the first — the leading group (indexes 0..4) predates the
/// first mark. The bleeding values keep the PAPER row populated; the
/// boundaries themselves come from the marks.
final _twoCycleEntries = <DailyEntry>[
  for (var i = 0; i < 12; i++)
    DailyEntry(
      date: septSevenDay(i),
      bbtC: 36.5,
      bleeding: i == 5 || i == 9 ? Bleeding.heavy : Bleeding.none,
    ),
];

/// The cycleStart marks of the two-cycle scenario: the heavy-bleeding
/// days 5 and 9 carry the cycleStart mark.
final _twoCycleMarks = <CycleMark>[
  CycleMark(date: septSevenDay(5), type: CycleMarkTypes.cycleStart),
  CycleMark(date: septSevenDay(9), type: CycleMarkTypes.cycleStart),
];

/// A gap scenario: day 0 tracked, days 1..4 untracked, a cycleStart mark
/// on the untracked gap day 3 — the mark date itself is the new cycle's
/// start (the untracked gap days belong to it), so the separator is drawn
/// at day 3's column, between the mark and the next tracked day 5.
final _gapEntries = <DailyEntry>[
  DailyEntry(date: septSevenDay(0), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: septSevenDay(5), bbtC: 36.5, bleeding: Bleeding.heavy),
];

final _gapMarks = <CycleMark>[
  CycleMark(date: septSevenDay(3), type: CycleMarkTypes.cycleStart),
];

// The FIRST tracked day itself carries the cycleStart mark: tracking began
// right on a cycle start (e.g. continued from the paper sheet), so there
// is NO leading pre-mark group and the recorded range's LEFT edge is the
// first cycle boundary.
final _firstDayBoundaryEntries = longRangeEntries(12);

final _firstDayBoundaryMarks = <CycleMark>[
  CycleMark(date: longRangeDay(0), type: CycleMarkTypes.cycleStart),
];

/// The card-row border container inside the cell of [index]/[row]: the
/// cell's decoration border is a non-uniform Border (right side only),
/// unlike every glyph's own decoration (uniform Border.all or none). The
/// recording-row cells key the whole cell (the border Container is a
/// descendant of the key), but the in-plot glyphs carry no cell borders.
/// Both search directions stay.
Border _cellBorder(WidgetTester tester, int index, String row) {
  final cell = chartCell(index, row);
  final containers = [
    ...tester.widgetList<Container>(
      find.descendant(of: cell, matching: find.byType(Container)),
    ),
    ...tester.widgetList<Container>(
      find.ancestor(of: cell, matching: find.byType(Container)),
    ),
  ];
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<Border>()
      .firstWhere(
        (b) => !b.isUniform,
        orElse: () => fail('no cell border found in cell $index of $row'),
      );
}

// The emphasized horizontal grid steps' dash pattern: inline literals in
// lib/ui/cycle_chart.dart (the help sheet's legend mirrors them), restated
// here once for the grid assertions.
const _emphasizedStepDashPattern = [4, 3];

void main() {
  group('vertical day lines', () {
    testWidgets('the chart draws hairline vertical grid lines with interval 1 '
        'aligned to the shifted domain\'s column boundaries', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final grid = chartData(tester).gridData;
      expect(
        grid.drawVerticalLine,
        isTrue,
        reason: 'the day columns are separated by vertical lines',
      );
      expect(grid.verticalInterval, 1, reason: 'one line per day column');
      // The domain is half a column shifted (minX −0.5); with the baseline
      // at minX the interval-1 lines land on the interior column
      // boundaries 0.5, 1.5, … dayCount − 1.5.
      expect(
        chartData(tester).baselineX,
        -0.5,
        reason:
            'the grid baseline sits at the domain start so interval-1 '
            'lines land on column boundaries',
      );
      final line = grid.getDrawingVerticalLine(0.5);
      expect(
        line.strokeWidth,
        lessThanOrEqualTo(1),
        reason: 'day lines are hairlines',
      );
      expect(
        line.color,
        chartScheme(tester).onSurface.withValues(alpha: 0.12),
        reason: 'the hairline is a subtle onSurface tint',
      );
    });

    testWidgets('every signal row\'s day cells carry a matching hairline right '
        'border, and the header row does too', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final onSurface = chartScheme(tester).onSurface;
      for (final row in const ['bleeding', 'time', 'notesBand']) {
        final border = _cellBorder(tester, 1, row);
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason: 'row $row: a hairline right border on the day cell',
        );
        expect(
          border.right.color,
          onSurface.withValues(alpha: 0.12),
          reason:
              'row $row: the border matches the chart\'s day line '
              'style',
        );
      }

      // The header row's cells carry the same hairline (the day/cycle
      // header belongs to the card).
      final headerBorder = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('dayLabel-1')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere(
            (b) => !b.isUniform,
            orElse: () => fail(
              'no header '
              'cell border found',
            ),
          );
      expect(headerBorder.right.width, closeTo(0.5, 0.01));
    });

    testWidgets(
      'cycle starts draw thick solid lines: the chart\'s extra line at '
      'nextCycleStart − 0.5 and the thick right border on the cell '
      'before the new cycle in every row',
      (tester) async {
        await pumpChart(
          tester,
          chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
        );

        final onSurface = chartScheme(tester).onSurface;
        final verticalLines = chartData(tester).extraLinesData.verticalLines;
        final boundaryXs = verticalLines.map((l) => l.x).toSet();
        expect(
          boundaryXs,
          {4.5, 8.5},
          reason:
              'the marked days at indexes 5 and 9 draw their separator '
              'at x = start − 0.5',
        );
        for (final line in verticalLines) {
          expect(
            line.strokeWidth,
            closeTo(2, 0.01),
            reason: 'cycle-start lines are thick',
          );
          expect(
            line.color,
            onSurface,
            reason: 'cycle-start lines are solid onSurface',
          );
          expect(
            line.dashArray,
            isNull,
            reason: 'the line is solid, not dashed',
          );
        }

        // The thick border sits on the cell BEFORE the new cycle (its right
        // edge is the separator), in every signal row.
        for (final row in const ['bleeding', 'time', 'notesBand']) {
          final thick = _cellBorder(tester, 4, row);
          expect(
            thick.right.width,
            closeTo(2, 0.01),
            reason: 'row $row: the boundary cell carries the thick border',
          );
          expect(
            thick.right.color,
            onSurface,
            reason: 'row $row: the boundary border is solid onSurface',
          );
          // The neighboring cells keep the hairline.
          final thinBefore = _cellBorder(tester, 3, row);
          expect(
            thinBefore.right.width,
            closeTo(0.5, 0.01),
            reason: 'row $row: only the boundary cell is thick',
          );
          final thinAfter = _cellBorder(tester, 5, row);
          expect(
            thinAfter.right.width,
            closeTo(0.5, 0.01),
            reason:
                'row $row: the new cycle\'s first day carries no thick '
                'border (the separator is to its LEFT)',
          );
        }
      },
    );

    testWidgets('no cycle-start line before the first cycleStart mark (the '
        'leading group)', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      expect(
        verticalLines.map((l) => l.x),
        isNot(contains(-0.5)),
        reason: 'the leading group\'s start is not a cycle-start line',
      );

      // The first cell of every row keeps the plain hairline.
      final onSurface = chartScheme(tester).onSurface;
      for (final row in const ['bleeding', 'time']) {
        final border = _cellBorder(tester, 0, row);
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason:
              'row $row: no thick border on the leading group\'s last '
              'cell',
        );
        expect(border.right.color, onSurface.withValues(alpha: 0.12));
      }
    });

    testWidgets('a cycle start on the FIRST tracked day is a boundary at the '
        'range\'s left edge: the ordinal chip renders at index 0 and the '
        'first day cells thicken their LEFT border (the mirror of the '
        'right-edge separator rule)', (tester) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _firstDayBoundaryEntries,
          marks: _firstDayBoundaryMarks,
        ),
      );

      final onSurface = chartScheme(tester).onSurface;

      // The ordinal chip renders at index 0, pinned to the plot's left
      // edge (the boundary column's start).
      final chip = find.byKey(const ValueKey('cycleOrdinalChip-0'));
      final plot = tester.getRect(find.byType(LineChart));
      expect(
        tester.getRect(chip).left,
        closeTo(plot.left + 2, 2.5),
        reason:
            'day-index 0: the chip pins to the boundary column\'s start, '
            'the recorded range\'s left edge',
      );

      // The domain-edge boundary paints through the first day cells' thick
      // LEFT border — the mirror of every interior boundary's thick RIGHT
      // border on the cell before the new cycle. (The chart's extra
      // separator line would sit exactly at the domain's left edge x =
      // −0.5, where its 2 px stroke clamps outside the plot.)
      const edgeThickRows = ['bleeding', 'time', 'notesBand'];
      for (final row in edgeThickRows) {
        final border = _cellBorder(tester, 0, row);
        expect(
          border.left.width,
          closeTo(2, 0.01),
          reason:
              'row $row: the range\'s first cell carries the thick '
              'left boundary border',
        );
        expect(
          border.left.color,
          onSurface,
          reason: 'row $row: the boundary border is solid onSurface',
        );
        // The separator goes to the LEFT of the boundary column, so the
        // first cell's right edge keeps the plain hairline.
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason: 'row $row: the first day keeps the hairline right edge',
        );
      }
      // The header row's first cell carries the same thick left border.
      final headerBorder = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('dayLabel-0')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere(
            (b) => !b.isUniform,
            orElse: () => fail('no header cell border found'),
          );
      expect(headerBorder.left.width, closeTo(2, 0.01));
      expect(headerBorder.left.color, onSurface);

      // The extra-line list carries no edge line: the boundary at the
      // recorded range's left edge is painted by the cells' borders, not
      // by a chart line that would clamp at the plot edge.
      expect(
        chartData(tester).extraLinesData.verticalLines.map((l) => l.x),
        isNot(contains(-0.5)),
        reason:
            'the left-edge boundary does not draw an extra line at the '
            'domain edge — the cells\' left borders carry it',
      );
    });

    testWidgets('a boundary mark inside untracked gap days draws its '
        'separator at the mark\'s own day column', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _gapEntries, marks: _gapMarks),
      );

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      // The mark sits on the untracked day index 3; the separator runs
      // through the gap at the mark's own column (not at the next tracked
      // day) — the boundary anchor is the mark date, and the line is
      // drawn at the boundary day's column START (x = i − 0.5).
      expect(
        verticalLines.map((l) => l.x),
        contains(2.5),
        reason:
            'the mark inside the untracked gap draws its separator at '
            'the mark\'s own day column',
      );
      expect(
        verticalLines.map((l) => l.x),
        isNot(contains(4.5)),
        reason:
            'the new cycle\'s first tracked day is no separator line: '
            'the boundary anchored on the mark date',
      );
    });

    testWidgets('the in-plot ordinal badge pins its left edge to the boundary '
        'column (the pixel the separator is drawn through)', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      // The badge chip renders inside the temperature plot, and its LEFT
      // edge pins to the boundary day's column start — pixel i · cellWidth
      // measured from the plot's left edge (a small inset tolerated), the
      // same pixel the thick separator's chart-domain x = i − 0.5 maps to.
      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / _twoCycleEntries.length;
      for (final i in [5, 9]) {
        final chipRect = tester.getRect(
          find.byKey(ValueKey('cycleOrdinalChip-$i')),
        );
        expect(
          chipRect.left,
          closeTo(plot.left + i * colW, 2.5),
          reason:
              'day-index $i: the badge\'s left edge pins to its '
              'cycle\'s first column inside the plot',
        );
      }
    });

    testWidgets('the in-plot ordinal badge shrink-wraps its background to the '
        'label: no full band across the cycle\'s own columns', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / _twoCycleEntries.length;
      // The first boundary (day 5) opens a cycle running columns 5..8 — a
      // 4-column span the chip must NOT paint across: its background hugs
      // the localized wording instead (text + a small horizontal padding).
      final firstTextNatural = tester
          .getSize(find.byKey(const ValueKey('cycleOrdinal-5')))
          .width;
      final first = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-5')),
      );
      final firstSpan = (9 - 5) * colW;
      expect(
        first.width,
        lessThan(firstSpan / 2),
        reason:
            'day-index 5: the chip\'s background hugs the label '
            'instead of spanning the cycle\'s own columns',
      );
      expect(
        first.width,
        greaterThan(firstTextNatural),
        reason:
            'day-index 5: the shrink-wrapped background still '
            'includes its horizontal padding around the text',
      );

      // The text sits inside the hugging background.
      final firstText = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinal-5')),
      );
      expect(
        firstText.left,
        greaterThanOrEqualTo(first.left),
        reason: 'the label starts inside the hugging background',
      );
      expect(
        firstText.right,
        lessThanOrEqualTo(first.right),
        reason: 'the label ends inside the hugging background',
      );

      // The last cycle's chip shrink-wraps to its label, so it does not
      // run to the plot's right edge.
      final last = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-9')),
      );
      expect(
        last.right,
        lessThan(plot.right),
        reason:
            'day-index 9: the last cycle\'s chip hugs its label '
            'instead of running to the plot\'s right edge',
      );
    });

    testWidgets('the in-plot ordinal badge clamps at the built window\'s right '
        'edge: a boundary whose cycle runs past the window squeezes the '
        'label into the windowed span instead of overflowing the plot', (
      tester,
    ) async {
      // A 150-day range with a sole cycleStart mark at day index 72: the
      // mark's cycle's own columns would run all the way to the range's
      // end — far past the built window once the block scrolled away from
      // the newest days. After dragging to the content's start the parked
      // window's last built index is 72 (observed below), so the clamp
      // leaves the chip a SINGLE day column — narrower than the natural
      // label, i.e. the clamp really bites.
      const boundaryIndex = 72;
      final entries = longRangeEntries(150);
      final marks = [
        CycleMark(
          date: longRangeDay(boundaryIndex),
          type: CycleMarkTypes.cycleStart,
        ),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: marks));
      // Drag back to the earliest days (the drag exceeds the range's whole
      // scroll extent, so it settles at the content's start) and let the
      // window re-park well inside the range.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      // The built window's right edge, observed like every windowed row:
      // the day-label cells render exactly for the window's indexes. The
      // fixture above depends on the boundary sitting AT that edge.
      var windowEnd = -1;
      for (var i = 0; i < entries.length; i++) {
        if (tester.any(dayLabel(i))) windowEnd = i;
      }
      expect(
        windowEnd,
        boundaryIndex,
        reason:
            'the fixture pins the boundary to the parked window\'s '
            'last built index, so the windowed clamp is what limits '
            'the chip',
      );

      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / entries.length;
      // The windowed clamp: the cycle's available span is clamped to the
      // window's right edge (one past the last built index), minus the two
      // column insets. The natural label is WIDER than that span, so the
      // clamp genuinely bites instead of the chip merely hugging the text.
      final maxWidth = (windowEnd + 1 - boundaryIndex) * colW - 4;
      final chip = tester.getRect(
        find.byKey(ValueKey('cycleOrdinalChip-$boundaryIndex')),
      );
      final natural = tester
          .getSize(find.byKey(ValueKey('cycleOrdinal-$boundaryIndex')))
          .width;
      expect(
        natural,
        greaterThan(maxWidth),
        reason:
            'the localized wording is wider than the single-column '
            'clamped span, so the window clamp — not the shrink-wrap — '
            'limits this chip',
      );

      // The chip fills the clamped span exactly: its right edge stops at
      // the window's right boundary instead of running toward the cycle's
      // natural end (the range's end), never overflowing the plot.
      expect(
        chip.width,
        closeTo(maxWidth, 0.5),
        reason:
            'day-index $boundaryIndex: the clamped span is the '
            'chip\'s effective width',
      );
      expect(
        chip.right,
        closeTo(plot.left + (windowEnd + 1) * colW, 2.5),
        reason:
            'day-index $boundaryIndex: the chip clamps at the built '
            'window\'s right edge',
      );
      expect(
        chip.right,
        lessThan(plot.right),
        reason: 'the clamped chip never overflows the plot',
      );
    });

    testWidgets('a perversely short cycle renders its chip and the FittedBox '
        'scales the label down instead of overflowing', (tester) async {
      // Cycle starts on directly adjacent days at the range's tail: two
      // degenerate one-day cycles, so each chip is bounded by a single
      // minimum-width column minus the two column insets.
      final entries = longRangeEntries(60);
      final marks = [
        for (final i in [58, 59])
          CycleMark(date: longRangeDay(i), type: CycleMarkTypes.cycleStart),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: marks));

      final chipFinder = find.byKey(const ValueKey('cycleOrdinalChip-59'));
      expect(
        chipFinder,
        findsOneWidget,
        reason: 'the one-day cycle renders its chip',
      );
      final chip = tester.getRect(chipFinder);

      // The one-cycle column minus the two column insets is the chip's
      // available width — and the natural label is wider, so the chip is
      // clamped to that span (this is what forces the scale-down case).
      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / entries.length;
      final natural = tester
          .getSize(find.descendant(of: chipFinder, matching: find.byType(Text)))
          .width;
      expect(
        natural,
        greaterThan(colW - 4),
        reason:
            'the localized wording is wider than the one-column '
            'span at its natural size, so only a FittedBox scale-down '
            'fits it',
      );
      expect(
        chip.width,
        closeTo(colW - 4, 0.5),
        reason:
            'the one-day cycle pins the chip to its single column '
            '(the natural text is squeezed, not widened beyond it)',
      );

      final textFinder = find.byKey(const ValueKey('cycleOrdinal-59'));
      final fitted = tester.widget<FittedBox>(
        find.descendant(of: chipFinder, matching: find.byType(FittedBox)),
      );
      expect(
        fitted.fit,
        BoxFit.scaleDown,
        reason: 'the chip scales the label down, never up',
      );
      // The VISUAL (fitted) text bounds stay inside the chip: scaled down
      // to the chip's width, not overflowing it.
      final visual = tester.getRect(textFinder);
      expect(
        visual.right,
        lessThanOrEqualTo(chip.right),
        reason: 'the scaled-down label fits inside the chip\'s width',
      );
      expect(
        visual.left,
        greaterThanOrEqualTo(chip.left),
        reason: 'the scaled-down label starts inside the chip',
      );
    });

    testWidgets('the in-plot ordinal badge rides the mucus-peak row: it clears '
        'the sex X row and centers on the peak dot', (tester) async {
      // The boundary day 5 carries a morning sex X in the chip's own column
      // — the row directly above the peak. Day 2 carries the mucus-peak
      // mark, whose dot renders from the mark alone.
      final entries = [
        for (final entry in _twoCycleEntries)
          entry.date == septSevenDay(5)
              ? entry.copyWith(sexTimings: SexTiming.morning.bit)
              : entry,
      ];
      await pumpChart(
        tester,
        chartHarness(
          entries: entries,
          marks: [
            ..._twoCycleMarks,
            CycleMark(date: septSevenDay(2), type: CycleMarkTypes.mucusPeakDay),
          ],
        ),
      );

      final plot = tester.getRect(find.byType(LineChart));
      final chip = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-5')),
      );
      final peakDot = tester.getRect(inPlotPeakDot(2));
      final sexX = tester.getRect(
        find.byKey(const ValueKey('inPlotSex-5-morning')),
      );

      expect(
        chip.center.dy,
        closeTo(peakDot.center.dy, 0.5),
        reason: 'the chip centers on the mucus-peak dot\'s row',
      );
      expect(
        chip.center.dy,
        greaterThan(sexX.bottom),
        reason:
            'the chip\'s center sits on the row below the sex X glyph, '
            'clear of the X box',
      );
      expect(
        chip.top,
        greaterThanOrEqualTo(plot.top),
        reason: 'the chip stays inside the plot at its top edge',
      );
      expect(
        chip.bottom,
        lessThanOrEqualTo(plot.bottom),
        reason: 'the chip stays inside the plot at its bottom edge',
      );
    });

    testWidgets('a degenerate persisted range keeps the ordinal badge inside '
        'the plot', (tester) async {
      // A 0.1 K span — only reachable through an imported or hand-built
      // range; the settings card's minimum gap is 1.0 K. The peak row then
      // lies below the plot's bottom edge.
      await pumpChart(
        tester,
        chartHarness(
          entries: _twoCycleEntries,
          marks: _twoCycleMarks,
          temperatureRange: const TemperatureRange(min: 37.8, max: 37.9),
        ),
      );

      final plot = tester.getRect(find.byType(LineChart));
      final chip = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-5')),
      );
      expect(
        chip.top,
        greaterThanOrEqualTo(plot.top),
        reason: 'the degenerate range cannot push the chip above the plot',
      );
      expect(
        chip.bottom,
        lessThanOrEqualTo(plot.bottom),
        reason: 'the degenerate range cannot clip the chip below the plot',
      );
    });
  });

  group('horizontal NER temperature grid', () {
    FlGridData grid(WidgetTester tester) => chartData(tester).gridData;

    Color emphasizedLine(WidgetTester tester) =>
        chartScheme(tester).onSurface.withValues(alpha: 0.45);

    Color plainLine(WidgetTester tester) =>
        chartScheme(tester).onSurface.withValues(alpha: 0.12);

    /// The horizontal-line styling for one temperature value.
    FlLine horizontalLine(WidgetTester tester, double value) =>
        grid(tester).getDrawingHorizontalLine(value);

    testWidgets(
      'the temperature body carries horizontal lines every 0.1 °C over '
      'the fixed display range',
      (tester) async {
        // The entries keep 36.5 — well inside the default 36–38 °C range; the
        // grid interval is fixed at 0.1 regardless of the data.
        await pumpChart(
          tester,
          chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
        );

        expect(
          grid(tester).drawHorizontalLine,
          isTrue,
          reason: 'the paper grid rules the temperature body horizontally',
        );
        expect(
          grid(tester).horizontalInterval,
          0.1,
          reason: 'one grid line per 0.1 K step (paper convention)',
        );
      },
    );

    testWidgets('full degrees draw SOLID, thick emphasis lines (×10 integer '
        'classification, no float equality)', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.0, 37.0, 38.0]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(1.2, 0.01),
          reason: '$value is a full degree: the grid emphasizes it',
        );
        expect(
          line.dashArray,
          isNull,
          reason: '$value: a full-degree line is solid',
        );
        expect(
          line.color,
          emphasizedLine(tester),
          reason: '$value: the emphasis tint on the on-surface color',
        );
      }
    });

    testWidgets('the 0.5 midpoints draw DASHED lines at the emphasis weight', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.5, 37.5]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(1.2, 0.01),
          reason: '$value: the half midpoint keeps the emphasis weight',
        );
        expect(
          line.dashArray,
          _emphasizedStepDashPattern,
          reason: '$value is dashed',
        );
        expect(
          line.color,
          emphasizedLine(tester),
          reason: '$value: the emphasis tint on the on-surface color',
        );
      }
    });

    testWidgets('the remaining 0.1 steps draw the plain day-hairline style', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.1, 36.2, 36.3, 36.4, 36.6, 36.9, 37.9]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(0.5, 0.01),
          reason: '$value: an in-between step stays a hairline',
        );
        expect(line.dashArray, isNull, reason: '$value is solid');
        expect(
          line.color,
          plainLine(tester),
          reason: '$value: the same subtle tint as the vertical day lines',
        );
      }
    });

    testWidgets('the vertical day lines are unchanged by the horizontal grid: '
        'interval 1, hairline style', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      expect(grid(tester).drawVerticalLine, isTrue);
      expect(grid(tester).verticalInterval, 1);
      final vertical = grid(tester).getDrawingVerticalLine(0.5);
      expect(vertical.strokeWidth, lessThanOrEqualTo(1));
      expect(
        vertical.color,
        plainLine(tester),
        reason: 'the day hairline style keeps its subtle tint',
      );
    });
  });
}
