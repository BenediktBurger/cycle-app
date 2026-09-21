// The encryption key of the native database file (ADR-005): 32 fresh random
// bytes, hex-encoded, living in the platform's protected storage (Android
// Keystore-backed preferences / iOS Keychain via flutter_secure_storage).
// The SQLite3MultipleCiphers build (the sqlite3 hook user-define in
// pubspec.yaml) encrypts the database file with this key, applied as
// `PRAGMA key` in lib/db/database_opener.dart.
//
// Threat model: protects the at-rest database file against off-device
// exfiltration (device backups, other apps with storage access, an
// extracted file system). It is not a defense against the app's own
// process or a rooted device.
//
// Loss mode: the key is device-bound. A platform-level restore that copies
// the database file onto a new device without the platform key leaves that
// file permanently unreadable — the JSON export (Settings) is the
// user-level backup path.
//
// Failure behavior: secure-storage errors surface loudly. If the key can
// neither be read nor stored — or a stored key has the wrong shape (a
// corrupted store value; regenerating would brick the existing database) —
// opening the database must FAIL. There is deliberately no silent
// fallback, which would quietly run an unencrypted database as if it were
// protected.
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The secure-storage key under which the database encryption key lives
/// (storage vocabulary, not schema).
const String dbKeyStorageName = 'dbEncryptionKey';

/// The raw key material length in bytes (a 256-bit key). Hex-encoded, this
/// becomes 64 characters of `PRAGMA key` passphrase.
const int dbKeyLength = 32;

/// Raised when the database encryption key cannot be read from or stored in
/// the platform's secure storage. Wraps the original cause so the error
/// surfaces loudly (the database open must fail) instead of degrading to an
/// unencrypted database.
final class DbKeyException implements Exception {
  DbKeyException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DbKeyException: $message'
      : 'DbKeyException: $message (cause: $cause)';
}

/// Read/write access to the key store, abstracted so the load-or-create
/// flow below is testable without platform channels (the production store
/// is [SecureStorageDbKeyStore]).
abstract interface class DbKeyStore {
  Future<String?> read();

  Future<void> write(String value);
}

/// The production key store: flutter_secure_storage, backed by Android's
/// Keystore-encrypted preferences / the iOS Keychain, with defaults chosen
/// by the library.
final class SecureStorageDbKeyStore implements DbKeyStore {
  const SecureStorageDbKeyStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: dbKeyStorageName);

  @override
  Future<void> write(String value) =>
      _storage.write(key: dbKeyStorageName, value: value);
}

/// Generates a fresh database encryption key: 32 cryptographically secure
/// random bytes, hex-encoded ([Random.secure] unless one is injected).
/// Character set and length are fixed, so it never needs escaping beyond
/// the routine quote-doubling the PRAGMA statement does anyway.
String generateDbKey({Random? random}) {
  final rng = random ?? Random.secure();
  return List.generate(
    dbKeyLength,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The shape every stored key must have: 64 lowercase hex characters
/// (32 bytes hex-encoded), exactly what [generateDbKey] produces. A stored
/// value outside this shape means the store is corrupted or holds a
/// foreign value — and a malformed `PRAGMA key` would only fail later,
/// with an unreadable database.
final RegExp _dbKeyFormat = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] has the expected stored-key format (see [_dbKeyFormat]).
bool isWellFormedDbKey(String value) => _dbKeyFormat.hasMatch(value);

/// Loads the database encryption key, on first use generating one and
/// persisting it before returning.
///
/// Throws [DbKeyException] when the key store is unusable — the caller
/// (lib/db/database_opener.dart) must then fail to open the database rather
/// than run it unencrypted. A key that could be generated but not be stored
/// is likewise fatal: an unstored-but-used key would leave the database
/// unreadable after the next restart, so nothing is applied at all.
///
/// A STORED key of the wrong shape (not 64 lowercase hex characters, see
/// [isWellFormedDbKey]) is also fatal: it cannot be the key the database
/// was encrypted with, and silently regenerating a new one would brick the
/// existing database — so this fails loudly like every other key-store
/// error.
Future<String> loadOrCreateDbKey({DbKeyStore? store}) async {
  final keyStore = store ?? const SecureStorageDbKeyStore();

  String? stored;
  try {
    stored = await keyStore.read();
  } catch (e) {
    throw DbKeyException('could not read the database encryption key', e);
  }
  if (stored != null && stored.isNotEmpty) {
    if (!isWellFormedDbKey(stored)) {
      throw DbKeyException(
        'the stored database encryption key has an unexpected format '
        '(expected 64 lowercase hex characters) — the key store is '
        'corrupted or holds a foreign value; refusing to regenerate '
        'silently, which would make the existing database unreadable',
      );
    }
    return stored;
  }

  final key = generateDbKey();
  try {
    await keyStore.write(key);
  } catch (e) {
    throw DbKeyException('could not store the database encryption key', e);
  }
  return key;
}
