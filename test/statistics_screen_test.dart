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
/// day (Mar 29, cycle day 1) with the peak on the SAME day: the "over all
/// cycles" variant drops to minimum cycle day 1. Cycle 2 produces no
/// measured circle of its own — a rise inside a cycle's first six days
/// has its six-low window truncated at the cycle's own tracked days (R9),
/// so no baseline and no candidate exist there — and the real (umrandete
/// Messung) variant keeps cycle 1's first circle, cycle day 14.
List<CycleMark> divergentMarks() => [
  ...screenMarks(),
  CycleMark(date: m(3, 29), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(date: m(3, 29), type: CycleMarkTypes.firstHigherMeasurement),
];

Finder countCard() => find.byKey(const ValueKey('statisticsCard-cyclesCount'));
Finder metricCard(String id) => find.byKey(ValueKey('statisticsCard-$id'));
Finder oldCard(String id) => find.byKey(ValueKey('statisticsCard-$id'));
Finder earliestFirstHigherCard() =>
    find.byKey(const ValueKey('statisticsCard-earliestFirstHigher'));

// The outside lines' English wordings, pinned before their arb keys
// (`statisticsShortestOutsideApp` / `statisticsFirstHigherOutsideApp`)
// exist — keep the prefixes in sync with the strings' final wordings.
const String outsideShortestPrefix = 'outside: ';
const String outsideEarliestPrefix = 'outside: cycle day ';

// The metric cards' count captions' plural rule, pinned before the arb key
// (`statisticsMetricFromCycles`) exists — keep in sync with the strings'
// final wordings (the singular form is the German proofread point).
String countCaption(int cycles) =>
    cycles == 1 ? 'from 1 cycle' : 'from $cycles cycles';

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
      'bleeding duration and the first-higher cycle day', (tester) async {
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
        matching: find.textContaining('(days)'),
      ),
      findsOneWidget,
      reason: 'the unit sits once in the card header',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Cycle length'),
      ),
      findsNothing,
      reason: 'the header carries the unit instead',
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
      find.descendant(of: metricCard('cycleLength'), matching: find.text('28')),
      findsNWidgets(2),
      reason: 'min and max both carry the bare value',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('28 days'),
      ),
      findsNothing,
      reason: 'metric-card rows carry no unit',
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
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text(countCaption(1)),
      ),
      findsOneWidget,
      reason: 'only the closed cycle has a length — the caption says so',
    );

    // Bleeding duration: spans 3 (cycle 1) and 2 (cycle 2) -> min 2, max 3,
    // average 2.5, POPULATION std-dev 0.5.
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.textContaining('(days)'),
      ),
      findsOneWidget,
      reason: 'the unit sits once in the card header',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('Bleeding duration'),
      ),
      findsNothing,
      reason: 'the header carries the unit instead',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('2'),
      ),
      findsOneWidget,
      reason: 'the minimum span, bare',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('2 days'),
      ),
      findsNothing,
      reason: 'metric-card rows carry no unit',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('3'),
      ),
      findsOneWidget,
      reason: 'the maximum span, bare',
    );
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text('3 days'),
      ),
      findsNothing,
      reason: 'metric-card rows carry no unit',
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
    expect(
      find.descendant(
        of: metricCard('bleedingDuration'),
        matching: find.text(countCaption(2)),
      ),
      findsOneWidget,
      reason: 'both bleeding cycles feed the card',
    );

    // The when-card keyed statisticsCard-firstHigher: cycle-day numbers,
    // not durations, so the header unit is the cycle-day one — pinned
    // case-insensitive, the parenthetical's capitalization is l10n's.
    expect(metricCard('riseSpan'), findsNothing);
    final firstHigherDay = metricCard('firstHigher');
    expect(firstHigherDay, findsOneWidget);
    expect(
      find.descendant(
        of: firstHigherDay,
        matching: find.textContaining(
          RegExp(r'\(cycle day\)', caseSensitive: false),
        ),
      ),
      findsOneWidget,
      reason: 'the header carries the cycle-day unit',
    );
    // Cycle 1's rise Mar 14 (measured 36.7 above the 36.4 low, after the
    // Mar 12 peak) resolves the when-figure — cycle day 14; cycle 2
    // carries no mark. Single value: min and max duplicate it, no spread.
    expect(
      find.descendant(of: firstHigherDay, matching: find.text('14')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: firstHigherDay, matching: find.text('14 days')),
      findsNothing,
      reason: 'metric-card rows carry no unit',
    );
    expect(
      find.descendant(of: firstHigherDay, matching: find.text('14.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstHigherDay, matching: find.text('0.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstHigherDay, matching: find.text(countCaption(1))),
      findsOneWidget,
      reason: 'only cycle 1 carries a resolved first higher',
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
        find.descendant(of: untilEnd, matching: find.textContaining('(days)')),
        findsOneWidget,
        reason: 'the unit sits once in the card header',
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('15')),
        findsNWidgets(2),
        reason: 'min and max duplicate the single span, bare',
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('15 days')),
        findsNothing,
        reason: 'metric-card rows carry no unit',
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('15.0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text('0.0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: untilEnd, matching: find.text(countCaption(1))),
        findsOneWidget,
        reason: 'the one qualified span feeds the card',
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

  testWidgets('the earliest first higher rows live on the summary card: both '
      'variants, real one primary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(entries: screenEntries(), marks: screenMarks()),
    );
    await tester.pumpAndSettle();

    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    // The real (umrandete Messung: the day after the peak when the
    // rise sits at/before it) variant: cycle 1's rise Mar 14, start
    // Mar 1 -> cycle day 14; the peak lies before the rise, so both
    // variants equal here.
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('after the mucus peak'),
      ),
      findsOneWidget,
      reason: 'the real variant row is labeled',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('cycle day 14'),
      ),
      findsNWidgets(2),
      reason: 'both variants equal here: cycle day 14',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('over all cycles'),
      ),
      findsOneWidget,
      reason: 'the fallback variant row is labeled',
    );
  });

  testWidgets('when the variants differ each summary variant row keeps its own '
      'in-app minimum', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(entries: screenEntries(), marks: divergentMarks()),
    );
    await tester.pumpAndSettle();

    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    // Cycle 2's rise mark sits on its first day (cycle day 1) on the
    // SAME day as its mucus peak. Cycle 2 produces no measured circle
    // of its own (R9 truncates its six-low window at its start), so
    // the real variant keeps cycle 1's first circle — cycle day 14 —
    // while the "over all cycles" minimum drops to cycle day 1.
    final rows = tester
        .widgetList<Text>(
          find.descendant(
            of: summaryEarliest,
            matching: find.textContaining('cycle day '),
          ),
        )
        .map((t) => t.data!)
        .toList();
    expect(rows, contains('cycle day 14'), reason: 'the real one (primary)');
    expect(
      rows,
      contains('cycle day 1'),
      reason: 'the "over all cycles" minimum',
    );
  });

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
      'Zykluslänge (Tage)',
      'Blutungsdauer (Tage)',
      'Dauer der Hochlage (Tage)',
      'Erste höhere Messung (Zyklustag)',
      'Standardabweichung',
      'Früheste erste höhere Messung',
      'Zyklustag 14',
    ]) {
      expect(find.textContaining(label), findsWidgets, reason: 'de: "$label"');
    }
    // The unit lives only in the card headers: the bare titles are gone
    // (the table header still renders "Erste höhere Messung" exactly, so
    // that one is not asserted gone).
    expect(find.text('Zykluslänge'), findsNothing);
    expect(find.text('Blutungsdauer'), findsNothing);
    expect(find.text('Dauer der Hochlage'), findsNothing);
    // The count captions in German: the singular wording on the three
    // single-fact metric cards, the plural on the two-bleeding-cycle card.
    expect(find.text('aus 1 Zyklus'), findsNWidgets(3));
    expect(find.text('aus 2 Zyklen'), findsOneWidget);
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
    // No riseSpan card exists on the screen, so nothing matches its key.
    expect(metricCard('riseSpan'), findsNothing);
    for (final id in ['cycleLength', 'bleedingDuration', 'firstHigher']) {
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
      expect(
        find.descendant(
          of: metricCard(id),
          matching: find.textContaining(RegExp('from \\d+ cycles?')),
        ),
        findsNothing,
        reason: '$id has no data — no count caption under the dashes',
      );
    }
    final emptyUntilEnd = find.byKey(
      const ValueKey('statisticsMetric-firstHigherUntilEnd'),
    );
    expect(emptyUntilEnd, findsOneWidget);
    expect(
      find.descendant(
        of: emptyUntilEnd,
        matching: find.textContaining(RegExp('from \\d+ cycles?')),
      ),
      findsNothing,
      reason: 'the empty Hochlage card carries no count caption',
    );
    // The earliest surfaces: the empty case keeps the summary row (and
    // its earliest card) hidden entirely, and the big earliest card is
    // gone — the summary card is the single earliest surface.
    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    expect(
      find.byKey(const ValueKey('statisticsCard-earliest')),
      findsNothing,
      reason: 'no summary row renders without any countable data',
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
    // figure dashing and the paper figure only on the outside line.
    expect(oldCard('shortest'), findsOneWidget);
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('—')),
      findsOneWidget,
      reason: 'the in-app main figure has no value to show',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.text('${outsideShortestPrefix}21'),
      ),
      findsOneWidget,
      reason: 'the paper figure lives on the outside line',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.textContaining(RegExp('from \\d+ cycles?')),
      ),
      findsNothing,
      reason: 'summary cards carry no count caption',
    );
    expect(
      find.textContaining('figures in parentheses'),
      findsNothing,
      reason: 'no parenthetical grouping and no hint line remain',
    );
    // The count card stays out of the summary row here too.
    expect(find.byKey(const ValueKey('statisticsCard-count')), findsNothing);
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('21')),
      findsNothing,
      reason: 'the paper value folds into the summary row only',
    );
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('—')),
      findsNWidgets(4),
      reason: 'no countable in-app length — every metric row dashes',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.textContaining(RegExp('from \\d+ cycles?')),
      ),
      findsNothing,
      reason: 'the all-dash card carries no count caption',
    );
    // Single recorded facts do NOT enter the distribution machinery.
    expect(
      find.byKey(const ValueKey('statisticsCard-distribution')),
      findsNothing,
    );
  });

  testWidgets('the shortest summary card keeps the in-app minimum as the '
      'main figure and surfaces the paper figure on the outside line, and '
      'the count card stays out of the summary row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperShortestCycleLength: 21,
      ),
    );
    await tester.pumpAndSettle();
    // The count card lives only on the top cycles-count surface; the
    // summary row holds shortest + earliest.
    expect(find.byKey(const ValueKey('statisticsCard-count')), findsNothing);
    expect(countCard(), findsOneWidget);
    // Shortest card: the in-app minimum stays the main figure untouched,
    // the paper figure shows on its own outside line.
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('28')),
      findsOneWidget,
      reason: 'the in-app minimum is the main figure',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.text('${outsideShortestPrefix}21'),
      ),
      findsOneWidget,
      reason: 'the paper figure lives on the outside line',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.textContaining(RegExp('from \\d+ cycles?')),
      ),
      findsNothing,
      reason: 'summary cards carry no count caption',
    );
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('21')),
      findsNothing,
      reason: 'the paper figure is never a bare second figure',
    );
    expect(
      find.textContaining('figures in parentheses'),
      findsNothing,
      reason: 'no parenthetical grouping and no hint line remain',
    );
    expect(
      find.descendant(
        of: metricCard('cycleLength'),
        matching: find.text('Maximum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('28')),
      findsNWidgets(2),
      reason: 'the in-app minimum and maximum stay untouched by the paper 21',
    );
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('21')),
      findsNothing,
    );
  });

  testWidgets('a paper shortest above the in-app minimum still surfaces on '
      'the outside line (no participation gate)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Paper 30 loses against the in-app 28: the main figure stays the
    // plain in-app minimum, and the outside line shows the paper figure
    // anyway — the line is a recorded fact, not a better minimum.
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
      reason: 'the smaller in-app minimum stays the main figure',
    );
    expect(
      find.descendant(
        of: oldCard('shortest'),
        matching: find.text('${outsideShortestPrefix}30'),
      ),
      findsOneWidget,
      reason: 'the paper figure shows even when it adds nothing to the minimum',
    );
    expect(
      find.descendant(of: oldCard('shortest'), matching: find.text('30')),
      findsNothing,
      reason: 'the paper figure is never a bare second figure',
    );
    expect(
      find.textContaining('figures in parentheses'),
      findsNothing,
      reason: 'no parenthetical grouping and no hint line remain',
    );
    // The paper 30 touches nothing on the metric card: min and max both
    // read the in-app 28.
    expect(
      find.descendant(of: metricCard('cycleLength'), matching: find.text('28')),
      findsNWidgets(2),
      reason: 'minimum and maximum duplicate the single value again',
    );
  });

  testWidgets('the earliest summary card shows the plain in-app rows and '
      'one outside line for the paper figure', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // In-app both variants are cycle day 14; the paper rise on cycle day
    // 5 shows only on the single outside line, not in the variant rows.
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
        matching: find.textContaining('after the mucus peak'),
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
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 14')),
      findsNWidgets(2),
      reason: 'both rows carry the in-app minimum un-grouped',
    );
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 5')),
      findsNothing,
      reason: 'the paper figure is never a row value',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('${outsideEarliestPrefix}5'),
      ),
      findsOneWidget,
      reason:
          'the paper figure lives on the single non-variant-split '
          'outside line',
    );
    expect(
      find.textContaining('figures in parentheses'),
      findsNothing,
      reason: 'no parenthetical grouping and no hint line remain',
    );
  });

  testWidgets('the earliest summary card without a paper value: plain '
      'in-app rows and neither hint line nor outside line', (tester) async {
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
        matching: find.textContaining('outside:'),
      ),
      findsNothing,
      reason: 'no paper value — no outside line on the summary cards',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining(RegExp('from \\d+ cycles?')),
      ),
      findsNothing,
      reason: 'summary cards carry no count caption',
    );
    expect(
      find.textContaining('figures in parentheses'),
      findsNothing,
      reason: 'no parenthetical grouping and no hint line remain',
    );
  });

  testWidgets('a paper earliest first higher surfaces on the summary '
      'card only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // In-app both variants are cycle day 14; a paper rise on cycle day 5
    // exists only as the summary row's outside line.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: screenMarks(),
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    expect(
      find.text('Earliest first higher measurement'),
      findsOneWidget,
      reason: 'one on-screen card carries the earliest title',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 14')),
      findsNWidgets(2),
      reason: 'the rows keep the in-app minima',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('${outsideEarliestPrefix}5'),
      ),
      findsOneWidget,
      reason: 'the paper figure lives on the outside line',
    );
  });

  testWidgets('a divergent in-app record keeps its "over all cycles" '
      'minimum on the summary card with a paper earliest pinned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The divergent in-app record (over all cycles = 1, real = 14 —
    // cycle 2 carries no measurable circle, R9) with paper 5 pinned:
    // both rows keep their own in-app minima, the paper figure shows on
    // the one outside line.
    await tester.pumpWidget(
      harness(
        entries: screenEntries(),
        marks: divergentMarks(),
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 1')),
      findsOneWidget,
      reason: 'the "over all cycles" minimum keeps its own figure',
    );
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 14')),
      findsOneWidget,
      reason: 'the real row keeps its in-app figure, un-min-combined',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('${outsideEarliestPrefix}5'),
      ),
      findsOneWidget,
      reason: 'the paper figure lives on the outside line',
    );
  });

  testWidgets('a paper earliest cannot qualify the real variant in-app: '
      'the summary card shows the dash plus the outside line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The narrow combination: the in-app cycle has a rise but NO marked
    // mucus peak, so the in-app "over all cycles" variant is cycle day 3
    // while the real (umrandete) variant qualifies nowhere in-app. The
    // follow-up start (Mar 29) gives the cycle a countable length so the
    // summary row renders; the paper earliest value is pinned and
    // surfaces as the card's outside line.
    await tester.pumpWidget(
      harness(
        entries: [
          DailyEntry(date: m(3, 1), bbtC: 36.4),
          DailyEntry(date: m(3, 29), bbtC: 36.4),
        ],
        marks: [
          CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart),
          CycleMark(date: m(3, 3), type: CycleMarkTypes.firstHigherMeasurement),
          CycleMark(date: m(3, 29), type: CycleMarkTypes.cycleStart),
        ],
        paperEarliestFirstHigherCycleDay: 5,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    expect(
      find.textContaining('no first higher measurement'),
      findsNothing,
      reason: 'the real variant stays unqualified on the screen',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('—')),
      findsOneWidget,
      reason: 'the real row dashes — the in-app variant has no value',
    );
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('cycle day 3')),
      findsOneWidget,
      reason: 'the "over all cycles" row keeps its in-app figure',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.text('${outsideEarliestPrefix}5'),
      ),
      findsOneWidget,
      reason: 'the paper figure lives on the outside line',
    );
  });

  testWidgets('without a paper value a genuinely unqualified real variant '
      'dashes on its summary row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The in-app cycle again has a rise but NO marked peak: the real
    // (umrandete) variant qualifies nowhere in-app, while the "over all
    // cycles" variant is cycle day 3. The follow-up start (Mar 29) gives
    // the cycle a countable length so the summary row renders.
    await tester.pumpWidget(
      harness(
        entries: [
          DailyEntry(date: m(3, 1), bbtC: 36.4),
          DailyEntry(date: m(3, 29), bbtC: 36.4),
        ],
        marks: [
          CycleMark(date: m(3, 1), type: CycleMarkTypes.cycleStart),
          CycleMark(date: m(3, 3), type: CycleMarkTypes.firstHigherMeasurement),
          CycleMark(date: m(3, 29), type: CycleMarkTypes.cycleStart),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      earliestFirstHigherCard(),
      findsNothing,
      reason: 'the summary card is the single earliest surface',
    );
    expect(
      find.textContaining('no first higher measurement'),
      findsNothing,
      reason: 'the real-variant note is gone from the screen',
    );
    final summaryEarliest = find.byKey(
      const ValueKey('statisticsCard-earliest'),
    );
    expect(summaryEarliest, findsOneWidget);
    expect(
      find.descendant(of: summaryEarliest, matching: find.text('—')),
      findsOneWidget,
      reason: 'the real row dashes — the in-app variant has no value',
    );
    expect(
      find.descendant(
        of: summaryEarliest,
        matching: find.textContaining('cycle day 3'),
      ),
      findsOneWidget,
      reason: 'the "over all cycles" row keeps its in-app value',
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
