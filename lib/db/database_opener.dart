// Platform-specific database opening — the ONLY place importing
// drift_flutter. Kept separate from lib/db/cycle_database.dart so the core
// schema/DAO library stays compilable for pure-Dart host scripts and tests.
//
// Executor decision table (ADR-0003/ADR-0005), resolved via drift_flutter's
// `driftDatabase()` which performs the conditional per-platform dispatch in
// one call:
//
//  - Native (Android/iOS/desktop): a background-isolate NativeDatabase over
//    `<application documents>/<databaseName>.sqlite` (directory resolved
//    via path_provider, now a direct dependency). The file is ALWAYS-ON
//    ENCRYPTED: the `hooks: user_defines: sqlite3` block in pubspec.yaml
//    pulls SQLite3MultipleCiphers in as the sqlite3 package's bundled
//    SQLite engine (compiled by the hook from the amalgamation vendored
//    under native/sqlite3mc/, no build-time download), and the native
//    `setup` below applies
//    the key from flutter_secure_storage (lib/db/db_key.dart) via
//    `PRAGMA key` before drift touches the database. There is no settings
//    toggle; the setup verifies that the cipher build is actually present
//    (`PRAGMA cipher`) and refuses to open otherwise — the shared steps
//    live in lib/db/cipher_setup.dart. Losing the platform key store
//    (e.g. a restore that copies the file without it) makes the database
//    unreadable — the JSON export is the user-level backup (ADR-005).
//  - Web (the iteration test target): drift's `WasmDatabase.open` — SQLite
//    compiled to WebAssembly (`web/sqlite3.wasm`) driven by the drift worker
//    (`web/drift_worker.js`), with the storage implementation selected
//    dynamically: OPFS when available, otherwise IndexedDB (both persist
//    across reloads on https/localhost origins). UNENCRYPTED — a documented
//    limitation (ADR-005); the hook build applies to the sqlite3 ffi/dart
//    side only, never to the web assembly assets.
//
// Asset maintenance: `web/sqlite3.wasm` + `web/drift_worker.js` are vendored
// from the tag-matching drift release (currently drift 2.35.x; the pubspec
// pins the same minor line). When bumping drift, re-download BOTH files from
// `https://github.com/simolus3/drift/releases/tag/drift-<version>` into
// `web/` and reference them from the [DriftWebOptions] below.
// See CONTRIBUTING.md §"web assets".
//
// Intentionally NOT used here: a CDN fallback URI. If the assets are missing
// from the served build, opening fails visibly instead of silently
// degrading to an ephemeral in-memory dataset — the UI surfaces this error
// on the splash screen.
//
// NOTE: never hold two [CycleDatabase] instances over the same name/file at
// once (file locks on native, duplicated storage on web); the Riverpod
// provider in lib/providers.dart guarantees the single instance for the app
// lifetime.
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import 'cipher_setup.dart';
import 'cycle_database.dart';
import 'db_key.dart';

/// Storage file/stream name of this app's drift database. On native this
/// becomes `cycle_storage.sqlite` inside the application documents
/// directory; on web it names the OPFS/IndexedDB storage slot.
const String databaseName = 'cycle_storage';

/// Opens the platform-appropriate database.
///
/// Tests construct `CycleDatabase(NativeDatabase.memory())` directly and
/// therefore never call this function; call sites use the Riverpod
/// [databaseProvider] instead of this factory directly.
///
/// Fails (never falls back) when the encryption key cannot be loaded from
/// the platform's secure storage or created there on first use — see
/// lib/db/db_key.dart.
Future<CycleDatabase> openCycleDatabase() async {
  // Web: the exact pre-encryption wiring, untouched. No key store access —
  // web storage stays unencrypted.
  if (kIsWeb) {
    return CycleDatabase(
      driftDatabase(
        name: databaseName,
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      ),
    );
  }

  // Native: encrypted by default. The key is resolved up front (before the
  // executor even exists) so a key-store failure surfaces immediately;
  // `setup` then runs inside the database's background isolate and applies
  // the key before drift issues any statement.
  final key = await loadOrCreateDbKey();
  return CycleDatabase(
    driftDatabase(
      name: databaseName,
      native: DriftNativeOptions(
        // Same directory the (drift_flutter) native default resolved
        // before: application documents + `$databaseName.sqlite`.
        databaseDirectory: getApplicationDocumentsDirectory,
        setup: (rawDb) => applyCipherAndKey(rawDb, key),
      ),
    ),
  );
}
