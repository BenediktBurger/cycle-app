// Widget tests of the cycle tab's per-day column labels: every day column
// shows the day of month ("21.") and the day of cycle (count from the
// cycle start, 1, 2, 3 …), the FIRST day of every cycle shows the
// localized short month form instead of the plain day number, and the
// labels are built windowed at their global x positions (same pattern as
// the symbol row, test/cycle_chart_windowing_test.dart).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A recorded range starting 2026-01-20 so the day of cycle (1, 2, …) never
// coincides with the day of month (20., 21., …) — the two label lines stay
// distinguishable.
DateTime _day(int index) => DateTime.utc(2026, 1, 20).add(Duration(days: index));

List<DailyEntry> _entries(int count, {Map<int, Bleeding> bleeding = const {}}) => [
      for (var i = 0; i < count; i++)
        DailyEntry(date: _day(i), bbtC: 36.5, bleeding: bleeding[i] ?? Bleeding.none),
    ];

Finder _dayLabel(int index) => find.byKey(ValueKey('dayLabel-$index'));

Finder _label(int index, String text) => find.descendant(
    of: find.byKey(ValueKey('dayLabel-$index')), matching: find.text(text));

Widget _chartHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
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
        locale: locale,
        home: const Scaffold(body: ZyklusScreen()),
      ),
    );

Finder _hScrollView() => find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);

void main() {
  group('per-day column labels', () {
    testWidgets('every day column shows day of month and day of cycle',
        (tester) async {
      // 5 recorded days, no bleeding onset anywhere: one leading cycle
      // group starting on 2026-01-20.
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      // Column 0 starts the (leading) cycle group at 2026-01-20, so it
      // carries the month form; the following days show plain numbers.
      expect(_label(0, 'Jan 20'), findsOneWidget);
      expect(_label(0, '1'), findsOneWidget);
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

    testWidgets('the first day of a cycle shows the localized short month '
        'form instead of the plain day number', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      expect(_label(0, 'Jan 20'), findsOneWidget,
          reason: 'the cycle start (2026-01-20) renders in the en short '
              'month form');
      expect(_label(0, '20.'), findsNothing,
          reason: 'the plain day number is replaced on the cycle start');
      // The following days keep the plain form.
      expect(_label(1, '21.'), findsOneWidget);
    });

    testWidgets('the German short month form is used in the de locale',
        (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries(5), locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(_label(0, '20. Jan.'), findsOneWidget,
          reason: 'the en-style "Jan 20" must not leak into the de locale');
      expect(_label(1, '21.'), findsOneWidget);
    });

    testWidgets('a new cycle restarts the day-of-cycle count and shows the '
        'month form again', (tester) async {
      // 40 days (2026-01-20 .. 2026-02-28); menstruation-level bleeding on
      // the first day and again on day index 35 (2026-02-24) after a
      // bleeding-free day 34, so a second cycle starts there.
      final bleeding = {
        0: Bleeding.heavy,
        35: Bleeding.heavy,
      };
      await tester.pumpWidget(_chartHarness(entries: _entries(40, bleeding: bleeding)));
      await tester.pumpAndSettle();

      // 40 narrow columns overflow the viewport, so the window around
      // indexes 34–36 only builds after scrolling towards the end.
      await tester.drag(_hScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // End of the first cycle: day of cycle 35 on 2026-02-23.
      expect(_label(34, '23.'), findsOneWidget);
      expect(_label(34, '35'), findsOneWidget);

      // Second cycle: the onset day shows the short month form and counts 1.
      expect(_label(35, 'Feb 24'), findsOneWidget);
      expect(_label(35, '24.'), findsNothing);
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
      // screen, so only the on-screen window renders labels — and after
      // scrolling, the later labels carry the content of THEIR day, not of
      // a re-indexed window.
      await tester.pumpWidget(_chartHarness(entries: _entries(60)));
      await tester.pumpAndSettle();

      expect(_dayLabel(0), findsOneWidget);
      expect(_dayLabel(40), findsNothing,
          reason: 'day 40 does not fit usefully on one screen -> not built');
      expect(_dayLabel(59), findsNothing);

      await tester.drag(_hScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      expect(_dayLabel(0), findsNothing,
          reason: 'the earliest labels scrolled out of the window');
      expect(_dayLabel(40), findsOneWidget);
      // Day index 40 = 2026-03-01 (20 + 40 days); its labels are its OWN:
      // day of month "1." and day of cycle 41 (counting from 2026-01-20).
      expect(_label(40, '1.'), findsOneWidget);
      expect(_label(40, '41'), findsOneWidget);
    });
  });
}
