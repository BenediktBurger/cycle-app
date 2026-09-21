This directory holds the Google-Play-style store metadata for the **de-DE**
locale, shared with F-Droid via the fastlane triple-T structure (see the
[parent README](../../README.md)).

Layout and file set the stores expect:

- `title.txt` — "NER Cycle App" (13 characters, well within the limit),
  **≤ 30 characters**
- `short_description.txt` — **≤ 80 characters**
- `full_description.txt` — **≤ 4000 characters**
- `changelogs/<versionCode>.txt` (one file per versionCode)
- `images/` — **partially done**: `phoneScreenshots/` exists (Gate G4
  pending for the remaining assets)

## Images: screenshots exist, branding assets pending Gate G4

`phoneScreenshots/` holds **2 screenshots** (`01.png`, `02.png`, 1080×2340)
of the app's English UI, copied byte-identical from
`../en-US/images/phoneScreenshots/` (by decision the German store shows the
English-UI shots for now; German-UI shots may follow later).

The shots are 1080×2340 = 19.5:9 (near-9:20 tall — a standard modern-phone
screenshot ratio; Play accepts up to 9:21), which exceeds F-Droid's classic
16:9/9:16 guidance. They are kept uncropped rather than faking the ratio —
re-capture on a 16:9 display if an F-Droid reviewer ever objects.

Still missing until Gate G4 ("branding assets") lands and a real logo
exists:

- `icon.png` (512×512, F-Droid; Play derives 512×512 from adaptive icon or
  high-resolution asset)
- `featureGraphic.png` (1024×500)

These two do not exist yet. Do **not** mistake "NER Cycle App" for a
decided product name: it is a clearly-marked **working title** shown to
test users (Gate G4 placeholder), recorded as such in `docs/release.md`;
the package name `cycle_app` remains an internal placeholder (ADR-0002).

See `docs/product/vision.md` for wording constraints: no INER-endorsement
claims, license remains TBD.
