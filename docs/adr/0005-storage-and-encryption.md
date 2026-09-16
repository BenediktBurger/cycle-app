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
