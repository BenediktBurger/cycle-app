// Widget tests of the cycle tab's viewport-limited day window: for long
// recorded ranges only the days that fit usefully on screen are rendered,
// the whole chart block scrolls horizontally (curve + marks row + symbol
// row together), and a jump-to-date affordance moves the window onto a
// picked calendar day. Tapping a day inside the scrolled window keeps
// opening the day's mark-entry sheet.
//
// Same harness pattern as test/cycle_chart_weekend_test.dart.
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
      for (var i = 0; i < 60; i++) DailyEntry(date: _day(i), bbtC: 36.4 + (i % 10) * 0.05),
    ];

List<DailyEntry> _shortEntries() => [
      for (var i = 0; i < 5; i++) DailyEntry(date: _day(i), bbtC: 36.5),
    ];

Finder _symbolCell(int index) => find.byKey(ValueKey('symbolCell-$index'));

Widget _chartHarness({required List<DailyEntry> entries}) => ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
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
Finder _hScrollView() => find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);

void main() {
  group('long recorded range (60 days)', () {
    testWidgets('only the on-screen window of day cells is rendered',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      // The window starts at the first day ...
      expect(_symbolCell(0), findsOneWidget);
      // ... but the range is far too long for one screen: the tail's cells
      // are not built until they scroll into view.
      expect(_symbolCell(40), findsNothing,
          reason: 'day 40 does not fit usefully on one screen -> not rendered');
      expect(_symbolCell(59), findsNothing);
    });

    testWidgets('the chart block scrolls horizontally', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      final scrollView = find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
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

      await tester.drag(_hScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      expect(_symbolCell(0), findsNothing,
          reason: 'the earliest days scrolled out of the window');
      expect(_symbolCell(40), findsOneWidget,
          reason: 'later days appear once scrolled to');
      expect(_symbolCell(59), findsOneWidget);

      // The temperature scale must NOT rescale per window: the y bounds are
      // computed over the whole recorded range, so the curve keeps its
      // absolute heights while scrolling.
      final chartMinY = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .minY;
      final recordedValues = _longEntries().map((e) => e.bbtC!).toList();
      expect(chartMinY, lessThanOrEqualTo(recordedValues.reduce((a, b) => a < b ? a : b)),
          reason: 'the y scale still covers the coldest recorded day');
    });

    testWidgets('jump-to-date: picking a date moves the window onto it',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _longEntries()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget,
          reason: 'the affordance opens the material date picker');
      // The window starts on the first recorded day (2026-01-01), so the
      // picker opens on that month. Day index of 2026-01-20 = 19. The
      // material picker confirms a day selection through its OK button.
      await tester.tap(find.text('20').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_symbolCell(19), findsOneWidget,
          reason: 'the picked day is now inside the rendered window');
      expect(_symbolCell(0), findsNothing,
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

      // Content is 60 columns wide plus the y-axis strip; at max scroll the
      // last day (index 59) sits at the content's right edge. Tap the day
      // column of index 58 (= 2026-02-28) inside the visible area.
      const leftAxisReservedSize = 44.0; // chart's y-title strip width
      const testViewportWidth = 800.0;
      const bodyPadding = 12.0;
      const viewportWidth = testViewportWidth - 2 * bodyPadding; // 776
      const contentWidth = 60 * 24.0; // minimum usable column -> 1440
      const maxOffset = contentWidth - viewportWidth; // 664
      const plotWidth = contentWidth - leftAxisReservedSize;
      // Content x of the tapped column, mapped back onto the screen.
      final tapContentX = leftAxisReservedSize + plotWidth * (58 / 59);
      final tapScreenX = bodyPadding + (tapContentX - maxOffset);
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

      // Same column mapping as the tap above; long-pressing instead of
      // tapping must behave identically (the chart's former long-press
      // behavior, kept for the overlay).
      const leftAxisReservedSize = 44.0;
      const bodyPadding = 12.0;
      const contentWidth = 60 * 24.0;
      const maxOffset = contentWidth - (800.0 - 2 * bodyPadding);
      final tapContentX =
          leftAxisReservedSize + (contentWidth - leftAxisReservedSize) * (58 / 59);
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.longPressAt(
          Offset(bodyPadding + (tapContentX - maxOffset), chartTop + 100));
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
        expect(_symbolCell(i), findsOneWidget,
            reason: 'a short range fits usefully on one screen');
      }

      final scrollView = find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
      expect(scrollView, findsOneWidget,
          reason: 'the chart is still laid out as one scrollable block');
      final state = tester.state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, 0,
          reason: '5 comfortable day columns fit the viewport exactly');
    });
  });
}
