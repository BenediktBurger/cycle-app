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

- pdf export (at least on web) does not render a temperature graph, does not show mucus signs, does not show any marks... It should be like the cycle tab

#### Android

- [ ] pdf export fails with "Speichern fehlgeschlagen"
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

- [x] add °C to the legend of the temperature plot
- [ ] title bar takes a lot of space in horizontal mode (cycle tab)
- how to mark a pregnancy: replace cycle start with pregnancy start or add a "conception" mark -> calculate probable bith?
- [x] show the cycle start flag and cycle number even for the first cycle (if first day of data is cycle start, the flag is currently not rendered)
- [x] make sure that long running cycles (day-of-cycle > 100, e.g. pregnancy) renders well on chart
- [ ] rework the statistics tab: don't show individual cycles starts / lengths, but possible to show a table (cycle start, number of bleeding, first higher measurement, length) at the bottom after the other statistics
- [x] order legend entries according to their appearance on the cycle tab
- [x] render the baseline on the cycle legend as dashed as it is on the cycle tab
- [x] revisit language entries, can some be consolidated (e.g. cycle legend and cycle row?)?
- [ ] mark sheet (implement all)
  - move edit between date and X in order to save space
  - checkmark overlaps the icon - do we need the checkmark at all?
  - comments should be in one column as well (not spanning the whole sheet)
  - strange distribution: one column with 3, the other one with 2 marks and then on the bottom joined another mark. All marks (and/or comments) should be distributed among columns. Maybe even more columns on wider screen?
- how to mark pregnancy and breast-feeding cycles -> they should not enter into statistics of "normal" cycles
- [ ] PDF Export (at most 1 cycle per page, longer cycles like pregnancy take several), with additional information (like paper form): name ( hideable per export "anonymize"), birth date (hidden by anonymization), count of observed cycles, shortest cycle, earliest first higher temperature. Also write out notes (vertically). For all these additional options offer a settings field to take into consideration either only source (name, birth date) or as information about cycles observed outside this app (e. G. Before stating here). For example cycle count should include previous cycles and cycles stored in the app up to the exported one
- order settings: everything related should be together, e.g pdf related (name, birth date) should be near pdf export. Don't show the datenschutz entry on the settings page
- should we add the birth bleeding (Wochenbett, marked as ~)?
- show cycle start mark on journal like temp?
- render observations inside temperature chart - see [signal-symbols-inside-temperature-plot](ideas/2026-09-21-signal-symbols-inside-temperature-plot.md)?

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

### Nitpicks

Small polish notes — not startable without a decision about whether each is
worth doing at all.

- German count strings in the app read "1 Tagebucheinträge" for singular
  counts (gen-l10n plural support would fix all such surfaces at once).
- The privacy-notice text references „Einstellungen › Export" / „Import",
  while the cards are titled „JSON-Export" / „JSON-Import".
- The about-page feedback notice phrasing mixes "an die Issues … oder per
  E-Mail" awkwardly.
- On a returning app start the onboarding/about gate can flash for one frame
  until settings hydration applies (same single-frame pattern as other
  hydrated settings).
- statistics.dart card builders mix styles (top-level
  _countCard/_lengthsListCard functions vs the _MetricCard class).
- Some test files carry historical section banners from a former cleanup
  pass ("former test/… (bodies concatenated verbatim)") that now only
  document section origin — the wording could mislead a reader into
  thinking dedup is still pending there.
