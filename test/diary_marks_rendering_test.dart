// Widget tests of the two full-text surfaces for the stored custom marks:
// the diary list's day tile subtitle (marks prepended before the free-note
// preview, rendered when either source is present) and the cycle tab's day
// sheet bottom note row (marks text above the full raw note).
//
// The diary tiles run over the pinned-clock DiaryHarness (German locale,
// labels are user data); the day sheet over the write-through cycle-list
// harness.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/cycle_list_harness.dart';
import 'support/diary_harness.dart';

// --- the diary list tile ---------------------------------------------------

final _now = DateTime(2026, 5, 10, 9);
final _harness = DiaryHarness(now: _now);
final _firstDay = DateTime(2026, 5, 1);

// The one ListTile whose title shows [day]'s formatted date label.
Finder _tileOf(DateTime day) => find
    .ancestor(
      of: find.text(DateFormat.yMd('de').format(DateOnly.normalize(day))),
      matching: find.byType(ListTile),
    )
    .first;

String? _tileSubtitle(WidgetTester tester, DateTime day) =>
    tester.widget<ListTile>(_tileOf(day)).subtitle is Text
    ? (tester.widget<ListTile>(_tileOf(day)).subtitle! as Text).data
    : null;

void main() {
  group('diary list tile subtitle', () {
    testWidgets('a custom-marks day with no free note renders the marks '
        'subtitle', (tester) async {
      final day = _firstDay;
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.marksDao.addMark(day, CycleMarkTypes.cycleStart);
            await db.entriesDao.upsertDaily(
              DailyEntry(
                date: day,
                customMarks: const {
                  'Sport': ['Joggen', 'Kraft'],
                },
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      expect(
        _tileSubtitle(tester, day),
        'Sport: Joggen, Kraft',
        reason: 'the marks line alone renders the subtitle',
      );
    });

    testWidgets('a day with custom marks and a free note renders the marks '
        'text before the note preview', (tester) async {
      final day = _firstDay;
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.marksDao.addMark(day, CycleMarkTypes.cycleStart);
            await db.entriesDao.upsertDaily(
              DailyEntry(
                date: day,
                customMarks: const {
                  'Sport': ['Joggen'],
                  'Urlaub': <String>[],
                },
                notes: 'Zahnarzt telefonieren',
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      final subtitle = _tileSubtitle(tester, day);
      expect(
        subtitle,
        'Sport: Joggen · Urlaub · Zahnarzt telefonieren',
        reason: 'the marks text precedes the note preview on one line',
      );
    });

    testWidgets('a day without marks and without a note renders no subtitle', (
      tester,
    ) async {
      final day = _firstDay;
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.marksDao.addMark(day, CycleMarkTypes.cycleStart);
            await db.entriesDao.upsertDaily(DailyEntry(date: day));
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      expect(_tileSubtitle(tester, day), isNull);
    });
  });

  group('cycle day sheet note row', () {
    testWidgets('a custom-marks day with no free note shows the marks line', (
      tester,
    ) async {
      final entries = [
        DailyEntry(
          date: scenarioDay(1),
          bbtC: 36.4,
          customMarks: const {
            'Sport': ['Joggen', 'Kraft'],
          },
        ),
      ];
      await pumpCycleList(tester, entries: entries);
      await tapCycleDay(tester, 0);

      final noteRow = find.byKey(const ValueKey('cycleSheetNote'));
      expect(noteRow, findsOneWidget, reason: "the day's note row renders");
      expect(
        tester.widget<Text>(noteRow).data,
        'Sport: Joggen, Kraft',
        reason: 'the marks line alone renders in the panel',
      );
    });

    testWidgets('a day with custom marks and a free note shows the marks text '
        'above the full raw note', (tester) async {
      final note = 'Notiz zweite Zeile\nNotiz erste Zeile';
      final entries = [
        DailyEntry(
          date: scenarioDay(1),
          bbtC: 36.5,
          customMarks: const {
            'Sport': ['Joggen'],
            'Urlaub': <String>[],
          },
          notes: note,
        ),
      ];
      await pumpCycleList(tester, entries: entries);
      await tapCycleDay(tester, 0);

      final noteRow = find.byKey(const ValueKey('cycleSheetNote'));
      expect(
        tester.widget<Text>(noteRow).data,
        'Sport: Joggen · Urlaub\n$note',
        reason: 'the marks text renders with the raw note, line breaks intact',
      );
    });
  });
}
