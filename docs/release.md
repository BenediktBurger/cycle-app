# Release & publishing runbook

Enactable companion to
[ADR-0009](adr/0009-release-pipeline-and-signing.md): commands, checklists,
and decision gates for getting the app distributed — local test APKs first,
then Google Play and official F-Droid inclusion; iOS later. Work items point
here from [`docs/roadmap.md`](roadmap.md).

Aim of this document: every step should be executable later *without*
re-deriving the reasoning. Reasons live in the ADR; this file is the how.

## Prepare Release

Preparing the first release to the different app stores.

### Where we stand

| Channel                      | Role                             | Blocked by                                                                  |
|------------------------------|----------------------------------|-----------------------------------------------------------------------------|
| Sideload APK                 | development/testing, demo builds | nothing (built on CI unsigned; signed + published locally via the two helper scripts)   |
| Google Play                  | primary store                    | Gate G3 (Phase F; G1 resolved 2026-09)                                      |
| F-Droid (official)           | intermediate, possibly permanent | Gate G2 (Phase E; G1 resolved 2026-09)                                      |
| iOS (TestFlight → App Store) | deferred workstream              | macOS + Apple Developer Program (Phase G)                                   |

Of the one-time setup phases, Phase A (Android toolchain) and Phase C
(signing) are complete — git history and
[ADR-0009](adr/0009-release-pipeline-and-signing.md) record how — and
Phase D is ongoing discipline. One-time setup still open: the remaining
Phase B item (adaptive launcher icon) and Phases E, F, G
behind the gates above. Routine releases skip the phases entirely: they
follow the one-path
[per-release checklist](#per-release-checklist-every-distribution-update):
push a `release/**` branch and CI builds the unsigned per-ABI release
artifacts; the local helper pair (`tool/download_and_sign.dart`, then —
after the mandatory device test — `tool/publish_release.dart`) downloads,
validates, and signs them with the release keystore, and publishes tag +
GitHub Release + assets plus the release-branch PR. The release keystore
never enters GitHub — CI only produces **unsigned** artifacts (ADR-0009
amendments in place).

### Decision gates — resolve before the first store upload

These are one-way doors; nothing below Phase D may start until they close.

- **G1 — applicationId / namespace.** **RESOLVED (owner decision, 2026-09):
  `io.github.benediktburger.cycleapp`** — the GitHub user "BenediktBurger"
  lowercased per reverse-domain convention. `org.iner.*` remains possible
  as a **one-way migration** (applicationIds are frozen after the first
  store upload; a move would need INER's explicit written consent and
  would orphan existing sideload installs unless staged carefully) — only
  if INER ever formally takes over publishing. See ADR-0009 §4.
  - Related: the app **display name** (what users see) is free to change at
    any time — it is explicitly **not decided** yet (working title
    "NER Cycle App" in the store metadata `title.txt` etc., shown to test
    users during testing). Do not treat the identifier as naming the
    product: the package name `cycle_app` remains an internal placeholder
    (ADR-0002) and does not affect the shown name.
- **G2 — license.** Chosen (owner decision, 2026-09): **Apache-2.0** — the
  `LICENSE` file at the repo root carries the full text. **Final
  confirmation before the first store upload is still open**; until then
  the gate blocks F-Droid only for that confirmation, not for the choice
  (Apache-2.0 is F-Droid-acceptable — a free-software license).
- **G3 — publisher/account shape.** Individual Play account first (ADR-0009
  §3). Open sub-question: EU DSA **trader status** for both stores (INER
  endorsement may make "trader" mandatory) and whether/when INER itself
  becomes the publisher of record. If an org registration (Play or Apple)
  becomes real: start the **D-U-N-S** application immediately — it is the
  long-lead-time item.
- **G4 — branding assets** (app name, icon, screenshots) — can be redone at
  will; not a true gate, listed here only because store listings need them.

### Phase B — application identity rename (items 2–4 remaining)

Preparation principle (from [ADR-0002](adr/0002-package-name-cycle-app-placeholder.md)):
everything is coded against the placeholder `cycle_app`, so the rename is
mechanical. Checklist, in order — run the full test gate between sensible
stages and commit stepwise. The first four steps are complete (git
history): `pubspec.yaml` bumped to `version: 0.1.0+1` (the `name:` stays
`cycle_app` per ADR-0002; keep bumping `+N` per distributed build —
per-release checklist), `applicationId` + `namespace` set to
`io.github.benediktburger.cycleapp` in `android/app/build.gradle.kts`,
`MainActivity.kt` relocated to
`android/app/src/main/kotlin/io/github/benediktburger/cycleapp/`
(manifest uses `.MainActivity` relative to the namespace), and the
launcher label set (2026-09) to the working title "NER Cycle App"
(currently shown to test users) as a direct string in the manifest. Remaining:

1. Launcher label: **done (2026-09)** — the manifest label is the direct
   string `android:label="NER Cycle App"`
   (`android/app/src/main/AndroidManifest.xml`); no localized
   `strings.xml` resource was introduced.
2. **Adaptive launcher icon** (replaces the default mipmaps): it must exist
   for any store listing; generate from a vector foreground + background
   (G4), e.g. via Android Studio once or an icon-generation tool.
3. **Before Play upload (hard deadline):** the identifier must be final —
   afterwards it is frozen (ADR-0009 §4).
4. iOS note (Phase G): reuse the exact `applicationId` string as the iOS
   bundle identifier.

Regression check after the rename: full analyze/test gate, then web build +
release APK both build.

### Phase C — signing (complete; custody + status notes)

Current state: the release keystore exists at
`~/keystores/cycleapp-release.jks` (alias `cycleapp-release`), and the
signing wiring is committed in `android/app/build.gradle.kts` — it reads
the gitignored `android/key.properties` and falls back to debug signing
when that file is absent (the CI release build relies on exactly that
fallback; those debug signature blocks are replaced entirely by the local
apksigner step and never reach the published assets).
**Still outstanding before the first signed build:** fill the two literal
`CHANGE-ME` passwords in `android/key.properties` from the password
manager. The release certificate fingerprint is pinned in the committed
`tool/release_fingerprint.txt`; the
[download-and-sign script](#per-release-checklist-every-distribution-update)
refuses to attach any APK whose certificate does not match that pin (see
the sign step of the per-release checklist), and the F-Droid metadata
carries the same value (`AllowedAPKSigningKeys`).

**Custody rules (ADR-0009 §2 — non-negotiable):**

- keystore file + `key.properties` **never** enter the repo
  (`android/.gitignore` already ignores `key.properties`, `**/*.keystore`,
  `**/*.jks`; store the keystore under `~/keystores` anyway, not inside any
  checkout);
- password + keystore backup file(s) into the password manager, **plus two
  offline encrypted copies** on separate media;
- a one-page "how to release from scratch on a new machine" note lives at
  the bottom of this file
  ([Fresh-machine recovery](#fresh-machine-recovery-the-handover-note)) —
  this is also the handover doc for a later INER takeover.

The original creation walk-through (keytool, `key.properties` template,
`build.gradle.kts` wiring snippet) lives in this file's git history;
ADR-0009 §2 covers the rationale.

### Phase D — build, install, upgrade discipline

Build variants (from the repo root):

```sh
flutter build apk --release                 # universal APK — one file, quick for local tests
flutter build apk --release --split-per-abi # smaller per-ABI APKs — the shape the CI release build and the F-Droid recipe use
flutter build appbundle --release           # .aab for Google Play
```

Artifacts land under `build/app/outputs/flutter-apk/`: the universal
`app-release.apk`, and with `--split-per-abi` the three per-ABI APKs
`app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, and
`app-x86_64-release.apk` (and `.../bundle/release/` for the AAB). The
universal APK stays valid for quick local testing; GitHub Releases attach
the three per-ABI APKs only.

Install on a device:

```sh
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

(the per-ABI APK matching the device; the universal APK installs the same
way via `app-release.apk` — see
[CONTRIBUTING.md](../CONTRIBUTING.md), "Running on your own Android
device", for which ABI a device needs).

**Upgrade test (mandatory for every distribution update, ADR-0009 §5):**

1. Install the previous released version (keep one APK of every release
   under `~/keystores`-adjacent storage or a release tag), open the app,
   enter representative data (bleeding, temperature, marks, journal).
2. `adb install -r` the new release **over it**.
3. Verify: journal/chart intact, schema migration ran, export → import
   round-trip still works (`tool/smoke_export_import.dart` logic mirrors
   this; the device test is the real-environment proof).
4. Only then ship.

**Numbers discipline: `version: X.Y.Z+N` in `pubspec.yaml`** — bump `+N`
for every distributed build (Play and F-Droid see the same versionCode).

- `X.Y.Z` is the **versionName** (the user-visible version string); `N`,
  the integer after the `+`, is the **base versionCode** — the only number
  stores, F-Droid, and fastlane changelog naming actually care about.
- The versionCode is monotonically increasing with every published version
  regardless the used versionName.
- How `N` flows: pubspec `+N` → Gradle's `flutter.versionCode` → the
  versionCode embedded in the APKs (wired as `versionCode =
  flutter.versionCode` in the `defaultConfig` of
  `android/app/build.gradle.kts`). The universal APK embeds **exactly
  `N`**; each of the three split APKs embeds `N*10 + abiCode` with
  abiCode 1 = armeabi-v7a, 2 = arm64-v8a, 3 = x86_64 — set explicitly by
  the abiCodes override (an `applicationVariants.configureEach` block) in
  `android/app/build.gradle.kts`; the universal APK has no ABI filter and
  is untouched by that block.
- The ABI splits and the versionCode offsets distinguishing them exist on
  request of the F-Droid maintainers — their ask for the official
  distribution shapes this scheme, not any Play requirement; pubspec's
  `+N` stays the single anchor for every consumer regardless.
- Equalities to maintain: the F-Droid `Builds:` entry's
  `versionCode:` (Phase E step 2) must equal `N` — that equality anchors
  the **universal APK** (a split-based F-Droid recipe would need its own
  version-code scheme statement at submission time; Phase E step 3 covers
  that choice, no changes here) — F-Droid's
   `UpdateCheckData` regex derives its candidate versionCode from the
   pubspec `+N` at the tagged commit, so `pubspec.yaml` is the single
   source — and the download-and-sign script's `aapt` validation (sign
   step of the per-release checklist) verifies each split APK's embedded
   versionCode against `N*10 + {1, 2, 3}`.
- The fastlane changelog filename (the changelog-files step) is the
  bare `N` — the split scheme changes nothing about that.

### Phase E — official F-Droid inclusion (after Gates G1 + G2)

Expectation management: the inclusion queue takes weeks to months; the app
can meanwhile distribute as APKs. F-Droid builds **from source** with the
app's declared signing key fingerprint. Because it builds from the source
at the tagged commit, it only consumes the GitHub Release APKs for their
signature (the metadata's `binary:` field: the buildserver downloads the
upstream assets at
`https://github.com/BenediktBurger/cycle-app/releases/download/v<version>/cycle-app-<version>-<abi>.apk`,
copies their signature onto its own build of the same commit, and
compares byte-for-byte) — so those upstream APKs must stay
byte-reproducible against the F-Droid build (see the
[per-release checklist](#per-release-checklist-every-distribution-update);
on a mismatch F-Droid silently skips publishing that version).
`pubspec.yaml` stays the single source of the versionCode.

1. Preconditions: `LICENSE` committed; license Apache-2.0 confirmed final
   (G2), final applicationId (G1), universal-APK build reproducible locally,
   no non-free deps (already satisfied — drift/sqlite/fl_chart are clean),
   no AntiFeatures expected.
2. Fork <https://gitlab.com/fdroid/fdroiddata>, add
   `metadata/<applicationId>.yml` from their template:
   `License: Apache-2.0`, `AuthorName`, githash/tag
   `UpdateCheckMode`, `CurrentVersion`, and the `Builds:` entry with
   `versionCode` + commit + recipe.
3. **Build recipe:** pin the exact Flutter version (`flutter --version`
   hash) used for the local release; check how Flutter apps currently
   define recipes in `fdroiddata` *at submission time* (conventions move;
   find a recent Flutter app's yaml as the blueprint — do not copy a stale
   one from memory). Decide there between universal APK and ABI splits.
   The exact pin lives in `tool/flutter-version` — both CI workflows and
   the F-Droid buildserver read that same file, parsed the same way (the
   recipe parses it from the built commit, which is the commit the
   publish script tags) — so a Flutter bump after the first parsed recipe
   needs no `fdroiddata` edit.
4. Store-facing metadata follows the fastlane/triple-T structure under
   `fastlane/metadata/android/<locale>/`: full/short description, changelogs
   per versionCode, text+image assets. German-first with English mirrored,
   matching the app's language policy. Every distributed version gets one
   changelog file per locale at release time (naming scheme and
   requirement: the changelog-files step of the per-release checklist).
5. Submit the merge request; respond to `fdroid-bot`/reviewer comments
   (typical asks: reproducibility notes, version-code scheme explanation).
6. After acceptance: F-Droid builds itself on their infrastructure — your
   local keystore stays authoritative for sideloads; coordinate the same
   key fingerprint in metadata (this is why the keystore decision precedes
   the F-Droid submission).

### Phase F — Google Play (after Gates G1 + G3)

1. **Account:** Play Console, individual account (G3). Budget one-time fee.
2. **Create the app entry** with the final applicationId — frozen from here.
3. **Signing:** first AAB upload enrolls Play App Signing; our upload key =
   the Phase C keystore. Back up the keystore *before* this point.
4. **Store listing (DE-first, EN mirrored):** title (App Store name is
   claimable — register the final name early once it exists), screenshots
   phone + 7", feature graphic, description, INER endorsement/logo per
   whatever agreement exists.
5. **Compliance:**
   - Privacy policy URL (needs a web address — the G1 domain naturally
     serves; GitHub Pages from this repo is an acceptable fallback).
   - Data Safety form: trivially "no data collected/shared" — no network,
     no analytics (verify against the dependency list before submitting!).
   - Content rating questionnaire; target-audience declaration (fertility
     awareness apps ≠ kids' apps, state 18+/ uninstructed accordingly).
   - EU DSA trader status per G3 outcome.
6. **Rollout:** internal testing track (self + testers, fast turnaround) →
   verify upgrade path → closed/open test if useful → production, staged
   rollout preferred (data-loss risk mitigation mirrors the Phase D
   discipline).
7. Per-release: version bump → `flutter build appbundle --release` →
   internal track first, production only after the device upgrade test.

### Phase G — iOS (deferred workstream)

Do **not** start until Android went through Phases B–F at least once.

- Prerequisites: macOS + Xcode (this Linux machine cannot build iOS),
  Apple Developer Program (annual fee), G1 (bundle id = same string),
  G3 analogs (Apple org account → same D-U-N-S number).
- Signing is account-based (certificates + profiles; reissuable) — lighter
  than the keystore story, but TestFlight/App Store review is stricter.
- Path: local build/test → TestFlight internal → external testers → App
  Store review. Prepare the App Privacy "nutrition label" and review
  answers from the same facts used for Play's Data Safety (fully offline
  app — consistent claims across stores).
- Health-adjacent app note: expect privacy/health scrutiny in review; the
  no-network/no-tracking story is the strongest card.

## Per-release checklist (every distribution update)

1. **Release branch + version bump (manual)** — cut the dedicated release
   branch off an up-to-date `main` and commit the version bump on
   it:

   ```sh
   git switch main
   git pull
   git switch -c release/vX.Y.Z
   ```

   Version bump: `version: X.Y.Z+N` in `pubspec.yaml` — always bump the
   versionCode `+N`; change the versionName `X.Y.Z` depending on the
   change — and commit it on the branch. The branch name `release/vX.Y.Z`
   triggers the Release workflow, the download-and-sign
   script selects the run by exactly this branch, and it re-checks the
   requested `X.Y.Z` against pubspec at the run's own commit.
2. **Changelog files (release notes, manual)** — create the fastlane
   changelog file
   `fastlane/metadata/android/<locale>/changelogs/<N>.txt` for all
   locales present under `fastlane/metadata/android/` — the filename
   is exactly the bare versionCode integer from pubspec, e.g. `2.txt` for
   versionCode 2 (it must match pubspec's `+N` verbatim — padding only if
   pubspec itself had it), extension `.txt`.
   Content: a short plain-text summary of what shipped (keep
   it ≤ 500 characters) — this file is the F-Droid store changelog and the
   basis for the Play release notes. Skipping this step has a visible consequence:
   the store listing for that version shows no release notes, because F-Droid
   derives the per-version changelog its users see solely from these
   files. Store-metadata layout context: Phase E step 4 and
   [`fastlane/metadata/android/README.md`](../fastlane/metadata/android/README.md).
3. **Push the branch → CI builds unsigned (NO tag exists yet)** —

   ```sh
   git push -u origin release/vX.Y.Z
   ```

   The push triggers the
   Release workflow (`.github/workflows/release.yml`): the full
   correctness gate (analyze, format, test —
   [ADR-0006](adr/0006-ci.md) conventions), then the three **unsigned**
   per-ABI APKs built with plain `--split-per-abi` (no
   `--target-platform`) at the fixed checkout path (invariants below),
   uploaded as workflow artifacts `cycle-app-<version>-<abi>-unsigned`.
   The version in those names comes from the branch's `pubspec.yaml` —
   nothing is derived from a ref, because no tag exists at build time.
   Wait for the run to finish green (`gh run watch` or the Actions page).
   Reruns and rehearsals need no tag either: `workflow_dispatch` on the
   release branch is an ordinary full run, and when several runs exist
   for the branch the download-and-sign script picks newest-first — or
   explicitly via `--run-id <id>` (the re-attach path, step 6).
4. **Sign — download, validate, sign (`tool/download_and_sign.dart`)**;
   runs NO builds and NO tests** —

   ```sh
   dart run tool/download_and_sign.dart vX.Y.Z
   # keystore password: the APKSIGNER_STORE_PASSWORD env var, or the
   # gitignored android/key.properties (the same file the Gradle release
   # signing reads; interactive apksigner prompting is not possible from
   # the script's process harness)
   ```

   This local step performs no builds and no tests — the artifact already
   passed the CI gate; the script's stages are pure download, validation,
   and signing. It downloads the three artifacts, re-checks each APK's
   embedded versionName (`X.Y.Z`) and versionCode (`N*10 + abiCode`, via
   `aapt`) against the requested version and the pubspec
   `version: X.Y.Z+N` **at the CI run's own commit** (fetched via the
   GitHub contents API — the local checkout may sit on any branch), and
   signs into the gitignored `build/gh-release/` under the publish names
   `cycle-app-<version>-<abi>.apk` — exactly the URLs the F-Droid
   metadata's `binary:` field downloads (Phase E). The signature comes
   from apksigner in Android build-tools ≤ 34 (hard cap, invariants
   below), with the v1 (JAR) scheme signed off on purpose — v1 would
   embed a randomized ECDSA signature inside the zip entries (the release
   key is EC) and defeat the determinism sanity, and v1 is unnecessary at
   minSdk 24 (Android 7+ verifies v2 natively). Every signature is
   verified against the pinned fingerprint in
   `tool/release_fingerprint.txt` (hard gate: mismatch = wrong key —
   never attach; the CI build's debug-signing fallback blocks are gone by
   then), and one APK is signed a second time and compared with the staged
   one everywhere except the signing-block interior (determinism sanity,
   aborts on any other difference — the release key is EC, and ECDSA
   randomizes every signature by design, so byte-for-byte equality is not
   attainable; identical ZIP content still is). Mismatched or corrupt
   artifacts abort before anything is staged. The script ends by writing
   the handoff manifest `build/gh-release/source.json` (the run id and
   head SHA the publish step will use) and printing the adb install
   lines below — it publishes nothing and opens no PR.
5. **Device install + DB-migration test** — the download-and-sign script
   printed the exact install commands, device-default ABIs first:

   ```sh
   adb install -r build/gh-release/cycle-app-<version>-armeabi-v7a.apk
   adb install -r build/gh-release/cycle-app-<version>-arm64-v8a.apk
   ```

   Run the Phase D upgrade test against the **previously installed
   release**: previous released version with representative data entered
   → `adb install -r` the newly signed device-matching APK **over it** →
   journal/chart intact, schema migration ran, export → import
   round-trip still works (`tool/smoke_export_import.dart` logic mirrors
   this). These CI-built, locally signed files are what ships and what
   users download, so installing the device-matching one tests exactly
   that. The publish script (Publish step) runs only once this test passed —
   the break is a real script boundary, the checklist order is the
   run order (attach is reversible; a data-loss incident is not).
6. **Publish — tag + release + assets, atomically at the built commit
   (`tool/publish_release.dart`)** —

   ```sh
   dart run tool/publish_release.dart vX.Y.Z
   ```

   Optional rehearsal first: `dart run tool/publish_release.dart vX.Y.Z --dry-run`
   is print-only and computes REAL checksums from the
   staged APKs, so every printed `gh` command (the release-create with
   `--target`, or the `--clobber` re-attach, plus the PR payloads)
   comes with the exact hashes the real run will publish — nothing is
   uploaded or edited.

   A release that does not exist yet is **created** with one command
   that authors **the tag `vX.Y.Z` as well**:

   ```sh
   gh release create vX.Y.Z build/gh-release/cycle-app-<version>-<abi>.apk … \
     --repo BenediktBurger/cycle-app --target <the manifest's head SHA> \
     --generate-notes --notes-file build/gh-release/notes-vX.Y.Z.md
   ```

   The head SHA comes from the handoff manifest
   `build/gh-release/source.json` (written by the download-and-sign
   script from the resolved run — not re-resolved, so a newer run on the
   branch or a `flutter clean` cannot retarget the release), pointing at
   the exact commit the CI run built, so tag, release, and signed assets
   appear atomically and a failed publish leaves no dangling tag; the
   CI build stays the only thing a push triggers. The notes body is the
   pinned fingerprint line plus one `APK SHA-256:` line per APK (GitHub
   appends the auto-generated changelog; the fingerprint is the trust
   anchor F-Droid metadata cross-checks). An already existing release is
   **re-attached** instead: the signed APKs are uploaded with `--clobber`
   and the fresh checksum lines are spliced into the existing notes body
   (everything else preserved). The re-attach path needs no tag
   delete/re-push games: re-sign from the original run via the
   download-and-sign script's `--run-id <original run>` (when the
   artifacts still exist) or re-dispatch a Release run on a release
   branch whose head is reset to the original commit, then run the
   publish script as usual.
7. **Post-release PR into `development` (automated; verify it)** — after
   publishing (create or re-attach), the publish script opens the PR
   `release/vX.Y.Z` → `development` (title "Release vX.Y.Z") and queues
   its auto-merge. What the operator verifies:

   - **Merge commit, never squash or rebase** — the tag points at the
     release commit, which must stay an ancestor of `development`; F-Droid
     build-recipe metadata and the version bookkeeping pin that exact
     SHA, so a squash/rebase would leave the tag pointing at a SHA the
     history no longer contains.
   - **Auto-merge prerequisite:** switch on **"Allow auto-merge"** in the
     GitHub repo Settings (General → Pull Requests), otherwise `--auto`
     cannot queue the merge.
   - The `pull_request` trigger in `.github/workflows/ci.yml` vets the
     PR; `--auto` queues it until the required checks are green.
   - PR plumbing failures are **soft failures**: the release is already
     published, so the script prints the exact manual fallback commands
     (`gh pr create …` / `gh pr merge --merge --auto release/vX.Y.Z`)
     instead of aborting, and an "already exists" answer is handled
     leniently (it just ensures auto-merge).
8. **F-Droid tasks (operator)** — the fdroiddata MR (Phase E) with the
   new `Builds:` entry: its `commit:` is the **same commit SHA the
   release tag points at** — that equality is what makes the signature
   comparison meaningful — and its `binary:` URLs name the just-published
   assets. Then the verification loop: the per-versionCode JSONs under
   `https://verification.f-droid.org/io.github.benediktburger.cycleapp_<versionCode>.apk.json`
   must report verified; on a mismatch iterate on the CI side only (JDK /
   build-tools / NDK alignment; the `libdartjni.so` build-id diff is
   already suppressed — the Android Gradle config appends
   `-Wl,--build-id=none` to the jni plugin's CMake shared-linker flags, so
   only the remaining knobs above are open) and
   rerun the loop: re-dispatch → re-sign → re-attach → re-verify.
9. **Distribute & observe** — sideload to testers first; Play internal
   track when involved (its AAB is built locally,
   `flutter build appbundle --release`; no automated Play upload); F-Droid
   ships when verification passed. Confirm the store dashboards show the
   intended version; observe crash reports (Play) / F-Droid comments in
   the days after. Only point testers at the release once it is visible
   and the upgrade test is done. (Git history is the release diary; the
   roadmap stays a queue.)

### Release invariants & hard gates (supporting detail)

- **Signing fingerprint pin (`tool/release_fingerprint.txt`)** — the
  release-certificate SHA-256 is pinned in the committed file; the
  download-and-sign script refuses to attach any APK signed with another
  key, and the F-Droid
  metadata carries the same value (`AllowedAPKSigningKeys`). Custody
  rules: Phase C.
- **apksigner only from Android build-tools ≤ 34** — a 35+ apksigner
  signature cannot be handled by the F-Droid buildserver's signature
  copying, hence the hard cap; the download-and-sign script resolves the
  newest qualifying directory under `$ANDROID_HOME/build-tools` and
  aborts loudly when none qualifies.
- **Keystore never on GitHub** — CI only produces **unsigned** artifacts
  (the Gradle release build's documented debug-signing fallback is
  exactly the CI case); apksigner replaces those signature blocks during
  local signing, so they never reach the published assets. Custody rules:
  Phase C.
- **Checkout-path invariant (byte-equality load-bearing for
  `libapp.so`):** the CI checkout path and the fdroiddata build path must
  stay identical. The fdroiddata recipe mirrors
  `/home/runner/work/cycle-app/cycle-app`; any change of the CI workspace
  directory (e.g. a repo rename → `/home/runner/work/<new>/<new>`) must
  be mirrored in the same change to the fdroiddata recipe — and vice
  versa.

## Fresh-machine recovery (the handover note)

For a later INER takeover or lost laptop — the minimum to rebuild a release
machine:

1. Flutter SDK + Android toolchain per
   [CONTRIBUTING.md](../CONTRIBUTING.md) (§1 and its "Android toolchain"
   section) — needed for day-to-day development and local builds; the
   release build itself runs on GitHub Actions (unsigned), so publishing
   depends only on a local Android SDK with build-tools ≤ 34
   (apksigner/aapt, resolved via `ANDROID_HOME`), an authenticated `gh`
   CLI, and the restored keystore below — not on a full local release
   build. No tag is needed to rebuild a release either: dispatch a
   Release run (`workflow_dispatch`) on a `release/**` branch — or push
   the branch again — and the CI artifacts are there to download; the
   tag itself is authored only at publish time, by
   `tool/publish_release.dart`, at the head SHA the manifest written by
   `tool/download_and_sign.dart` carries. A Flutter-version bump is a
   one-file edit: change `tool/flutter-version` — both CI workflows and
   the F-Droid recipe read that file directly; there are no per-workflow
   mirror lines to update anymore.
2. Restore the **keystore** from the offline backup (custody rules, Phase C)
   — without the `.jks` no update can be signed for the installed base.
3. Recreate `android/key.properties` from the password-manager record
   (needed for locally signed release builds during development, not for
   the publish path).
4. Follow the per-release checklist above — its two-script flow
   (`download_and_sign` → device test → `publish_release`) is the same
   on a fresh machine; F-Droid metadata lives in the
   `fdroiddata` fork (separate git repo), Play listing lives in the console.

---

Related: [ADR-0002](adr/0002-package-name-cycle-app-placeholder.md)
(placeholder name), [ADR-0003](adr/0003-target-platforms-web-iteration.md)
(platform targets), [ADR-0006](adr/0006-ci.md) (CI scope),
[ADR-0009](adr/0009-release-pipeline-and-signing.md) (this document is its
enactable companion).
