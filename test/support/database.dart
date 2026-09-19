// Shared widget-test harness: the in-memory drift database override and the
// app scope builder used by every test that pumps the real app (CycleApp)
// against a fresh database — no files, no platform channels, no FFI paths.
//
// All pins are optional; leaving one out keeps the provider at its real
// default, which is exactly what the "system follows the device" tests rely
// on (see locale_test.dart / theme_mode_setting_test.dart).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Creates the in-memory [CycleDatabase] used by the widget-test harnesses.
///
/// `closeStreamsSynchronously: true` is drift's documented remedy for widget
/// tests failing with "A Timer is still pending even after the widget tree
/// was disposed": without it, drift delays query-stream cancellation by one
/// event-loop turn (Timer.run), and streams cancelled while Riverpod disposes
/// the ProviderScope during tree teardown can never reach that turn in the
/// test's fake async zone.
///
/// The scope override closes the instance together with the test's
/// ProviderScope (same closing semantics as the production provider).
CycleDatabase inMemoryCycleDatabase() {
  return CycleDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}

/// The databaseProvider override: a fresh in-memory database per scope.
///
/// [seed] runs inside the database future — that guarantees the form (which
/// reads only through databaseProvider.future) sees the seeded day. [onCreated]
/// hands the created instance to the caller (for assertions against what was
/// actually STORED).
Override inMemoryDatabase({
  Future<void> Function(CycleDatabase db)? seed,
  void Function(CycleDatabase db)? onCreated,
}) {
  return databaseProvider.overrideWith((ref) async {
    final db = inMemoryCycleDatabase();
    onCreated?.call(db);
    ref.onDispose(db.close);
    await seed?.call(db);
    return db;
  });
}

/// App scope for the widget smoke tests: wraps the real app in a
/// ProviderScope over a fresh in-memory database. Every pin is optional and
/// null means "leave the provider at its real default":
///
///  - [locale]: the system language (the settings' "System" option),
///  - [themeMode]: follow the device brightness ("System"),
///  - [now]: the real wall clock,
///  - [selectedDay]: today (the provider's real default),
///  - [entriesStream]: the provider's real database-backed stream (the
///    override replaces it wholesale — broadcast streams let the diary and
///    the cycle chart listen at the same time).
///
/// [seed] and [onCreated] reach the database override ([inMemoryDatabase]).
ProviderScope appScope({
  Locale? locale,
  ThemeMode? themeMode,
  Future<void> Function(CycleDatabase db)? seed,
  void Function(CycleDatabase db)? onCreated,
  DateTime Function()? now,
  DateTime? selectedDay,
  Stream<List<DailyEntry>>? entriesStream,
}) {
  return ProviderScope(
    overrides: [
      inMemoryDatabase(seed: seed, onCreated: onCreated),
      if (locale != null) localeProvider.overrideWith((ref) => locale),
      if (themeMode != null) themeModeProvider.overrideWith((ref) => themeMode),
      if (now != null) nowProvider.overrideWith((ref) => now),
      if (selectedDay != null)
        selectedDateProvider.overrideWith((ref) => selectedDay),
      if (entriesStream != null)
        dailyEntriesProvider.overrideWith((ref) => entriesStream),
    ],
    child: const CycleApp(),
  );
}
