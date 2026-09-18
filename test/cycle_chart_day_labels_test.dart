// Widget tests of the cycle tab's per-day column labels: every day column
// shows the day of month ("21.") and the day of cycle (count from the
// cycle start, 1, 2, 3 …); on the FIRST DAY of a calendar month the
// day-of-month label is replaced by the localized short month form
// (day-of-month rule, not a cycle-start rule), and the labels are built
// windowed at their global x positions (same pattern as the signal rows,
// test/cycle_chart_windowing_test.dart).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(marks)),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const Scaffold(body: ZyklusScreen()),
      ),
    );

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
      // 60 recorded days (2026-01-20 .. 2026-03-20): far more than one
      // screen, so only the on-screen window renders labels — and the
      // initial auto-scroll starts that window at the newest days, where
      // the later labels carry the content of THEIR day, not of a
      // re-indexed window.
      await tester.pumpWidget(_chartHarness(entries: _entries(60)));
      await tester.pumpAndSettle();

      expect(_dayLabel(0), findsNothing,
          reason: 'the earliest days are outside the initial (newest-days) '
              'window');
      expect(_dayLabel(59), findsOneWidget,
          reason: 'the newest day fills the initial window');

      // Day index 40 = 2026-03-01 (20 + 40 days): a month FIRST, so its
      // label is the short month form instead of "1." — and the day-of-
      // cycle line is its own (41, counting from 2026-01-20). The initial
      // window covers the range's tail, so index 40 renders without any
      // scrolling.
      expect(_label(40, 'Mar'), findsOneWidget,
          reason: 'March 1st shows the short month form even mid-window');
      expect(_label(40, '1.'), findsNothing);
      expect(_label(40, '41'), findsOneWidget);
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

    testWidgets(
        'the header corner (now in the frozen left rail, outside the '
        'scroll) shows the two column prototypes '
        '(a date sample and a cycle-day sample) with localized tooltips '
        'and semantics labels', (tester) async {
      // 5 days from 2026-01-20: no column label is "14." and no day of
      // cycle is 5, so the two prototype texts are unambiguous.
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      expect(corner, findsOneWidget);
      expect(find.descendant(of: corner, matching: find.text('14.')),
          findsOneWidget,
          reason: 'the date column prototype renders in the corner slot');
      expect(find.descendant(of: corner, matching: find.text('#5')),
          findsOneWidget,
          reason: 'the cycle-day column prototype renders in the corner slot');

      // Tooltips: the date prototype explains itself as the date column,
      // the cycle-day prototype as the cycle-day column.
      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Date', 'Cycle day']),
          reason: 'both prototypes carry their localized tooltip');

      // Semantics: the same labels are announced to screen readers.
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Date')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Cycle day')),
        findsOneWidget,
      );
    });

    testWidgets('the corner prototypes use the German wording in de',
        (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries(5), locale: const Locale('de')));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Datum', 'Zyklustag']));
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Datum')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Zyklustag')),
        findsOneWidget,
      );
    });
  });
}
