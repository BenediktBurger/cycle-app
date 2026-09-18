// Riverpod providers for the app's state: the single open database, live
// entry streams and cross-screen selection state (tab index, locale, the
// date pre-selected in the entry form).
//
// Simple in-memory state only by design at this milestone:
//  - locale resets to the system default on web reload (documented
//    limitation; see the doc comment on [localeProvider] and
//    docs/roadmap.md),
//  - the PIN lock stub (Settings screen) is non-functional and local.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/cycle_database.dart';
import 'db/database_opener.dart';
import 'db/mappers.dart';
import 'domain/date_only.dart';
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

/// The profile all M1 UI reads/writes. Multi-profile (partner mode) is in
/// the schema, but deliberately not exposed in the M1 UI.
const int defaultProfileId = 1;

/// Live stream of the tracked days (as pure domain models) for the default
/// profile — the single source of truth behind Tagebuch, Zyklus and
/// Statistik screens. Re-emits on every write.
final dailyEntriesProvider =
    StreamProvider.autoDispose<List<DailyEntry>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.entriesDao
      .watchAll(defaultProfileId)
      .map((rows) => rows.map(dailyEntryFromDrift).toList());
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

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).
final selectedDateProvider =
    StateProvider<DateTime>((ref) => DateOnly.normalize(DateTime.now()));
