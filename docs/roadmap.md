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

#### Building the app

- Building the actual app — release/packaging scope has been resolved into a
  runbook: see [`docs/release.md`](release.md) and
  [ADR-0009](adr/0009-release-pipeline-and-signing.md); the ready items are
  below, the blocked ones are plain bullets.
- [ ] Android toolchain: JDK 21 + Android command-line-tools SDK on the dev
  machine, `flutter doctor` green, release APK builds (release.md Phase A)
- [ ] Create the release keystore outside the repo, wire gitignored
  `key.properties` + signing config, verify with `apksigner` (release.md
  Phase C)
- [ ] Adaptive launcher icon replacing the default template mipmaps
  (release.md Phase B)
- Application identity rename: final `applicationId`/domain (owner + INER
  decision, release.md Gate G1) and the license choice for F-Droid (Gate G2) block
  all store submissions; sideload APKs are not blocked.
- [ ] Sideload APK + device upgrade test (old release with data → install
  new release → migrations preserve cycle data) as repeatable discipline
  (release.md Phase D, per-release checklist)
- [ ] create a logo for this app, with some similarity to the iner logo, but enough distinction to be independent
- [ ] change appId to io.github.benediktburger.cycleapp
- [ ] check whether dependencies are up to date
- [ ] could CI (tooling) catch more errors/improve the quality (also for android)?
- choose and set a license

#### Domain / UI

- [ ] Make the cycle chart more like the paper: first bleeding, then mucus, then temperature. ideas if possible to render entries inside temperature chart, see the image in .opencode/plans, to get closer to paper:
  - render bleeding and mucus inside the temperature chart (at the top of the chart)
  - M below mucus
  - also sex
  - add temperature disturbance reasons here (bottom part of the chart)
  - time of measurement below, can be its own row (not part of the chart)
- [ ] cycle chart: show an indicator if there is a note for a day
- Encryption on native platforms ([ADR-005](adr/0005-storage-and-encryption.md))
- [ ] with many cycles, scrolling the cycle chart becomes sloppy
- [ ] Add a welcome/warning screen for the first start that fertility tracking depends on the faithful observation and interpretation of body signs (temperature, mucus). The guide by Prof. Rötzer or courses (see INER page) teach the necessary skills. For questions don't hesitate to reach out to INER. (this should also to some about page or so, maybe show that about page at the beginning?)
- [ ] add the number of cycle to the cycle page somewhere to the cycle start (add a setting for numbers of observed cycles outside this app)
- [ ] PDF Export (at most 1 cycle per page, longer cycles like pregnancy take several), with additional information (like paper form): name ( hideable per export "anonymize"), birth date (hidden by anonymization), count of observed cycles, shortest cycle, earliest first higher temperature. Also write out notes (vertically). For all these additional options offer a settings field to take into consideration either only source (name, birth date) or as information about cycles observed outside this app (e. G. Before stating here). For example cycle count should include previous cycles and cycles stored in the app up to the exported one
- [ ] prepare Metadata, setup... for local build, fdroid, and for play store
- [ ] cycle: make it possible to click another day without des electing the first one (maybe add a button to close day options)
- [ ] add necessary DSVGO notice
- [ ] add a notice that you should open a Github issue or send a mail for errors (or suggestions) as this app does not send anything ever, even on crash
- [ ] The diary cycle-start prompt re-fires when re-saving a suggested day that
  already carries the cycle start mark (harmless — addMark is idempotent):
  -> suppress the prompt when the mark is already present on the saved day.

- [ ] set adr 1 to accepted adapted to this decision: It is crucial that the woman / the couple remains in control and takes consciens decisions. There should be no unwanted pregnancy because someone trusted this app without knowing what they do. Therefore, the app should support the user but not give the final answer. It is fine if it raises a warning (like setting the first higher measruement to a day which is below the baseline), if it calculates temperature differences etc. Also, it should be clear that you need to know the method (either via book or a course) regarding proper oberservations (temperature and mucus) and analysis such that the interpretation (fertility) becomes reliable.

### Convenience

- Password protection for the database — first revisit
      [ADR-005](adr/0005-storage-and-encryption.md) (encryption stub) and
      pin down the storage decision; implementation then follows it.
- [ ] persist language and mode choices
- [ ] diary tab: reorder entries: everything of temperature (value, time, exclude) together, all mucus together, all cervix together, sex, pain, extra data
- [ ] cycle tab: limit temperature to a range selectable in the settings, default is 36-38 °C
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
