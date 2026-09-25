# ADR-0009: Release pipeline — Android-first publishing, signing custody, store accounts

- **Date:** 2026-09-18
- **Status:** Accepted
  (amended in place five times, 2026-09: first to local-only releases with
  the tag-triggered pipeline parked, then to an unsigned tag-triggered CI
  build, then to a tagless branch-triggered CI build with the tag and
  release authored at publish time, then to a two-script split of
  the local release helper with the CI Flutter pin read directly from
  `tool/flutter-version`, and finally to a release signing gate that
  fails the build without the provisioned keystore — see decision #6 and
  its amendment notes)

## Context

The product targets Android + iOS ([ADR-0003](0003-target-platforms-web-iteration.md));
development iterates on web. Distribution planning surfaced the following
starting state:

- No Android SDK on the dev machine yet; CI is deliberately web-only
  ([ADR-0006](0006-ci.md)) — that original decision predates this ADR, and
  this ADR's follow-up decision (#6, documented after the Context section)
  now supersedes the web-only clause: ADR-0006 has since been amended to
  also compile an Android debug build and run tag-triggered release builds.
- `android/` started from the untouched Flutter template: release build signed
  with the *debug* key, `applicationId` was the
  [ADR-0002](0002-package-name-cycle-app-placeholder.md) placeholder
  `com.example.cycle_app` — already replaced by the Gate G1 decision below
  (see the resolved open question).
- License: none was chosen yet when this ADR was written (README flagged
  the choice as still open) — a hard blocker for F-Droid, not for local
  APK testing or Play development; Apache-2.0 has since been chosen
  (owner decision, 2026-09, final confirmation before the first store
  upload still open — see the open-questions entry below).
- The collaboration with INER (iner.org): an endorsement is likely (logo on
  the listing), INER may eventually assume publishing — but INER is not
  technical, so day-to-day release operations stay with the project owner.
  The relationship is not finally settled, and the `applicationId` is an
  effectively immutable decision on Play.

The dependency graph matters: the first store upload is the **last moment**
at which the applicationId, the license, and the publisher-account type can
still be changed cheaply. Signing keys outlive store accounts: whoever holds
the private key can produce valid updates for the installed base on
sideload/F-Droid, so key custody is a governance question in itself.

## Decision

1. **Channels, Android first.** Local release APKs for testing; **Google
   Play** as the primary store; **official F-Droid inclusion** as the
   intermediate channel, possibly permanent. iOS is a **deferred parallel
   workstream** (needs macOS/Xcode; test builds via TestFlight) gated behind
   Android release experience. All three Android-relevant artifacts share one
   identity decision (below).
2. **Signing custody.** One release keystore per app, created once, never
   committed; wired via a gitignored `key.properties` (already covered by
   `android/.gitignore`). **Custody stays with the release operator** (the
   owner), not with INER — an organization taking over publishing without
   technical competence is the classic lost-key failure mode. Password
   manager + two offline encrypted backups; a handover runbook lives in
   [`docs/release.md`](../release.md).
3. **Play App Signing + individual console account.** Enroll in Play App
   Signing (Google holds the *app signing key*; our *upload key* is
   recoverable if lost). Register the Play console as an **individual**
   account first (no D-U-N-S wait). An organization console (Play *and/or*
   Apple) is only created when an INER takeover or formal org becomes real —
   the D-U-N-S number is the long-lead-time item and should be started early
   at that point.
4. **applicationId policy.** Final value must be chosen **before the first
   store upload** (Play: immutable; F-Droid: same app entry). Acceptable end
   states: a project/owner domain namespace, or `org.iner.*` **with INER's
   explicit consent** (an app does not need "iner" in its ID to be handed
   over to INER later — the transfer mechanisms are the signing key, repo
   URL, and Play account transfer). The same string is reused verbatim as
   the iOS bundle identifier. Until then, the rename stays staged
   ([ADR-0002](0002-package-name-cycle-app-placeholder.md)).
5. **Release verification.** Every distribution update passes the full
   analyze/test gate **plus an upgrade test on a real device** (old release
   with entered data → install the new release → drift migrations preserve
   the cycle data). Users' cycle history is irreplaceable; a broken
   migration is a data-loss incident, not a bug.
6. **Documentation split.** The enactable runbook (commands, checklists,
   gates) lives in [`docs/release.md`](../release.md); the work queue lives in
   [`docs/roadmap.md`](../roadmap.md). Tag-triggered signed release builds
   run in CI: a release workflow builds signed artifacts on `vX.Y.Z` tags,
   with the release keystore provisioned as a GPG-encrypted GitHub Actions
   secret and decrypted only into the runner's ephemeral temp directory —
   the keystore is never committed (custody per decision #2 above) and never
   decrypted outside `$RUNNER_TEMP`; the offline backups remain authoritative.
   (Supersedes the earlier "CI stays web-only" clause —
   [ADR-0006](0006-ci.md) itself now also compiles the Android target in
   debug mode as a correctness gate.)

   **Amended in place (2026-09):** release builds and signing are performed
   **locally** by the release operator; GitHub Releases are created manually
   (`gh release create` with the `vX.Y.Z` tag and the signed APK). Signing
   secrets never enter GitHub. The tag-triggered workflow above is **parked,
   not deleted** (kept with `workflow_dispatch` as its only trigger) for a
   possible later re-enable; the keystore-as-GPG-secrets provisioning scheme
   was documented in [`docs/release.md`](../release.md) ("Parked CI release
   path" — historical; since superseded, see the 2026-09 un-park amendment
   below; the pointer's target section is gone, its topic is superseded
   history). Reason: a
   minimal custody surface until F-Droid distribution is running. This
   amendment supersedes the tag-triggered clause above; the
   documentation split itself is unchanged, and decision #5's device
   upgrade test is unaffected — under the local path it runs *before*
   publishing, which the parked CI flow could not guarantee.

   **Amended again in place (2026-09):** the workflow is un-parked in the
   opposite shape: GitHub Actions builds the release APKs **unsigned** on
   `vX.Y.Z` tag pushes and uploads them as workflow artifacts; the
   release keystore stays off GitHub entirely, and signing is a *local*
   apksigner step that replaces the CI builds' debug-signing-fallback
   blocks, automated by the local release helper of the time (a single
   all-in-one sign-then-publish script; its name is retired and its
   duties are split — see the 2026-09 split amendment below: download →
   verify → sign → attach). apksigner must come from Android build-tools
   ≤ 34: a
   35+ apksigner signature cannot be handled by the F-Droid buildserver's
   signature copying. This supersedes the parked state and the
   keystore-as-GPG-secrets scheme documented above; the runbook in
   [`docs/release.md`](../release.md) is the authority (originally its
   "CI release path" section, later folded into the single per-release
   checklist — see the amendment below). Reason: the upstream release
   APKs must be byte-reproducible
   against the F-Droid buildserver (per-build `binary:` verification), a
   requirement that shapes the CI build environment — and the CI checkout
   path invariant — not the signing custody.

   **Amended a third time in place (2026-09):** the release build no
   longer waits for a tag: it triggers on pushes of `release/**`
   branches (naming `release/v<semver>`) and on `workflow_dispatch`; the
   version in the artifact names comes from `pubspec.yaml`
   (`version: A.B.C+N`), so no tag exists at build time. The tag and the
   GitHub release are authored later, at publish time, by the local
   publish helper of that amendment (`gh release create vX.Y.Z --target
   <the commit CI built>`), so tag, release, and signed assets appear
   atomically at the exact commit the run built — and a failed CI build
   leaves no dangling tag. This supersedes the tag-push trigger
   documented above; [`docs/release.md`](../release.md) stays the
   authority.

   **Amended a fourth time in place (2026-09):** the single local release
   helper referenced by the two amendments above (the all-in-one
   sign-then-publish script; its file name is retired since the script
   was deleted) is replaced by a two-script split with a deliberate
   break between them:
   `tool/download_and_sign.dart` runs everything through signing and
   staging (no publish, no PR, and — by design — no dry-run; it mutates
   nothing outside gitignored directories) and ends by writing the
   handoff manifest `build/gh-release/source.json` (tag, versionName,
   versionCodeBase, runId, headSha) and printing the adb install lines;
   the device install + DB-migration test (decision #5) now happens as a
   real script break; `tool/publish_release.dart` then consumes the
   staged directory, computes checksums, assembles the release/tag at the
   manifest's head SHA, opens the release-branch PR, and carries the
   only `--dry-run` — print-only, with REAL checksums computed from the
   staged files (the former sign-side rehearsal mode is removed). A
   Flutter bump is now a one-file edit: ALL CI workflows read
   `tool/flutter-version` directly with the F-Droid build recipe's exact
   parse — the pin-sync tooling of the separately deleted local-build
   release helper is gone with it, mirror input lines remain in no
   workflow, and a malformed pin fails loudly in both workflows' resolve
   steps. [`docs/release.md`](../release.md) stays the authority.

   **Amended a fifth time in place (2026-09-25):** the Gradle release
   build no longer falls back to the debug signing key when
   `android/key.properties` is absent — it fails the build instead. The
   fallback was the CI case, but it also made a debug-signed release
   artifact silently buildable (and shippable) — the exact mistake this
   decision guards against. The one opt-in is an explicit Android
   project argument `-PallowDebugSigning`: the release workflow passes
   it (unchanged in substance — CI artifacts are still debug-keyed and
   apksigner signs them locally against the pinned fingerprint), and a
   future F-Droid buildserver recipe needs the same opt-in in its own
   invocation. The provisioning requirement
   (`key.properties` + existing keystore path) is documented in Phase C
   of [`docs/release.md`](../release.md), which stays the authority for
   the gate's mechanics.

## Consequences

- A first distributable artifact (sideload APK) is possible **without any
  identity or license decision**.
- Store submissions are intentionally blocked by the open questions below —
  they are one-way doors and must not be improvised at submit time.
- If INER later takes over publishing: Play app transfer and F-Droid
  metadata/URL updates keep the installed base intact; the keystore outlives
  account changes. No renaming of the applicationId is needed for a handover.
- The web/PWA path is unaffected; web assets keep their own distribution
  story.
- The iOS bundle identifier decision is shared with decision #4; iOS
  signing is account-based (certificates are reissuable by Apple), so the
  Android *keystore* — not Apple certificates — remains the only artifact
  demanding paranoid backup.

## Open questions (marked, not settled)

- **RESOLVED (owner decision, 2026-09):** final applicationId is
  `io.github.benediktburger.cycleapp` (GitHub user "BenediktBurger",
  lowercased per reverse-domain convention); no `org.iner.*` identifier.
  As noted in the decision text above, a later `org.iner.*` usage stays
  possible as a **one-way migration** (Play identifiers are immutable after
  the first store upload) — it would require INER's explicit written
  consent and only makes sense if INER formally takes over publishing.
  Applied to `android/app/build.gradle.kts` (`applicationId` + `namespace`)
  and the relocated `MainActivity.kt` package; the Dart package name stays
  `cycle_app` per [ADR-0002](0002-package-name-cycle-app-placeholder.md).
- **RESOLVED (owner decision, 2026-09):** license choice (Gate G2) is
  **Apache-2.0** — the `LICENSE` file at the repo root carries the full
  text; F-Droid accepts it as a free-software license, and the F-Droid
  metadata `License:` value follows it. Residual
  `TODO(user-review)`: the final confirmation of Apache-2.0 before the
  first store upload (Gate G2) is still open.
- `TODO(user-review)`: whether INER becomes the Play/Apple publisher of
  record — determines D-U-N-S timing and the EU DSA **trader status** of the
  developer accounts on both stores (also relevant for a solo individual
  account under the endorsement arrangement).
- The exact F-Droid build recipe (Flutter version pinning, split/universal
  APK choice) is resolved **at submission time** against current
  `fdroiddata` conventions, not pre-decided here.
