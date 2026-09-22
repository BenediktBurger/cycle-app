// Widget tests for the MANUAL temperature-exclusion coupling on the
// Tagebuch screen (owner decision 2026-09-19: the old flag-driven auto-set
// of the ignoreTemperature mark is DELETED — the linkage between the
// disturbance flags and the exclusion mark is MANUAL ONLY).
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
// independently and are covered elsewhere; the REVERSE-direction
// no-auto-removal of the old engine (mark survives flag clears) is also
// pinned by test/diary_cycle_start_prompt_test.dart (the pre-existing mark
// survives the save there).
//
// The database is an in-memory override and the German locale is pinned,
// same harness pattern as test/diary_measured_time_test.dart.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/viewport.dart';

final _fixedNow = DateTime(2026, 4, 10, 14, 35);
final _selectedDay = DateOnly.normalize(_fixedNow);

CycleDatabase? _db;

/// The exclude switch inside the diary's disturbance group (test-visible
/// key on the SwitchListTile).
Finder get _excludeSwitch =>
    find.byKey(const ValueKey('diaryExcludeTemperatureSwitch'));

/// The current value of the exclude switch, read from its widget.
bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_excludeSwitch).value;

/// German locale, pinned "now" and selected day over the shared appScope
/// harness — the pins this file's German assertions need, without the
/// per-file scope copy.
ProviderScope _scope({Future<void> Function(CycleDatabase db)? seed}) {
  return appScope(
    now: () => _fixedNow,
    selectedDay: _selectedDay,
    locale: const Locale('de'),
    onCreated: (db) => _db = db,
    seed: seed,
  );
}

void main() {
  /// Selects the disturbance chip [label] (German: the pinned locale) —
  /// the disturbance options are FilterChips (independent toggles).
  Future<void> toggleDisturbanceChip(
    WidgetTester tester,
    String chipLabel,
  ) async {
    await tester.tap(find.widgetWithText(FilterChip, chipLabel));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  /// The stored mark types for the selected day (from the real database).
  Future<List<String>> storedMarkTypes() async =>
      (await _db!.marksDao.marksForDay(
        _selectedDay,
      )).map((m) => m.markType).toList();

  testWidgets('saving a flagged day WITHOUT the exclude switch does NOT create '
      'the ignoreTemperature mark (no auto-set in any direction)', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    expect(
      await storedMarkTypes(),
      isEmpty,
      reason: 'guard: a fresh day carries no marks',
    );

    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)');
    await save(tester);

    expect(
      await storedMarkTypes(),
      isEmpty,
      reason:
          'a disturbance flag alone never excludes the day from the '
          'analysis — the explicit exclude switch decides',
    );
    final entry = await _db!.entriesDao.entryFor(_selectedDay);
    expect(
      entry!.tempDisturbances,
      TempDisturbance.sp.bit,
      reason: 'the raw mask is still stored on the entry as entered',
    );
  });

  testWidgets('the exclude switch inside the disturbance group writes the '
      'ignoreTemperature mark on save — even without any flag, and '
      'idempotently', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    await tester.tap(_excludeSwitch);
    await tester.pumpAndSettle();
    await save(tester);

    final marks = await _db!.marksDao.marksForDay(_selectedDay);
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
    final entry = await _db!.entriesDao.entryFor(_selectedDay);
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
      (await _db!.marksDao.marksForDay(_selectedDay)),
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
      useTallSurface(tester);
      await tester.pumpWidget(
        _scope(
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
        await storedMarkTypes(),
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
      useTallSurface(tester);
      await tester.pumpWidget(
        _scope(
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

      await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)');
      await save(tester);

      final marks = await _db!.marksDao.marksForDay(_selectedDay);
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
    useTallSurface(tester);
    await tester.pumpWidget(
      _scope(
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

    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)'); // deselect
    await toggleDisturbanceChip(tester, 'Alkohol (alk)'); // deselect
    await save(tester);

    final marks = await _db!.marksDao.marksForDay(_selectedDay);
    expect(
      marks.map((m) => m.markType),
      [CycleMarkTypes.ignoreTemperature],
      reason:
          'clearing the flags never lifts the exclusion — only the '
          'switch does',
    );
    final entry = await _db!.entriesDao.entryFor(_selectedDay);
    expect(
      entry!.tempDisturbances,
      0,
      reason: 'the mask itself is fully cleared by the save',
    );
  });
}
