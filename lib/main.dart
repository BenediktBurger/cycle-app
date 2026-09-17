// Root widget: Material app, German-first localization whose language
// follows the system until overridden in the settings screen, a theme mode
// that likewise follows the device brightness until overridden, and the
// database gating shell.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/cycle_database.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'ui/cycle.dart';
import 'ui/diary.dart';
import 'ui/settings.dart';
import 'ui/statistics.dart';

/// Seed for both brightness' color schemes: Flutter's Material 3 default
/// seed, i.e. the scheme the app materialized before dark mode was made
/// explicit — keeping it keeps the light look byte-for-byte familiar.
const _themeSeedColor = Color(0xFF6750A4);

void main() {
  runApp(const ProviderScope(child: CycleApp()));
}

class CycleApp extends ConsumerWidget {
  const CycleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _themeSeedColor),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: _themeSeedColor, brightness: Brightness.dark),
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

/// Gates the navigation shell behind the database opening: a simple loading
/// splash while the (possibly wasm/OPFS-side) open is in flight, and a
/// retrying error screen so users can recover from, e.g., an OPFS hiccup.
class _DatabaseGate extends ConsumerWidget {
  const _DatabaseGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dbAsync = ref.watch(databaseProvider);
    return Scaffold(
      body: dbAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.splashLoadingDatabase),
            ],
          ),
        ),
        error: (error, stackTrace) => _DatabaseError(
          error: error,
          retry: () => ref.invalidate(databaseProvider),
        ),
        data: (CycleDatabase db) => _HomeShell(),
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
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(l10n.dbErrorTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.dbErrorHint, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('$error',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
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
    return Scaffold(
      body: _screens[index],
      bottomNavigationBar: NavigationBar(
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
      ),
    );
  }
}
