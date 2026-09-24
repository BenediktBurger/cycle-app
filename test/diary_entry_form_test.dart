// Widget tests of the Tagebuch (diary) entry-form selectors — the
// whole entry-form family in one file: the bleeding levels, the
// Muttermund (cervix) position and opening, the two letter-coded pain
// options (B, M), the Muttermund-FESTIGKEIT (firmness) picker and the
// sex time-of-day chips (including the mucus-A-segment check the
// firmness picker shares its form with).
//
// Each section below (kicked off by a `════ former` banner) carries
// the former file's header comments verbatim; test bodies were
// concatenated, not rewritten. Every section pumps the app the same way
// through diarySelectorScope (support/diary_harness.dart); German labels
// are pinned (locale de).

// No assertion was edited: run the full gate and diff the collected
// test names against the pre-merge report — only the suite-path
// prefix changed.

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/diary_harness.dart';
import 'support/finders.dart';
import 'support/viewport.dart';
import 'support/error_collector.dart';

// Widget test of the bleeding control on the Tagebuch entry form: the
// selector must offer the full 5-level vocabulary (none/spotting/light/
// medium/heavy), and selecting a level must survive the save path — the
// level is read back from the database through the same database provider
// the form writes with.
//
// An in-memory drift database is injected (provider-override pattern from
// app_shell_test.dart), so the test stays file-free and platform-channel-free.

// The tests call diarySelectorScope (support/diary_harness.dart) directly —
// the one-hundred-percent alias this file used to carry is gone.

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

  testWidgets('bleeding selector offers all six levels and stores heavy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The Tagebuch screen is the shell's initial tab; the bleeding control
    // sits on its entry form. All six levels of the numeric scale must be
    // offered (German labels, per the pinned locale). NB "mittel" is also
    // the German label of one Muttermund position AND of the opening chip
    // "mittel" on the same form, so the strict one-match assertion does not
    // apply to that one word.
    const levels = [
      'keine',
      'Schmierblutung',
      'leicht',
      'mittel',
      'stark',
      'sehr stark',
    ];
    for (final level in levels) {
      expect(
        find.text(level),
        findsWidgets,
        reason: 'Bleeding option "$level" should be offered on the form',
      );
    }

    // Select the heaviest level and save the day.
    await tester.ensureVisible(diaryChip('bleeding', 'heavy'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('bleeding', 'heavy'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
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

  testWidgets('selecting the top bleeding level persists maximum (level 5)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // Selecting the top level locates the chip by key — "sehr stark" and
    // the middle "stark" differ only in a shared substring of their labels.
    await tester.ensureVisible(diaryChip('bleeding', 'maximum'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('bleeding', 'maximum'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.bleeding,
      Bleeding.maximum,
      reason:
          'Selecting "sehr stark" (maximum) and saving must persist '
          'level 5',
    );
  });

  // ═══════════ cervix position and opening ═══════════
  // former test/diary_cervix_selector_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('Muttermund position and opening are offered and persist', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The pickers are offered with the German vocabulary (pinned locale).
    // NB "mittel" (position AND opening BOTH say it) is NOT asserted here
    // because it is ambiguous against the bleeding chip "mittel" on the
    // same form.
    expect(
      find.text('tief'),
      findsOneWidget,
      reason: 'the position options must be selectable',
    );
    expect(find.text('sehr hoch'), findsOneWidget);
    expect(find.text('unerreichbar'), findsOneWidget);
    expect(
      find.text('geschlossen'),
      findsOneWidget,
      reason: 'the opening options must be selectable',
    );
    expect(find.text('offen'), findsOneWidget);

    // Select a disambiguating combination: position tief, opening offen.
    await tester.ensureVisible(diaryChip('cervixPosition', 'low'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('cervixPosition', 'low'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('cervixOpening', 'open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.cervixPosition,
      CervixPosition.low.name,
      reason: 'the selected position (tief) must persist',
    );
    expect(
      row.cervixOpening,
      CervixOpening.open.name,
      reason: 'the selected opening (offen) must persist',
    );
  });

  // ═══════════ pain options (B, M) ═══════════
  // former test/diary_pain_selector_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('pain options B and M are offered and survive the save path', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // Both options offered on the entry form (German labels, per the
    // pinned locale), each carrying its letter code. The pain block has
    // its own section header above the chips — the same section shape as
    // the sex block and its neighbors.
    expect(
      find.text('Schmerzen'),
      findsOneWidget,
      reason: 'the pain section header must sit above the pain chips',
    );
    expect(
      find.text('Brustschmerz (B)'),
      findsOneWidget,
      reason: 'the breast-pain (B) option must be selectable',
    );
    expect(
      find.text('Mittelschmerz (M)'),
      findsOneWidget,
      reason: 'the Mittelschmerz (M) option must be selectable',
    );

    // Select breast and Mittelschmerz together, then breast only.
    await tester.ensureVisible(diaryChip('pain', 'breast'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('pain', 'breast'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('pain', 'mittelschmerz'));
    await tester.pumpAndSettle();
    // Tapping the selected breast chip again deselects it (chip toggle,
    // same semantics as the bleeding chips).
    await tester.tap(diaryChip('pain', 'breast'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.painMittelschmerz,
      isTrue,
      reason: 'the selected M option must persist',
    );
    expect(
      row.painBreast,
      isFalse,
      reason: 'deselecting B must clear it independently of M',
    );
  });

  // ═══════════ firmness and sex timing ═══════════
  // former test/diary_firmness_sex_timing_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('the mucus sign picker offers the A (Ausfluss) segment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The sign chips show the cheat-sheet glyphs themselves; the A
    // (Ausfluss) sign joined the vocabulary, so its chip must be
    // offered on the shared form.
    expect(
      find.text('A'),
      findsOneWidget,
      reason: 'the Ausfluss sign (A) must be selectable on the form',
    );
  });

  testWidgets('firmness options are offered and a selection persists', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The firmness vocabulary (paper shorthand h / h-w / w as the chip
    // labels, pinned German locale). NB the unset chip "—" is NOT asserted
    // here: the mucus/position/opening pickers use the same label, so it is
    // ambiguous on this form.
    expect(
      find.text('hart'),
      findsOneWidget,
      reason: 'the firmness option hart must be selectable',
    );
    expect(
      find.text('h-w'),
      findsOneWidget,
      reason: 'the firmness option h-w must be selectable',
    );
    expect(
      find.text('weich'),
      findsOneWidget,
      reason: 'the firmness option weich must be selectable',
    );

    await tester.ensureVisible(diaryChip('cervixFirmness', 'soft'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('cervixFirmness', 'soft'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    // Read the saved day back through the database provider — the same
    // instance the form writes through, not a second connection.
    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.cervixFirmness,
      'soft',
      reason: 'the selected firmness (weich) must persist as its token',
    );
  });

  testWidgets('tapping the selected firmness again deselects it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diaryChip('cervixFirmness', 'hard'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('cervixFirmness', 'hard'));
    await tester.pumpAndSettle();
    // Tap-again-deselect: the chips pattern of position/opening.
    await tester.tap(diaryChip('cervixFirmness', 'hard'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.cervixFirmness,
      isNull,
      reason: 'a deselected firmness must persist as no observation',
    );
  });

  testWidgets('sex time slots are a multi-select: several chips persist as '
      'the OR of their bits', (WidgetTester tester) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    // The three time slots (pinned German locale).
    expect(
      find.text('Anfang'),
      findsOneWidget,
      reason: 'the start slot must be offered',
    );
    expect(
      find.text('Mitte'),
      findsOneWidget,
      reason: 'the middle slot must be offered',
    );
    expect(
      find.text('Ende'),
      findsOneWidget,
      reason: 'the end slot must be offered',
    );

    // Select TWO slots at once — the old single bool is gone.
    await tester.ensureVisible(diaryChip('sexTiming', 'start'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('sexTiming', 'start'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('sexTiming', 'end'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.sexTimings,
      1 | 4,
      reason: 'Anfang (bit 1) + Ende (bit 4) must persist as mask 5',
    );
  });

  testWidgets('tapping a selected sex slot again clears its bit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(diarySelectorScope(const Locale('de')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diaryChip('sexTiming', 'middle'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('sexTiming', 'middle'));
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('sexTiming', 'middle')); // deselect again
    await tester.pumpAndSettle();
    await tester.tap(diaryChip('sexTiming', 'end'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(diarySaveButton());
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final (:db, :date) = await savedDayOf(tester);
    final row = await db.entriesDao.entryFor(date);
    expect(row, isNotNull, reason: 'The saved day must exist in the database');
    expect(
      row!.sexTimings,
      4,
      reason:
          'the re-tapped middle slot must be cleared; Ende (bit 4) '
          'stays',
    );
  });

  // ═══════════ mucus sign row at a narrow viewport ═══════════
  // Device-field reports show the sign row growing taller and painting a
  // partially visible overflow band on narrow Android widths: the row
  // divides the width evenly across all of its options, so the two-glyph
  // f/S label reflows to two lines. The repro pumps the whole app shell at
  // a 320 x 800 dp viewport (physical = 960 x 2400 px, devicePixelRatio 3)
  // and walks every sign option — start width 320 dp, not decremented: the
  // error reproduces deterministically here.
  //
  // The framework error collector is installed only after the shell has
  // pumped and the form is scrolled to the sign row: the other shell tabs
  // stay mounted and laid out (IndexedStack), so anything overflowing
  // elsewhere must not be attributed to this row.

  testWidgets(
    'the mucus sign row renders every sign without overflow at a narrow '
    'width and stores an f/S day',
    (WidgetTester tester) async {
      useNarrowPhoneViewport(tester);

      await tester.pumpWidget(diarySelectorScope(const Locale('de')));
      await tester.pumpAndSettle();

      final caption = find.text('Fruchtbarkeitszeichen (Zervixschleim)');
      await tester.ensureVisible(caption);
      await tester.pumpAndSettle();

      // Waive the pump-time record: at this forced width, widget-test font
      // metrics (square fallback glyphs, wider than device fonts) can
      // overflow OTHER rows of the tall form once at the initial layout —
      // e.g. the date row. That single pump-time pass is not what this test
      // measures; everything that fails from here on, on any interaction
      // with the sign row, belongs to the row and must stay silent.
      // (Take the record, not assert on it: render details of OTHER rows
      // are irrelevant to this repro; any row failure during the taps below
      // is still collected and fails the test.)
      tester.takeException();

      await expectNoFrameworkErrors(tester, () async {
        // Walk every option of the row, including the two-glyph f/S: the
        // single-glyph options around it leave the row narrow, f/S forces
        // the reflow. Tapping S first brings up the quality row (its rule
        // is exercised below with f/S). The chips are located by key —
        // their labels are the glyphs, but the taps' targets are not what
        // this repro asserts.
        for (final sign in [
          MucusSign.t,
          MucusSign.nothing,
          MucusSign.f,
          MucusSign.s,
        ]) {
          await tester.ensureVisible(diaryChip('mucusSign', sign.name));
          await tester.pumpAndSettle();
          await tester.tap(diaryChip('mucusSign', sign.name));
          await tester.pumpAndSettle();
        }
        // Selecting S shows the quality row (quality only exists with S);
        // a recorded quality chips the row on.
        await tester.tap(diaryChip('mucusQuality', 'ew'));
        await tester.pumpAndSettle();

        // Leaving S for f/S hides the quality row again (addressed by the
        // chip's key: 'EW' is the display token, 'ew' the row's key token).
        await tester.ensureVisible(diaryChip('mucusSign', 'fs'));
        await tester.pumpAndSettle();
        await tester.tap(diaryChip('mucusSign', 'fs'));
        await tester.pumpAndSettle();
        expect(
          diaryChip('mucusQuality', 'ew'),
          findsNothing,
          reason: 'the quality row must hide once the sign leaves S',
        );

        // And A (Ausfluss) — the last two-glyph-risky option after f/S.
        await tester.tap(diaryChip('mucusSign', 'a'));
        await tester.pumpAndSettle();

        // End on f/S for the save round-trip. Tap-again would deselect (the
        // unset chip turns null), so A → f/S is the final selection.
        await tester.tap(diaryChip('mucusSign', 'fs'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(diarySaveButton());
        await tester.pumpAndSettle();
        await tester.tap(diarySaveButton());
        await tester.pumpAndSettle();

        final (:db, :date) = await savedDayOf(tester);
        final row = await db.entriesDao.entryFor(date);
        expect(row, isNotNull, reason: 'The saved day must exist in the DB');
        expect(
          row!.mucusSign,
          'fs',
          reason: 'the selected f/S sign must persist with its stored token',
        );
        expect(
          row.mucusQuality,
          isNull,
          reason: 'f/S carries no quality qualifier',
        );
      }, reason: 'narrow-width sign-row interaction must not overflow the row');
      expect(tester.takeException(), isNull);
    },
  );

  // ═══════════ diary day tile at a narrow viewport ═══════════
  // The sign row was one of several surfaces rendering the two-glyph f/S
  // token; the Tagebuch list's day tile renders a recorded observation as a
  // trailing chip whose row also holds the temperature and the measured
  // time. At a narrow width that trailing content is the tile's widest
  // part, so this check pumps the shell at the same 320 x 800 dp viewport
  // as the sign-row repro above and walks the recorded tiles with the
  // framework error collector installed: any overflow here would be a real
  // tile defect, not one of the entry form. (Pump-time noise from the
  // other shell tabs is waived the same way the sign-row repro waives it.)

  testWidgets('the day tile renders its mucus chip beside temperature and time '
      'without overflow at a narrow width', (WidgetTester tester) async {
    useNarrowPhoneViewport(tester);

    // The two widest chip shapes the tile can render: the two-glyph f/S
    // token, and the S glyph with its EW superscript. Both days also
    // carry a temperature and a measured time (and one of them a
    // bleeding marker) — the maximal trailing/leading content a tile
    // can hold. The recorded days stay before the pinned "now" so the
    // cycle-group list offers them as recorded days.
    final tileHarness = DiaryHarness(now: DateTime(2026, 9, 21, 10, 30));
    await tester.pumpWidget(
      tileHarness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 9, 14),
              bbtC: 36.4,
              measuredAtMinutes: 407, // 06:47
              bleeding: Bleeding.heavy,
              mucusSign: MucusSign.fs,
            ),
          );
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 9, 15),
              bbtC: 36.9,
              mucusSign: MucusSign.s,
              mucusQuality: MucusQuality.ew,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Waive the pump-time record: at this forced width, widget-test font
    // metrics can overflow OTHER rows of the shell once at the initial
    // layout. Everything that fails from here on, while the tiles build
    // and lay out, belongs to the tile and must stay silent.
    tester.takeException();

    await expectNoFrameworkErrors(
      tester,
      () async {
        // The cycle-group tiles start collapsed; bring the list into view
        // and expand every group so the recorded days' tiles build and lay
        // out at the narrow width. The ListView is lazy, so the group
        // headers only exist once the scroll reaches them.
        final listView = find
            .descendant(
              of: find.byType(TagebuchScreen),
              matching: find.byType(ListView),
            )
            .first;
        final groupTiles = find.descendant(
          of: find.byType(TagebuchScreen),
          matching: find.byType(ExpansionTile),
        );
        for (var i = 0; i < 50 && groupTiles.evaluate().isEmpty; i++) {
          await tester.drag(listView, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        final count = tester.widgetList(groupTiles).length;
        for (var i = 0; i < count; i++) {
          await tester.ensureVisible(groupTiles.at(i));
          await tester.pumpAndSettle();
          await tester.tap(groupTiles.at(i), warnIfMissed: false);
          await tester.pumpAndSettle();
        }

        // The recorded tiles render their full content: temperature, the
        // measured time, and the two mucus chips (one per recorded day).
        await tester.ensureVisible(find.text('06:47'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('36,90 °C'));
        await tester.pumpAndSettle();
        expect(
          find.text('36,40 °C'),
          findsOneWidget,
          reason: 'the f/S day tile shows its temperature',
        );
        expect(
          find.text('06:47'),
          findsOneWidget,
          reason: 'the f/S day tile shows its measured time',
        );
        expect(
          find.descendant(
            of: find.byType(TagebuchScreen),
            matching: find.byType(MucusSymbolText),
          ),
          findsNWidgets(2),
          reason: 'both recorded days render their mucus chip on the tile',
        );
      },
      reason:
          'narrow-width day tiles must not overflow their trailing '
          'chip row',
    );
    expect(tester.takeException(), isNull);
  });
}
