// Shared driver for the settings switcher-card tests: opening the settings
// pane of the real CycleApp and walking a switcher's option table. The
// scaffold (tall surface for the lazy card list, navigation tap, selection
// state) is the same for every card — what a card DOES with a choice stays
// in the caller's step outcomes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database.dart';
import 'finders.dart';
import 'viewport.dart';

/// One walked switcher step: tap [segment], then [outcome] pins what the
/// setting does beyond its switcher state (the materialized device locale,
/// the brightness, the provider value — null when the selection state is
/// the whole contract of the step).
class SwitcherStep<T> {
  final Finder segment;
  final Set<T> selected;
  final Future<void> Function(WidgetTester tester)? outcome;

  const SwitcherStep({
    required this.segment,
    required this.selected,
    this.outcome,
  });
}

/// Opens the settings pane of the real CycleApp on an enlarged surface —
/// the card list is lazy and builds the lower cards only on a tall viewport.
/// [tabLabel] is the tab's label in the surface language under test.
Future<void> pumpSettingsPane(WidgetTester tester, String tabLabel) async {
  useTallSurface(tester, width: 900);
  await tester.pumpWidget(appScope());
  await tester.pumpAndSettle();
  await tester.tap(navLabel(tabLabel));
  await tester.pumpAndSettle();
}

/// Exercises one switcher card: the switcher must be on screen, its default
/// selection must be [defaultSelected], and every step's tap must apply the
/// choice immediately — the step's own state plus its outcome.
Future<void> exerciseSwitcher<T>(
  WidgetTester tester, {
  required Finder switcher,
  required Set<T> defaultSelected,
  required List<SwitcherStep<T>> steps,
}) async {
  expect(
    switcher,
    findsOneWidget,
    reason: 'the switcher must be on the settings screen',
  );
  expect(
    tester.widget<SegmentedButton<T>>(switcher).selected,
    defaultSelected,
    reason: 'the switcher must start on its System default',
  );

  for (final step in steps) {
    await tester.tap(step.segment);
    await tester.pumpAndSettle();
    if (step.outcome != null) await step.outcome!(tester);
    expect(tester.widget<SegmentedButton<T>>(switcher).selected, step.selected);
  }
}
