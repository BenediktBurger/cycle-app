# Roadmap

**Open work only** — this is a to-do list, not a diary. What has landed is
git history; *why* it landed that way is in
[\`docs/adr/\`](adr/README.md). When an item is done, its checkbox gets
ticked only until it is folded into the next release note/commit — unchecked
items are the queue.

Work-package numbering comes from the internal plan file (ephemeral, not
versioned); the durable record of that numbering is git history, in the
commit messages tagged with it. Any legacy or remaining IDs are mapped
here and appear nowhere else: not in code comments, prose docs, or tool
names (see [`AGENTS.md`](../AGENTS.md)).

## Backlog — issues & improvements

Collector for real issues and improvement ideas that are not (yet) part of a
milestone or the internal plan. Readiness convention: **a plain bullet means
needs discussion** — not startable, the line states what must be resolved
first; **an unchecked checkbox means ready to be implemented** — an agent may
pick it up. When an item is done, it is **removed** from here, not ticked —
the sections above track planned work, git history keeps the record (see
[`AGENTS.md`](../AGENTS.md)).

### Bugs

#### Android

### Necessary

### Convenience

- [ ] **Rename the stored mark token.**
  `firstHigherMeasurement` → `temperatureRise`.
  Footprint: bump `schemaVersion` 14 → 15 in `lib/db/cycle_database.dart`
  and rewrite the existing rows with a `customStatement` UPDATE in
  `onUpgrade` — the mark column is an open TEXT vocabulary, so the
  schema shape does not change and the one-time UPDATE is the whole
  migration; pin the new version and seed an old-token row in
  `test/db/migration_test.dart`; translate old tokens on import in
  `lib/db/export_adapter.dart` so an old backup keeps its mark; keep
  `exportSchemaVersion` at 6 — an old app version stores a new
  export's unknown token unchanged (`lib/db/export_adapter.dart` takes
  any non-empty `mark_type`) and writes it back verbatim on its own
  export (`exportDatabaseToBlob` writes `markType`), so the mark
  round-trips and is only not evaluated there; the version gate exists
  for shape changes that would silently drop data, and this is not one,
  so `test/examples_samples_test.dart` stays valid; reword
  `examples/README.md`'s “the app's current JSON export format (schema
  v6)” in the same change — that file becomes the v6 legacy canary; keep
  `examples/example-cycle.json` as that canary and assert in
  `test/db/example_cycle_import_test.dart` that its mark survives the
  import; update the “persisted token … keeps its name for storage
  stability” sentence in `docs/NER/app-conventions.md`, which the rename
  makes false.
- [ ] **Rename the Dart identifiers for the mark.**
  Footprint: `CycleMarkTypes.firstHigherMeasurement` →
  `temperatureRise` (`lib/domain/marks.dart`),
  `MarkTypes.firstHigherMeasurement` → `temperatureRise`
  (`lib/db/tables.dart`), `CycleEvaluation.firstHigherDay` → `riseDay`,
  the mark chip's widget key `cycleSheetChip-firstHigherMeasurement`
  together with the test keys that mirror it, and the mark fixture in
  `tool/pdf_smoke.dart`;
  `test/db/cycle_database_test.dart` pins `CycleMarkTypes` and
  `MarkTypes` in sync.
  Unchanged: `CycleFact.firstHigherDay`, `firstCircledCandidateDay` and
  `earliestFirstHigherCycleDay` keep their names — they mean the circled
  measurement and are correct.

### Deferred for later
