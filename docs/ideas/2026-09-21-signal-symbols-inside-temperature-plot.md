# Idea: Signal symbols overlaid inside the temperature plot

> Status: idea, not scheduled. Discussion notes from 2026-09-21 (owner
> request + review decisions captured inline). Nothing here is implemented
> yet; when this lands, this file should be reduced to the decisions that
> are still worth keeping (the rest lives in git history).

## Goal

Render bleeding, sex, mucus peak, mucus, and Mittelschmerz as day-cell
symbols INSIDE the temperature plot, each anchored to the chart's own
0.1 °C grid bands (one "row" = one 0.1 °C band of the temperature grid),
like the symptom rows of the NFP paper sheet. The curve/dots may run
behind the symbols — overlay semantics, explicitly chosen by the owner.

## Owner decisions (2026-09-21)

- **Spacing**: "two rows below" means two 0.1 °C grid bands of the
  temperature chart, not widget rows.
- **Placement**: overlay on the plot (symbols drawn on top of the plot's
  upper region; high temperatures can pass behind them).
- **Peak dot**: the solid mucus-peak dot must keep appearing above the
  mucus glyph; implementation detail (own band vs. reserved slot) is free.
- **Old rows**: the current above-chart signal block (bleeding, mucus,
  M, sex) is fully replaced; nothing remains between the day header and
  the chart except the overlaid symbols. The below-chart strip (time,
  disturbance, cervix, pain B, note) stays unchanged.

## Layout spec (top-down, in °C from the plot top)

| Symbol          | Band               | Band center value |
|-----------------|--------------------|-------------------|
| Bleeding        | 1                  | yMax − 0.05       |
| Sex             | 3 (2 bands below)  | yMax − 0.25       |
| Mucus peak dot  | 5 (2 bands below)  | yMax − 0.45       |
| Mucus glyph     | 6 (directly below) | yMax − 0.55       |
| Mittelschmerz M | 7 (directly below) | yMax − 0.65       |

Overlay stack depth: 0.7 °C (7 bands).

## Implementation sketch

- **Overlay widget** (lib/ui/cycle.dart): a windowed day-cell strip as a
  `Positioned.fill` child of the plot's existing `Stack` (after the
  `LineChart`, so symbols paint over the curve). Reuse the existing
  geometry: leading window spacer, cell i centered at
  `(i + 0.5) · colWidth`, test keys like `bleedingCell-N`. Reuse the
  existing content builders (`_bleedingContent`, `_sexContent`,
  `_mucusContent`, `_mittelschmerzContent`). Vertical position per
  symbol: `scale.pixelFor(bandCenterValue)` from the shared
  `_TemperatureScale` (`pixelFor`, lib/ui/cycle.dart).
- **Remove the old block**: the `_SignalRows(_topSignalKinds)` call and
  the `_topSignalKinds` constant; the enum and below-chart kinds stay.
- **Frozen left rail**: the top rows' name glyphs move INTO the scale
  slot, positioned at the same band pixel offsets (mirroring the
  overlay), replacing the `_railSignalSegment(_topSignalKinds)` block.
  The rail alignment test must stay green.

## Open rendering decisions (mark TODO(user-review) when implementing)

- **SUZ arrow collision**: the arrow glyph anchors 0.25 °C below the top
  border — that lands in the bleeding/sex bands. Proposal: move the
  arrow's anchor below the symbol stack (~0.75–0.8 °C inset); the SUZ
  bar itself still hangs from the top border behind the overlay.
- **Chart height**: the overlay consumes the top 0.7 °C of the plot.
  Proposal: grow the plot so the curve keeps its vertical room —
  `H = F · span / (span − 0.7)` where `F` is the current adaptive
  formula result (base + extra-degrees growth, capped). Eyeball
  heuristic, not a settled rule.
- **Tiny settings spans**: the settings range enforces min < max but can
  go down to a 0.5 °C span → bands ≈ 4 px, symbols collide. Either clamp
  with a minimum effective span or accept and flag.
- Band anchoring values above are owner-eyeball choices.

## Test impact (test/cycle_chart_test.dart)

- Update the per-signal-rows group: cells now live inside the plot; keys
  unchanged, positions re-asserted.
- Update the rail alignment test and the adaptive-chart-height test.
- Add: band-anchor test (symbol centers at `pixelFor(yMax − k·0.1 +
  0.05)` for a known range), dot-above-glyph order test, windowing test
  for the overlay.

## Data notes

No data-layer work needed: bleeding (`DailyEntry.bleeding`), sex
(`DailyEntry.sexTimings`), mucus (`DailyEntry.mucusSign`/`mucusQuality`),
mucus peak (user-placed mark → `overlay.peakIndexes`), and Mittelschmerz
(`DailyEntry.painMittelschmerz`) are all already available to
`_CycleChart`.

Related existing review flag this idea would resolve: the Mittelschmerz
letter M's row placement in lib/ui/cycle.dart (TODO(user-review), the
experts may want M in the pain row as well — with M in the plot, the
question shifts to whether the pain row should ALSO show it).
