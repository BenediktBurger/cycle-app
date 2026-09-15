# Contributing

This guide is written for the **project owner / user** as a step-by-step setup
path, and doubled as the Phase-1/2 handoff checklist. **Steps 1–2 below are
ALREADY DONE (2026-09-15):** the Flutter SDK is installed and the platform
scaffolding has been generated — see the per-step status markers. **Step 4
(`flutter test`) is NOT yet done:** it could not be executed in the
coding-agent sandbox (loopback bind denial, see §4) and is still pending a
real run by the user or in CI. Later phases only need steps 3–5 in normal
daily use.

## 1. Install the Flutter SDK (stable channel) — ✅ DONE (2026-09-15)

**Status:** done — Flutter stable is installed on this host at `~/flutter`
(currently Flutter 3.47.4 / Dart 3.13.3). Make its `bin` available on PATH,
then verify.

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
```

**Where to install:** the official quick-start guide at
<https://docs.flutter.dev/install/quick> is **the** source of truth for
installing the stable SDK. We do **not** require a specific folder — any
location works as long as `<sdk>/bin` is on your PATH — but we recommend
`~/flutter` as a typical path (the current maintainer install lives there).

Put the `PATH` export into your shell profile (`~/.bashrc` / `~/.zshrc`) so it
persists.

`flutter doctor` will complain about missing Android Studio / Xcode etc. —
that is fine for the web iteration target. What you need for everything below
is only the Flutter SDK itself.

## 2. Generate the platform scaffolding — ✅ DONE (2026-09-15)

**Status:** done. `android/` and `ios/` platform folders plus `.metadata` and
IDE module files exist at the repo root, generated for project name
`cycle_app`. You do NOT need to redo this for M1.

⚠️ **How this actually went here — cautionary tale for the future.** The
scaffolding was NOT created by the safe command below. The project owner had
earlier run `flutter create cycle_app` (which creates a **subfolder**) and
then moved its contents up with `mv cycle_app/* ./`. Two problems:

1. Template non-dotfiles (`README.md`, `pubspec.yaml`, `lib/main.dart`,
   `test/widget_test.dart`, `web/index.html`, …) **overwrote** the project's
   own hand-reviewed files of the same name at the repo root — this is
   literally how the hand-written `README.md` was clobbered by flutter's
   "A new Flutter project" template (repaired 2026-09-15).
2. `mv cycle_app/*` **skips dotfiles** — flutter's `.gitignore`, `.metadata`,
   `.idea/` etc. stayed inside the leftover `cycle_app/` directory or were
   dropped entirely.

**Rule going forward:** never move scaffold output up a level like that. If
platform files are missing or you want to (re)generate, run `flutter create .`
against the existing tree — it **preserves already-existing files**:

```sh
flutter create --platforms=android,ios --project-name cycle_app .
```

(Web is not listed here because `web/index.html` and `web/manifest.json`
already exist in this repo and are preserved untouched — see Phase 1 / the
plan file. `flutter create` never clobbers existing files, so the web pair
survives either way.)

Even so, run `git status` right afterwards: `flutter create` normally
preserves existing files, but verify nothing tracked shows up as *modified* —
if one does, restore it with `git checkout -- <file>` and investigate before
continuing (`flutter create` for web never clobbers `web/manifest.json` and
does not require icon files for a web build).

## 3. Fetch dependencies and run

```sh
flutter pub get
flutter run -d chrome
```

`-d chrome` runs the app as a Flutter web app in Chrome — that is the
iteration/test target (see
[ADR-003](docs/adr/0003-target-platforms-web-iteration.md)); the product
targets Android + iOS.

Note (Phase 2 onwards): running on web with a database needs drift's
`sqlite3.wasm` + worker assets — CONTRIBUTING will be updated in that
milestone; this section is updated then.

## 4. Static analysis and tests

```sh
flutter analyze
flutter test
```

Both must pass before you push. CI will run exactly these steps plus a web
build (see [.github/workflows/ci.yml](.github/workflows/ci.yml)).

**Verified status (2026-09-15):** `flutter analyze` passes with **0 issues**,
`flutter build web` succeeds; `flutter test` compiles (analyzer clean) but
**could not be executed inside the coding-agent's omac sandbox** — the sandbox
denies `bind()` on any 127.0.0.1 port, while `flutter test` spawns
`flutter_tester`, which requires a temporary loopback WebSocket server socket
(`Failed to create server socket (OS Error: Permission denied, errno = 13)`).
Run `flutter test` in a normal terminal outside the sandbox (or rely on CI);
an intent was declared in the omac sandbox log so this limitation is on record.

If `flutter analyze` or `flutter test` fails here, that is very valuable — it
is the first real compile check of hand-written code. Please report the full
analyzer/test output back so issues can be fixed in a follow-up commit.

## 5. Milestone-1 verification checklist

(The list below doubles as an early version of `docs/verification-m1.md`,
added in full when Phase 2/3 wrap up. State of 2026-09-15 after the scaffold
repair is marked inline.)

- [x] Flutter SDK stable installed per **1.** (`~/flutter`, Flutter 3.47.4 /
      Dart 3.13.3)
- [x] Platform scaffolding generated for project name `cycle_app` — but see
      **2.** ⚠️: it happened via `flutter create cycle_app` + `mv cycle_app/* ./`
      (clobbered `README.md`; repaired 2026-09-15). Recommended future
      procedure: `flutter create --platforms=android,ios --project-name
      cycle_app .` from the repo root.
- [x] Scaffold clobber review done — after repair, `git status` shows only
      intended files; leftover `cycle_app.iml` removed; no stray `cycle_app/`
      directory or `.idea/` remains
- [x] `flutter pub get` succeeds
- [x] `flutter analyze` passes with 0 issues
- [ ] `flutter test` passes — blocked in the coding-agent sandbox (loopback
      bind denied, see **4.**); run it in a plain terminal / press CI. The
      test compiles cleanly (analyzer), but the runtime assertion pass has
      not been observed on host yet.
- [ ] `flutter run -d chrome` starts the app; manually verify:
  - [ ] app shell opens with tabs **Tagebuch / Zyklus / Statistik /
        Einstellungen** in German
  - [ ] switching to English (Settings → language) shows the same tabs in
        English (once Phase 2 lands)
  - [ ] entering data and reloading the page keeps the data (once Phase 2
        lands)
  - [ ] JSON export → modify → import works (once Phase 2 lands)
  - [ ] the Statistik screen shows **only arithmetic** (no interpretive or
        status conclusions) (once Phase 2 lands)
- [ ] Push to GitHub → CI green (first true compile check)
- [ ] Report analyzer/test output (successes and failures) back so fixes can
      land in a follow-up commit

## Notes on assumptions flagged for review

Several items in the code and docs are deliberately documented working
assumptions marked for expert review — in particular the overall "Mode M"
product shape ([ADR-001](docs/adr/0001-iner-mode-m-hypothesis.md),
status: Hypothesis), the NFP 0–4 mucus mapping table, and the cycle-boundary
rule. Treat marked comments like `// TODO(user-review)` as questions to bring
to INER experts, not as settled behavior.
