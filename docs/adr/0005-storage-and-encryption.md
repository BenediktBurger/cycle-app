# ADR-0005: Storage drift/SQLite; encryption split native-SQLCipher vs. web-none

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

Cycle data is highly sensitive personal data. Storage requirements: local-only
(no cloud, no analytics — req. 7), Android + iOS + web (web = iteration target,
ADR-0003), versioned schema migrations, typed queries, streams for reactive
UI. Candidates: raw SQLite helpers, drift (over SQLite), Hive/Isar-style
NoSQL, plain JSON files.

Encryption: on native mobile, at-rest encryption of the DB is highly desirable
(SQLCipher). On web, there is **no equivalent** for a transparently encrypted
browser-local database (IndexedDB/OPFS-backed storage cannot be
SQLCipher-encrypted; a WASM SQLCipher would still leave browsers' storage
plumbing uninitialized outside our control and is out of scope).

## Decision

- **Storage: drift (SQLite)** — type-safe, works on Android/iOS/web/desktop,
  built-in versioned migrations; native SQLite via `sqlite3_flutter_libs`;
  on web drift's `WasmDatabase` (IndexedDB/OPFS-backed). The DB lands in
  Phase 2; the M1 app shell intentionally runs **without** a database.
- **Encryption plan is a documented split, not symmetric:**
  - **Native (Android/iOS): SQLCipher later**, via `sqlcipher_flutter_libs`
    — deliberately **kept OUT of the M1 pubspec** (it arrives when encryption
    is wired up in a later milestone; adding it earlier would break the web
    build anyway since it is native-only).
  - **Web: no at-rest encryption** — a **documented limitation**. The browser
    environment is trusted as-is for the iteration target; mitigation is
    **PIN lock only on web** at app level (real password/biometric lock uses
    `flutter_secure_storage` on native later — req. 6, native/web asymmetry
    per ADR-0003).

## Consequences

- Pros: strongly typed schema, DAOs, migrations for schema evolution across
  milestones; one storage API for mobile and web; reactive streams map
  cleanly to Riverpod providers.
- WIP exception — destructive upgrades while the app is unpublished: until
  the first published release, every schema upgrade recreates the database
  from the current schema and discards all data (a change is just a
  schema-version bump). From that release on, upgrades must be real
  incremental migrations, one version step at a time, that preserve user
  data.
- Web limitation must be surfaced to the user visibly (PIN lock placeholder +
  docs), and it is acceptable because web is the **iteration target**, not the
  product's privacy guarantee — native mobile is where the real
  confidentiality bar applies and SQLCipher later meets it.
- The export/import feature (JSON in Settings) doubles as a user-controlled
  backup path, which also mitigates browser-storage risks on web.
- Migration to SQLCipher later must include a data-remigration/story from
  unencrypted → encrypted DB (handled in the later milestone that introduces
  it, not swept under the rug).

## Amendment 2026-09-21: SQLite3MultipleCiphers instead of SQLCipher, always-on

**Status: Accepted (amends the encryption decision above; storage choice
unchanged).** The original text above is kept for the record; where it
conflicts with this amendment, the amendment governs.

Since this ADR was written, the `sqlite3` package (3.x) gained build hooks:
a pubspec-level user-define supplies **SQLite3MultipleCiphers** as the
SQLite library drift's `NativeDatabase` uses — no `sqlcipher_flutter_libs`
and no separate native plugin (the drift ≥ 2.32 pattern, documented at
[drift → platforms → encryption](https://drift.simonbinder.eu/platforms/encryption/)).
SQLCipher is no longer supported with a straightforward setup in that
toolchain.

Decision change:

- **Native (Android/iOS): at-rest encryption is always-on.** There is no
  settings toggle and no opt-out. `lib/db/database_opener.dart` applies the
  key via `PRAGMA key` in the native database's `setup`, before drift
  issues any statement, and verifies the cipher build's presence on every
  open (`PRAGMA cipher` empty → the open fails loudly, since the key would
  silently no-op on a SQLite build without cipher support).
- **Key: a random 32-byte value** (hex-encoded) stored in the platform's
  protected store via `flutter_secure_storage` (Android Keystore-backed
  storage / iOS Keychain) — see `lib/db/db_key.dart`. There is **no user
  passphrase**. Key-store failures are fatal at open time (the app must
  never fall back to an unencrypted database silently).
- **No migration shipped.** The feature landed pre-release, so there are
  no published devices to migrate: dev devices simply get a one-time
  app-data wipe (the old plaintext file is discarded, not re-keyed).
  From the first published release on, any change to the encryption setup
  needs a real migration story, like every other schema-adjacent change
  (see the WIP exception in the consequences above).
- **Web: unchanged — still unencrypted**, the documented limitation above.
  The hook user-define only affects the ffi/dart side, not the vendored
  wasm assets.
- **Residual risk (accepted):** the key is device-bound. A platform-level
  restore that carries the database file to a new device without the
  platform key makes that file permanently unreadable; losing or wiping
  the key store while the file survives has the same effect. The mitigation
  is the existing user-level **JSON export** (Settings), which remains the
  backup path for such cases.
- **Not yet verified:** the encryption feature has never run on a physical
  Android/iOS device (no device was available when it was implemented).
  On-device verification is pending: the key flow through the real
  `flutter_secure_storage` (Android Keystore / iOS Keychain behavior) is
  exercised only by host-side integration tests so far.
