# ADR-0008: Cycle start is a user-owned mark; bleeding only suggests

- **Date:** 2026-09-18
- **Status:** Accepted

> **Author's note (2026-09-24, drip import):** the shared suggestion
> predicate `isSuggestedCycleStart` is REMOVED — its last production
> caller was the foreign-import derivation, and the new rules below
> contradict the level >= 2 gate it pinned. The derivation now uses a
> drip-local replay rule. The journal side had already lost its
> bleeding-driven suggestion with the entry-form switch (see the note
> below from the same day), so nothing on the diary side changes.
> Owner decisions of 2026-09-24:
>
> - **Any bleeding level:** every stored bleeding level (drip values
>   0–3) both OPENS a row of bleedings — the row's first day derives a
>   `cycleStart` mark, author `import` — and CONTINUES it: a previous
>   calendar-day bleeding at any level suppresses the mark. Spotting
>   is full-coverage bleeding.
> - **`bleeding.exclude` = replay-skip only:** an excluded bleeding
>   day cannot open, continue, or suppress — the next non-excluded
>   bleeding day is a fresh onset. The stored entry keeps its
>   bleeding level unchanged, and an excluded bleeding day derives NO
>   `ignoreTemperature` mark (that mark is temperature-only).
> - **`temperature.exclude` semantics unchanged:** it still derives
>   the `ignoreTemperature` mark exactly as before and never affects
>   the cycleStart replay.
>
> This supersedes the level >= 2 predicate wording still quoted in the
> Decision bullets, in the dated notes below and in settled question
> (b) — they are history now, pointing at the drip-local rule where
> they describe current behavior — and it supersedes this record's
> statement that the predicate "keeps its exact logic": the predicate
> and its characterization tests are gone with it.
>
> **Author's note (2026-09-24):** the diary's "asks on suggested saves"
> prompt (the Decision bullet below) is superseded by an explicit
> cycle-start switch on the diary entry form — it writes/removes the same
> user-authored `cycleStart` mark, seeded from the day's existing mark, in
> both directions. Bleeding no longer triggers any diary-side ask: a
> menstruation-level save without the switch touched places no mark and
> shows no dialog. The suggestion predicate `isSuggestedCycleStart`
> (as of this note) retained its exact logic, with the foreign-import
> derivation as its remaining role (drip CSV import; cycle-app's own
> exports already carry the marks) — the newer 2026-09-24 drip note
> above has since removed the predicate and moved that derivation to
> a drip-local rule. Open question (c)'s dialog wording is thereby moot in the
> diary: the switch's label reuses the shared "Cycle start" /
> "Zyklusbeginn" string already on the day sheet's mark chip and the
> statistics table — its wording review follows that surface now.
>
> **Author's note (2026-09-23):** the cycle's start date is, in all layers,
> the opening `cycleStart` mark's OWN date. A group still opens at the
> first tracked day on/after the mark, but `Cycle.startDate` — and with it
> the onset list, the cycle-length statistics, the evaluation windows and
> the UI labels — anchors on the mark date itself. Among multiple marks
> on/before a group's first tracked day the NEWEST one supersedes the
> older ones (the re-marking rule). A mark placed on an untracked gap day
> therefore yields a start inside the gap: the untracked gap days belong
> to the new cycle (they are not in `Cycle.days`), and the calculated
> cycle length equals the visible distance between the two marks. The
> leading group (entries predating the first mark) keeps its first tracked
> day as its start.

> **Author's note (2026-09-18, post-schema-v9 and Phase 3):** the record
> below was written against the multi-profile database (this ADR's
> single-user posture had not yet been revisited). Two later rounds of
> work moved mechanics without touching the DECISION — the decision
> itself (cycle start is a user-owned mark; bleeding only suggests; the
> suggestion predicate gates prompts and derivations but never creates
> boundaries) is unchanged and stays ACCEPTED.
>
> Schema v9 removed the profiles machinery completely — one tracked-day
> table with no profile dimension, marks unique per (entry_date,
> mark_type), grouping day-keyed. Wherever this record says "for that
> profile" / "per profile", read it as history: the current code has no
> profile argument anywhere.
>
> The temperature-ignore mark is now named `ignoreTemperature`
> (owner decision 2026-09-18; formerly sketched as an "analysis
> exclusion" mark) and is temperature-evaluation-scoped only: the
> evaluation arithmetic (lib/domain/evaluation.dart) treats a marked day
> like an unmeasured one in the six-low window, the candidate gap walk
> and the rise-consistency check. The old exclude_* raw flags are gone;
> since owner decision 2026-09-19 the `ignoreTemperature` mark is
> ALSO the temperature curve's rendering input — marked days render
> lighter, and the raw disturbance mask survives only as the Tagebuch
> list's interrupted-day badge input (lib/domain/models.dart) — so open
> question (a)'s "exclusion flags never block it" now reads "the
> temperature-ignore mark never blocks it" (unchanged behavior).
> `isSuggestedCycleStart(entry, previous)` no longer takes an
> excluded-state parameter: the suppression is keyed PURELY to bleeding
> continuity (a day whose previous calendar day also bleeds at level >= 2
> is mid-flow), which is what (b)'s "non-excluded day" means today — a
> marked bleeding day still suggests.

## Context

Until now, cycle boundaries were decided by an automatic rule in the domain
layer: a new cycle started at the first day with menstruation-level bleeding
(bleeding level >= 2) that followed a bleeding-free day — the "first
non-spotting period day starts a cycle" consequence of
[ADR-0001](0001-iner-mode-m-hypothesis.md)'s Mode-M posture. That rule made
the app, not the user, the author of the cycle boundary, and it misfired
whenever the user's view of where a cycle begins differs from the bleeding
pattern (e.g. the user wants the cycle to start on a day without bleeding,
or does not want every first menstruation-level day after a bleeding-free
day to end the previous cycle). The rule also carried unstated assumptions
(suppression of a second bleeding day in a row, silence on excluded days)
that had not been reviewed by INER experts. **Update (2026-09-19, owner
decision confirmed with INER experts):** these assumptions have since been
reviewed and settled — the suppression is bleeding-continuity-based and
previous-calendar-day only (see the Decision), and the excluded-day
silence is moot because day-level exclusion semantics are gone entirely:
the `ignoreTemperature` mark is temperature-evaluation-scoped and does
not affect suggestions at all.

## Decision

**Cycle start is a user-owned mark (`cycleStart`, evaluation layer);
bleeding only suggests it.**

- The boundary rule is **mark-driven**: a new cycle group opens at the first
  tracked day on/after a `cycleStart` mark for that profile. Marks of other
  types never create boundaries. *(Author's note, schema v9: profile-free —
  a cycleStart mark keys to a day; no profile argument exists.)* A mark no
  later than the current group's start is a no-op. The cycle's start date is
  the opening mark's own date — a mark placed on an untracked gap day keeps
  its date as the start (the gap days belong to the new cycle), and among
  multiple marks on/before a group's first tracked day the newest
  supersedes. The leading group — entries predating the first mark — keeps
  `startsAtMenstruation == false` (its begin is unknown; the app shows only
  its end) and anchors on its first tracked day.
- The mark is **authoritative wherever placed**: it binds on days without
  bleeding and on temperature-ignored days alike (owner decision
  2026-09-19, confirmed with INER experts — recorded under Consequences
  below).
- Bleeding only **suggests**: bleeding never decides the boundary by
  itself in the diary. Nothing there derives a mark from bleeding — a
  bleeding save places no mark; the mark comes only from the entry
  form's explicit cycle-start switch (see the 2026-09-24 author's
  note). The suggestion role survives only in the drip import's
  drip-local replay rule (see the 2026-09-24 author's note): any
  bleeding level opens/continues a row of bleedings, and
  `bleeding.exclude` days are skipped by the replay only — the derived
  marks stay provenance-tagged (`author: import`), user-owned marks
  remain the only in-app boundary source.
- The old diary save flow **asked on suggested saves** (superseded by
  the entry-form switch, see the 2026-09-24 author's note — kept for
  the committed wording record, see open question (c)): when a
  menstruation-level save fired the suggestion, a localized confirm
  dialog appeared; confirming wrote the mark (author `user`),
  dismissing stored nothing. Committed wording (implementer-inventable
  per language; see open question (c)):
  - en: title "Start new cycle?", body "The bleeding on this day suggests
    that a new cycle begins here. Set a cycle start mark on this day?",
    confirm "Set cycle start", dismiss "Not now".
  - de (German-first per [ADR-0007](0007-language-policy.md)): "Neuen Zyklus
    beginnen?" / "Die Blutung an diesem Tag deutet darauf hin, dass hier ein
    neuer Zyklus beginnt. Soll an diesem Tag eine Zyklusbeginn-Markierung
    gesetzt werden?" / "Zyklusbeginn setzen" / "Nicht jetzt".
- The mark is **settable/removable on the cycle chart** (mark-sheet toggle,
  author `user`) — so it can be placed or corrected independently of any
  bleeding day.
- **Foreign imports (drip) derive marks**: the importer replays the mapped
  entry rows through the drip-local onset rule (any bleeding level opens
  or continues a row of bleedings; `bleeding.exclude` days are skipped by
  the replay only — they cannot open, continue or suppress, they still
  store their bleeding level, and they derive no `ignoreTemperature`
  mark; see the 2026-09-24 author's note) and writes a
  `cycleStart` mark with author `import` for every onset day — the
  author column records that the mark was derived, not placed. Cycle-app's
  own exports already carry the marks, so a round-trip never re-derives:
  derivation applies only to foreign imports.
- The old automatic onset rule is **superseded**: no automatic boundary
  rule remains. `menstruationOnsetDates` now returns the dates of the
  user-placed cycle starts that open a group (the groups with
  `startsAtMenstruation == true` — a mark yields a group only when at least
  one tracked day falls on/after it) — namely the opening mark's own date,
  which sits on an untracked gap day when users place it there, and which
  includes marks placed on days without menstruation bleeding and marks
  whose previous-day subtleties the old rule would have suppressed.

This continues [ADR-0001](0001-iner-mode-m-hypothesis.md)'s Mode-M posture:
the prompt is a suggestion the user confirms, the mark is user-authored —
the app never decides a boundary on its own.

## Consequences

- `groupIntoCycles` takes the marks; statistics (`cycleLengthsInDays`,
  `menstruationOnsetDates`) thread the same marks, so cycle lengths are
  measured between the user's marked starts.
- Existing local data is not backfilled (no users yet); before the first
  `cycleStart` mark the app shows only the leading group without a known
  begin.
- The drip-local replay rule is characterization logic (tests pin it),
  so expert review can change the derivation without touching the
  grouping machinery; the removed shared predicate's level >= 2
  characterization is history.
- Exports/imports round-trip `cycleStart` marks unchanged, including the
  author column (`user` vs. `import` provenance is preserved).

**Settled questions (owner decisions 2026-09-19, confirmed with INER
experts — no further expert consultation queued):**

(a) **Mark-on-temperature-ignored-day interplay:** a `cycleStart` mark on
an `ignoreTemperature`-marked (temperature-evaluation-ignored) day is
never rejected or reworded — the cycleStart mark is authoritative
wherever placed, and the temperature-ignore mark never blocks it
(unchanged behavior; the old exclude_* flags are gone, see the author's
note).

(b) **Mid-flow suppression (now the drip replay rule):** the strict
previous-calendar-day bleeding rule survives in the drip-local onset
rule — a bleeding day whose previous CALENDAR day also bleeds (any
level, drip 0–3) derives no mark (bleeding continuity is the ONLY
suppression; no wider continuity notion). Days tagged
`bleeding.exclude` are skipped by the replay entirely: they cannot
suppress, and the next non-excluded bleeding day is a fresh onset.
The `ignoreTemperature` mark and the raw disturbance mask do not
affect the replay (a marked bleeding day still derives).

### Open questions for INER experts (`TODO(user-review)`)

(c) **Wording of the prompt rows:** the committed dialog wording (title,
body, confirm, dismiss — en/de above) is a first draft; iterate it here,
not in code comments. TODO(user-review): pending wording review — this
also feeds the roadmap's period-start label wording follow-up (the
"period start" row label vs. a marked cycle start on a bleeding-free
day).
