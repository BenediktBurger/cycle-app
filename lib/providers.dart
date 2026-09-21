// Riverpod providers for the app's state: the single open database, live
// entry streams and cross-screen selection state (tab index, locale, the
// date pre-selected in the entry form).
//
// The persisted general settings (locale, theme mode, temperature range,
// the outside-app cycle count) are persisted in the app_settings key-value
// table of the drift database: they load into the StateProviders below
// right after the database opens ([persistedSettingsProvider], hydration
// wiring in main.CycleApp) and every change is written back through to
// that table (also main.CycleApp). The providers stay plain in-memory
// StateProviders — all overrides and call sites keep working unchanged.
//
// The PIN lock stub (Settings screen) is non-functional and local.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/cycle_database.dart';
import 'db/database_opener.dart';
import 'db/mappers.dart';
import 'db/settings_store.dart';
import 'domain/date_only.dart';
import 'domain/marks.dart';
import 'domain/models.dart';
import 'domain/temperature_range.dart';

/// The one open database for the app lifetime. `FutureProvider` (without
/// autoDispose) keeps the instance cached; disposing the ProviderScope
/// closes it. UI screens wait on it via the splash gate in main.dart, so
/// everything downstream can `ref.read(databaseProvider.future)`.
///
/// Opening is async since the native path first resolves the encryption
/// key from the platform's secure storage (and fails loudly if that is
/// impossible — lib/db/db_key.dart); the splash gate surfaces the error.
final databaseProvider = FutureProvider<CycleDatabase>((ref) async {
  final db = await openCycleDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The current wall-clock time, injectable: the Tagebuch entry form prefills
/// the time-of-measurement with this value for a fresh day. Widget tests
/// override it with a fixed clock (`() => fixedNow`) so "the form shows the
/// current time" is deterministic (no race against the real minute boundary).
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Live stream of the tracked days (as pure domain models) — the single
/// source of truth behind Tagebuch, Zyklus and Statistik screens. Re-emits
/// on every write.
final dailyEntriesProvider =
    StreamProvider.autoDispose<List<DailyEntry>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.entriesDao
      .watchAll()
      .map((rows) => rows.map(dailyEntryFromDrift).toList());
});

/// Live stream of the user-placed marks (as pure domain models) — the read
/// side of the evaluation feature (Mode M, the counterpart to
/// [dailyEntriesProvider]). Re-emits on every mark write (add/remove);
/// consumers recompute the derived evaluation (baseline, circled higher
/// measurements, SUZ) from it at render time — never from a persisted copy,
/// per ADR-0001.
final marksProvider = StreamProvider.autoDispose<List<CycleMark>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.marksDao
      .watchAll()
      .map((rows) => rows.map(cycleMarkFromDrift).toList());
});

/// Tab index of the bottom navigation shell. Simple StateProvider: screens
/// (e.g. a chart tap on the Zyklus screen) can jump the shell to the
/// Tagebuch tab by writing here.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Locale of the whole app: `null` (the default) means "follow the system
/// language", a non-null value is an explicit choice from the settings
/// language switcher that wins over the platform.
///
/// With null, [main.CycleApp] leaves `MaterialApp.locale` unset, so
/// Flutter's locale resolution matches the platform language against the
/// supported de/en set and falls back to the first supported locale —
/// English — for any other device language (ADR-0007; the list lives in
/// main.dart and the resolution story in its comment).
///
/// Persisted: hydrated from the local app_settings table once the database
/// opens — before any screen that could change it is reachable (the
/// database gate) — and written through on every change (main.CycleApp).
final localeProvider = StateProvider<Locale?>((ref) => null);

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// Persisted, mirroring [localeProvider]: hydrated from the local
/// app_settings table once the database opens and written through on every
/// change (main.CycleApp).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// The cycle chart's temperature display range ("Temperaturbereich"
/// settings card): the FIXED y bounds the chart's plot and the frozen
/// rail's scale share — settings-selectable, default 36–38 °C. Readings
/// outside the range are not rendered: their dots are skipped and the
/// curve's drawable line pieces clip at the boundary crossings (see
/// lib/ui/cycle_curve.dart); the scale never stretches to fit an outlier.
///
/// Persisted, mirroring [localeProvider]/[themeModeProvider]: hydrated from
/// the local app_settings table once the database opens and written through
/// on every change (main.CycleApp). The °C unit stays the unit of record —
/// a later Fahrenheit display conversion would happen above this provider.
final temperatureRangeProvider =
    StateProvider<TemperatureRange>((ref) => TemperatureRange.defaults);

/// The count of cycles the user observed OUTSIDE this app (set in the
/// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
/// the chart's boundary labels AND the evaluation table's column headers —
/// add this count on top of the mark-opened cycles recorded in the
/// database, so numbering continues seamlessly across the migration
/// (lib/domain/cycle_grouping.dart's shared ordinal rule).
///
/// Persisted, mirroring [localeProvider]/[themeModeProvider]: hydrated from
/// the local app_settings table once the database opens and written through
/// on every change (main.CycleApp).
final observedCyclesOutsideAppProvider = StateProvider<int>((ref) => 0);

/// Whether the onboarding page has been completed ("Weiter" tapped). The
/// default false shows the shared about-content page full-page once the
/// database is open; the continue action flips it to true, and the shell
/// takes over (main._HomeGate reads this provider).
///
/// Persisted, mirroring the other general settings: hydrated from the local
/// app_settings table once the database opens (absent row = not completed,
/// for existing installs too, so the welcome page shows once after the
/// update) and written through on every change (main.CycleApp).
final onboardingCompletedProvider = StateProvider<bool>((ref) => false);

/// The persisted general settings as one snapshot, freshly loaded from the
/// app_settings table the moment the database opens ([databaseProvider]).
/// main.CycleApp's hydration listener applies each snapshot into
/// [localeProvider], [themeModeProvider] and [temperatureRangeProvider].
/// Non-autoDispose like [databaseProvider] — the load keeps the database
/// open for the app lifetime.
final persistedSettingsProvider =
    FutureProvider<PersistedSettings>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SettingsStore(db.settingsDao).load();
});

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).
final selectedDateProvider =
    StateProvider<DateTime>((ref) => DateOnly.normalize(DateTime.now()));

/// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
/// AppBar's actions (next to the info action — a row of its own above the
/// chart wasted vertical space), but the jump logic needs the chart's scroll
/// state (the viewport/column geometry, the day mapping and the scroll
/// controller all live on the chart state), so the chart state registers its
/// action here while mounted and clears it again on dispose. Null while no
/// chart is on screen (entries still loading, no data) — the AppBar hides
/// the button then, exactly like the old in-chart row never rendered there.
final cycleChartJumpProvider =
    StateProvider<void Function(BuildContext context)?>((ref) => null);

/// The day whose options panel is shown on the Zyklus screen (null = no
/// panel). Chart taps (the curve, the marks row, the signal-row cells)
/// write here instead of pushing a modal route, so tapping ANOTHER day
/// retargets the panel in place — the first day's marks are never
/// deselected by a dismissal — and the panel's close button clears it.
/// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
/// every writer is a chart day mapping). In-memory only: the panel is a
/// view-mode, not data.
final cycleDayPanelProvider = StateProvider<DateTime?>((ref) => null);
