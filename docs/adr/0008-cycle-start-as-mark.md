# ADR-0008: Cycle start is a user-owned mark; bleeding only suggests

- **Date:** 2026-09-18
- **Status:** Accepted

> **Author's note (2026-09-18, post-schema-v9):** the record below was
> written against the multi-profile database (ADR-0008's single-user
> posture had not yet been revisited). The schema v9 work removed the
> profiles machinery completely — there is one tracked-day table with no
> profile dimension, marks are unique per (entry_date, mark_type), and
> grouping is day-keyed. Wherever this record says "for that profile" /
> "per profile", read it as history: the current code has no profile
> argument anywhere. The DECISION itself (cycle start is a user-owned
> mark; bleeding only suggests; the suggestion predicate gates prompts
> and derivations but never creates boundaries) is unchanged and stays
> accepted. Two mechanics also moved with v9: the analysis exclusion is
> the `excludedFromAnalysis` MARK (the old exclude_* raw flags are gone —
> the raw disturbance mask is rendering input only, see
> lib/domain/models.dart), so open question (a)'s "exclusion flags never
> block it" now reads "the exclusion mark never blocks it" (unchanged
> behavior); and `isSuggestedCycleStart` takes the excluded-state as an
> explicit parameter (the entries stay raw-data-only), which is what
> (b)'s "non-excluded day" means today.

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
that had not been reviewed by INER experts.

## Decision

**Cycle start is a user-owned mark (`cycleStart`, evaluation layer);
bleeding only suggests it.**

- The boundary rule is **mark-driven**: a new cycle group opens at the first
  tracked day on/after a `cycleStart` mark for that profile. Marks of other
  types never create boundaries. *(Author's note, schema v9: profile-free —
  a cycleStart mark keys to a day; no profile argument exists.)* A mark no
  later than the current group's start is a no-op. A mark placed on an
  untracked gap day opens the group at the next tracked entry. The leading
  group — entries predating the first mark — keeps
  `startsAtMenstruation == false` (its begin is unknown; the app shows only
  its end).
- The mark is **authoritative wherever placed**: it binds on days without
  bleeding and on excluded/interrupted days alike (owner decision — see the
  open questions below).
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
  one tracked day falls on/after it), which includes marks placed on days
  without menstruation bleeding and marks whose previous-day subtleties the
  old rule would have suppressed.

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

### Open questions for INER experts (`TODO(user-review)`)

(a) **Mark-on-excluded-day interplay:** should a `cycleStart` mark on an
excluded/interrupted day ever be rejected or reworded? Current behavior: no
— the mark is authoritative wherever placed (owner decision); exclusion
flags never block it.

(b) **Suggestion predicate's mid-flow suppression:** the predicate does not
suggest on a day whose previous non-excluded calendar day is also bleeding
level >= 2. Keep this as-is, or should the suppression stem from bleeding
continuity instead of the strict previous-day rule?

(c) **Wording of the prompt rows:** the committed dialog wording (title,
body, confirm, dismiss — en/de above) is a first draft; iterate it here,
not in code comments.
