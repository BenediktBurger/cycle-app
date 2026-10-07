# Importing drip CSV exports

The settings screen can import a **CSV export of the drip cycle tracker**
(a sibling project). Paste the CSV anywhere (a file picker is offered on
the web).

## What is mapped

Per day, drip's bleeding (heaviness carries over level by level, spotting
to heavy), temperature, mucus (including the `S+` → slippery egg-white
decode), desire, sex, pain, mood, cervix words, and notes are mapped into
the NFP diary.

## Merge policy

Rows merge into the **main profile** with the same overwrite-by-date policy
as the JSON import: an imported row overwrites that day's existing entry.
Re-importing the same export therefore adds no duplicates.

## What is lost

- Mucus texture nuances: the decode works on drip's combined NFP number, so
  any NFP 4 — including one drip derived from a slippery feeling — imports
  as S with egg-white quality (≙ S+), whereas a slippery feeling recorded
  without a texture imports no mucus at all (mirroring drip; the creamy
  nuance is likewise lost).
- The exclude flags of mucus, cervix, and bleeding are not stored as their
  own flags: a mucus or cervix exclusion folds into that family's
  `[mucus]`/`[cervix]` note line as an `excluded` token, a bleeding
  exclusion into its own `[bleedingExclude]` note line when a bleeding
  value rides under the flag — without a value, the exclusion only makes
  the day count as skipped in the cycle-start replay. Only the
  temperature exclusion becomes a real mark.

## Note lines

Whatever a structured entry column cannot carry rides into the day note as
a `[tag]`-prefixed line after the day's own note, in this fixed order:
`[temp]`, `[bleedingExclude]`, `[mucus]`, `[cervix]`, `[desire]`, `[pain]`,
`[sex]`, `[mood]`. Symptom note text is appended this way — not lost.

## Open expert-review questions

Two mapping decisions are awaiting NFP expert (INER) review; the decision
points carry `TODO(user-review)` markers in the code
(`lib/domain/models.dart`, `lib/domain/drip_import.dart`):

- The `period` bleeding entry means "menstruation, heaviness unknown";
  it degrades to `medium` (3), the central menstruation level. INER experts
  may prefer a different default.
- Out-of-range cervix values are handled asymmetrically: an out-of-range
  position or opening leaves no stored observation (its raw cell rides
  into the `[cervix]` note line), while an out-of-range firmness clamps to
  the nearest valid value and leaves a `firmness <i> → soft` trace in the
  note line. Whether that asymmetry is acceptable is the open question.
