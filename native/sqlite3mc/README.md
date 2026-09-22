# Vendored SQLite3MultipleCiphers amalgamation

The `sqlite3` package's build hook compiles this amalgamation into the
bundled SQLite engine (native platforms) — see the `hooks.user_defines`
block in `pubspec.yaml` (`source: source`, `path:` pointing here). This
makes the build network-free: the package's default `sqlite3mc` source
would download a prebuilt `libsqlite3mc.so` from a GitHub release cast
instead (ADR-0005 amendment; relevant for F-Droid's build-from-source
requirement, docs/release.md Phase E).

## Provenance

- Source archive:
  https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.5.0/sqlite3mc-2.5.0-sqlite-3.53.4-amalgamation.zip
  (from the tooling the `sqlite3` package itself pins in
  `tool/download_sqlite.dart` at tag `sqlite3-3.5.2`)
- Content: SQLite3MultipleCiphers 2.5.0 built on SQLite 3.53.4,
  release date 2026-08-02. Only `sqlite3mc_amalgamation.c` and
  `sqlite3mc_amalgamation.h` from the archive are vendored here (the
  same two files the `sqlite3` project's download script copies).
- SHA-256:
  - `sqlite3mc_amalgamation.c`
    d28339d7a56f3b465720aa9c729f3ca9d429705ea8fda45bb8d034536cecd579
  - `sqlite3mc_amalgamation.h`
    959f37e52c004f179ac0e2a5ce28f7bc58271c1a7d532ce9654484641fc31855

## Licensing

The SQLite3MultipleCiphers extension is MIT (Copyright (c) 2019-2026
Ulrich Telle); the embedded original SQLite sources are public domain
(SQLite "blessing"). The amalgamation is self-contained: no extra
libraries beyond `libm` (linked by the hook on Android) and no OpenSSL
(that is only needed when compiling the SQLCipher fork).

## Refreshing

1. Check which amalgamation the current `sqlite3` package release pins
   (`tool/download_sqlite.dart` at the corresponding
   `sqlite3.dart` tag), download that exact archive, and replace the two
   files here after comparing the README release notes in the archive.
2. Update the version facts + SHA-256 hashes in this file.
3. Rebuild and run the test gate (CONTRIBUTING.md §4); the cipher
   feature only needs to keep satisfying `PRAGMA cipher` being set on
   open (`lib/db/database_opener.dart`).
