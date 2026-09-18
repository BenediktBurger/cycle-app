// Widget tests for the previous/next day navigation on the Tagebuch entry
// form: the chevron buttons beside the date button must move the form to
// the adjacent calendar day and load that day's entry, be disabled outside
// the date-picker window (nothing before 2000, nothing beyond tomorrow),
// and discard unsaved edits like every other day-change path (the form
// only persists on the explicit save button).
//
// In-memory drift database + pinned clock (nowProvider) and pinned selected
// day (selectedDateProvider override), same pattern as
// diary_measured_time_test.dart. The German locale is pinned so the date
// label and tooltip assertions stay deterministic.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

// Injected "now" for every test in this file.
final _fixedNow = DateTime(2026, 4, 10, 14, 35); // Friday, 10.4.2026

// The two days the form navigates between (both before "today" so the
// cycle-group tiles can render them as recorded days).
final _day1 = DateOnly.normalize(DateTime(2026, 4, 8));
final _day2 = DateOnly.normalize(DateTime(2026, 4, 9));

/// The database instance created by the scope's override (set on first
/// watch), so tests can assert what was actually STORED.
CycleDatabase? _db;

ProviderScope _scope({required DateTime selectedDay}) {
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
        // Two adjacent days with distinct temperatures: the form must show
        // the one belonging to the currently selected day.
        await db.entriesDao.upsertDaily(DailyEntry(date: _day1, bbtC: 36.4));
        await db.entriesDao.upsertDaily(DailyEntry(date: _day2, bbtC: 36.9));
        return db;
      }),
      nowProvider.overrideWith((ref) => () => _fixedNow),
      selectedDateProvider.overrideWith((ref) => selectedDay),
      localeProvider.overrideWith((ref) => const Locale('de')),
    ],
    child: const CycleApp(),
  );
}

/// The BBT field is the first form field; its controller text is the
/// round-trip signal for "which day's entry is loaded".
String _bbtText(WidgetTester tester) =>
    tester.widget<TextFormField>(find.byType(TextFormField).first)
        .controller!
        .text;

String _dayLabel(DateTime day) =>
    DateFormat.yMd('de').format(DateOnly.normalize(day).toLocal());

/// The navigation IconButton for [icon] — widgetWithIcon so the cast sees
/// the IconButton itself, not the bare Icon inside it.
IconButton _chevron(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

void main() {
  testWidgets(
      'next/previous change the loaded day and its entry, back and forth',
      (WidgetTester tester) async {
    await tester.pumpWidget(_scope(selectedDay: _day1));
    await tester.pumpAndSettle();

    expect(_bbtText(tester), '36.4',
        reason: 'the form opens on the seeded first day');
    expect(find.widgetWithText(OutlinedButton, _dayLabel(_day1)),
        findsOneWidget);

    // Next: the form moves to the adjacent day and loads ITS entry.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TagebuchScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(selectedDateProvider), _day2,
        reason: 'the next button moves the selection one day forward');
    expect(find.widgetWithText(OutlinedButton, _dayLabel(_day2)),
        findsOneWidget,
        reason: 'the date button shows the new day');
    expect(_bbtText(tester), '36.9',
        reason: 'the new day\'s entry is loaded into the form');

    // Previous: back to the first day, its entry reloaded.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(container.read(selectedDateProvider), _day1);
    expect(find.widgetWithText(OutlinedButton, _dayLabel(_day1)),
        findsOneWidget);
    expect(_bbtText(tester), '36.4');

    // The chevron buttons carry localized tooltips (German pinned locale).
    expect(_chevron(tester, Icons.chevron_left).tooltip, 'Voriger Tag');
    expect(_chevron(tester, Icons.chevron_right).tooltip, 'Nächster Tag');
  });

  testWidgets('next is disabled at the date-picker\'s last day (tomorrow)',
      (WidgetTester tester) async {
    // The picker window (see _pickDate) ends at now + 1 day: selecting
    // tomorrow must not offer a next day — no unbounded future.
    final tomorrow = DateOnly.addDays(_fixedNow, 1);
    await tester.pumpWidget(_scope(selectedDay: tomorrow));
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
    await tester.pumpWidget(_scope(selectedDay: firstDay));
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
    await tester.pumpWidget(_scope(selectedDay: _day1));
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

    final stored1 = await _db!.entriesDao.entryFor(defaultProfileId, _day1);
    final stored2 = await _db!.entriesDao.entryFor(defaultProfileId, _day2);
    expect(stored1!.bbtC, 36.4,
        reason: 'navigation must not write the unsaved edit');
    expect(stored2!.bbtC, 36.9);
  });
}
