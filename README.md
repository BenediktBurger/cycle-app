# Zyklus-App (Arbeitstitel) / Cycle App

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for environment setup (Flutter SDK,
platform scaffolding, run/analyze/test/build commands) and the current
implementation status.

## Project layout / docs

- [docs/product/vision.md](docs/product/vision.md) — product vision and
  requirements.
- [docs/adr/README.md](docs/adr/README.md) — architecture decision records
  (ADR-0001 … ADR-0006).
- `.github/workflows/ci.yml` — GitHub Actions CI: `flutter analyze`,
  `flutter test`, `flutter build web` (ADR-0006).

## Status: Milestone 1 (phase 1)

Phase-1 scaffold: app shell (Riverpod `ProviderScope` → `MaterialApp`,
Material-3 `NavigationBar` with 4 placeholder tabs Tagebuch / Zyklus /
Statistik / Einstellungen), German-first localization via `flutter gen-l10n`
with English mirrored, no database yet (data layer lands in Phase 2).
