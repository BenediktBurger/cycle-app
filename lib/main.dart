// Root widget: Material app, German-first localization whose language
// follows the system until overridden in the settings screen, a theme mode
// that likewise follows the device brightness until overridden, the
// database gating shell, and the persistence wiring for the persisted
// general settings (hydration from / write-through to the app_settings
// table).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/cycle_database.dart';
import 'db/settings_store.dart';
import 'domain/date_only.dart';
import 'domain/temperature_range.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'ui/about.dart';
import 'ui/cycle.dart';
import 'ui/diary.dart';
import 'ui/settings.dart';
import 'ui/statistics.dart';

/// Seed for both brightness' color schemes: Flutter's Material 3 default
/// seed, i.e. the scheme the app materialized before dark mode was made
/// explicit — keeping it keeps the light look byte-for-byte familiar.
const _themeSeedColor = Color(0xFF6750A4);

/// ThemeData built on one brightness' color scheme. Shared by light and
/// dark mode so both stay in sync: the app bars are slightly slimmer than
/// the Material 3 default to keep more of the screen for content
/// (especially the cycle chart).
ThemeData _buildTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  appBarTheme: const AppBarTheme(toolbarHeight: 48),
);

void main() {
  runApp(const ProviderScope(child: CycleApp()));
}

class CycleApp extends ConsumerStatefulWidget {
  const CycleApp({super.key});

  @override
  ConsumerState<CycleApp> createState() => _CycleAppState();
}

class _CycleAppState extends ConsumerState<CycleApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Lifecycle observation: the foreground-leavings and the resumes are
    // what drive the new-day warm resume ("morning jump",
    // [didChangeAppLifecycleState]) — the wake-up must know on which day
    // the app went to sleep, and only the root state lives long enough
    // (and is mounted early enough) to observe both ends of that
    // backgrounding.
    WidgetsBinding.instance.addObserver(this);
    // Hydration: every persisted snapshot (loaded by
    // persistedSettingsProvider the moment the database opens) is applied
    // into the settings providers. Fill-if-untouched — only a provider
    // still holding its default takes the snapshot value, so a live choice
    // (made in between, or coming from a test override) is never clobbered,
    // and snapshot defaults are skipped as no-ops. The snapshot lands
    // shortly after the first frame: the MaterialApp
    // skeleton renders one frame in defaults until then — accepted
    // trade-off, the database gate keeps every screen behind the open
    // database, so nothing can write a contradicting choice in between.
    // fireImmediately covers the (unlikely) case of the snapshot being
    // ready before this root widget mounts; normally the callback only
    // fires on the loading→data transition.
    ref.listenManual(persistedSettingsProvider, fireImmediately: true, (
      previous,
      next,
    ) {
      // valueOrNull (not .value): a broken settings read must surface as
      // "no snapshot" here — .value rethrows the read error and would
      // crash the start through this listener, defeating the gate's
      // fail-open to the shell below.
      final snapshot = next.valueOrNull; // null while loading/in error
      if (snapshot == null) return;
      final locale = ref.read(localeProvider);
      if (locale == null && snapshot.locale != null) {
        ref.read(localeProvider.notifier).state = snapshot.locale;
      }
      final themeMode = ref.read(themeModeProvider);
      if (themeMode == ThemeMode.system &&
          snapshot.themeMode != ThemeMode.system) {
        ref.read(themeModeProvider.notifier).state = snapshot.themeMode;
      }
      final range = ref.read(temperatureRangeProvider);
      if (range == TemperatureRange.defaults &&
          snapshot.temperatureRange != TemperatureRange.defaults) {
        ref.read(temperatureRangeProvider.notifier).state =
            snapshot.temperatureRange;
      }
      final observedCycles = ref.read(observedCyclesOutsideAppProvider);
      if (observedCycles == 0 && snapshot.observedCyclesOutsideApp != 0) {
        ref.read(observedCyclesOutsideAppProvider.notifier).state =
            snapshot.observedCyclesOutsideApp;
      }
      // The nullable paper-history values follow the pdfExport pattern:
      // null means "not given" (the default), so only a non-null snapshot
      // value fills an untouched provider.
      final paperShortest = ref.read(shortestCycleLengthOutsideAppProvider);
      if (paperShortest == null &&
          snapshot.shortestCycleLengthOutsideApp != null) {
        ref.read(shortestCycleLengthOutsideAppProvider.notifier).state =
            snapshot.shortestCycleLengthOutsideApp;
      }
      final paperEarliest = ref.read(
        earliestFirstHigherCycleDayOutsideAppProvider,
      );
      if (paperEarliest == null &&
          snapshot.earliestFirstHigherCycleDayOutsideApp != null) {
        ref.read(earliestFirstHigherCycleDayOutsideAppProvider.notifier).state =
            snapshot.earliestFirstHigherCycleDayOutsideApp;
      }
      final pdfName = ref.read(pdfExportNameProvider);
      if (pdfName == null && snapshot.pdfExportName != null) {
        ref.read(pdfExportNameProvider.notifier).state = snapshot.pdfExportName;
      }
      final pdfBirthDate = ref.read(pdfExportBirthDateProvider);
      if (pdfBirthDate == null && snapshot.pdfExportBirthDate != null) {
        ref.read(pdfExportBirthDateProvider.notifier).state =
            snapshot.pdfExportBirthDate;
      }
      // One-directional by nature: the onboarding flag can only flip
      // not-completed → completed, and hydration applies only that flip (a
      // persisted completion must never be re-set to false).
      final onboarded = ref.read(onboardingCompletedProvider);
      if (!onboarded && snapshot.onboardingCompleted) {
        ref.read(onboardingCompletedProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    // Unregistering keeps the observer table clean beyond this state's
    // lifetime — the watch must outlive neither the state nor the mounted
    // flag of the ref it uses.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The morning jump ("new-day warm resume"): while the app's process
    // was alive overnight, the FIRST foreground of a new calendar day
    // resets the shell to today's entry form on the diary tab — data entry
    // for the new day happens directly after getting up, and the wake-up
    // should present the ready form, not yesterday's last-opened day or a
    // chart the user fell asleep on.
    final previous = _lifecycleState ?? AppLifecycleState.resumed;
    _lifecycleState = state;
    switch (state) {
      // Every resume decides between the jump and a plain continue.
      case AppLifecycleState.resumed:
        _jumpToTodaysDiaryIfOvernight();
      // Recording the day is deliberately DIRECTION-AWARE: hidden and
      // inactive are ambiguous states — the engine walks them on the way
      // DOWN (resumed → inactive → hidden → paused, whichever stop the
      // platform eventually makes: Android pauses, iOS/by-design may stay
      // hidden) AND on the way back UP (paused → hidden → inactive →
      // resumed). A blind record on every non-resumed state would stamp
      // "today" onto the resume path and erase the sleeping-over night
      // right before the jump compares against it — the jump could never
      // fire. So: write only on transitions that move DEEPER away from the
      // foreground, which cover every backgrounding path while leaving the
      // return path untouched. Detached is skipped entirely: the shell is
      // tearing down and a provider read is no longer meaningful — it can
      // only follow states that already recorded, or never return.
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Only the departure from the interactive foreground stamps the
        // day; partial wake-ups that never reach `resumed` must not.
        if (previous == AppLifecycleState.resumed) {
          ref.read(lastForegroundDayProvider.notifier).state =
              DateOnly.normalize(ref.read(nowProvider)());
        }
    }
  }

  /// The lifecycle state before the current one — the recording rule ("only
  /// the departure from the interactive foreground stamps the day") compares
  /// against it. Null until the first event; the launch state beforehand is
  /// "resumed" by definition.
  AppLifecycleState? _lifecycleState;

  /// The wake-up end of the morning jump: overnight only (the last seen
  /// foreground day differs from the calendar day now) the shell resets to
  /// today's entry form on the diary tab, re-records the day so further
  /// resumes stay put, and otherwise — same-day resume, or the very first
  /// foreground after launch with nothing recorded yet — keeps the user
  /// exactly where they left off.
  ///
  /// The jump moves the form through the SAME date-change path as every
  /// manual day change ([selectedDateProvider], which the diary's
  /// ref.listen reloads its fields on): unsaved diary-form edits are
  /// deliberately discarded by the jump — the established discard rule of
  /// day changes, not a new behavior — because entries persist only on the
  /// explicit save and the user returning after a wake-up wants the new
  /// day, not a stale draft for yesterday.
  void _jumpToTodaysDiaryIfOvernight() {
    final lastDay = ref.read(lastForegroundDayProvider);
    final today = DateOnly.normalize(ref.read(nowProvider)());
    if (lastDay == null || DateOnly.sameDay(lastDay, today)) return;
    ref.read(selectedDateProvider.notifier).state = today;
    // Tab 0 is the diary: the reset lands WITH the ready form, not beside
    // wherever the user last looked.
    ref.read(tabIndexProvider.notifier).state = 0;
    ref.read(lastForegroundDayProvider.notifier).state = today;
  }

  @override
  Widget build(BuildContext context) {
    // Write-through: every provider change (settings screen, future call
    // sites) is echoed into app_settings as a fire-and-forget upsert on
    // the open database. Hydration assignments echo their just-loaded
    // values back — same row content, an idempotent upsert. A storage
    // failure cannot undo the in-memory change — it only reverts the
    // choice to its default on the next start — so the write error is
    // deliberately ignored, see [_persistSetting].
    ref.listen<Locale?>(localeProvider, (previous, current) {
      _persistSetting(ref, (store) => store.persistLocale(current));
    });
    ref.listen<ThemeMode>(themeModeProvider, (previous, current) {
      _persistSetting(ref, (store) => store.persistThemeMode(current));
    });
    ref.listen<TemperatureRange>(temperatureRangeProvider, (previous, current) {
      _persistSetting(ref, (store) => store.persistTemperatureRange(current));
    });
    ref.listen<int>(observedCyclesOutsideAppProvider, (previous, current) {
      _persistSetting(
        ref,
        (store) => store.persistObservedCyclesOutsideApp(current),
      );
    });
    ref.listen<int?>(shortestCycleLengthOutsideAppProvider, (
      previous,
      current,
    ) {
      _persistSetting(
        ref,
        (store) => store.persistShortestCycleLengthOutsideApp(current),
      );
    });
    ref.listen<int?>(earliestFirstHigherCycleDayOutsideAppProvider, (
      previous,
      current,
    ) {
      _persistSetting(
        ref,
        (store) => store.persistEarliestFirstHigherCycleDayOutsideApp(current),
      );
    });
    ref.listen<String?>(pdfExportNameProvider, (previous, current) {
      _persistSetting(ref, (store) => store.persistPdfExportName(current));
    });
    ref.listen<DateTime?>(pdfExportBirthDateProvider, (previous, current) {
      _persistSetting(ref, (store) => store.persistPdfExportBirthDate(current));
    });
    ref.listen<bool>(onboardingCompletedProvider, (previous, current) {
      _persistSetting(
        ref,
        (store) => store.persistOnboardingCompleted(current),
      );
    });

    // null (the localeProvider default) = follow the system language: the
    // platform's locale list is then resolved against supportedLocales,
    // which picks German for German devices and English for everything
    // else (English is the fallback language, ADR-0007). An explicit
    // settings choice is always applied as-is.
    final Locale? explicitLocale = ref.watch(localeProvider);
    // ThemeMode.system (the themeModeProvider default) follows the device
    // brightness; an explicit light/dark choice from the settings switcher
    // wins over the platform.
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      // Theme: explicit Material 3 color schemes from one seed. The light
      // scheme is Flutter's own default seed, so light mode looks exactly
      // as before; dark mode derives from the same seed
      // (ColorScheme.fromSeed(brightness: dark)) so both schemes stay in
      // the same tonal neighborhood, and the app follows the device
      // brightness setting (themeMode: system).
      themeMode: themeMode,
      theme: _buildTheme(ColorScheme.fromSeed(seedColor: _themeSeedColor)),
      darkTheme: _buildTheme(
        ColorScheme.fromSeed(
          seedColor: _themeSeedColor,
          brightness: Brightness.dark,
        ),
      ),
      locale: explicitLocale,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        // English first, German second: when nothing is matched explicitly,
        // Flutter's locale resolution ends at the first supported locale, so
        // anything outside the supported set (or no system locale at all,
        // or the system following "System") falls back to English — the
        // app's fallback language, never German
        // (docs/adr/0007-language-policy.md). An explicit supported locale,
        // as the language switcher sets it, is unaffected.
        Locale('en'),
        Locale('de'),
      ],
      home: const _DatabaseGate(),
    );
  }
}

/// Fire-and-forget persistence of one settings-provider change ([write])
/// through the typed settings store on the app's open database. The write
/// error is deliberately ignored (see the write-through comment in
/// [CycleApp.build]): the in-memory choice stands, and the failure only
/// means the default is restored on the next start.
void _persistSetting(
  WidgetRef ref,
  Future<void> Function(SettingsStore store) write,
) {
  unawaited(() async {
    try {
      final db = await ref.read(databaseProvider.future);
      await write(SettingsStore(db.settingsDao));
    } catch (_) {
      // Deliberately ignored, see the comment above.
    }
  }());
}

/// Gates the navigation shell behind the database opening AND the first
/// settings hydration: a simple loading splash while the (possibly
/// wasm/OPFS-side) open is in flight — kept up while the persisted-settings
/// snapshot loads from the freshly opened database — and a retrying error
/// screen so users can recover from, e.g., an OPFS hiccup. The waiting
/// branches bring their own Scaffold; on the interactive paths the shell's
/// own Scaffold must be the topmost one in the messenger's scope.
class _DatabaseGate extends ConsumerWidget {
  const _DatabaseGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);
    return dbAsync.when(
      loading: () => const Scaffold(body: _SplashLoading()),
      error: (error, stackTrace) => Scaffold(
        body: _DatabaseError(
          error: error,
          retry: () => ref.invalidate(databaseProvider),
        ),
      ),
      // NO wrapper Scaffold here: the interactive branches return their
      // content unwrapped so the shell's own Scaffold (and the about
      // page's) is the topmost Scaffold in the root messenger's scope —
      // SnackBars then dock above the shell's bottom NavigationBar / rail
      // instead of draping it and blocking destination taps while they
      // show. Only the waiting branches need a Scaffold of their own.
      data: (CycleDatabase db) {
        // The shell opens on the persisted-settings snapshot, not on the
        // bare database: hydration (CycleApp.initState) applies the
        // snapshot into the settings providers — the onboarding-completed
        // flag among them — the moment this value arrives, so waiting
        // here lets a returning user's hydrated state drive the first
        // shell frame instead of flashing the first-start page while the
        // settings are still in flight.
        final settingsAsync = ref.watch(persistedSettingsProvider);
        return settingsAsync.when(
          loading: () => const Scaffold(body: _SplashLoading()),
          // Fail-open: a broken settings read renders the shell so a
          // faulty settings source never bricks the app. Effectively a
          // db-level path only — SettingsStore.load() already degrades
          // corrupt per-key values (catch-per-row).
          error: (error, stackTrace) => const _HomeGate(),
          data: (_) => const _HomeGate(),
        );
      },
    );
  }
}

/// The shared database-open splash: the plain spinner-plus-label column
/// used BOTH while the database opens and afterwards while the persisted
/// settings are read from it — one surface for the whole open+warm-up
/// sequence, so the wait never jumps between looks.
class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.splashLoadingDatabase),
        ],
      ),
    );
  }
}

class _DatabaseError extends StatelessWidget {
  const _DatabaseError({required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.dbErrorTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.dbErrorHint, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.dbErrorRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Width breakpoint that promotes the shell's bottom NavigationBar to a
/// side NavigationRail: below it (phone portrait) the bottom bar stays,
/// at/above it (landscape phones, wide windows/tabs) the rail frees the
/// bottom edge and puts almost the full width on the screen body — exactly
/// the "see more of the cycle in landscape" win. Desktop-class narrow
/// windows under 720 keep the bar.
const _railBreakpointWidth = 720.0;

/// The surface behind the database gate — reached only after the gate has
/// seen both the open database and the persisted-settings snapshot
/// ([_DatabaseGate]): the shared about-content page in its onboarding
/// variant until the persisted onboarding flag flips, then the navigation
/// shell forever. Hydrated flag → no onboarding at all (a returning start
/// shows nothing), so the page plays exactly once.
class _HomeGate extends ConsumerWidget {
  const _HomeGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardingCompletedProvider);
    return onboarded ? const _HomeShell() : const AboutPage(onboarding: true);
  }
}

class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  static const List<Widget> _screens = [
    TagebuchScreen(),
    ZyklusScreen(),
    StatistikScreen(),
    EinstellungenScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final index = ref.watch(tabIndexProvider);
    // The IndexedStack stays mounted through both shell surfaces (all tabs
    // alive and watching their providers).
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _railBreakpointWidth;
        final indexedStack = IndexedStack(index: index, children: _screens);
        return Scaffold(
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The rail reuses the bottom bar's icons and the same
                    // `nav…` l10n labels — one navigation vocabulary, two
                    // surfaces. Labeled on every destination, so the tests
                    // (and the tab tap targets) stay independent of the
                    // selection state.
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: (int newIndex) =>
                          ref.read(tabIndexProvider.notifier).state = newIndex,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.event_outlined),
                          selectedIcon: const Icon(Icons.event),
                          label: Text(l10n.navDiary),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.loop_outlined),
                          selectedIcon: const Icon(Icons.loop),
                          label: Text(l10n.navCycle),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.bar_chart_outlined),
                          selectedIcon: const Icon(Icons.bar_chart),
                          label: Text(l10n.navStatistics),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: const Icon(Icons.settings),
                          label: Text(l10n.navSettings),
                        ),
                      ],
                    ),
                    Expanded(child: indexedStack),
                  ],
                )
              : indexedStack,
          // All tabs stay mounted in an IndexedStack: switching away and
          // back preserves each screen's widget state (e.g. the cycle
          // chart's scroll window survives the Tagebuch→Zyklus roundtrip),
          // and the offstage screens keep watching their providers so they
          // are up to date when shown. Offstage children are built and laid
          // out but neither painted nor hit-testable.
          bottomNavigationBar: wide
              ? null
              : _bottomNavigationBar(context, ref, index, l10n),
        );
      },
    );
  }

  NavigationBar _bottomNavigationBar(
    BuildContext context,
    WidgetRef ref,
    int index,
    AppLocalizations l10n,
  ) => NavigationBar(
    height: 64,
    selectedIndex: index,
    onDestinationSelected: (int newIndex) =>
        ref.read(tabIndexProvider.notifier).state = newIndex,
    destinations: [
      NavigationDestination(
        icon: const Icon(Icons.event_outlined),
        selectedIcon: const Icon(Icons.event),
        label: l10n.navDiary,
      ),
      NavigationDestination(
        icon: const Icon(Icons.loop_outlined),
        selectedIcon: const Icon(Icons.loop),
        label: l10n.navCycle,
      ),
      NavigationDestination(
        icon: const Icon(Icons.bar_chart_outlined),
        selectedIcon: const Icon(Icons.bar_chart),
        label: l10n.navStatistics,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.navSettings,
      ),
    ],
  );
}
