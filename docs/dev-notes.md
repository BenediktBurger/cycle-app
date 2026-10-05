# Dev notes

Short-lived operational lessons and how-tos that do not merit an ADR.
(There is no history here — git history is the record of executed steps.)

## Never move `flutter create` output up a directory tree

**Cautionary tale from 2026-09-15 — how the original `README.md` got clobbered.**

The platform scaffolding was *not* created by the safe command. The project
owner had earlier run `flutter create cycle_app` (which creates a
**subfolder**) and then moved its contents up with `mv cycle_app/* ./`. Two
problems:

1. Template non-dotfiles (`README.md`, `pubspec.yaml`, `lib/main.dart`,
   `test/widget_test.dart`, `web/index.html`, …) **overwrote** the project's
   own hand-reviewed files of the same name at the repo root — this is
   literally how the hand-written `README.md` was replaced by flutter's
   "A new Flutter project" template (repaired 2026-09-15).
2. `mv cycle_app/*` **skips dotfiles** — flutter's `.gitignore`, `.metadata`,
   `.idea/` etc. stayed inside the leftover `cycle_app/` directory or were
   dropped entirely.

**Rule going forward:** never move scaffold output up a level like that. To
(re)generate platform files, run `flutter create .` against the existing
tree — it **preserves already-existing files**:

```sh
flutter create --platforms=android,ios --project-name cycle_app .
```

(Web is not listed here because `web/index.html` and `web/manifest.json`
already exist in this repo and are preserved untouched. `flutter create`
never clobbers existing files, so the web pair survives either way.)

Even so, run `git status` right afterwards: if any tracked file shows up as
*modified*, restore it with `git checkout -- <file>` and investigate before
continuing (`flutter create` for web never clobbers `web/manifest.json` and
does not require icon files for a web build).

A related tripwire lives in `pubspec.yaml`: if that file ever reverts to
"A new Flutter project" defaults, a `flutter create` run has clobbered it —
restore from git history.

## Lesson learned: `flutter test` and loopback sockets (2026-09-15, resolved)

`flutter_tester` (spawned by `flutter test`) opens a temporary loopback
WebSocket server socket, so a sandbox that denies `bind()` on 127.0.0.1
ports breaks it (`Failed to create server socket (OS Error: Permission
denied, errno = 13)`). An omac sandbox version used to behave that way, and
an intent was documented in its sandbox log.

Resolved 2026-09-16: in the current environment `flutter test` runs directly
inside the sandbox — agents/editors just execute `flutter pub get` and then
`flutter test` like anyone else. If it ever starts failing with the bind
error above again, the cause is the sandbox profile, not the tests; verify
against the log and fall back to `flutter analyze` plus the host-VM smoke
scripts (§4 of CONTRIBUTING.md) until it is lifted again.

## NER evaluation rules, as implemented (lib/domain/evaluation.dart)

HARD RULE (ADR-0001, Mode M): the user places marks, the app computes, never
interprets. Everything the evaluation produces is computed only at render
time — nothing is persisted. The overall Mode-M posture is accepted by owner
decision; the per-rule `TODO(user-review)` flags are separate open questions.

Rules as implemented (owner-reviewed):

- R1 Candidacy: every measured day STRICTLY ABOVE the baseline is a
  candidate, regardless of the margin. The 0.2 K margin survives only
  inside SUZ rule D.
- R2 Connectedness: between consecutive candidates at most ONE intervening
  day may be missing (no measured temperature), excluded, or at/below the
  baseline. With more than one such day the automatic evaluation STOPS
  (`evaluationStopped`): no SUZ, nothing further is marked, no automatic
  re-search — the user re-marks the rise at the next higher measurement.
  The gap counting applies across the WHOLE candidate sequence, including
  the arrow→circle transition — mixed sequences are one sequence.
- R3 Candidate region: candidates exist only from the marked rise day
  onward. The rise anchor is the MOST RECENT `firstHigherMeasurement` mark
  of the cycle (owner-confirmed: re-marking supersedes — after a broken
  Hochlage or a delayed second peak the user re-marks the rise; the earlier
  mark stays stored and, lying before the walk region, renders no
  candidate). Above-baseline values before the rise are user error or a
  separately-handled disturbance and never become candidates.
- R4 Arrow vs circle, PER CANDIDATE: a candidate is an ARROW when the mucus
  peak is not set at all, or the candidate day is at or before the peak day
  (the peak day's own above-baseline temperature is an ARROW); every
  candidate AFTER the peak day is a CIRCLE. The peak anchor is the MOST
  RECENT marked peak of the cycle ("Höhepunkt = letzter Tag mit der besten
  Qualität"): multiple peaks arise from delayed ovulation — a peak subsides
  and a later one appears — so the last marked peak is the ovulation that
  counts. When a later peak is added, earlier candidates flip from circles
  back to arrows automatically (compute-only re-evaluation, no mark
  changes). Arrows and circles are never interleaved. The caps are PER
  KIND: up to four arrows carry ordinals 1–4, then up to four circles carry
  ordinals 1–4; candidates beyond their kind's cap stay unnumbered (ordinal
  null), so a late peak does not swallow the circles that follow it.
- R5 SUZ rules D and E count CIRCLED measurements only (the cheat sheet
  speaks of the "umrandete" — circled — higher measurement; arrows never
  start the SUZ, and circles exist only after the peak day, so an
  arrow-only sequence never yields an SUZ). D: the 3rd CIRCLE at least
  0.2 K above the baseline starts the SUZ the EVENING of that day ("gegen
  Abendessen"). E: when the 3rd circle is below that margin, the 4th CIRCLE
  — ANY margin — starts the SUZ in the MORNING of that day. Both require
  R2 connectedness; once a rule fires the sequence is complete.
- R7 Every marked candidate carries its difference to the baseline
  (`differenceK`) so the UI can render it without arithmetic.
- R9 Six-low window and numbering: the six-low window is the SIX PREVIOUS
  CALENDAR DAYS before the user-marked first higher measurement
  (rise−1 … rise−6), intersected with the cycle group's tracked days; the
  baseline is the MAX of the not-marked-excluded MEASURED temperatures
  within those days (the earliest maximum wins on ties). Any measured,
  not-marked-excluded temperature in the window counts as a low, regardless
  of its mucus role — the peak day itself carries a number when it falls
  into the window. Numbering belongs to the CALENDAR POSITIONS, not a dense
  index: the measured, not-excluded day at rise−i carries number i
  (cheat sheet: "zurücknummerieren"); an untracked, unmeasured or
  excluded window day gets NO number — numbers skip, e.g. "6 5 _ 3 _ 1".
  A window reaching past the group's first tracked day (rise marked within
  the first six days of a cycle group) truncates at the group's tracked
  days — beyond that it must not reach into the previous cycle group; the
  edge case is consciously not handled further (owner: "should never happen
  physically").
- R10 Baseline SEGMENT: the evaluation reports the x-extent the drawn
  baseline line covers (`baselineSpan`). START: the earliest numbered low
  day (low #6; see the TODO below for the fewer-than-six case). END: the
  last marked candidate day (arrow or circle), clamped by the next
  menstruation start and by the next cycle's six-low window start per
  R10's min() definition — under the current grouping both clamps cannot
  bind; they are kept because R10 defines them. The "+ half a day" padding
  past the end day's column is a rendering concern of the chart. A cycle
  with NO marked candidate draws no segment (null span).

Owner-confirmed settled interpretations (2026-09-17):

- An unmeasured or EXCLUDED day inside the candidate sequence counts
  exactly like a day at/below the baseline — a gap day consuming the
  one-gap R2 allowance. The R2 class list names one and the same gap-day
  class.
- The SUZ is declared only from CIRCLED measurements (summary rule 2.5:
  arrows are "keine höhere Messung im Sinne dieser Auswertung"; rules
  2.7/2.8 cite the "umrandete höhere Messung").
- The user is assumed to follow the rules (Mode M), so the user-marked
  first higher measurement is taken verbatim for the six-low window and
  the baseline, even when the marked day itself is not above the baseline;
  the candidate search then starts at the next strictly-above measurement
  from the mark onward (R3).
- Multiple peak / first-higher marks inside one cycle are EXPECTED, not a
  user-data problem; the MOST RECENT mark of each type anchors the
  evaluation and earlier duplicates stay stored until removed through the
  sheet's mark toggles.

Open questions (`TODO(user-review)` in the file):

- R10 with fewer than six numbered lows: the segment START falls on the
  earliest AVAILABLE low day instead of a low #6 that does not exist.
  R10 defines only the six-low case; the fallback is this implementation's
  choice.
- R10 end-of-segment handling: the min() clamps are defensive — under the
  current cycle grouping they can never bind. If a future grouping change
  makes them bind, revisit.

## Statistics' "earliest first higher" variants (lib/domain/statistics.dart)

`earliestFirstHigherCycleDay` folds two variants over the mark-driven
cycles, both reported as cycle-day numbers (the cycle's marked start day is
day 1):

- `any`: the minimum cycle-day number of the marked first-higher rise,
  wherever it sits relative to the mucus peak. Mark-position only.
- `afterMucusPeak` (the "umrandete Messung"): the minimum cycle-day number
  of the cycles' FIRST CIRCLED candidate — `firstCircledCandidateDay()`
  (evaluation.dart, rule R4). The same function behind the chart's and
  PDF's rings and the fact rows' first-higher resolution (`marked day`
  fallback), so rendering and statistics refer to one domain definition.
  The PDF per-cycle header line shares the helper over its truncated
  record prefixes.

The ruling behind the real variant: the NER analysis rules are the
official ones; the first circled line is a consequence of them, and that
marked-and-measured day is the first higher measurement the statistics
analyze. A mark-only reading ("the marked rise, else peak + 1, without a
temperature") differs from it exactly where the measurement is absent:

| Situation | mark-only reading | first circle (R4, implemented) |
|---|---|---|
| rise strictly after peak, measured above the baseline | rise day | first circle = rise day |
| rise at/before peak, peak + 1 measured above the baseline | peak + 1 | first circle = peak + 1 |
| rise at/before peak, peak + 1 unmeasured or ≤ baseline | peak + 1 (no temperature needed) | first circle later, or the cycle does not qualify |
| rise after peak, marked day itself not above the baseline | the marked day | first circle later, or the cycle does not qualify |
| sequence gap-stopped (R2) before any circle | peak + 1 qualifies | no circle — the cycle does not qualify |
| no marked peak | real variant null | arrows only — no circle, so the cycle does not qualify |

Both variants' day numbers lie inside their cycle's window by
construction (marks attach within a cycle window; the candidate walk ends
at the cycle's own end), so no extra window guard is needed.

## Paper-form PDF export (lib/pdf/cycle_pdf.dart)

Layout/design decisions:

- Print friendliness (the sheet's own rendering principle, applied to
  everything on it): the sheet must survive plain B/W printing — no
  information may be encoded in COLOR alone. Every colored or informative
  element carries a second, color-independent difference (shape, position,
  weight or luminance): the curve (near-black ink) vs the accent marks
  (rings, arrows, dashed baseline, bold 1–6 numbers, peak dot, SUZ bars —
  each differs by SHAPE or POSITION, and the accent grayscales to a
  mid-gray clearly lighter than ink), the bleeding levels (solid fill
  FRACTION and the dotted spotting mechanic, not the red), the dimmed
  ignoreTemperature pieces (ExtGState alpha → lighter gray + thinner
  stroke), the computed-SUZ line (thin ink line + rule letter, distinct in
  shape and letter from the user SUZ bar+arrow glyph), the dashed window
  bounds, the always-dark scale labels and value row, and the weekend
  bands (all-equal near-white gray — never a pale color — far enough from
  ink/accent/grid grays that nothing above or beside it loses legibility).
- Print idempotency: a page must look identical however late it is
  reprinted, so the cumulative header facts ("Beobachtete Zyklen",
  shortest cycle, earliest first higher) are read at the printed cycle's
  point of view, truncated at that cycle.
- Anonymize (per export, not persisted): the toggle hides the stored name
  and birth date and marks the header "anonymisiert", even when no
  identifying value was stored at all. The observation window (with the
  year) is NOT anonymized — it belongs to the evaluation, not the person.
- Vertical notes: the rotated notes area — multi-line diary notes fold
  into one bottom-up line. DOCUMENTED LIMITATION: a note longer than the
  area clips at its bounds (paper sheets behave the same when the
  handwriting runs out of room); there is no overflow marker and no
  follow-to-next-page rendering — future work, deliberately out of scope.
- Dense glyphs (accepted): at ~18 pt columns the superset cells (mucus
  glyph + quality superscript, stacked disturbance codes, cervix
  shorthand pairs) render in footnote-sized type kept to the cell; longer
  runs clip like the notes area.
- Document language: German — the PDF replaces the German paper form
  (NFR/Rötzer practice; the audience is teacher/doctor), matching the
  language-free-data JSON export precedent. Localizing the document is
  future work, not wired yet.
- Font: the bundled Noto Sans TTF (OFL, assets/fonts/) is the document
  base font so note text beyond Latin-1 renders verbatim; symbols outside
  the font's own coverage (arrows, emoji, …) draw as the notdef box — the
  byte generation never fails on them.
- The curve block has no caption row of its own: the °C lives in every
  scale label, and the temperature naming lives on the below-plot value
  row's rail legend ("Temperatur in °C").
- The in-plot glyph halo is a paper-colored backing, not a stroke pass:
  with the pdf package (3.13.1) the text layer leaks the render mode —
  `setFont` emits the `Tr` operator only for non-fill modes and
  `drawString` never resets it, so a stroke-mode halo pass would keep
  stroking every later text on the page. Backing and ink share the
  slot center, so their placement cannot drift.

## Drip CSV import format

The input of lib/domain/drip_import.dart is the CSV export of the sibling
"drip" app: one header row of flattened CycleDay columns like
`temperature.value`, then one row per calendar day. The format spec is
drip's own writer (drip: lib/import-export/export-to-csv.js):

- fields are comma-separated; string cells containing `\n`, `\t`, `,`,
  `;`, `.` or `'` are wrapped in double quotes with inner quotes escaped
  as `""`,
- rows are joined with plain `\n` (the parser also tolerates `\r\n`),
- the header lists the columns of whichever drip version exported the
  file, so all parsing is header-driven: unknown columns are ignored,
  known-but-missing columns simply carry no data. A day's `notes` hold
  the free note plus tagged lines — `[temp]`, `[bleedingExclude]`,
  `[mucus]`, `[cervix]`, `[desire]`, `[pain]`, `[sex]` and `[mood]` — for
  example the unmapped pain kinds in `[pain] cramps, migraine` or the
  raw desire value in `[desire] 2`.

## Cycle day mark sheet (lib/ui/cycle_mark_sheet.dart)

- Mode M applies (ADR-0001): the panel writes nothing derived — mark
  toggles go through the MarksDao, and everything it shows as evaluation
  data (the 1–6 numbering, the baseline value, the R7 differences, the R2
  stopped-evaluation notice, the SUZ suggestion) is recomputed from the
  entries + marks streams at render time; a write re-emits through
  marksProvider, so labels, chart overlay and info lines update live.
- Non-modal: the panel is owned by cycle_day_panel_provider and rendered
  in a fixed slot below the chart, never pushed as a route. Tapping
  another chart day retargets it in place — the first day's marks are
  never deselected by a dismissal — and the close button clears it
  explicitly.
- Layout: all six chips (the five mark chips and the temperature-exclusion
  chip) sit in ONE shared grid of equal column widths — two columns on
  phone widths, three from 600 dp — so every row completes evenly. Each
  chip carries a static mark-name label plus the mark type's identifying
  avatar icon (flag, dot, ring, dusk, sun, crossed-out eye —
  identification only); the selected state carries set/remove through the
  Material selected fill, announced as selected to screen readers. The
  canvas-drawn checkmark is off: it overlapped the scrimmed avatar icon,
  and the fill plus the announced selection already carry set/remove.
- No note editing in the panel: notes live in the diary entry form's note
  row, so there is no comment surface to lay out in columns.
- SUZ suggestion: on the computed `suzBegins` day the suggestion line
  names which rule fired with the rule's time of day — rule D the EVENING
  phrasing (the SUZ begins that evening, "gegen Abendessen"), rule E the
  MORNING phrasing — while no user SUZ mark exists anywhere in that
  cycle. The computed SUZ is never persisted and never renders on the
  chart; a manual SUZ mark in turn never alters the arithmetic
  (compute-only separation, ADR-0001).
- Temperature exclusion (owner decisions, 2026-09-19): the exclusion is
  manual-only and made visible as the grid's third chip; the day's
  disturbance flags are not shown there (the chart's disturbance row
  spells them per day), flag editing stays diary-side, and marked days
  render lighter on the temperature curve. The mark does not affect the
  drip-import cycleStart replay.
