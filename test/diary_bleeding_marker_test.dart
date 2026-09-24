// Widget test of the diary's day-tile bleeding marker: recorded bleeding
// renders the shared square-box symbol (see lib/ui/bleeding_symbol.dart)
// at the tile's 18 px size — the bottom-anchored fill-fraction convention
// the cycle chart's cells and the glossary sample share, asserted here
// through the tile's rendered geometry (getRect). The interruption badge
// Stack around the marker and the faint none dot stay as they are.
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
final _spottingDay = DateOnly.normalize(DateTime(2026, 9, 6));

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
            await db.entriesDao.upsertDaily(
              DailyEntry(
                date: _spottingDay,
                bbtC: 36.5,
                bleeding: Bleeding.spotting,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // The cycle-group tiles start collapsed; open the group first.
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // The heavy marker: an 18 px box with one solid fill of (4-1)/4 of the
      // box height, anchored at the box bottom.
      expect(_tileMarker(_heavyDay), findsOneWidget);
      final heavyBox = tester.getRect(_tileMarker(_heavyDay));
      expect(
        heavyBox.width,
        18,
        reason: 'the tile marker keeps its square 18 px box',
      );
      expect(heavyBox.height, 18);
      final heavyFillFinder = find.descendant(
        of: _tileMarker(_heavyDay),
        matching: find.byType(BleedingFill),
      );
      expect(heavyFillFinder, findsOneWidget);
      final heavyFill = tester.getRect(heavyFillFinder);
      expect(
        heavyFill.height,
        closeTo(18 * 3 / 4, 0.01),
        reason: 'heavy fills (level-1)/4 of the box height',
      );
      expect(
        heavyFill.bottom,
        closeTo(heavyBox.bottom, 0.01),
        reason: 'the fill is anchored at the box bottom',
      );
      expect(
        heavyFill.width,
        closeTo(18, 0.01),
        reason: 'the fill spans the full box width',
      );

      // The spotting marker: interrupted dots within the bottom quarter
      // band of its own box (three or more disjoint regions).
      final spottingDots = find.descendant(
        of: _tileMarker(_spottingDay),
        matching: find.byType(BleedingFill),
      );
      expect(
        spottingDots.evaluate().length,
        greaterThanOrEqualTo(3),
        reason: 'spotting interrupts the quarter band into dots',
      );
      final spottingBox = tester.getRect(_tileMarker(_spottingDay));
      final bandTop = spottingBox.top + spottingBox.height * 3 / 4;
      final dotRects = [
        for (var i = 0; i < spottingDots.evaluate().length; i++)
          tester.getRect(spottingDots.at(i)),
      ];
      for (final rect in dotRects) {
        expect(
          rect.top,
          greaterThanOrEqualTo(bandTop - 0.01),
          reason: 'the dots stay inside the bottom quarter band',
        );
      }
    },
  );
}
