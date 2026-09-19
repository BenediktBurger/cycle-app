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
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';

// Injected "now" for every test in this file.
final _fixedNow = DateTime(2026, 4, 10, 14, 35); // 14:35

final harness = DiaryHarness(now: _fixedNow);

void main() {
  /// Types into the temperature field (the first form field) and lets the
  /// controller listener rebuild the form (the time row's visibility
  /// follows the temperature).
  Future<void> enterTemperature(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextFormField).first, text);
    await tester.pumpAndSettle();
  }

  testWidgets('the time row appears only once a temperature is entered',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness.scope());
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
    await tester.pumpWidget(harness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '999');

    expect(find.text('Gemessen um'), findsNothing,
        reason: 'a temperature outside the BBT range can never be saved, '
            'so there is nothing to record a measurement time for');
  });

  testWidgets('a stored time stays on re-open for editing (no re-prefill)',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness.scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: harness.selectedDay,
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
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope(seed: (db) async {
      await db.entriesDao.upsertDaily(DailyEntry(
        date: harness.selectedDay,
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

    final stored = (await harness.db!.entriesDao.entryFor(harness.selectedDay))!;
    expect(stored.bbtC, 36.4, reason: 'the temperature itself is kept');
    expect(stored.measuredAtMinutes, isNull,
        reason: 'a day without time entry is legal; nothing is invented');
  });

  testWidgets(
      'a temperature-less save stores no time, even after the '
      'prefill was shown', (WidgetTester tester) async {
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope());
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

    final stored = (await harness.db!.entriesDao.entryFor(harness.selectedDay))!;
    expect(stored.bbtC, isNull);
    expect(stored.mucusSign, 's');
    expect(stored.measuredAtMinutes, isNull,
        reason: 'the time is only stored together with a temperature — '
            'the prefilled current time must not leak into the row');
  });

  testWidgets('saving a temperature stores the (prefilled) time with it',
      (WidgetTester tester) async {
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope());
    await tester.pumpAndSettle();

    await enterTemperature(tester, '36.5');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stored = (await harness.db!.entriesDao.entryFor(harness.selectedDay))!;
    expect(stored.bbtC, 36.5);
    expect(stored.measuredAtMinutes, 14 * 60 + 35, // the injected "now"
        reason: 'a temperature with the prefilled measurement time stores '
            'the time');
  });

  testWidgets('the day tile shows the stored time',
      (WidgetTester tester) async {
    // The time lives on a DIFFERENT day than the selected one, so the only
    // possible source of the string is the tile, not the form.
    harness.tallSurface(tester);
    await tester.pumpWidget(harness.scope(seed: (db) async {
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
}
