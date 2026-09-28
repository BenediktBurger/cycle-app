// Widget tests of the Tagebuch list's lazy day-tile building: a cycle whose
// span covers years (a far-past cycleStart mark anchors the count, real
// tracked days end at "now") must not BUILD its whole day list at once — the
// tiles exist only where the scroll list lays them out plus its cache
// extent. The everyday contracts ride on the same structure: the newest
// cycle opens the list (with the header's TRUE day count, silent gap
// included), its newest tiles build first, and tapping a built tile selects
// the day.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/diary_harness.dart';

final _now = DateTime.utc(2026, 9, 25);

// A cycleStart mark at the date picker's oldest reachable day — far enough
// in the past that the cycle's true span (mark → today) is years of
// calendar days, while the tracked data itself stays recent.
final _farMark = DateTime(2000, 1, 1);

final _marks = [CycleMark(date: _farMark, type: CycleMarkTypes.cycleStart)];

// ~2 years of plain tracked days, ending at the pinned "now" (one
// temperature per day, nothing else — the tile content must never be the
// subject here).
final _entries = <DailyEntry>[
  for (
    var day = DateOnly.addDays(_now, -729);
    !day.isAfter(_now);
    day = DateOnly.addDays(day, 1)
  )
    DailyEntry(date: day, bbtC: 36.5),
];

Future<void> _seedTwoYearsAndFarMark(CycleDatabase db) async {
  await db.transaction(() async {
    for (final entry in _entries) {
      await db.entriesDao.upsertDaily(entry);
    }
    await db.marksDao.addMark(_farMark, CycleMarkTypes.cycleStart);
  });
}

final _harness = DiaryHarness(now: _now);

// The tile's plain yMd date label — also the counting pattern below: a bare
// "d.m.yyyy" text exists only on a built day tile (the form's header button
// uses the longer yMMMEd shape, the cycle headers carry their title around
// the date).
final _tileDatePattern = RegExp(r'^\d{1,2}\.\d{1,2}\.\d{4}$');

Finder _builtDayTiles() => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && _tileDatePattern.hasMatch(w.data!),
);

String _tileDate(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day));

void main() {
  testWidgets('an expanded cycle builds its day tiles lazily, far below the '
      'true day count', (tester) async {
    _harness.tallSurface(tester, height: 3600);
    await tester.pumpWidget(_harness.scope(seed: _seedTwoYearsAndFarMark));
    await tester.pumpAndSettle();

    // The fixture's total day count, computed with the same pinned clock
    // the screen groups with: the tracked days themselves (real data is
    // never trimmed) — here one mark-opened cycle spanning all of them.
    final cycles = groupIntoCycles(_entries, _marks, today: _now);
    final totalDays = cycles.fold<int>(0, (n, c) => n + c.days.length);
    expect(
      totalDays,
      greaterThanOrEqualTo(700),
      reason: 'fixture sanity: ~2 years of tracked days in the list',
    );

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    final built = _builtDayTiles().evaluate().length;
    expect(
      built,
      greaterThan(0),
      reason: 'the newest cycle lays out its first tiles',
    );
    expect(
      built,
      lessThan(totalDays ~/ 4),
      reason:
          'an expanded cycle builds only the tiles it lays out '
          '($built built vs. $totalDays days in the cycles)',
    );
  });

  testWidgets('the newest cycle opens the list: the header counts the true '
      'span, its newest day tiles build right below it', (tester) async {
    _harness.tallSurface(tester, height: 3600);
    await tester.pumpWidget(_harness.scope(seed: _seedTwoYearsAndFarMark));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    // The header title anchors on the far-past opening mark's own date.
    final startLabel = DateFormat.yMd(
      'de',
    ).format(DateOnly.normalize(_farMark));
    expect(find.text('Zyklus ab $startLabel'), findsOneWidget);

    // The subtitle keeps the TRUE span day count (mark → today), not the
    // size of the rendered day list.
    final cycle = groupIntoCycles(_entries, _marks, today: _now).single;
    final trueDayCount =
        DateOnly.daysBetween(
          DateOnly.normalize(cycle.endDate),
          cycle.startDate,
        ) +
        1;
    final header =
        tester.widget<ExpansionTile>(find.byType(ExpansionTile).first).subtitle
            as Text;
    final shownDayCount = int.parse(header.data!.split(' ').first);
    expect(shownDayCount, trueDayCount);

    // The built tiles are the cycle's newest recorded days, newest first.
    expect(find.text(_tileDate(_now)), findsOneWidget);
    expect(find.text(_tileDate(DateOnly.addDays(_now, -1))), findsOneWidget);
    expect(find.text(_tileDate(DateOnly.addDays(_now, -2))), findsOneWidget);
  });

  testWidgets('tapping a built day tile selects that day', (tester) async {
    _harness.tallSurface(tester, height: 3600);
    await tester.pumpWidget(
      _harness.scope(
        seed: _seedTwoYearsAndFarMark,
        // A different selected day keeps "tap today's tile" observable: the
        // provider must actually change to the tapped day.
        selectedDay: DateOnly.addDays(_now, -3),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(_tileDate(_now)));
    await tester.pumpAndSettle();

    expect(
      DateOnly.sameDay((await savedDayOf(tester)).date, _now),
      isTrue,
      reason: 'the tapped tile moved the entry form to its day',
    );
  });
}
