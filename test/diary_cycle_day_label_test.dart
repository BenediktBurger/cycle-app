// Widget test of the diary's day-of-cycle labels: every day tile of the
// cycle-grouped list shows its position inside the containing cycle
// ("Zyklustag N" for the pinned German locale), and the entry form's date
// row repeats the same label for the selected day — computed over the SAME
// cycles the list groups with (mark-driven boundaries), so a mark placed on
// an untracked gap day is the number anchor too. The tile's date label is
// the fixture for the tile locators and must remain EXACTLY the plain
// formatted date (other tile tests locate through it).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/diary_harness.dart';
import 'support/error_collector.dart';
import 'support/viewport.dart';

final _now = DateTime(2026, 9, 10);

final _harness = DiaryHarness(now: _now);

// Two-cycle fixture, mirroring the bleeding-marker test's shape: an early
// leading pre-mark group (Aug 30–31), then a cycleStart mark on the
// UNTRACKED gap day Sep 2 with the first tracked day Sep 3.
final _leadingFirst = DateTime(2026, 8, 30);
final _leadingSecond = DateTime(2026, 8, 31);
final _gappedMark = DateTime(2026, 9, 2);
final _openedFirst = DateTime(2026, 9, 3);
final _openedSecond = DateTime(2026, 9, 4);

Future<void> _seedTwoCycles(CycleDatabase db) async {
  Future<void> entry(DateTime day) =>
      db.entriesDao.upsertDaily(DailyEntry(date: DateOnly.normalize(day)));
  await entry(_leadingFirst);
  await entry(_leadingSecond);
  await entry(_openedFirst);
  await entry(_openedSecond);
  await db.marksDao.addMark(_gappedMark, CycleMarkTypes.cycleStart);
}

// Normalized verbatim (no host-timezone shifting): the screen formats the
// UTC-midnight dates directly.
String _tileDate(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day));

/// The one ListTile whose title shows [day]'s exact date label.
Finder _tileOf(DateTime day) => find
    .ancestor(of: find.text(_tileDate(day)), matching: find.byType(ListTile))
    .first;

/// Expands both cycle groups so the day tiles are built.
Future<void> _expandAllGroups(WidgetTester tester) async {
  await tester.tap(find.byType(ExpansionTile).first);
  await tester.pumpAndSettle();
  // The newest cycle sits at the top; after expanding the first, the
  // leading group is the remaining collapsed tile.
  await tester.tap(find.byType(ExpansionTile).last);
  await tester.pumpAndSettle();
}

String _cycleDayLabel(int cycleDay) => 'Zyklustag $cycleDay';

void main() {
  testWidgets('every day tile shows its day-of-cycle label and keeps the plain '
      'date label', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(seed: (db) async => _seedTwoCycles(db)),
    );
    await tester.pumpAndSettle();
    await _expandAllGroups(tester);

    // Leading pre-mark group: numbering anchors on its first tracked day.
    void expectTile(DateTime day, int cycleDay) => expect(
      find.descendant(
        of: _tileOf(day),
        matching: find.text(_cycleDayLabel(cycleDay)),
      ),
      findsOneWidget,
      reason:
          'the tile for ${_tileDate(day)} shows $_cycleDayLabel($cycleDay) '
          'directly inside its own ListTile',
    );
    expectTile(_leadingFirst, 1);
    expectTile(_leadingSecond, 2);

    // Mark-opened cycle: the mark sits on the untracked gap Sep 2, so the
    // first tracked day is already cycle day 2.
    expectTile(_openedFirst, 2);
    expectTile(_openedSecond, 3);
  });

  testWidgets('the form date row shows the selected day as a cycle day', (
    tester,
  ) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async => _seedTwoCycles(db),
        selectedDay: _openedFirst,
      ),
    );
    await tester.pumpAndSettle();

    // The label lives inside the form (the collapsed list shows nothing).
    expect(
      find.descendant(
        of: find.byType(Form),
        matching: find.text(_cycleDayLabel(2)),
      ),
      findsOneWidget,
      reason: 'the first tracked day after the gap mark numbers from the mark',
    );
  });

  testWidgets(
    'a day before the first cycle start shows no cycle-day label anywhere',
    (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async => _seedTwoCycles(db),
          selectedDay: DateTime(2026, 8, 29),
        ),
      );
      await tester.pumpAndSettle();

      // Default find.text is exact-match, so pin the ABSENCE with a prefix
      // matcher: no tile anywhere renders any "Zyklustag N" label.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('Zyklustag'),
        ),
        findsNothing,
      );
      expect(find.text(_cycleDayLabel(1)), findsNothing);
      expect(find.text(_cycleDayLabel(2)), findsNothing);
      expect(find.text(_cycleDayLabel(3)), findsNothing);
    },
  );

  testWidgets('the line below the date navigation row stays overflow-free at a '
      'narrow viewport', (tester) async {
    useNarrowPhoneViewport(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async => _seedTwoCycles(db),
        selectedDay: _openedFirst,
      ),
    );
    await tester.pumpAndSettle();

    // Waive the pump-time record: the date navigation row itself is the
    // documented, still-open narrow-width overflow case (see the
    // narrow-viewport test in the diary navigation tests). Everything
    // from here on is the NEW label line and must stay silent.
    tester.takeException();

    await expectNoFrameworkErrors(
      tester,
      () async {
        expect(
          find.descendant(
            of: find.byType(Form),
            matching: find.text(_cycleDayLabel(2)),
          ),
          findsOneWidget,
          reason:
              'the narrow-width form still shows the selected day as '
              'a cycle day',
        );
      },
      reason:
          'the cycle-day label line must not introduce a new '
          'RenderFlex overflow at narrow widths',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty database shows no cycle-day label', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope());
    await tester.pumpAndSettle();

    // Same prefix-based absence pin as above: an empty database renders
    // no "Zyklustag N" label anywhere.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Zyklustag'),
      ),
      findsNothing,
    );
    expect(find.text(_cycleDayLabel(1)), findsNothing);
    expect(find.text(_cycleDayLabel(2)), findsNothing);
    expect(find.text(_cycleDayLabel(3)), findsNothing);
  });
}
