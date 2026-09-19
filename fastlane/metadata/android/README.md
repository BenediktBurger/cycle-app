# `fastlane/metadata/android/` — store metadata (one layout, two stores)

This directory holds the store listing for the app in the **fastlane triple-T
structure** — title / (short/full) texts + images per locale. One layout
serves both store channels; the same directory tree is what F-Droid and the
Google Play Console both read from a repository root:

- **F-Droid**: the
  [official documentation](https://f-droid.org/en/docs/metadata/) expects
  `fastlane/metadata/android/en-US/…` (or whatever the default locale is)
  for description, changelogs and images, keyed to the applicationId.
- **Google Play**: uploading the equivalent texts is manual in the console
  (or via the `fastlane supply` tooling); the *content* of these files is
  the source of truth for both, so the listings never drift apart.

Locales present: `de-DE` (first-class language of the app) and `en-US`
(mirror). Editing rules: draft the German text first, then mirror it in
English — mirroring the app's own language policy.

The applicationId used by the stores is
`io.github.benediktburger.cycleapp` (ADR/companion: `docs/release.md`);
the future `docs/fdroid-metadata-draft.yml` file in the repo holds the
F-Droid `metadata/<applicationId>.yml` draft pending the fdroiddata MR.

## Status — working title and placeholder assets

- **"Cycle App" is a working title, not a decided name** (display name is
  explicitly undecided; see release.md Gate G1/G4 notes). The store text
  files must stay usable as-is (stores parse `title.txt` etc. literally,
  ≤ 30 characters), so the placeholder caveat lives here and in each
  locale's `images/README.md`.
- **All images are pending Gate G4** — none exist yet; the `images/`
  directories carry only READMEs describing what will go there.
- Commissioning / endorsement wording constraints come from
  `docs/product/vision.md`: describe the method as "per NER rules (Rötzer),
  in the spirit of INER" — **never claim INER endorsement**.
- The F-Droid submission itself is **blocked by Gate G2** (license still
  TBD) — `docs/fdroid-metadata-draft.yml` is a draft, never submitted.
