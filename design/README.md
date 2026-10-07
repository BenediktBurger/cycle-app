# Design assets

`design/logo.svg` is the single master for every app-icon artifact. All
rasters are derived from it — change the SVG, never a PNG.

| Artifact                                          | Size      | Producer                                        |
|---------------------------------------------------|-----------|-------------------------------------------------|
| `design/icon.png`                                 | 1024×1024 | Inkscape render of `logo.svg`                   |
| Android mipmaps + iOS asset catalog               | 48–432 px | `flutter_launcher_icons` from `design/icon.png` |
| `fastlane/metadata/android/en-US/images/icon.png` | 512×512   | Inkscape render of `logo.svg`                   |

## On a logo change

1. Render the master raster:

   ```sh
   inkscape design/logo.svg -w 1024 -h 1024 -o design/icon.png
   ```

2. Regenerate the launcher icons (all Android densities + the iOS asset
   catalog; the generated outputs are committed):

   ```sh
   dart run flutter_launcher_icons
   ```

3. Render the F-Droid listing icon:

   ```sh
   inkscape design/logo.svg -w 512 -h 512 \
     -o fastlane/metadata/android/en-US/images/icon.png
   ```

4. Check sizes and channels — both renders are 8-bit sRGB with a fully
   opaque alpha channel:

   ```sh
   identify -verbose design/icon.png \
     fastlane/metadata/android/en-US/images/icon.png | grep -E "Geometry|alpha"
   ```

5. Commit the SVG, `design/icon.png`, and all regenerated outputs.

## Notes

- Always use Inkscape for the raster renders (byte-reproducible here, and
  one renderer means all artifacts share the same antialiasing).
  `rsvg-convert` is not installed; do not use ImageMagick's internal SVG
  renderer (`convert file.svg`) — it is not spec-compliant.
- Inkscape exports carry an alpha channel even though the SVG paints an
  opaque white background. That is fine everywhere except Apple's App
  Store, where `flutter_launcher_icons` strips it (`remove_alpha_ios` in
  `pubspec.yaml`).
- Only the `en-US` locale carries a store icon: F-Droid reads the listing
  icon from the default locale, so no per-locale copies exist.
- Distribution lag differs: the launcher icon ships with the next app
  release, while the F-Droid listing icon updates with F-Droid's next
  metadata update — no release needed.
- `featureGraphic.png` (1024×500, Play Store) is pending Gate G4; when it
  is created, it joins this chain.
