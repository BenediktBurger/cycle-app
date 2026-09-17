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

## Backlog — issues & improvements

Collector for real issues and improvement ideas that are not (yet) part of a
milestone or the internal plan. Readiness convention: **a plain bullet means
needs discussion** — not startable, the line states what must be resolved
first; **an unchecked checkbox means ready to be implemented** — an agent may
pick it up. When an item is done, it is **removed** from here, not ticked —
the sections above track planned work, git history keeps the record (see
[`AGENTS.md`](../AGENTS.md)).

### Bugs

### Necessary

- Data entry aligned with the NER scheme: time of day for sex
  (morning/midday/evening), … — the exact term list must be specified first.
  - show sex as an X (and distinguish morning/midday/evening)
  - generic exclude temperature and a note, or keep these different reasons
  - [ ] add "Ausfluss" (A) as an option to mucus
- Building the actual app (as captured: "building an app" — scope to be
  clarified: release/packaging vs. remaining placeholder screens).
- mark "exclude" (Temperatur, Blutung) als negative Zahl?
- Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md))
- pdf export for consultants (one cycle per sheet?)
- [ ] show temperature measurement time, sex, and pain (M, B) on cycle tab
- bleeding should not always start a new cycle. Either choose to ignore bleeding (opt out) or active choice to start a new cycle (maybe suggested at the first bleeding: do you want to start?)

### Convenience

- Password protection for the database — first revisit
      [ADR-005](adr/0005-storage-and-encryption.md) (encryption stub) and
      pin down the storage decision; implementation then follows it.
- [ ] on diary: add buttons for previous/next day
- [ ] make mode selectable: light mode, dark mode, system setting
- [ ] add vertical lines to separate days
- exclude unabhängig von krank etc machen
- Fahrenheit unterstützen: Wie Daten speichern?
- Messmethode speichern (rektal...)? einmal nur (am Anfang) oder als Event (wenn man ändert)? In the "marks" table – but it is raw data (but not per day).
- [ ] adjust variable names in internationalization to English (if applicable and advisable), make it coherent with the tab name
- add descriptions (texts TBD) and tooltips
- export as password protected zip
- improve json export (currently quite verbose), better Csv or similar for the days?

- Indicate the fourth day after mucus peak without temperature rising with arrow down (↓) - DOMAIN
