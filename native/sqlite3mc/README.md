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
  https://github.com/utelle/SQLite3MultipleCiphers/releases/download/v2.6.1/sqlite3mc-2.6.1-sqlite-3.54.0-amalgamation.zip
  (from the tooling the `sqlite3` package itself pins in
  `tool/download_sqlite.dart` at tag `sqlite3-3.7.1`)
- Content: SQLite3MultipleCiphers 2.6.1 built on SQLite 3.54.0.
  Only `sqlite3mc_amalgamation.c` and `sqlite3mc_amalgamation.h` from the
  archive are vendored here (the same two files the `sqlite3` project's
  download script copies).
- Vendored on 2026-10-19 by `dart run tool/sqlite3mc.dart update`.
- SHA-256:
  - `sqlite3mc_amalgamation.c`
    9b129d1ceb2c7d5dbf374b833eb29a640ecfa8e4a5af6d48508b429019c707b0
  - `sqlite3mc_amalgamation.h`
    99b3e6997aa5fc604d9ea2352e6ae89dfd4d0af8d5bd7cbfe7293d959779e6eb

## Licensing

The SQLite3MultipleCiphers extension is MIT (Copyright (c) 2019-2026
Ulrich Telle); the embedded original SQLite sources are public domain
(SQLite "blessing"). The amalgamation is self-contained: no extra
libraries beyond `libm` (linked by the hook on Android) and no OpenSSL
(that is only needed when compiling the SQLCipher fork).

## Refreshing

The automated alternative to the manual procedure below:

```
dart run tool/sqlite3mc.dart check    # integrity + upstream drift (also in CI)
dart run tool/sqlite3mc.dart update   # refresh vendored files + this block
```

1. Check which amalgamation the current `sqlite3` package release pins
   (`tool/download_sqlite.dart` at the corresponding
   `sqlite3.dart` tag), download that exact archive, and replace the two
   files here after comparing the README release notes in the archive.
2. Update the version facts + SHA-256 hashes in this file.
3. Rebuild and run the test gate (CONTRIBUTING.md §4); the cipher
   feature only needs to keep satisfying `PRAGMA cipher` being set on
   open (`lib/db/database_opener.dart`).
