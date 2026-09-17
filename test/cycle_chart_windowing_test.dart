// Widget tests of the cycle tab's viewport-limited day window: for long
// recorded ranges only the days that fit usefully on screen are rendered,
// the whole chart block scrolls horizontally (curve + signal
// rows together), the FIRST data frame auto-scrolls so the MOST RECENT days
// fill the viewport, a later entries re-emit never re-jumps (the user's
// scrolled position survives), and a jump-to-date affordance moves the
// window onto a picked calendar day. Tapping a day inside the scrolled
// window keeps opening the day's mark-entry sheet.
//
// Same harness pattern as test/cycle_chart_weekend_test.dart.
import 'dart:async';

import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A long recorded range: 2026-01-01 .. 2026-03-01 (60 days, indexes 0..59).
DateTime _day(int index) => DateTime.utc(2026, 1, 1).add(Duration(days: index));

List<DailyEntry> _longEntries() => [
      for (var i = 0; i < 60; i++)
        DailyEntry(date: _day(i), bbtC: 36.4 + (i % 10) * 0.05),
    ];

List<DailyEntry> _shortEntries() => [
      for (var i = 0; i < 5; i++) DailyEntry(date: _day(i), bbtC: 36.5),
    ];

Finder _bleedingCell(int index) => find.byKey(ValueKey('bleedingCell-$index'));

// The chart's day-column geometry at the test viewport (800 wide, 12 body
// padding on each side): a 60-day range overflows, so columns render at the
// minimum usable width and the content exceeds the viewport.
const _columnWidth = 24.0;

Widget _chartHarness({
  required List<DailyEntry> entries,
  Stream<List<DailyEntry>>? entriesStream,
}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider
            .overrideWith((ref) => entriesStream ?? Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(const <CycleMark>[])),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: ZyklusScreen()),
      ),
    );

/// The finder for the horizontal scroll view that carries the chart block.
/// The evaluation table below the chart block has its own horizontal
/// scroller (key `cycleSummaryScroll`) — it is not the chart block, so it
/// is excluded by that key here.
Finder _hScrollView() => find.byWidgetPredicate((w) =>
    w is SingleChildScrollView &&
    w.scrollDirection == Axis.horizontal &&
    w.key != const ValueKey('cycleSummaryScroll'));

void main() {
  group('long recorded range (60 days)', () {
    testWidgets('the first data frame auto-scrolls to the newest days',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      // The newest days sit at the content's right edge, so the initial
      // auto-scroll jumped the viewport to the maximum scroll extent: the
      // last day column fills the window, the earliest days are off-screen.
      expect(_bleedingCell(59), findsOneWidget,
          reason: 'the newest days fill the viewport after the first frame');
      expect(_bleedingCell(0), findsNothing,
          reason: 'the earliest days are outside the initial window');

      // The jump is instant (no animation): the offset sits at the maximum
      // extent already after the settle.
      final state = tester.state<ScrollableState>(find.descendant(
          of: _hScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, greaterThan(0),
          reason: '60 day columns need more width than the viewport provides');
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the initial auto-scroll jumps straight to the newest days');
    });

    testWidgets('the chart block scrolls horizontally', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      final scrollView = _hScrollView();
      expect(scrollView, findsOneWidget,
          reason: 'the whole chart block is horizontally scrollable');
      final state = tester.state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, greaterThan(0),
          reason: '60 day columns need more width than the viewport provides');
    });

    testWidgets('dragging scrolls the window; y bounds stay global',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      // The initial window sits at the newest days; drag BACK toward the
      // earliest days and assert the window follows the scroll.
      await tester.drag(_hScrollView(), const Offset(1000, 0));
      await tester.pumpAndSettle();

      expect(_bleedingCell(59), findsNothing,
          reason: 'the newest days scrolled out of the window');
      expect(_bleedingCell(0), findsOneWidget,
          reason: 'the earliest days appear once scrolled to');

      // The temperature scale must NOT rescale per window: the y bounds are
      // computed over the whole recorded range, so the curve keeps its
      // absolute heights while scrolling.
      final chartMinY =
          tester.widget<LineChart>(find.byType(LineChart)).data.minY;
      final recordedValues = _longEntries().map((e) => e.bbtC!).toList();
      expect(chartMinY,
          lessThanOrEqualTo(recordedValues.reduce((a, b) => a < b ? a : b)),
          reason: 'the y scale still covers the coldest recorded day');
    });

    testWidgets('a later entries re-emit never re-runs the initial auto-scroll',
        (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(_chartHarness(
          entries: _longEntries(), entriesStream: controller.stream));
      controller.add(_longEntries());
      await tester.pumpAndSettle();

      final state = tester.state<ScrollableState>(find.descendant(
          of: _hScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the first data frame jumped to the newest days');

      // Drag away from the end toward earlier days. A timed drag has no
      // fling momentum, so the settled offset is deterministic.
      await tester.timedDrag(_hScrollView(), const Offset(300, 0),
          const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final offsetAfterDrag = state.position.pixels;
      expect(offsetAfterDrag, lessThan(state.position.maxScrollExtent));

      // Emit a NEW list instance (one extra day at the end): the user's
      // scrolled position must survive — no re-jump back to the end.
      controller
          .add([..._longEntries(), DailyEntry(date: _day(60), bbtC: 36.5)]);
      await tester.pumpAndSettle();

      expect(state.position.pixels, offsetAfterDrag,
          reason: 'a later re-emit must not re-run the initial auto-scroll');
      expect(_bleedingCell(59), findsNothing,
          reason: 'the view stayed where the user dragged it, not at the end');
      // The dragged-to window still renders: at the dragged offset the
      // visible window starts around floor(offset / columnWidth) — the
      // scroll content leads directly with day column 0 (the y scale lives
      // in the frozen rail outside the scroll), so the offset maps onto
      // the column grid without any leading-strip subtraction.
      final firstVisible = (offsetAfterDrag / _columnWidth).floor();
      expect(_bleedingCell(firstVisible + 2), findsOneWidget,
          reason: 'the dragged-to window cells are still rendered');
    });

    testWidgets(
        'an empty first frame does not jump; the first non-empty '
        'frame mounts the chart and jumps', (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(_chartHarness(
          entries: _longEntries(), entriesStream: controller.stream));
      controller.add(const <DailyEntry>[]);
      await tester.pumpAndSettle();

      // No data: the chart block is not built at all, so there is nothing
      // to jump (the screen shows its no-data state instead).
      expect(_hScrollView(), findsNothing);

      controller.add(_longEntries());
      await tester.pumpAndSettle();

      // The first NON-EMPTY data frame mounts the chart and auto-scrolls
      // to the newest days.
      final state = tester.state<ScrollableState>(find.descendant(
          of: _hScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the first non-empty data frame jumps to the newest days');
      expect(_bleedingCell(59), findsOneWidget);
    });

    testWidgets(
        'after a drag away from the end the rendered window matches the '
        'leftmost visible day (stripless content)', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      // Drag from the newest-days end (max scroll extent) back toward the
      // earliest days. A drag gesture carries no fling momentum, so the
      // settled offset stays put; its exact delta depends on the framework's
      // touch slop, so the test READS the settled offset and pins the
      // window math against it (the bare offset maps straight onto the
      // column grid — the content has no leading strip).
      await tester.drag(_hScrollView(), const Offset(260, 0));
      await tester.pumpAndSettle();

      final state = tester.state<ScrollableState>(find.descendant(
          of: _hScrollView(), matching: find.byType(Scrollable)));
      final offset = state.position.pixels;
      expect(offset, lessThan(state.position.maxScrollExtent),
          reason: 'the drag moved the window off the end');
      // Day cell i starts at i * 24 in the content, so the leftmost
      // partially visible day is floor(offset / columnWidth).
      final leftmostVisible = (offset / _columnWidth).floor();

      expect(_bleedingCell(leftmostVisible), findsOneWidget,
          reason: 'the leftmost visible day is rendered');
      // The window carries one day of margin before the visible edge, but
      // no further: the day BEFORE the margin must not render.
      expect(_bleedingCell(leftmostVisible - 1), findsOneWidget,
          reason: 'the one-day margin before the visible edge renders');
      expect(_bleedingCell(leftmostVisible - 2), findsNothing,
          reason: 'the window does not reach past the margin — the window '
              'math matches the stripless content, it does not lag behind '
              'the scroll');
    });

    testWidgets('jump-to-date: picking a date moves the window onto it',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget,
          reason: 'the affordance opens the material date picker');
      // With the initial auto-scroll the window sits at the newest days
      // (offset = max extent -> leftmost visible day index 26 = 2026-01-27,
      // the picker's initial date), so it still opens on January. Day index
      // of 2026-01-20 = 19. The material picker confirms a day selection
      // through its OK button.
      await tester.tap(find.text('20').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_bleedingCell(19), findsOneWidget,
          reason: 'the picked day is now inside the rendered window');
      expect(_bleedingCell(0), findsNothing,
          reason: 'the window jumped away from the first day');
    });

    testWidgets('tapping the curve in the scrolled window opens the day sheet',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      // Scroll to the end (content is much wider than the viewport, so a
      // large leftward drag lands at maxScrollExtent).
      await tester.drag(_hScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Content is 60 day columns, no leading strip (the temperature scale
      // lives in the frozen rail left of the scroll view); at max scroll
      // the last day (index 59) sits at the content's right edge. Tap the
      // day column of index 58 (= 2026-02-28) inside the visible area. The
      // chart's x domain is half a column shifted, so day 58's column
      // center maps to tap x = colW * (58 + 0.5).
      const railWidth = 44.0; // the frozen rail left of the scroll view
      const testViewportWidth = 800.0;
      const bodyPadding = 12.0;
      const scrollViewport =
          testViewportWidth - 2 * bodyPadding - railWidth; // 732
      const contentWidth = 60 * 24.0; // 1440
      const maxOffset = contentWidth - scrollViewport; // 708
      final tapContentX = 24.0 * (58 + 0.5);
      final tapScreenX =
          bodyPadding + railWidth + (tapContentX - maxOffset); // 752
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.tapAt(Offset(tapScreenX, chartTop + 100));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'a tap in the scrolled window still opens the day sheet');
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, DateTime.utc(2026, 2, 28),
          reason: 'the tapped chart column maps to day index 58');
    });

    testWidgets('a long press on the curve opens the day sheet too',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      await tester.drag(_hScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Same column mapping as the tap above (day 58's column center at
      // colW * (58 + 0.5), content = 60 columns without a strip); the
      // long-press behaves identically to the tap.
      const railWidth = 44.0; // the frozen rail left of the scroll view
      const bodyPadding = 12.0;
      const contentWidth = 60 * 24.0;
      const maxOffset = contentWidth - (800.0 - 2 * bodyPadding - railWidth);
      final tapContentX = 24.0 * (58 + 0.5);
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.longPressAt(Offset(
          bodyPadding + railWidth + (tapContentX - maxOffset), chartTop + 100));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, DateTime.utc(2026, 2, 28));
    });
  });

  group('short recorded range (5 days)', () {
    testWidgets('every day cell is rendered and nothing is scrollable',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _shortEntries()));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(_bleedingCell(i), findsOneWidget,
            reason: 'a short range fits usefully on one screen');
      }

      final scrollView = _hScrollView();
      expect(scrollView, findsOneWidget,
          reason: 'the chart is still laid out as one scrollable block');
      final state = tester.state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, 0,
          reason: '5 comfortable day columns fit the viewport exactly');
    });
  });
}
