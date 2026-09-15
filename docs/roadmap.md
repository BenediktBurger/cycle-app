# Roadmap

**Open work only** — this is a to-do list, not a diary. What has landed is
git history; *why* it landed that way is in
[\`docs/adr/\`](adr/README.md). When an item is done, its checkbox gets
ticked only until it is folded into the next release note/commit — unchecked
items are the queue.

Numbering (`WP1.x`, `WP2.x`) mirrors the internal plan file, which is
ephemeral and not versioned — this roadmap is therefore the only durable
record of those IDs. They appear here and nowhere else: not in code
comments, prose docs, or tool names (see [`AGENTS.md`](../AGENTS.md)).

## Milestone 1 — Phase 1 (app shell)

- [ ] `flutter test` passes in a normal terminal (compile-clean already
      verified; runtime hasn't been observed yet — see
      [`dev-notes.md`](dev-notes.md) for the sandbox caveat)
- [ ] CI green on GitHub (`flutter analyze` + `flutter test` +
      `flutter build web`)
- [ ] `flutter run -d chrome` manual smoke test: app shell opens with tabs
      **Tagebuch / Zyklus / Statistik / Einstellungen** in German

## Phase 2 — data layer & real screens (WP2.x)

- [ ] **WP2.2 / WP2.2.1** — wire `openCycleDatabase()`: platform executors
      (lazy native file / web wasm) now exist only as a stub
      (`lib/db/cycle_database.dart`); schema, DAOs and mappers (WP2.1) are in
      the tree
- [ ] **WP2.2 (web)** — bundle `sqlite3.wasm` + drift worker assets so the
      app runs with a database on web; update the run note in
      [CONTRIBUTING.md](../CONTRIBUTING.md) §3 when this lands
- [ ] **WP2.2.2** — language switcher in the settings screen (German-first
      localization is in place, switching itself is not wired)
- [ ] **WP2.2.3** — JSON export → modify → import round-trip
- [ ] **WP2.2.4** — real Tagebuch entry form (replaces the placeholder
      screen)
- [ ] **WP2.2.5** — *(not derivable from the repo; from the plan file — owner
      to slot in)*
- [ ] **WP2.2.6** — Zyklus temperature curve with `fl_chart`
- [ ] **WP2.2.7** — real Statistik screens — **arithmetic only**, no
      interpretive or status conclusions (flagged for INER expert review,
      ADR-001)

Manual acceptance for each Phase-2 screen (once wired): data survives a page
reload (persistence), language switch reflects immediately, export/import
round-trips, Statistik shows arithmetic only.

## Later milestones (not yet broken down)

- [ ] Rename all German-named code files to English identifiers — at the
      time of writing: `lib/ui/{einstellungen,zyklus,statistik,tagebuch}.dart`
      → `{settings,cycle,statistics,diary}.dart`, plus any German-named
      files that appear meanwhile; mechanical, no behavior change. Policy:
      [ADR-0007](adr/0007-language-policy.md).

Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md)
stubs), the pin-lock stub, PDF export, and whatever follows WP2.2 — to be
slotted in as the plan file solidifies.
