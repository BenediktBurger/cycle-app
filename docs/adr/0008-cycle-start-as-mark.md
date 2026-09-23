# ADR-0008: Cycle start is a user-owned mark; bleeding only suggests

- **Date:** 2026-09-18
- **Status:** Accepted

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
- Bleeding only **suggests**: `isSuggestedCycleStart(entry, previous)` keeps
  the former automatic predicate verbatim (bleeding level >= 2 on a
  non-excluded day whose previous non-excluded calendar day is not also a
  non-excluded level >= 2 day), but its role is demoted to gating prompts
  and derivations. It never creates a boundary by itself.
- The diary save flow **asks on suggested saves**: when a menstruation-level
  save fires the suggestion, a localized confirm dialog appears; confirming
  writes the mark (author `user`), dismissing stores nothing. Committed
  wording (implementer-inventable per language; see open question (c)):
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
  entry rows through the same suggestion predicate and writes a
  `cycleStart` mark with author `import` for every suggested day — the
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
- The suggestion predicate stays verbatim characterization logic (tests pin
  it), so expert review can change its role without touching its logic.
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

(b) **Suggestion predicate's mid-flow suppression:** keep the strict
previous-calendar-day bleeding rule — a day whose previous CALENDAR day
bleeds at level >= 2 does not suggest (bleeding continuity is the ONLY
suppression; no wider continuity notion). The `ignoreTemperature` mark
and the raw disturbance mask do not affect the predicate (a marked
bleeding day still suggests).

### Open questions for INER experts (`TODO(user-review)`)

(c) **Wording of the prompt rows:** the committed dialog wording (title,
body, confirm, dismiss — en/de above) is a first draft; iterate it here,
not in code comments. TODO(user-review): pending wording review — this
also feeds the roadmap's period-start label wording follow-up (the
"period start" row label vs. a marked cycle start on a bleeding-free
day).
