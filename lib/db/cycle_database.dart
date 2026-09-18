// The app's drift database (schema version 9, profile-free).
//
// File organization: the DAO files (entries_dao.dart, marks_dao.dart) are
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

@DriftDatabase(
  tables: [CycleEntries, UserMarks],
  daos: [EntriesDao, MarksDao],
)
class CycleDatabase extends _$CycleDatabase {
  // Accepts any QueryExecutor; tests pass NativeDatabase.memory(), the
  // platform wiring (lib/db/database_opener.dart) passes a lazy
  // native/wasm executor.
  CycleDatabase(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Pre-release policy: the app is unpublished, no database with real
          // data exists anywhere, so upgrades carry no compatibility
          // obligation. Every upgrade drops the app's tables and recreates
          // them from the current schema, which keeps schema work cheap:
          // changing the schema is then just bumping [schemaVersion] above.
          // `deleteTable('profiles')` stays so an old (v8) database file
          // loses its legacy profiles table too — nothing recreates or
          // re-seeds it (the schema is profile-free).
          //
          // From the FIRST PUBLISHED RELEASE on this must become real one
          // version step at a time migrations that preserve user data.
          await m.deleteTable('cycle_entries');
          await m.deleteTable('user_marks');
          await m.deleteTable('profiles');
          await m.createAll();
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
