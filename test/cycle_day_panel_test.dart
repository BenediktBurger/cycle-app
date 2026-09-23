// Widget tests of the non-modal day options panel on the cycle tab (the
// converted former modal bottom sheet): tapping a chart day shows the
// day's options in a panel below the chart, tapping ANOTHER day retargets
// the panel without dismissing it (and without touching the marks), the
// close button clears it, and the mark chips write through the real
// MarksDao exactly like the former sheet did.
//
// Harness: both files share support/cycle_list_harness.dart (the real
// MarksDao against an in-memory database, so every write surfaces in the
// stream that re-renders the panel and the chart, plus the scenario
// constants and the day taps).
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cycle_list_harness.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

void main() {
  testWidgets('tapping a chart day shows the day options in a NON-MODAL panel '
      'below the chart', (tester) async {
    // A taller surface: the chart block plus the open panel should both
    // be laid out visibly here (the Zyklus list is lazy; at the default
    // test viewport the panel below the chart would sit below the fold
    // and never build).
    useTallSurface(tester, height: 2000);
    final (_, _) = await pumpCycleList(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 4); // 9/10, a numbered low (4)

    // The panel is the form-jump + mark-toggle surface, keyed for the tests.
    final panel = find.byKey(const ValueKey('cycleDayPanel'));
    expect(
      panel,
      findsOneWidget,
      reason: 'the day tap shows the day options panel',
    );
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'the panel is NOT a modal route — the chart stays reachable',
    );
    expect(
      find.byKey(const ValueKey('cycleDayPanelEdit')),
      findsOneWidget,
      reason: 'the form jump stays reachable via "edit day"',
    );
    expect(
      find.text('Low measurement 4'),
      findsOneWidget,
      reason: "A's options carry the day's computed info line",
    );
    // Non-modal: the chart below stays laid out (the panel renders in the
    // owning list's flow, not as an overlay), and the evaluation summary
    // table that used to sit under the chart is gone.
    expect(find.byKey(const ValueKey('cycleSummaryScroll')), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets(
    'tapping another day retargets the panel — A stays marked, B takes '
    'over the options',
    (tester) async {
      final (db, _) = await pumpCycleList(
        tester,
        entries: scenarioEntries,
        seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
      );

      await tapCycleDay(tester, 4); // 9/10: "A"
      expect(find.text('Low measurement 4'), findsOneWidget);

      await tapCycleDay(tester, 8); // 9/14: first-higher day, circled #1
      expect(
        find.text('+0.50 K above the baseline'),
        findsOneWidget,
        reason: 'the panel retargets to B and shows B\'s computed line',
      );
      expect(
        find.text('Low measurement 4'),
        findsNothing,
        reason: 'A\'s info line is gone from the retargeted panel',
      );

      // Retargeting must not touch A's data: the seeded marks are unchanged.
      expect(await storedMarkTypes(db, scenarioDay(12)), [
        'mucusPeakDay',
      ], reason: 'A-adjacent seeded marks are untouched');
      expect(await storedMarkTypes(db, scenarioDay(14)), [
        'firstHigherMeasurement',
      ], reason: 'B\'s own seeded mark is untouched');
      expect(
        dotPainterOrNull(tester, 8),
        isA<RingDotPainter>(),
        reason:
            'the chart overlay is unchanged by the retarget (9/14 is '
            'the circled first-higher candidate)',
      );
    },
  );

  testWidgets('the close button clears the panel', (tester) async {
    await pumpCycleList(tester, entries: scenarioEntries);

    await tapCycleDay(tester, 4);
    expect(find.byKey(const ValueKey('cycleDayPanel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cycleDayPanelClose')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cycleDayPanel')),
      findsNothing,
      reason: 'the close button dismisses the panel',
    );
    expect(find.byKey(const ValueKey('cycleDayPanelEdit')), findsNothing);
  });

  testWidgets('a mark chip inside the panel writes through the MarksDao — the '
      'first tap places the mark, the second removes it', (tester) async {
    // The toggle rows live in the Zyklus list and can sit below the fold —
    // a tall surface lays the whole panel out at once.
    useTallSurface(tester);
    final (db, _) = await pumpCycleList(
      tester,
      entries: scenarioEntries,
    ); // no marks yet

    await tapCycleDay(tester, 6); // 9/12, the day to mark
    final chip = find.descendant(
      of: find.byKey(const ValueKey('cycleDayPanel')),
      matching: find.text('Mucus peak'),
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      contains('mucusPeakDay'),
      reason: 'the mark is persisted through marksDao',
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      isEmpty,
      reason: 'the second tap on the selected chip removes the mark',
    );

    // R6: placing the peak renders the solid dot in the symbol row.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      contains('mucusPeakDay'),
    );
    expect(
      find.byKey(const ValueKey('peakDot-6')),
      findsOneWidget,
      reason:
          'the chart overlay re-renders from the marks stream '
          'while the panel stays open',
    );
  });

  testWidgets(
    'adding a mark on a SECOND day does not lose the FIRST day\'s marks '
    '(the "tap another day without deselecting" scenario)',
    (tester) async {
      useTallSurface(tester);
      final (db, _) = await pumpCycleList(tester, entries: scenarioEntries);

      // Mark 9/12 with the mucus peak.
      await tapCycleDay(tester, 6);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('cycleDayPanel')),
          matching: find.text('Mucus peak'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await storedMarkTypes(db, scenarioDay(12)), ['mucusPeakDay']);

      // Without closing anything, mark 9/13 with the first higher mark. The
      // placement is INCONSISTENT there (36.30 below the baseline 36.40), so
      // the owner warning pops — Keep keeps the just-placed mark.
      await tapCycleDay(tester, 7);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('cycleDayPanel')),
          matching: find.text('First higher measurement'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Keep'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        await storedMarkTypes(db, scenarioDay(12)),
        ['mucusPeakDay'],
        reason:
            'the first day\'s mark survives — the panel retarget, not a '
            'modal dismissal, moves the options',
      );
      expect(await storedMarkTypes(db, scenarioDay(13)), [
        'firstHigherMeasurement',
      ], reason: 'the second mark is written through the same panel');
    },
  );
}
