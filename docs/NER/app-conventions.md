# NER app conventions

This file is **not** part of the NER rule-set. The book rules are summarized
in [rules.md](rules.md), and that summary is the vocabulary this app quotes.
This file records how the app implements and renders those rules. Where the
two conflict, the book wins and the app convention is the bug.

German rule names are quoted from [rules.md](rules.md). The acronym in the
identifiers `SuzRule`, `suzBegins` and `SuzOverlayMark` means the computed
definitely infertile time „sicher unfruchtbare Zeit“; it survives only inside
those English technical names.

## Source discipline

The book (Rötzer, *Natürliche Empfängnisregelung*, 2021 edition) is the
highest authority. Its text was extracted with `pdftotext -layout` (160
pages; PDF page = printed page), so claims are checked against it and cited
by printed page in [rules.md](rules.md). Below the book ranks the teacher-made
[cheatsheet.md](cheatsheet.md) — an original source, not edited here — and
[rules.md](rules.md) condenses the rule-set for this app's vocabulary.
Rules change only from official sources (book, INER teaching material);
anything the sources do not cover is recorded as an open question or an
owner decision instead of being presented as book behavior. This pass
verified the items listed under “Book verification”; it is not a claim that
every rule detail of the book has been audited page by page.

## App conventions

- **Mark naming**: the user-placed mark is the „Temperaturanstieg“; only the
  computed post-peak circles are „umrandete höhere Messungen“. rules.md
  „Pfeilmessung“ (S. 58) calls the rising values before the peak
  „Pfeilmessungen“, and the cheatsheet asks for the „**erste** höhere Messung
  **nach** dem \*“, so “higher measurement” names a measured, circled value,
  not the mark. The persisted token `firstHigherMeasurement` keeps its name
  for storage stability.
- **Candidate walk**: from the marked rise onward, every measured day
  strictly above the baseline is a candidate. The 0.2 °C margin decides only
  which of the two book cases applies: at least 0.2 °C starts the „sicher
  unfruchtbare Zeit“ on the evening of the 3rd circle; below it, the „Erster
  Sonderfall“ awaits a 4th higher measurement, a waking temperature, so the
  app reports the morning start after it is read. The book lets the first of the three
  circles sit at only 0.05 °C above the baseline („die Hälfte von 0,1 °C“,
  rules.md, S. 30); with the app's 0.05 °C recording granularity this
  collapses to „above the baseline“, so the strictly-above walk is
  book-consistent (owner decision 2026-11-12).
- **Latest-mark anchor**: the most recent rise mark and the most recent peak
  mark anchor the evaluation. Re-marking supersedes; earlier marks stay
  stored but no longer anchor, so they render no candidate.
- **Temperature-ignore exclusion**: a day marked “ignore temperature” is
  excluded from the baseline and from the numbered lows and counts as a gap
  day. The exclusion is manual-only; it is never inferred from the day's
  disturbance flags. The book says only that a bracketed value is neglected
  when judging the lower measurements and does not influence the Basislinie;
  treating an ignored day as an unmeasured day / a gap is the app's own
  reading, and the app's gap-day behavior stays separate from the book's
  Einklammerung.
- **Low-window numbering**: a missing or excluded day inside the six-day
  window counts for the sequence but receives no digit, so the numbers skip
  (for example `6 5 _ 3 _ 1`). This is an app interpretation of the window,
  not quoted book text; see “Book verification” below.
- **Gap tolerance**: the candidate sequence tolerates at most one gap day in
  total — an unmeasured day, an excluded day, or a day at/below the baseline
  all count as the same gap class, including across the arrow-to-circle
  transition. A second gap day stops the evaluation at the next
  above-baseline day; a trailing gap with no following candidate does not
  stop it. The book's nearest sentence is „nur eine!“ for a fallen
  measurement (S. 42); the gap class and the second-drop stop are app
  conventions.
- **Per-kind cap**: up to four arrows and up to four circles each carry
  ordinals 1–4. Candidates beyond their own kind's cap stay in the sequence
  but unnumbered.
- **Peak marker**: the app renders the book's peak dot in its own in-plot
  row above the mucus letters row, never on the temperature curve. Every
  placed peak renders from the marks stream, so peaks appear even when no
  evaluation exists. This is rendering only; the rule itself (dot above the
  mucus sign) is in [rules.md](rules.md).
- **Baseline difference**: every marked candidate carries its difference to
  the baseline, so the UI renders it without arithmetic.
- **Baseline line extent**: the drawn baseline segment starts at the
  earliest numbered low day and ends at the last marked candidate day,
  clamped by the next cycle start and by the next cycle's six-low window
  start. A cycle with no marked candidate draws no segment.
- **Rise consistency check**: the marked rise day's measured value is
  compared with the baseline; an inconsistent mark produces the persistent
  warning on that day, recomputed at render time.
- **Statistics earliest first higher**: one sense — the first circled
  candidate (`firstCircledCandidateDay`), the book's „umrandete höhere
  Messung“. A cycle without a circle renders „—“ and feeds no metric card;
  the „Temperaturanstieg“ mark is not a statistic. See “Statistics ruling”
  below.

## Implementation map

| Convention                                  | Current code                                                                         |
|---------------------------------------------|--------------------------------------------------------------------------------------|
| candidate walk                              | `_evaluateCycle` / `_candidateValue` / `candidateMeasurements`                       |
| latest-mark anchor                          | `_latestMarkOf`                                                                      |
| temperature-ignore exclusion                | `excludedDays` / `ignoredDayIndexes`                                                 |
| gap tolerance                               | `gapDays` / `evaluationStopped`                                                      |
| low-window numbering                        | `NumberedLow.number` / `_LowWindow.numberedLows`                                     |
| per-kind cap                                | `_marksPerKindCap` / `MarkKind` / `ordinal`                                          |
| peak marker                                 | `EvaluationOverlay.peakIndexes` / `peakDotCenterOffsetK`                             |
| baseline difference                         | `CandidateMeasurement.differenceK` / `cycleSheetDifferenceInfo`                      |
| baseline line extent                        | `BaselineSpan` / `baselineSpan` / `BaselineSegment` / `PdfBaselinePiece`             |
| rise consistency check                      | `riseMarkConsistent`                                                                 |
| computed „sicher unfruchtbare Zeit“ trigger | `suzBegins` / `cycleSheetSuzSuggestion*`                                             |
| statistics earliest first higher            | `earliestFirstHigherCycleDay` / `firstCircledCandidateDay`                          |

## Settled interpretations

Owner-confirmed on 2026-09-17:

- An unmeasured or excluded day inside the candidate sequence counts exactly
  like a day at/below the baseline — one gap-day class consuming the
  single-gap allowance.
- The „sicher unfruchtbare Zeit“ is declared only from circled
  measurements. Arrows are „Pfeilmessungen“, not „höhere Messungen“ in the
  sense of the evaluation, and circles exist only after the peak day, so an
  arrow-only sequence never yields a trigger.
- The user is assumed to follow the rules (Mode M), so the user-placed
  „Temperaturanstieg“ is taken verbatim as the anchor for the six-low
  window, the baseline and the candidate search, even when the marked day
  itself is not above the baseline; the search starts at the next
  strictly-above measurement from the mark onward.
- Multiple peak and rise marks inside one cycle are expected, not a
  user-data problem. The most recent mark of each type anchors the
  evaluation; earlier duplicates stay stored until removed through the
  sheet's mark toggles.

Owner decisions on temperature exclusion (2026-09-19):

- The exclusion is manual-only and made visible as the mark sheet's own
  chip.
- The day's disturbance flags are not shown there; flag editing stays
  diary-side.
- Marked days render lighter on the temperature curve.
- The mark does not affect the drip-import cycle-start replay.

Owner decisions on record granularity (2026-11-12):

- Temperatures are stored in 0.05 °C steps. The book's first-circle
  tolerance („die Hälfte von 0,1 °C“, rules.md, S. 30) is therefore
  equivalent to „higher“ — the strictly-above candidate walk is
  book-consistent and needs no tolerance logic of its own.

### Book-verified, kept as app conventions

- **Low-window numbering**: the book's printed tables show continuous
  `6 5 4 3 2 1`; no `6 5 _ 3 _ 1` pattern appears. The text only says
  „mit den Ziffern 1 bis 6 zurücknummeriert“ (S. 30) and that a single
  disturbed value has „kein Einfluss auf die Rücknummerierung 1 bis 6“
  (S. 43). The skipped digit is therefore the app interpretation “low-window
  numbering”, not book text.
- **Gap tolerance**: the book's „nur eine!“ covers exactly one fallen
  measurement inside the three higher measurements (S. 42). A missing day
  is not covered by a rule there (S. 32 says only that no connecting line is
  drawn); “a second drop ends the search” is an inference, not a book
  sentence. Both remain app conventions with the S. 42 reference.

## Open questions (`TODO(user-review)`)

- Baseline segment with fewer than six numbered lows: the segment start falls
  on the earliest available low day instead of a low #6 that does not exist.
  The book rule defines only the six-low case; the closest book analogue
  comes from the abgekürzte Verfahren — with fewer lower measurements
  recorded, clearly „higher“ measurements are required (rules.md, S. 41) —
  which is a different context and does not directly cover the fallback.
- End-of-segment clamps: the min() clamps are defensive — under the current
  cycle grouping they cannot bind. Revisit if a future grouping change makes
  them bind.
- Stopped-evaluation notice scope: the notice surfaces on the whole cycle
  rather than only the day after the break, because the domain does not
  report the break day.
- Minimum placement of the difference line: the sheet info line is the
  minimum display for the baseline difference; extra placements (chart-curve
  labels) remain an option for the expert review.
- Rise-consistency wording: the dialog and info-line wording is pending the
  expert review.
- „Sicher unfruchtbare Zeit“ glyph top anchoring: the bar hangs down from
  the chart's top border by a fixed °C drop and the arrow anchors just below
  that border — an owner-eyeball placement, not a settled rule. A
  temperature dot near the scale top can visually meet the arrow; accepted,
  no avoidance logic.
- Days after the trigger: days after the „sicher unfruchtbare Zeit“ trigger
  or after a connectedness break render as ordinary temperature dots. The
  domain lists exactly the marked candidates; there is no automatic
  continuation — the user re-marks the rise.
- „Hochlage“ start: whether the higher phase begins at the
  „Temperaturanstieg“ (the placed mark) or only at the first circled higher
  measurement. The app counts „Dauer der Hochlage“ from the circled day; an
  INER-expert question, not a settled rule.
- Persisted `CycleMarkTypes.suzEvening` / `suzMorning`: the two chips, their
  DB tokens, labels and chart placement (column start vs. column middle)
  predate this audit. The morning rule semantics are settled by the owner
  decision of 2026-11-12 (see “Candidate walk”); whether the morning chip
  survives as a manual annotation or is relabeled/removed (with a migration
  or read-compat plan) remains a separate owner UI decision.

## Statistics ruling

`earliestFirstHigherCycleDay` reports one sense over the mark-driven cycles:
the minimum cycle-day number (the cycle's marked start day is day 1) of the
cycles' first circled candidate — `firstCircledCandidateDay()`, the book's
„umrandete höhere Messung“. The chart's and PDF's rings draw from the same
circle definition, the cycle's evaluated candidate sequence
(`CycleEvaluation.candidateMeasurements`) filtered to `MarkKind.circle`; the
statistics layer and the PDF per-cycle header line run the helper over their
cycles and truncated record prefixes, so screen statistics and PDF statistics
share one evaluated candidate sequence. There is no `any` variant and no mark
fallback: a cycle without a circle renders „—“ on the statistics surfaces and
feeds no metric card.

The NER analysis rules are the official ones; the first circled line is a
consequence of them, and that measured day is the first higher measurement
the statistics analyze. The term is book-anchored: the modifizierte
Döring-Regel searches all cycles for „der Tag der frühesten eingetretenen
ersten umrandeten höheren Messung“ (rules.md, S. 37).

| Situation                                                 | Outcome                                                |
|-----------------------------------------------------------|--------------------------------------------------------|
| a marked „Temperaturanstieg“ without a measured circle    | no statistic — the cycle renders „—“                   |
| rise strictly after peak, measured above the baseline     | first circle = rise day                                |
| rise at/before peak, peak + 1 measured above the baseline | first circle = peak + 1                                |
| rise at/before peak, peak + 1 unmeasured or ≤ baseline    | first circle later, or the cycle does not qualify      |
| rise after peak, marked day itself not above the baseline | first circle later, or the cycle does not qualify      |
| sequence gap-stopped before any circle                    | no circle — the cycle does not qualify                 |
| no marked peak                                            | arrows only — no circle, so the cycle does not qualify |

The day numbers lie inside their cycle's window by construction (marks attach
within a cycle window; the candidate walk ends at the cycle's own end), so no
extra window guard is needed.
