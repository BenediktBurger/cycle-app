// Widget tests of the Statistik screen: the aggregate statistics live here
// (concentrated, since the cycle tab's evaluation table is the paper-form
// evaluation, not aggregates). Each metric group is covered by a
// min/max/average/std-dev card plus the "earliest first higher" rows; the
// cycle-count surface handles the observed-cycles-outside-app setting
// (the count card shows the total with the "in this app" meaning on
// its surface). The old surfaces (cycle-length list, average/shortest/
// longest, cycle starts, distribution) stay. Numbers only — no
// interpretation, mirroring the domain's hard rule.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime m(int month, int day) => DateTime.utc(2026, month, day);

/// Two marked cycles, 2026:
///   cycle 1: start Mar 1 — bleeding Mar 1-3 (span 3), six measured low
///            days 36.4 from Mar 4, mucus-peak mark Mar 12, first-higher
///            mark Mar 14 (measured 36.7 Mar 14-16), cycle 2 starts Mar 29
///            -> rise span Mar 14..Mar 28 = 15 days; length 28
///   cycle 2: start Mar 29 — bleeding Mar 29-30 (span 2), open (no
///            follow-up start)
List<DailyEntry> screenEntries() => [
      DailyEntry(date: m(3, 1), bbtC: 36.4, bleeding: Bleeding.heavy),
      DailyEntry(date: m(3, 2), bbtC: 36.4, bleeding: Bleeding.medium),
      DailyEntry(date: m(3, 3), bbtC: 36.4, bleeding: Bleeding.light),
      DailyEntry(date: m(3, 4), bbtC: 36.4),
      DailyEntry(date: m(3, 5), bbtC: 36.4),
      DailyEntry(date: m(3, 6), bbtC: 36.4),
      DailyEntry(date: m(3, 7), bbtC: 36.4),
      DailyEntry(date: m(3, 8), bbtC: 36.4),
      DailyEntry(date: m(3, 14), bbtC: 36.7),
      DailyEntry(date: m(3, 15), bbtC: 36.7),
      DailyEntry(date: m(3, 16), bbtC: 36.7),
      DailyEntry(date: m(3, 29), bbtC: 36.4, bleeding: Bleeding.medium),
      DailyEntry(date: m(3, 30), bbtC: 36.4, bleeding: Bleeding.light),
    ];

List<CycleMark> screenMarks() => [
      CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart),
      CycleMark(date: m(3, 29), type: CycleMarkTypes.cycleStart),
      CycleMark(date: m(3, 12), type: CycleMarkTypes.mucusPeakDay),
      CycleMark(date: m(3, 14), type: CycleMarkTypes.firstHigherMeasurement),
    ];

/// Variant of [screenMarks] adding a first-higher mark ON cycle 2's first
/// day (Mar 29, cycle day 1) with the peak on the SAME day — a rise NOT
/// strictly after the peak: it changes the "over all cycles" variant
/// (minimum cycle day 1) but not the real one (cycle day 14 stays).
List<CycleMark> divergentMarks() => [
      ...screenMarks(),
      CycleMark(date: m(3, 29), type: CycleMarkTypes.mucusPeakDay),
      CycleMark(date: m(3, 29), type: CycleMarkTypes.firstHigherMeasurement),
    ];

Finder countCard() => find.byKey(const ValueKey('statisticsCard-cyclesCount'));
Finder metricCard(String id) => find.byKey(ValueKey('statisticsCard-$id'));
Finder oldCard(String id) => find.byKey(ValueKey('statisticsCard-$id'));
Finder earliestCard() =>
    find.byKey(const ValueKey('statisticsCard-earliestFirstHigher'));

Widget harness({
  List<DailyEntry> entries = const [],
  List<CycleMark> marks = const [],
  int observedOutsideApp = 0,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(marks)),
        observedCyclesOutsideAppProvider
            .overrideWith((ref) => observedOutsideApp),
      ],
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF6750A4)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const Scaffold(body: StatistikScreen()),
      ),
    );

void main() {
  testWidgets(
      'the cycle-count card totals in-app and outside-app cycles '
      'with the meaning on the surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(
      entries: screenEntries(),
      marks: screenMarks(),
      observedOutsideApp: 3,
    ));
    await tester.pumpAndSettle();

    // The card title and the total: 2 mark-opened cycles in the app + the
    // 3 outside-app cycles from the setting = 5 observed cycles.
    expect(
        find.descendant(
            of: countCard(), matching: find.text('Observed cycles')),
        findsOneWidget);
    expect(find.descendant(of: countCard(), matching: find.text('5')),
        findsOneWidget);
    // The meaning stays on the surface: how the total is composed (one
    // composed caption line: "in this app: n · outside: m").
    expect(
        find.descendant(
            of: countCard(), matching: find.textContaining('in this app: 2')),
        findsOneWidget);
    expect(
        find.descendant(
            of: countCard(), matching: find.textContaining('outside: 3')),
        findsOneWidget);
  });

  testWidgets(
      'per-metric min/max/average/std-dev cards for cycle length, '
      'bleeding duration and rise span', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(harness(entries: screenEntries(), marks: screenMarks()));
    await tester.pumpAndSettle();

    // Cycle length: one counted length (28 days, the open cycle 2 has
    // none) -> min/max 28, average 28.0, std-dev of one value 0.0.
    expect(metricCard('cycleLength'), findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('Cycle length')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('Minimum')),
        findsOneWidget,
        reason: 'the minimum row is present');
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('Maximum')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('Average')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('cycleLength'),
            matching: find.text('Standard deviation')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('28 days')),
        findsNWidgets(2),
        reason: 'min and max both carry the value');
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('28.0')),
        findsOneWidget,
        reason: 'the average value');
    expect(
        find.descendant(
            of: metricCard('cycleLength'), matching: find.text('0.0')),
        findsOneWidget,
        reason: 'the std-dev of the single value');

    // Bleeding duration: spans 3 (cycle 1) and 2 (cycle 2) -> min 2, max 3,
    // average 2.5, POPULATION std-dev 0.5.
    expect(
        find.descendant(
            of: metricCard('bleedingDuration'),
            matching: find.text('Bleeding duration')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('bleedingDuration'), matching: find.text('2 days')),
        findsOneWidget,
        reason: 'the minimum span');
    expect(
        find.descendant(
            of: metricCard('bleedingDuration'), matching: find.text('3 days')),
        findsOneWidget,
        reason: 'the maximum span');
    expect(
        find.descendant(
            of: metricCard('bleedingDuration'), matching: find.text('2.5')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('bleedingDuration'), matching: find.text('0.5')),
        findsOneWidget,
        reason: 'population std-dev: sqrt(0.25)');

    // Rise span: first higher (Mar 14) to the day before the next start
    // (Mar 28) = 15 days, single value -> all scalars "no spread".
    expect(
        find.descendant(
            of: metricCard('riseSpan'),
            matching: find.text('First higher measurement → cycle end')),
        findsOneWidget);
    expect(
        find.descendant(
            of: metricCard('riseSpan'), matching: find.text('15 days')),
        findsNWidgets(2));
    expect(
        find.descendant(
            of: metricCard('riseSpan'), matching: find.text('15.0')),
        findsOneWidget);
    expect(
        find.descendant(of: metricCard('riseSpan'), matching: find.text('0.0')),
        findsOneWidget);
  });

  testWidgets('the earliest first higher rows: both variants, real one primary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(harness(entries: screenEntries(), marks: screenMarks()));
    await tester.pumpAndSettle();

    // The real (strictly after the mucus peak) variant: cycle 1's rise
    // Mar 14, start Mar 1 -> cycle day 14; the peak lies before the rise,
    // so both variants equal here.
    expect(
        find.descendant(
            of: earliestCard(),
            matching: find.textContaining('strictly after')),
        findsOneWidget,
        reason: 'the real variant row is labeled');
    expect(
        find.descendant(
            of: earliestCard(), matching: find.textContaining('cycle day 14')),
        findsNWidgets(2),
        reason: 'both variants equal here: cycle day 14');
    expect(
        find.descendant(
            of: earliestCard(),
            matching: find.textContaining('over all cycles')),
        findsOneWidget,
        reason: 'the fallback variant row is labeled');
  });

  testWidgets(
      'when the variants differ the real one stays the primary row and the '
      '"over all cycles" row shows its own minimum', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(harness(entries: screenEntries(), marks: divergentMarks()));
    await tester.pumpAndSettle();

    // Cycle 2's rise mark sits on its first day (cycle day 1) but on the
    // SAME day as its mucus peak — not strictly after, so the real variant
    // keeps cycle day 14 while the "any" minimum drops to cycle day 1.
    final rows = tester
        .widgetList<Text>(find.descendant(
            of: earliestCard(), matching: find.textContaining('cycle day ')))
        .map((t) => t.data!)
        .toList();
    expect(rows, contains('cycle day 14'), reason: 'the real one (primary)');
    expect(rows, contains('cycle day 1'), reason: 'the own "any" minimum');
  });

  testWidgets('the German wording renders on the de surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness(
      entries: screenEntries(),
      marks: screenMarks(),
      observedOutsideApp: 3,
      locale: const Locale('de'),
    ));
    await tester.pumpAndSettle();

    for (final label in [
      'Beobachtete Zyklen',
      'in dieser App: 2',
      'außerhalb: 3',
      'Zykluslänge',
      'Blutungsdauer',
      'Standardabweichung',
      'Früheste erste höhere Messung',
      'Zyklustag 14',
    ]) {
      expect(find.textContaining(label), findsWidgets, reason: 'de: "$label"');
    }
  });

  testWidgets(
      'the old surfaces remain: lengths list, average/shortest/longest, '
      'cycle starts, distribution', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(harness(entries: screenEntries(), marks: screenMarks()));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: oldCard('lengthsList'), matching: find.text('Cycle lengths')),
        findsOneWidget);
    expect(
        find.descendant(
            of: oldCard('lengthsList'), matching: find.text('28 days')),
        findsOneWidget);
    expect(
        find.descendant(of: oldCard('average'), matching: find.text('Average')),
        findsOneWidget);
    expect(find.descendant(of: oldCard('average'), matching: find.text('28.0')),
        findsOneWidget);
    expect(
        find.descendant(
            of: oldCard('shortest'), matching: find.text('Shortest')),
        findsOneWidget);
    expect(find.descendant(of: oldCard('shortest'), matching: find.text('28')),
        findsOneWidget);
    expect(
        find.descendant(of: oldCard('longest'), matching: find.text('Longest')),
        findsOneWidget);
    expect(
        find.descendant(
            of: oldCard('onsets'), matching: find.text('Cycle starts')),
        findsOneWidget);
    expect(
        find.descendant(of: oldCard('onsets'), matching: find.text('3/1/2026')),
        findsOneWidget);
    expect(
        find.descendant(
            of: oldCard('distribution'), matching: find.text('Distribution')),
        findsOneWidget);
  });

  testWidgets('no data: the dash surfaces and the zero cycle count',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // The upstream wording: the mark-driven statistics appear from the
    // first recorded cycle start, not from two.
    expect(find.textContaining('once a first cycle start'), findsOneWidget,
        reason: 'the no-data note speaks the reworked wording');
    expect(find.descendant(of: countCard(), matching: find.text('0')),
        findsOneWidget);
    for (final id in ['cycleLength', 'bleedingDuration', 'riseSpan']) {
      expect(
          find.descendant(
              of: metricCard(id), matching: find.text('Minimum')),
          findsOneWidget,
          reason: '$id keeps its rows');
      // All four metric rows render the dash.
      expect(find.descendant(of: metricCard(id), matching: find.text('—')),
          findsNWidgets(4));
    }
    expect(find.descendant(of: earliestCard(), matching: find.text('—')),
        findsNWidgets(2),
        reason: 'both earliest-first-higher rows dash');
  });
}
