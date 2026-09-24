// Widget tests of the Tagebuch screen's time and navigation behavior —
// the whole family in one file: the measured-time picker (conditional
// visibility, prefill, round-trip, clearing, day-tile display), the
// previous/next day chevrons (with their edit-discard semantics) and the
// entry form's explicit cycle-start switch (the disturbance flags'
// analysis-exclusion marking works without any auto behavior — see
// test/diary_temperature_exclude_group_test.dart's manual exclude switch).
//
// Each section below (kicked off by a `════ former` banner) carries
// the former file's header comments verbatim; test bodies were
// concatenated, not rewritten. Colliding top-level names (`harness`,
// `_fixedNow`) were prefixed per former file.

// No assertion was edited: run the full gate and diff the collected
// test names against the pre-merge report — only the suite-path
// prefix changed.

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'support/diary_harness.dart';
import 'support/finders.dart';
import 'support/viewport.dart';
import 'support/error_collector.dart';

// Widget tests for the time-of-measurement feature on the Tagebuch screen.
//
// The measurement time is metadata OF the temperature: the picker row only
// appears while a temperature is entered, and a save without a temperature
// stores no time (the domain model normalizes — see
// test/domain/daily_entry_test.dart). Covered here: the conditional
// visibility with the current-time prefill once a temperature is entered, a
// stored time stays when the day is re-opened for editing, clearing the
// time is possible, a temperature-less save keeps no time, and the day
// tiles show the stored time.
//
// The clock is pinned through the nowProvider override (the real wall clock
// would make the prefill assertion race with the minute boundary); the
// database is an in-memory override, same pattern as test/app_shell_test.dart.
// The German locale is pinned (like the sibling widget tests) so the 24 h
// format assertions stay deterministic.

// Injected "now" for every test in this file.
final _measuredTimeNow = DateTime(2026, 4, 10, 14, 35); // 14:35

final _measuredTimeHarness = DiaryHarness(now: _measuredTimeNow);

// Widget tests for the previous/next day navigation on the Tagebuch entry
// form: the chevron buttons beside the date button must move the form to
// the adjacent calendar day and load that day's entry, be disabled outside
// the date-picker window (nothing before 2000, nothing beyond tomorrow),
// and discard unsaved edits like every other day-change path (the form
// only persists on the explicit save button).
//
// In-memory drift database + pinned clock (nowProvider) and pinned selected
// day (selectedDateProvider override), same pattern as
// the measured-time section. The German locale is pinned so the date
// label and tooltip assertions stay deterministic.

// Injected "now" for every test in this file.
final _dayNavNow = DateTime(2026, 4, 10, 14, 35); // Friday, 10.4.2026

// The two days the form navigates between (both before "today" so the
// cycle-group tiles can render them as recorded days).
final _day1 = DateOnly.normalize(DateTime(2026, 4, 8));
final _day2 = DateOnly.normalize(DateTime(2026, 4, 9));

final _dayNavHarness = DiaryHarness(now: _dayNavNow);

ProviderScope _dayNavScope({required DateTime selectedDay}) =>
    _dayNavHarness.scope(
      seed: (db) async {
        // Two adjacent days with distinct temperatures: the form must show
        // the one belonging to the currently selected day.
        await db.entriesDao.upsertDaily(DailyEntry(date: _day1, bbtC: 36.4));
        await db.entriesDao.upsertDaily(DailyEntry(date: _day2, bbtC: 36.9));
      },
      selectedDay: selectedDay,
    );

/// The BBT field is the first form field; its controller text is the
/// round-trip signal for "which day's entry is loaded".
String _bbtText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byType(TextFormField).first)
    .controller!
    .text;

// No host-timezone shifting: the label is host-TZ-independent because the
// diary formats the UTC-midnight dates verbatim, each read by its own
// fields.
String _dayLabel(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day));

/// The navigation IconButton for [icon] — widgetWithIcon so the cast sees
/// the IconButton itself, not the bare Icon inside it.
IconButton _chevron(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

// Widget tests for the ENTRY FORM'S EXPLICIT CYCLE-START SWITCH on the
// Tagebuch screen: the switch (shared "Zyklusbeginn" label) is the
// diary-side writer of the authoritative cycleStart mark — toggling it on
// and saving places the mark (author 'user'), toggling it off and saving
// removes it, and the switch seeds from the day's existing mark so an
// untouched save keeps it (same contract as the exclude switch — see
// test/diary_temperature_exclude_group_test.dart). Bleeding never implies
// or asks for a cycle start on the diary anymore: saving a
// menstruation-level day WITHOUT touching the switch places no mark and
// shows no dialog.
//
// Covered: the switch is labeled "Zyklusbeginn" in the form, the
// on/off -> mark write/remove in both directions, the seeding from an
// externally placed (pre-seeded) mark, the no-mark no-dialog regression
// pin on a suggested bleeding day, and the coexistence with an
// ignoreTemperature mark (both marks survive one save).
//
// The database is an in-memory override, same pattern as the
// measured-time section; the German locale is pinned so the
// switch-label assertion stays deterministic.

// Selected calendar day of the entry form.
final _day = DateTime.utc(2026, 9, 15);

final _toggleHarness = DiaryHarness(
  now: DateTime(2026, 9, 15, 10, 30),
  selectedDay: _day,
);

/// The cycle-start switch of the entry form (test-visible key).
Finder get _cycleStartSwitch =>
    find.byKey(const ValueKey('diaryCycleStartSwitch'));

/// The current value of the cycle-start switch, read from its widget.
bool _cycleStartSwitchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_cycleStartSwitch).value;

void main() {
  // ═══════════ measured time ═══════════
  // former test/diary_measured_time_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  /// Types into the temperature field (the first form field) and lets the
  /// controller listener rebuild the form (the time row's visibility
  /// follows the temperature).
  Future<void> enterTemperature(WidgetTester tester, String text) async {
    await tester.enterText(diaryTemperatureField(), text);
    await tester.pumpAndSettle();
  }

  testWidgets('the time row appears only once a temperature is entered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    // The time row's visibility rides on the keyed picker button: both the
    // label and the button exist only while the temperature is plausible.
    expect(
      measuredTimeField(),
      findsNothing,
      reason:
          'without a temperature there is no measurement time to '
          'record — the picker row stays hidden',
    );
    expect(find.text('14:35'), findsNothing);

    await enterTemperature(tester, '36.5');

    expect(
      measuredTimeField(),
      findsOneWidget,
      reason: 'with a temperature the picker row becomes visible',
    );
    expect(
      find.text('14:35'),
      findsOneWidget,
      reason:
          'the picker button shows the injected current time as the '
          'prefill',
    );
  });

  testWidgets(
    'compact density: the temperature field and the measured-time row '
    'share one visual line',
    (WidgetTester tester) async {
      _measuredTimeHarness.tallSurface(tester);
      await tester.pumpWidget(_measuredTimeHarness.scope());
      await tester.pumpAndSettle();

      await enterTemperature(tester, '36.5');

      // The measured-time label must sit INSIDE the vertical span of the
      // temperature field (beside it), not below it in its own row.
      final tempField = find.byType(TextFormField).first;
      final tempTop = tester.getTopLeft(tempField).dy;
      final tempBottom = tester.getBottomRight(tempField).dy;
      // Deliberate: this geometry pins the label's rect, not the control.
      final timeTop = tester.getTopLeft(find.text('Gemessen um')).dy;
      expect(
        timeTop,
        inInclusiveRange(tempTop, tempBottom),
        reason:
            'the temperature field and the measured-time row share one '
            'visual line — the time row is not stacked below the field',
      );
    },
  );

  testWidgets(
    'the one-line temperature/time row stays overflow-free at a narrow '
    'viewport',
    (WidgetTester tester) async {
      useNarrowPhoneViewport(tester);

      await tester.pumpWidget(_measuredTimeHarness.scope());
      await tester.pumpAndSettle();

      // Waive the pump-time record: at this forced width, widget-test font
      // metrics can overflow OTHER rows of the tall form once at the initial
      // layout — e.g. the date row (a documented, still-open narrow-width
      // defect of that row, not this one). Everything that fails from here
      // on, during the temperature/time interaction, belongs to the one-line
      // row and must stay silent.
      tester.takeException();

      await expectNoFrameworkErrors(
        tester,
        () async {
          await enterTemperature(tester, '36.5');
          // At this width the printed label drops (it is the widest part of
          // the line); the control stays through icon, time button and the
          // prefill.
          expect(
            find.text('Gemessen um'),
            findsNothing,
            reason:
                'narrow-width layout drops the printed label (documented '
                'behavior) — it is the widest part of the line',
          );
          expect(
            find.text('14:35'),
            findsOneWidget,
            reason:
                'the one-line row still renders the time control with the '
                'prefilled current time at the narrow width',
          );
          expect(
            find.byIcon(Icons.schedule_outlined),
            findsOneWidget,
            reason:
                'the clock icon keeps carrying the meaning at narrow '
                'widths',
          );
        },
        reason:
            'the compact temperature/time row must not introduce a new '
            'RenderFlex overflow at narrow widths',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an implausible temperature keeps the time row hidden', (
    WidgetTester tester,
  ) async {
    // The row mirrors the validator's plausibility gate (isWithinBbtRange):
    // "999" parses as a number but can never be saved as a temperature, so
    // no measurement time may be recorded for it.
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '999');

    expect(
      measuredTimeField(),
      findsNothing,
      reason:
          'a temperature outside the BBT range can never be saved, '
          'so there is nothing to record a measurement time for',
    );
  });

  testWidgets('a stored time stays on re-open for editing (no re-prefill)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _measuredTimeHarness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: _measuredTimeHarness.selectedDay,
              bbtC: 36.4,
              measuredAtMinutes: 407, // 06:47 — measured in the early morning
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);
    // The injected "now" (14:35) must NOT overwrite the stored morning time.
    expect(find.text('14:35'), findsNothing);
  });

  testWidgets('clearing the time is possible and stores null', (
    WidgetTester tester,
  ) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(
      _measuredTimeHarness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: _measuredTimeHarness.selectedDay,
              bbtC: 36.4,
              measuredAtMinutes: 407,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);

    // The clear affordance is the trailing close button of the time row.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('06:47'), findsNothing);

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao.entryFor(
      _measuredTimeHarness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.4, reason: 'the temperature itself is kept');
    expect(
      stored.measuredAtMinutes,
      isNull,
      reason: 'a day without time entry is legal; nothing is invented',
    );
  });

  testWidgets('a temperature-less save stores no time, even after the '
      'prefill was shown', (WidgetTester tester) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    // The user starts typing a temperature (the time row appears with the
    // current-time prefill), then removes the temperature again — e.g. the
    // thermometer showed an unusable value — and saves the mucus-only day.
    await enterTemperature(tester, '36.5');
    expect(measuredTimeField(), findsOneWidget);
    await enterTemperature(tester, '');
    // Mucus sign S so the day is a real, meaningful entry (not an empty
    // form save).
    await tester.tap(diaryChip('mucusSign', 's'));
    await tester.pumpAndSettle();

    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao.entryFor(
      _measuredTimeHarness.selectedDay,
    ))!;
    expect(stored.bbtC, isNull);
    expect(stored.mucusSign, 's');
    expect(
      stored.measuredAtMinutes,
      isNull,
      reason:
          'the time is only stored together with a temperature — '
          'the prefilled current time must not leak into the row',
    );
  });

  testWidgets('saving a temperature stores the (prefilled) time with it', (
    WidgetTester tester,
  ) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '36.5');
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao.entryFor(
      _measuredTimeHarness.selectedDay,
    ))!;
    expect(stored.bbtC, 36.5);
    expect(
      stored.measuredAtMinutes,
      14 * 60 + 35, // the injected "now"
      reason:
          'a temperature with the prefilled measurement time stores '
          'the time',
    );
  });

  testWidgets('the day tile shows the stored time', (
    WidgetTester tester,
  ) async {
    // The time lives on a DIFFERENT day than the selected one, so the only
    // possible source of the string is the tile, not the form.
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(
      _measuredTimeHarness.scope(
        seed: (db) async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 1, 5),
              bbtC: 36.4,
              measuredAtMinutes: 407,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // The cycle-group tiles start collapsed; open the group first.
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(
      find.text('06:47'),
      findsOneWidget,
      reason: 'the measured time appears on the day tile',
    );
  });

  // ═══════════ day navigation ═══════════
  // former test/diary_day_navigation_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets(
    'next/previous change the loaded day and its entry, back and forth',
    (WidgetTester tester) async {
      await tester.pumpWidget(_dayNavScope(selectedDay: _day1));
      await tester.pumpAndSettle();

      expect(
        _bbtText(tester),
        '36,4',
        reason:
            'the form opens on the seeded first day, '
            'comma-prefilled (display follows the locale)',
      );
      expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day1)),
        findsOneWidget,
      );

      // Next: the form moves to the adjacent day and loads ITS entry.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TagebuchScreen));
      final container = ProviderScope.containerOf(context);
      expect(
        container.read(selectedDateProvider),
        _day2,
        reason: 'the next button moves the selection one day forward',
      );
      expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day2)),
        findsOneWidget,
        reason: 'the date button shows the new day',
      );
      expect(
        _bbtText(tester),
        '36,9',
        reason:
            'the new day\'s entry is loaded into the form '
            '(comma-prefilled — display follows the locale)',
      );

      // Previous: back to the first day, its entry reloaded.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(container.read(selectedDateProvider), _day1);
      expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day1)),
        findsOneWidget,
      );
      expect(_bbtText(tester), '36,4');

      // The chevron buttons carry localized tooltips (German pinned locale).
      expect(_chevron(tester, Icons.chevron_left).tooltip, 'Voriger Tag');
      expect(_chevron(tester, Icons.chevron_right).tooltip, 'Nächster Tag');
    },
  );

  testWidgets('next is disabled at the date-picker\'s last day (tomorrow)', (
    WidgetTester tester,
  ) async {
    // The picker window (see _pickDate) ends at now + 1 day: selecting
    // tomorrow must not offer a next day — no unbounded future.
    final tomorrow = DateOnly.addDays(_dayNavNow, 1);
    await tester.pumpWidget(_dayNavScope(selectedDay: tomorrow));
    await tester.pumpAndSettle();

    final nextButton = _chevron(tester, Icons.chevron_right);
    expect(
      nextButton.onPressed,
      isNull,
      reason: 'beyond tomorrow the next button must be disabled',
    );

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      container.read(selectedDateProvider),
      tomorrow,
      reason: 'a disabled button must not move the selection',
    );
    expect(
      _bbtText(tester),
      '',
      reason: 'tomorrow has no stored entry — the fresh day stays loaded',
    );

    // Previous stays available from there (moving back is in-window).
    expect(_chevron(tester, Icons.chevron_left).onPressed, isNotNull);
  });

  testWidgets('previous is disabled at the date-picker\'s first day (2000)', (
    WidgetTester tester,
  ) async {
    final firstDay = DateOnly.normalize(DateTime(2000));
    await tester.pumpWidget(_dayNavScope(selectedDay: firstDay));
    await tester.pumpAndSettle();

    expect(
      _chevron(tester, Icons.chevron_left).onPressed,
      isNull,
      reason:
          'before 2000 the previous button must be disabled, '
          'mirroring the date picker\'s firstDate',
    );

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(
      container.read(selectedDateProvider),
      firstDay,
      reason: 'a disabled button must not move the selection',
    );

    // Next stays available from there (moving forward is in-window).
    expect(_chevron(tester, Icons.chevron_right).onPressed, isNotNull);
  });

  testWidgets('navigating away discards unsaved edits (explicit save only)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dayNavScope(selectedDay: _day1));
    await tester.pumpAndSettle();

    expect(_bbtText(tester), '36,4');

    // The user types a new temperature but does NOT save.
    await tester.enterText(diaryTemperatureField(), '39.9');
    await tester.pumpAndSettle();

    // Navigating away loads the next day fresh — the unsaved edit is gone
    // from the form, same semantics as a list-tile tap or a date-picker
    // change.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(
      _bbtText(tester),
      '36,9',
      reason: 'the next day loads fresh, not with the unsaved edit',
    );

    // Coming back shows the STORED value, not the discarded edit.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(
      _bbtText(tester),
      '36,4',
      reason: 'the discarded edit never reached the database',
    );

    final stored1 = await _dayNavHarness.db!.entriesDao.entryFor(_day1);
    final stored2 = await _dayNavHarness.db!.entriesDao.entryFor(_day2);
    expect(
      stored1!.bbtC,
      36.4,
      reason: 'navigation must not write the unsaved edit',
    );
    expect(stored2!.bbtC, 36.9);
  });

  // ═══════════ cycle-start switch ═══════════
  // former test/diary_cycle_start_prompt_test.dart — rewritten: the
  // bleeding-suggested confirm dialog is replaced by the form's explicit
  // cycle-start switch (see the section comment above).

  testWidgets('the form offers a "Zyklusbeginn" switch, off on a fresh day', (
    tester,
  ) async {
    _toggleHarness.tallSurface(tester);
    await tester.pumpWidget(_toggleHarness.scope());
    await tester.pumpAndSettle();

    expect(
      _cycleStartSwitch,
      findsOneWidget,
      reason: 'the entry form carries the explicit cycle-start switch',
    );
    expect(
      find.descendant(
        of: _cycleStartSwitch,
        matching: find.text('Zyklusbeginn'),
      ),
      findsOneWidget,
      reason:
          'the switch reuses the shared surface name "Zyklusbeginn" '
          '(the day sheet\'s mark chip label) in the pinned locale',
    );
    expect(
      _cycleStartSwitchValue(tester),
      isFalse,
      reason: 'a fresh day without a cycleStart mark loads the switch off',
    );
  });

  testWidgets(
    'toggling the switch on and saving places a user-authored cycleStart '
    'mark',
    (tester) async {
      _toggleHarness.tallSurface(tester);
      await tester.pumpWidget(_toggleHarness.scope());
      await tester.pumpAndSettle();

      expect(
        await _toggleHarness.storedMarkTypes(_day),
        isEmpty,
        reason: 'guard: a fresh day carries no marks',
      );

      await tester.tap(_cycleStartSwitch);
      await tester.pumpAndSettle();
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final marks = await _toggleHarness.db!.marksDao.marksForDay(_day);
      expect(
        marks.map((m) => m.markType),
        contains(CycleMarkTypes.cycleStart),
        reason:
            'the switched-on save writes the authoritative '
            'cycle-boundary mark through the MarksDao',
      );
      final mark = marks.singleWhere(
        (m) => m.markType == CycleMarkTypes.cycleStart,
      );
      expect(
        mark.author,
        'user',
        reason:
            'the diary save is user-placed data — the mark is '
            'user-authored',
      );
    },
  );

  testWidgets('toggling the switch off and saving REMOVES a pre-existing '
      'cycleStart mark (both directions)', (tester) async {
    _toggleHarness.tallSurface(tester);
    await tester.pumpWidget(
      _toggleHarness.scope(
        seed: (db) async {
          await db.marksDao.addMark(
            _day,
            CycleMarkTypes.cycleStart,
            author: 'user',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _cycleStartSwitchValue(tester),
      isTrue,
      reason: 'the switch seeds from the day\'s existing cycleStart mark',
    );

    await tester.tap(_cycleStartSwitch);
    await tester.pumpAndSettle();
    await tester.tap(diarySaveButton());
    await tester.pumpAndSettle();

    expect(
      await _toggleHarness.storedMarkTypes(_day),
      isEmpty,
      reason:
          'the switch off -> save removes the mark in the same save '
          'the on-direction writes it (the explicit toggle decides, '
          'never an auto rule)',
    );
  });

  testWidgets(
    'a pre-seeded cycleStart mark loads the switch on and an untouched '
    'save keeps the mark exactly as it was',
    (tester) async {
      _toggleHarness.tallSurface(tester);
      await tester.pumpWidget(
        _toggleHarness.scope(
          seed: (db) async {
            await db.marksDao.addMark(
              _day,
              CycleMarkTypes.cycleStart,
              author: 'import',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _cycleStartSwitchValue(tester),
        isTrue,
        reason:
            'an externally placed cycleStart mark (day sheet, import) '
            'shows up as the switched-on state',
      );

      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final marks = await _toggleHarness.db!.marksDao.marksForDay(_day);
      expect(
        marks.map((m) => m.markType),
        [CycleMarkTypes.cycleStart],
        reason:
            'the untouched switch neither removes nor duplicates the '
            'pre-existing mark',
      );
      expect(
        marks.single.author,
        'import',
        reason: 'the pre-existing mark\'s provenance stays untouched',
      );
    },
  );

  testWidgets(
    'saving a suggested menstruation-level bleeding day WITHOUT touching '
    'the switch places no mark and shows no dialog',
    (tester) async {
      _toggleHarness.tallSurface(tester);
      await tester.pumpWidget(_toggleHarness.scope());
      await tester.pumpAndSettle();

      // First recorded day, bleeding "leicht" (level 2): the shared
      // suggestion predicate would flag this day as a cycle start — the
      // old prompt fired here. Bleeding no longer implies or asks for a
      // cycle start on the diary.
      await _toggleHarness.saveWithBleeding(tester, Bleeding.light);

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'no cycle-start prompt ever appears — bleeding only '
            'suggested, and the diary no longer asks',
      );
      expect(
        await _toggleHarness.storedMarkTypes(_day),
        isEmpty,
        reason:
            'a plain bleeding save places no cycleStart mark — only the '
            'explicit switch does',
      );
    },
  );

  testWidgets(
    'an ignoreTemperature-seeded day plus the switch toggled on keeps '
    'BOTH marks after one save (no coupling in either direction)',
    (tester) async {
      _toggleHarness.tallSurface(tester);
      await tester.pumpWidget(
        _toggleHarness.scope(
          seed: (db) async {
            // The day already carries the temperature-ignore mark: it is
            // scoped to the temperature evaluation and must not couple
            // with the cycle-start switch in either direction.
            await db.marksDao.addMark(
              _day,
              CycleMarkTypes.ignoreTemperature,
              author: 'user',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_cycleStartSwitch);
      await tester.pumpAndSettle();
      await tester.tap(diarySaveButton());
      await tester.pumpAndSettle();

      final marks = await _toggleHarness.db!.marksDao.marksForDay(_day);
      expect(
        marks.map((m) => m.markType),
        unorderedEquals([
          CycleMarkTypes.ignoreTemperature,
          CycleMarkTypes.cycleStart,
        ]),
        reason:
            'toggling the cycle-start on persists both marks — the '
            'cycleStart write neither removes the ignoreTemperature mark '
            'nor vice versa',
      );
      final start = marks.singleWhere(
        (m) => m.markType == CycleMarkTypes.cycleStart,
      );
      expect(
        start.author,
        'user',
        reason: 'the switch-placed cycleStart mark is user-authored',
      );
    },
  );
}
