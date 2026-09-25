// Widget tests of the day options panel on the cycle tab (Mode M, ADR-0001):
// tapping a chart day shows a NON-MODAL panel below the chart with a single
// header row (the day's locale-formatted label, then the compact "edit day"
// icon button, then the close button) and the mark toggles as Material
// FilterChips in ONE shared two-column grid of equal column widths
// (three columns on viewports from 600 dp of grid width) — ALL six chips
// (the five mark chips AND the temperature-exclusion chip, which keeps its
// keyed group cell inside the grid) — each chip carries the STATIC mark-name
// label plus its mark type's identifying leading icon and shows the mark
// state itself (the selected fill, announced as selected to screen readers;
// the canvas-drawn check is off): the mucus peak, the first higher
// measurement, the SUZ
// start, the cycle start (the authoritative cycle boundary — bleeding only
// suggests it) and the temperature exclusion — plus the computed info lines
// (derived artifacts such as the baseline value, the 1-6 low numbering, the
// difference to the baseline for marked candidates and the stopped-evaluation
// notice). Formerly a modal bottom sheet; the fixture/scenarios and all
// write paths are unchanged by the conversion.
//
// Unlike the evaluation section of test/cycle_chart_test.dart (fixed
// marks streams), these tests write through the REAL MarksDao against an
// in-memory database — the panel must persist and the surface (chart
// overlay, chip states, info lines) must re-render from the marks stream
// after every write. The harness body (scope, day taps, stored readback)
// and the scenario constants are shared once with
// test/cycle_day_panel_test.dart in support/cycle_list_harness.dart.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'dart:ui' show Tristate;

import 'support/cycle_list_harness.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

/// A tall-enough test surface for every pump: the Zyklus list is lazy and
/// the panel sits BELOW the chart block, so the default viewport would
/// leave most panel rows unbuilt below the fold. A tall surface lays the
/// chart and the open panel out at once (the modal
/// sheet of the old layout always fit the viewport on its own — the panel
/// replaced that self-scroll with the owning list, see the panel comment).
/// The scenario constants and the write-through harness live once in
/// support/cycle_list_harness.dart.
Future<(CycleDatabase, ProviderContainer)> _pump(
  WidgetTester tester, {
  required List<DailyEntry> entries,
  List<CycleMark> seedMarks = const [],
  DateTime? selectedDate,
  int initialTab = 0,
  CycleDatabase Function()? builder,
  Stream<List<CycleMark>> Function()? marksStreamFactory,
}) async {
  useTallSurface(tester);
  return pumpCycleList(
    tester,
    entries: entries,
    seedMarks: seedMarks,
    selectedDate: selectedDate,
    initialTab: initialTab,
    builder: builder,
    marksStreamFactory: marksStreamFactory,
  );
}

/// Brings a panel row into view: the panel lives in the Zyklus screen's
/// vertical list, and the bottom rows of the chip grid (the SUZ variants)
/// can sit below the viewport fold once the day options carry all content —
/// scrolled into view the same way the modal sheet's rows used to be.
Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 50, scrollable: cycleListScroller());
  await tester.pumpAndSettle();
}

/// [_pump] with the surface width pinned: the chip grid's column count is
/// breakpoint-dependent (three columns from 600 dp of grid width), so the
/// geometry tests pin a narrow or a wide surface first — [_pump] always
/// lays the default wide surface that would collide with the pin.
Future<(CycleDatabase, ProviderContainer)> _pumpAt(
  WidgetTester tester, {
  required double width,
  required List<DailyEntry> entries,
}) async {
  useTallSurface(tester, width: width);
  return pumpCycleList(tester, entries: entries);
}

/// The panel header's day label for a scenario day, computed with the same
/// `DateFormat.yMMMEd` the header uses (English, the harness's pinned
/// locale) instead of being hardcoded — the assertion stays independent of
/// the concrete date formatting.
String dayLabelOf(int day) =>
    DateFormat.yMMMEd('en').format(DateOnly.normalize(scenarioDay(day)));

/// The day header's close button (the explicit panel close affordance).
Finder panelCloseButton() => find.byKey(const ValueKey('cycleDayPanelClose'));

/// Fault injection for the mark writes: the real in-memory database whose
/// mark writes can be armed to fail AFTER the harness was pumped — the
/// test flips the flag at exactly the point the fault should occur (the
/// same seam the save-flow and delete-data tests use).
class _FaultyDatabase extends CycleDatabase {
  _FaultyDatabase(super.executor);

  bool failMarkWrites = false;

  late final _FaultyMarksDao _faultyMarksDao = _FaultyMarksDao(this);

  @override
  MarksDao get marksDao => _faultyMarksDao;
}

class _FaultyMarksDao extends MarksDao {
  _FaultyMarksDao(this._faulty) : super(_faulty);

  final _FaultyDatabase _faulty;

  @override
  Future<UserMark> addMark(
    DateTime date,
    String markType, {
    String author = 'user',
  }) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.addMark(date, markType, author: author);
  }

  @override
  Future<bool> toggleMark(DateTime date, String markType) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.toggleMark(date, markType);
  }

  @override
  Future<int> deleteMark(DateTime date, String markType) {
    if (_faulty.failMarkWrites) {
      throw StateError('injected mark write failure');
    }
    return super.deleteMark(date, markType);
  }
}

_FaultyDatabase _faultyDatabase() {
  return _FaultyDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}

/// The panel's keyed temperature-exclusion group (test-visible key) —
/// used for the chip-icon scoping and the exclusion-group tests.
final excludeGroup = find.byKey(const ValueKey('cycleSheetExcludeGroup'));

/// Whether the chip's merged semantics node carries the selected flag —
/// the accessibility side of the Material selected state. The M3 check
/// mark is canvas-painted (no Icon widget), so the visible state is
/// asserted through the chip's `selected` property and this flag. The
/// chip resolves through the same keyed finder ([cycleSheetChip]) as
/// every other chip addressing in this file.
bool chipSelectedSemantics(WidgetTester tester, String markType) =>
    tester.getSemantics(cycleSheetChip(markType)).flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  testWidgets(
    'tapping a chart day opens the day options panel with the chip grid, '
    'not the form',
    (tester) async {
      final (_, _) = await _pump(
        tester,
        entries: scenarioEntries,
        seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
      );

      await tapCycleDay(tester, 4); // 9/10, a numbered low (4)

      expect(
        cycleDayPanel(),
        findsOneWidget,
        reason: 'the day tap shows the non-modal day options panel',
      );
      expect(
        cycleDayPanelEditButton(),
        findsOneWidget,
        reason: 'the form jump stays reachable via "edit day"',
      );
      expect(
        cycleSheetChip('mucusPeakDay'),
        findsOneWidget,
        reason: 'the day carries no peak mark -> the unselected chip',
      );
      expect(
        cycleSheetChip('firstHigherMeasurement'),
        findsOneWidget,
        reason: 'the day carries no first-higher mark -> the unselected chip',
      );
      expect(
        find.text('Low measurement 4'),
        findsOneWidget,
        reason: '9/10 is the 4th low of the six before the first higher',
      );
      expect(
        find.byType(LineChart),
        findsOneWidget,
        reason: 'the surface stays on the cycle tab',
      );
      // No stopped-evaluation notice in an intact evaluation.
      expect(
        find.byKey(const ValueKey('cycleSheetEvaluationStopped')),
        findsNothing,
        reason: 'the evaluation did not stop — no notice',
      );
    },
  );

  testWidgets('the header shows the selected day next to the close button — no '
      'measurement-time line even when one is recorded', (tester) async {
    // The chart's time row spells the recorded time on wide columns itself;
    // the panel header names the DAY and no longer repeats the time.
    final entries = [...scenarioEntries];
    entries[4] = entries[4].copyWith(measuredAtMinutes: 6 * 60 + 30);
    final (_, _) = await _pump(tester, entries: entries);

    await tapCycleDay(tester, 4); // 9/10

    expect(
      find.descendant(of: cycleDayPanel(), matching: find.text(dayLabelOf(10))),
      findsOneWidget,
      reason:
          'the header labels the selected day (yMMMEd, computed by '
          'the test with the same DateFormat the header uses)',
    );
    expect(
      find.textContaining('Measurement time:'),
      findsNothing,
      reason:
          'the measurement-time line is gone from the panel — the '
          'time lives in the chart row and the diary form',
    );
    expect(
      panelCloseButton(),
      findsOneWidget,
      reason: 'the header keeps the explicit close affordance',
    );
  });

  testWidgets('the header day label follows the tapped day', (tester) async {
    final (_, _) = await _pump(tester, entries: scenarioEntries);

    await tapCycleDay(tester, 4); // 9/10
    expect(
      find.descendant(of: cycleDayPanel(), matching: find.text(dayLabelOf(10))),
      findsOneWidget,
    );

    await tapCycleDay(tester, 6); // 9/12: the panel retargets in place
    expect(
      find.descendant(of: cycleDayPanel(), matching: find.text(dayLabelOf(10))),
      findsNothing,
      reason: 'the previous day\'s label is gone',
    );
    expect(
      find.descendant(of: cycleDayPanel(), matching: find.text(dayLabelOf(12))),
      findsOneWidget,
      reason: 'the label changed with the tapped day',
    );
  });

  testWidgets('the info line shows the computed baseline on the baseline day', (
    tester,
  ) async {
    final (_, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 3); // 9/9: highest of the six lows = baseline

    expect(
      find.text('Baseline: 36.40'),
      findsOneWidget,
      reason: 'the derived baseline value is shown on its own day',
    );
    expect(
      find.text('Low measurement 5'),
      findsOneWidget,
      reason: 'the baseline day is also the 5th low (both facts hold)',
    );
  });

  testWidgets('R7: circled days show the difference to the baseline', (
    tester,
  ) async {
    final (_, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 8); // 9/14: circled candidate #1, +0.50 K

    expect(
      find.text('+0.50 K above the baseline'),
      findsOneWidget,
      reason: 'the difference to the baseline is shown for easy checking',
    );
    expect(
      find.text('Circled higher measurement 1'),
      findsOneWidget,
      reason: 'the ordinal of the circled candidate stays visible',
    );
  });

  testWidgets('R7: arrowed days show the difference too — without the '
      'circled ordinal line', (tester) async {
    // Peak unmarked: the candidates become arrows (R4) — the difference
    // display applies to circled AND arrowed days.
    final (_, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 8); // 9/14: arrowed candidate #1, +0.50 K

    expect(
      find.text('+0.50 K above the baseline'),
      findsOneWidget,
      reason: 'arrowed candidates show the difference too (R7)',
    );
    expect(
      find.text('Circled higher measurement 1'),
      findsNothing,
      reason: 'nothing is circled without a peak before the rise',
    );
  });

  testWidgets('a beyond-cap arrow keeps the difference line — it stays a '
      'marked candidate, just unnumbered (R4)', (tester) async {
    // Peak unmarked: every candidate is an arrow; the 5th (9/18) is beyond
    // its kind's four-cap, so it carries no ordinal — but it stays in the
    // connected sequence (R4) and still shows the R7 difference line.
    final entries = [
      ...scenarioEntries,
      DailyEntry(date: scenarioDay(17), bbtC: 36.5),
      DailyEntry(date: scenarioDay(18), bbtC: 36.5),
    ];
    final (_, _) = await _pump(
      tester,
      entries: entries,
      seedMarks: [scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 12); // 9/18: beyond-cap arrow, +0.10 K

    expect(
      find.text('+0.10 K above the baseline'),
      findsOneWidget,
      reason: 'beyond-cap candidates stay marked (R4) and show R7',
    );
    expect(
      find.text('Circled higher measurement 1'),
      findsNothing,
      reason: 'arrow ordinals never surface in the sheet',
    );
  });

  testWidgets('R4 per-kind ordinals: the circle ordinal restarts after the '
      'arrows — the sheet shows the circle number, not the overall count', (
    tester,
  ) async {
    // Peak 9/15 lies between the marked rise (9/14) and the later
    // candidates: 9/14 and the peak day itself are arrows, 9/16 is the
    // FIRST circle — its sheet line counts within the circle kind only.
    final entries = [
      ...scenarioEntries,
      DailyEntry(date: scenarioDay(17), bbtC: 36.5),
    ];
    final (_, _) = await _pump(
      tester,
      entries: entries,
      seedMarks: [
        CycleMark(date: scenarioDay(15), type: CycleMarkTypes.mucusPeakDay),
        scenarioFirstHigherMark,
      ],
    );

    await tapCycleDay(tester, 10); // 9/16: first circle after the arrows

    expect(
      find.text('Circled higher measurement 1'),
      findsOneWidget,
      reason: 'the circle ordinal restarts within its own kind (R4)',
    );
    expect(
      find.text('Circled higher measurement 3'),
      findsNothing,
      reason:
          'the sheet shows the CIRCLE number, not the overall '
          'candidate count',
    );
    expect(
      find.text('+0.60 K above the baseline'),
      findsOneWidget,
      reason: '9/16 is 37.0 — 0.60 K above the baseline 36.4',
    );
  });

  testWidgets('setting a mucus peak persists through the DAO and '
      're-renders the sheet and the chart', (tester) async {
    final (db, _) = await _pump(
      tester,
      entries: scenarioEntries,
    ); // no marks yet

    await tapCycleDay(tester, 6); // 9/12, the day to mark
    await tester.tap(cycleSheetChip('mucusPeakDay'));
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      contains('mucusPeakDay'),
      reason: 'the mark is persisted through marksDao',
    );
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isTrue,
      reason:
          'the chip re-renders selected from the marks stream after '
          'the write',
    );
    // R6: the peak renders as a solid dot in the SYMBOL ROW — not as a
    // ring on the temperature curve.
    expect(
      find.byKey(const ValueKey('peakDot-6')),
      findsOneWidget,
      reason: 'the symbol row re-renders from the marks stream',
    );
    expect(
      dotPainterOrNull(tester, 6),
      isNot(isA<RingDotPainter>()),
      reason: 'the peak day keeps a plain dot on the curve (R6)',
    );
  });

  testWidgets('the mucus-peak chip carries the mark state itself: unselected, '
      'selected after the tap (fill and semantics), unselected again after '
      'removing', (tester) async {
    final (db, _) = await _pump(
      tester,
      entries: scenarioEntries,
    ); // no marks yet
    // The chip's selected state rides its semantics (the announced
    // selection is part of the Material chip state), so the screen-reader
    // side is asserted alongside the widget state.
    final semantics = tester.ensureSemantics();

    await tapCycleDay(tester, 4); // 9/10, an arbitrary day

    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isFalse,
      reason: 'the day carries no peak mark -> the unselected chip',
    );
    expect(
      chipSelectedSemantics(tester, 'mucusPeakDay'),
      isFalse,
      reason: 'the unselected chip is not announced as selected',
    );

    await tester.tap(cycleSheetChip('mucusPeakDay'));
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(db, scenarioDay(10)),
      contains(CycleMarkTypes.mucusPeakDay),
      reason: 'the tap persists the mark through the MarksDao',
    );
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isTrue,
      reason: 'the re-rendered chip is selected (Material selected fill)',
    );
    expect(
      chipSelectedSemantics(tester, 'mucusPeakDay'),
      isTrue,
      reason:
          'the selected chip announces itself (the built-in state '
          'visualization: fill and semantics — the canvas check is off)',
    );
    // The identity icon NEVER disappears with the selection: the selected
    // fill scrim sits ON TOP of the still-present avatar (no canvas-drawn
    // check anymore — the icon carries the identity, the fill the state).
    expect(
      find.descendant(
        of: cycleSheetChip('mucusPeakDay'),
        matching: find.byIcon(Icons.circle),
      ),
      findsOneWidget,
      reason:
          'the selected peak chip still carries its identifying '
          'glyph under the selected fill',
    );

    await tester.tap(cycleSheetChip('mucusPeakDay'));
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(db, scenarioDay(10)),
      isEmpty,
      reason: 'the second tap removes the mark again',
    );
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isFalse,
      reason: 'the chip deselects after the removal',
    );
    semantics.dispose();
  });

  testWidgets('tapping the selected chip again removes the mark', (
    tester,
  ) async {
    final (db, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark],
    );

    await tapCycleDay(tester, 6);
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isTrue,
      reason: 'the day already carries the peak -> the selected chip',
    );
    await tester.tap(cycleSheetChip('mucusPeakDay'));
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      isEmpty,
      reason: 'the mark is removed from storage',
    );
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isFalse,
      reason: 'the chip deselects again',
    );
  });

  testWidgets('both marks on one day are two independent toggles', (
    tester,
  ) async {
    final (db, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark],
    );

    await tapCycleDay(tester, 6);
    // The day already carries the peak; the first-higher mark is addable
    // on the same day (two independent chips).
    await tester.tap(cycleSheetChip('firstHigherMeasurement'));
    await tester.pumpAndSettle();
    expect(
      await storedMarkTypes(db, scenarioDay(12)),
      unorderedEquals(['mucusPeakDay', 'firstHigherMeasurement']),
      reason: 'both marks may live on one day',
    );
    // The placement leaves the mark inconsistent (36.20 on 9/12 lies
    // below the baseline 36.90 of its window 9/6..9/11), so the owner
    // warning pops; Keep keeps the mark so the chips stay independent.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(cycleSheetRiseKeepButton());
    await tester.pumpAndSettle();

    // Removing the second mark keeps the first one untouched. The chip can
    // sit below the panel fold (the shared grid carries all six chips
    // now) — scroll it into view first (same pattern as the SUZ chips).
    await scrollSheetTo(tester, cycleSheetChip('firstHigherMeasurement'));
    await tester.tap(cycleSheetChip('firstHigherMeasurement'));
    await tester.pumpAndSettle();
    expect(await storedMarkTypes(db, scenarioDay(12)), [
      'mucusPeakDay',
    ], reason: 'the two toggles are independent');
    expect(
      tester.widget<FilterChip>(cycleSheetChip('mucusPeakDay')).selected,
      isTrue,
      reason: 'the peak chip is unaffected',
    );
    expect(
      tester
          .widget<FilterChip>(cycleSheetChip('firstHigherMeasurement'))
          .selected,
      isFalse,
      reason: 'the first-higher chip deselected after the removal',
    );
  });

  testWidgets('"edit day" writes the selected date + Tagebuch tab and closes '
      'the sheet', (tester) async {
    final (_, container) = await _pump(
      tester,
      entries: scenarioEntries,
      selectedDate: scenarioDay(1),
      initialTab: 2, // a non-Tagebuch tab, so the write is observable
    );

    await tapCycleDay(tester, 4); // 9/10
    await tester.tap(cycleDayPanelEditButton());
    await tester.pumpAndSettle();

    expect(
      container.read(selectedDateProvider),
      scenarioDay(10),
      reason: 'the tapped day is pre-selected in the entry form',
    );
    expect(
      container.read(tabIndexProvider),
      0,
      reason: 'the shell switches to the Tagebuch tab',
    );
    expect(
      cycleDayPanelEditButton(),
      findsNothing,
      reason: 'the sheet closes after the navigation',
    );
  });

  testWidgets('a symbol-row cell opens the same sheet', (tester) async {
    final (_, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    // warnIfMissed: false — the tap point may fall on the cell's fixed-height
    // sign slot, which does not absorb hits itself; the enclosing InkWell's
    // pointer listener still receives it (same as the marks-row taps above).
    await tester.tap(
      find.byKey(const ValueKey('bleedingCell-2')),
      warnIfMissed: false,
    ); // 9/8
    await tester.pumpAndSettle();

    expect(cycleDayPanelEditButton(), findsOneWidget);
    expect(
      find.text('Low measurement 6'),
      findsOneWidget,
      reason: '9/8 is the 6th (outermost) low',
    );
  });

  testWidgets('a broken sequence shows the stopped-evaluation notice '
      '(R2: the user re-marks the rise)', (tester) async {
    // Candidate 1 on 9/14, then TWO untracked days (9/15, 9/16), then 9/17
    // above the baseline: the automatic evaluation stops (R2).
    final entries = <DailyEntry>[
      DailyEntry(date: scenarioDay(6), bbtC: 36.2),
      DailyEntry(date: scenarioDay(7), bbtC: 36.1),
      DailyEntry(date: scenarioDay(8), bbtC: 36.4),
      DailyEntry(date: scenarioDay(9), bbtC: 36.3),
      DailyEntry(date: scenarioDay(10), bbtC: 36.2),
      DailyEntry(date: scenarioDay(11), bbtC: 36.3),
      DailyEntry(date: scenarioDay(12), bbtC: 36.1), // peak day
      DailyEntry(date: scenarioDay(13), bbtC: 36.3),
      DailyEntry(
        date: scenarioDay(14),
        bbtC: 36.8,
      ), // marked rise -> candidate 1
      // 9/15 + 9/16 untracked -> two gap days -> break.
      DailyEntry(
        date: scenarioDay(17),
        bbtC: 36.9,
      ), // would-be candidate, NOT marked
    ];
    final (_, _) = await _pump(
      tester,
      entries: entries,
      seedMarks: [
        CycleMark(date: scenarioDay(12), type: CycleMarkTypes.mucusPeakDay),
        scenarioFirstHigherMark,
      ],
    );

    await tapCycleDay(tester, 11); // 9/17: the day after the break

    expect(
      find.byKey(const ValueKey('cycleSheetEvaluationStopped')),
      findsOneWidget,
      reason: 'the broken sequence surfaces the stopped state (R2)',
    );
  });

  testWidgets('a day outside any evaluation data shows no info line', (
    tester,
  ) async {
    final (_, _) = await _pump(
      tester,
      entries: scenarioEntries,
      seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
    );

    await tapCycleDay(tester, 0); // 9/6: before the six-low window

    expect(cycleDayPanelEditButton(), findsOneWidget);
    expect(
      find.byType(Text),
      findsWidgets,
    ); // the sheet itself renders — see the harness
    for (final info in [
      'Baseline: 36.40',
      'Low measurement 1',
      'Low measurement 2',
      'Low measurement 3',
      'Low measurement 4',
      'Low measurement 5',
      'Low measurement 6',
      '+0.50 K above the baseline',
      'Circled higher measurement 1',
    ]) {
      expect(
        find.text(info),
        findsNothing,
        reason: 'no derived artifact exists for this day',
      );
    }
    expect(
      find.byKey(const ValueKey('cycleSheetEvaluationStopped')),
      findsNothing,
      reason: 'the evaluation did not stop — no notice',
    );
  });

  group('cycleStart toggle (the authoritative cycle-boundary mark)', () {
    testWidgets(
      'setting the cycle start persists a user-authored cycleStart mark '
      'and selects the chip with its state',
      (tester) async {
        final (db, _) = await _pump(
          tester,
          entries: scenarioEntries,
        ); // no marks yet
        final semantics = tester.ensureSemantics();

        await tapCycleDay(tester, 4); // 9/10, an arbitrary day
        await tester.tap(cycleSheetChip('cycleStart'));
        await tester.pumpAndSettle();

        final stored = await db.marksDao.marksForDay(scenarioDay(10));
        expect(
          stored.map((m) => m.markType),
          contains(CycleMarkTypes.cycleStart),
          reason:
              'the cycle start is persisted through the MarksDao '
              '(the user places the mark — bleeding only suggests)',
        );
        final mark = stored.singleWhere(
          (m) => m.markType == CycleMarkTypes.cycleStart,
        );
        expect(
          mark.author,
          'user',
          reason: 'the chip placement is user-authored',
        );
        expect(
          tester.widget<FilterChip>(cycleSheetChip('cycleStart')).selected,
          isTrue,
          reason: 'the chip re-renders selected after the write',
        );
        expect(
          chipSelectedSemantics(tester, 'cycleStart'),
          isTrue,
          reason:
              'the selected state carries fill and the announced '
              'selection',
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'a present cycle start renders the selected chip and the removal '
      'tap deselects it and deletes the mark',
      (tester) async {
        final (db, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [
            CycleMark(date: scenarioDay(10), type: CycleMarkTypes.cycleStart),
          ],
        );
        final semantics = tester.ensureSemantics();

        await tapCycleDay(tester, 4); // 9/10: the marked day
        expect(
          tester.widget<FilterChip>(cycleSheetChip('cycleStart')).selected,
          isTrue,
          reason: 'the day already carries the mark -> the selected chip',
        );
        expect(chipSelectedSemantics(tester, 'cycleStart'), isTrue);

        await tester.tap(cycleSheetChip('cycleStart'));
        await tester.pumpAndSettle();

        expect(
          await storedMarkTypes(db, scenarioDay(10)),
          isEmpty,
          reason: 'the cycle start is removed from storage',
        );
        expect(
          tester.widget<FilterChip>(cycleSheetChip('cycleStart')).selected,
          isFalse,
          reason: 'the chip deselects again',
        );
        expect(
          chipSelectedSemantics(tester, 'cycleStart'),
          isFalse,
          reason: 'the deselected chip is no longer announced as selected',
        );
        semantics.dispose();
      },
    );
  });

  group('panel layout (the header row and the shared chip grid)', () {
    testWidgets(
      'the header row carries the day title, the edit-day affordance and '
      'the close button — "edit day" sits between the title and the close, '
      'and no full-width action precedes the grid',
      (tester) async {
        // A narrow surface pins the grid to its phone-width two columns (the
        // breakpoint is 600 dp of grid width — see the wide-viewport test).
        final (_, _) = await _pumpAt(
          tester,
          width: 500,
          entries: scenarioEntries,
        );
        await tapCycleDay(tester, 4); // 9/10, an arbitrary day

        final titleTop = tester.getCenter(find.text(dayLabelOf(10))).dy;
        final editTop = tester.getCenter(cycleDayPanelEditButton()).dy;
        final closeTop = tester.getCenter(panelCloseButton()).dy;

        // One header row: the title, the edit affordance and the close
        // button all sit on the same line (row CENTERS — the icon
        // buttons' 48 dp tap targets center the label text)...
        expect(
          (titleTop - editTop).abs(),
          lessThan(4),
          reason: 'the day title shares the header row with "edit day"',
        );
        expect(
          (editTop - closeTop).abs(),
          lessThan(4),
          reason: '"edit day" shares the header row with the close button',
        );
        // ...reading left to right: title, edit, close. (The title's Text
        // box fills the expanded header space — the ordering is asserted
        // by the left edges.)
        final titleRect = tester.getRect(find.text(dayLabelOf(10)));
        final editRect = tester.getRect(cycleDayPanelEditButton());
        final closeRect = tester.getRect(panelCloseButton());
        expect(
          titleRect.left,
          lessThan(editRect.left),
          reason: 'the day title reads left of the edit affordance',
        );
        expect(
          editRect.left,
          lessThan(closeRect.left),
          reason:
              '"edit day" sits between the title and the close button '
              '(the icon buttons\' tap targets touch in the row)',
        );
        // The former full-width "edit day" action above the chips is gone —
        // the compact header icon button replaces it.
        expect(
          find.descendant(
            of: cycleDayPanel(),
            matching: find.byType(FilledButton),
          ),
          findsNothing,
          reason:
              '"edit day" is the compact header icon button — no '
              'full-width action above the grid anymore',
        );
      },
    );

    testWidgets(
      'all six chips — the five mark chips AND the exclusion chip — share '
      'ONE equal-width grid in the reading order cycle start, mucus peak, '
      'exclusion, first higher, SUZ evening, SUZ morning: on a narrow '
      'surface the last row completes evenly with the SUZ variants and '
      'the exclusion sits directly before first higher',
      (tester) async {
        final (_, _) = await _pumpAt(
          tester,
          width: 500,
          entries: scenarioEntries,
        );
        await tapCycleDay(tester, 4); // 9/10, an arbitrary day

        Rect chipRect(String markType) =>
            tester.getRect(cycleSheetChip(markType));
        final cycleStart = chipRect('cycleStart');
        final peak = chipRect('mucusPeakDay');
        final firstHigher = chipRect('firstHigherMeasurement');
        final suzEvening = chipRect('suzEvening');
        final suzMorn = chipRect('suzMorning');
        final ignore = chipRect('ignoreTemperature');

        // The grid rows (two columns): cycle start + mucus peak, exclusion
        // + first higher (the exclusion sits directly BEFORE first
        // higher, per the evaluation-based reading order), then the SUZ
        // variants.
        expect(
          (cycleStart.top - peak.top).abs(),
          lessThan(4),
          reason: 'the first grid row carries the first two chips',
        );
        expect(
          (firstHigher.top - ignore.top).abs(),
          lessThan(4),
          reason:
              'the second grid row carries the exclusion chip (left) '
              'and first higher (right) — the exclusion sits directly '
              'before the first-higher chip',
        );
        expect(
          (suzEvening.top - suzMorn.top).abs(),
          lessThan(4),
          reason: 'the last row completes evenly with the SUZ variants',
        );
        expect(
          suzEvening.left,
          closeTo(cycleStart.left, 4),
          reason: 'the third row restarts in the first column',
        );
        expect(
          ignore.left,
          closeTo(cycleStart.left, 4),
          reason:
              'the exclusion chip opens the second row (first column) '
              'like every other chip — the keyed exclusion group '
              'SURVIVES on the chip cell inside the grid)',
        );
        expect(
          firstHigher.left,
          closeTo(peak.left, 4),
          reason: 'the first-higher chip occupies the second column',
        );
        expect(
          suzMorn.left,
          closeTo(peak.left, 4),
          reason: 'the SUZ morning chip occupies the second column',
        );
        expect(
          suzMorn.top,
          greaterThan(firstHigher.bottom),
          reason:
              'the SUZ variants wrap BELOW the exclusion/first-higher '
              'row',
        );
        expect(
          excludeGroup,
          findsOneWidget,
          reason: 'narrow surface: the exclusion group renders inside the grid',
        );
        // Every chip shares the same column width — the grid distributes
        // all six chips evenly.
        final columnWidth = cycleStart.width;
        for (final (name, rect) in [
          ('mucus peak', peak),
          ('first higher measurement', firstHigher),
          ('SUZ evening', suzEvening),
          ('SUZ morning', suzMorn),
          ('temperature exclusion', ignore),
        ]) {
          expect(
            rect.width,
            closeTo(columnWidth, 1),
            reason: 'the $name chip shares the grid column width',
          );
        }
      },
    );

    testWidgets(
      'on a wide viewport (grid width >= 600 dp) the shared grid lays out '
      'THREE per row and BOTH rows complete evenly (3+3 — the exclusion '
      'chip closes the first row directly after the mucus peak)',
      (tester) async {
        final (_, _) = await _pumpAt(
          tester,
          width: 1000,
          entries: scenarioEntries,
        );
        await tapCycleDay(tester, 4); // 9/10, an arbitrary day

        Rect chipRect(String markType) =>
            tester.getRect(cycleSheetChip(markType));
        final cycleStart = chipRect('cycleStart');
        final peak = chipRect('mucusPeakDay');
        final firstHigher = chipRect('firstHigherMeasurement');
        final suzEvening = chipRect('suzEvening');
        final suzMorn = chipRect('suzMorning');
        final ignore = chipRect('ignoreTemperature');

        expect(
          (cycleStart.top - peak.top).abs(),
          lessThan(4),
          reason: 'the first wide row carries the first three chips',
        );
        expect(
          (cycleStart.top - ignore.top).abs(),
          lessThan(4),
          reason:
              'the exclusion chip joins the FIRST wide row — it sits '
              'directly after the mucus-peak chip in the reading order',
        );
        expect(
          firstHigher.top,
          greaterThan(ignore.bottom),
          reason:
              'the first-higher chip starts the SECOND row — the '
              'exclusion sits directly before it on the first row',
        );
        expect(
          (suzEvening.top - firstHigher.top).abs(),
          lessThan(4),
          reason:
              'the second wide row continues with first higher and the '
              'SUZ variants',
        );
        expect((suzEvening.top - suzMorn.top).abs(), lessThan(4));
        // The distribution stays even on wide surfaces (3+3, no lone
        // chip).
        expect(
          suzEvening.left,
          closeTo(peak.left, 4),
          reason: 'the SUZ evening chip is the second row\'s second column',
        );
        expect(
          suzMorn.left,
          closeTo(ignore.left, 4),
          reason: 'the SUZ morning chip is the second row\'s third column',
        );
        expect(
          ignore.left,
          greaterThan(peak.right),
          reason: 'the exclusion chip is the first row\'s third column',
        );
      },
    );

    testWidgets(
      'each grid chip is about half the grid width: a row fits exactly '
      'two chips',
      (tester) async {
        final (_, _) = await _pumpAt(
          tester,
          width: 500,
          entries: scenarioEntries,
        );
        await tapCycleDay(tester, 4); // 9/10, an arbitrary day

        final cycleStart = tester.getRect(cycleSheetChip('cycleStart'));
        final peak = tester.getRect(cycleSheetChip('mucusPeakDay'));
        final firstHigher = tester.getRect(
          cycleSheetChip('firstHigherMeasurement'),
        );
        expect(
          peak.left - cycleStart.right,
          lessThan(12),
          reason:
              'the two chips touch within the wrap spacing — no room '
              'for a third column',
        );
        expect(
          firstHigher.top,
          greaterThan(cycleStart.bottom),
          reason:
              'each chip spans about half the line — the third mark '
              'wraps to the next row',
        );
      },
    );

    testWidgets(
      'no chip draws the canvas check mark — the selected fill plus the '
      'announced selection carry the mark state (the check overlapped '
      'the avatar icon)',
      (tester) async {
        final (_, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
        );
        await tapCycleDay(tester, 4); // 9/10: peak unmarked, arbitrary day

        final chips = find.descendant(
          of: cycleDayPanel(),
          matching: find.byType(FilterChip),
        );
        expect(
          chips,
          findsNWidgets(6),
          reason: 'five mark chips plus the exclusion chip',
        );
        for (final chip in chips.evaluate()) {
          expect(
            (chip.widget as FilterChip).showCheckmark,
            isFalse,
            reason:
                'every panel chip suppresses the canvas-drawn check on '
                'the selected state',
          );
        }
      },
    );
  });

  group('ignoreTemperature toggle (the temperature-ignore mark)', () {
    testWidgets('tapping the exclusion chip places the ignoreTemperature mark '
        'through the MarksDao on ANY day; tapping again removes it', (
      tester,
    ) async {
      final (db, _) = await _pump(
        tester,
        entries: scenarioEntries,
      ); // no marks yet

      await tapCycleDay(tester, 4); // 9/10, an arbitrary day
      expect(
        cycleSheetChip('ignoreTemperature'),
        findsOneWidget,
        reason: 'the keyed exclusion chip — the chip state carries set/remove',
      );
      await tester.tap(cycleSheetChip('ignoreTemperature'));
      await tester.pumpAndSettle();

      final stored = await db.marksDao.marksForDay(scenarioDay(10));
      expect(
        stored.map((m) => m.markType),
        contains(CycleMarkTypes.ignoreTemperature),
        reason:
            'the toggle writes the mark through marksDao '
            '(day/type-keyed addMark)',
      );
      final mark = stored.singleWhere(
        (m) => m.markType == CycleMarkTypes.ignoreTemperature,
      );
      expect(
        mark.author,
        'user',
        reason: 'the chip placement is user-authored',
      );
      expect(stored, hasLength(1), reason: 'exactly one mark was written');

      await tester.tap(cycleSheetChip('ignoreTemperature'));
      await tester.pumpAndSettle();

      expect(
        await storedMarkTypes(db, scenarioDay(10)),
        isEmpty,
        reason: 'the reverse toggle deletes the mark',
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('ignoreTemperature')).selected,
        isFalse,
        reason: 'the chip deselects — the label never flips wording',
      );
    });

    testWidgets('a present exclusion mark renders the selected chip and the '
        'removal tap deletes it', (tester) async {
      final (db, _) = await _pump(
        tester,
        entries: scenarioEntries,
        seedMarks: [
          CycleMark(
            date: scenarioDay(10),
            type: CycleMarkTypes.ignoreTemperature,
          ),
        ],
      );

      await tapCycleDay(tester, 4); // 9/10: the marked day
      expect(
        tester.widget<FilterChip>(cycleSheetChip('ignoreTemperature')).selected,
        isTrue,
        reason: 'the day already carries the mark -> the selected chip',
      );

      await tester.tap(cycleSheetChip('ignoreTemperature'));
      await tester.pumpAndSettle();

      expect(
        await storedMarkTypes(db, scenarioDay(10)),
        isEmpty,
        reason:
            'the mark is removed from storage through the deleteMark '
            'path',
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('ignoreTemperature')).selected,
        isFalse,
        reason: 'the chip deselects after the removal',
      );
    });

    testWidgets(
      'the consistency dialog covers the mark-excluded branch: placing a '
      'first higher on a mark-EXCLUDED (but measured) day warns with the '
      'no-usable-temperature wording',
      (tester) async {
        // 9/14 is measured (36.90, ABOVE the baseline 36.40) — with the
        // temperature-ignore mark on the day the temperature is still not
        // usable, so the placement warns with the "unmeasured or
        // interrupted" wording (the mark-excluded branch of the dialog
        // body choice).
        final (_, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [
            CycleMark(
              date: scenarioDay(14),
              type: CycleMarkTypes.ignoreTemperature,
            ),
          ],
        );

        await tapCycleDay(tester, 8); // 9/14: measured above the baseline
        await tester.tap(cycleSheetChip('firstHigherMeasurement'));
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'the ignored temperature is not usable for the check — '
              'the placement warns even though the VALUE is above the '
              'baseline',
        );
        expect(
          find.text(
            'The marked day carries no usable temperature (unmeasured or '
            'interrupted).',
          ),
          findsOneWidget,
          reason:
              'the mark-excluded branch shows the fact wording, not a '
              'value comparison',
        );
      },
    );
  });

  group('chip icons (the per-type identification on the chips)', () {
    /// The icon inside the panel's keyed chip [markType]: the scoping
    /// keeps the lookup inside exactly one chip (the crossed-out-eye glyph
    /// also renders in the chart's temperature-exclusion badge, so a bare
    /// `find.byIcon` would match outside the panel).
    Finder chipIcon(String markType, IconData icon) => find.descendant(
      of: cycleSheetChip(markType),
      matching: find.byIcon(icon),
    );

    testWidgets('every mark chip shows its mark type icon while unselected — '
        'the six chips carry dusk, sun, dot, ring, flag and crossed-out-eye '
        'glyphs', (tester) async {
      final (_, _) = await _pump(
        tester,
        entries: scenarioEntries,
      ); // no marks yet
      await tapCycleDay(tester, 4); // 9/10, an arbitrary unmarked day

      expect(
        chipIcon('cycleStart', Icons.flag_outlined),
        findsOneWidget,
        reason: 'the cycle start keeps its pre-refactor boundary flag',
      );
      expect(
        chipIcon('mucusPeakDay', Icons.circle),
        findsOneWidget,
        reason:
            'the peak chip identifies the solid dot the chart '
            'renders for a peak (R6)',
      );
      expect(
        chipIcon('firstHigherMeasurement', Icons.adjust),
        findsOneWidget,
        reason: 'the first-higher chip keeps its circled-dot glyph',
      );
      expect(
        chipIcon('suzEvening', Icons.nightlight_outlined),
        findsOneWidget,
        reason:
            'the evening variant identifies itself with the dusk '
            'glyph',
      );
      expect(
        chipIcon('suzMorning', Icons.wb_sunny_outlined),
        findsOneWidget,
        reason:
            'the morning variant identifies itself with the sun '
            'glyph',
      );
      expect(
        find.descendant(
          of: excludeGroup,
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsOneWidget,
        reason:
            'the temperature-exclusion chip keeps its '
            'crossed-out-eye glyph inside its keyed grid cell',
      );

      // The two SUZ icons identify THEIR variant, not the pair — the
      // glyphs never appear swapped onto the sibling variant chip.
      expect(
        chipIcon('suzMorning', Icons.nightlight_outlined),
        findsNothing,
        reason: 'the dusk glyph belongs to the evening chip alone',
      );
      expect(
        chipIcon('suzEvening', Icons.wb_sunny_outlined),
        findsNothing,
        reason: 'the sun glyph belongs to the morning chip alone',
      );
    });
  });

  group('exclusion group (the manual temperature-exclusion chip)', () {
    /// [scenarioEntries] with the disturbance flags [mask] recorded on day 9/10
    /// (index 4).
    List<DailyEntry> entriesWithDay4Mask(int mask) {
      final entries = [...scenarioEntries];
      entries[4] = entries[4].copyWith(tempDisturbances: mask);
      return entries;
    }

    testWidgets(
      'a day WITH recorded disturbance flags: the group carries only the '
      'chip — neither heading text, nor flag labels, nor an empty '
      'line (the chart row shows the letters)',
      (tester) async {
        final (_, _) = await _pump(
          tester,
          entries: entriesWithDay4Mask(
            TempDisturbance.alk.bit | TempDisturbance.kr.bit,
          ),
        );

        await tapCycleDay(tester, 4); // 9/10: flags alk + kr recorded

        expect(
          excludeGroup,
          findsOneWidget,
          reason:
              'the exclusion chip lives in the keyed group '
              '(cycleSheetExcludeGroup)',
        );
        expect(
          find.text('Excluded from the evaluation'),
          findsNothing,
          reason:
              'the stale exclusion-group heading is gone — the chip '
              'label already says what it does',
        );
        expect(
          find.descendant(
            of: excludeGroup,
            matching: find.text('Alcohol (alk)'),
          ),
          findsNothing,
          reason:
              'the disturbance letters render on the CHART row, not in '
              'the sheet — no read-only flags here',
        );
        expect(
          find.descendant(
            of: excludeGroup,
            matching: find.text('Illness (kr)'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: excludeGroup,
            matching: find.text('No temperature disturbance recorded'),
          ),
          findsNothing,
          reason:
              'no explicit empty line — flag-less days show the same '
              'chip-only group',
        );
        // The group carries exactly ONE chip: the temperature exclusion,
        // itself keyed inside the group.
        expect(
          find.descendant(of: excludeGroup, matching: find.byType(FilterChip)),
          findsOneWidget,
          reason:
              'the group is exactly the exclusion chip — no flagged '
              'chips for read-only disturbance facts',
        );
        expect(
          find.descendant(
            of: excludeGroup,
            matching: find.text('Ignore temperature'),
          ),
          findsOneWidget,
          reason:
              'the temperature-exclusion chip stays inside the group '
              'cell of the shared chip grid',
        );
      },
    );

    testWidgets('a day WITHOUT recorded flags shows the same chip-only group — '
        'no empty-state line, and no disturbance-flag editing UI', (
      tester,
    ) async {
      final (_, _) = await _pump(tester, entries: scenarioEntries);

      await tapCycleDay(tester, 4); // 9/10: no flags recorded

      expect(
        excludeGroup,
        findsOneWidget,
        reason:
            'the group renders on every day: the chip without a '
            'heading',
      );
      expect(
        find.text('Excluded from the evaluation'),
        findsNothing,
        reason:
            'the stale exclusion-group heading is gone, also without '
            'flags',
      );
      expect(
        find.descendant(
          of: excludeGroup,
          matching: find.text('No temperature disturbance recorded'),
        ),
        findsNothing,
        reason: 'the explicit empty line is gone — nothing replaces it',
      );
      // Read-only concept stays: the panel never EDITS the flags (data
      // entry stays in the diary) — the group chip is the ONLY chip in the
      // group, and no disturbance string renders as an editable chip
      // anywhere in the panel.
      expect(
        find.descendant(of: excludeGroup, matching: find.byType(FilterChip)),
        findsOneWidget,
        reason: 'exactly the exclusion chip lives in the group',
      );
      for (final disturbance in [
        'Alcohol (alk)',
        'Illness (kr)',
        'Late to bed (sp)',
      ]) {
        expect(
          find.descendant(
            of: cycleDayPanel(),
            matching: find.text(disturbance),
          ),
          findsNothing,
          reason:
              '$disturbance stays a chart/diary fact, never a panel '
              'chip',
        );
      }
    });

    testWidgets(
      'the exclusion chip inside the group keeps its write behavior: it '
      'places the ignoreTemperature mark through the MarksDao and '
      'renders selected within the group',
      (tester) async {
        final (db, _) = await _pump(
          tester,
          entries: entriesWithDay4Mask(TempDisturbance.alk.bit),
        );

        await tapCycleDay(tester, 4); // 9/10
        await tester.tap(cycleSheetChip('ignoreTemperature'));
        await tester.pumpAndSettle();

        expect(
          await storedMarkTypes(db, scenarioDay(10)),
          contains(CycleMarkTypes.ignoreTemperature),
          reason: 'the group chip writes through the same mark path',
        );
        final groupChip = find.descendant(
          of: excludeGroup,
          matching: find.byType(FilterChip),
        );
        expect(
          tester.widget<FilterChip>(groupChip).selected,
          isTrue,
          reason:
              'the toggled chip stays visible and selected inside the '
              'group',
        );
      },
    );
  });

  group('SUZ mark + suggestion (the app suggests, the user places)', () {
    testWidgets(
      'the computed SUZ day suggests the start with the EVENING phrasing, '
      'naming rule D',
      (tester) async {
        // Main scenario: the 3rd circled candidate (9/16, 37.0) is >= 0.2 K
        // above the baseline 36.4 -> rule D fires, SUZ begins 9/16 evening.
        final (_, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
        );

        await tapCycleDay(tester, 10); // 9/16: the computed suzBegins

        expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')),
          findsOneWidget,
          reason:
              'the viewed day equals the computed suzBegins and '
              'no user SUZ mark exists anywhere in the cycle',
        );
        expect(
          find.textContaining('begins this evening (rule D)'),
          findsOneWidget,
          reason:
              'rule D: the suggestion names the rule AND carries the '
              'evening phrasing (rule D begins the SUZ that evening)',
        );
        expect(
          find.textContaining('begins this morning'),
          findsNothing,
          reason: 'rule D must NOT render the morning phrasing',
        );
      },
    );

    testWidgets(
      'the suggestion carries the MORNING phrasing when rule E fires on '
      'the 4th circle',
      (tester) async {
        // 9/14..9/17 all 36.5 (+0.1 above the baseline): the 3rd circled
        // candidate is below the rule-D margin, so the 4th (9/17) fires
        // rule E — and rule E begins the SUZ in the MORNING (owner-corrected:
        // the SUZ begins the morning of the 4th circled measurement, not the
        // evening).
        final entries = [
          ...scenarioEntries.take(8),
          DailyEntry(date: scenarioDay(14), bbtC: 36.5),
          DailyEntry(date: scenarioDay(15), bbtC: 36.5),
          DailyEntry(date: scenarioDay(16), bbtC: 36.5),
          DailyEntry(date: scenarioDay(17), bbtC: 36.5),
        ];
        final (_, _) = await _pump(
          tester,
          entries: entries,
          seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
        );

        await tapCycleDay(tester, 11); // 9/17: the computed suzBegins

        expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')),
          findsOneWidget,
        );
        expect(
          find.textContaining('begins this morning (rule E)'),
          findsOneWidget,
          reason:
              'rule E: the suggestion names the rule AND carries the '
              'morning phrasing (rule E begins the SUZ that morning)',
        );
        expect(
          find.textContaining('begins this evening'),
          findsNothing,
          reason:
              'rule E must NOT render the evening phrasing — the SUZ '
              'begins in the morning of the 4th circled day',
        );
      },
    );

    testWidgets(
      'the suggestion is suppressed once a user SUZ mark exists in the '
      'cycle',
      (tester) async {
        final (_, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [
            scenarioPeakMark,
            scenarioFirstHigherMark,
            CycleMark(date: scenarioDay(13), type: CycleMarkTypes.suzMorning),
          ],
        );

        await tapCycleDay(tester, 10); // 9/16: the computed suzBegins

        expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')),
          findsNothing,
          reason:
              'a user SUZ mark anywhere in the cycle suppresses the '
              'suggestion',
        );
      },
    );

    testWidgets('no suggestion on days that are not the computed SUZ day', (
      tester,
    ) async {
      final (_, _) = await _pump(
        tester,
        entries: scenarioEntries,
        seedMarks: [scenarioPeakMark, scenarioFirstHigherMark],
      );

      await tapCycleDay(tester, 8); // 9/14: the marked rise, not the SUZ day

      expect(
        find.byKey(const ValueKey('cycleSheetSuzSuggestion')),
        findsNothing,
      );
    });

    testWidgets('SUZ chips on any day: set evening, variant-switch to morning, '
        'remove', (tester) async {
      final (db, _) = await _pump(tester, entries: scenarioEntries);
      await tapCycleDay(
        tester,
        4,
      ); // 9/10 — an arbitrary day (chips on ANY day)

      // The chip can sit below the panel fold — scroll it into view first
      // (the helper used throughout for the bottom rows).
      await scrollSheetTo(tester, cycleSheetChip('suzEvening'));
      await tester.tap(cycleSheetChip('suzEvening'));
      await tester.pumpAndSettle();
      expect(
        await storedMarkTypes(db, scenarioDay(10)),
        contains(CycleMarkTypes.suzEvening),
        reason: 'the SUZ mark is persisted through the MarksDao',
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('suzEvening')).selected,
        isTrue,
        reason: 'the evening chip renders selected',
      );

      // Variant switch: placing the other variant removes the one present
      // (scroll it into view first — the bottom chips can sit below the
      // panel fold).
      await scrollSheetTo(tester, cycleSheetChip('suzMorning'));
      await tester.tap(cycleSheetChip('suzMorning'));
      await tester.pumpAndSettle();
      expect(
        await storedMarkTypes(db, scenarioDay(10)),
        unorderedEquals([CycleMarkTypes.suzMorning]),
        reason: 'placing one variant removes the other',
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('suzMorning')).selected,
        isTrue,
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('suzEvening')).selected,
        isFalse,
        reason:
            'the evening chip deselects with the removed variant — the '
            'mutual exclusivity is visible on the chips',
      );

      await tester.tap(cycleSheetChip('suzMorning'));
      await tester.pumpAndSettle();
      expect(
        await storedMarkTypes(db, scenarioDay(10)),
        isEmpty,
        reason: 'tapping the selected chip again deletes the mark',
      );
      expect(
        tester.widget<FilterChip>(cycleSheetChip('suzMorning')).selected,
        isFalse,
        reason: 'the morning chip deselects again',
      );
    });

    testWidgets(
      'a manual SUZ mark never alters the arithmetic — the evaluation '
      'info lines stay as computed',
      (tester) async {
        final (_, _) = await _pump(
          tester,
          entries: scenarioEntries,
          seedMarks: [
            scenarioPeakMark,
            scenarioFirstHigherMark,
            CycleMark(date: scenarioDay(12), type: CycleMarkTypes.suzEvening),
          ],
        );

        await tapCycleDay(tester, 8); // 9/14: circled candidate #1

        expect(
          find.text('+0.50 K above the baseline'),
          findsOneWidget,
          reason:
              'the difference to the baseline is unchanged by the SUZ '
              'mark (compute-only separation)',
        );
        expect(
          find.text('Circled higher measurement 1'),
          findsOneWidget,
          reason: 'the candidate sequence is unchanged by the SUZ mark',
        );
      },
    );
  });

  group('rise-mark consistency warning (owner decision 2026-09-17)', () {
    // The six-previous-calendar-day window of a mark on 9/13 is 9/7..9/12,
    // whose baseline is 36.40 (9/9); the marked day itself carries 36.30 —
    // NOT strictly above the baseline, so the placement is inconsistent.
    CycleMark markOn13() => CycleMark(
      date: scenarioDay(13),
      type: CycleMarkTypes.firstHigherMeasurement,
    );

    testWidgets('placing an inconsistent mark warns with the arithmetic and '
        'Keep keeps the mark', (tester) async {
      final (db, _) = await _pump(
        tester,
        entries: scenarioEntries,
      ); // no marks yet

      await tapCycleDay(tester, 7); // 9/13: 36.30 below the baseline 36.40
      await tester.tap(cycleSheetChip('firstHigherMeasurement'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'the inconsistent placement warns immediately',
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('First higher measurement'),
        ),
        findsOneWidget,
        reason:
            'the dialog title names the mark, never a verdict (the '
            'chip label equals the title — scoped to the dialog)',
      );
      expect(
        find.text(
          '36.30 °C on the marked day is not above the baseline 36.40 °C.',
        ),
        findsOneWidget,
        reason:
            'the dialog shows the arithmetic fact: marked value vs '
            'baseline value',
      );
      // Keep (like dismissing the dialog) leaves the mark standing.
      await tester.tap(cycleSheetRiseKeepButton());
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'the dialog is non-blocking: Keep only closes it',
      );
      expect(
        await storedMarkTypes(db, scenarioDay(13)),
        contains('firstHigherMeasurement'),
        reason: 'Keep keeps the just-placed mark',
      );
      expect(
        cycleDayPanel(),
        findsOneWidget,
        reason: 'the panel stays open across the warning',
      );
      expect(
        tester
            .widget<FilterChip>(cycleSheetChip('firstHigherMeasurement'))
            .selected,
        isTrue,
        reason: 'the chip reflects the kept mark',
      );
    });

    testWidgets('the Remove choice removes the just-placed mark', (
      tester,
    ) async {
      final (db, _) = await _pump(tester, entries: scenarioEntries);

      await tapCycleDay(tester, 7);
      await tester.tap(cycleSheetChip('firstHigherMeasurement'));
      await tester.pumpAndSettle();

      // The dialog's Remove choice is keyed — like the Keep choice, the
      // action is located by key; the wording names the mark type only.
      await tester.tap(cycleSheetRiseRemoveButton());
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await storedMarkTypes(db, scenarioDay(13)),
        isEmpty,
        reason: 'Remove undoes the placement through the toggle path',
      );
      expect(
        tester
            .widget<FilterChip>(cycleSheetChip('firstHigherMeasurement'))
            .selected,
        isFalse,
        reason: 'the chip deselected after the removal',
      );
    });

    testWidgets('placing a consistent mark shows no dialog', (tester) async {
      final (db, _) = await _pump(tester, entries: scenarioEntries);

      await tapCycleDay(tester, 8); // 9/14: 36.90 above the baseline 36.40
      await tester.tap(cycleSheetChip('firstHigherMeasurement'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'only an INCONSISTENT placement warns',
      );
      expect(
        await storedMarkTypes(db, scenarioDay(14)),
        contains('firstHigherMeasurement'),
        reason: 'the consistent mark is placed without the choice',
      );
    });

    testWidgets('a marked day without a usable temperature warns without a '
        'value arithmetic', (tester) async {
      final entries = [
        ...scenarioEntries.take(7), // 9/6..9/12 measured
        DailyEntry(date: scenarioDay(13)), // 9/13 tracked but UNMEASURED
        ...scenarioEntries.skip(8),
      ];
      final (_, _) = await _pump(tester, entries: entries);

      await tapCycleDay(tester, 7); // 9/13: the unmeasured day (baseline 36.40)
      await tester.tap(cycleSheetChip('firstHigherMeasurement'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The marked day carries no usable temperature (unmeasured or '
          'interrupted).',
        ),
        findsOneWidget,
        reason: 'without a marked value only the fact is stated',
      );
    });

    testWidgets('a merely-opened sheet for an existing inconsistent mark shows '
        'the PERSISTENT warning, no dialog', (tester) async {
      final (_, _) = await _pump(
        tester,
        entries: scenarioEntries,
        seedMarks: [markOn13()],
      );

      await tapCycleDay(tester, 7); // 9/13: the marked day

      expect(
        find.byKey(const ValueKey('cycleSheetRiseConsistency')),
        findsOneWidget,
        reason:
            'the inconsistency stays visible on every sheet open '
            '(later data edits cannot silently invalidate the mark)',
      );
      expect(
        find.text(
          'No measurement on the marked day is above the baseline 36.40 °C.',
        ),
        findsOneWidget,
        reason: 'the warning states the arithmetic fact only',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'merely opening the sheet never pops the dialog',
      );
    });

    testWidgets(
      'a later data edit that raises the baseline flips the warning on '
      '(the persistent line covers edits)',
      (tester) async {
        // The mark on 9/14 was placed over the baseline 36.40; an edited
        // 9/11 temperature 36.95 raises the window's baseline past the
        // marked 36.90 — the warning must show without re-placing the mark.
        final entries = [...scenarioEntries];
        entries[5] = entries[5].copyWith(bbtC: 36.95); // 9/11, in the window
        final (_, _) = await _pump(
          tester,
          entries: entries,
          seedMarks: [scenarioFirstHigherMark],
        );

        await tapCycleDay(tester, 8); // 9/14: the marked day

        expect(
          find.byKey(const ValueKey('cycleSheetRiseConsistency')),
          findsOneWidget,
          reason: 'the warning recomputes with the changed baseline',
        );
      },
    );

    testWidgets('a consistent mark shows no warning line', (tester) async {
      final (_, _) = await _pump(
        tester,
        entries: scenarioEntries,
        seedMarks: [scenarioFirstHigherMark],
      );

      await tapCycleDay(tester, 8); // 9/14: 36.90 above the baseline 36.40

      expect(
        find.byKey(const ValueKey('cycleSheetRiseConsistency')),
        findsNothing,
      );
    });
  });

  group(
    'mark write failures (a failed write reports, storage stays empty)',
    () {
      testWidgets(
        'a failing mark toggle surfaces the failure message and stores '
        'nothing — never an unhandled error',
        (tester) async {
          final faulty = _faultyDatabase();
          final (db, _) = await _pump(
            tester,
            entries: scenarioEntries,
            builder: () => faulty,
          ); // no marks yet
          faulty.failMarkWrites = true;

          await tapCycleDay(tester, 4); // 9/10, an unmarked arbitrary day
          await tester.tap(cycleSheetChip('mucusPeakDay'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'the chip write must catch its own failure — nothing may '
                'leak into the zone as an unhandled error',
          );
          expect(
            find.text('Saving failed — the data was not changed.'),
            findsOneWidget,
            reason:
                'a failed mark write is reported via the localized failure '
                'SnackBar (same posture as the diary save flow: nothing was '
                'changed)',
          );
          expect(
            await storedMarkTypes(db, scenarioDay(10)),
            isEmpty,
            reason: 'the failed toggle leaves no mark in storage',
          );
        },
      );

      testWidgets(
        'a failing SUZ write surfaces the same failure message, stores no '
        'mark, and stays free of unhandled errors',
        (tester) async {
          final faulty = _faultyDatabase();
          final (db, _) = await _pump(
            tester,
            entries: scenarioEntries,
            builder: () => faulty,
          ); // no marks yet
          faulty.failMarkWrites = true;

          await tapCycleDay(tester, 4); // 9/10, an unmarked arbitrary day
          await scrollSheetTo(tester, cycleSheetChip('suzEvening'));
          await tester.tap(cycleSheetChip('suzEvening'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'the SUZ write must catch its own failure — nothing may '
                'leak into the zone as an unhandled error',
          );
          expect(
            find.text('Saving failed — the data was not changed.'),
            findsOneWidget,
            reason:
                'a failed SUZ write is reported via the same localized '
                'failure SnackBar (nothing was changed)',
          );
          expect(
            await storedMarkTypes(db, scenarioDay(10)),
            isEmpty,
            reason:
                'the failed variant-switch write leaves neither variant in '
                'storage',
          );
        },
      );
    },
  );

  // ═══════════ marks stream error retry surface ═══════════

  testWidgets(
    'a marks stream error shows the retry surface in the panel instead of '
    'the all-unselected chip grid, and retry restores the chips',
    (tester) async {
      var attempt = 0;
      final (_, container) = await _pump(
        tester,
        entries: scenarioEntries,
        marksStreamFactory: () {
          attempt++;
          return attempt == 1
              ? Stream<List<CycleMark>>.error(StateError('injected error'))
              : Stream.value(evaluationScenarioMarks());
        },
      );

      // The panel is opened by writing its targeting provider directly —
      // the chart is replaced by its own retry surface, so no marks-row
      // cell is tappable.
      container.read(cycleDayPanelProvider.notifier).state = scenarioDay(10);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: cycleDayPanel(),
          matching: find.byKey(const ValueKey('marksStreamRetryButton')),
        ),
        findsOneWidget,
        reason: 'the grid area carries the retry affordance',
      );
      expect(
        find.descendant(
          of: cycleDayPanel(),
          matching: find.text('Loading failed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cycleDayPanel(), matching: find.byType(FilterChip)),
        findsNothing,
        reason: 'no all-unselected chip grid on a failed marks stream',
      );

      // Two marks retry surfaces coexist (the chart slot's and the
      // panel's own grid-area surface): the retry taps the panel's.
      await tester.tap(
        find.descendant(
          of: cycleDayPanel(),
          matching: find.byKey(const ValueKey('marksStreamRetryButton')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        cycleSheetChip('mucusPeakDay'),
        findsOneWidget,
        reason:
            'the retry re-subscribed the marks provider and the chips '
            'render from the real data',
      );
      expect(attempt, 2, reason: 'the retry re-invoked the stream factory');
    },
  );
}
