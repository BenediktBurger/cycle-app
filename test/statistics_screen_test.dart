// Statistics screen end-to-end: the reworked Statistik screen over the REAL
// app surface — a cycle count card, one uniform detailed presentation
// (Minimum/Streuung/Maximum/Durchschnitt) for the three metrics (cycle
// length, bleeding days, first higher until end of cycle), the earliest
// first higher measurement as a day-of-cycle number, and below ALL other
// statistics a per-cycle table (start, bleeding days, first higher,
// length). The in-memory ProviderScope harness mirrors
// test/settings_persistence_test.dart: entries and marks are seeded through
// the real DAOs before the UI builds.
//
// Scenario (German device locale, German labels): four mark-opened cycles
// Mar 2 / Mar 30 / Apr 27 / May 25 2026 — lengths 28, 28, 28 (+ trailing);
// bleeding days 2 / 1 / 0 / 2; a first-higher mark on Mar 20 (day-of-cycle
// 19, ten days until the cycle end), no other first higher.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

Future<void> _seed(CycleDatabase db) async {
  final entries = [
    DailyEntry(date: DateTime(2026, 3, 2), bleeding: Bleeding.medium),
    DailyEntry(date: DateTime(2026, 3, 3), bleeding: Bleeding.medium),
    DailyEntry(date: DateTime(2026, 3, 4)),
    DailyEntry(date: DateTime(2026, 3, 20), bbtC: 36.4),
    DailyEntry(date: DateTime(2026, 3, 30), bleeding: Bleeding.medium),
    DailyEntry(date: DateTime(2026, 4, 27)),
    DailyEntry(date: DateTime(2026, 5, 25), bleeding: Bleeding.medium),
    DailyEntry(date: DateTime(2026, 5, 26), bleeding: Bleeding.medium),
  ];
  for (final entry in entries) {
    await db.entriesDao.upsertDaily(entry);
  }
  const starts = [(2026, 3, 2), (2026, 3, 30), (2026, 4, 27), (2026, 5, 25)];
  for (final (y, m, d) in starts) {
    await db.marksDao.addMark(DateTime(y, m, d), CycleMarkTypes.cycleStart);
  }
  await db.marksDao.addMark(
    DateTime(2026, 3, 20),
    CycleMarkTypes.firstHigherMeasurement,
  );
}

String _dateLabel(DateTime day) => DateFormat.yMd(
  'de',
).format(DateTime.utc(day.year, day.month, day.day).toLocal());

/// Pumps the real app (German device locale → German labels) against the
/// in-memory database and opens the statistics tab.
Future<void> pumpStatisticsScreen(WidgetTester tester) async {
  useDeviceLocales(tester, const [Locale('de')]);
  await tester.pumpWidget(appScope(locale: const Locale('de'), seed: _seed));
  await tester.pumpAndSettle();

  await tester.tap(navLabel('Statistik'));
  await tester.pumpAndSettle();
}

final countCard = find.byKey(const ValueKey('statisticsCycleCountCard'));
final earliestEntry = find.byKey(
  const ValueKey('statisticsEarliestFirstHigher'),
);
final table = find.byKey(const ValueKey('statisticsCycleTable'));
Finder tableCell(String prefix, int index) =>
    find.byKey(ValueKey('$prefix-$index'));
Finder insideMetric(String id, Finder inner) => find.descendant(
  of: find.byKey(ValueKey('statisticsMetric-$id')),
  matching: inner,
);

void main() {
  testWidgets('the cycle-count card shows the number of mark-opened cycles', (
    tester,
  ) async {
    await pumpStatisticsScreen(tester);

    expect(
      countCard,
      findsOneWidget,
      reason: 'the count card is one of the topmost statistics',
    );
    expect(
      find.descendant(of: countCard, matching: find.text('4')),
      findsOneWidget,
      reason: 'the card shows just the count of the four mark-opened cycles',
    );
  });

  testWidgets('the three metrics share the uniform '
      'minimum/streuung/maximum/durchschnitt presentation', (tester) async {
    await pumpStatisticsScreen(tester);

    // Cycle lengths [28, 28, 28] (the trailing cycle has no length yet).
    expect(insideMetric('cycleLength', find.text('Minimum')), findsOneWidget);
    expect(insideMetric('cycleLength', find.text('Maximum')), findsOneWidget);
    expect(insideMetric('cycleLength', find.text('Streuung')), findsOneWidget);
    expect(
      insideMetric('cycleLength', find.text('Durchschnitt')),
      findsOneWidget,
    );
    expect(insideMetric('cycleLength', find.text('28')), findsNWidgets(2));
    expect(insideMetric('cycleLength', find.text('0,0')), findsOneWidget);
    expect(insideMetric('cycleLength', find.text('28,0')), findsOneWidget);

    // Bleeding days [2, 1, 0, 2]: minimum 0, maximum 2, average 1.25,
    // population std ≈ 0.829.
    expect(insideMetric('bleedingDays', find.text('0')), findsOneWidget);
    expect(insideMetric('bleedingDays', find.text('2')), findsOneWidget);
    expect(insideMetric('bleedingDays', find.text('0,8')), findsOneWidget);
    expect(insideMetric('bleedingDays', find.text('1,3')), findsOneWidget);

    // First higher until end of cycle [10]: min/max duplicate 10, the
    // spread is 0, the average 10,0.
    expect(insideMetric('firstHigherUntilEnd', find.text('-')), findsNothing);
    expect(
      insideMetric('firstHigherUntilEnd', find.text('10')),
      findsNWidgets(2),
    );
    expect(
      insideMetric('firstHigherUntilEnd', find.text('0,0')),
      findsOneWidget,
    );
    expect(
      insideMetric('firstHigherUntilEnd', find.text('10,0')),
      findsOneWidget,
    );
  });

  testWidgets('the earliest first higher measurement entry names its '
      'day-of-cycle number', (tester) async {
    // A tall surface: the entry sits with the metrics high on the list,
    // but the lazy list must build it for the finder to see it at all.
    useTallSurface(tester);
    await pumpStatisticsScreen(tester);

    expect(
      earliestEntry,
      findsOneWidget,
      reason: 'the earliest-first-higher entry sits with the metrics',
    );
    expect(
      find.descendant(of: earliestEntry, matching: find.text('Zyklustag 19')),
      findsOneWidget,
      reason: 'Mar 20 is day 19 of the cycle starting Mar 2',
    );
  });

  testWidgets('the per-cycle table renders below all other statistics', (
    tester,
  ) async {
    // A tall surface: the lazy list only builds what the viewport holds,
    // so position assertions need the whole content on stage.
    useTallSurface(tester);
    await pumpStatisticsScreen(tester);

    expect(table, findsOneWidget);
    // Four rows: one per mark-opened cycle (start-cell keyed).
    expect(tableCell('statisticsRowStart', 0), findsOneWidget);
    expect(tableCell('statisticsRowStart', 3), findsOneWidget);
    expect(tableCell('statisticsRowStart', 4), findsNothing);

    // Column headers: cycle start, bleeding days, first higher, length.
    expect(
      find.descendant(of: table, matching: find.text('Zyklusbeginn')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('Blutungstage')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('Erste höhere Messung')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('Länge')),
      findsOneWidget,
    );

    // Row 1 (cycle Mar 2..Mar 29): bleeding days 2, first higher on day 19
    // of the cycle, length 28 days.
    expect(
      find.descendant(
        of: tableCell('statisticsRowStart', 0),
        matching: find.text(_dateLabel(DateTime(2026, 3, 2))),
      ),
      findsOneWidget,
      reason: 'the start column carries the cycle start date',
    );
    expect(
      find.descendant(
        of: tableCell('statisticsRowFirstHigher', 0),
        matching: find.text('Zyklustag 19'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tableCell('statisticsRowLength', 0),
        matching: find.text('28 Tage'),
      ),
      findsOneWidget,
    );

    // Row 4 (the trailing cycle): no length, no first higher yet. The
    // other cells carry their values (bleeding days 2, start date).
    expect(
      find.descendant(
        of: tableCell('statisticsRowFirstHigher', 3),
        matching: find.text('-'),
      ),
      findsOneWidget,
      reason: 'the trailing cycle carries no first higher yet',
    );
    expect(
      find.descendant(
        of: tableCell('statisticsRowLength', 3),
        matching: find.text('-'),
      ),
      findsOneWidget,
      reason: 'the trailing cycle carries no length yet',
    );

    // Below ALL other statistics: the table sits lower than the count card
    // and lower than the last metric card.
    expect(
      tester.getTopLeft(table).dy,
      greaterThan(tester.getTopLeft(countCard).dy),
    );
    expect(
      tester.getTopLeft(table).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('statisticsMetric-firstHigherUntilEnd'),
              ),
            )
            .dy,
      ),
    );
  });

  testWidgets('the old per-cycle lists and the shortest/longest trio are '
      'gone', (tester) async {
    useTallSurface(tester);
    await pumpStatisticsScreen(tester);

    expect(find.text('Zykluslängen'), findsNothing);
    expect(find.text('Zyklusbeginne'), findsNothing);
    expect(find.text('Kürzester'), findsNothing);
    expect(find.text('Längster'), findsNothing);
  });

  testWidgets('the empty state speaks the updated wording', (tester) async {
    // Entries but no marks: no mark-opened cycle, no statistics.
    useDeviceLocales(tester, const [Locale('de')]);
    await tester.pumpWidget(
      appScope(
        locale: const Locale('de'),
        seed: (db) => db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 3, 2), bleeding: Bleeding.medium),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Statistik'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Sobald ein erster Zyklusbeginn erfasst ist, erscheinen hier '
        'Statistiken.',
      ),
      findsOneWidget,
      reason: 'statistics appear once a cycle start (with data) exists',
    );
    expect(
      find.text(
        'Sobald zwei Zyklusbeginne erfasst sind, erscheinen '
        'Zykluslängen.',
      ),
      findsNothing,
      reason: 'the outdated two-starts wording must not render',
    );
    expect(countCard, findsNothing);
  });
}
