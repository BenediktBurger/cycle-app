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

#### Building the app

- Building the actual app — release/packaging scope has been resolved into a
  runbook: see [`docs/release.md`](release.md) and
  [ADR-0009](adr/0009-release-pipeline-and-signing.md); the ready items are
  below, the blocked ones are plain bullets.
- [ ] Create the release keystore outside the repo, fill the gitignored
  `key.properties` (the gradle signing wiring is already in place),
  verify the signed release APK with `apksigner` (release.md Phase C)
- [ ] Adaptive launcher icon replacing the default template mipmaps
  (release.md Phase B)
- License choice for the app (release.md Gate G2) — the remaining blocker
  for the F-Droid submission; sideload APKs are not blocked. The
  application identity is resolved (`io.github.benediktburger.cycleapp`,
  release.md Gate G1), so this is the last open gate before store
  submissions; needs an owner decision (GPL-3-compatible intent per
  README).
- [ ] Sideload APK + device upgrade test (old release with data → install
  new release → migrations preserve cycle data) as repeatable discipline
  (release.md Phase D, per-release checklist)
- [ ] Release workflow pre-flight: assert the tag name matches the pubspec
  version (`v` + `pubspec.yaml` `version:` without its `+N` build part
  equals `${GITHUB_REF_NAME}`); refuse to build on mismatch. The APK
  embeds the pubspec version regardless of the tag, so a mismatch would
  silently ship a wrong versionName/versionCode (release.md, per-release
  checklist step 5)
- [ ] create a logo for this app, with some similarity to the iner logo, but enough distinction to be independent
- choose and set a license

#### Domain / UI

- [ ] make the journals save button always visible (top bar?) such that you can save wherever you changed something, not only at the bottom
- [ ] remove stale text line "von der Auswertung ausgeschlossen" from the add mark sheet
- [ ] make sure that it works also in horizontal view (especially for the cycle, to see more of the cycle better)
- [ ] diary: make it compacter (temperature and time on the same line?)
- Cycle-length statistics during a very long mark-driven cycle: during
  pregnancy a cycle runs arbitrarily long (day-of-cycle > 100 on the
  chart) and skews cycle-length statistics — `cycleLengthsInDays`
  (`lib/domain/statistics.dart`) computes lengths as gaps between
  consecutive cycle-start marks, so the next mark after a pregnancy
  yields one length spanning the whole pregnancy. Needs discussion how to
  treat such spans (cap, exclusion, pregnancy marker) — an expert/ADR
  question.
- Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md))
- [ ] Add a welcome/warning screen for the first start that fertility tracking depends on the faithful observation and interpretation of body signs (temperature, mucus). The guide by Prof. Rötzer or courses (see INER page) teach the necessary skills. For questions don't hesitate to reach out to INER. (this should also to some about page or so, maybe show that about page at the beginning?)
- [ ] add the number of cycle to the cycle page somewhere to the cycle start (add a setting for numbers of observed cycles outside this app)
- [ ] PDF Export (at most 1 cycle per page, longer cycles like pregnancy take several), with additional information (like paper form): name ( hideable per export "anonymize"), birth date (hidden by anonymization), count of observed cycles, shortest cycle, earliest first higher temperature. Also write out notes (vertically). For all these additional options offer a settings field to take into consideration either only source (name, birth date) or as information about cycles observed outside this app (e. G. Before stating here). For example cycle count should include previous cycles and cycles stored in the app up to the exported one
- [ ] cycle: make it possible to click another day without deselecting the first one (maybe add a button to close day options)
- [ ] add necessary DSVGO notice
- [ ] add a notice that you should open a Github issue or send a mail for errors (or suggestions) as this app does not send anything ever, even on crash

### Convenience

- Password protection for the database — first revisit
      [ADR-005](adr/0005-storage-and-encryption.md) (encryption stub) and
      pin down the storage decision; implementation then follows it.
- [ ] clean up statistics on the cycle tab -> all statistics on the statistics tab. Relevant: number of cycles (just count), detailed statistics (min,max, std, avg) for cycle length, for bleeding length, and for first higher measurement until end of cycle. Entry for earliest first higher measurement among all cycles (if possible, real first higher measurement, i.e. after mucus peak)
- Fahrenheit unterstützen: Wie Daten speichern?
- Messmethode speichern (rektal...) als Event (wenn man es ändert). In the "marks" table – but it is raw data (but not per day)?.
- add descriptions (texts TBD) and tooltips, welcome page, links, help, copyright...
- export as password protected zip
- improve json export (currently quite verbose), better Csv or similar for the days?
- [ ] review test suite and clean it up
- drip import: how to handle excluded bleeding values and auto-calculation of new cycles?

- Indicate the fourth day after mucus peak without temperature rising with arrow down (↓)
- The cycle-summary table's "period start" row label still says period
  start, while the marked cycle start may sit on a bleeding-free day —
  wording follow-up; the new label wording should be settled first with the
  ADR-0008 open question (c) expert review (needs expert wording).
