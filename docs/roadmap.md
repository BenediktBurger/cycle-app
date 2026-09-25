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

#### Stability (audit 2026-09-25)

- [ ] Marks-stream errors are silently masked everywhere: every screen reads
  `ref.watch(marksProvider).valueOrNull ?? const []` (lib/ui/cycle.dart,
  lib/ui/diary.dart, lib/ui/statistics.dart, lib/ui/cycle_mark_sheet.dart), so a
  session-long marks error renders wrong evaluations (missing marks, wrong SUZ
  states) with no error surface and no retry. Render the error branch like the
  entries streams do.
- [ ] Entries-stream error branches (same three screens) show a static "load
  failed" text with no retry affordance — recovery relies on the next write
  re-emitting. Add a retry (ref.invalidate of dailyEntriesProvider).
- [ ] The `bleeding` column has no CHECK constraint (lib/db/tables.dart, unlike
  `temp_disturbances`/`sex_timings`) while its converter throws on out-of-range
  values at READ time (lib/db/converters.dart): one corrupt row turns every data
  stream into a permanent app-wide "load failed". Add the CHECK via a schema
  migration; whether the read side should additionally degrade corrupt values
  gracefully (instead of the deliberate fail-loud conversion) needs a decision —
  see the packages section.
- [ ] Unbounded cycle-span materialization can hang the app: the span rule
  extends the last cycle to "today" at every grouping call and the diary list is
  a non-lazy widget list over all those days (`lib/ui/diary.dart`), so one
  accidental cycle-start mark dated far in the past (the date picker reaches year
  2000) materializes thousands of synthetic days per build. Cap the
  materialized/day-built range (grouping semantics stay; the cap needs defining)
  and build the diary list lazily.
- [ ] Statistics recomputes the full grouping about five times per state change
  (cycle lengths, onsets, evaluation, statistics, mark-driven count each call
  into grouping/evaluation; lib/ui/statistics.dart + lib/domain/statistics.dart)
  — also while the tab is offstage in the IndexedStack — and
  `domain/statistics.dart` `cycleFacts` carries a build-path
  StateError("cycle/evaluation count mismatch") that degrades to a grey screen if
  it ever trips. Memoize the derived values and replace the invariant throw with
  degradation.

#### Android

- Verify the entry-form date row on a real device and at large system
  font scales — under widget-test fallback metrics it now lays out
  overflow-free at every pumped width (down to 320 dp), but those are not
  device fonts or font scales.
- Confirm on device that the `_dependents.isEmpty` framework assertion no
  longer occurs: the underlying import-dialog dismissal race is fixed and
  guarded by widget tests, but the literal assertion text could not be
  byte-reproduced under test conditions.

### Necessary

#### Security & privacy hardening (audit 2026-09-25)

- [ ] Android backup rules: no `allowBackup`/`dataExtractionRules`/
  `fullBackupContent` exists anywhere under android/, so Auto Backup and
  device-to-device migration carry the encrypted database AND the
  flutter_secure_storage preference file — and same-platform D2D can carry the
  keystore-wrapped key along, contradicting ADR-005's device-bound key. Add
  explicit rules excluding the database file and the secure-storage preferences
  (the JSON export stays the sanctioned user backup).
- [ ] Screen capture is not blocked: no FLAG_SECURE anywhere (Android) — diary
  text, curve and the full-screen JSON export are visible in screenshots,
  recordings and the recents thumbnail. Set FLAG_SECURE while the app is
  foregrounded.
- [ ] Shared exports stay in the temp directory forever: `shareFile` and
  `shareFileBytes` (lib/ui/file_transfer_io.dart) stage the plaintext JSON
  export / PDF under the platform temp dir and never delete the file after the
  share sheet resolves. Delete after hand-off (or sweep on start).
- [ ] Release builds silently fall back to the DEBUG signing key when
  `key.properties` is absent (android/app/build.gradle.kts, release block): the
  fallback makes a debug-signed release artifact ship-able by mistake. Fail the
  release build instead of falling back (document the provisioning requirement).

#### Import & backup safety

- [ ] Import overwrite safety: the documented "overwrite" merge policy silently
  replaces same-day local data, with no preview and no snapshot — a bad or older
  document destroys current-day values irrecoverably. Wire the already-existing
  preview (`planDatabaseImport`, lib/db/export_adapter.dart — currently "not
  wired into the UI yet") into the import dialog ("N days will be overwritten")
  and/or write an auto-export snapshot before applying.

#### Refactors (decided 2026-09-25, startable)

- [ ] Screen split, settings side: turn lib/ui/settings.dart (~1.9k lines) into
  real per-feature-card libraries under `lib/ui/settings/` (locale, theme,
  temperature range, paper-history, PDF export, export/import, data wipe — the
  seams already exist as card widgets). Sequencing: AFTER the WP-A packages
  (A1 and A5 both touch settings.dart) — behavior-changing fixes first,
  behavior-preserving movement second, one branch so the diff verifies as
  near-pure moves. As decided, cycle_pdf.dart stays OUT of scope (its cohesive
  parts — pdf_curve/symbols/axis/layout — are already separate files; the
  remainder is a single-document orchestrator) and lib/ui/cycle.dart is split
  with part files first, not libraries (S2 below).
- [ ] Screen split, cycle side: split lib/ui/cycle.dart (~2.4k lines) into
  `part`/`part of` files ONLY (zero import/API churn; the chart's internals —
  scroll controller, day mapping, jump registration, panel interaction — are
  too entangled for real libraries pre-WP-A3). Sequencing: after A1–A3 land,
  with the option to promote the parts to libraries later once A3's
  memoization/span-cap has thinned what they share.

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

### Work packages — audit 2026-09-25

Packages for the audit findings above (stability, security, architecture —
including the decided refactor rows). The `WP-A`/`WP-S` families are
defined HERE in this file. Each package is self-contained and meant for one
agent in one worktree/branch. Agents still pick work only from the checkbox
rows themselves; a package merely bounds the scope. When a package lands,
its rows go (per the backlog convention) and the package entry is removed.

Parallelization rules: A4 is file-disjoint from everything else and can
run anytime in parallel. The refactor packages come after their
serialization points described in their entries below. Remaining rules
of thumb:

- lib/ui/statistics.dart / lib/ui/cycle.dart are shared by A2 (error
  branches) and A3 (recompute + span) — land A3 after A2.
- Every package: fresh worktree, `flutter pub get`, full gate per
  CONTRIBUTING (analyze, format check, `flutter test --no-pub -r expanded`).

- **WP-A2 — stream & schema resiliency** (bugs: marks masking, entries retry,
  bleeding CHECK rows)
  Scope: error branches for the marks stream on all four screens +
  `valueOrNull`-unmasking, retry affordances (`ref.invalidate`) for both
  streams, `bleeding` CHECK constraint via a drift schema migration
  (lib/db/tables.dart + cycle_database.dart migration + generated code via
  build_runner) and a test seeding an out-of-range row directly through the
  raw sqlite3 binding. Gated decision (ask the owner first): whether the read
  side should degrade a corrupt value gracefully or keep the deliberate
  fail-loud converter — the CHECK constraint makes the degradation
  less necessary either way.

- **WP-A3 — span & rendering cost** (bugs: unbounded span, statistics recompute
  rows)
  Scope: lib/domain/cycle_grouping.dart (bound the materialized span; define
  the cap with the owner if the obvious one — e.g. a bounded-lookback plus an
  explicit "cycle starts very far in the past" state — changes display
  semantics), lazy diary list building in lib/ui/diary.dart, memoized
  statistics derivation in lib/ui/statistics.dart +
  lib/domain/statistics.dart (single grouping/evaluation pass, degrading
  `cycleFacts` instead of throwing). Tests: test/statistics_screen_test.dart,
  test/cycle_chart_test.dart, test/cycle_ordinal_test.dart.

- **WP-A4 — native/privacy hardening** (Necessary: backup rules, FLAG_SECURE,
  temp deletion, signing gate)
  Scope: android/app/src/main/AndroidManifest.xml + new backup-rule XMLs,
  android/.../MainActivity.kt (FLAG_SECURE), lib/ui/file_transfer_io.dart
  (delete staged files after share), android/app/build.gradle.kts (release
  signing gate). File-disjoint from A1–A3 — safe to run in parallel with
  anything. Tests: test/export_share_test.dart; device behavior can only be
  smoke-verified, state so in the commit.

- **WP-A5 — import safety** (Necessary: import overwrite safety row)
  Scope: lib/ui/settings.dart import dialog (wire the plan-based preview into
  the confirm dialog) and optionally an auto-snapshot export before applying
  (decision: snapshot always vs preview only — quick owner question). Merge
  AFTER A1 (both touch lib/ui/settings.dart). Tests:
  test/import_dialog_test.dart, test/export_share_test.dart.

- **WP-S1 — settings screen split into libraries** (Refactors: settings row,
  decided 2026-09-25)
  Scope: lib/ui/settings.dart → `lib/ui/settings/` real per-card libraries,
  the settings.dart file becomes a thin shell reassembling the cards; behavior
  must not change beyond the mechanical import moves. Merge AFTER A1 AND A5
  (both touch lib/ui/settings.dart) — last of the settings touchers. Tests:
  test/settings_layout_test.dart, test/settings_*.dart,
  test/theme_mode_setting_test.dart, test/temperature_range_setting_test.dart
  (expect mechanical import tweaks only).

- **WP-S2 — cycle screen part split** (Refactors: cycle row, decided
  2026-09-25)
  Scope: lib/ui/cycle.dart → `part`/`part of` files (chart, marks/panel,
  day mapping), no import/API changes, no logic movement — the diff should
  verify as near-pure relocation. Merge AFTER A1–A3 have landed (A1's
  `_jumpToDate` fix and A2's error branches move into the parts as-is;
  A3 may thin the chart's shared internals first, changing where the natural
  part boundaries sit). Promotion of the parts to real libraries is a later
  call, NOT part of this package. Tests: test/cycle_*.dart suites,
  test/cycle_tab_roundtrip_test.dart.
