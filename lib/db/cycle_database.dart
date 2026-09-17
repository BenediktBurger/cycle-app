// The app's drift database (schema version 7).
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultProfile();
        },
        onUpgrade: (m, from, to) async {
          // Pre-release policy: the app is unpublished, no database with real
          // data exists anywhere, so upgrades carry no compatibility
          // obligation. Every upgrade drops the app's tables and recreates
          // them from the current schema, which keeps schema work cheap:
          // changing the schema is then just bumping [schemaVersion] above.
          // Also: `PRAGMA foreign_keys` is still OFF at this point (it is
          // only enabled in beforeOpen below), so the drop order cannot
          // trip over the profile references.
          //
          // From the FIRST PUBLISHED RELEASE on this must become real one
          // version step at a time migrations that preserve user data.
          await m.deleteTable('cycle_entries');
          await m.deleteTable('user_marks');
          await m.deleteTable('profiles');
          await m.createAll();
          await _seedDefaultProfile();
        },
        // SQLite only enforces FOREIGN KEY constraints when the pragma is
        // enabled for the connection; make that explicit. Idempotent if
        // drift's defaults already set it.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  /// Seeds the default profile so `profile_id` defaults (1) reference a valid
  /// row from the very first open — used by both onCreate and the destructive
  /// onUpgrade path.
  Future<void> _seedDefaultProfile() =>
      into(profiles).insert(ProfilesCompanion.insert(name: 'main'));
}
