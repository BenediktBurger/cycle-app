// Widget tests of the non-modal day options panel on the cycle tab (the
// converted former modal bottom sheet): tapping a chart day shows the
// day's options in a panel docked at the bottom of the screen, tapping
// ANOTHER day retargets the panel without dismissing it (and without
// touching the marks), the close button clears it, and the mark chips
// write through the real MarksDao exactly like the former sheet did.
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

void main() {
  testWidgets('tapping a chart day shows the day options in a NON-MODAL panel '
      'docked at the bottom of the screen', (tester) async {
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
      cycleDayPanelEditButton(),
      findsOneWidget,
      reason: 'the form jump stays reachable via "edit day"',
    );
    expect(
      find.text('Low measurement 4'),
      findsOneWidget,
      reason: "A's options carry the day's computed info line",
    );
    // Non-modal: the chart still fills the screen under the docked panel
    // (an overlaying dock, never a modal route), and the evaluation summary
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
    expect(cycleDayPanelEditButton(), findsNothing);
  });

  testWidgets('a mark chip inside the panel writes through the MarksDao — the '
      'first tap places the mark, the second removes it', (tester) async {
    final (db, _) = await pumpCycleList(
      tester,
      entries: scenarioEntries,
    ); // no marks yet

    await tapCycleDay(tester, 6); // 9/12, the day to mark
    final chip = cycleSheetChip('mucusPeakDay');
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

    // R6: placing the peak renders the solid in-plot dot.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      contains('mucusPeakDay'),
    );
    expect(
      find.byKey(const ValueKey('inPlotPeakDot-6')),
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
      final (db, _) = await pumpCycleList(tester, entries: scenarioEntries);

      // Mark 9/12 with the mucus peak.
      await tapCycleDay(tester, 6);
      await tester.tap(cycleSheetChip('mucusPeakDay'));
      await tester.pumpAndSettle();
      expect(await storedMarkTypes(db, scenarioDay(12)), ['mucusPeakDay']);

      // Without closing anything, mark 9/13 with the first higher mark. The
      // placement is INCONSISTENT there (36.30 below the baseline 36.40), so
      // the owner warning pops — Keep keeps the just-placed mark.
      await tapCycleDay(tester, 7);
      await tester.tap(cycleSheetChip('firstHigherMeasurement'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(cycleSheetRiseKeepButton());
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

  testWidgets('tapping a chart day never scrolls the list — the docked panel '
      'renders fully visible at the bottom', (tester) async {
    await pumpCycleList(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    final tappedCell = find.byKey(const ValueKey('bleedingCell-4'));
    final cellBefore = tester.getRect(tappedCell);

    await tapCycleDay(tester, 4); // 9/10, a numbered low (4)

    expect(cycleDayPanel(), findsOneWidget);
    final panelRect = tester.getRect(cycleDayPanel());
    expect(
      panelRect.top,
      greaterThanOrEqualTo(0),
      reason: 'the docked panel is fully on screen',
    );
    expect(
      panelRect.bottom,
      lessThanOrEqualTo(600),
      reason: 'the docked panel is fully on screen above the bottom edge',
    );
    expect(
      tester.getRect(tappedCell),
      cellBefore,
      reason: 'the day tap opens the dock without moving the chart rows',
    );
  });

  testWidgets(
    'retargeting an open panel does not scroll the list — the dock updates '
    'its content in place (no-jump regression guard)',
    (tester) async {
      await pumpCycleList(
        tester,
        entries: scenarioEntries,
        seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
      );

      final tappedCell = find.byKey(const ValueKey('bleedingCell-8'));

      await tapCycleDay(tester, 6); // 9/12: opens the panel
      expect(cycleDayPanel(), findsOneWidget);
      final cellBefore = tester.getRect(tappedCell);

      await tapCycleDay(tester, 8); // 9/14: retarget, panel stays open
      expect(
        tester.getRect(tappedCell),
        cellBefore,
        reason: 'the retarget updates the dock in place — never a jump',
      );
      expect(
        find.text('+0.50 K above the baseline'),
        findsOneWidget,
        reason: 'the retargeted dock shows the new day\'s computed line',
      );
    },
  );

  testWidgets('retargeting to another day opens the panel scrolled to the '
      'top — day B never inherits day A\'s scroll offset', (tester) async {
    final noteA = List.generate(40, (i) => 'A note line $i').join('\n');
    final noteB = List.generate(40, (i) => 'B note line $i').join('\n');
    final entries = [...scenarioEntries];
    entries[4] = entries[4].copyWith(notes: noteA);
    entries[8] = entries[8].copyWith(notes: noteB);
    await pumpCycleList(tester, entries: entries);

    await tapCycleDay(tester, 4); // 9/10, the noted day
    final panelScrollable = find.descendant(
      of: cycleDayPanel(),
      matching: find.byType(Scrollable),
    );
    expect(panelScrollable, findsOneWidget);
    // Scroll from the chip grid: a visible element inside the capped
    // viewport (the note's center sits below it, where the drag would
    // fall through to the chart list behind the panel).
    await tester.drag(cycleSheetChip('cycleStart'), const Offset(0, -250));
    await tester.pumpAndSettle();
    final offsetBefore = tester
        .state<ScrollableState>(panelScrollable)
        .position
        .pixels;
    expect(
      offsetBefore,
      greaterThan(0),
      reason: 'precondition: day A\'s panel content is scrolled down',
    );

    await tapCycleDay(tester, 8); // 9/14: retarget, panel stays open
    final offsetAfter = tester
        .state<ScrollableState>(panelScrollable)
        .position
        .pixels;
    expect(
      offsetAfter,
      0,
      reason: 'the retargeted panel starts at the top of day B\'s content',
    );
  });

  testWidgets('a very long note caps the docked panel — the content scrolls '
      'internally instead of the dock growing', (tester) async {
    final raw = List.generate(40, (i) => 'note line $i').join('\n');
    final entries = [...scenarioEntries];
    entries[4] = entries[4].copyWith(notes: raw);
    await pumpCycleList(tester, entries: entries);

    await tapCycleDay(tester, 4); // 9/10, the noted day

    // Default test surface 600 logical px tall, no system bottom inset:
    // the AppBar's share and the dock's 12 px bottom offset come off the
    // surface before the ~60% factor.
    final cappedHeight = (600 - kToolbarHeight - 12.0) * 0.6;
    expect(
      tester.getRect(cycleDayPanel()).height,
      lessThanOrEqualTo(cappedHeight),
      reason:
          'the dock never exceeds about 60% of the body space above '
          'its bottom offset',
    );
    expect(
      find.descendant(
        of: cycleDayPanel(),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
      reason: 'above the cap the dock content scrolls internally',
    );
    expect(
      find.text(raw),
      findsOneWidget,
      reason: 'the full note stays in the tree inside the capped dock',
    );
  });

  testWidgets('short window: the cap tracks the body constraints, so the '
      'dock never grows into the AppBar', (tester) async {
    // 160 logical px tall: 60% of the FULL surface (96 px) would exceed
    // the body space above the dock's bottom offset
    // (160 - AppBar - 12 = 92 px) and top-clip the dock into the AppBar.
    final dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(800 * dpr, 160 * dpr);
    addTearDown(tester.view.reset);

    final raw = List.generate(40, (i) => 'note line $i').join('\n');
    final entries = [...scenarioEntries];
    entries[4] = entries[4].copyWith(notes: raw);
    await pumpCycleList(tester, entries: entries);

    await tapCycleDay(tester, 4); // 9/10, the noted day

    final panelRect = tester.getRect(cycleDayPanel());
    expect(
      panelRect.height,
      lessThanOrEqualTo((160 - kToolbarHeight - 12.0) * 0.6),
      reason: 'the cap follows the body space above the bottom offset',
    );
    expect(
      panelRect.top,
      greaterThanOrEqualTo(kToolbarHeight),
      reason: 'the dock stays inside the body, below the AppBar',
    );
  });
}
