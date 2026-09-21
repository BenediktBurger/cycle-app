# Release & publishing runbook

Enactable companion to
[ADR-0009](adr/0009-release-pipeline-and-signing.md): commands, checklists,
and decision gates for getting the app distributed — local test APKs first,
then Google Play and official F-Droid inclusion; iOS later. Work items point
here from [`docs/roadmap.md`](roadmap.md).

Aim of this document: every step should be executable later *without*
re-deriving the reasoning. Reasons live in the ADR; this file is the how.

## Where we stand

| Channel                      | Role                             | Blocked by                                         |
|------------------------------|----------------------------------|----------------------------------------------------|
| Sideload APK                 | development/testing, demo builds | nothing (Phase D discipline; APK built + signed locally, released manually) |
| Google Play                  | primary store                    | Gate G3 (Phase F; G1 resolved 2026-09)             |
| F-Droid (official)           | intermediate, possibly permanent | Gate G2 (Phase E; G1 resolved 2026-09)             |
| iOS (TestFlight → App Store) | deferred workstream              | macOS + Apple Developer Program (Phase G)          |

Order of execution is exactly A → C → D, then (whenever gates resolve) B, E, F.
Routine releases skip the phases entirely: they follow the
[per-release checklist](#per-release-checklist-every-distribution-update)
and the
[local release path](#local-release-path)
(the tag-triggered CI pipeline is
[parked](#parked-ci-release-path-adr-0009-amended-2026-09-superseded-by-the-local-release-path));
Phases A–G are one-time setup.

## Decision gates — resolve before the first store upload

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
    "Cycle App" in store metadata); do not treat the identifier as
    naming the product.
- **G2 — license.** Pick and commit the `LICENSE` file (README signals
  GPL-3-compatible intent). Blocks F-Droid only, but blocks it hard.
- **G3 — publisher/account shape.** Individual Play account first (ADR-0009
  §3). Open sub-question: EU DSA **trader status** for both stores (INER
  endorsement may make "trader" mandatory) and whether/when INER itself
  becomes the publisher of record. If an org registration (Play or Apple)
  becomes real: start the **D-U-N-S** application immediately — it is the
  long-lead-time item.
- **G4 — branding assets** (app name, icon, screenshots) — can be redone at
  will; not a true gate, listed here only because store listings need them.

## Phase A — Android toolchain (one-time, dev machine)

The setup itself — JDK 21, Android SDK, licenses, device connection —
lives with the contributor docs:
[CONTRIBUTING.md](../CONTRIBUTING.md), section "Android toolchain"
(Android Studio is described there as an alternative). It is **required
for releases**: release artifacts are built and signed locally (the
parked CI release path would cover it too, but that is disabled — see
"Local release path" below), and the device upgrade test (Phase D) needs
the built release APK.

Gate: `flutter build apk --release` in the repo root succeeds (debug-signed
is fine without `key.properties`; real signing comes in Phase C).

## Phase B — application identity rename (Gate G1 resolved)

Preparation principle (from [ADR-0002](adr/0002-package-name-cycle-app-placeholder.md)):
everything is coded against the placeholder `cycle_app`, so the rename is
mechanical. Checklist, in order — run the full test gate between sensible
stages and commit stepwise. **Items 1–3 are already done** (identifier
per Gate G1 above; Dart package name stays `cycle_app` per ADR-0002):

1. `pubspec.yaml`: ✅ bumped to `version: 0.1.0+1` (versionCode = 1, matching
   `fastlane/metadata/android/*/changelogs/1.txt`). Keep bumping `+N` per
   distributed build from here (per-release checklist). The `name:` stays
   `cycle_app` (ADR-0002 placeholder decision; rename explicitly out of
   scope).
2. `android/app/build.gradle.kts`: ✅ `applicationId` and `namespace` set to
   `io.github.benediktburger.cycleapp`; template TODOs removed.
3. ✅ `MainActivity.kt` moved to
   `android/app/src/main/kotlin/io/github/benediktburger/cycleapp/` with
   its `package` line updated (manifest uses `.MainActivity` relative to
   the namespace — no manifest edit needed).
4. Launcher label: **open** — replace `android:label="cycle_app"` with a
   localized resource — create `android/app/src/main/res/values{-de}/strings.xml` with
   `app_name`, manifest references `@string/app_name`.
5. **Adaptive launcher icon** (replaces the default mipmaps): it must exist
   for any store listing; generate from a vector foreground + background
   (G4), e.g. via Android Studio once or an icon-generation tool.
6. **Before Play upload (hard deadline):** the identifier must be final —
   afterwards it is frozen (ADR-0009 §4).
7. iOS note (Phase G): reuse the exact `applicationId` string as the iOS
   bundle identifier.

Regression check after the rename: full analyze/test gate, then web build +
release APK both build.

## Phase C — signing (independent of Gate G1 — can be done early)

Create the release keystore **once**, outside the repo:

```sh
mkdir -p ~/keystores
keytool -genkeypair -v \
  -keystore ~/keystores/<app>-release.jks -alias <app>-release \
  -keyalg RSA -keysize 2048 -validity 10000
```

Use the **final project name** for the alias/keystore — Gate G1 is
resolved, so alias `cycleapp-release`, keystore `cycleapp-release.jks`
(the alias is internal — the key itself is what lasts; a per-app key is
the cleaner choice per ADR-0009).

**Custody rules (ADR-0009 §2 — non-negotiable):**

- keystore file + `key.properties` **never** enter the repo
  (`android/.gitignore` already ignores `key.properties`, `**/*.keystore`,
  `**/*.jks`; store the keystore under `~/keystores` anyway, not inside any
  checkout);
- password + keystore backup file(s) into the password manager, **plus two
  offline encrypted copies** on separate media;
- a one-page "how to release from scratch on a new machine" note lives at
  the bottom of this file (§Released-machine recovery) — this is also the
  handover doc for a later INER takeover.

Wire it up:

1. `android/key.properties` (gitignored):

   ```properties
   storeFile=/home/<you>/keystores/<app>-release.jks
   storePassword=...
   keyAlias=<app>-release
   keyPassword=...
   ```

2. `android/app/build.gradle.kts` — replace the debug-signing release block:

   ```kotlin
   import java.util.Properties

   val keystoreProperties = Properties()
   val keystorePropertiesFile = rootProject.file("key.properties")
   if (keystorePropertiesFile.exists()) {
       keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
   }

   android {
       signingConfigs {
           create("release") {
               keyAlias = keystoreProperties.getProperty("keyAlias")
               keyPassword = keystoreProperties.getProperty("keyPassword")
               storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
               storePassword = keystoreProperties.getProperty("storePassword")
           }
       }
       buildTypes {
           release {
               signingConfig = if (keystorePropertiesFile.exists()) {
                   signingConfigs.getByName("release")
               } else {
                   // debug fallback keeps `flutter build apk --release` runnable
                   // on machines without key.properties (CI, fresh clones)
                   signingConfigs.getByName("debug")
               }
           }
       }
   }
   ```

   (Adapt the exact insertion points; `rootProject.file("key.properties")`
   resolves to `android/key.properties`.)

Gate: `flutter build apk --release`, then verify the signature is *not* the
debug key:

```sh
$ANDROID_HOME/build-tools/<N>.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

## Phase D — build, install, upgrade discipline

Build variants (from the repo root):

```sh
flutter build apk --release                 # universal APK — simplest, F-Droid-ish default
flutter build apk --release --split-per-abi # smaller per-ABI APKs for sideloading
flutter build appbundle --release           # .aab for Google Play
```

Artifacts land under `build/app/outputs/flutter-apk/` (and
`.../bundle/release/` for the AAB).

Install on a device:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Upgrade test (mandatory for every distribution update, ADR-0009 §5):**

1. Install the previous released version (keep one APK of every release
   under `~/keystores`-adjacent storage or a release tag), open the app,
   enter representative data (bleeding, temperature, marks, journal).
2. `adb install -r` the new release **over it**.
3. Verify: journal/chart intact, schema migration ran, export → import
   round-trip still works (`tool/smoke_export_import.dart` logic mirrors
   this; the device test is the real-environment proof).
4. Only then ship.

Numbers discipline: `version: X.Y.Z+N` in `pubspec.yaml` — bump `+N` for
every distributed build (Play and F-Droid see the same versionCode; the ABI
split adds its offset automatically — see the comment in
`android/app/build.gradle.kts`).

## Phase E — official F-Droid inclusion (after Gates G1 + G2)

Expectation management: the inclusion queue takes weeks to months; the app
can meanwhile distribute as APKs. F-Droid builds **from source** with the
app's declared signing key fingerprint.

1. Preconditions: `LICENSE` committed (G2), final applicationId (G1),
   universal-APK build reproducible locally, no non-free deps (already
   satisfied — drift/sqlite/fl_chart are clean), no AntiFeatures expected.
2. Fork <https://gitlab.com/fdroid/fdroiddata>, add
   `metadata/<applicationId>.yml` from their template:
   `License:` (must match the chosen license), `AuthorName`, githash/tag
   `UpdateCheckMode`, `CurrentVersion`, and the `Builds:` entry with
   `versionCode` + commit + recipe.
3. **Build recipe:** pin the exact Flutter version (`flutter --version`
   hash) used for the local release; check how Flutter apps currently
   define recipes in `fdroiddata` *at submission time* (conventions move;
   find a recent Flutter app's yaml as the blueprint — do not copy a stale
   one from memory). Decide there between universal APK and ABI splits.
4. Store-facing metadata follows the fastlane/triple-T structure under
   `fastlane/metadata/android/<locale>/`: full/short description, changelogs
   per versionCode, text+image assets. German-first with English mirrored,
   matching the app's language policy.
5. Submit the merge request; respond to `fdroid-bot`/reviewer comments
   (typical asks: reproducibility notes, version-code scheme explanation).
6. After acceptance: F-Droid builds itself on their infrastructure — your
   local keystore stays authoritative for sideloads; coordinate the same
   key fingerprint in metadata (this is why the keystore decision precedes
   the F-Droid submission).

## Phase F — Google Play (after Gates G1 + G3)

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

## Phase G — iOS (deferred workstream)

Do **not** start until Android went through Phases A–F at least once.

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

1. `pubspec.yaml`: `version: X.Y.Z+N` (bump `+N`, note the versionName).
2. `flutter analyze && flutter test --no-pub -r expanded` (full gate,
   [ADR-0006](adr/0006-ci.md) conventions).
3. Fastlane changelog file for the new versionCode (F-Droid) + Play release
   notes draft (DE/EN).
4. Build the release artifact itself:
   `flutter build apk --release` (universal APK). With the local
   `key.properties` present this is release-signed via the Phase C wiring;
   if the file is missing, Gradle silently falls back to **debug** signing —
   the `apksigner verify` step below is the guard against that, never skip
   it. (Detail: [local release path](#local-release-path).)
5. Verify the signature — this is both the trust-anchor source and the
   debug-fallback guard:

   ```sh
   $ANDROID_HOME/build-tools/<N>.0.0/apksigner verify --print-certs \
     build/app/outputs/flutter-apk/app-release.apk
   ```

   The certificate must be the release key, not the debug key.
6. **Upgrade test on the real device** (Phase D) with **this exact APK** —
   non-negotiable, and it happens **before** publishing: the locally built
   APK *is* the artifact users install (byte-identical), so install it over
   the previous release and verify the cycle data survives before anything
   is public.
7. Sanity-check the version/tag, then tag and publish:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   gh release create vX.Y.Z \
     build/app/outputs/flutter-apk/app-release.apk \
     --generate-notes \
     --notes "SHA-256 certificate fingerprint: <from the apksigner output above>"
   ```

   The APK embeds the `version:` from `pubspec.yaml` at the tagged commit —
   the tag must sit on the commit containing the pubspec bump, and the tag
   name must match that versionName; nothing cross-checks the two on the
   local path. The fingerprint goes into the release notes body as the
   trust anchor (F-Droid metadata later cross-checks against the same
   fingerprint). Only point testers at the release once it is visible.
   (Git history is the release diary; the roadmap stays a queue.)
8. Upload/distribute (sideload → testers; Play internal track; F-Droid MR
   or automatic build on their side). When Play is involved, the AAB is
   also built locally (`flutter build appbundle --release`); there is no
   automated Play upload.
9. Confirm the store dashboards show the intended version; observe crash
   reports (Play) / F-Droid comments in the days after.

## Local release path

Until F-Droid distribution is running, signing secrets never enter
GitHub: release builds and signing happen on the release machine, and the
GitHub Release is created manually with the locally built APK
([ADR-0009](adr/0009-release-pipeline-and-signing.md), amended 2026-09 —
decision #6's tag-triggered CI flow is
[parked](#parked-ci-release-path-adr-0009-amended-2026-09-superseded-by-the-local-release-path),
not deleted).

The sequence aligns with the per-release checklist above (where items 4–7
carry the exact commands):

1. Build the artifact: `flutter build apk --release` — signed via the
   local `android/key.properties` (Phase C wiring). **Debug-signing
   fallback risk:** when that file is absent, Gradle silently signs with
   the debug key; the `apksigner verify` step below is the local
   equivalent of the parked workflow's pre-flight and is the proof this
   did not happen. (The old CI flow's re-tag salvage step is gone: the
   artifact already exists before any tag is pushed, so the gate ordering
   is build → verify → upgrade test → *then* tag + publish.)
2. Verify the signature and note the SHA-256 certificate fingerprint:
   the cert must be the release key, and the fingerprint doubles as the
   trust anchor for the release notes.
3. **Device upgrade test with this exact APK** (Phase D) — non-negotiable.
   Because the build *is* the release artifact, the test happens before
   publishing: the APK users install is byte-identical to the tested one —
   strictly better than the parked CI flow, which had to test after
   publishing (Tag → CI build → download → test → distribute).
4. Version/tag sanity: the APK embeds the `version:` from `pubspec.yaml`
   at the tagged commit; before creating the release, confirm the tag
   name matches the versionName (one-line eyeball check — nothing
   cross-checks automatically on the local path).
5. Tag `vX.Y.Z` on the commit containing the pubspec bump: create it
   explicitly with `git tag`/`git push` — the one consistent way this
   runbook does it — rather than left to `gh release create` to
   auto-create the tag at the default branch's HEAD, which may not be
   the pubspec-bump commit. Then create the GitHub Release with
   `gh release create` + the same APK.
   `--generate-notes` builds the changelog from the commit log; GitHub
   appends it to the `--notes` content, so the pasted SHA-256 certificate
   fingerprint ends up in the release notes body as the trust anchor —
   same practice the CI workflow had, and what F-Droid metadata later
   cross-checks.
6. Distribute (checklist steps 8–9).

AAB note: when Play distribution starts, the bundle is built locally too
(`flutter build appbundle --release`); there is no automated Play upload.

## Parked CI release path (ADR-0009 amended 2026-09, superseded by the local release path)

`.github/workflows/release.yml` — the tag-triggered build-and-sign
pipeline — is **parked, not deleted**: releases are made locally
([local release path](#local-release-path)). The workflow is kept with
**`workflow_dispatch` as its only trigger** — pushing a `vX.Y.Z` tag no
longer runs it — and stays useful as a manual dry run on a clean machine.

**Re-enable checklist** (returning to the old tag-push flow):

1. Set the five secrets below (they may also be set while parked).
2. Restore `push: tags: ["v*.*.*"]` in `.github/workflows/release.yml`.
3. Dry-run via **workflow_dispatch** (GitHub → Actions → Release → Run
   workflow) to validate secrets, signing, and the build.
4. Then follow the old flow again: push the `vX.Y.Z` tag (the tag push
   triggers the workflow), wait for it to finish green, download the
   signed APK, run the device upgrade test, then distribute. The
   workflow's outputs are unchanged: a signed universal release APK
   attached to a GitHub Release with automatically generated notes (the
   workflow prints the signing certificate fingerprint in its log — copy
   it into the release notes as the trust anchor; F-Droid metadata later
   cross-checks it), plus an AAB uploaded as a workflow **artifact** for
   the manual Play upload (no Play API integration exists).

Note on versions: the APK embeds the `version:` from `pubspec.yaml` at the
tagged commit; the tag name itself is only the trigger and trust anchor.
Keep the two in sync (per-release checklist step 7) — nothing in the
workflow verifies them against each other.

**Required repository secrets (GitHub Settings → Secrets → Actions), all
five — set them BEFORE the first tag push. Why the hard pre-flight
requirement: missing secrets are not reported by the build chain itself —
Gradle silently falls back to the debug signing config, and a debug-signed
APK would get attached to a public Release. The workflow now aborts with a
preflight check when a secret is absent, but treat a debug-signed APK on a
Release as a trigger failure to investigate and never trust it:**

1. `RELEASE_KEYSTORE_GPG_BASE64` — the keystore below, GPG-encrypted then
   base64-encoded (how to produce it: the two commands below; Phase C
   creates the `.jks`).
2. `RELEASE_KEYSTORE_PASSPHRASE` — the GPG passphrase used in the same
   encryption (store it in the password manager like the keystore
   passwords; it is NOT the keystore password unless you chose to reuse).
3. `RELEASE_KEYSTORE_KEY_ALIAS` — Phase C keystore alias (`cycleapp-release`).
4. `RELEASE_KEYSTORE_KEY_PASSWORD` — the key's password.
5. `RELEASE_KEYSTORE_STORE_PASSWORD` — the keystore's password.

**Create the encrypted secret payload from the Phase C `.jks`:**

```sh
gpg --symmetric --output ~/keystores/cycleapp-release.jks.gpg ~/keystores/cycleapp-release.jks
base64 ~/keystores/cycleapp-release.jks.gpg > ~/keystores/cycleapp-release.jks.gpg.b64
# paste the .b64 content into the RELEASE_KEYSTORE_GPG_BASE64 secret, then
# keep the passphrase mentally paired with it (password-manager entries).
```

The workflow decrypts the keystore **only into `$RUNNER_TEMP`** and writes
a generated, gitignored `android/key.properties` pointing there; nothing
keystore-shaped is committed or leaves `$RUNNER_TEMP`. The local keystore
and its offline backups remain authoritative.

When the parked path is re-enabled, the workflow again does **not** make a
release count as "shipped": the device upgrade test remains a mandatory
manual step before announcing the release (re-enable checklist item 4).

## Fresh-machine recovery (the handover note)

For a later INER takeover or lost laptop — the minimum to rebuild a release
machine:

1. Flutter SDK + Android toolchain per
   [CONTRIBUTING.md](../CONTRIBUTING.md) (§1 and its "Android toolchain"
   section) — required: releases are built and signed locally, so releases
   cannot be made without the full Android toolchain (the parked CI path
   would be the alternative if re-enabled).
2. Restore the **keystore** from the offline backup (custody rules, Phase C)
   — without the `.jks` no update can be signed for the installed base.
3. Recreate `android/key.properties` from the password-manager record.
4. Follow the per-release checklist above; F-Droid metadata lives in the
   `fdroiddata` fork (separate git repo), Play listing lives in the console.

---

Related: [ADR-0002](adr/0002-package-name-cycle-app-placeholder.md)
(placeholder name), [ADR-0003](adr/0003-target-platforms-web-iteration.md)
(platform targets), [ADR-0006](adr/0006-ci.md) (CI scope),
[ADR-0009](adr/0009-release-pipeline-and-signing.md) (this document is its
enactable companion).
