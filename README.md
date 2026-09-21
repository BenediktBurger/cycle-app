# Zyklus-App (Arbeitstitel) / Cycle App

[![CI](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml/badge.svg)](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml)

A local-first, open-source mobile app (Android + iOS, PWA bonus) for tracking
menstrual-cycle symptoms and manually evaluating them per **NER rules
(Rötzer), in the INER spirit** — the user places the marks and stays the
authority; the app is a tool (visualization, arithmetic, statistics), not the
decision-maker.

> **The app supports, it never decides.** The product shape is
> "Mode M" (NFP/NER assisted marking, see
> [ADR-0001](docs/adr/0001-iner-mode-m-hypothesis.md), status: *Accepted* —
> by owner decision, 2026-09-19). The user/couple stays in control and
> takes conscious decisions; the app computes and warns about arithmetic,
> but never gives a fertility verdict. Knowing the method (book or course)
> is a prerequisite for reliable interpretation. This posture is the
> owner's, **not endorsed by INER**.
> For the full picture read [docs/product/vision.md](docs/product/vision.md).

> **⚠️ This is an alpha version — do NOT rely on its data. Data might get
> lost.**

- **Package name `cycle_app`** is an explicit **PLACEHOLDER** (ADR-0002) —
  rename is a one-line `pubspec.yaml` change later.
- **⚠️ license-tbd**: No license yet — license is TBD, will likely be
  GPL-3-compatible eventually. Do not treat the tree as licensed until one is
  chosen.
- Local-first: no cloud, no analytics; data stays on the device
  (drift/SQLite, encrypted on native platforms later — ADR-0005).

## Trying it out (testers)

This section is for people who just want to install the app on an **Android**
device — no Flutter SDK, no development setup needed. (An iOS build does not
exist yet.)

### Where to get it

Download the APK from the
[GitHub releases page](https://github.com/BenediktBurger/cycle-app/releases).
Each release carries one release-signed, universal APK — a single file that
runs on all Android devices. Every release note also lists the APK's SHA-256
checksum and the signing certificate's SHA-256 fingerprint, so you can verify
the download if you want to.

### Installing

1. Download the APK from the latest release.
2. Open the downloaded file on the device.
3. Android will warn about installing apps from an external source
   (sideloading / "unknown sources") — accept it to continue.
4. Expect an additional "unknown developer" / "unsafe app" style
   Play-Protect remark: the app is signed with the project's own key and is
   not distributed through a store. This is expected, not a sign that
   something is wrong with the file.

### Updating

Download the most recent APK from the releases page and install it over the
existing version. Because the signing certificate stays the same, Android
updates the app in place instead of treating it as a new install, and your
data stays. That said: this is an alpha — data loss is not ruled out, so
exporting your data (JSON export in the Einstellungen screen) before
updating is wise.

### Privacy note

The app is fully offline: no network access, no analytics. All data stays on
your device.

## Getting started

```sh
flutter pub get
flutter run -d chrome
```

Requires a Flutter stable SDK (any location with `<sdk>/bin` on PATH). See
[CONTRIBUTING.md](CONTRIBUTING.md) for the full setup, platform scaffolding,
and the analyze/test/build commands — notably `flutter pub get` before
`flutter test`.

## Tech stack

- **Flutter** stable (web as iteration target, per
  [ADR-0003](docs/adr/0003-target-platforms-web-iteration.md); product
  targets Android + iOS)
- **flutter_riverpod** for state management
  ([ADR-0004](docs/adr/0004-riverpod-flchart-flutter.md))
- **drift / SQLite** for local-first storage
  ([ADR-0005](docs/adr/0005-storage-and-encryption.md))
- **`flutter gen-l10n`** for localization, German-first with English mirrored

## Project layout / docs

- [docs/product/vision.md](docs/product/vision.md) — product vision and
  requirements.
- [docs/adr/README.md](docs/adr/README.md) — architecture decision records
  (ADR-0001 … ADR-0007 — 0007 is the language policy).
- [docs/dev-notes.md](docs/dev-notes.md) — operational lessons and how-tos.
- [docs/roadmap.md](docs/roadmap.md) — open work / upcoming milestones
  (to-do list; history lives in git).
- `.github/workflows/ci.yml` — GitHub Actions CI: `flutter analyze`,
  `flutter test`, `flutter build web` (ADR-0006).

## Status

Working app: Tagebuch / Zyklus / Statistik / Einstellungen on a local
drift database (SQLite file on Android/iOS, WebAssembly/OPFS in the
browser; data persists across reloads), with JSON export/import. The UI is
German-first with an English switch, including the Mode-M marking UI
(first higher measurement, mucus peak, SUZ — computed evaluation marks on
the cycle chart, see [docs/roadmap.md](docs/roadmap.md) for open work).

## Screenshots

Two screenshots of the current app (cycle chart and diary) are in the
fastlane store metadata:
[01](fastlane/metadata/android/en-US/images/phoneScreenshots/01.png) and
[02](fastlane/metadata/android/en-US/images/phoneScreenshots/02.png)
(shown in English, matching the en-US store listing).

## Import from drip

The Einstellungen screen can import a **CSV export of the drip cycle
tracker** (a sibling project): paste it anywhere (a file picker is offered
on the web). Rows merge into the **main profile** with the same
overwrite-by-date policy as the JSON import, so re-importing the same export
adds no duplicates. Per day, drip's bleeding, temperature, mucus (including
the S+ → slippery egg-white decode), desire, sex, pain, mood, cervix words,
and notes are mapped into the NFP diary. **Lost in the import**: the
per-symptom exclude flags other than the temperature one (an excluded
temperature just marks the day) and the temperature measurement time.

Five mapping decisions below are **awaiting NFP expert (INER) review** —
they are also marked `TODO(user-review)` in the code:

- Light/medium/heavy bleeding all collapse into a single "period" entry.
- Drip's "temperature excluded" becomes a generic interrupted day; the
  reason for the exclusion is not stored.
- The mucus decode works on drip's combined NFP number, so texture nuances
  are lost: any NFP 4 — including one drip derived from a slippery
  feeling — imports as S with egg-white quality (≙ S+), whereas a slippery
  feeling recorded without a texture imports no mucus at all (mirrors
  drip; the creamy nuance is likewise lost).
- Cervix observations become free-text English words, and out-of-range
  indices are clamped to the nearest valid one.
- Symptom notes concatenate after the day note as
  `[temp]`/`[pain]`/`[sex]`/`[mood]` prefixed lines.

## License

**TBD** — no license has been chosen yet; it will likely be GPL-3-compatible
eventually. Do not treat the tree as licensed until one is chosen.
