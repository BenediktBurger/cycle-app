# Zyklus-App (Arbeitstitel) / Cycle App

[![CI](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml/badge.svg)](https://github.com/BenediktBurger/cycle-app/actions/workflows/ci.yml)

A local-first, open-source mobile app (Android + iOS, PWA bonus) for tracking
menstrual-cycle symptoms and manually evaluating them per **NER rules
(Rötzer), in the INER spirit** — the user places the marks and stays the
authority; the app is a tool (visualization, arithmetic, statistics), not the
decision-maker.

> **INER framing is a working assumption** (NFP/NER "Mode M", see
> [ADR-0001](docs/adr/0001-iner-mode-m-hypothesis.md), status: *Hypothesis*) —
> to be validated with INER experts before any interpretive feature ships.
> For the full picture read [docs/product/vision.md](docs/product/vision.md).

- **Package name `cycle_app`** is an explicit **PLACEHOLDER** (ADR-0002) —
  rename is a one-line `pubspec.yaml` change later.
- **⚠️ license-tbd**: No license yet — license is TBD, will likely be
  GPL-3-compatible eventually. Do not treat the tree as licensed until one is
  chosen.
- Local-first: no cloud, no analytics; data stays on the device
  (drift/SQLite, encrypted on native platforms later — ADR-0005).

## Getting started

```sh
flutter pub get
flutter run -d chrome
```

Requires a Flutter stable SDK (any location with `<sdk>/bin` on PATH). See
[CONTRIBUTING.md](CONTRIBUTING.md) for the full setup, platform scaffolding,
and the analyze/test/build commands.

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
German-first with an English switch. Still open: the Mode-M marking UI
([docs/roadmap.md](docs/roadmap.md)).

## License

**TBD** — no license has been chosen yet; it will likely be GPL-3-compatible
eventually. Do not treat the tree as licensed until one is chosen.
