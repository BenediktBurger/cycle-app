// Widget tests of the Tagebuch screen's time and navigation behavior —
// the whole family in one file: the measured-time picker (conditional
// visibility, prefill, round-trip, clearing, day-tile display), the
// previous/next day chevrons (with their edit-discard semantics) and the
// cycle-start suggestion prompt (the disturbance flags' analysis-exclusion
// marking works without any auto behavior — see
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
        selectedDay: selectedDay);

/// The BBT field is the first form field; its controller text is the
/// round-trip signal for "which day's entry is loaded".
String _bbtText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byType(TextFormField).first)
    .controller!
    .text;

String _dayLabel(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day).toLocal());

/// The navigation IconButton for [icon] — widgetWithIcon so the cast sees
/// the IconButton itself, not the bare Icon inside it.
IconButton _chevron(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

// Widget tests for the cycle-start suggestion on the Tagebuch screen: after
// saving a day whose bleeding SUGGESTS a cycle start (menstruation-level
// bleeding on a not-interrupted day that does not continue the previous
// day's menstruation-level bleeding — see isSuggestedCycleStart in
// lib/domain/cycle_grouping.dart), the app asks "Neuen Zyklus beginnen?" /
// "Start new cycle?" and, on confirmation, places the authoritative
// cycleStart mark through the MarksDao. Bleeding never creates a boundary
// by itself — the user still places the mark (ADR-0008).
//
// Covered: the prompt appears only for a SUGGESTED menstruation-level day
// (level >= 2), confirming persists the user-authored mark, dismissing
// persists nothing, a level-1 day (spotting) prompts nothing, a
// menstruation-level day that continues the previous day's bleeding
// (mid-flow) prompts nothing, the prompt is keyed PURELY to bleeding
// continuity: the ignoreTemperature mark does NOT suppress it any more
// (owner decision 2026-09-18 — the mark is temperature-evaluation-scoped;
// a marked bleeding day still prompts and still places the cycleStart),
// and a day that ALREADY carries the cycleStart mark re-saves without the
// prompt re-firing (the mark decides the cycle boundary — no repeat ask).
//
// The database is an in-memory override, same pattern as the
// measured-time section; the German locale is pinned so the
// dialog wording assertions stay deterministic.

// Selected calendar day of the entry form.
final _day = DateTime.utc(2026, 9, 15);
final _previousDay = DateTime.utc(2026, 9, 14);

final _promptHarness = DiaryHarness(
  now: DateTime(2026, 9, 15, 10, 30),
  selectedDay: _day,
);

void main() {
// ═══════════ measured time ═══════════
// former test/diary_measured_time_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  /// Types into the temperature field (the first form field) and lets the
  /// controller listener rebuild the form (the time row's visibility
  /// follows the temperature).
  Future<void> enterTemperature(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextFormField).first, text);
    await tester.pumpAndSettle();
  }

  testWidgets('the time row appears only once a temperature is entered',
      (WidgetTester tester) async {
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    expect(find.text('Gemessen um'), findsNothing,
        reason: 'without a temperature there is no measurement time to '
            'record — the picker row stays hidden');
    expect(find.text('14:35'), findsNothing);

    await enterTemperature(tester, '36.5');

    expect(find.text('Gemessen um'), findsOneWidget,
        reason: 'with a temperature the picker row becomes visible');
    expect(find.text('14:35'), findsOneWidget,
        reason: 'the picker button shows the injected current time as the '
            'prefill');
  });

  testWidgets('an implausible temperature keeps the time row hidden',
      (WidgetTester tester) async {
    // The row mirrors the validator's plausibility gate (isWithinBbtRange):
    // "999" parses as a number but can never be saved as a temperature, so
    // no measurement time may be recorded for it.
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '999');

    expect(find.text('Gemessen um'), findsNothing,
        reason: 'a temperature outside the BBT range can never be saved, '
            'so there is nothing to record a measurement time for');
  });

  testWidgets('a stored time stays on re-open for editing (no re-prefill)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_measuredTimeHarness.scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _measuredTimeHarness.selectedDay,
        bbtC: 36.4,
        measuredAtMinutes: 407, // 06:47 — measured in the early morning
      ));
    }));
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);
    // The injected "now" (14:35) must NOT overwrite the stored morning time.
    expect(find.text('14:35'), findsNothing);
  });

  testWidgets('clearing the time is possible and stores null',
      (WidgetTester tester) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _measuredTimeHarness.selectedDay,
        bbtC: 36.4,
        measuredAtMinutes: 407,
      ));
    }));
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget);

    // The clear affordance is the trailing close button of the time row.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('06:47'), findsNothing);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao
        .entryFor(_measuredTimeHarness.selectedDay))!;
    expect(stored.bbtC, 36.4, reason: 'the temperature itself is kept');
    expect(stored.measuredAtMinutes, isNull,
        reason: 'a day without time entry is legal; nothing is invented');
  });

  testWidgets(
      'a temperature-less save stores no time, even after the '
      'prefill was shown', (WidgetTester tester) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    // The user starts typing a temperature (the time row appears with the
    // current-time prefill), then removes the temperature again — e.g. the
    // thermometer showed an unusable value — and saves the mucus-only day.
    await enterTemperature(tester, '36.5');
    expect(find.text('Gemessen um'), findsOneWidget);
    await enterTemperature(tester, '');
    // Mucus sign S so the day is a real, meaningful entry (not an empty
    // form save).
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao
        .entryFor(_measuredTimeHarness.selectedDay))!;
    expect(stored.bbtC, isNull);
    expect(stored.mucusSign, 's');
    expect(stored.measuredAtMinutes, isNull,
        reason: 'the time is only stored together with a temperature — '
            'the prefilled current time must not leak into the row');
  });

  testWidgets('saving a temperature stores the (prefilled) time with it',
      (WidgetTester tester) async {
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '36.5');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stored = (await _measuredTimeHarness.db!.entriesDao
        .entryFor(_measuredTimeHarness.selectedDay))!;
    expect(stored.bbtC, 36.5);
    expect(stored.measuredAtMinutes, 14 * 60 + 35, // the injected "now"
        reason: 'a temperature with the prefilled measurement time stores '
            'the time');
  });

  testWidgets('the day tile shows the stored time',
      (WidgetTester tester) async {
    // The time lives on a DIFFERENT day than the selected one, so the only
    // possible source of the string is the tile, not the form.
    _measuredTimeHarness.tallSurface(tester);
    await tester.pumpWidget(_measuredTimeHarness.scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime(2026, 1, 5),
        bbtC: 36.4,
        measuredAtMinutes: 407,
      ));
    }));
    await tester.pumpAndSettle();

    // The cycle-group tiles start collapsed; open the group first.
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(find.text('06:47'), findsOneWidget,
        reason: 'the measured time appears on the day tile');
  });

// ═══════════ day navigation ═══════════
// former test/diary_day_navigation_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'next/previous change the loaded day and its entry, back and forth',
      (WidgetTester tester) async {
    await tester.pumpWidget(_dayNavScope(selectedDay: _day1));
    await tester.pumpAndSettle();

    expect(_bbtText(tester), '36.4',
        reason: 'the form opens on the seeded first day');
    expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day1)), findsOneWidget);

    // Next: the form moves to the adjacent day and loads ITS entry.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(selectedDateProvider), _day2,
        reason: 'the next button moves the selection one day forward');
    expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day2)), findsOneWidget,
        reason: 'the date button shows the new day');
    expect(_bbtText(tester), '36.9',
        reason: 'the new day\'s entry is loaded into the form');

    // Previous: back to the first day, its entry reloaded.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(container.read(selectedDateProvider), _day1);
    expect(
        find.widgetWithText(OutlinedButton, _dayLabel(_day1)), findsOneWidget);
    expect(_bbtText(tester), '36.4');

    // The chevron buttons carry localized tooltips (German pinned locale).
    expect(_chevron(tester, Icons.chevron_left).tooltip, 'Voriger Tag');
    expect(_chevron(tester, Icons.chevron_right).tooltip, 'Nächster Tag');
  });

  testWidgets('next is disabled at the date-picker\'s last day (tomorrow)',
      (WidgetTester tester) async {
    // The picker window (see _pickDate) ends at now + 1 day: selecting
    // tomorrow must not offer a next day — no unbounded future.
    final tomorrow = DateOnly.addDays(_dayNavNow, 1);
    await tester.pumpWidget(_dayNavScope(selectedDay: tomorrow));
    await tester.pumpAndSettle();

    final nextButton = _chevron(tester, Icons.chevron_right);
    expect(nextButton.onPressed, isNull,
        reason: 'beyond tomorrow the next button must be disabled');

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), tomorrow,
        reason: 'a disabled button must not move the selection');
    expect(_bbtText(tester), '',
        reason: 'tomorrow has no stored entry — the fresh day stays loaded');

    // Previous stays available from there (moving back is in-window).
    expect(_chevron(tester, Icons.chevron_left).onPressed, isNotNull);
  });

  testWidgets('previous is disabled at the date-picker\'s first day (2000)',
      (WidgetTester tester) async {
    final firstDay = DateOnly.normalize(DateTime(2000));
    await tester.pumpWidget(_dayNavScope(selectedDay: firstDay));
    await tester.pumpAndSettle();

    expect(_chevron(tester, Icons.chevron_left).onPressed, isNull,
        reason: 'before 2000 the previous button must be disabled, '
            'mirroring the date picker\'s firstDate');

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(container.read(selectedDateProvider), firstDay,
        reason: 'a disabled button must not move the selection');

    // Next stays available from there (moving forward is in-window).
    expect(_chevron(tester, Icons.chevron_right).onPressed, isNotNull);
  });

  testWidgets('navigating away discards unsaved edits (explicit save only)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_dayNavScope(selectedDay: _day1));
    await tester.pumpAndSettle();

    expect(_bbtText(tester), '36.4');

    // The user types a new temperature but does NOT save.
    await tester.enterText(find.byType(TextFormField).first, '39.9');
    await tester.pumpAndSettle();

    // Navigating away loads the next day fresh — the unsaved edit is gone
    // from the form, same semantics as a list-tile tap or a date-picker
    // change.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(_bbtText(tester), '36.9',
        reason: 'the next day loads fresh, not with the unsaved edit');

    // Coming back shows the STORED value, not the discarded edit.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(_bbtText(tester), '36.4',
        reason: 'the discarded edit never reached the database');

    final stored1 = await _dayNavHarness.db!.entriesDao.entryFor(_day1);
    final stored2 = await _dayNavHarness.db!.entriesDao.entryFor(_day2);
    expect(stored1!.bbtC, 36.4,
        reason: 'navigation must not write the unsaved edit');
    expect(stored2!.bbtC, 36.9);
  });

// ═══════════ cycle-start prompt ═══════════
// former test/diary_cycle_start_prompt_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'a suggested menstruation-level day prompts for the cycle start; '
      'confirming places the cycleStart mark', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope());
    await tester.pumpAndSettle();

    // First recorded day, bleeding "leicht" (level 2): already
    // menstruation-level, so the suggestion predicate flags it as a cycle
    // start — the prompt does not wait for the central levels.
    await _promptHarness.saveWithBleeding(tester, 'leicht');

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'a suggested menstruation-level day asks for the cycle '
            'start instead of placing the mark silently');
    expect(find.text('Neuen Zyklus beginnen?'), findsOneWidget,
        reason: 'the prompt names the suggestion in the pinned locale');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zyklusbeginn setzen')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'confirming closes the prompt');
    final marks = await _promptHarness.db!.marksDao.marksForDay(_day);
    expect(marks.map((m) => m.markType), contains(CycleMarkTypes.cycleStart),
        reason: 'the confirmed suggestion places the authoritative '
            'cycle-boundary mark through the MarksDao');
    final mark =
        marks.singleWhere((m) => m.markType == CycleMarkTypes.cycleStart);
    expect(mark.author, 'user',
        reason: 'the confirmed placement is user-authored');
  });

  testWidgets('dismissing the prompt places no mark', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope());
    await tester.pumpAndSettle();

    await _promptHarness.saveWithBleeding(tester, 'stark');

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Nicht jetzt')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'dismissing closes the prompt');
    expect(await _promptHarness.storedMarkTypes(_day), isEmpty,
        reason: 'dismissing must not place the mark — bleeding only '
            'suggests, the user decides');
  });

  testWidgets('a spotting day (level 1) shows no prompt', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope());
    await tester.pumpAndSettle();

    await _promptHarness.saveWithBleeding(tester, 'Schmierblutung');

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'only menstruation-level bleeding (level >= 2) suggests a '
            'cycle start — spotting does not');
    expect(await _promptHarness.storedMarkTypes(_day), isEmpty);
  });

  testWidgets(
      'a menstruation-level day continuing the previous day\'s bleeding '
      '(mid-flow) shows no prompt', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope(seed: (db) async {
      // The previous calendar day already carries an uninterrupted
      // menstruation-level bleeding day: the saved day is mid-flow.
      await db.entriesDao.upsertDaily(DailyEntry(
        date: _previousDay,
        bleeding: Bleeding.medium,
      ));
    }));
    await tester.pumpAndSettle();

    await _promptHarness.saveWithBleeding(tester, 'stark');

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'fresh menstruation starts after a break or on the first '
            'day — a continuous menstruation is mid-flow, not a new start');
    expect(await _promptHarness.storedMarkTypes(_day), isEmpty);
  });

  testWidgets(
      'a suggested day that already carries the cycleStart mark shows no '
      'prompt (no re-fire on re-save)', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope(seed: (db) async {
      // The user already confirmed the cycle start on this day: re-saving
      // the still-suggested bleeding day must not ask again — the mark is
      // the authoritative boundary and stays untouched.
      await db.marksDao.addMark(
        _day,
        CycleMarkTypes.cycleStart,
        author: 'user',
      );
    }));
    await tester.pumpAndSettle();

    await _promptHarness.saveWithBleeding(tester, 'leicht');

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'the cycleStart mark is already on the day — the prompt '
            'must not re-fire on a re-save');
    expect(await _promptHarness.storedMarkTypes(_day),
        equals([CycleMarkTypes.cycleStart]),
        reason: 'the pre-existing cycleStart mark stays exactly as it was');
  });

  testWidgets(
      'an ignoreTemperature mark on the day does NOT suppress the prompt '
      '(a marked bleeding day still suggests)', (tester) async {
    _promptHarness.tallSurface(tester);
    await tester.pumpWidget(_promptHarness.scope(seed: (db) async {
      // The day already carries the temperature-ignore mark: that mark is
      // scoped to the temperature evaluation and must not swallow the
      // cycle-start suggestion — the suppression is keyed purely to
      // bleeding continuity.
      await db.marksDao.addMark(
        _day,
        CycleMarkTypes.ignoreTemperature,
        author: 'user',
      );
    }));
    await tester.pumpAndSettle();

    await _promptHarness.saveWithBleeding(tester, 'leicht');

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'the ignoreTemperature mark no longer suppresses the '
            'suggestion — the marked bleeding day still asks');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zyklusbeginn setzen')));
    await tester.pumpAndSettle();

    final marks = await _promptHarness.db!.marksDao.marksForDay(_day);
    expect(
        marks.map((m) => m.markType),
        unorderedEquals([
          CycleMarkTypes.ignoreTemperature,
          CycleMarkTypes.cycleStart,
        ]),
        reason: 'confirming places the cycleStart mark; the pre-existing '
            'ignoreTemperature mark stays untouched (the form\'s exclude '
            'switch seeds from the existing mark, so the plain save keeps '
            'it — no auto behavior in either direction)');
    final start =
        marks.singleWhere((m) => m.markType == CycleMarkTypes.cycleStart);
    expect(start.author, 'user',
        reason: 'the confirmed placement is user-authored even on a '
            'marked day');
  });
}
