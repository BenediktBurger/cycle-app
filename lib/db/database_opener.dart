// Platform-specific database opening — the ONLY place importing
// drift_flutter. Kept separate from lib/db/cycle_database.dart so the core
// schema/DAO library stays compilable for pure-Dart host scripts and tests.
//
// Executor decision table (ADR-0003/ADR-0005), resolved via drift_flutter's
// `driftDatabase()` which performs the conditional per-platform dispatch in
// one call:
//
//  - Native (Android/iOS/desktop): a background-isolate NativeDatabase over
//    `<application documents>/<databaseName>.sqlite` (directory resolved via
//    path_provider, which drift_flutter brings transitively). The SQLite C
//    library comes from `sqlite3_flutter_libs` (already in pubspec).
//  - Web (the iteration test target): drift's `WasmDatabase.open` — SQLite
//    compiled to WebAssembly (`web/sqlite3.wasm`) driven by the drift worker
//    (`web/drift_worker.js`), with the storage implementation selected
//    dynamically: OPFS when available, otherwise IndexedDB (both persist
//    across reloads on https/localhost origins).
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

import 'cycle_database.dart';

/// Storage file/stream name of this app's drift database. On native this
/// becomes `cycle_storage.sqlite` inside the application documents
/// directory; on web it names the OPFS/IndexedDB storage slot.
const String databaseName = 'cycle_storage';

/// Opens the platform-appropriate database.
///
/// Tests construct `CycleDatabase(NativeDatabase.memory())` directly and
/// therefore never call this function; call sites use the Riverpod
/// [databaseProvider] instead of this factory directly.
CycleDatabase openCycleDatabase() {
  return CycleDatabase(
    driftDatabase(
      name: databaseName,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
      // Native defaults are correct for us: documents directory +
      // background-isolate execution already provide safety + persistence.
    ),
  );
}
