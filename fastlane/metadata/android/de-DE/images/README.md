This directory holds the Google-Play-style store metadata for the **de-DE**
locale, shared with F-Droid via the fastlane triple-T structure (see the
[parent README](../../README.md)).

Layout and file set the stores expect:

- `title.txt` — "NER Cycle App" (13 characters, well within the limit),
  **≤ 30 characters**
- `short_description.txt` — **≤ 80 characters**
- `full_description.txt` — **≤ 4000 characters**
- `changelogs/<versionName>.txt` — the release notes (authoring file); the
  numeric `<versionCode>.txt` entries plus `default.txt` are generated
  relative symlinks by `tool/fdroid_changelog_links.dart`
- `images/` — **partially done**: `phoneScreenshots/` exists (Gate G4
  pending for the remaining assets)

## Images: screenshots exist, feature graphic pending Gate G4

`phoneScreenshots/` holds **2 screenshots** (`01.png`, `02.png`, 1080×2340)
of the app's English UI, copied byte-identical from
`../en-US/images/phoneScreenshots/` (by decision the German store shows the
English-UI shots for now; German-UI shots may follow later).

The shots are 1080×2340 = 19.5:9 (near-9:20 tall — a standard modern-phone
screenshot ratio; Play accepts up to 9:21), which exceeds F-Droid's classic
16:9/9:16 guidance. They are kept uncropped rather than faking the ratio —
re-capture on a 16:9 display if an F-Droid reviewer ever objects.

The F-Droid listing icon (512×512) lives in `../en-US/images/icon.png`;
F-Droid reads it from the default locale, so no per-locale copies exist.

Still missing until Gate G4 ("branding assets") lands and a final logo
exists:

- `featureGraphic.png` (1024×500)

Do **not** mistake "NER Cycle App" for a
decided product name: it is a clearly-marked **working title** shown to
test users (Gate G4 placeholder), recorded as such in `docs/release.md`;
the package name `cycle_app` remains an internal placeholder (ADR-0002).

See `docs/product/vision.md` for wording constraints: no INER-endorsement
claims, the license is Apache-2.0 (chosen 2026-09).
