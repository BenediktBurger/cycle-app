// Widget tests of the Tagebuch (diary) entry-form selectors — the
// whole entry-form family in one file: the bleeding levels, the
// Muttermund (cervix) position and opening, the two letter-coded pain
// options (B, M), the Muttermund-FESTIGKEIT (firmness) picker and the
// sex time-of-day chips (including the mucus-A-segment check the
// firmness picker shares its form with).
//
// Each section below (kicked off by a `════ former` banner) carries
// the former file's header comments verbatim; test bodies were
// concatenated, not rewritten. The single `_appScope` wrapper around
// support/diary_harness.dart was shared four times byte-for-byte, so
// it lives here once.

// No assertion was edited: run the full gate and diff the collected
// test names against the pre-merge report — only the suite-path
// prefix changed.

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/diary_harness.dart';

// Widget test of the bleeding control on the Tagebuch entry form: the
// selector must offer the full 5-level vocabulary (none/spotting/light/
// medium/heavy), and selecting a level must survive the save path — the
// level is read back from the database through the same database provider
// the form writes with.
//
// An in-memory drift database is injected (provider-override pattern from
// app_shell_test.dart), so the test stays file-free and platform-channel-free.

ProviderScope _appScope(Locale locale) => diarySelectorScope(locale);

// Widget test of the Muttermund (cervix) observation on the Tagebuch entry
// form: the position (tief … unerreichbar) and the opening
// (geschlossen/mittel/offen) must be offered as chip pickers, and a selected
// combination must survive the save path into the database (read back
// through the same database provider the form writes with).
//
// Provider-override harness from
// support/diary_harness.dart; German labels are pinned (locale de).

// Widget test of the pain options on the Tagebuch entry form: the two
// letter-coded pain options — breast tenderness (B) and Mittelschmerz (M)
// — must be offered and selectable, and selecting one of them (with the
// other unset) must survive the save path: the options are separate
// per-day booleans, read back from the database through the same
// database provider the form writes with.
//
// An in-memory drift database is injected (provider-override harness from
// support/diary_harness.dart).

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
// Provider-override harness from
// support/diary_harness.dart; German labels are pinned (locale de).

void main() {
// ═══════════ bleeding selector ═══════════
// former test/diary_bleeding_selector_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets('bleeding selector offers all five levels and stores heavy',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The Tagebuch screen is the shell's initial tab; the bleeding control
    // sits on its entry form. All five levels of the numeric scale must be
    // offered (German labels, per the pinned locale). NB "mittel" is also
    // the German label of one Muttermund position AND of the opening chip
    // "mittel" on the same form, so the strict one-match assertion does not
    // apply to that one word.
    const levels = ['keine', 'Schmierblutung', 'leicht', 'mittel', 'stark'];
    for (final level in levels) {
      expect(
        find.text(level),
        findsWidgets,
        reason: 'Bleeding option "$level" should be offered on the form',
      );
    }

    // Select the heaviest level and save the day.
    await tester.ensureVisible(find.text('stark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stark'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.bleeding,
      Bleeding.heavy,
      reason: 'Selecting "stark" (heavy) and saving must persist level 4',
    );
  });

// ═══════════ cervix position and opening ═══════════
// former test/diary_cervix_selector_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets('Muttermund position and opening are offered and persist',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The pickers are offered with the German vocabulary (pinned locale).
    // NB "mittel" (position AND opening BOTH say it) is NOT asserted here
    // because it is ambiguous against the bleeding chip "mittel" on the
    // same form.
    expect(find.text('tief'), findsOneWidget,
        reason: 'the position options must be selectable');
    expect(find.text('sehr hoch'), findsOneWidget);
    expect(find.text('unerreichbar'), findsOneWidget);
    expect(find.text('geschlossen'), findsOneWidget,
        reason: 'the opening options must be selectable');
    expect(find.text('offen'), findsOneWidget);

    // Select a disambiguating combination: position tief, opening offen.
    await tester.ensureVisible(find.text('tief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('offen'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.cervixPosition, CervixPosition.low.name,
        reason: 'the selected position (tief) must persist');
    expect(row.cervixOpening, CervixOpening.open.name,
        reason: 'the selected opening (offen) must persist');
  });

// ═══════════ pain options (B, M) ═══════════
// former test/diary_pain_selector_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets('pain options B and M are offered and survive the save path',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();

    // Both options offered on the entry form (German labels, per the
    // pinned locale), each carrying its letter code.
    expect(find.text('Brustschmerzen (B)'), findsOneWidget,
        reason: 'the breast-pain (B) option must be selectable');
    expect(find.text('Mittelschmerz (M)'), findsOneWidget,
        reason: 'the Mittelschmerz (M) option must be selectable');

    // Select breast and Mittelschmerz together, then breast only.
    await tester.ensureVisible(find.text('Brustschmerzen (B)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brustschmerzen (B)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittelschmerz (M)'));
    await tester.pumpAndSettle();
    // Tapping the selected breast chip again deselects it (chip toggle,
    // same semantics as the bleeding chips).
    await tester.tap(find.text('Brustschmerzen (B)'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.painMittelschmerz, isTrue,
        reason: 'the selected M option must persist');
    expect(row.painBreast, isFalse,
        reason: 'deselecting B must clear it independently of M');
  });

// ═══════════ firmness and sex timing ═══════════
// former test/diary_firmness_sex_timing_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

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
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
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

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.cervixFirmness, isNull,
        reason: 'a deselected firmness must persist as no observation');
  });

  testWidgets(
      'sex time slots are a multi-select: several chips persist as '
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

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
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

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(row!.sexTimings, 4,
        reason: 'the re-tapped middle slot must be cleared; Ende (bit 4) '
            'stays');
  });
}
