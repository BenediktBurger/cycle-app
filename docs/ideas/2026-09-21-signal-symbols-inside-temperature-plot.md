# Idea: Signal symbols overlaid inside the temperature plot

> Status: landed for the sex Xs, the mucus letters, and the mucus peak
> dot (see `lib/ui/chart_marks.dart`, consumed by the screen chart and
> the PDF painter; git history holds the rest). The 2026-09-21
> seven-band layout sketch is superseded: bleeding, Mittelschmerz and
> the exclusion reasons stayed in the rows, and the row pitches settled
> at −0.15 / −0.25 / −0.35 °C from the scale max.

## Settled decisions

- Overlay semantics, owner-chosen: the in-plot glyphs paint over the
  curve and dots with no collision-avoidance logic — an occasional
  collision reads as accepted ink-over-dot.
- Row pitches from the scale max, at the 0.1 K grid-band centers
  (owner-eyeball choices, flagged `TODO(user-review)` in
  `lib/ui/chart_marks.dart`): sex X row at `max − 0.15`, mucus peak dot
  at `max − 0.25` (shared with the SUZ arrow row, directly above the
  day's letter), mucus letters row at `max − 0.35`.
- The mucus peak dot is part of the mucus band: it hides and shows with
  the letters row, not alone.
- Under narrow settings ranges each row hides independently once its
  center value leaves the plot (`chartMarkRowVisible`, one shared
  predicate for screen and PDF).
- The below-chart strip (time, disturbance, cervix, pain B, note) stays
  unchanged.

## Still open

- The Mittelschmerz letter M's row placement in
  `lib/ui/cycle_recording_rows.dart` (existing `TODO(user-review)`):
  with mucus letters now in the plot, the question is whether the pain
  row should ALSO show M.
