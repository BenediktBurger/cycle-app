// The app's drift database (schema version 11, profile-free).
//
// File organization: the DAO files (entries_dao.dart, marks_dao.dart,
// settings_dao.dart) are
// PARTS of this library. That is the standard drift layout when DAOs
// reference generated data classes — drift writes all data
// classes/companions and the _$DaoMixin classes into a single
// cycle_database.g.dart, and parts share the library's scope. Tables live in
// lib/db/tables.dart, converters in lib/db/converters.dart, and the
// drift <-> lib/domain conversion in lib/db/mappers.dart.
//
// This file (core schema + DAOs) deliberately stays free of Flutter and
// platform-opening imports so it compiles for pure-Dart host scripts
// (tool/*_smoke.dart) and tests. Platform-specific database opening lives in
// lib/db/database_opener.dart (the single place importing drift_flutter).
import 'package:drift/drift.dart';

import '../domain/date_only.dart';
import '../domain/models.dart';
import 'converters.dart';
import 'mappers.dart';
import 'tables.dart';

part 'cycle_database.g.dart';

part 'entries_dao.dart';
part 'marks_dao.dart';
part 'settings_dao.dart';

@DriftDatabase(
  tables: [CycleEntries, UserMarks, AppSettings],
  daos: [EntriesDao, MarksDao, SettingsDao],
)
class CycleDatabase extends _$CycleDatabase {
  // Accepts any QueryExecutor; tests pass NativeDatabase.memory(), the
  // platform wiring (lib/db/database_opener.dart) passes a lazy
  // native/wasm executor.
  CycleDatabase(super.executor);

  /// A UI-level reset (the settings pane's danger card): deletes everything
  /// from the TRACKED data tables — cycle_entries and user_marks, both
  /// inside ONE transaction (all-or-nothing) — and reports the removed row
  /// counts. It is deliberately NOT part of the domain export/import module
  /// (that one transfers data; this wipes it) and it deliberately touches
  /// NO app_settings row: settings are user choices (language, theme,
  /// temperature range…), and the onboarding flag must stay so the
  /// completed welcome page does not replay after a data wipe.
  Future<({int entries, int marks})> deleteAllTrackedData() {
    return transaction(() async {
      final entries = await entriesDao.deleteAll();
      final marks = await marksDao.deleteAll();
      return (entries: entries, marks: marks);
    });
  }

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Every upgrade is a graceful, incremental migration: one schema
          // version step at a time, never dropping or recreating anything,
          // so user data always survives (ADR-0005, amendment 2026-09-22 —
          // destructive upgrades are no longer permitted).
          //
          // Files OLDER than v9 have no migration promise (they are
          // pre-release artifacts whose table layouts were never published
          // and are not reconstructed anywhere): the supported steps below
          // still run best-effort for them, nothing is erased, and their
          // old-shaped/orphaned tables are simply left untouched.
          if (from < 10) {
            // The only SQL delta of v9 → v10: the app_settings key-value
            // table appears (ADR-0010); no data is transformed.
            await m.createTable(appSettings);
          }
          // v10 → v11 changed no SQL: the bleeding vocabulary gained its
          // level-5 member at the converter level, and the bleeding column's
          // INTEGER DDL is unchanged (ADR-0010) — nothing to migrate.

          // Each future schema-version bump adds its own guarded block here
          // (e.g. `if (from < 12) { ... }`), using Migrator helpers only
          // (createTable, addColumn, customStatement, …); disruptive table
          // shape changes copy data into the new table instead of dropping
          // anything. Skipped steps (from several versions behind) run every
          // missing block in order, so any distance migrates step-wise.
        },
        // SQLite only enforces FOREIGN KEY constraints when the pragma is
        // enabled for the connection; make that explicit. Idempotent if
        // drift's defaults already set it. (There are no foreign keys left
        // in the profile-free schema; the pragma costs nothing.)
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );
}
