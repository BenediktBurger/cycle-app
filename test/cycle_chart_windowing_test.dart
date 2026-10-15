import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cycle_app/ui/cycle.dart';
import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle tab's viewport-limited day window: for long
// recorded ranges only the days that fit usefully on screen are rendered
// (the window PARKS with an extra screen-width of margin past the visible
// edges and is only rebuilt when the visible edge runs into that margin),
// the whole chart block scrolls horizontally (curve and signal
// rows together), the FIRST data frame auto-scrolls so the MOST RECENT days
// fill the viewport, a later entries re-emit never re-jumps (the user's
// scrolled position survives), and a jump-to-date affordance moves the
// window onto a picked calendar day. Tapping a day inside the scrolled
// window keeps opening the day's mark-entry sheet.
//

// A many-day range: 2026-01-01 .. 2026-05-30 (150 days, indexes 0..149) —
// long enough that the scroll window and its margin sit strictly inside
// the recorded range, so windowing and margin semantics stay distinguishable.
List<DailyEntry> _manyEntries() => longRangeEntries(150);

List<DailyEntry> _shortEntries() => [
  for (var i = 0; i < 5; i++) DailyEntry(date: longRangeDay(i), bbtC: 36.5),
];

/// A 149-day range whose TAIL evaluates: days 142..147 sit 0.3 °C under
/// day 148's marked rise, so the six days before the rise carry the 1–6
/// numbering while the visible front of the range stays number-free.
List<DailyEntry> _numberedTailEntries() => [
  ...longRangeEntries(142),
  for (var i = 0; i < 6; i++)
    DailyEntry(date: longRangeDay(142 + i), bbtC: 36.2),
  DailyEntry(date: longRangeDay(148), bbtC: 36.5),
];

/// The first-higher mark that anchors _numberedTailEntries's low window.
final _numberedTailMarks = <CycleMark>[
  CycleMark(
    date: longRangeDay(148),
    type: CycleMarkTypes.firstHigherMeasurement,
  ),
];

Finder _bleedingCell(int index) => find.byKey(ValueKey('bleedingCell-$index'));

// The chart's day-column geometry at the test viewport (800 wide, 12 body
// padding on each side): a 60-day range overflows, so columns render at
// [minDayColumnWidth] and the content exceeds the viewport.
const _columnWidth = minDayColumnWidth;

// A regression test for the chart's window-rebuild pace: the built day
// window parks with an extra screen-width of margin past the visible
// edges and is only rebuilt when the visible edge would run into that
// margin. Scrolling a long distance must therefore re-window only a
// handful of times — not once per day column. The scroll listener fires
// every scroll tick, but only a window-bound change rebuilds the chart
// block, so the count of rendered-window transitions IS the rebuild
// count the scroll path causes.
//

// A many-day recorded range (2026-01-01 onwards, 600 days; the shared
// long-range fixture with a longer count).
List<DailyEntry> _windowRebuildEntries() => longRangeEntries(600);

/// The day indexes whose signal cells are currently built.
Set<int> _builtCells(WidgetTester tester) {
  const prefix = 'bleedingCell-';
  final indexes = <int>{};
  for (final widget in tester.widgetList(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith(prefix),
    ),
  )) {
    final suffix = (widget.key! as ValueKey<String>).value.substring(
      prefix.length,
    );
    indexes.add(int.parse(suffix));
  }
  return indexes;
}

void main() {
  group('long recorded range', () {
    testWidgets('the first data frame auto-scrolls to the newest days', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _manyEntries()));

      // The newest days sit at the content's right edge, so the initial
      // auto-scroll jumped the viewport to the maximum scroll extent: the
      // last day column fills the window, the earliest days are off-screen.
      expect(
        _bleedingCell(149),
        findsOneWidget,
        reason: 'the newest days fill the viewport after the first frame',
      );
      expect(
        _bleedingCell(0),
        findsNothing,
        reason: 'the earliest days are outside the initial window',
      );

      // The jump is instant (no animation): the offset sits at the maximum
      // extent already after the settle.
      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: '150 day columns need more width than the viewport provides',
      );
      expect(
        state.position.pixels,
        state.position.maxScrollExtent,
        reason: 'the initial auto-scroll jumps straight to the newest days',
      );
    });

    testWidgets('the chart block scrolls horizontally', (tester) async {
      await pumpChart(tester, chartHarness(entries: longRangeEntries()));

      final scrollView = chartScrollView();
      expect(
        scrollView,
        findsOneWidget,
        reason: 'the whole chart block is horizontally scrollable',
      );
      final state = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: '60 day columns need more width than the viewport provides',
      );
    });

    testWidgets('dragging scrolls the window; y bounds stay global', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _manyEntries()));

      // The initial window sits at the newest days; drag BACK toward the
      // earliest days and assert the window follows the scroll. The drag
      // exceeds the maximum scroll extent, so it settles at the content's
      // start (the earliest days).
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      expect(
        _bleedingCell(149),
        findsNothing,
        reason: 'the newest days scrolled out of the window',
      );
      expect(
        _bleedingCell(0),
        findsOneWidget,
        reason: 'the earliest days appear once scrolled to',
      );

      // The temperature scale must NOT rescale per window: the y bounds are
      // the fixed settings-derived range (default 36..38 °C, well above the
      // coldest recorded day here), so the curve keeps its absolute heights
      // while scrolling.
      final chartMinY = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .minY;
      final recordedValues = _manyEntries().map((e) => e.bbtC!).toList();
      expect(
        chartMinY,
        lessThanOrEqualTo(recordedValues.reduce((a, b) => a < b ? a : b)),
        reason: 'the y scale still covers the coldest recorded day',
      );
    });

    testWidgets(
      'a later entries re-emit never re-runs the initial auto-scroll',
      (tester) async {
        final controller = StreamController<List<DailyEntry>>();
        addTearDown(controller.close);
        await tester.pumpWidget(
          chartHarness(
            entries: _manyEntries(),
            entriesStream: controller.stream,
          ),
        );
        controller.add(_manyEntries());
        await tester.pumpAndSettle();

        final state = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          state.position.pixels,
          state.position.maxScrollExtent,
          reason: 'the first data frame jumped to the newest days',
        );

        // Drag away from the end toward earlier days (deep enough that the
        // parked window's margin sits strictly inside the recorded range). A
        // timed drag has no fling momentum, so the settled offset is
        // deterministic.
        await tester.timedDrag(
          chartScrollView(),
          const Offset(900, 0),
          const Duration(milliseconds: 200),
        );
        await tester.pumpAndSettle();
        final offsetAfterDrag = state.position.pixels;
        expect(offsetAfterDrag, lessThan(state.position.maxScrollExtent));

        // Emit a NEW list instance (one extra day at the end): the user's
        // scrolled position must survive — no re-jump back to the end.
        controller.add([
          ..._manyEntries(),
          DailyEntry(date: longRangeDay(150), bbtC: 36.5),
        ]);
        await tester.pumpAndSettle();

        expect(
          state.position.pixels,
          offsetAfterDrag,
          reason: 'a later re-emit must not re-run the initial auto-scroll',
        );
        expect(
          _bleedingCell(149),
          findsNothing,
          reason: 'the view stayed where the user dragged it, not at the end',
        );
        // The dragged-to window still renders: at the dragged offset the
        // visible window starts around floor(offset / columnWidth) — the
        // scroll content leads directly with day column 0 (the y scale lives
        // in the frozen rail outside the scroll), so the offset maps onto
        // the column grid without any leading-strip subtraction.
        final firstVisible = (offsetAfterDrag / _columnWidth).floor();
        expect(
          _bleedingCell(firstVisible + 2),
          findsOneWidget,
          reason: 'the dragged-to window cells are still rendered',
        );
      },
    );

    testWidgets('an empty first frame does not jump; the first non-empty '
        'frame mounts the chart and jumps', (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(
        chartHarness(entries: _manyEntries(), entriesStream: controller.stream),
      );
      controller.add(const <DailyEntry>[]);
      await tester.pumpAndSettle();

      // No data: the chart block is not built at all, so there is nothing
      // to jump (the screen shows its no-data state instead).
      expect(chartScrollView(), findsNothing);

      controller.add(_manyEntries());
      await tester.pumpAndSettle();

      // The first NON-EMPTY data frame mounts the chart and auto-scrolls
      // to the newest days.
      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        state.position.pixels,
        state.position.maxScrollExtent,
        reason: 'the first non-empty data frame jumps to the newest days',
      );
      expect(_bleedingCell(149), findsOneWidget);
    });

    testWidgets(
      'a freshly parked window carries one extra screen-width of margin '
      'past the visible edges, not further',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _manyEntries()));

        final state = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        // The scroll viewport: block width (800 test viewport, 12 body
        // padding on each side) minus the frozen rail left of the scroll.
        const scrollViewport = 800.0 - 2 * 12 - frozenRailWidth; // 752
        final marginDays = (scrollViewport / _columnWidth).ceil(); // 36

        // Fresh park 1: the initial auto-scroll landed at the newest days;
        // the left margin is unclamped and ends exactly one extra
        // screen-width before the leftmost visible edge.
        final maxExtent = state.position.maxScrollExtent;
        final freshVisible = (maxExtent / _columnWidth).floor();
        expect(
          _bleedingCell(freshVisible - 1 - marginDays),
          findsOneWidget,
          reason:
              'a full extra screen-width of margin renders before the '
              'visible edge of a freshly parked window',
        );
        expect(
          _bleedingCell(freshVisible - 2 - marginDays),
          findsNothing,
          reason:
              'the fresh park is bounded: the window does not extend '
              'past one extra screen-width',
        );

        // Fresh park 2: a long jump (the jump-to-date landing does the same)
        // re-parks the window around the landed position: both margins
        // extend exactly one extra screen-width past the visible edges.
        // Day cell i spans [i * 21, (i + 1) * 21).
        state.position.jumpTo(1000.0);
        await tester.pumpAndSettle();
        expect(
          state.position.pixels,
          1000.0,
          reason: 'precondition: the jump landed at the exact offset',
        );
        final firstVisible = (1000.0 / _columnWidth).floor();
        final lastVisible =
            ((1000.0 + scrollViewport) / _columnWidth).ceil() - 1;
        expect(
          _bleedingCell(firstVisible - 1 - marginDays),
          findsOneWidget,
          reason:
              'the re-parked window carries the screen-width margin '
              'before the visible edge',
        );
        expect(
          _bleedingCell(firstVisible - 2 - marginDays),
          findsNothing,
          reason: 'the re-parked window stays bounded at the margin',
        );
        expect(
          _bleedingCell(lastVisible + 1 + marginDays),
          findsOneWidget,
          reason:
              'the re-parked window carries the screen-width margin '
              'past the visible right edge',
        );
        expect(
          _bleedingCell(lastVisible + 2 + marginDays),
          findsNothing,
          reason: 'the re-parked window stays bounded at the margin',
        );
      },
    );

    testWidgets('a small scroll stays inside the parked window — the window is '
        'not rebuilt for travel the margin absorbs', (tester) async {
      await pumpChart(tester, chartHarness(entries: _manyEntries()));

      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      const scrollViewport = 800.0 - 2 * 12 - frozenRailWidth; // 752
      final marginDays = (scrollViewport / _columnWidth).ceil();
      final maxExtent = state.position.maxScrollExtent;
      final freshVisible = (maxExtent / _columnWidth).floor();
      final parkedStart = freshVisible - 1 - marginDays;
      expect(
        parkedStart,
        greaterThan(0),
        reason: 'precondition: the parked margin is unclamped here',
      );

      // Travel 240 px (≈ 11 columns) — well within one extra screen-width
      // of margin: the visible edge moves, but the parked window around it
      // still covers the viewport with seam margin to spare.
      state.position.jumpTo(maxExtent - 240.0);
      await tester.pumpAndSettle();

      // The parked window keeps sitting at the SAME boundary — it was not
      // re-parked around the new position (that is what keeps the rebuild
      // rare during a fling).
      expect(_bleedingCell(parkedStart), findsOneWidget);
      expect(
        _bleedingCell(parkedStart - 1),
        findsNothing,
        reason:
            'the parked window did not follow the small scroll — '
            'the margin absorbs the travel',
      );

      // The seam guarantee still holds at the new position: the leftmost
      // visible day and the day before it render.
      final visible = (state.position.pixels / _columnWidth).floor();
      expect(_bleedingCell(visible), findsOneWidget);
    });

    testWidgets(
      'the jump-to-date affordance sits in the AppBar actions, next to '
      'the info action',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: longRangeEntries()));

        final jump = find.byKey(const ValueKey('calendarJumpButton'));
        final info = find.byKey(const ValueKey('cycleHelpAction'));
        expect(
          find.ancestor(of: jump, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the jump affordance moved into the AppBar actions',
        );
        expect(
          find.ancestor(of: info, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the info action stays in the AppBar beside it',
        );
        expect(
          tester.getCenter(jump).dx,
          lessThan(tester.getCenter(info).dx),
          reason: 'the jump affordance renders before the info action',
        );
        expect(
          find.ancestor(of: jump, matching: find.byType(ListView)),
          findsNothing,
          reason:
              'the jump affordance lives in the AppBar, not in the screen '
              'body (no standalone row above the chart block)',
        );
      },
    );

    testWidgets('jump-to-date: picking a date moves the window onto it', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _manyEntries()));

      // Drag to the content's start first: the picker opens on the
      // leftmost day of the window (the day the user is looking at), so
      // with the window parked at the earliest days it opens on January —
      // independent of how wide the window margin sits behind the visible
      // edge.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
      await tester.pumpAndSettle();

      expect(
        find.byType(DatePickerDialog),
        findsOneWidget,
        reason: 'the affordance opens the material date picker',
      );
      // Day index of 2026-01-20 = 19. The material picker confirms a day
      // selection through its OK button.
      await tester.tap(find.text('20').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        _bleedingCell(19),
        findsOneWidget,
        reason: 'the picked day is now inside the rendered window',
      );
      expect(
        _bleedingCell(149),
        findsNothing,
        reason: 'the window jumped away from where it was',
      );
    });

    testWidgets(
      'jump-to-date: picking a date after the chart unmounted disposes '
      'quietly, with no reach into the disposed state',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _manyEntries()));

        // The picker opens on the leftmost visible day, so the January
        // date grid is on screen (day cells of other months stay off it —
        // see the picking test above).
        await tester.drag(chartScrollView(), const Offset(3000, 0));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
        await tester.pumpAndSettle();
        expect(
          find.byType(DatePickerDialog),
          findsOneWidget,
          reason: 'the affordance opens the material date picker',
        );

        // Unmount the screen body while the picker stays open (a real tab
        // change does the same): the chart state and its scroll hooks are
        // disposed under the still-open dialog.
        await tester.pumpWidget(
          chartHarness(entries: _manyEntries(), emptyHome: true),
        );
        await tester.pump();
        expect(
          find.byType(DatePickerDialog),
          findsOneWidget,
          reason:
              'the picker rides the root navigator and survives the '
              'body swap',
        );

        // Confirming the pick resolves the picker future inside the
        // disposed chart's continuation — which must return without
        // touching the disposed state (no unhandled error, no crash).
        await tester.tap(find.text('20').last, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping the curve in the scrolled window opens the day sheet',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: longRangeEntries()));

        // Scroll to the end (content is much wider than the viewport, so a
        // large leftward drag lands at maxScrollExtent).
        await tester.drag(chartScrollView(), const Offset(-1000, 0));
        await tester.pumpAndSettle();

        // Content is 60 day columns, no leading strip (the temperature scale
        // lives in the frozen rail left of the scroll view); at max scroll
        // the last day (index 59) sits at the content's right edge. Tap the
        // day column of index 58 (= 2026-02-28) inside the visible area. The
        // chart's x domain is half a column shifted, so day 58's column
        // center maps to tap x = colW * (58 + 0.5).
        const railWidth = frozenRailWidth; // the rail left of the scroll view
        const testViewportWidth = 800.0;
        const bodyPadding = 12.0;
        const scrollViewport =
            testViewportWidth - 2 * bodyPadding - railWidth; // 752
        const contentWidth = 60 * minDayColumnWidth; // 1260
        const maxOffset = contentWidth - scrollViewport; // 508
        final tapContentX = minDayColumnWidth * (58 + 0.5);
        final tapScreenX =
            bodyPadding + railWidth + (tapContentX - maxOffset); // 756.5
        final chartTop = tester.getRect(find.byType(LineChart)).top;

        await tester.tapAt(Offset(tapScreenX, chartTop + 100));
        await tester.pumpAndSettle();

        expect(
          cycleDayPanel(),
          findsOneWidget,
          reason: 'a tap in the scrolled window still opens the day sheet',
        );
        final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
        expect(
          sheet.day,
          DateTime.utc(2026, 2, 28),
          reason: 'the tapped chart column maps to day index 58',
        );
      },
    );

    testWidgets('a long press on the curve opens the day sheet too', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: longRangeEntries()));

      await tester.drag(chartScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Same column mapping as the tap above (day 58's column center at
      // colW * (58 + 0.5), content = 60 columns without a strip); the
      // long-press behaves identically to the tap.
      const railWidth = frozenRailWidth; // the rail left of the scroll view
      const bodyPadding = 12.0;
      const contentWidth = 60 * minDayColumnWidth;
      const maxOffset = contentWidth - (800.0 - 2 * bodyPadding - railWidth);
      final tapContentX = minDayColumnWidth * (58 + 0.5);
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.longPressAt(
        Offset(
          bodyPadding + railWidth + (tapContentX - maxOffset),
          chartTop + 100,
        ),
      );
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(sheet.day, DateTime.utc(2026, 2, 28));
    });
  });

  group('the in-plot day numbers are windowed like the in-plot glyphs', () {
    testWidgets('only the scroll window\'s number glyphs render', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _numberedTailEntries(),
          marks: _numberedTailMarks,
        ),
      );

      // The initial auto-scroll parks the window at the newest days: the
      // tail's low days (indexes 142..147) sit inside the parked window
      // and the earliest days are outside it.
      expect(
        dayNumberGlyph(142, 6),
        findsOneWidget,
        reason: 'the newest days fill the window after the first frame',
      );
      expect(
        numberUnder(tester, 0),
        isNull,
        reason: 'the earliest days carry no number',
      );

      // Drag back to the earliest days: the number glyphs follow the
      // built window, like every other in-plot glyph.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();
      expect(
        numberUnder(tester, 142),
        isNull,
        reason: 'the numbered tail leaves the built window after the drag',
      );
    });

    testWidgets(
      'the windowed number glyphs keep their global column positions',
      (tester) async {
        await pumpChart(
          tester,
          chartHarness(
            entries: _numberedTailEntries(),
            marks: _numberedTailMarks,
          ),
        );

        // The window spacer keeps glyph i at its global column position:
        // wherever the window starts, a day's number centers exactly at
        // that day's signal-row cell center.
        void expectSharedColumn(int index, int number) {
          final numberX = tester
              .getRect(dayNumberGlyph(index, number))
              .center
              .dx;
          final bleedingX = tester.getRect(_bleedingCell(index)).center.dx;
          expect(
            numberX,
            closeTo(bleedingX, 0.5),
            reason:
                'number glyph $index keeps its global column position '
                '(window spacer, like the in-plot glyphs)',
          );
        }

        // The initial window sits at the newest days ...
        expectSharedColumn(142, 6);
        // ... and the dragged-to window at the earliest days carries no
        // number glyphs to align.
        await tester.drag(chartScrollView(), const Offset(3000, 0));
        await tester.pumpAndSettle();
        expect(numberUnder(tester, 142), isNull);
      },
    );
  });

  group('short recorded range (5 days)', () {
    testWidgets('every day cell is rendered and nothing is scrollable', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _shortEntries()));

      for (var i = 0; i < 5; i++) {
        expect(
          _bleedingCell(i),
          findsOneWidget,
          reason: 'a short range fits usefully on one screen',
        );
      }

      final scrollView = chartScrollView();
      expect(
        scrollView,
        findsOneWidget,
        reason: 'the chart is still laid out as one scrollable block',
      );
      final state = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(
        state.position.maxScrollExtent,
        0,
        reason: '5 comfortable day columns fit the viewport exactly',
      );
    });
  });

  testWidgets(
    'scrolling a long distance re-windows the chart only a handful of '
    'times, not once per day column',
    (tester) async {
      final entries = _windowRebuildEntries();
      // No theme wiring here: the test counts window rebuilds, not looks.
      await pumpChart(tester, chartHarness(entries: entries, themed: false));

      // Travel 2000 px in 10 px steps (one pump per step): with a parked
      // window carrying an extra screen-width of margin (31 columns at this
      // viewport), the window needs re-parking only every extra screen-width
      // of travel — once per active edge — not once per day column.
      var reWindows = 0;
      var built = _builtCells(tester);
      const steps = 200;
      final gesture = await tester.startGesture(
        tester.getCenter(chartScrollView().first),
      );
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(const Offset(10, 0)); // toward earlier days
        await tester.pump(const Duration(milliseconds: 16));
        final now = _builtCells(tester);
        if (!setEquals(now, built)) {
          reWindows++;
          built = now;
        }
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // Measured improvement trail: without windowing/margin this 2000 px
      // scroll caused 200 window rebuilds; with the parked screen-width
      // margin ≤2 were observed — the bound of 6 is headroom for the parked
      // window's two edges and the range's clamped edges.
      expect(
        reWindows,
        lessThanOrEqualTo(6),
        reason:
            'a 2000 px scroll must re-window only a handful of times '
            '(the parked margin absorbs the travel); observed $reWindows',
      );
    },
  );
}
