// Widget tests for the MANUAL temperature-exclusion coupling on the
// Tagebuch screen (owner decision): the linkage between the disturbance
// flags and the ignoreTemperature mark is MANUAL ONLY.
//
// The disturbance flags (sp/a/alk/kr) and the exclude switch live in ONE
// labelled group so flagging and excluding are visibly one decision, but
// they are independent inputs:
//   - a flagged save NEVER creates the ignoreTemperature mark,
//   - the explicit exclude switch inside the group is the only diary-side
//     writer of the mark (both directions: on -> set, off -> removed),
//   - the switch seeds from the day's existing mark, so an untouched
//     switch preserves an externally placed mark (day sheet, imports),
//   - clearing the flags never auto-clears a present mark.
//
// Import paths (drip CSV, old export documents) derive the mark
// independently and are covered elsewhere; the untouched-save-keeps-a-mark
// side is also pinned by test/diary_time_and_navigation_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/finders.dart';

/// The shared pinned-harness (German locale, pinned clock and selected day,
/// in-memory database — see DiaryHarness).
final _harness = DiaryHarness(now: DateTime(2026, 4, 10, 14, 35));

DateTime get _selectedDay => _harness.selectedDay;

/// The exclude switch inside the diary's disturbance group (test-visible
/// key on the SwitchListTile).
Finder get _excludeSwitch =>
    find.byKey(const ValueKey('diaryExcludeTemperatureSwitch'));

/// The current value of the exclude switch, read from its widget.
bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_excludeSwitch).value;

void main() {
  /// Selects the disturbance chip [token] (sp / a / alk / kr) —
  /// the disturbance options are FilterChips (independent toggles).
  Future<void> toggleDisturbanceChip(WidgetTester tester, String token) async {
    await tester.tap(diaryChip('disturbance', token));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();
  }

  testWidgets('saving a flagged day WITHOUT the exclude switch does NOT create '
      'the ignoreTemperature mark (no auto-set in any direction)', (
    tester,
  ) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope());
    await tester.pumpAndSettle();

    expect(
      await _harness.storedMarkTypes(_selectedDay),
      isEmpty,
      reason: 'guard: a fresh day carries no marks',
    );

    await toggleDisturbanceChip(tester, 'sp');
    await save(tester);

    expect(
      await _harness.storedMarkTypes(_selectedDay),
      isEmpty,
      reason:
          'a disturbance flag alone never excludes the day from the '
          'analysis — the explicit exclude switch decides',
    );
    final entry = await _harness.db!.entriesDao.entryFor(_selectedDay);
    expect(
      entry!.tempDisturbances,
      TempDisturbance.sp.bit,
      reason: 'the raw mask is still stored on the entry as entered',
    );
  });

  testWidgets('the exclude switch inside the disturbance group writes the '
      'ignoreTemperature mark on save — even without any flag, and '
      'idempotently', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(_harness.scope());
    await tester.pumpAndSettle();

    await tester.tap(_excludeSwitch);
    await tester.pumpAndSettle();
    await save(tester);

    final marks = await _harness.db!.marksDao.marksForDay(_selectedDay);
    expect(
      marks.map((m) => m.markType),
      [CycleMarkTypes.ignoreTemperature],
      reason:
          'the manual switch is the diary-side writer of the '
          'analysis-exclusion mark (exactly one, no flag needed)',
    );
    expect(
      marks.single.author,
      'user',
      reason:
          'the diary save is user-placed data — the mark is '
          'user-authored like every sheet toggle',
    );
    final entry = await _harness.db!.entriesDao.entryFor(_selectedDay);
    expect(
      entry!.tempDisturbances,
      0,
      reason:
          'the switch is independent of the raw mask: excluding '
          'without flags is representable',
    );

    // Re-save with the switch untouched: addMark is idempotent.
    await save(tester);
    expect(
      (await _harness.db!.marksDao.marksForDay(_selectedDay)),
      hasLength(1),
      reason:
          'repeated saves with the switch on stay at one mark '
          '(idempotent)',
    );
  });

  testWidgets(
    'the switch seeds from the day\'s existing mark; switching it off '
    'and saving REMOVES the mark',
    (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.marksDao.addMark(
              _selectedDay,
              CycleMarkTypes.ignoreTemperature,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _switchValue(tester),
        isTrue,
        reason:
            'the switch is wired to the mark\'s actual present state, '
            'not to the disturbance mask',
      );

      await tester.tap(_excludeSwitch);
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        await _harness.storedMarkTypes(_selectedDay),
        isEmpty,
        reason:
            'the switch off -> save removes the pre-existing mark '
            '(the explicit manual removal)',
      );
    },
  );

  testWidgets(
    'a flagged save keeps an externally placed mark intact (the switch '
    'seeds on, so the save re-affirms instead of auto-deciding)',
    (tester) async {
      _harness.tallSurface(tester);
      await tester.pumpWidget(
        _harness.scope(
          seed: (db) async {
            await db.marksDao.addMark(
              _selectedDay,
              CycleMarkTypes.ignoreTemperature,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _switchValue(tester),
        isTrue,
        reason: 'the seed: the switch mirrors the mark\'s present state',
      );

      await toggleDisturbanceChip(tester, 'sp');
      await save(tester);

      final marks = await _harness.db!.marksDao.marksForDay(_selectedDay);
      expect(
        marks.map((m) => m.markType),
        [CycleMarkTypes.ignoreTemperature],
        reason:
            'the flagged save neither removes nor duplicates the '
            'pre-existing mark — no auto behavior in either direction',
      );
      expect(marks.single.author, 'user');
    },
  );

  testWidgets('removing the disturbance flags never auto-clears a present mark '
      '(the switch drives the mark, not the mask)', (tester) async {
    _harness.tallSurface(tester);
    await tester.pumpWidget(
      _harness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: _selectedDay,
              tempDisturbances:
                  TempDisturbance.sp.bit | TempDisturbance.alk.bit,
            ),
          );
          await db.marksDao.addMark(
            _selectedDay,
            CycleMarkTypes.ignoreTemperature,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await toggleDisturbanceChip(tester, 'sp'); // deselect
    await toggleDisturbanceChip(tester, 'alk'); // deselect
    await save(tester);

    final marks = await _harness.db!.marksDao.marksForDay(_selectedDay);
    expect(
      marks.map((m) => m.markType),
      [CycleMarkTypes.ignoreTemperature],
      reason:
          'clearing the flags never lifts the exclusion — only the '
          'switch does',
    );
    final entry = await _harness.db!.entriesDao.entryFor(_selectedDay);
    expect(
      entry!.tempDisturbances,
      0,
      reason: 'the mask itself is fully cleared by the save',
    );
  });
}
