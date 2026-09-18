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

- [ ] time of measurement is not visible on the cycle chart (not enough space?) -> if space constraint is there, write vertically

### Necessary

- Building the actual app (as captured: "building an app" — scope to be
  clarified: release/packaging vs. remaining placeholder screens).
- [ ] Make the cycle chart more like the paper: first bleeding, then mucus, then temperature. ideas if possible to render entries inside temperature chart, see the image in .opencode/plans, to get closer to paper:
  - render bleeding and mucus inside the temperature chart (at the top of the chart)
  - M below mucus
  - also sex
  - add temperature disturbance reasons here (bottom part of the chart)
  - time of measurement below, can be its own row (not part of the chart)
- [ ] cycle chart: show an indicator if there is a note for a day
- [ ] SUZ mark should have a larger arrow
- Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md))
- pdf export for consultants (similar to paper form)
- [ ] with many cycles, scrolling the cycle chart becomes sloppy

### Convenience

- Password protection for the database — first revisit
      [ADR-005](adr/0005-storage-and-encryption.md) (encryption stub) and
      pin down the storage decision; implementation then follows it.
- [ ] the arrow sign for a higher measurement before mucus peak should be **below** the temperature measurement, not above. Its legend should state "vorzeitiger Temperaturanstieg"
- [ ] persist language and mode choices
- [ ] cycle tab, selection: set mucus peak should show a filled circle
- [ ] cycle tab: date selector wastes space (it sits in its own row) should probably be next to info
- [ ] diary tab: reorder entries: everything of temperature (value, time, exclude) together, all mucus together, all cervix together, sex, pain, extra data
- [ ] cycle tab: limit temperature to a range selectable in the settings, default is 36-38 °C
- [ ] clean up statistics on the cycle tab -> all statistics on the statistics tab. Relevant: number of cycles (just count), detailed statistics (min,max, std, avg) for cycle length, for bleeding length, and for first higher measurement until end of cycle. Entry for earliest first higher measurement among all cycles (if possible, real first higher measurement, i.e. after mucus peak)
- Fahrenheit unterstützen: Wie Daten speichern?
- Messmethode speichern (rektal...) als Event (wenn man es ändert). In the "marks" table – but it is raw data (but not per day)?.
- add descriptions (texts TBD) and tooltips, welcome page, links, help, copyright...
- export as password protected zip
- improve json export (currently quite verbose), better Csv or similar for the days?
- review test suite and clean it up
- drip import: how to handle excluded bleeding values and auto-calculation of new cycles?

- Indicate the fourth day after mucus peak without temperature rising with arrow down (↓)
- The cycle-summary table's "period start" row label still says period
  start, while the marked cycle start may sit on a bleeding-free day —
  wording follow-up; the new label wording should be settled first with the
  ADR-0008 open question (c) expert review (needs expert wording).
- The diary cycle-start prompt re-fires when re-saving a suggested day that
  already carries the cycle start mark (harmless — addMark is idempotent):
  needs discussion whether to suppress the prompt when the mark is already
  present on the saved day.
