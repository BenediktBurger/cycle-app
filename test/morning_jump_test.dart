// The "morning jump": the FIRST foreground of a NEW calendar day (after the
// app was backgrounded overnight with its process still alive) resets the
// shell to today's entry form on the diary tab — the midnight-wake use case,
// where the day's data entry happens directly after getting up. Within the
// same day, resuming keeps the user exactly where they left off. A killed
// (cold) start is out of scope here: it re-derives today's diary form from
// the provider defaults, which is driver-tested elsewhere.
//
// The tests pump the REAL CycleApp over the shared in-memory-database
// harness, pin the clock through nowProvider with a mutable test variable
// (so the test itself moves it across the midnight boundary), and drive the
// real lifecycle dispatch (handleAppLifecycleStateChanged — the observer
// notification path of the test binding). The last-foreground day is never
// written or read by hand in the tests: recording it is exactly what the
// pause dispatch is supposed to do, so every scenario drives the lifecycle
// the way the platform would.
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/database.dart';
import 'support/finders.dart';

// Injected "now": the evening of the launch day (the evening the user left
// the app on). The German locale is pinned so the date-button label
// assertions stay deterministic (same pattern as the day-navigation tests).
final _launchDayEvening = DateTime(2026, 4, 10, 23, 5);

final _nextDayMorning = DateTime(2026, 4, 11, 8, 10);

// The header date button's format lives in the widget (_headerDayLabel
// renders yMMMEd, the mark-sheet style); mirroring that call keeps the
// expected label free of a transcribed format literal.
String _dayLabel(DateTime day) =>
    DateFormat.yMMMEd('de').format(DateOnly.normalize(day));

/// The app's own localized strings, read from any element below the
/// MaterialApp (every widget in the pumped tree shares the delegates).
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(OutlinedButton).first));

/// Provider access below the MaterialApp: CycleApp itself is always on
/// stage (the shell's IndexedStack skips offstage tabs for default finders,
/// unlike the root).
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CycleApp)));

void main() {
  DateTime clock = _launchDayEvening;

  Future<void> pumpApp(WidgetTester tester, {DateTime? selectedDay}) async {
    // Each test starts on the launch-day evening again — the clock is the
    // shared mutable variable the lifecycle scenarios move around.
    clock = _launchDayEvening;
    await tester.pumpWidget(
      appScope(
        locale: const Locale('de'),
        now: () => clock,
        selectedDay: selectedDay ?? DateOnly.normalize(_launchDayEvening),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The real lifecycle dispatches; each transition gets a settle pump so
  /// the shell and the entry form have rebuilt. The listed states mirror
  /// the engine's legal transition chains (resumed↔inactive↔hidden↔paused),
  /// which framework-side AppLifecycleListeners assert when a dispatch skips
  /// the intermediate states.
  Future<void> backgrounded(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
    }
  }

  Future<void> foregrounded(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'overnight resume after a day change jumps to today\'s diary form',
    (WidgetTester tester) async {
      await pumpApp(tester);

      // The user reviewed yesterday's day on the diary tab: the selection
      // leaves "today" through the form's back-chevron day navigation.
      final container = _container(tester);
      expect(
        container.read(selectedDateProvider),
        DateOnly.normalize(_launchDayEvening),
        reason: 'guard: the shell opens with today pre-selected',
      );
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedDateProvider),
        DateOnly.normalize(_launchDayEvening).subtract(const Duration(days: 1)),
        reason: 'guard: the user moved the form to the previous day',
      );

      // The app goes to the background ON the launch day; the clock moves
      // overnight while the process stays alive; the wake-up is the first
      // foreground of the new day.
      await backgrounded(tester);
      clock = _nextDayMorning;
      await foregrounded(tester);

      expect(
        container.read(selectedDateProvider),
        DateOnly.normalize(_nextDayMorning),
        reason:
            'the new-day warm resume resets the entry form to today '
            '(the morning jump)',
      );
      expect(
        container.read(tabIndexProvider),
        0,
        reason: 'the jump lands on the diary tab',
      );
      // On the jumped-to day (today) the header prefixes the date with the
      // ARB's today composite, so the expected string is assembled from the
      // app's own l10n instead of a transcribed German literal.
      expect(
        find.widgetWithText(
          OutlinedButton,
          _l10n(
            tester,
          ).todayDate(_dayLabel(DateOnly.normalize(_nextDayMorning))),
        ),
        findsOneWidget,
        reason: 'the form\'s date button shows the new day as today',
      );
    },
  );

  testWidgets('same-day resume keeps the user exactly where they left off', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    final container = _container(tester);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final movedDay = container.read(selectedDateProvider);
    expect(
      movedDay,
      isNot(DateOnly.normalize(_launchDayEvening)),
      reason: 'guard: the selection actually moved',
    );

    // Backgrounded late in the day, foregrounded later the SAME day:
    // nothing may reset — the review of yesterday's day continues.
    await backgrounded(tester);
    clock = DateTime(2026, 4, 10, 23, 55);
    await foregrounded(tester);

    expect(
      container.read(selectedDateProvider),
      movedDay,
      reason: 'a same-day resume must not touch the selection',
    );
    expect(
      container.read(tabIndexProvider),
      0,
      reason: 'the tab count stays as left off',
    );
    expect(
      find.widgetWithText(OutlinedButton, _dayLabel(movedDay)),
      findsOneWidget,
      reason: 'the date button still shows the day the user moved to',
    );
  });

  testWidgets('overnight resume on a non-diary tab switches to the diary tab', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    final container = _container(tester);

    // The user browsed statistics before backgrounding; the overnight
    // wake lands on the diary tab regardless of where they left off.
    await tester.tap(navLabel('Statistik'));
    await tester.pumpAndSettle();
    expect(
      container.read(tabIndexProvider),
      isNot(0),
      reason: 'guard: the user is on a non-diary tab',
    );

    await backgrounded(tester);
    clock = _nextDayMorning;
    await foregrounded(tester);

    expect(
      container.read(tabIndexProvider),
      0,
      reason:
          'the first foreground of a new day jumps to the diary tab '
          '(the midnight-wake use case: entry happens right after '
          'getting up)',
    );
    expect(
      container.read(selectedDateProvider),
      DateOnly.normalize(_nextDayMorning),
      reason: 'and the jump also resets the entry form to today',
    );
    expect(
      find.byType(TagebuchScreen),
      findsOneWidget,
      reason: 'the diary tab is the one shown after the jump',
    );
  });

  testWidgets(
    'a resume without any prior backgrounding leaves the state alone',
    (WidgetTester tester) async {
      await pumpApp(tester);
      final container = _container(tester);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      final movedDay = container.read(selectedDateProvider);

      // The very first foreground after launch, with the clock already
      // crossed over midnight: only the plain `resumed` event is
      // dispatched — deliberately NOT the resume chain (hidden, inactive),
      // because against a null last-foreground day those states would move
      // DOWN from the launch state, deepen away from the foreground, and
      // record the new day before the resume could compare — the no-op
      // would pass via the same-day branch instead of the null guard this
      // test pins. A bare `resumed` dispatch is legal here (the state has
      // been foreground since launch, nothing was ever dispatched before),
      // so nothing was ever recorded: the null guard must keep the state
      // exactly as the provider defaults (plus the user's day change) left
      // it.
      clock = _nextDayMorning;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        container.read(selectedDateProvider),
        movedDay,
        reason:
            'without a recorded last-foreground day the resume must be '
            'a no-op',
      );
      expect(
        container.read(tabIndexProvider),
        0,
        reason: 'the tab was never left either',
      );
    },
  );
}
