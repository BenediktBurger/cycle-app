This directory holds the Google-Play-style store metadata for the **de-DE**
locale, shared with F-Droid via the fastlane triple-T structure (see the
[parent README](../../README.md)).

Layout and file set the stores expect:

- `title.txt` — "Cycle App", **≤ 30 characters**
- `short_description.txt` — **≤ 80 characters**
- `full_description.txt` — **≤ 4000 characters**
- `changelogs/<versionCode>.txt` (one file per versionCode)
- `images/` — **all placeholder work, not yet done** (Gate G4)

## Images: pending Gate-G4 placeholder

This app's logo, icon and screenshots do not exist yet; every image used at
store level is a placeholder until Gate G4 ("branding assets") lands and a
real logo exists. The files F-Droid/Play expect here:

- `icon.png` (512×512, F-Droid; Play derives 512×512 from adaptive icon or
  high-resolution asset)
- `featureGraphic.png` (1024×500)
- `phoneScreenshots/*.png` (≥ 2 screenshots, 16:9 or 9:16)

None of these files exist yet — this README is the directory carrier in
their place. Do **not** mistake "Cycle App" for a decided product name: it
is a clearly-marked **working title** (Gate G4 placeholder), recorded as
such in `docs/release.md`.

See `docs/product/vision.md` for wording constraints: no INER-endorsement
claims, license remains TBD.
