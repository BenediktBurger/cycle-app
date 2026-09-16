// The app's drift database (schema version 2).
//
// File organization: the DAO files (entries_dao.dart, marks_dao.dart,
// profiles_dao.dart) are PARTS of this library. That is the standard drift
// layout when DAOs reference generated data classes — drift writes all data
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
part 'profiles_dao.dart';

@DriftDatabase(
  tables: [Profiles, CycleEntries, UserMarks],
  daos: [EntriesDao, MarksDao, ProfilesDao],
)
class CycleDatabase extends _$CycleDatabase {
  // Accepts any QueryExecutor; tests pass NativeDatabase.memory(), the
  // platform wiring (lib/db/database_opener.dart) passes a lazy
  // native/wasm executor.
  CycleDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed the default profile so profile_id defaults (1) reference a
          // valid row from the very first open.
          await into(profiles).insert(ProfilesCompanion.insert(name: 'main'));
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _rebuildCycleEntriesWithoutLegacyMucusColumns(m);
          }
          // v2 -> future: extend here, one version step at a time.
        },
        // SQLite only enforces FOREIGN KEY constraints when the pragma is
        // enabled for the connection; make that explicit. Idempotent if
        // drift's defaults already set it.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  /// v1 -> v2 upgrade step: removes the two retired legacy mucus columns
  /// (a free-text feeling column and a numeric 0–4 value column) from
  /// cycle_entries and introduces mucus_sign / mucus_quality as NULL.
  ///
  /// Plain `ALTER TABLE ... DROP COLUMN` is deliberately NOT used, verified
  /// against the runtime SQLite here: it only succeeds for a column whose
  /// CHECK is written inline (the check is then dropped along with the
  /// column); a table-level CHECK referencing it fails with
  /// "no such column". That nuance alone makes the explicit rebuild the
  /// safer, schema-faithful route, and it re-creates the table exactly as
  /// drift now generates it. The classic rename-copy-drop pattern runs
  /// inside drift's migration transaction (a failure rolls everything back):
  ///
  ///   1. RENAME the old table away
  ///   2. create a fresh cycle_entries from the CURRENT drift schema
  ///   3. copy the surviving columns across (the old column VALUES are
  ///      deliberately not migrated — old days keep every other field and
  ///      start without a mucus observation)
  ///   4. drop the old table
  ///   5. re-create the unique index, which was dropped with the old table
  ///
  /// No data migration of the dropped values (app unpublished; no
  /// compatibility obligations).
  Future<void> _rebuildCycleEntriesWithoutLegacyMucusColumns(Migrator m) async {
    const survivingColumns =
        'id, profile_id, date, bbt_c, bleeding, exclude_illness, '
        'exclude_alcohol, exclude_travel, exclude_other, cervix, pain, '
        'mood, desire, sex, notes, created_at, updated_at';

    await customStatement(
      'ALTER TABLE cycle_entries RENAME TO cycle_entries_old;',
    );
    await m.createTable(cycleEntries);
    await customStatement(
      'INSERT INTO cycle_entries ($survivingColumns) '
      'SELECT $survivingColumns FROM cycle_entries_old;',
    );
    await customStatement('DROP TABLE cycle_entries_old;');

    // Dropping the old table dropped its unique
    // cycle_entries_profile_date_unique index with it; recreate it so the
    // EntriesDao upsert keeps its conflict target.
    await m.createIndex(cycleEntriesProfileDateUnique);
  }
}
