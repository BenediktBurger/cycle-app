// First-start onboarding: one shared about-content page that the shell
// shows full-page on the first start (the onboardingCompleted flag is
// absent in the app_settings table) and that the settings pane's about
// entry plays on demand. The "continue" action flips the flag; the
// write-through persistence (main.CycleApp) stores it and the next start
// opens the shell directly.
//
// German device locale mirrors the app's German-first posture: the warning
// text below is asserted in German via the generated arbs. The appScope
// harness simulates an already-onboarded install by default, so the
// first-start tests pass onboardingCompleted: false explicitly — either to
// pin the raw first-start state or to let the seeded row hydrate over it.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

void main() {
  testWidgets('first start shows the onboarding page with the method warning',
      (WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    await tester.pumpWidget(
        appScope(locale: const Locale('de'), onboardingCompleted: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('getreue Beobachtung'), findsOneWidget,
        reason: 'the fertility-tracking warning (faithful observation and '
            'interpretation of the body signs) is the core first-start '
            'content and must be visible before any tracking screen');
    expect(find.textContaining('INER'), findsOneWidget,
        reason: 'the warning points to the Rötzer guide / INER courses and '
            'to INER for questions');
    expect(navLabel('Tagebuch'), findsNothing,
        reason: 'the shell stays hidden behind the onboarding page until '
            'the user continues');
  });

  testWidgets('continue enters the shell and persists the flag',
      (WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    CycleDatabase? db;
    await tester.pumpWidget(appScope(
        locale: const Locale('de'),
        onboardingCompleted: false,
        onCreated: (created) => db = created));
    await tester.pumpAndSettle();

    // The one way forward — bring it into view ( ListView builds only the
    // visible children) and tap it.
    await tester.dragUntilVisible(
        find.text('Weiter'), find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(navLabel('Tagebuch'), findsWidgets,
        reason: 'continuing must open the normal navigation shell');
    expect(find.textContaining('getreue Beobachtung'), findsNothing,
        reason: 'the onboarding page must be gone from the shell');

    final store = SettingsStore(db!.settingsDao);
    expect(await store.readSetting(SettingKeys.onboardingCompleted), true,
        reason: 'continuing must write through the onboardingCompleted flag '
            'to app_settings so the page does not replay');
  });

  testWidgets('second start shows nothing (the persisted flag is hydrated)',
      (WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    Future<void> seed(CycleDatabase db) =>
        SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

    // The pin keeps the provider at its raw not-completed default so the
    // seeded row has to do the work through hydration.
    await tester.pumpWidget(appScope(
        locale: const Locale('de'), onboardingCompleted: false, seed: seed));
    await tester.pumpAndSettle();

    expect(find.textContaining('getreue Beobachtung'), findsNothing,
        reason: 'once the flag is persisted, the next start must open the '
            'navigation shell directly');
    expect(navLabel('Tagebuch'), findsWidgets,
        reason: 'the shell is the first surface on a returning start');
  });

  testWidgets('the settings pane opens an about entry with the same content',
      (WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    Future<void> seed(CycleDatabase db) =>
        SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

    await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    // The about entry is intentionally forwardable without the first-start
    // flag: opening it does not need to persist anything. It sits below the
    // fold on the settings pane, so scroll it into view first.
    await tester.dragUntilVisible(find.text('Über die App'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Über die App'));
    await tester.pumpAndSettle();

    expect(find.textContaining('getreue Beobachtung'), findsOneWidget,
        reason: 'the settings about entry must show the SAME content page '
            'the first-start onboarding shows (one content source)');
  });
}
