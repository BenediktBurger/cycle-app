// The raw SQLite setup steps that key an encrypted native database
// (ADR-0005) — shared verbatim by the production opener
// (lib/db/database_opener.dart) and the host-side mechanics test
// (test/db/native_encryption_mechanics_test.dart), so the test exercises
// the SAME setup logic production runs instead of a hand-copied variant.
//
// Kept in its own module (not the opener library) on purpose: it imports
// only package:sqlite3, no drift_flutter/path_provider, so both the opener
// and any test or host script can pull it in without native-only
// dependencies.
import 'package:sqlite3/common.dart';

/// Escapes a database key for inlining into the single-quoted `PRAGMA key`
/// statement (the pragma does not take prepared statements, the docs
/// pattern inlines it; our generated keys are hex-only, the escaping is
/// routine robustness).
String _pragmaKeyString(String key) => key.replaceAll("'", "''");

/// Applies the cipher-presence tripwire and the encryption key to a raw
/// native database handle. This runs inside the database's background
/// isolate, before drift issues any statement. The handle arrives as
/// drift's setup type [CommonDatabase].
///
/// The cipher check is UNCONDITIONAL (not a debug-only assert): vanilla
/// SQLite has no `cipher` pragma, SQLite3MultipleCiphers does. If it comes
/// back empty, the hook user-define in pubspec.yaml is missing from the
/// build — and `PRAGMA key` would then silently no-op, running a
/// misconfigured release build unencrypted as if it were protected. The
/// clear failure costs one query per open; that trade is deliberate.
void applyCipherAndKey(CommonDatabase rawDb, String key) {
  final cipher = rawDb.select('PRAGMA cipher;');
  if (cipher.isEmpty) {
    throw UnsupportedError(
      'The SQLite build behind the native database has no cipher support '
      '(empty `PRAGMA cipher`) — the sqlite3 hook user-define in '
      'pubspec.yaml did not apply. Refusing to open, because `PRAGMA key` '
      'would silently no-op and the database would run unencrypted.',
    );
  }
  rawDb.execute("PRAGMA key = '${_pragmaKeyString(key)}'");
}
