// Widget tests of the Statistik screen: the aggregate statistics live here
// (concentrated, since the cycle tab's evaluation table is the paper-form
// evaluation, not aggregates). Each metric group is covered by a
// min/max/average/std-dev card plus the "earliest first higher" rows; the
// cycle-count surface handles the observed-cycles-outside-app setting
// (the count card shows the total with the "in this app" meaning on
// its surface).
// Numbers only — no interpretation, mirroring the domain's hard rule.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/provider_fixtures.dart';

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

// Pins the summary row's description line in its English wording — the
// arb string (`statisticsSummaryPaperHint`) and this constant must stay
// in sync.
const String paperHintText =
    'figures in parentheses include the earlier, paper cycles';

Widget harness({
  List<DailyEntry> entries = const [],
  List<CycleMark> marks = const [],
  int observedOutsideApp = 0,
  int? paperShortestCycleLength,
  int? paperEarliestFirstHigherCycleDay,
  Locale locale = const Locale('en'),
  Stream<List<DailyEntry>> Function()? entriesStreamFactory,
  Stream<List<CycleMark>> Function()? marksStreamFactory,
}) => ProviderScope(
  overrides: [
    dailyEntriesProvider.overrideWith(
      (ref) => entriesStreamFactory?.call() ?? Stream.value(entries),
    ),
    marksProvider.overrideWith(
      (ref) => marksStreamFactory?.call() ?? Stream.value(marks),
    ),
    observedCyclesPin(observedOutsideApp),
    paperShortestPin(paperShortestCycleLength),
    paperEarliestPin(paperEarliestFirstHigherCycleDay),
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
  testWidgets('the cycle-count card totals in-app and outside-app cycles '
      'with the meaning on the surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        observedOutsideApp: 3,
      ),
    );
    await tester.pumpAndSettle();

    // The card title and the total: 2 mark-opened cycles in the app + the
    // 3 outside-app cycles from the setting = 5 observed cycles.
    expect(
      find.descendant(of: countCard(), matching: find.text('Observed cycles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: countCard(), matching: find.text('5')),
      findsOneWidget,
    );
    // The meaning stays on the surface: how the total is composed (one
    // composed caption line: "in this app: n · outside: m").
    expect(
      find.descendant(
        of: countCard(),
        matching: find.textContaining('in this app: 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: countCard(),
        matching: find.textContaining('outside: 3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('per-metric min/max/average/std-dev cards for cycle length, '
      'bleeding duration and rise span', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(entries: screenEntries(), marks: screenMarks()),
    );
    await tester.pumpAndSettle();

    // Cycle length: one counted length (28 days, the open cycle 2 has
    // none) -> min/max 28, average 28.0, std-dev of one value 0.0.
    expect(metricCard('cycleLength'), findsOneWidget);
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Cycle length'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Minimum'),
      ),
      findsOneWidget,
      reason: 'the minimum row is present',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Maximum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Average'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Standard deviation'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('28 days'),
      ),
      findsNWidgets(2),
      reason: 'min and max both carry the value',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('28.0'),
      ),
      findsOneWidget,
      reason: 'the average value',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('0.0'),
      ),
      findsOneWidget,
      reason: 'the std-dev of the single value',
    );

    // Bleeding duration: spans 3 (cycle 1) and 2 (cycle 2) -> min 2, max 3,
    // average 2.5, POPULATION std-dev 0.5.
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('Bleeding duration'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('2 days'),
      ),
      findsOneWidget,
      reason: 'the minimum span',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('3 days'),
      ),
      findsOneWidget,
      reason: 'the maximum span',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('2.5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('0.5'),
      ),
      findsOneWidget,
      reason: 'population std-dev: sqrt(0.25)',
    );

    // Rise span: first higher (Mar 14) to the day before the next start
    // (Mar 28) = 15 days, single value -> all scalars "no spread".
    expect(
      find.descendant(
        of: metricCard('riseSpan'),
        matching: find.text('First higher measurement → cycle end'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('riseSpan'),
        matching: find.text('15 days'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: metricCard('riseSpan'), matching: find.text('15.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: metricCard('riseSpan'), matching: find.text('0.0')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the shared first-higher-until-cycle-end metric keeps the upstream '
    'counting rule on the shared card shape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(entries: screenEntries(), marks: screenMarks()),
      );
      await tester.pumpAndSettle();

      // The upstream metric: cycle 1's first higher (Mar 14) counts to the
      // NEXT marked start (Mar 29) -> 15 — the same inclusive rule the
      // cycle table's column uses, so the metric and the table cannot
      // disagree. The trailing cycle has no known end here -> no value.
      final untilEnd = find.byKey(
        const ValueKey('statisticsMetric-firstHigherUntilEnd'),
      );
      expect(untilEnd, findsOneWidget);
      expect(
        find.descendant(
          of: untilEnd,
          matching: find.text('First higher measurement to end of cycle'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('15 days')),
        findsNWidgets(2),
        reason: 'min and max duplicate the single span',
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('15.0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('0.0')),
        findsOneWidget,
      );
    },
  );

  testWidgets('the per-cycle table renders below all other statistics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(entries: screenEntries(), marks: screenMarks()),
    );
    await tester.pumpAndSettle();

    final table = find.byKey(const ValueKey('statisticsCycleTable'));
    expect(table, findsOneWidget);
    // Two rows: one per mark-opened cycle (start-cell keyed).
    expect(find.byKey(const ValueKey('statisticsRowStart-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('statisticsRowStart-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('statisticsRowStart-2')), findsNothing);

    // Column headers: cycle start, bleeding days, first higher, length.
    for (final header in [
      'Cycle start',
      'Bleeding days',
      'First higher measurement',
      'Length',
    ]) {
      expect(
        find.descendant(of: table, matching: find.text(header)),
        findsOneWidget,
      );
    }

    // Row 0 (cycle Mar 1..Mar 28): bleeding days 3 (Mar 1-3), first
    // higher on day 14 of the cycle, length 28 days.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowStart-0')),
        matching: find.text('3/1/2026'),
      ),
      findsOneWidget,
      reason: 'the start column carries the cycle start date',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('statisticsRowBleeding-0')))
          .data,
      '3',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowFirstHigher-0')),
        matching: find.text('Cycle day 14'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowLength-0')),
        matching: find.text('28 days'),
      ),
      findsOneWidget,
    );

    // Row 1 (the trailing cycle): no length, no first higher yet. The
    // other cells carry their values (bleeding days 2, start date).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowStart-1')),
        matching: find.text('3/29/2026'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('statisticsRowBleeding-1')))
          .data,
      '2',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowFirstHigher-1')),
        matching: find.text('—'),
      ),
      findsOneWidget,
      reason: 'the trailing cycle carries no first higher yet',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statisticsRowLength-1')),
        matching: find.text('—'),
      ),
      findsOneWidget,
      reason: 'the trailing cycle carries no length yet',
    );

    // Below ALL other statistics: the table sits lower than the count
    // card and lower than the first-higher-until-end metric card.
    final countCardTop = tester.getTopLeft(
      find.byKey(const ValueKey('statisticsCard-cyclesCount')),
    );
    final untilEndTop = tester.getTopLeft(
      find.byKey(const ValueKey('statisticsMetric-firstHigherUntilEnd')),
    );
    expect(tester.getTopLeft(table).dy, greaterThan(countCardTop.dy));
    expect(tester.getTopLeft(table).dy, greaterThan(untilEndTop.dy));
  });

  testWidgets(
    'the earliest first higher rows: both variants, real one primary',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(entries: screenEntries(), marks: screenMarks()),
      );
      await tester.pumpAndSettle();

      // The real (strictly after the mucus peak) variant: cycle 1's rise
      // Mar 14, start Mar 1 -> cycle day 14; the peak lies before the rise,
      // so both variants equal here.
      expect(
        find.descendant(
          of: earliestCard(),
          matching: find.textContaining('strictly after'),
        ),
        findsOneWidget,
        reason: 'the real variant row is labeled',
      );
      expect(
        find.descendant(
          of: earliestCard(),
          matching: find.textContaining('cycle day 14'),
        ),
        findsNWidgets(2),
        reason: 'both variants equal here: cycle day 14',
      );
      expect(
        find.descendant(
          of: earliestCard(),
          matching: find.textContaining('over all cycles'),
        ),
        findsOneWidget,
        reason: 'the fallback variant row is labeled',
      );
    },
  );

  testWidgets(
    'when the variants differ the real one stays the primary row and the '
    '"over all cycles" row shows its own minimum',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(entries: screenEntries(), marks: divergentMarks()),
      );
      await tester.pumpAndSettle();

      // Cycle 2's rise mark sits on its first day (cycle day 1) but on the
      // SAME day as its mucus peak — not strictly after, so the real variant
      // keeps cycle day 14 while the "any" minimum drops to cycle day 1.
      final rows = tester
          .widgetList<Text>(
            find.descendant(
              of: earliestCard(),
              matching: find.textContaining('cycle day '),
            ),
          )
          .map((t) => t.data!)
          .toList();
      expect(rows, contains('cycle day 14'), reason: 'the real one (primary)');
      expect(rows, contains('cycle day 1'), reason: 'the own "any" minimum');
    },
  );

  testWidgets('the German wording renders on the de surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        observedOutsideApp: 3,
        locale: const Locale('de'),
      ),
    );
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
    'de locale: the fraction rows render the German comma separator',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          entries: screenEntries(),
          marks: screenMarks(),
          locale: const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();

      // Same fixtures as the en descriptive card: one-decimal aggregates —
      // only the separator flips with the effective locale.
      expect(
        find.descendant(
          of: metricCard('cycleLength'),
          matching: find.text('28,0'),
        ),
        findsOneWidget,
        reason: 'the cycle-length average renders comma in de',
      );
      expect(
        find.descendant(
          of: metricCard('cycleLength'),
          matching: find.text('0,0'),
        ),
        findsOneWidget,
        reason: 'the cycle-length standard deviation renders comma in de',
      );
      expect(
        find.descendant(
          of: metricCard('bleedingDuration'),
          matching: find.text('2,5'),
        ),
        findsOneWidget,
        reason: 'the bleeding-duration average renders comma in de',
      );
    },
  );

  testWidgets('no data: the dash surfaces and the zero cycle count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // The upstream wording: the mark-driven statistics appear from the
    // first recorded cycle start, not from two.
    expect(
      find.textContaining('once a first cycle start'),
      findsOneWidget,
      reason: 'the no-data note speaks the reworked wording',
    );
    expect(
      find.descendant(of: countCard(), matching: find.text('0')),
      findsOneWidget,
    );
    for (final id in ['cycleLength', 'bleedingDuration', 'riseSpan']) {
      expect(
        find.descendant(of: metricCard(id), matching: find.text('Minimum')),
        findsOneWidget,
        reason: '$id keeps its rows',
      );
      // All four metric rows render the dash.
      expect(
        find.descendant(of: metricCard(id), matching: find.text('—')),
        findsNWidgets(4),
      );
    }
    expect(
      find.descendant(of: earliestCard(), matching: find.text('—')),
      findsNWidgets(2),
      reason: 'both earliest-first-higher rows dash',
    );
    // The fact-gated per-cycle table: no cycle start recorded, no rows
    // (with ANY later data the table's row count is the
    // recorded-count gate, never the lengths').
    expect(find.byKey(const ValueKey('statisticsCycleTable')), findsNothing);
  });

  testWidgets('ONE recorded cycle: the table row shows, but no no-data '
      'note and nothing about lengths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        entries: [
          DailyEntry(date: m(3, 1), bbtC: 36.4, bleeding: Bleeding.heavy),
          DailyEntry(date: m(3, 2), bbtC: 36.4, bleeding: Bleeding.medium),
        ],
        marks: [CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart)],
      ),
    );
    await tester.pumpAndSettle();

    // One mark-opened cycle — the table's row rule.
    expect(find.byKey(const ValueKey('statisticsRowStart-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('statisticsRowLength-0')), findsOneWidget);
    // No "no-data" note: a cycle start IS recorded — the note's own
    // wording promises exactly that threshold.
    expect(find.textContaining('once a first cycle start'), findsNothing);
    // The lengths surfaces stay hidden: the still-open cycle has no
    // countable length yet.
    for (final id in ['shortest', 'distribution']) {
      expect(
        find.byKey(ValueKey('statisticsCard-$id')),
        findsNothing,
        reason: '$id is a lengths surface, untouched by the one-cycle case',
      );
    }
  });

  testWidgets('a paper-only shortest value renders on the summary row even '
      'with no in-app lengths (paper-only user)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        entries: [DailyEntry(date: m(3, 1), bbtC: 36.4)],
        marks: [CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart)],
        paperShortestCycleLength: 21,
      ),
    );
    await tester.pumpAndSettle();

    // One open in-app cycle: no countable in-app length — the summary row
    // still renders (the paper-only-shortest gate), with the in-app main
    // figure dashing and the paper figure as the grouped second figure
    // under the hint line.
    expect(oldCard('shortest'), findsOneWidget);
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('—')),
      findsOneWidget,
      reason: 'the in-app main figure has no value to show',
    );
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('21')),
      findsOneWidget,
      reason: 'the paper-inclusive minimum is the grouped figure',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.textContaining(paperHintText),
      ),
      findsOneWidget,
      reason: 'the hint names the paper cycles behind the grouped figure',
    );
    // The count card stays out of the summary row here too.
    expect(find.byKey(const ValueKey('statisticsCard-count')), findsNothing);
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('21 days'),
      ),
      findsNothing,
      reason: 'the paper value folds into the summary row only',
    );
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('—')),
      findsNWidgets(4),
      reason: 'no countable in-app length — every metric row dashes',
    );
    // Single recorded facts do NOT enter the distribution machinery.
    expect(
      find.byKey(const ValueKey('statisticsCard-distribution')),
      findsNothing,
    );
  });

  testWidgets('the shortest summary card groups the paper-inclusive '
      'minimum under the in-app main figure, and the count card stays out '
      'of the summary row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // In-app minimum is 28: paper 21 beats it on the summary figure.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperShortestCycleLength: 21,
      ),
    );
    await tester.pumpAndSettle();
    // The count card is gone from the summary row; the composed caption
    // lives on the top cycles-count card only.
    expect(find.byKey(const ValueKey('statisticsCard-count')), findsNothing);
    expect(countCard(), findsOneWidget);
    // Shortest card: the in-app minimum stays the main figure, the
    // paper-inclusive minimum is grouped under it with the hint line.
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('28')),
      findsOneWidget,
      reason: 'the in-app minimum is the main figure',
    );
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('21')),
      findsOneWidget,
      reason: 'the paper-inclusive minimum is the grouped figure',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.textContaining(paperHintText),
      ),
      findsOneWidget,
      reason: 'the hint names the paper cycles behind the grouped figure',
    );
    // The metric card:
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Maximum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('28 days'),
      ),
      findsNWidgets(2),
      reason: 'the in-app minimum and maximum stay untouched by the paper 21',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('21 days'),
      ),
      findsNothing,
    );
  });

  testWidgets('a paper shortest ABOVE the in-app minimum never flips the '
      'surfaced minimum upward (plain figure, no hint)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Paper 30 loses against the in-app 28: the shortest card keeps the
    // plain in-app figure — no grouped paper figure, no hint line.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperShortestCycleLength: 30,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('28')),
      findsOneWidget,
      reason: 'the smaller in-app minimum wins the fold',
    );
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('30')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.textContaining(paperHintText),
      ),
      findsNothing,
      reason:
          'the paper figure adds nothing to the minimum here, so the '
          'hint would describe a parenthesis that is not there',
    );
    // With the paper 30 folded out, min and max both read the in-app 28.
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('28 days'),
      ),
      findsNWidgets(2),
      reason: 'minimum and maximum duplicate the single value again',
    );
  });

  testWidgets('the earliest summary card groups both variants with the '
      'paper-inclusive figures and the hint line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // In-app both variants are cycle day 14; a paper rise on cycle day 5
    // is the earlier fact for both rows.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('Earliest first higher measurement'),
      ),
      findsOneWidget,
      reason: 'the neutral title; the variant labels live on the rows',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('strictly after the mucus peak'),
      ),
      findsOneWidget,
      reason: 'the real variant row keeps its label',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('over all cycles'),
      ),
      findsOneWidget,
      reason: 'the any-variant row keeps its label',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('cycle day 5'),
      ),
      findsNWidgets(2),
      reason: 'both rows carry the paper-inclusive minimum',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining(paperHintText),
      ),
      findsOneWidget,
      reason: 'the hint names the paper cycles behind the grouped figures',
    );
  });

  testWidgets('the earliest summary card without a paper value: plain '
      'in-app rows and no hint line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(entries: screenEntries(), marks: screenMarks()),
    );
    await tester.pumpAndSettle();
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('Earliest first higher measurement'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('cycle day 14'),
      ),
      findsNWidgets(2),
      reason: 'both variant rows carry the in-app minimum un-grouped',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining(paperHintText),
      ),
      findsNothing,
      reason: 'no paper value — no grouped figure, no hint',
    );
  });

  testWidgets('a paper earliest first higher stays out of the big '
      'earliest card\'s variant rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // In-app both variants are cycle day 14; a paper rise on cycle day 5
    // is pinned but surfaces on the summary row only.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    final rows = tester
        .widgetList<Text>(
          find.descendant(
            of: earliestCard(),
            matching: find.textContaining('cycle day '),
          ),
        )
        .map((t) => t.data!)
        .toList();
    expect(
      rows,
      everyElement('cycle day 14'),
      reason:
          'both variant rows '
          'carry the in-app minimum; the paper fact does not enter '
          'the card',
    );
  });

  testWidgets('a divergent in-app record keeps each variant row on its '
      'in-app value with a paper earliest pinned', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The divergent in-app record (any = 1, real = 14) with paper 5
    // pinned: the rows read the in-app values, the paper 5 stays on the
    // summary row.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: divergentMarks(),
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    final mixedRows = tester
        .widgetList<Text>(
          find.descendant(
            of: earliestCard(),
            matching: find.textContaining('cycle day '),
          ),
        )
        .map((t) => t.data!)
        .toList();
    expect(
      mixedRows,
      contains('cycle day 1'),
      reason: 'the in-app "any" minimum of 1 stays on its row',
    );
    expect(
      mixedRows,
      contains('cycle day 14'),
      reason: 'the real variant keeps its in-app day',
    );
    expect(
      mixedRows,
      isNot(contains('cycle day 5')),
      reason: 'the paper fact does not enter the card',
    );
  });

  testWidgets('the missing-real-variant note keys on the in-app variants: '
      'a paper figure alone does not suppress it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The narrow combination: the in-app rise sits ON its peak day (both
    // marks on one day), so the in-app "any" variant is cycle day 1 while
    // the real variant qualifies nowhere — a paper earliest value is
    // pinned, but it surfaces on the summary row only.
    await tester.pumpWidget(
      harness(
        entries: [DailyEntry(date: m(3, 1), bbtC: 36.4)],
        marks: [
          CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart),
          CycleMark(date: m(3, 1), type: CycleMarkTypes.mucusPeakDay),
          CycleMark(date: m(3, 1), type: CycleMarkTypes.firstHigherMeasurement),
        ],
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: earliestCard(),
        matching: find.textContaining('cycle day 5'),
      ),
      findsNothing,
      reason:
          'the paper figure does not enter the card, let alone the '
          'real row',
    );
    expect(
      find.descendant(of: earliestCard(), matching: find.text('—')),
      findsOneWidget,
      reason: 'the real row dashes — the in-app variant has no value',
    );
    expect(
      find.descendant(
        of: earliestCard(),
        matching: find.textContaining('no first higher measurement'),
      ),
      findsOneWidget,
      reason:
          'a paper figure alone does not qualify the real variant '
          'in-app, so the note stays true',
    );
    expect(
      find.descendant(
        of: earliestCard(),
        matching: find.textContaining('cycle day 1'),
      ),
      findsOneWidget,
      reason: 'the "any" row keeps its in-app value',
    );
  });

  testWidgets('without a paper value the same in-app shape genuinely lacks '
      'the real variant, and the note states exactly that', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The in-app rise sits ON its peak day again, but no paper fact folds
    // in: the real row dashes and the missing-variant note is true.
    await tester.pumpWidget(
      harness(
        entries: [DailyEntry(date: m(3, 1), bbtC: 36.4)],
        marks: [
          CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart),
          CycleMark(date: m(3, 1), type: CycleMarkTypes.mucusPeakDay),
          CycleMark(date: m(3, 1), type: CycleMarkTypes.firstHigherMeasurement),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: earliestCard(), matching: find.text('—')),
      findsOneWidget,
      reason: 'the real row genuinely dashes without the paper value',
    );
    expect(
      find.descendant(
        of: earliestCard(),
        matching: find.textContaining('no first higher measurement'),
      ),
      findsOneWidget,
      reason: 'the note appears only for the genuinely missing real variant',
    );
  });

  testWidgets('without surface data the paper values change nothing '
      '(default null keeps the no-data screen)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('statisticsCard-shortest')),
      findsNothing,
      reason: 'no paper value set — the empty case keeps its gate',
    );
  });

  group('memoized derived data', () {
    testWidgets('the derived-data provider holds one pass across an '
        'unrelated rebuild', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(entries: screenEntries(), marks: screenMarks()),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StatistikScreen)),
      );
      final before = container.read(derivedCycleDataProvider);

      // An unrelated surface change (a setting on the count card's
      // caption) rebuilds everything that watches it without re-deriving.
      container.read(observedCyclesOutsideAppProvider.notifier).state = 3;
      await tester.pumpAndSettle();

      final after = container.read(derivedCycleDataProvider);
      expect(identical(before, after), isTrue);
    });

    testWidgets('a year-2000 cycle-start mark settles with sane totals '
        'and no exception', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          entries: [
            DailyEntry(
              date: DateTime(2000, 1, 5),
              bbtC: 36.4,
              bleeding: Bleeding.medium,
            ),
          ],
          marks: [
            CycleMark(
              date: DateTime(2000, 1, 5),
              type: CycleMarkTypes.cycleStart,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The screen settles into the count card with the one recorded
      // mark-driven cycle — no grey screen, no far-past blow-up.
      expect(countCard(), findsOneWidget);
      expect(
        find.descendant(of: countCard(), matching: find.text('1')),
        findsOneWidget,
      );
    });
  });

  group('stream error retry surfaces', () {
    testWidgets('a marks stream error shows the retry surface instead of '
        'the statistics cards, and retry restores them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempt = 0;
      await tester.pumpWidget(
        harness(
          entries: screenEntries(),
          marks: screenMarks(),
          marksStreamFactory: () {
            attempt++;
            return attempt == 1
                ? Stream<List<CycleMark>>.error(StateError('injected error'))
                : Stream.value(screenMarks());
          },
        ),
      );
      await tester.pumpAndSettle();

      // NOT the statistics cards computed with silently-empty marks.
      expect(countCard(), findsNothing);
      expect(find.text('Loading failed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('marksStreamRetryButton')),
        findsOneWidget,
        reason: 'the error branch carries a retry affordance',
      );

      await tester.tap(find.byKey(const ValueKey('marksStreamRetryButton')));
      await tester.pumpAndSettle();

      expect(
        countCard(),
        findsOneWidget,
        reason:
            'the retry re-subscribed '
            'the provider and the real content rendered',
      );
      expect(attempt, 2, reason: 'the retry re-invoked the stream factory');
    });

    testWidgets('an entries stream error gains the retry affordance, and '
        'retry restores the cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempt = 0;
      await tester.pumpWidget(
        harness(
          entries: screenEntries(),
          marks: screenMarks(),
          entriesStreamFactory: () {
            attempt++;
            return attempt == 1
                ? Stream<List<DailyEntry>>.error(StateError('injected error'))
                : Stream.value(screenEntries());
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(countCard(), findsNothing);
      expect(find.text('Loading failed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('entriesStreamRetryButton')),
        findsOneWidget,
        reason: 'the error branch carries a retry affordance',
      );

      await tester.tap(find.byKey(const ValueKey('entriesStreamRetryButton')));
      await tester.pumpAndSettle();

      expect(countCard(), findsOneWidget);
      expect(attempt, 2);
    });

    testWidgets('the retry surface speaks the German wording in the de '
        'locale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          entries: screenEntries(),
          marks: screenMarks(),
          locale: const Locale('de'),
          marksStreamFactory: () =>
              Stream<List<CycleMark>>.error(StateError('injected error')),
        ),
      );
      await tester.pumpAndSettle();

      // The German wording is authoritative (language policy).
      expect(find.text('Laden fehlgeschlagen'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });
  });
}
