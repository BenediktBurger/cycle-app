// Widget tests for the analysis-exclusion AUTO-SET on the Tagebuch screen:
// saving a day with ANY disturbance flag selected (sp/a/alk/kr) auto-SETs
// the ignoreTemperature mark (idempotent); saving a flag-less day never
// creates the mark. The REVERSE direction — a mark is never auto-REMOVED
// when the flags clear — is pinned in test/diary_cycle_start_prompt_test.dart
// (the prompt test asserts the mark does NOT suppress the cycle-start
// prompt while the pre-existing mark survives the save).
//
// The database is an in-memory override and the German locale is pinned,
// same harness pattern as test/diary_measured_time_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

final harness = DiaryHarness(now: DateTime(2026, 4, 10, 14, 35));

void main() {
  /// Selects the disturbance chip [label] (German: the pinned locale) —
  /// the disturbance options are FilterChips (independent toggles).
  Future<void> toggleDisturbanceChip(
      WidgetTester tester, String chipLabel) async {
    await tester.tap(find.widgetWithText(FilterChip, chipLabel));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saving a day with a disturbance flag selected auto-sets the '
      'ignoreTemperature mark (user-authored, once)', (tester) async {
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope());
    await tester.pumpAndSettle();

    expect(await harness.db!.marksDao.marksForDay(harness.selectedDay), isEmpty,
        reason: 'guard: a fresh day carries no marks');

    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)');
    await save(tester);

    final marks = await harness.db!.marksDao.marksForDay(harness.selectedDay);
    expect(marks.map((m) => m.markType),
        contains(CycleMarkTypes.ignoreTemperature),
        reason: 'any selected disturbance flag auto-SETs the '
            'analysis-exclusion mark on save (the raw mask alone is '
            'rendering input, the analysis is mark-driven)');
    final mark = marks
        .singleWhere((m) => m.markType == CycleMarkTypes.ignoreTemperature);
    expect(mark.author, 'user',
        reason: 'the diary save is user-placed data — the mark is '
            'user-authored like every sheet toggle');
    expect(marks, hasLength(1),
        reason: 'the auto-set is idempotent: exactly one mark lands');

    final entry = await harness.db!.entriesDao.entryFor(harness.selectedDay);
    expect(entry!.tempDisturbances, TempDisturbance.sp.bit,
        reason: 'the raw mask is stored on the entry as well');
  });

  testWidgets('re-saving with another flag keeps exactly one mark',
      (tester) async {
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope());
    await tester.pumpAndSettle();

    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)');
    await save(tester);
    // The form keeps its saved state (no reload after save): clear the
    // first flag explicitly, then select a different one and re-save — the
    // storage write is a full replace, and the auto-set re-runs
    // idempotently on the new mask.
    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)'); // deselect
    await toggleDisturbanceChip(tester, 'Krank (kr)');
    await save(tester);

    final marks = await harness.db!.marksDao.marksForDay(harness.selectedDay);
    expect(marks.map((m) => m.markType), [CycleMarkTypes.ignoreTemperature],
        reason: 'still exactly ONE exclusion mark (addMark is idempotent)');
    final entry = await harness.db!.entriesDao.entryFor(harness.selectedDay);
    expect(entry!.tempDisturbances, TempDisturbance.kr.bit,
        reason: 'the second save fully replaced the mask (sp cleared, kr '
            'set)');
  });

  testWidgets('a save without any disturbance flag creates NO mark',
      (tester) async {
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope());
    await tester.pumpAndSettle();

    await harness.saveWithBleeding(tester, 'leicht'); // bleeding only

    expect(await harness.db!.marksDao.marksForDay(harness.selectedDay), isEmpty,
        reason: 'auto-set is flag-driven only: a plain save must not '
            'exclude the day from the analysis');
  });
}
