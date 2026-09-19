# ADR-0001: INER-compatible "Mode M" product shape

- **Date:** 2026-09-15
- **Status:** Accepted (owner decision, 2026-09-19)

## Context

The app is intended as a tool for menstrual-cycle tracking and evaluation per
NER rules (Rötzer) in the INER spirit. In the INER/NFP ecosystem,
software-assisted evaluation can take several shapes with very different
implications for who holds the authority over the evaluation: fully
human ("assisted marking"), human-with-suggestions, or fully automatic.

Three modes are conceivable:

| Mode | Name               | Description                                                                                         |
|------|--------------------|-----------------------------------------------------------------------------------------------------|
| M    | Assisted marking   | The user places every mark; the app computes baseline/counts/lines/stats (it does arithmetic only). |
| S    | Suggest + override | The app suggests marks/phases via a rules engine; the user can override every suggestion.           |
| A    | Automatic          | The app evaluates fully automatically per a rules engine plus a trust concept.                      |

The product's posture ("the user stays the authority; the app is a tool, not
the decision-maker") strongly suggests Mode M as the default product shape.
However, **no INER resolution or expert statement exists that confirms this
tool-role interpretation**. Which modes an INER-compatible app may take — and
whether suggestion/automatic modes are permissible at all under the INER
framework — is unknown to us.

## Decision

**We adopt Mode M (assisted marking) as the product shape** — the default
position, where the human decides fully: the user places all marks themselves
and the app provides only visualization, arithmetic (baseline/coverline from
six prior low measurements, counts, phase lines) and statistics.

This is **accepted by owner decision (2026-09-19), not by INER-expert
resolution**: the app supports the user but never gives the final answer.
It is crucial that the woman / the couple remains in control and takes
conscious decisions — there should be no unwanted pregnancy because
someone trusted this app without knowing what they do. The app may compute
derived values (temperature differences, baseline shifts) and may surface
warnings about arithmetic/record anomalies (e.g. a first higher
measurement placed on a day below the baseline) — that is app behavior,
not interpretation. A fertility verdict is never the app's output: the
user/couple stays the authority. Knowing the method itself (via book or
course) — proper observation of temperature and mucus, and analysis — is
a prerequisite, so that the interpretation of fertility becomes reliable;
the app cannot replace that knowledge. No INER resolution or expert
statement backs this posture; it rests on the owner's judgment alone.

Modes S (suggest + override, rules engine) and A (automatic, rules engine +
trust concept) are **explicitly deferred** — their data models are designed to
remain possible later (marks are stored as user-authored records; nothing in
the schema assumes a specific mode), but no S/A functionality is built.

## Consequences

- The app UI and domain layer only *compute*, never *interpret*: statistics
  show arithmetic only, no status conclusions. Arithmetic and anomaly
  warnings (e.g. a flagged first-higher-measurement below the baseline,
  computed temperature differences) are legitimate compute-only app
  behavior; a fertility verdict is not — the user/couple stays the
  authority.
- Data model (marks, phases) is designed mode-agnostic so S/A remain possible
  later without a rewrite.
- The posture is settled: changing it now requires a new ADR that
  supersedes this one. The posture remains attributable to the owner's
  decision; it has not been reviewed by INER experts.
- Historically, cycle-boundary rules and mapping tables encoded in the
  domain layer (e.g. first non-spotting period day starts a cycle; NFP 0–4
  mucus mapping) inherited review flags from this ADR — they were
  themselves assumptions to validate. Both have since been removed or
  superseded by the Updates below, so **no remaining review flags inherit
  from this ADR**. Open `TODO(user-review)` questions in code and docs are
  separate, narrower interpretation questions (rule wording, rendering
  details), not the posture itself.

  **Update (2026-09-16):** the "NFP 0–4 mucus mapping" assumption listed above
  has been removed — mucus is no longer stored or shown as a 0–4 number, but
  is displayed with the fertility-sign vocabulary from the cheat sheet
  (`t / Ø / f / S`, with quality superscripts — Ø and the superscripts are
  display glyphs) and stored as stable ASCII enum tokens in TEXT columns.
  The review flag no longer applies to it; the Mode-M compute-never-interpret
  posture is unchanged and still applies.

  **Update (2026-09-18):** the "first non-spotting period day starts a
  cycle" consequence is superseded by
  [ADR-0008](0008-cycle-start-as-mark.md) — the cycle start is now a
  user-owned `cycleStart` mark; bleeding only suggests it (the diary prompt
  is a suggestion the user confirms) and never creates a boundary by itself.
  The Mode-M posture is unchanged: the mark is user-authored, and the
  app still computes only (foreign drip imports derive marks with author
  `import`, recording derivation rather than placement).
