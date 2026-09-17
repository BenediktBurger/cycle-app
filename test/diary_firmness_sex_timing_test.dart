// Widget test of the Muttermund-FESTIGKEIT (cervix firmness) picker and the
// sex time-of-day chips on the Tagebuch entry form:
//
//  - firmness (hart / h-w / weich) is offered as a ChoiceChip wrap with the
//    same pattern as position/opening (leading unset chip, tap-again
//    deselects) and a selected value survives the save path into the
//    database;
//  - the three sex time slots (Anfang/Mitte/Ende) are an INDEPENDENT
//    multi-select: each chip toggles its own SexTiming bit in the day's
//    sexTimings mask, several can be selected at once, tapping a selected
//    chip again clears its bit — the saved mask is the OR of the selected
//    chips.
//
// Provider-override harness pattern from diary_cervix_selector_test.dart;
// German labels are pinned per that file's convention (pinned locale de).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderScope _appScope(Locale locale) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith(
          (ref) {
            final db = CycleDatabase(
              DatabaseConnection(
                NativeDatabase.memory(),
                closeStreamsSynchronously: true,
              ),
            );
            ref.onDispose(db.close);
            return db;
          },
        ),
        localeProvider.overrideWith((ref) => locale),
      ],
      child: const CycleApp(),
    );

Future<({CycleDatabase db, DateTime date})> _savedDayOf(
    WidgetTester tester) async {
  final context = tester.element(find.byType(TagebuchScreen));
  final container = ProviderScope.containerOf(context);
  final db = await container.read(databaseProvider.future);
  return (db: db, date: container.read(selectedDateProvider));
}

void main() {
  testWidgets('the mucus sign picker offers the A (Ausfluss) segment',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The sign segments show the cheat-sheet glyphs themselves; the A
    // (Ausfluss) sign joined the vocabulary, so its segment must be
    // offered (it renders via the same MucusSymbolText pipeline as the
    // other signs — no picker-specific handling).
    expect(find.text('A'), findsOneWidget,
        reason: 'the Ausfluss sign (A) must be selectable on the form');
  });

  testWidgets('firmness options are offered and a selection persists',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The firmness vocabulary (paper shorthand h / h-w / w as the chip
    // labels, pinned German locale). NB the unset chip "—" is NOT asserted
    // here: the mucus/position/opening pickers use the same label, so it is
    // ambiguous on this form.
    expect(find.text('hart'), findsOneWidget,
        reason: 'the firmness option hart must be selectable');
    expect(find.text('h-w'), findsOneWidget,
        reason: 'the firmness option h-w must be selectable');
    expect(find.text('weich'), findsOneWidget,
        reason: 'the firmness option weich must be selectable');

    await tester.ensureVisible(find.text('weich'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('weich'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await _savedDayOf(tester);
    final row = await db.entriesDao.entryFor(defaultProfileId, date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.cervixFirmness, 'soft',
        reason: 'the selected firmness (weich) must persist as its token');
  });

  testWidgets('tapping the selected firmness again deselects it',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('hart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hart'));
    await tester.pumpAndSettle();
    // Tap-again-deselect: the chips pattern of position/opening.
    await tester.tap(find.text('hart'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final (:db, :date) = await _savedDayOf(tester);
    final row = await db.entriesDao.entryFor(defaultProfileId, date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.cervixFirmness, isNull,
        reason: 'a deselected firmness must persist as no observation');
  });

  testWidgets('sex time slots are a multi-select: several chips persist as '
      'the OR of their bits', (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The three time slots (pinned German locale).
    expect(find.text('Anfang'), findsOneWidget,
        reason: 'the start slot must be offered');
    expect(find.text('Mitte'), findsOneWidget,
        reason: 'the middle slot must be offered');
    expect(find.text('Ende'), findsOneWidget,
        reason: 'the end slot must be offered');

    // Select TWO slots at once — the old single bool is gone.
    await tester.ensureVisible(find.text('Anfang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anfang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ende'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final (:db, :date) = await _savedDayOf(tester);
    final row = await db.entriesDao.entryFor(defaultProfileId, date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.sexTimings, 1 | 4,
        reason: 'Anfang (bit 1) + Ende (bit 4) must persist as mask 5');
  });

  testWidgets('tapping a selected sex slot again clears its bit',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mitte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mitte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mitte')); // deselect again
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ende'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final (:db, :date) = await _savedDayOf(tester);
    final row = await db.entriesDao.entryFor(defaultProfileId, date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.sexTimings, 4,
        reason: 'the re-tapped middle slot must be cleared; Ende (bit 4) '
            'stays');
  });
}
