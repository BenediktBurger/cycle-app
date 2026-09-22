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

- Cycle-length statistics during a very long mark-driven cycle: during
  pregnancy a cycle runs arbitrarily long (day-of-cycle > 100 on the
  chart) and skews cycle-length statistics — `cycleLengthsInDays`
  (`lib/domain/statistics.dart`) computes lengths as gaps between
  consecutive cycle-start marks, so the next mark after a pregnancy
  yields one length spanning the whole pregnancy. Needs discussion how to
  treat such spans (cap, exclusion, pregnancy marker) — an expert/ADR
  question.
- [ ] PDF Export (at most 1 cycle per page, longer cycles like pregnancy take several), with additional information (like paper form): name ( hideable per export "anonymize"), birth date (hidden by anonymization), count of observed cycles, shortest cycle, earliest first higher temperature. Also write out notes (vertically). For all these additional options offer a settings field to take into consideration either only source (name, birth date) or as information about cycles observed outside this app (e. G. Before stating here). For example cycle count should include previous cycles and cycles stored in the app up to the exported one
- should we add the birth bleeding (Wochenbett, marked as ~)?
- show cycle start mark on journal like temp?
- render observations above temperature chart - see [signal-symbols-inside-temperature-plot](ideas/2026-09-21-signal-symbols-inside-temperature-plot.md)?

- proof read German texts and let translate changes to english

### Convenience

- Password protection for the database — the storage decision is settled
      (native files are now always-on encrypted, ADR-005); what a
      user-facing passphrase would additionally protect, and how it
      interacts with the device-bound key, needs discussion.
- [ ] clean up statistics on the cycle tab -> all statistics on the statistics tab. Relevant: number of cycles (just count), detailed statistics (min,max, std, avg) for cycle length, for bleeding length, and for first higher measurement until end of cycle. Entry for earliest first higher measurement among all cycles (if possible, real first higher measurement, i.e. after mucus peak)
- Fahrenheit unterstützen: Wie Daten speichern?
- Messmethode speichern (rektal...) als Event (wenn man es ändert). In the "marks" table – but it is raw data (but not per day)?.
- export as password protected zip
- drip import: how to handle excluded bleeding values and auto-calculation of new cycles?
- add (optional) reminder (e.g. every year) to do a backup of your data

- Indicate the fourth day after mucus peak without temperature rising with arrow down (↓)
