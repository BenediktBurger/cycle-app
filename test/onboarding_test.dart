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
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/about.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

void main() {
  testWidgets('first start shows the onboarding page with the method warning', (
    WidgetTester tester,
  ) async {
    useDeviceLocales(tester, const [Locale('de')]);

    await tester.pumpWidget(
      appScope(locale: const Locale('de'), onboardingCompleted: false),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('getreue Beobachtung'),
      findsOneWidget,
      reason:
          'the fertility-tracking warning (faithful observation and '
          'interpretation of the body signs) is the core first-start '
          'content and must be visible before any tracking screen',
    );
    expect(
      find.textContaining('INER'),
      findsOneWidget,
      reason:
          'the warning points to the Rötzer guide / INER courses and '
          'to INER for questions',
    );
    expect(
      navLabel('Tagebuch'),
      findsNothing,
      reason:
          'the shell stays hidden behind the onboarding page until '
          'the user continues',
    );
  });

  testWidgets('continue enters the shell and persists the flag', (
    WidgetTester tester,
  ) async {
    useDeviceLocales(tester, const [Locale('de')]);

    CycleDatabase? db;
    await tester.pumpWidget(
      appScope(
        locale: const Locale('de'),
        onboardingCompleted: false,
        onCreated: (created) => db = created,
      ),
    );
    await tester.pumpAndSettle();

    // The one way forward — bring it into view ( ListView builds only the
    // visible children) and tap it.
    await tester.dragUntilVisible(
      find.text('Weiter'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(
      navLabel('Tagebuch'),
      findsWidgets,
      reason: 'continuing must open the normal navigation shell',
    );
    expect(
      find.textContaining('getreue Beobachtung'),
      findsNothing,
      reason: 'the onboarding page must be gone from the shell',
    );

    final store = SettingsStore(db!.settingsDao);
    expect(
      await store.readSetting(SettingKeys.onboardingCompleted),
      true,
      reason:
          'continuing must write through the onboardingCompleted flag '
          'to app_settings so the page does not replay',
    );
  });

  testWidgets('second start shows nothing (the persisted flag is hydrated)', (
    WidgetTester tester,
  ) async {
    useDeviceLocales(tester, const [Locale('de')]);

    Future<void> seed(CycleDatabase db) =>
        SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

    // The pin keeps the provider at its raw not-completed default so the
    // seeded row has to do the work through hydration.
    await tester.pumpWidget(
      appScope(
        locale: const Locale('de'),
        onboardingCompleted: false,
        seed: seed,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('getreue Beobachtung'),
      findsNothing,
      reason:
          'once the flag is persisted, the next start must open the '
          'navigation shell directly',
    );
    expect(
      navLabel('Tagebuch'),
      findsWidgets,
      reason: 'the shell is the first surface on a returning start',
    );
  });

  testWidgets(
    'returning start: no frame shows the first-start page between splash '
    'and shell',
    (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);
      PackageInfo.setMockInitialValues(
        appName: '',
        packageName: '',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

      // Pumps the app itself instead of the harness: the harness would pin
      // the onboarding provider (already-onboarded default), leaving no trace
      // of a returning start. Here the provider stays at its raw default and
      // the seeded app_settings row must flip it through hydration — exactly
      // the real returning-user path. The persisted-settings load is
      // deliberately SLOWED (same row, later completion): on a real device,
      // opening the database and reading its settings table are two separate
      // async steps, and the transient flash hides exactly in that gap —
      // an in-memory database resolves both within one microtask drain, which
      // pumpWidget and the next pump swallow without ever painting it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryDatabase(seed: seed),
            persistedSettingsProvider.overrideWith((ref) async {
              final db = await ref.watch(databaseProvider.future);
              await Future<void>.delayed(const Duration(milliseconds: 96));
              return SettingsStore(db.settingsDao).load();
            }),
          ],
          child: const CycleApp(),
        ),
      );

      // Frame by frame: not one frame of the returning start may show the
      // first-start variant of the about page — a persisted completion must
      // take the user straight from the splash to the shell. The variant
      // widget is asserted, not its below-the-fold "continue" button
      // (ValueKey 'aboutContinueButton'): the page builds only its visible
      // ListView children over the default test viewport.
      final onboardingVariant = find.byWidgetPredicate(
        (w) => w is AboutPage && w.onboarding,
      );
      for (var frame = 1; frame <= 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          onboardingVariant,
          findsNothing,
          reason:
              'frame $frame: while the persisted settings load is in '
              'flight, the completed onboarding row must not surface the '
              'first-start page — that transient flash is what a returning '
              'user sees before hydration flips the flag',
        );
      }

      await tester.pumpAndSettle();
      expect(
        find.textContaining('getreue Beobachtung'),
        findsNothing,
        reason: 'the first-start content is gone from the returned-to shell',
      );
      expect(
        navLabel('Tagebuch'),
        findsWidgets,
        reason: 'the hydrated completion opens the shell as the end state',
      );
    },
  );

  testWidgets(
    'a failing persisted-settings read fails open instead of hanging on '
    'the splash',
    (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);
      PackageInfo.setMockInitialValues(
        appName: '',
        packageName: '',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );

      // The settings snapshot errors out AFTER the database opened: the gate
      // must not brick on the splash waiting forever for a snapshot that will
      // never come.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryDatabase(),
            persistedSettingsProvider.overrideWith((ref) async {
              await ref.watch(databaseProvider.future);
              throw StateError('settings table unreadable');
            }),
          ],
          child: const CycleApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is AboutPage && w.onboarding),
        findsOneWidget,
        reason:
            'the gate fails open to the home-gate surface: a broken '
            'settings source must never brick the start (the unhydrated '
            "flag shows the first-start page — the same surface today's "
            'settings-free behavior produced)',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'the splash wait is over — the open turns on an error of '
            'the settings read, not stuck loading',
      );
    },
  );

  testWidgets(
    'the settings pane app bar opens the about page with the SAME content',
    (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      // The about page is intentionally forwardable without the first-start
      // flag: opening it does not need to persist anything. It opens from the
      // settings pane's app bar info action.
      await tester.tap(find.byKey(const ValueKey('aboutAction')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('getreue Beobachtung'),
        findsOneWidget,
        reason:
            'the settings about entry must show the SAME content page '
            'the first-start onboarding shows (one content source)',
      );
    },
  );
}
