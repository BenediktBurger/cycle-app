# NER Cycle App (Arbeitstitel)

[![GitHub Release](https://img.shields.io/github/v/release/BenediktBurger/cycle-app)](https://github.com/BenediktBurger/cycle-app/releases)
[![CI](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml/badge.svg)](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml)

---

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

> **This app is in beta.** A beta can still lose data, so export your data
> **regularly and before every update** — via the JSON export in the
> settings screen. Everything is stored locally on your device, and the
> JSON export is the one backup path on all platforms (see
> [Backup, migration & recovery](#backup-migration--recovery)).

- **Package name `cycle_app`** is an explicit **PLACEHOLDER** (ADR-0002) —
  rename is a one-line `pubspec.yaml` change later.
- **⚠️ license — chosen, final confirmation open**: the license has been
  chosen (2026-09): **Apache-2.0** — full text in the
  [`LICENSE`](LICENSE) file at the repo root. The tree is distributed under
  Apache-2.0; the final confirmation before the first published release is
  still open.
- Local-first: no cloud, no analytics; data stays on the device
  (drift/SQLite, encrypted on native platforms later — ADR-0005).

## Installation

Install the app on an **Android** device — no Flutter SDK, no development
setup needed. (An iOS build does not exist yet.)

What to expect: the app supports observing and computing/visualizing only —
it does not interpret your data, advise, or give a fertility verdict.
Knowing the method (book or course) is a prerequisite for reliable
interpretation; see the "The app supports, it never decides" block above
for the full posture.

### Where to get it

Download an APK from the
[GitHub releases page](https://github.com/BenediktBurger/cycle-app/releases).
Each release carries three release-signed APKs — one per device
architecture (ABI), named `cycle-app-<version>-<abi>.apk` where `<version>`
is the release's version number, e.g. `cycle-app-0.2.0-arm64-v8a.apk`. Pick
the one matching your phone:

- `cycle-app-<version>-arm64-v8a.apk` — modern phones (the right choice for
  most devices),
- `cycle-app-<version>-armeabi-v7a.apk` — older 32-bit devices,
- `cycle-app-<version>-x86_64.apk` — mainly emulators.

Not sure which? Check *Settings → About phone* for the processor
information, or — with the phone connected to a computer and
developer options enabled — run `adb shell getprop ro.product.cpu.abi`.
All three APKs are signed with the same release key. Every release note
lists each APK's SHA-256 checksum plus the signing certificate's SHA-256
fingerprint, so you can verify the download if you want to.

### Installing

1. Download the APK matching your device (see above) from the latest
   release.
2. Open the downloaded file on the device.
3. Android will warn about installing apps from an external source
   (sideloading / "unknown sources") — accept it to continue.
4. Expect an additional "unknown developer" / "unsafe app" style
   Play-Protect remark: the app is signed with the project's own key and is
   not distributed through a store. This is expected, not a sign that
   something is wrong with the file.

### Updating

Download the most recent APK for your device's architecture (the same one
you installed before) from the releases page and install it over the
existing version. Because the signing certificate stays the same, Android
updates the app in place instead of treating it as a new install, and your
data stays. That said: this is a beta — data loss is not ruled out, so
exporting your data (JSON export in the settings screen) before updating is
necessary, and exporting regularly while you use the app is wise.

### Privacy note

The app is fully offline: no network access, no analytics. All data stays on
your device.

Found an issue or have a suggestion? Please open an issue at
[github.com/BenediktBurger/cycle-app/issues](https://github.com/BenediktBurger/cycle-app/issues)
— feedback is very welcome.

## Installation (Deutsch)

Deutsche Fassung des Wichtigsten für deutschsprachige Nutzer —
Installationsweg, Beta- und Backup-Hinweis, Charakter der App, Feedback:

Die App unterstützt die Beobachtung des Zyklus: Sie erfassen jeden Tag Ihre
Daten, und die App rechnet und zeigt an — sie schlägt nichts vor und
entscheidet nichts. Methodenkenntnisse (aus einem Lehrbuch oder einer
Schulung) sind Voraussetzung für eine zuverlässige Beurteilung.

**Beta-Hinweis:** Die App befindet sich in der Beta-Phase. Datenverlust ist
nicht ausgeschlossen — exportieren Sie Ihre Daten deshalb **regelmäßig und
vor jedem Update** über den JSON-Export in den Einstellungen. Alle Daten
liegen lokal auf dem Gerät; der JSON-Export ist auf allen Plattformen der
einzige Backup-Weg (Einzelheiten: [Backup, migration & recovery
(auf Englisch)](#backup-migration--recovery)).

**Installation (Android):** Eine iOS-Version gibt es noch nicht.

1. Laden Sie die zu Ihrem Gerät passende APK von der
   [GitHub-Releases-Seite](https://github.com/BenediktBurger/cycle-app/releases)
   herunter. Jedes Release enthält drei APKs — eine pro Gerätearchitektur:

   - `cycle-app-<version>-arm64-v8a.apk` — moderne Telefone (die richtige
     Wahl für die meisten Geräte),
   - `cycle-app-<version>-armeabi-v7a.apk` — ältere 32-Bit-Geräte,
   - `cycle-app-<version>-x86_64.apk` — hauptsächlich Emulatoren.

2. Öffnen Sie die heruntergeladene Datei auf dem Gerät und bestätigen Sie
   die Warnung zum Installieren aus einer externen Quelle (Sideload /
   „unbekannte Quellen“).
3. Ein zusätzlicher Play-Protect-Hinweis („unbekannter Entwickler“) ist zu
   erwarten: Die App ist mit dem eigenen Schlüssel des Projekts signiert
   und wird über keinen Store verteilt — das ist normal und kein Zeichen
   für ein Problem.

### Aktualisierung

Laden Sie die neueste APK für dieselbe Architektur herunter und
installieren Sie sie über die bestehende Version. Da der
Signaturschlüssel gleich bleibt, wird die App an Ort und Stelle
aktualisiert und Ihre Daten bleiben erhalten — aber: exportieren Sie
vorher (siehe Beta-Hinweis oben).

Fehler gefunden oder Verbesserungsvorschlag? Bitte öffnen Sie ein Issue auf
[GitHub](https://github.com/BenediktBurger/cycle-app/issues).

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

## Backup, migration & recovery

Backup, data migration to another device, and data recovery all happen
through the **JSON export/import in the Einstellungen (settings) pane — and
nowhere else**:

- Export regularly to a file you control (Einstellungen › JSON-Export) and
  import it on the target device to restore/re-migrate your data there.
- **Never copy the database file itself** (Android/iOS): there the database
  is encrypted with a device-bound key (see
  [ADR-0005](docs/adr/0005-storage-and-encryption.md)), so a copied file is
  unopenable data on anything else — not a backup.
- On the **web build** the browser storage (OPFS/IndexedDB) is not encrypted
  by the app (web stays an unencrypted development tool).

JSON export/import is the only backup path on **all** platforms — web
included.

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

**Apache-2.0** — chosen (owner decision, 2026-09); the full text is in the
[`LICENSE`](LICENSE) file at the repo root. The final confirmation before the
first published release is still open.

One shipped asset already carries its own license: the bundled Noto Sans
Regular font (used by the PDF export so note text renders beyond Latin-1)
is Google's, licensed under the SIL Open Font License 1.1 — see
`assets/fonts/LICENSE-NotoSans.txt`.
