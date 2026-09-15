# ADR-0004: Riverpod for state management; fl_chart for the temperature curve

- **Date:** 2026-09-15
- **Status:** Accepted

## Context

The app needs reactive state management for a local-first data app: reactive
entry screens, streams of DB rows grouped by cycle, statistics recomputed on
data changes, and a small amount of app-level UI state (settings, language).
The ecosystem offers Provider, BLoC, Riverpod, MobX, plain ChangeNotifier
etc.

The core visualization is a **temperature curve** (BBT over cycle days) with
an additional symbol row (bleeding, mucus, marks) below/around it, tappable
per day. Charting options include fl_chart and custom painting; PDF/graphic
exports (Auswertungsbogen) are a later feature.

## Decision

- **State management: Riverpod (`flutter_riverpod`).**
- **Charting: `fl_chart`** for the temperature curve (added in Phase 2 — not
  in the M1 shell pubspec).
- `pdf` + `printing` are **deferred past M1**; the PDF export requirement
  (Auswertungsbogen) is not part of M1 and will get its own decision/ADR when
  it is built.
- Split Story note: plain Dart SQLite access was considered; it is covered by
  ADR-0005 (drift on top of SQLite), which is where the storage decision
  lives.

## Consequences

- Riverpod: compile-time-safe providers, streams from drift map naturally to
  Riverpod providers, no BuildContext juggling for business logic. Adds a
  (well-known, small) framework dependency and the ProviderScope at the app
  root. Widget tests pump with a ProviderScope — documented pattern
  `providerScope` overrides in tests.
- fl_chart: covers line chart + symbol/scatter layers out of the box; stylization
  for Rötzer-style curves (coverline, phase lines) is achievable but has some
  learning curve; if its API cannot express a NER-specific overlay, we fall
  back to a custom painter for that layer only (kept behind a small widget
  facade).
- Deferred pdf/printing: no dependency bloat in M1; the export feature will be
  a separate milestone decision.
