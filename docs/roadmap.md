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

- [ ] CI green on GitHub (`flutter analyze` + `flutter test` +
      `flutter build web`)

## Phase 2 — data layer & real screens (WP2.x)

- [x] **WP2.2 / WP2.2.1** — `openCycleDatabase()` wired: native = lazy
      background-isolate file DB, web = drift wasm (`web/sqlite3.wasm` +
      `web/drift_worker.js` vendored); wrapped as the Riverpod
      `databaseProvider` behind the splash gate
- [x] **WP2.2 (web)** — wasm + worker assets vendored from the drift 2.35.0
      release; run note updated in [CONTRIBUTING.md](../CONTRIBUTING.md) §3
- [x] **WP2.2.2** — language switcher (de/en) in settings; in-memory only
      (resets to German on reload — documented limitation)
- [x] **WP2.2.3** — JSON export/import in settings: copy-text path on all
      platforms, browser download + file input on web, home-directory file
      on desktop; merge policy (profile, date) = overwrite with counts
- [x] **WP2.2.4** — real Tagebuch entry form (full field set incl. the
      NFP mucus mapping table, marked as a review-pending assumption)
- [x] **WP2.2.5** — Tagebuch entries list grouped by cycle: live entry
      stream → domain cycle grouping, newest cycle first; per-day tiles
      carry bleeding/exclusion/BBT/NFP/notes and load the day back into
      the entry form on tap
- [x] **WP2.2.6** — Zyklus temperature curve (fl_chart) + bleeding/mucus
      symbol row; tapping a day opens the entry form on that date
- [x] **WP2.2.7** — real Statistik screens — **arithmetic only**, no
      interpretive or status conclusions (flagged for INER expert review,
      ADR-001)

Manual acceptance for each Phase-2 screen (once wired): data survives a page
reload (persistence), language switch reflects immediately, export/import
round-trips, Statistik shows arithmetic only.

## Backlog — issues & improvements

Collector for real issues and improvement ideas that are not (yet) part of a
milestone or the internal plan. Readiness convention: **a plain bullet means
needs discussion** — not startable, the line states what must be resolved
first; **an unchecked checkbox means ready to be implemented** — an agent may
pick it up. When an item is done, it is **removed** from here, not ticked —
the sections above track planned work, git history keeps the record (see
[`AGENTS.md`](../AGENTS.md)).

### Bugs

- [ ] Temperature curve only connects measurements on *consecutive* days:
      when a day without a measurement lies between two measured days, the
      line breaks. It should connect across the gap.

### Necessary

- [ ] Language default: system language when available, otherwise English;
      the settings offer switching between "system" and the individual
      languages (de/en) — see
      [ADR-0007](adr/0007-language-policy.md).
- [ ] Rename all German-named code files to English identifiers — at the
      time of writing: `lib/ui/{einstellungen,zyklus,statistik,tagebuch}.dart`
      → `{settings,cycle,statistics,diary}.dart`, plus any German-named
      files that appear meanwhile; mechanical, no behavior change. Policy:
      [ADR-0007](adr/0007-language-policy.md).
- [ ] Missing translation term falls back to **English** (non-Germans likely
      know English, but not German) instead of German.
- [ ] Analysis marks storage & UI: place evaluation marks (cervix peak etc.); the "first
      higher measurement" adds the baseline automatically, based on the preceding measurements
      User can add marks on the cycle tab: for cervix peak (Schleimhöhepunkt), a circle, and higher temperature: circle around temperature measurement (if after cervix peak) or arrow up if before. Selecting a temperature rise should number the previous six days and draw the baseline according to the cheat sheet rules
- Data entry aligned with the NER scheme: different bleeding levels, time
  of day for sex (morning/midday/evening), … — the exact term list must be
  specified first.
- Building the actual app (as captured: "building an app" — scope to be
  clarified: release/packaging vs. remaining placeholder screens).
- [ ] Time of temperature measurement (can be prefilled with current time)
- Datenbankschema überarbeiten (manche Dinge pro Zyklus nicht pro Tag speichern? )
- exclude (Temperatur, Blutung) als negative Zahl?
- set markings (temperature rising etc.) on the cycle tab
- [ ] Muttermund Beobachtung ermöglichen mit verschiedenen Positionen auf Chart anzeigen
- Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md)
- pdf export for consultants (one cycle per sheet?)

### Convenience

- [ ] Dark mode, following the device setting.
- Password protection for the database — first revisit
      [ADR-005](adr/0005-storage-and-encryption.md) (encryption stub) and
      pin down the storage decision; implementation then follows it.
- Import from drip
- [ ] Wochenende farblich hervorheben
- exclude unabhängig von krank etc machen
- Fahrenheit unterstützen: Wie Daten speichern?
- Messmethode speichern (rektal...)? einmal nur (am Anfang) oder als Event (wenn man ändert)?