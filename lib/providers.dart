// Riverpod providers for the app's state: the single open database, live
// entry streams and cross-screen selection state (tab index, locale, the
// date pre-selected in the entry form).
//
// Simple in-memory state only by design at this milestone:
//  - locale resets to the system default on web reload (documented
//    limitation; see the doc comment on [localeProvider] and
//    docs/roadmap.md),
//  - the theme mode resets to System on web reload for the same reason
//    (see the doc comment on [themeModeProvider]),
//  - the PIN lock stub (Settings screen) is non-functional and local.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/cycle_database.dart';
import 'db/database_opener.dart';
import 'db/mappers.dart';
import 'domain/date_only.dart';
import 'domain/marks.dart';
import 'domain/models.dart';

/// The one open database for the app lifetime. `FutureProvider` (without
/// autoDispose) keeps the instance cached; disposing the ProviderScope
/// closes it. UI screens wait on it via the splash gate in main.dart, so
/// everything downstream can `ref.read(databaseProvider.future)`.
final databaseProvider = FutureProvider<CycleDatabase>((ref) {
  final db = openCycleDatabase();
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
/// In-memory only at this milestone: switching works immediately but resets
/// on web reload BY DESIGN (persisting it would mean a settings table in
/// drift or localStorage — the drift database itself is the only durable
/// state for now). Persistence is a documented TODO:
/// - on web, localStorage would be the natural place,
/// - on native, a drift settings table (or SharedPreferences) would fit.
/// Recorded in docs/roadmap.md as the language-persistence TODO.
final localeProvider = StateProvider<Locale?>((ref) => null);

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// In-memory only, mirroring [localeProvider]: switching works immediately
/// but resets to System on web reload BY DESIGN (see the persistence note
/// there — no settings table in drift at this milestone).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

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
