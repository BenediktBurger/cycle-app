# Contributing

Contributions are very much appreciated — there are many ways to help, and
several need no code at all:

- **Translations** — add or improve strings in the `.arb` files
  (German-first with English mirrored).
- **Bug reports and feature suggestions**
- **Fixing texts** — wording, grammar, and clarity in UI strings and docs.
- **Improving the UI** — usability, layout, visual polish.
- **Implementing features**

Whatever you take on, a few expectations keep the project consistent; the
details live in [AGENTS.md](AGENTS.md). In brief:

- **Improvement notes have fixed destinations**: agent behavior you want
  changed → a rule in AGENTS.md; doubts about a decision → the ADR in
  question; actual work items → the backlog of
  [`docs/roadmap.md`](docs/roadmap.md).
- **Roadmap readiness**: only checkbox items (`- [ ]`) are ready to
  implement; plain bullets are under discussion — ask instead of guessing
  scope.
- **No work-package IDs** in code, docs, or tool/file names.
- **Run the full test gate** before you consider work done:
  `flutter analyze` and `flutter test --no-pub -r expanded` (why that
  reporter: [AGENTS.md](AGENTS.md); commands: section 4 below).

Setup path and daily commands below; open work is tracked in
[`docs/roadmap.md`](docs/roadmap.md), architecture decisions in
[`docs/adr/`](docs/adr/README.md). Release and publishing (local APKs,
F-Droid, Google Play) follow the runbook in
[`docs/release.md`](docs/release.md), with the decisions recorded in
[ADR-0009](docs/adr/0009-release-pipeline-and-signing.md).

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

### Running on your own Android device

The Android toolchain setup (JDK, SDK, licenses) is described in
[`docs/release.md`](docs/release.md), Phase A. Once `flutter devices` lists
your phone (or emulator), you can run the app directly on it:

```sh
flutter devices                        # connected devices / emulators
flutter run -d <device-id>             # debug build with hot reload
flutter run --release -d <device-id>   # closer to production behaviour
```

To install without a running session, build an APK once and either install
via adb or sideload manually:

```sh
flutter build apk --release            # universal APK; debug-signed locally is fine for testing
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Sideload without adb: copy
`build/app/outputs/flutter-apk/app-release.apk` to the phone (USB file
transfer, KDE Connect, …), open it with the file manager, and allow
"install unknown apps" for that app when prompted.

**adb over Wi-Fi (Android 11+):** enable *Developer options → Wireless
debugging* on the phone, then:

```sh
adb pair <ip>:<pair-port>   # pairing code shown under "Pair device with pairing code"
adb connect <ip>:<port>     # port from "IP address & port"
```

Phone and machine must be on the same Wi-Fi network. The pairing port and
the connect port are different numbers — both are shown on the Wireless
debugging screen. Pairing is a one-time step; the connect port changes
whenever wireless debugging is toggled or the phone reboots, so re-run
`adb connect` with the current port. Afterwards `flutter run -d
<device-id>` works over Wi-Fi as well.

## 4. Analyze, test, build

The local gate mirrors [.github/workflows/ci.yml](.github/workflows/ci.yml)
(see [ADR-0006](docs/adr/0006-ci.md) for the decision):

```sh
flutter pub get    # prerequisite of test runs (also runs gen-l10n)
flutter analyze
dart format --output=none --set-exit-if-changed .   # check-only
flutter test
flutter build web
```

All four checks must pass before you push. To fix formatting instead of
merely checking it, run a plain `dart format .` (only the check variant is
part of the gate).

`flutter build apk --debug` is available locally as well once the local
Android toolchain is green (see [`docs/release.md`](docs/release.md),
Phase A) — the web build remains the primary correctness gate until then.

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
- The JSON document format is schema-versioned (`schema_version`); the
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
  particular the open questions (`TODO(user-review)`) in
  [ADR-0008](docs/adr/0008-cycle-start-as-mark.md), the statistics
  bucket edges (`lib/domain/statistics.dart`), and per-rule interpretation
  questions under `lib/domain/evaluation.dart` (the overall "Mode M"
  product shape itself is settled —
  [ADR-0001](docs/adr/0001-iner-mode-m-hypothesis.md), Accepted). Treat
  marked comments like `// TODO(user-review)` as questions to bring to
  INER experts, not as settled behavior.
