// The paper-form geometry source for the PDF's day grid and temperature
// plot: the x layout of the left rail and the day columns, and the y
// geometry of the temperature scale. BOTH live here — the grid rows, the
// axis-label rail and the curve painter must never disagree about a
// position, so they all derive from these constants (plain doubles, no
// pdf-package import).
//
// y convention: yFor is the DISTANCE DOWN from the plot's top edge (the
// widget/rail convention — the upper range bound sits at y 0, the lower
// bound at the plot height). Widget code positions rail labels directly
// with it; the curve PAINTER — whose PdfGraphics origin is the box's
// bottom-left corner (PDF y-up) — converts with `plotHeight − yFor(value)`.
import '../domain/temperature_range.dart';
import 'pdf_layout.dart';

/// The left rail's width (the scale-label column) in pt.
const double pdfRailWidth = 58;

/// The printable width of one landscape A4 page (842 pt) with the
/// generator's 28 pt page margin on both sides — the full width the
/// scaffold (rail + 40 columns) lays out into.
const double pdfPrintableWidth = 842 - 2 * 28;

/// One day column's width in pt: the printable width minus the rail,
/// divided by the paper sheet's column count (the layout planner's
/// [defaultMaxDaysPerPage], imported — not re-declared — so the drawn
/// column count and the page plan cannot drift).
final double pdfColumnWidth =
    (pdfPrintableWidth - pdfRailWidth) / defaultMaxDaysPerPage;

/// The x of the left edge of [windowDayIndex]'s day column (window-relative
/// day index, 0-based), in scaffold coordinates.
///
/// Coordinate space: these helpers return RAIL-relative grid x (rail +
/// column grid across the printable width — full-scaffold/widget space),
/// NOT painter space: the curve painter's canvas starts after the rail
/// and re-derives its own arithmetic at cycle_pdf.dart's
/// `_columnCenterX`.
double pdfColumnLeft(int windowDayIndex) =>
    pdfRailWidth + windowDayIndex * pdfColumnWidth;

/// The x of the center of [windowDayIndex]'s day column — where a curve
/// dot, its ring/arrow marks and a row cell's text center. Same
/// rail-relative grid space as [pdfColumnLeft] (never painter space).
double pdfColumnCenter(int windowDayIndex) =>
    pdfRailWidth + (windowDayIndex + 0.5) * pdfColumnWidth;

/// The x of the RIGHT edge of the whole grid (rail + every column) — the
/// wrapping containers' shared right boundary.
double get pdfGridRightEdge =>
    pdfRailWidth + defaultMaxDaysPerPage * pdfColumnWidth;

/// The temperature scale's label convention: EVERY scale label carries the
/// unit itself ("37,5 °C", see [_labelText]) — and because the unit lives
/// on every number, the scaffold carries no separate temperature caption
/// row: the curve block is plot-only (the former caption row above the
/// plot is removed) and the temperature naming lives on the numeric value
/// row's rail legend "Temperatur in °C" BELOW the plot (cycle_pdf.dart's
/// value row). The app chart's rail renders the
/// identical label convention (lib/ui/cycle.dart's frozen rail,
/// temperature-scale slot) — the two implementations are deliberately
/// separate (pdf_axis labels the PDF rail, the chart rail renders its own
/// labels), so keep the unit-suffix styling in sync by eye on both sides.
///
/// RAIL WIDTH: the suffix needs no wider rail — the widest label
/// ("37,5 °C") still fits comfortably into [pdfRailWidth] at the rail's
/// label size (~21 pt at 5.2 pt type, right-aligned inside 58 pt with the
/// 2/3 pt insets), so rail + 40 columns keep filling the printable width
/// exactly (see the invariant test in test/pdf/pdf_axis_test.dart).
const String pdfScaleUnit = '°C';

/// One label/grid-line slot of the temperature scale: the °C value, its y
/// in the plot (PDF y-up, see the file header) and — labels only — its
/// German decimal-comma text.
final class PdfAxisLine {
  const PdfAxisLine(this.value, this.y);

  final double value;
  final double y;
}

final class PdfAxisLabel extends PdfAxisLine {
  const PdfAxisLabel(super.value, super.y, this.text);

  /// The label text, German decimal comma with the °C unit on every label
  /// ("37,5 °C"; whole degrees plain but suffixed too: "38 °C").
  final String text;
}

/// The fixed y scale of the curve plot: maps °C values onto the plot's
/// height like the chart (fixed window, never rescaled — owner decision,
/// see TemperatureRange). y runs DOWN from the plot's top edge (see the
/// file header for the painter-conversion convention).
final class PdfCurveAxis {
  const PdfCurveAxis({required this.range, required this.plotHeight});

  /// The settings-driven display range (the model's `temperatureRange`).
  final TemperatureRange range;

  /// The curve plot's drawable height in pt. The scale labels live in the
  /// rail of exactly this height.
  final double plotHeight;

  /// The y of [value] in the plot, CLAMPED to the plot bounds — drawing
  /// calls may pass off-scale values without escaping the box.
  double yFor(double value) {
    var y = range.max - value; // upper bound → 0 (top edge)
    if (y < 0) y = 0;
    if (y > range.span) y = range.span;
    return y / range.span * plotHeight;
  }

  /// The 0.1 °C graduation lines inside the window, both bounds inclusive
  /// (the paper form graduations every tenth of a degree).
  List<PdfAxisLine> gridLines() {
    // Integer tenths: addition-drift-free grid positions.
    final firstTenth = (range.min * 10).ceil();
    final lastTenth = (range.max * 10).floor();
    return [
      for (var t = firstTenth; t <= lastTenth; t++)
        PdfAxisLine(t / 10, yFor(t / 10)),
    ];
  }

  /// The scale labels in the rail: every 0.5 °C step inside the window,
  /// plus the window's own bounding values (a bound between two steps
  /// still gets its line — the paper labels the window edges).
  /// Top-down (the reading order of the label column).
  List<PdfAxisLabel> axisLabels() {
    // Integer halves: addition-drift-free label positions.
    final values = <double>{};
    final firstHalf = (range.min * 2).ceil();
    final lastHalf = (range.max * 2).floor();
    for (var t = firstHalf; t <= lastHalf; t++) {
      values.add(t / 2);
    }
    values
      ..add(range.min)
      ..add(range.max);
    final sorted = values.toList()..sort((a, b) => b.compareTo(a));
    return [for (final v in sorted) PdfAxisLabel(v, yFor(v), _labelText(v))];
  }
}

/// The German decimal-comma label text with the unit on EVERY label: whole
/// degrees without decimals ("38 °C"), fractions with one comma decimal
/// ("37,5 °C", "36,2 °C") — the suffix rides on the whole scale like on the
/// paper sheet's margin ("36.5 °C" app-side style is locale-consistent
/// separately; this document is German).
String _labelText(double value) {
  final whole = (value.truncateToDouble()) == value
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceFirst('.', ',');
  return '$whole $pdfScaleUnit';
}
