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
the `docs/fdroid-metadata-draft.yml` file in the repo holds the
F-Droid `metadata/<applicationId>.yml` draft pending the fdroiddata MR.

## Status — working title, placeholder assets

- **"NER Cycle App" is a working title, not a decided name** — the shown
  name for test users during testing (store `title.txt` etc. already show
  it; display name explicitly still undecided, see release.md Gate G1/G4
  notes). The package name `cycle_app` remains a clearly-marked
  **internal placeholder** (ADR-0002) and does not affect the shown name
  (the same caveat lives in each locale's `images/README.md`). The store
  text files must stay usable as-is (stores parse `title.txt` etc.
  literally, ≤ 30 characters).
- **Images: partially done** — `phoneScreenshots/` exists for both locales
  (2 PNG shots each, English UI, shared by `de-DE` and `en-US`); `icon.png`
  and `featureGraphic.png` remain pending Gate G4 and do not exist yet.
- **Screenshot ratio note:** the phone screenshots are 1080×2340 = 19.5:9
  (near-9:20 tall — a standard modern-phone screenshot ratio; Play accepts
  up to 9:21), which exceeds F-Droid's classic 16:9/9:16 guidance. They are
  kept uncropped rather than faking the ratio — re-capture on a 16:9
  display if an F-Droid reviewer ever objects.
- Commissioning / endorsement wording constraints come from
  `docs/product/vision.md`: describe the method as "per NER rules (Rötzer),
  in the spirit of INER" — **never claim INER endorsement**.
- The F-Droid submission itself is **blocked by Gate G2** — only by the
  final Apache-2.0 (chosen 2026-09) confirmation before the first store
  upload; the license choice itself is made. `docs/fdroid-metadata-draft.yml`
  is a draft, never submitted as-is.
