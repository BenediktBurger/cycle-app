// Widget test of the Tagebuch app bar's always-visible save action: the
// Save action must sit in the AppBar (reachable from anywhere in the form,
// not only at the bottom), and tapping it must persist the day exactly like
// the bottom button does. The bottom button stays (in addition, not
// instead).
//
// Provider-override harness from support/diary_harness.dart; German labels
// are pinned (locale de), the clock is pinned through nowProvider so the
// prefilled measurement-time assertion stays deterministic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

final _harness = DiaryHarness(now: DateTime(2026, 9, 21, 10, 30));

/// The app-bar save action (test-visible key, like the dark-switch and the
/// temperature-picker keys).
Finder _saveAction() => find.byKey(const ValueKey('diarySaveAction'));

void main() {
  testWidgets('the Tagebuch AppBar carries the save action beside the bottom '
      'button', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope());
    await tester.pumpAndSettle();

    expect(
      _saveAction(),
      findsOneWidget,
      reason:
          'the save action lives in the app bar, reachable from '
          'anywhere in the form',
    );
    expect(
      find.ancestor(of: _saveAction(), matching: find.byType(AppBar)),
      findsOneWidget,
      reason: 'the action is part of the AppBar, not the form body',
    );
  });

  testWidgets('tapping the app-bar save action persists the entry exactly like '
      'the bottom button', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope());
    await tester.pumpAndSettle();

    // The bottom button stays: both surfaces offer the same action.
    expect(
      find.ancestor(
        of: find.text('Speichern'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
      reason:
          'the bottom save button is kept in addition to the app-bar '
          'action',
    );

    await tester.enterText(find.byType(TextFormField).first, '36.5');
    await tester.pumpAndSettle();

    await tester.tap(_saveAction());
    await tester.pumpAndSettle();

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(
      row,
      isNotNull,
      reason:
          'the app-bar action must persist the day like the bottom '
          'button does',
    );
    expect(
      row!.bbtC,
      36.5,
      reason:
          'the entered temperature is stored through the same save '
          'handler',
    );
    expect(
      row.measuredAtMinutes,
      10 * 60 + 30,
      reason:
          'the same save path also persists the prefilled measurement '
          'time (the pinned "now")',
    );
  });
}
