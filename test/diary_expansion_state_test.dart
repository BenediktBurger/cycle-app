// Expansion-state continuity in the Tagebuch sliver list: sibling
// expand/collapse shifts the cycle headers' sliver positions; a remounted
// header rebuilds collapsed while its day list stays expanded below it.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

final _now = DateTime.utc(2026, 9, 25);

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

Future<void> _seedTwoCycles(CycleDatabase db) async {
  await db.transaction(() async {
    for (var i = 0; i < 5; i++) {
      await db.entriesDao.upsertDaily(
        DailyEntry(date: d(8, 10 + i), bbtC: 36.4),
      );
    }
    for (var i = 0; i < 5; i++) {
      await db.entriesDao.upsertDaily(
        DailyEntry(date: d(9, 10 + i), bbtC: 36.5),
      );
    }
    await db.marksDao.addMark(d(8, 10), CycleMarkTypes.cycleStart);
    await db.marksDao.addMark(d(9, 10), CycleMarkTypes.cycleStart);
  });
}

final _harness = DiaryHarness(now: _now);

void main() {
  testWidgets('an expanded cycle keeps its header element when a sibling '
      'cycle expands (its day-list sliver inserts between the two '
      'headers)', (tester) async {
    _harness.tallSurface(tester, height: 2400);
    await tester.pumpWidget(_harness.scope(seed: _seedTwoCycles));
    await tester.pumpAndSettle();

    final headers = find.byType(ExpansionTile);
    expect(headers, findsNWidgets(2));

    // The list opens on the newest cycle: expanding it after the older one
    // inserts its day-list sliver between the two headers, shifting the
    // older cycle's slivers down.
    await tester.tap(headers.last);
    await tester.pumpAndSettle();
    final retained = tester.element(headers.last);

    await tester.tap(headers.first);
    await tester.pumpAndSettle();

    expect(
      tester.element(headers.last),
      same(retained),
      reason:
          'the older cycle\'s header element must survive the shift — '
          'otherwise its internal expansion state resets to collapsed '
          'while its day list stays expanded',
    );
  });

  testWidgets('an expanded cycle keeps its header element when a sibling '
      'cycle collapses (its day-list sliver is removed above the '
      'header)', (tester) async {
    _harness.tallSurface(tester, height: 2400);
    await tester.pumpWidget(_harness.scope(seed: _seedTwoCycles));
    await tester.pumpAndSettle();

    final headers = find.byType(ExpansionTile);
    expect(headers, findsNWidgets(2));

    // Collapsing the newest cycle removes its day-list sliver above the
    // older header, shifting the older one up.
    await tester.tap(headers.last);
    await tester.pumpAndSettle();
    await tester.tap(headers.first);
    await tester.pumpAndSettle();
    final retained = tester.element(headers.last);

    await tester.tap(headers.first);
    await tester.pumpAndSettle();

    expect(
      tester.element(headers.last),
      same(retained),
      reason:
          'the older cycle\'s header element must survive the shift — '
          'otherwise its internal expansion state resets to collapsed '
          'while its day list stays expanded',
    );
  });
}
