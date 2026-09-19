// Widget tests of the cycle tab's per-day column labels: every day column
// shows the day of month ("21.") and the day of cycle (count from the
// cycle start, 1, 2, 3 …); on the FIRST DAY of a calendar month the
// day-of-month label is replaced by the localized short month form
// (day-of-month rule, not a cycle-start rule), and the labels are built
// windowed at their global x positions (same pattern as the signal rows,
// test/cycle_chart_windowing_test.dart).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chart_pump.dart';

// A recorded range starting 2026-01-20 so the day of cycle (1, 2, …) never
// coincides with the day of month (20., 21., …) — the two label lines stay
// distinguishable.
DateTime _day(int index) =>
    DateTime.utc(2026, 1, 20).add(Duration(days: index));

List<DailyEntry> _entries(int count,
        {Map<int, Bleeding> bleeding = const {}}) =>
    [
      for (var i = 0; i < count; i++)
        DailyEntry(
            date: _day(i), bbtC: 36.5, bleeding: bleeding[i] ?? Bleeding.none),
    ];

// A recorded range starting `start` (unlike _day above, so month-first
// scenarios can begin on other calendar days).
DateTime _dayFrom(DateTime start, int index) =>
    start.add(Duration(days: index));

List<DailyEntry> _entriesFrom(DateTime start, int count,
        {Map<int, Bleeding> bleeding = const {}}) =>
    [
      for (var i = 0; i < count; i++)
        DailyEntry(
          date: _dayFrom(start, i),
          bbtC: 36.5,
          bleeding: bleeding[i] ?? Bleeding.none,
        ),
    ];

Finder _dayLabel(int index) => find.byKey(ValueKey('dayLabel-$index'));

Finder _label(int index, String text) => find.descendant(
    of: find.byKey(ValueKey('dayLabel-$index')), matching: find.text(text));

Widget _chartHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, marks: marks, locale: locale);

void main() {
  group('per-day column labels', () {
    testWidgets(
        'every day column shows day of month and day of cycle; a '
        'cycle start that is not a month first stays a plain number',
        (tester) async {
      // 5 recorded days, no bleeding onset anywhere: one leading cycle
      // group starting on 2026-01-20.
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      // Column 0 starts the (leading) cycle group on 2026-01-20 — but the
      // month form follows the CALENDAR (day-of-month == 1), not the cycle,
      // so it shows its plain day number; the cycle start is only visible
      // in line 2 counting from 1.
      expect(_label(0, '20.'), findsOneWidget,
          reason: 'the non-month-first cycle start shows a plain day number');
      expect(_label(0, 'Jan'), findsNothing,
          reason: 'no month form on a cycle start that is not a month first');
      expect(_label(0, '1'), findsOneWidget,
          reason: 'day of cycle 1 on the cycle start');
      for (var i = 1; i < 5; i++) {
        expect(_label(i, '${20 + i}.'), findsOneWidget,
            reason: 'day column $i shows its day of month');
        expect(_label(i, '${i + 1}'), findsOneWidget,
            reason: 'day column $i shows its day of cycle (counted from the '
                'cycle start on 2026-01-20)');
      }

      // The label row replaces the old sparse bottom axis titles: no
      // duplicated day-of-month strip anywhere else in the chart.
      expect(find.text('21.'), findsOneWidget);
    });

    testWidgets(
        'the first day of a calendar month shows the localized '
        'short month form instead of the plain day number', (tester) async {
      // 2026-01-29 .. 2026-02-02: day index 3 is February 1st.
      await tester.pumpWidget(
          _chartHarness(entries: _entriesFrom(DateTime.utc(2026, 1, 29), 5)));
      await tester.pumpAndSettle();

      expect(_label(2, '31.'), findsOneWidget,
          reason: 'ordinary days keep the plain day number');
      expect(_label(3, 'Feb'), findsOneWidget,
          reason: 'February 1st renders the short month form');
      expect(_label(3, '1.'), findsNothing,
          reason: 'the "1." day number is replaced by the short month');
      // Day of cycle line 2 is unchanged: it keeps counting through the
      // month boundary (leading group started 2026-01-29).
      expect(_label(3, '4'), findsOneWidget);
      expect(_label(4, '2.'), findsOneWidget);
    });

    testWidgets('the German short month form is used in the de locale',
        (tester) async {
      // 2025-12-29 .. 2026-01-02: day index 3 is January 1st.
      await tester.pumpWidget(_chartHarness(
          entries: _entriesFrom(DateTime.utc(2025, 12, 29), 5),
          locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(_label(3, 'Jan.'), findsOneWidget,
          reason: 'the German month abbreviation keeps its trailing period');
      expect(_label(3, 'Jan '), findsNothing,
          reason: 'no en-style "1 Jan"-like composite may leak in');
      expect(_label(4, '2.'), findsOneWidget,
          reason: 'ordinary days show the plain day number');
      expect(_label(3, '4'), findsOneWidget,
          reason: 'day of cycle continues through the month boundary '
              '(leading group started 2025-12-29)');
    });

    testWidgets(
        'a month first that is also a cycle start shows the short '
        'month form, not the day number', (tester) async {
      // The recorded range BEGINS on 2026-02-01 (the leading group's
      // start, no cycleStart mark involved): the first of the month shows
      // the month form, and the leading group's day-of-cycle count also
      // starts at 1 there.
      await tester.pumpWidget(_chartHarness(
          entries: _entriesFrom(DateTime.utc(2026, 2, 1), 3,
              bleeding: {0: Bleeding.heavy})));
      await tester.pumpAndSettle();

      expect(_label(0, 'Feb'), findsOneWidget,
          reason: 'February 1st is a month first AND the range\'s first '
              'day — the month form shows');
      expect(_label(0, '1.'), findsNothing);
      expect(_label(0, '1'), findsOneWidget,
          reason: 'day of cycle 1 on the cycle start');
      expect(_label(1, '2.'), findsOneWidget);
      expect(_label(1, '2'), findsOneWidget);
    });

    testWidgets(
        'a new cycle starts mid-month with a plain day number and '
        'restarts the day-of-cycle count', (tester) async {
      // 40 days (2026-01-20 .. 2026-02-28); a cycleStart mark on day index
      // 35 (2026-02-24) opens the second cycle there — mid-month, hence a
      // plain day number despite the cycle start.
      final marks = [
        CycleMark(date: _day(35), type: CycleMarkTypes.cycleStart),
      ];
      await tester
          .pumpWidget(_chartHarness(entries: _entries(40), marks: marks));
      await tester.pumpAndSettle();

      // The initial auto-scroll puts the window at the newest days: the 40
      // narrow columns overflow the viewport, so the end of the recorded
      // range — the window around indexes 34–36 — is on screen right away.

      // End of the first cycle: day of cycle 35 on 2026-02-23.
      expect(_label(34, '23.'), findsOneWidget);
      expect(_label(34, '35'), findsOneWidget);

      // Second cycle: the onset day shows a PLAIN day number (month form
      // is only for month firsts) and counts 1.
      expect(_label(35, '24.'), findsOneWidget,
          reason: 'a mid-month cycle start is not a month first');
      expect(_label(35, 'Feb 24'), findsNothing);
      expect(_label(35, '1'), findsOneWidget);
      expect(_label(36, '25.'), findsOneWidget);
      expect(_label(36, '2'), findsOneWidget);
    });

    testWidgets('untracked gap days keep counting from the last cycle start',
        (tester) async {
      // Only day 0 (bleeding onset) and day 5 carry entries; days 1–4 are
      // untracked calendar gaps that still belong to the running cycle.
      final entries = [
        DailyEntry(date: _day(0), bbtC: 36.5, bleeding: Bleeding.heavy),
        DailyEntry(date: _day(5), bbtC: 36.5),
      ];
      await tester.pumpWidget(_chartHarness(entries: entries));
      await tester.pumpAndSettle();

      for (var i = 1; i < 5; i++) {
        expect(_label(i, '${20 + i}.'), findsOneWidget,
            reason: 'the untracked gap day $i still shows its day of month');
        expect(_label(i, '${i + 1}'), findsOneWidget,
            reason: 'the gap day keeps counting from the cycle start');
      }
    });

    testWidgets('the labels build windowed at their global x positions',
        (tester) async {
      // 100 recorded days (2026-01-20 .. 2026-04-29): far more than one
      // screen, so only the parked window renders labels — and the
      // initial auto-scroll starts that window at the newest days, where
      // the later labels carry the content of THEIR day, not of a
      // re-indexed window. The parked window carries an extra screen-width
      // of margin past the visible edges (31 columns at this viewport), so
      // the earliest days (index 0..36) stay outside it. The fixture keeps
      // its 100 days for exactly that windowing margin: at ~60 days the
      // parked window would swallow index 0.
      await tester.pumpWidget(_chartHarness(entries: _entries(100)));
      await tester.pumpAndSettle();

      expect(_dayLabel(0), findsNothing,
          reason: 'the earliest days are outside the initial (newest-days) '
              'parked window');
      expect(_dayLabel(99), findsOneWidget,
          reason: 'the newest day fills the initial window');

      // Day index 40 = 2026-03-01 (20 + 40 days): a month FIRST, so its
      // label is the short month form instead of "1." — and the day-of-
      // cycle line is its own (41, counting from 2026-01-20). The initial
      // parked window covers the range's tail, so index 40 renders without
      // any scrolling.
      expect(_label(40, 'Mar'), findsOneWidget,
          reason: 'March 1st shows the short month form even mid-window');
      expect(_label(40, '1.'), findsNothing);
      expect(_label(40, '41'), findsOneWidget);
    });
  });

  group('three-digit day-of-cycle labels', () {
    testWidgets(
        'a long mark-driven cycle (no cycle start in the recorded range — '
        'e.g. during pregnancy) keeps the three-digit day-of-cycle label '
        'inside its column', (tester) async {
      // 104 recorded days (2026-01-20 .. 2026-05-03) with NO cycleStart
      // marks: the leading cycle group's day-of-cycle counter runs 1..104,
      // so the range's tail renders three-digit day-of-cycle labels. The
      // 104 columns overflow the viewport, so every column renders at the
      // 24 px minimum width — the narrowest layout the chart ever uses.
      await tester.pumpWidget(_chartHarness(entries: _entries(104)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the three-digit day-of-cycle label must not overflow '
              'its 24 px column');

      // Day index 103 shows day-of-cycle 104 (the leading group counts
      // from 2026-01-20) and sits inside the parked window at the newest
      // days. Its rendered label must not paint past its column bounds.
      final column = tester.getRect(_dayLabel(103));
      final label = tester.getRect(
          find.descendant(of: _dayLabel(103), matching: find.text('104')));
      expect(label.left, greaterThanOrEqualTo(column.left - 0.5),
          reason: 'the rendered label does not paint left of its column');
      expect(label.right, lessThanOrEqualTo(column.right + 0.5),
          reason: 'the rendered label does not paint right of its column');
    });

    testWidgets(
        'short day-of-cycle labels keep their natural size — the label '
        'scales down only, never shrinks 1–2 digit numbers', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries(104)));
      await tester.pumpAndSettle();

      // Day index 45 shows day-of-cycle 46 (the leading group counts from
      // 2026-01-20) and sits inside the parked window at the newest days.
      // In the test font every glyph is a 1 em square, so the natural
      // (unshrunk) width of the label at fontSize 9 is exactly 2 * 9 = 18.
      final label = tester.getRect(
          find.descendant(of: _dayLabel(45), matching: find.text('46')));
      expect(label.width, closeTo(18.0, 0.5),
          reason: 'a two-digit day-of-cycle label renders at its natural, '
              'unshrunk size (it must never be scaled down to fit)');
    });
  });

  group('header above the chart', () {
    testWidgets(
        'the day header row renders ABOVE the temperature curve '
        '(the paper\'s header line on top of the sheet)', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final headerTop =
          tester.getRect(find.byKey(const ValueKey('dayLabel-2'))).top;
      expect(headerTop, lessThan(chartTop),
          reason: 'the day/cycle header sits above the chart, not below it');
    });

    // The header corner itself (a superset test with localized en tooltips,
    // semantics and the de wording variants) lives beside the rail it slots
    // into: test/cycle_chart_left_rail_test.dart.
  });
}
