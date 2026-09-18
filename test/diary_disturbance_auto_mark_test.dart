// Widget tests for the analysis-exclusion AUTO-SET on the Tagebuch screen:
// saving a day with ANY disturbance flag selected (sp/a/alk/kr) auto-SETs
// the excludedFromAnalysis mark (idempotent); saving a flag-less day never
// creates the mark. The REVERSE direction — a mark is never auto-REMOVED
// when the flags clear — is pinned in test/diary_cycle_start_prompt_test.dart
// (the mark-suppresses-prompt test asserts the mark survives the save).
//
// The database is an in-memory override and the German locale is pinned,
// same harness pattern as test/diary_measured_time_test.dart.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixedNow = DateTime(2026, 4, 10, 14, 35);
final _selectedDay = DateOnly.normalize(_fixedNow);

CycleDatabase? _db;

ProviderScope _scope({Future<void> Function(CycleDatabase db)? seed}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) async {
        final db = CycleDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        );
        _db = db;
        ref.onDispose(db.close);
        await seed?.call(db);
        return db;
      }),
      nowProvider.overrideWith((ref) => () => _fixedNow),
      selectedDateProvider.overrideWith((ref) => _selectedDay),
      localeProvider.overrideWith((ref) => const Locale('de')),
    ],
    child: const CycleApp(),
  );
}

void main() {
  void tallSurface(WidgetTester tester, {double height = 2400}) {
    tester.view.physicalSize = Size(800, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Selects the disturbance chip [label] (German: the pinned locale) —
  /// the disturbance options are FilterChips (independent toggles).
  Future<void> toggleDisturbanceChip(
      WidgetTester tester, String chipLabel) async {
    await tester.tap(find.widgetWithText(FilterChip, chipLabel));
    await tester.pumpAndSettle();
  }

  /// Selects the bleeding chip [label] (bleeding is a ChoiceChip) and
  /// saves the day.
  Future<void> saveWithBleeding(WidgetTester tester, String chipLabel) async {
    await tester.tap(find.widgetWithText(ChoiceChip, chipLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saving a day with a disturbance flag selected auto-sets the '
      'excludedFromAnalysis mark (user-authored, once)', (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    expect(await _db!.marksDao.marksForDay(_selectedDay), isEmpty,
        reason: 'guard: a fresh day carries no marks');

    await toggleDisturbanceChip(tester, 'Spät ins Bett (sp)');
    await save(tester);

    final marks = await _db!.marksDao.marksForDay(_selectedDay);
    expect(marks.map((m) => m.markType),
        contains(CycleMarkTypes.excludedFromAnalysis),
        reason: 'any selected disturbance flag auto-SETs the '
            'analysis-exclusion mark on save (the raw mask alone is '
            'rendering input, the analysis is mark-driven)');
    final mark = marks
        .singleWhere((m) => m.markType == CycleMarkTypes.excludedFromAnalysis);
    expect(mark.author, 'user',
        reason: 'the diary save is user-placed data — the mark is '
            'user-authored like every sheet toggle');
    expect(marks, hasLength(1),
        reason: 'the auto-set is idempotent: exactly one mark lands');

    final entry = await _db!.entriesDao.entryFor(_selectedDay);
    expect(entry!.tempDisturbances, TempDisturbance.sp.bit,
        reason: 'the raw mask is stored on the entry as well');
  });

  testWidgets('re-saving with another flag keeps exactly one mark',
      (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
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

    final marks = await _db!.marksDao.marksForDay(_selectedDay);
    expect(marks.map((m) => m.markType), [CycleMarkTypes.excludedFromAnalysis],
        reason: 'still exactly ONE exclusion mark (addMark is idempotent)');
    final entry = await _db!.entriesDao.entryFor(_selectedDay);
    expect(entry!.tempDisturbances, TempDisturbance.kr.bit,
        reason: 'the second save fully replaced the mask (sp cleared, kr '
            'set)');
  });

  testWidgets('a save without any disturbance flag creates NO mark',
      (tester) async {
    tallSurface(tester);
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    await saveWithBleeding(tester, 'leicht'); // bleeding only

    expect(await _db!.marksDao.marksForDay(_selectedDay), isEmpty,
        reason: 'auto-set is flag-driven only: a plain save must not '
            'exclude the day from the analysis');
  });
}
