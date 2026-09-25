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

#### Android

- The entry-form date row in `lib/ui/diary.dart` overflows at narrow widths
  (about 70–110 px at 320–360 dp under widget-test fallback font metrics; the
  new narrow-viewport tests waive it with a documented justification) —
  verify on a real device and at large system font scales before treating it
  as a real defect and fixing it.
- Confirm on device that the `_dependents.isEmpty` framework assertion no
  longer occurs: the underlying import-dialog dismissal race is fixed and
  guarded by widget tests, but the literal assertion text could not be
  byte-reproduced under test conditions.

### Necessary

#### Building the app (to be clarified with INER)

- create a logo for this app, with some similarity to the iner logo, but enough distinction to be independent
- confirm Apache-2.0 (chosen 2026-09) as the final license before the
  first store submission — release.md Gate G2; sideload APKs are not
  affected.

#### Domain / UI

- how to mark pregnancy and breast-feeding cycles -> they should not enter into statistics of "normal" cycles
- how to mark a pregnancy: replace cycle start with pregnancy start or add a "conception" mark -> calculate probable bith?
  - move edit between date and X in order to save space
  - checkmark overlaps the icon - do we need the checkmark at all?
  - comments should be in one column as well (not spanning the whole sheet)
  - strange distribution: one column with 3, the other one with 2 marks and then on the bottom joined another mark. All marks (and/or comments) should be distributed among columns. Maybe even more columns on wider screen?
- should we add the birth bleeding (Wochenbett, marked as ~)?
- render observations inside temperature chart - see [signal-symbols-inside-temperature-plot](ideas/2026-09-21-signal-symbols-inside-temperature-plot.md)?

- proof read German texts and let translate changes to english

### Convenience

- Password protection for the database — the storage decision is settled
      (native files are now always-on encrypted, ADR-005); what a
      user-facing passphrase would additionally protect, and how it
      interacts with the device-bound key, needs discussion.
- save measurement method + thermometer as changeover marks
      (decided 2026-09-24, sketch only — the ADR is written together with
      the implementation):
  - two mark types placed by one "measurement setup" form on the changeover
    date: `method.rectal|vaginal|oral` (closed vocabulary, in `markType`)
    and `thermometer` with the free-text model name → needs a nullable
    `value TEXT` column on `user_marks` (graceful migration)
  - effective method/thermometer for a day = the latest mark ≤ that day
    (same derive-from-dated-events pattern as cycle start); the choice is
    prompted when the first temperature is entered and written as a mark
    on that date
  - day view shows only the mark chip — no auto-note, notes stay
    user-owned; temperature disturbances stay untouched
  - PDF renders the method in effect at the chart's start date
- export as password protected zip
- add (optional) reminder (e.g. every year) to do a backup of your data

- Indicate the fourth day after mucus peak without temperature rising with arrow down (↓)

- German count strings in the app read "1 Tagebucheinträge" for singular
  counts (gen-l10n plural support would fix all such surfaces at once).
- The privacy-notice text references „Einstellungen › Export" / „Import",
  while the cards are titled „JSON-Export" / „JSON-Import".
- The about-page feedback notice phrasing mixes "an die Issues … oder per
  E-Mail" awkwardly.

### Deferred for later

- more translations (Polish, Italian)
- Fahrenheit — decided: only a UI concern; °C stays the unit of record in
  storage, conversion happens at the display edge (existing seams:
  temperature_range, settings pickers, PDF axis); German decimal comma in
  the PDF is handled separately under Bugs
