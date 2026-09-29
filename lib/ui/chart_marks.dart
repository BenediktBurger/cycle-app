// The in-chart glyph layer's shared constants and the per-day placement
// map for the marks rendered INSIDE the temperature plot (sex X marks,
// mucus sign letters, mucus peak dot, the Mittelschmerz M and the
// evaluation day numbers) — pure Dart, NO Flutter imports (the cycle
// chart and the PDF export both place the glyphs in °C scale units, and
// the PDF generation layer must stay free of material imports for the
// host smoke scripts, tool/pdf_smoke.dart).
//
// The glyphs paint OVER the fl_chart temperature dots with no avoidance
// logic — an occasional collision reads as accepted ink-over-dot.
//
// TODO(user-review): the row pitches and the alpha below are owner-eyeball
// rendering details, not settled rules; the top-anchored rows sit between
// the 0.1 K grid lines at the −0.05 (sex), −0.15 (peak dot / SUZ arrow),
// −0.25 (mucus letters) and −0.35 (M) offsets from the scale max, and the
// day numbers anchor from the BOTTOM at min + 0.05.
import '../domain/mucus.dart';
import '../domain/models.dart';
import '../domain/temperature_range.dart';

/// The gridline-gap margin every visibility predicate keeps free at both
/// ends of the settings range: a row's center must stay at or inside
/// `min + [chartEdgeMarginK] … max − [chartEdgeMarginK]` to render.
const double chartEdgeMarginK = 0.05;

/// Vertical pitch of the sex X row's glyph center, in °C below the scale
/// max ([TemperatureRange.max]).
const double sexRowCenterOffsetK = 0.05;

/// Vertical pitch of the mucus peak dot's center, in °C below the scale
/// max — shared with the SUZ arrow row (see suz_glyph.dart), so a
/// same-column peak/arrow co-occurrence collides (accepted). The dot is
/// ITS OWN row: it hides and shows at this offset, decoupled from the
/// letters row below it.
const double peakDotCenterOffsetK = 0.15;

/// Vertical pitch of the mucus letter row's glyph center, in °C below the
/// scale max.
const double mucusRowCenterOffsetK = 0.25;

/// Vertical pitch of the Mittelschmerz M row's glyph center, in °C below
/// the scale max — the bottommost in-plot signal row.
const double mRowCenterOffsetK = 0.35;

/// Vertical pitch of the evaluation day numbers' center, in °C ABOVE the
/// scale min ([TemperatureRange.min]) — the one bottom-anchored row; all
/// other rows anchor from the max.
const double dayNumbersRowCenterOffsetK = 0.05;

/// The one alpha every in-chart glyph renders at.
const double chartMarkAlpha = 0.85;

/// The halo stroke's width in logical pixels: the surface-colored stroke
/// pass behind every in-plot ink glyph (screen) paints at this weight.
/// TODO(user-review): the width is an owner-eyeball rendering detail.
const double chartMarkHaloStrokeWidth = 2.0;

/// The width of the fixed box centering a sex X at its slot's column
/// fraction — wide enough to never clip the glyph; screen and PDF share it.
const double sexGlyphBoxWidth = 14;

/// Whether a glyph row whose center sits [rowCenterOffsetK] °C below the
/// scale max still lands inside the plot: hidden (false) when the center
/// falls below the `min + [chartEdgeMarginK]` margin of the settings
/// range, which is never rescaled. Each row is evaluated independently at
/// its own offset — the peak dot at [peakDotCenterOffsetK], the letters
/// row at [mucusRowCenterOffsetK].
bool chartMarkRowVisible(double rowCenterOffsetK, TemperatureRange range) =>
    range.max - rowCenterOffsetK >= range.min + chartEdgeMarginK;

/// Whether the bottom-anchored day-numbers row still lands inside the
/// plot: its center sits [dayNumbersRowCenterOffsetK] °C above the scale
/// min, visible only while that center stays at or below
/// `max − [chartEdgeMarginK]` — i.e. when the range's span is at least
/// twice the edge margin. Boundary equality is visible.
bool dayNumbersRowVisible(TemperatureRange range) =>
    range.min + dayNumbersRowCenterOffsetK <= range.max - chartEdgeMarginK;

/// One X mark inside a day column: the recorded timing and its horizontal
/// slot as a fraction of the column width (start → 1/6, middle → 1/2,
/// end → 5/6 — the rows' exact x mapping, mirrored here).
typedef SexTimingSlot = ({SexTiming timing, double columnFraction});

/// The in-chart marks of one plotted day: the X slots, the mucus letter
/// (mucusDisplay's record, null when the day recorded no sign), the
/// peak-dot flag (peak-indexed day WITH an entry — mirrors the rows), the
/// Mittelschmerz M flag, and the evaluation day number the CALLER feeds
/// in (day index → number, already window-mapped by its producer — this
/// layer never computes a numbering).
typedef ChartDayMarks = ({
  List<SexTimingSlot> sexSlots,
  MucusDisplay? mucus,
  bool mucusPeak,
  bool mittelschmerz,
  int? dayNumber,
});

/// Maps the plotted days' entries (by day index, the chart's shapes) into
/// per-day placement records consumed by the screen widget and the PDF
/// painter; [peakIndexes] are the day indexes flagged as mucus peaks and
/// [numbers] feeds the day numbers through unchanged. A day absent from
/// [entries] gets no record, so an in-window lookup renders nothing for
/// it.
Map<int, ChartDayMarks> chartDayMarks(
  Map<int, DailyEntry> entries, {
  Set<int> peakIndexes = const {},
  Map<int, int> numbers = const {},
}) => {
  for (final MapEntry(:key, :value) in entries.entries)
    key: (
      sexSlots: [
        for (final timing in SexTiming.values)
          if (value.sexTimings & timing.bit != 0)
            (timing: timing, columnFraction: _sexFraction(timing)),
      ],
      mucus: _mucusOrNothing(
        sign: value.mucusSign,
        quality: value.mucusQuality,
      ),
      mucusPeak: peakIndexes.contains(key),
      mittelschmerz: value.painMittelschmerz,
      dayNumber: numbers[key],
    ),
};

/// A day without a recorded sign gets NO mucus record — null, not
/// mucusDisplay's all-null record — so both renderers skip empty days the
/// same way without re-checking the symbol.
MucusDisplay? _mucusOrNothing({MucusSign? sign, MucusQuality? quality}) {
  final display = mucusDisplay(sign: sign, quality: quality);
  return display.symbol == null ? null : display;
}

double _sexFraction(SexTiming timing) => switch (timing) {
  SexTiming.start => 1 / 6,
  SexTiming.middle => 0.5,
  SexTiming.end => 5 / 6,
};
