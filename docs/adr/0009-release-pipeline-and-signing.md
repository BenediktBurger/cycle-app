# ADR-0009: Release pipeline — Android-first publishing, signing custody, store accounts

- **Date:** 2026-09-18
- **Status:** Accepted

## Context

The product targets Android + iOS ([ADR-0003](0003-target-platforms-web-iteration.md));
development iterates on web. Distribution planning surfaced the following
starting state:

- No Android SDK on the dev machine yet; CI is deliberately web-only
  ([ADR-0006](0006-ci.md)) — that original decision predates this ADR, and
  this ADR's follow-up decision (#6, documented after the Context section)
  now supersedes the web-only clause: ADR-0006 has since been amended to
  also compile an Android debug build and run tag-triggered signed releases.
- `android/` started from the untouched Flutter template: release build signed
  with the *debug* key, `applicationId` was the
  [ADR-0002](0002-package-name-cycle-app-placeholder.md) placeholder
  `com.example.cycle_app` — already replaced by the Gate G1 decision below
  (see the resolved open question).
- No license has been chosen yet (README `license-tbd`) — a hard blocker for
  F-Droid, not for local APK testing or Play development.
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
- `TODO(user-review)`: license choice (Gate G2) — blocks F-Droid metadata
  (F-Droid requires a free-software license); README signals
  GPL-3-compatible intent.
- `TODO(user-review)`: whether INER becomes the Play/Apple publisher of
  record — determines D-U-N-S timing and the EU DSA **trader status** of the
  developer accounts on both stores (also relevant for a solo individual
  account under the endorsement arrangement).
- The exact F-Droid build recipe (Flutter version pinning, split/universal
  APK choice) is resolved **at submission time** against current
  `fdroiddata` conventions, not pre-decided here.
