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
| Sideload APK                 | development/testing, demo builds | nothing (Phase D discipline; APK built + signed locally, released manually) |
| Google Play                  | primary store                    | Gate G3 (Phase F; G1 resolved 2026-09)                                      |
| F-Droid (official)           | intermediate, possibly permanent | Gate G2 (Phase E; G1 resolved 2026-09)                                      |
| iOS (TestFlight → App Store) | deferred workstream              | macOS + Apple Developer Program (Phase G)                                   |

Of the one-time setup phases, Phase A (Android toolchain) and Phase C
(signing) are complete — git history and
[ADR-0009](adr/0009-release-pipeline-and-signing.md) record how — and
Phase D is ongoing discipline. One-time setup still open: the remaining
Phase B item (adaptive launcher icon) and Phases E, F, G
behind the gates above. Routine releases skip the phases entirely: they
follow the
[per-release checklist](#per-release-checklist-every-distribution-update)
(the tag-triggered CI pipeline is
[parked](#parked-ci-release-path-adr-0009-amended-2026-09-superseded-by-the-per-release-checklist)).
Signing secrets never enter GitHub: release builds and signing happen on
the release machine, and the GitHub Release is created from the locally
built APK (ADR-0009 amended 2026-09).

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
when that file is absent (the per-release checklist guards against that).
**Still outstanding before the first signed build:** fill the two literal
`CHANGE-ME` passwords in `android/key.properties` from the password
manager. On the first real release, the script's `--accept-fingerprint`
flow creates and commits `tool/release_fingerprint.txt` — see
[per-release checklist](#per-release-checklist-every-distribution-update)
step 7.

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

**Numbers discipline: `version: X.Y.Z+N` in `pubspec.yaml`** — bump `+N`
for every distributed build (Play and F-Droid see the same versionCode).

- `X.Y.Z` is the **versionName** (the user-visible version string); `N`,
  the integer after the `+`, is the **versionCode** — the only number
  stores, F-Droid, and fastlane changelog naming actually care about.
- The versionCode is monotonically increasing with every published version
  regardless the used versionName.
- How `N` flows: pubspec `+N` → Gradle's `flutter.versionCode` → the
  versionCode embedded in the APK (wired as `versionCode =
  flutter.versionCode` in the `defaultConfig` of
  `android/app/build.gradle.kts`). For the universal APK
  (`flutter build apk --release` — the per-release checklist default) that
  is **exactly `N`**; the offset mentioned in that file's comment (Flutter
  adds `1000 * ABI_VERSION` for split APKs, suppressible with
  `-P force-version-code-ignoring-abi=true`) applies **only** to
  `--split-per-abi` builds, never to the universal APK.
- Equalities to maintain: the F-Droid `Builds:` entry's
  `versionCode:` (Phase E step 2) must equal `N` — F-Droid's
  `UpdateCheckData` regex derives its candidate versionCode from the
  pubspec `+N` at the tagged commit, so `pubspec.yaml` is the single
  source — and the `aapt` re-check in per-release checklist step 7
  verifies the APK's embedded versionCode matches the pubspec `+N` behind
  the published tag.
- The fastlane changelog filename (per-release checklist step 3) is that
  same `N`.

### Phase E — official F-Droid inclusion (after Gates G1 + G2)

Expectation management: the inclusion queue takes weeks to months; the app
can meanwhile distribute as APKs. F-Droid builds **from source** with the
app's declared signing key fingerprint.

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
   The exact pin lives in `tool/flutter-version`, enforced by CI and by
   `tool/make_release.dart`; the recipe parses that file from the tagged
   commit, so a Flutter bump after the first parsed recipe needs no
   `fdroiddata` edit.
4. Store-facing metadata follows the fastlane/triple-T structure under
   `fastlane/metadata/android/<locale>/`: full/short description, changelogs
   per versionCode, text+image assets. German-first with English mirrored,
   matching the app's language policy. Every distributed version gets one
   changelog file per locale at release time (naming scheme and
   requirement: per-release checklist step 3).
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

1. **Change the version** in `pubspec.yaml`: `version: X.Y.Z+N`:
   always bump the versionCode`+N`; change the versionName `X.Y.Z`, if applicable.
2. **Run tests**: `flutter analyze && flutter test --no-pub -r expanded` (full gate,
   [ADR-0006](adr/0006-ci.md) conventions).
3. **Create fastlane changelog files** — for all locales present under
   `fastlane/metadata/android/`: ** Create
   `fastlane/metadata/android/<locale>/changelogs/<N>.txt` — the filename
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
4. **Build the release artifact** itself:
   `flutter build apk --release` (universal APK). With the local
   `key.properties` present this is release-signed via the Phase C wiring;
   if the file is missing, Gradle silently falls back to **debug** signing —
   the `apksigner verify` step below is the guard against that, never skip
   it.
5. **Verify the signature** — this is both the trust-anchor source and the
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
   Install for example with `adb install -r build/app/outputs/flutter-apk/app-release.apk`.

7. **Run the release script**:

   ```sh
   dart run tool/make_release.dart vX.Y.Z
   # --dry-run first: performs the checks below, no side effects, no prompt
   # first release ever: --accept-fingerprint (see below)
   ```

   - **Checks (refuse to publish on any failure):** cross-checks the tag
     against the `pubspec.yaml` version (the parked workflow's missing
     pre-flight, performed locally), requires a clean tree, refuses when
     `vX.Y.Z` already exists as a tag, and requires the step-4 APK to
     exist. The run also requires the installed SDK to match
     `tool/flutter-version` — a mismatch fails;
     `--accept-flutter-version` writes the pin and stops for commit +
     rerun (first pin), or bypasses a deliberate mismatch for the run.
   - **Signature pin:** the `apksigner verify --print-certs` SHA-256
     certificate fingerprint must match the pin in
     `tool/release_fingerprint.txt` — a mismatch means the wrong key or
     the silent debug-signing fallback; never publish. Also re-checks the
     APK's embedded versionName/versionCode via `aapt` (best effort) and
     prints the APK SHA-256.
   - **First run (`--accept-fingerprint`):** writes the actual fingerprint
     into `tool/release_fingerprint.txt` and stops — the operator decides
     at the pin that the certificate is genuinely the release key — then
     commit the pin (it is public; it goes into the release notes anyway)
     and rerun: the rerun matches the APK against the pin and proceeds.
   - **Confirm, then publish:** on a real run the script demands explicit
     confirmation that step 6's upgrade test was done with **this exact
     APK** (`--tested` skips the prompt for scripted use — do not use it
     to skip the real test); then `git tag vX.Y.Z` → `git push origin vX.Y.Z`
     → `gh release create vX.Y.Z <apk> --generate-notes --notes`
     with the SHA-256 certificate fingerprint and the APK SHA-256 in the
     notes body (GitHub appends the auto-generated changelog; the
     fingerprint is the trust anchor F-Droid metadata later cross-checks).
   - **Not covered:** steps 4–6 — it never builds, never tests, never
     touches the device; step 5's trust decision stays with the operator
     at the first pin.
   - **Manual fallback** (script unusable on some machine):

     ```sh
     git tag vX.Y.Z
     git push origin vX.Y.Z
     gh release create vX.Y.Z \
       build/app/outputs/flutter-apk/app-release.apk \
       --generate-notes \
       --notes "SHA-256 certificate fingerprint: <from step 5's apksigner output>
     APK SHA-256: <sha256sum build/app/outputs/flutter-apk/app-release.apk>"
     ```

     Create the tag explicitly with `git tag`/`git push` — `gh release
     create` would otherwise auto-create it at the default branch's HEAD,
     which may not be the pubspec-bump commit — and by hand the operator
     must apply the same guards the script automates: compare the
     `apksigner` fingerprint against `tool/release_fingerprint.txt` and
     the tag name against `pubspec.yaml`.

   Only point testers at the release once it is visible. (Git history is
   the release diary; the roadmap stays a queue.)
8. **Upload/distribute** (sideload → testers; Play internal track; F-Droid MR
   or automatic build on their side). When Play is involved, the AAB is
   also built locally (`flutter build appbundle --release`); there is no
   automated Play upload.
9. Confirm the store dashboards show the intended version; observe crash
   reports (Play) / F-Droid comments in the days after.

## Parked CI release path (ADR-0009 amended 2026-09, superseded by the per-release checklist)

`.github/workflows/release.yml` — the tag-triggered build-and-sign
pipeline — is **parked, not deleted**: releases are made locally, via
per-release checklist step 7 and its manual fallback (the
[ADR-0009](adr/0009-release-pipeline-and-signing.md) amendment).
The workflow is kept with **`workflow_dispatch` as its only trigger** —
pushing a `vX.Y.Z` tag no
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
workflow verifies them against each other (the local release script does
have that cross-check, but it only guards the scripted local publishing
path; when publishing by hand, the operator applies the same cross-check).

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
