# Release & publishing runbook

Enactable companion to
[ADR-0009](adr/0009-release-pipeline-and-signing.md): commands, checklists,
and decision gates for getting the app distributed — local test APKs first,
then Google Play and official F-Droid inclusion; iOS later. Work items point
here from [`docs/roadmap.md`](roadmap.md).

Aim of this document: every step should be executable later *without*
re-deriving the reasoning. Reasons live in the ADR; this file is the how.

## Where we stand

| Channel                      | Role                             | Blocked by                                |
|------------------------------|----------------------------------|-------------------------------------------|
| Sideload APK                 | development/testing, demo builds | nothing (Phase A + D)                     |
| Google Play                  | primary store                    | Gate G3 (Phase F; G1 resolved 2026-09)    |
| F-Droid (official)           | intermediate, possibly permanent | Gate G2 (Phase E; G1 resolved 2026-09)    |
| iOS (TestFlight → App Store) | deferred workstream              | macOS + Apple Developer Program (Phase G) |

Order of execution is exactly A → C → D, then (whenever gates resolve) B, E, F.

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

Goal: `flutter doctor` fully green for the Android toolchain; first release
APK builds.

1. **JDK 21.** Gradle 9.x refuses Java 25 (the system default here); install
   an LTS alongside it:

   ```sh
   sudo apt install openjdk-21-jdk
   /usr/lib/jvm/java-21-openjdk-amd64/bin/java -version
   ```

   Tell only Flutter about it (does not change the system default):

   ```sh
   flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64
   ```

2. **Android SDK, command-line tools** (no Android Studio needed):

   ```sh
   mkdir -p ~/android-sdk/cmdline-tools
   # download https://dl.google.com/android/repository/commandlinetools-linux_<ver>_latest.zip
   unzip commandlinetools-linux_*.zip -d ~/android-sdk/cmdline-tools
   mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest
   ```

   Add to the shell profile:

   ```sh
   export ANDROID_HOME="$HOME/android-sdk"
   export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
   ```

3. **SDK packages + licenses.** The platform/build-tools versions must match
   what the Flutter Gradle plugin selects (`flutter.compileSdkVersion`);
   check `flutter doctor -v` and install:

   ```sh
   sdkmanager --list | grep -E 'platforms;android|build-tools' | tail
   sdkmanager platform-tools 'platforms;android-<N>' 'build-tools;<N>.0.0'
   flutter doctor --android-licenses
   flutter doctor -v   # must show the Android toolchain without warnings
   ```

4. **Device.** Preferred: a real phone via USB (Developer options → USB
   debugging). Emulator alternative: create with `avdmanager`; usable speed
   requires KVM (`ls -la /dev/kvm`, `sudo apt install cpu-checker && kvm-ok`).

Gate: `flutter build apk --release` in the repo root succeeds (debug-signed
is fine in Phase A; real signing comes in Phase C).

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
4. `flutter build apk --release` (+ AAB when Play is involved).
5. **Upgrade test on the real device** (Phase D) — non-negotiable.
6. Tag the release commit `vX.Y.Z` (git history is the release diary; the
   roadmap stays a queue).
7. Upload/distribute (sideload → testers; Play internal track; F-Droid MR
   or automatic build on their side).
8. Confirm the store dashboards show the intended version; observe crash
   reports (Play) / F-Droid comments in the days after.

## CI release path (tag-triggered, ADR-0009 amended)

`.github/workflows/release.yml` automates the build-and-sign step once a
release tag `vX.Y.Z` is pushed. It runs the full gate (analyze, format,
test), then provisions the keystore and builds.

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

**A `vX.Y.Z` tag produces:**

- A **signed universal release APK** attached to a GitHub Release with
  automatically generated notes (use the notes as the changelog; the
  workflow prints the signing certificate fingerprint in its log — copy it
  into the release notes as the trust anchor; F-Droid metadata later
  cross-checks against the same fingerprint).
- An **AAB** uploaded as a workflow **artifact** for the manual Play upload
  (no Play API integration exists; upload from CI is not planned yet).

The workflow itself does **not** make a release count as "shipped": the
**device upgrade test (Phase D checklist step 5) remains a mandatory manual
step** before announcing the release. Tag → CI build → download APK →
upgrade test → then distribute.

## Fresh-machine recovery (the handover note)

For a later INER takeover or lost laptop — the minimum to rebuild a release
machine:

1. Flutter SDK per [CONTRIBUTING.md](../CONTRIBUTING.md) §1; JDK 21
   (Phase A step 1); Android SDK (Phase A steps 2–3).
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
