// Shared widget-test harness: the in-memory drift database override and the
// scopes built on it — the screen-level harnesses (`diaryScreenScope`,
// `settingsHarness`) for tests that inspect one screen, and `appScope` for
// the thin full-shell tier (navigation, lifecycle, write-through, snackbars)
// — no files, no platform channels, no FFI paths.
//
// `appScope`'s pins are optional; leaving one out keeps the provider at its
// real default, which is exactly what the "system follows the device" tests
// rely on (see locale_test.dart / theme_mode_setting_test.dart).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:cycle_app/domain/diary_track.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/diary.dart';
import 'package:cycle_app/ui/settings.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override (the inMemoryDatabase return type) ships from the misc entry in
// Riverpod 3.x — the main import doesn't export it.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'finders.dart';
import 'provider_fixtures.dart';

/// The connection every test-side CycleDatabase runs over: in-memory, no
/// files, no platform channels, no FFI paths.
///
/// `closeStreamsSynchronously: true` is drift's documented remedy for widget
/// tests failing with "A Timer is still pending even after the widget tree
/// was disposed": without it, drift delays query-stream cancellation by one
/// event-loop turn (Timer.run), and streams cancelled while Riverpod disposes
/// the ProviderScope during tree teardown can never reach that turn in the
/// test's fake async zone.
DatabaseConnection inMemoryConnection() => DatabaseConnection(
  NativeDatabase.memory(),
  closeStreamsSynchronously: true,
);

/// Creates the in-memory [CycleDatabase] used by the widget-test harnesses.
///
/// The scope override closes the instance together with the test's
/// ProviderScope (same closing semantics as the production provider).
CycleDatabase inMemoryCycleDatabase() => CycleDatabase(inMemoryConnection());

/// The databaseProvider override: a fresh in-memory database per scope.
///
/// [seed] runs inside the database future — that guarantees the form (which
/// reads only through databaseProvider.future) sees the seeded day. [onCreated]
/// hands the created instance to the caller (for assertions against what was
/// actually STORED).
Override inMemoryDatabase({
  Future<void> Function(CycleDatabase db)? seed,
  void Function(CycleDatabase db)? onCreated,
  CycleDatabase Function()? builder,
}) {
  return databaseProvider.overrideWith((ref) async {
    // [builder] lets a test subclass the database for fault injection; the
    // default stays the plain in-memory instance (same constructor wiring).
    final db = builder?.call() ?? inMemoryCycleDatabase();
    onCreated?.call(db);
    ref.onDispose(db.close);
    await seed?.call(db);
    return db;
  });
}

/// The package-info channel the about/onboarding pages read their version
/// through. The success posture seeds `PackageInfo`'s static cache and
/// registers no handler; `fromPlatform` returns that cache before consulting
/// the channel. A failure posture only installs a throwing handler, so it
/// takes effect only while no success has seeded the cache — keep a file's
/// failure cases before its success cases.
const MethodChannel packageInfoChannel = MethodChannel(
  'dev.fluttercommunity.plus/package_info',
);

/// MaterialApp wiring shared by the screen-level harnesses: the app's seed
/// color and app-bar/tooltip themes, and the production `supportedLocales`
/// order (English first, so an unmatched locale falls back to English).
/// `darkTheme`/`themeMode` and `onGenerateTitle` are deliberately absent —
/// the screen tests fix their locale and never exercise brightness or the
/// window title.
Widget _harnessApp({required Locale locale, required Widget home}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        appBarTheme: const AppBarTheme(toolbarHeight: 48),
        tooltipTheme: const TooltipThemeData(preferBelow: false),
      ),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en'), Locale('de')],
      home: home,
    );

/// Answers the package-info channel for one scope: seeded device values, or
/// (with [failure]) an error that models an unanswerable install.
void _answerPackageInfo({required bool failure}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (failure) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (call) async {
          throw MissingPluginException(
            'no package metadata on this (test) device',
          );
        });
  } else {
    PackageInfo.setMockInitialValues(
      appName: '',
      packageName: '',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  }
}

/// The thin full-shell integration tier: navigation, lifecycle, write-through and snackbar tests only.
///
/// App scope for the widget smoke tests: wraps the real app in a
/// ProviderScope over a fresh in-memory database. Every pin is optional and
/// null means "leave the provider at its real default":
///
///  - [locale]: the system language (the settings' "System" option),
///  - [themeMode]: follow the device brightness ("System"),
///  - [diaryTrack]: the real What-to-track defaults (mucus/sex/pain on),
///  - [now]: the real wall clock,
///  - [selectedDay]: today (the provider's real default),
///  - [entriesStream]: the provider's real database-backed stream (the
///    override replaces it wholesale — broadcast streams let the diary and
///    the cycle chart listen at the same time).
///
/// [seed] and [onCreated] reach the database override ([inMemoryDatabase]).
///
/// The onboarding gate is part of the app surface the harness pumps, so the
/// harness simulates an ALREADY-ONBOARDED install (`onboardingCompleted ??
/// true`): the shell tests that predate the first-start page keep hitting
/// the navigation shell directly. The onboarding/gate tests pass an
/// explicit pin — `false` for a first start, `false` + a seeded
/// onboardingCompleted row to exercise the hydration flip. The few tests
/// that pump CycleApp directly (without [appScope]) override the provider
/// themselves.
///
/// The harness also sets the package-info posture on every scope call: the
/// default seeds the mock values of a real 0.1.0+1 device install (version
/// without the build suffix, buildNumber without the `+`) so the version
/// line renders; [packageInfoFailure] installs a throwing channel handler
/// instead — the closest model of a broken/unanswerable device install — and
/// the version line hides (its designed failure path). [packageInfoChannel]
/// documents why that failure posture depends on call order.
ProviderScope appScope({
  Locale? locale,
  ThemeMode? themeMode,
  DiaryTrack? diaryTrack,
  List<CustomCategory>? customCategories,
  bool? onboardingCompleted,
  bool packageInfoFailure = false,
  Future<void> Function(CycleDatabase db)? seed,
  void Function(CycleDatabase db)? onCreated,
  CycleDatabase Function()? builder,
  DateTime Function()? now,
  DateTime? selectedDay,
  Stream<List<DailyEntry>>? entriesStream,
}) {
  _answerPackageInfo(failure: packageInfoFailure);
  return ProviderScope(
    overrides: [
      inMemoryDatabase(seed: seed, onCreated: onCreated, builder: builder),
      if (locale != null) localePin(locale),
      if (themeMode != null) themeModePin(themeMode),
      if (diaryTrack != null) diaryTrackPin(diaryTrack),
      if (customCategories != null) customDiaryCategoriesPin(customCategories),
      onboardingPin(onboardingCompleted ?? true),
      if (now != null) nowProvider.overrideWith((ref) => now),
      if (selectedDay != null) selectedDatePin(selectedDay),
      if (entriesStream != null)
        dailyEntriesProvider.overrideWith((ref) => entriesStream),
    ],
    child: const CycleApp(),
  );
}

/// The settings screen over the in-memory database (sans the shell).
/// [locale] pins the settings/about language; [packageInfoFailure] makes the
/// about page's version lookup fail and hides its version line (see
/// [packageInfoChannel] for its call-order caveat); [seed] provides the
/// device-side data the surface under test previews against; [builder] swaps
/// in a fault-injectable database (support/faulty_db.dart).
Widget settingsHarness({
  Locale locale = const Locale('de'),
  bool packageInfoFailure = false,
  Future<void> Function(CycleDatabase db)? seed,
  CycleDatabase Function()? builder,
}) {
  _answerPackageInfo(failure: packageInfoFailure);
  return ProviderScope(
    overrides: [inMemoryDatabase(seed: seed, builder: builder)],
    child: _harnessApp(locale: locale, home: const EinstellungenScreen()),
  );
}

/// The Tagebuch screen over the in-memory database (sans the shell).
/// [seed]/[onCreated]/[builder] reach the database override
/// ([inMemoryDatabase]); [now] and [selectedDay] pin the clock and the form's
/// day, [diaryTrack] the What-to-track defaults, [customCategories] the
/// user-defined category pins.
ProviderScope diaryScreenScope({
  Locale locale = const Locale('de'),
  Future<void> Function(CycleDatabase db)? seed,
  void Function(CycleDatabase db)? onCreated,
  CycleDatabase Function()? builder,
  DateTime Function()? now,
  DateTime? selectedDay,
  DiaryTrack? diaryTrack,
  List<CustomCategory>? customCategories,
}) => ProviderScope(
  overrides: [
    inMemoryDatabase(seed: seed, onCreated: onCreated, builder: builder),
    localePin(locale),
    if (now != null) nowProvider.overrideWith((ref) => now),
    if (selectedDay != null) selectedDatePin(selectedDay),
    if (diaryTrack != null) diaryTrackPin(diaryTrack),
    if (customCategories != null) customDiaryCategoriesPin(customCategories),
  ],
  child: _harnessApp(
    locale: locale,
    home: const Scaffold(body: TagebuchScreen()),
  ),
);

/// Navigates a pumped app shell to the settings tab and settles. The tab
/// goes through the shared [navLabel] finder: all tabs stay mounted in the
/// shell's IndexedStack, so a bare 'Einstellungen' text finder would also
/// match the offstage screen's AppBar title — and in tree order that AppBar
/// precedes the bar, so the scoped tap is what lands on the destination.
Future<void> openSettingsTab(WidgetTester tester) async {
  await tester.tap(navLabel('Einstellungen'));
  await tester.pumpAndSettle();
}

/// Scrolls the settings screen's lazy list until [card] is built and
/// visible — the list is allowed to grow above the card (e.g. the
/// theme-mode switcher), so fixed-amount drag loops would be brittle. The
/// scrollable is scoped to the settings screen: with the shell keeping
/// every tab mounted, the diary and statistics screens bring their own
/// scrollables and ListViews into the tree, and [settingsHarness] mounts
/// the screen directly (the scope costs nothing there).
Future<void> scrollSettingsCardIntoView(
  WidgetTester tester,
  Finder card,
) async {
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}
