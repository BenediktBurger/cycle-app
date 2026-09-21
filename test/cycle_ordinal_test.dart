// Widget tests of the cycle ordinal on the cycle chart: every cycle
// boundary day (the same isCycleBoundary predicate that draws the thick
// separator line) renders the "Cycle N" ordinal in the day header, with N
// shifted by the persisted "cycles observed outside this app" setting. The
// leading pre-mark group carries no ordinal (the shared ordinal rule,
// lib/domain/cycle_grouping.dart — the evaluation table numbers through the
// same helper so the two surfaces cannot drift).
//
// Harness: the shared chart pump (chart_pump.dart) with the
// observedCyclesOutsideApp provider pinned per test; nothing is written to
// any database here (pure render-time display, ADR-0001).
import 'package:cycle_app/domain/marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/chart_pump.dart';

/// Twenty-one consecutive tracked days from 2026-01-01 with a repeating
/// temperature run (the shared long-range fixture's first 21 days); the
/// cycleStart mark on 2026-01-10 opens the first boundary at day index 9.
DateTime boundaryDay(int index) => longRangeDay(index);

final _entries = longRangeEntries(21);

CycleMark _cycleStartAt(int index) =>
    CycleMark(date: boundaryDay(index), type: CycleMarkTypes.cycleStart);

void main() {
  /// The rendered ordinal text of the boundary day at [index] (keyed on the
  /// Text itself).
  String ordinalText(WidgetTester tester, int index) =>
      tester.widget<Text>(find.byKey(ValueKey('cycleOrdinal-$index'))).data!;

  testWidgets(
      'the first cycle boundary carries the ordinal 1 without any '
      'outside-app cycles', (tester) async {
    await tester.pumpWidget(chartHarness(
      entries: _entries,
      marks: [_cycleStartAt(9)],
    ));
    await tester.pumpAndSettle();

    final ordinal = find.byKey(const ValueKey('cycleOrdinal-9'));
    expect(ordinal, findsOneWidget,
        reason: 'the boundary day renders its ordinal label in the day '
            'header');
    expect(ordinalText(tester, 9), 'Cycle 1',
        reason: 'the first mark-opened cycle is "Cycle 1"');
    // The leading pre-mark group carries no ordinal.
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('cycleOrdinal-')),
        findsOneWidget,
        reason: 'no ordinal anywhere before the first cycleStart mark');
  });

  testWidgets(
      'the ordinal shifts by the persisted outside-app count: the first '
      'boundary after 2 prior cycles reads "Cycle 3"', (tester) async {
    await tester.pumpWidget(chartHarness(
      entries: _entries,
      marks: [_cycleStartAt(9)],
      observedCyclesOutsideApp: 2,
    ));
    await tester.pumpAndSettle();

    expect(ordinalText(tester, 9), 'Cycle 3',
        reason: 'outside-app cycles shift every ordinal: prior count 2 '
            'makes the first boundary "Cycle 3"');
  });

  testWidgets(
      'a second boundary is numbered one higher than the first '
      '(1, 2, …)', (tester) async {
    await tester.pumpWidget(chartHarness(
      entries: _entries,
      marks: [_cycleStartAt(9), _cycleStartAt(18)],
      observedCyclesOutsideApp: 1,
    ));
    await tester.pumpAndSettle();

    expect(ordinalText(tester, 9), 'Cycle 2',
        reason: 'first boundary: prior count 1 + 1');
    expect(ordinalText(tester, 18), 'Cycle 3',
        reason: 'second boundary: prior count 1 + 2');
  });

  testWidgets(
      'the ordinal label stays inside the header cell in German '
      '(the l10n key mirrors the evaluation-table wording)', (tester) async {
    await tester.pumpWidget(chartHarness(
      entries: _entries,
      marks: [_cycleStartAt(9)],
      observedCyclesOutsideApp: 2,
      locale: const Locale('de'),
    ));
    await tester.pumpAndSettle();

    expect(ordinalText(tester, 9), 'Zyklus 3',
        reason: 'the German ordinal wording renders on the chart');
  });
}
