// Widget test of the diary's day-tile bleeding marker: recorded bleeding
// renders the shared square-box symbol (see lib/ui/bleeding_symbol.dart)
// at the tile's 18 px size — the fill-fraction convention itself lives in
// test/bleeding_symbol_test.dart. The interruption badge Stack around the
// marker and the faint none dot stay as they are.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/bleeding_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/diary_harness.dart';

final _markerNow = DateTime(2026, 9, 10);

final _markerHarness = DiaryHarness(now: _markerNow);

final _heavyDay = DateOnly.normalize(DateTime(2026, 9, 5));

/// The day tile's date label, exactly as the screen formats it (the
/// pinned German locale).
String _tileTitle(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day));

/// The bleeding marker inside the tile whose title shows [day].
Finder _tileMarker(DateTime day) => find.descendant(
  of: find.ancestor(
    of: find.text(_tileTitle(day)),
    matching: find.byType(ListTile),
  ),
  matching: find.byType(BleedingSymbol),
);

void main() {
  testWidgets(
    'a day tile renders recorded bleeding as the shared square-box symbol',
    (tester) async {
      _markerHarness.tallSurface(tester);
      await tester.pumpWidget(
        _markerHarness.scope(
          seed: (db) async {
            await db.entriesDao.upsertDaily(
              DailyEntry(date: _heavyDay, bbtC: 36.4, bleeding: Bleeding.heavy),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // The cycle-group tiles start collapsed; open the group first.
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // The tile pins the shared symbol to its own 18 px square box.
      expect(_tileMarker(_heavyDay), findsOneWidget);
      final heavyBox = tester.getRect(_tileMarker(_heavyDay));
      expect(
        heavyBox.width,
        18,
        reason: 'the tile marker keeps its square 18 px box',
      );
      expect(heavyBox.height, 18);
    },
  );
}
