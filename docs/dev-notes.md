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

## Dialog scrim-dismissal race (test/dialog_and_shell_lifecycle_test.dart)

An Android field report for the dialog/diary cluster described a Flutter
framework assertion (`_dependents.isEmpty` in InheritedElement unmount — an
inherited widget element taken down while widgets still depend on it). The
lifecycle regression matrix in `test/dialog_and_shell_lifecycle_test.dart`
drives the dialog and diary interaction surface through the real app shell
(all tabs mounted in the IndexedStack) with an error collector wrapped
around each scenario INCLUDING the explicit teardown, and reproduced the
defect deterministically:

Fast scrim dismissal racing the running drip-import popped the ENTIRE route
stack out from under the app — right after the second tap the MaterialApp
rendered an empty Navigator (no scaffold, no shell, no bottom navigation).
Cause: the dialogs' apply closure runs on the settings screen and pops the
DIALOG by the dialog's context once the import lands. After a fast dismissal
the dialog route is already popped by the barrier tap, but its elements are
not yet torn down — `dialogContext.mounted` is still true, so the
mounted-guarded pop went through, `Navigator.of(dialogContext)` still
resolved to the root navigator (the context's ancestor chain is intact until
route finalization) and popped whatever was on top now: the HOME route. On a
device, the same race tears the whole visible UI down with the dialog; the
churn through the route's inherited-element teardown (the dialog route's
MediaQuery/Localizations/riverpod scope dependents being disassembled while
still registering dependents) is the class of field-reported assertion.

Fix policy: the success-path pop only fires while the dialog route is still
the current route (`ModalRoute.of(...).isCurrent` in the settings screen's
apply handlers); the import summary still appears as a snackbar from the
screen context either way.

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

## NER rules and app conventions

The book rule-set is summarized in [NER/rules.md](NER/rules.md). The app's
own evaluation and rendering conventions, the implementation map, the settled
interpretations, the open `TODO(user-review)` questions and the statistics
ruling live in [NER/app-conventions.md](NER/app-conventions.md).

## Paper-form PDF export (lib/pdf/cycle_pdf.dart)

Layout/design decisions:

- Print friendliness (the sheet's own rendering principle, applied to
  everything on it): the sheet must survive plain B/W printing — no
  information may be encoded in COLOR alone. Every colored or informative
  element carries a second, color-independent difference (shape, position,
  weight or luminance): the curve (near-black ink) vs the accent marks
  (rings, arrows, dashed baseline, bold 1–6 numbers, peak dot,
  user-placed „sicher unfruchtbare Zeit“ bars — each differs by SHAPE or
  POSITION, and the accent grayscales to a mid-gray clearly lighter than
  ink), the bleeding levels (solid fill FRACTION and the dotted spotting
  mechanic, not the red), the dimmed ignoreTemperature pieces (ExtGState
  alpha → lighter gray + thinner stroke), the dashed window
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
  data (the 1–6 numbering, the baseline value, the baseline differences,
  the gap-tolerance stopped-evaluation notice, the „sicher unfruchtbare
  Zeit“ suggestion) is recomputed from the entries + marks streams at
  render time; a write re-emits through marksProvider, so labels, chart
  overlay and info lines update live.
- Non-modal: the panel is owned by cycle_day_panel_provider and rendered
  as a fixed dock at the bottom of the cycle screen — a card in front of
  the chart list, margin ~12 dp above the system bottom inset, elevation
  so it reads as a layer above the chart — never pushed as a route.
  Tapping a chart day never scrolls the list: it only swaps the dock's
  content in place (retargeting keeps the panel open; the first day's
  marks are never deselected by a dismissal), and the close button clears
  it explicitly. The rows the dock covers stay reachable through the
  list's extra bottom padding, measured from the dock's laid-out height
  and re-measured on every retarget.
- Height cap: the dock never covers more than ~60% of the body space above
  its own bottom offset — the cap is computed from a `LayoutBuilder`'s
  constraints around the dock branch (the AppBar's share and a
  keyboard-shrunk body count; the full surface does not) and handed to the
  panel as data. Most days never reach the cap (two or three chip rows
  plus the note); beyond it the panel content scrolls internally instead
  of the dock growing over the chart, and the scroll view is re-keyed per
  day so a retarget opens the new day's content at the top.
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
- „Sicher unfruchtbare Zeit“ suggestion: on the computed `suzBegins` day
  the suggestion line names the firing book case — „Sicher unfruchtbare
  Zeit am Abend“ when the quoted book text begins it that evening, or the
  „Erster Sonderfall“ (vierte höhere Messung) with the morning wording
  settled by the 2026-11-12 owner decision: the 4th is a waking temperature,
  so the start is that morning (book boundary note in
  app-conventions.md) — while no user mark exists anywhere in that cycle.
  The computed „sicher unfruchtbare Zeit“ is never persisted and never
  renders on the chart; a manual mark in turn never alters the arithmetic
  (compute-only separation, ADR-0001).
