# Contributing

Setup path, daily commands, and project conventions. Open work and upcoming
milestones are tracked in [`docs/roadmap.md`](docs/roadmap.md).

## 1. Install the Flutter SDK (stable channel)

The official quick-start guide at
<https://docs.flutter.dev/install/quick> is **the** source of truth for
installing the stable SDK. We do **not** require a specific folder — any
location works as long as `<sdk>/bin` is on your PATH — but we recommend
`~/flutter` as a typical path. Put the `PATH` export into your shell profile
(`~/.bashrc` / `~/.zshrc`) so it persists, then verify:

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
```

`flutter doctor` will complain about missing Android Studio / Xcode etc. —
that is fine for the web iteration target. What you need for everything below
is only the Flutter SDK itself.

## 2. Platform scaffolding

`android/`, `ios/`, `.metadata` and the IDE module files exist at the repo
root (project name `cycle_app`). You do not need to regenerate them normally.

If platform files ever go missing or need (re)generation, run from the repo
root:

```sh
flutter create --platforms=android,ios --project-name cycle_app .
```

`flutter create .` **preserves already-existing files**, so it is always the
safe route.
Always run `git status` right afterwards.

## 3. Fetch dependencies and run

```sh
flutter pub get
flutter run -d chrome
```

`-d chrome` runs the app as a Flutter web app in Chrome — that is the
iteration/test target (see
[ADR-0003](docs/adr/0003-target-platforms-web-iteration.md)); the product
targets Android + iOS.

### Web assets (drift wasm database)

On web the app opens its database through drift's WebAssembly SQLite
(`WasmDatabase`). This needs two files **vendored into `web/`** (committed to
the repo so the build never depends on a CDN):

- `web/sqlite3.wasm`
- `web/drift_worker.js`

Both are taken from the tag-matching [drift release]
(https://github.com/simolus3/drift/releases) — currently the `drift-2.35.0`
release, matching the `drift: ^2.35.0` pin in `pubspec.yaml`. **When bumping
drift, re-download both files from the new release tag** into `web/`
(names unchanged). They are referenced from
`lib/db/database_opener.dart` (`DriftWebOptions`); if they are missing from
a served build, the app shows the database error screen instead of silently
losing persistence. The persistence medium is picked per browser (OPFS when
supported, else IndexedDB) — data survives a normal page reload, but
clearing site data/private windows do not (expected browser behaviour).

## 4. Analyze, test, build

```sh
flutter pub get    # prerequisite of test runs (also runs gen-l10n)
flutter analyze
flutter test
flutter build web
```

All three must pass before you push. CI runs exactly these (see
[.github/workflows/ci.yml](.github/workflows/ci.yml) and
[ADR-0006](docs/adr/0006-ci.md)).

**Linux note (database tests):** the drift tests under `test/db/` open the
real SQLite engine through `sqlite3`'s dart:ffi bindings on the host.
Debian/Ubuntu need the dev library once (`sudo apt-get install
libsqlite3-dev`); CI installs it in the workflow. macOS and Windows SDK
test runs bundle/resolve it themselves. Two host-VM smoke scripts execute
core assertions without the test runner (useful when hunting failures):

```sh
~/flutter/bin/dart run tool/db_smoke.dart            # schema/DAO/domain
~/flutter/bin/dart run tool/smoke_export_import.dart # export/import round trip
```

## 5. JSON export/import limits

- **Export paths differ per platform on purpose** — no file-picker/share
  plugin dependencies: Settings → JSON export shows the whole document
  as copyable text on ALL platforms; a file save/download additionally
  exists on web (browser download) and on desktop (written next to the
  user's home directory, when `HOME`/`USERPROFILE` is set).
- **Android/iOS:** iOS offers the copy path instead of a share sheet today;
  a share/picker requires a plugin dependency, to be added when the need
  arises.
- **Import:** paste the exported JSON into the settings import dialog
  (web additionally offers a file picker). Merge policy: merges by
  (profile, day) with **overwrite** of conflicting days; known marks are
  skipped (idempotent); unknown profiles are re-created. A summary counts
  new/overwritten/skipped rows.
- The JSON document format is schema-versioned (`schema_version: 1`); the
  codec and merge planner are pure logic under `lib/domain/export_import.dart`
  (unit-tested in `test/domain/`), the database adapter lives in
  `lib/db/export_adapter.dart`.

If `flutter analyze` or `flutter test` fails with hand-written code, please
report the full analyzer/test output back so issues can be fixed promptly.

## Conventions

- **Architecture decisions** get an ADR under
  [`docs/adr/`](docs/adr/README.md) — one numbered Markdown file with the
  sections Title / Date / Status / Context / Decision / Consequences; the
  status vocabulary (Accepted / Hypothesis / Proposed) is defined there.
- **Localization** is German-first via `flutter gen-l10n` (`l10n.yaml`,
  `lib/l10n/`), with English mirrored. Add new UI strings to both
  `.arb` files.
- **Package name** `cycle_app` is a placeholder ([ADR-0002](docs/adr/0002-package-name-cycle-app-placeholder.md));
  do not rely on it in code
- **Unresolved working assumptions** are marked in code and docs — in
  particular the overall "Mode M" product shape
  ([ADR-001](docs/adr/0001-iner-mode-m-hypothesis.md), status: Hypothesis),
  the NFP 0–4 mucus mapping table (`lib/domain/mucus.dart`,
  `// TODO(user-review)`), the cycle-boundary rule
  (`lib/domain/cycle_grouping.dart`), and the statistics bucket edges
  (`lib/domain/statistics.dart`). Treat marked comments like
  `// TODO(user-review)` as questions to bring to INER experts, not as
  settled behavior.
- **In-memory-only state for now**: the language selection resets to German
  on web reload by design (persisting it — e.g. a settings table or
  localStorage — is future work; see `localeProvider` in
  `lib/providers.dart`).
