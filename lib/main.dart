// Root widget: Material app, German-first localization (switchable in the
// settings screen), and the database gating shell.
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

void main() {
  runApp(const ProviderScope(child: CycleApp()));
}

class CycleApp extends ConsumerWidget {
  const CycleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      locale: locale,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de'), // German first — base language of the app.
        Locale('en'),
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
            label: l10n.navTagebuch,
          ),
          NavigationDestination(
            icon: const Icon(Icons.loop_outlined),
            selectedIcon: const Icon(Icons.loop),
            label: l10n.navZyklus,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.navStatistik,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navEinstellungen,
          ),
        ],
      ),
    );
  }
}
