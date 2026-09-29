// The PDF document generation layer: turns a [PdfExportModel] into the
// PDF byte stream the file_transfer seam saves.
//
// - ONE CYCLE PER PAGE: the pure layout planner (pdf_layout.dart) decides
//   the (cycle -> pages) split; this builder draws one planned window per
//   physical page, continuation pages repeat the identical scaffold
//   ("Blatt k/n").
// - PAPER-FORM SCAFFOLD: left rail with rail legends, 40 day columns, the
//   row stack top-down: day numbers (calendar cycle days), dates (month +
//   year on every first-of-month column), the bleeding bands, the CURVE
//   BLOCK (the plot with the in-plot glyph row seam), the numeric
//   temperature values below the plot (out-of-range readings lose no
//   data), the recorded measurement times (vertical, narrow-column
//   convention), then disturbance/cervix/pain and the rotated notes area.
//   Columns the window does not track stay empty. The sex X marks, the
//   mucus sign letters, the mucus peak dot, the Mittelschmerz M and the
//   evaluation day numbers render INSIDE the plot (paper-form parity with
//   the cycle tab — no duplicated recording rows), placed by the shared
//   chart-marks mapper.
// - The TEMPERATURE CURVE and the evaluation overlay geometry (rings
//   around circled candidates, arrow-up glyphs hanging clear below their
//   dots, the solid peak dot, the user-placed SUZ bar+arrow glyphs) are
//   painted here from draw lists composed ONCE by lib/pdf/pdf_curve.dart
//   — this file never re-derives a rule; the overlay's 1–6 low numbers
//   ride the same draw list onto the in-plot glyph seam. The computed
//   suzBegins renders as the suggestion line: a thin solid vertical line
//   plus the rule letter D/E, visually distinct from the user marks; the
//   chart draws only user marks, the PDF is for teacher/doctor and adds
//   the line.
// - INDEX SPACES: the overlay's day indexes are calendar offsets from the
//   cycle start; lib/pdf/pdf_curve.dart maps them onto the page window's
//   tracked positions (marks on untracked gap days drop out) and the
//   scaffold draws window-relative positions only.
// - VERTICAL NOTES: every tracked day column carries its note text rotated
//   90° into the column's footer area (multi-line notes folded to one
//   line, note longer than the area clips — accepted limit, see
//   docs/dev-notes.md "Paper-form PDF export" for the layout decisions and
//   the print-friendliness rule).
// - HEADER PER PAGE: identifying facts (anonymize rules — [pdfHeaderFacts])
//   plus the cumulative ones read at the printed cycle (print idempotency),
//   the cycle's observation window and the export date.
// - DOCUMENT LANGUAGE: German (the PDF replaces the German paper form);
//   the app's UI strings stay l10n-driven. Text is drawn with the bundled
//   Noto Sans TTF (beyond Latin-1 coverage; symbols outside coverage draw
//   as the notdef box).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/date_only.dart';
import '../domain/models.dart';
import '../domain/pdf_export_model.dart';
import '../ui/chart_marks.dart'
    show
        chartDayMarks,
        chartMarkHaloStrokeWidth,
        chartMarkRowVisible,
        dayNumbersRowCenterOffsetK,
        dayNumbersRowVisible,
        mucusRowCenterOffsetK,
        mRowCenterOffsetK,
        peakDotCenterOffsetK,
        sexGlyphBoxWidth,
        sexRowCenterOffsetK;
import '../ui/cycle_curve.dart' show ignoredTemperatureAlpha;
import '../ui/suz_glyph.dart'
    show suzArrowTopInsetDegrees, suzBarHangSpanDegrees;
import 'pdf_axis.dart';
import 'pdf_curve.dart';
import 'pdf_layout.dart';
import 'pdf_symbols.dart';

/// Per-export generation options. `anonymized` is the per-export toggle:
/// NOT persisted anywhere, it decides the identifying values' fate for
/// THIS document only (see [pdfHeaderFacts]).
final class PdfExportOptions {
  const PdfExportOptions({required this.anonymized, this.exportDate});

  /// Hide name + birth date in the document regardless of the stored
  /// settings values, and mark the document "anonymisiert".
  final bool anonymized;

  /// The export date printed in the header; defaults to the wall clock at
  /// generation time (tests may fix it through their stubs).
  final DateTime? exportDate;
}

/// The header facts as ready-to-label rows, one record per line: the pure
/// mapping from model + per-cycle index + per-export anonymize toggle to
/// the paper-form info (every missing value becomes the "—" convention).
///
/// The cumulative facts are read at [cycleIndex] — the printed cycle's
/// point of view, never the whole record's, so a page shows the state as
/// of ITS cycle (print idempotency). The anonymized mapping hides name and
/// birth date and adds the marker line; the OBSERVATION WINDOW is NOT
/// anonymized — it belongs to the evaluation, not the person.
List<({String label, String value})> pdfHeaderFacts({
  required PdfExportModel model,
  required bool anonymized,
  required int cycleIndex,
  ({DateTime first, DateTime last})? cycleWindow,
}) {
  final birthDate = model.birthDate == null
      ? null
      : _formatDate(DateOnly.normalize(model.birthDate!));
  final earliest =
      model.earliestFirstHigherCycleDays[cycleIndex].afterMucusPeak ??
      model.earliestFirstHigherCycleDays[cycleIndex].any;
  final shortest = model.shortestCycleLengths[cycleIndex];
  return [
    if (anonymized) (label: 'Anonymisierung', value: 'anonymisiert'),
    (label: 'Name', value: anonymized ? 'anonymisiert' : (model.name ?? '—')),
    (label: 'Geburtsdatum', value: anonymized ? '—' : (birthDate ?? '—')),
    (label: 'Beobachtete Zyklen', value: '${model.ordinalOf(cycleIndex)}'),
    (
      label: 'Kürzester Zyklus',
      value: shortest == null ? '—' : '$shortest Tage',
    ),
    (
      label: 'Früheste erste höhere Messung',
      value: earliest == null ? '—' : 'Zyklustag $earliest',
    ),
    if (cycleWindow != null)
      (
        label: 'Zykluszeitraum',
        value:
            '${_formatDate(DateOnly.normalize(cycleWindow.first))} – '
            '${_formatDate(DateOnly.normalize(cycleWindow.last))}',
      ),
  ];
}

/// The app identifier printed in every page header (German wording).
const String pdfAppIdentifier = 'Zyklus-App';

/// The scaffold's rail legends — the pure pin-able strings the private row
/// builders place into the left rail. The curve block has no caption row:
/// the °C lives in every scale label and the temperature naming lives on
/// [pdfRailCaptionTemperatureValues].
const String pdfRailCaptionDayNumbers = 'Zyklustag';
const String pdfRailCaptionDates = 'Datum';
const String pdfRailCaptionTemperatureValues = 'Temperatur in °C';

/// The bundled asset font (the app loads the bytes via rootBundle before
/// handing them to the builder; host smoke scripts read the file directly).
const String pdfFontAsset = 'assets/fonts/NotoSans-Regular.ttf';

/// The save filename for one export: the same "cycle_app_export" base as
/// the JSON document, suffixed with the ISO export date so successive
/// exports keep separate files, extension .pdf.
String pdfExportFileName(DateTime exportDate) =>
    'cycle_app_export_${_formatIsoDate(exportDate)}.pdf';

/// ISO date ('yyyy-MM-dd') — the filename suffix form.
String _formatIsoDate(DateTime date) =>
    DateOnly.normalize(date).toIso8601String().substring(0, 10);

/// Generates the PDF export document.
///
/// `fontBytes` carries the bundled TTF's bytes (registered as the
/// document's base font). `compress` is a generation flag: production
/// keeps the default; the smoke tests flip it to count uncompressed page
/// markers. Page count and window layout follow the layout planner exactly.
Future<List<int>> generatePdfBytes({
  required PdfExportModel model,
  required List<int> fontBytes,
  required PdfExportOptions options,
  bool compress = true,
}) async {
  final ttf = pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(fontBytes)));
  final doc = pw.Document(
    compress: compress,
    theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
  );

  // The planner skips day counts of 0, silently dropping the sheet — but
  // an empty cycle is still export-selected, so it counts as one
  // placeholder day.
  final dayCounts = [
    for (final evaluation in model.cycles)
      evaluation.cycle.days.isEmpty ? 1 : evaluation.cycle.days.length,
  ];
  final plan = planCyclePages(dayCounts);
  final windowsPerCycle = <int, int>{};
  for (final window in plan) {
    windowsPerCycle[window.cycleIndex] =
        (windowsPerCycle[window.cycleIndex] ?? 0) + 1;
  }
  final exportDate = DateOnly.normalize(options.exportDate ?? DateTime.now());

  for (final window in plan) {
    final evaluation = model.cycles[window.cycleIndex];
    final cycleDays = evaluation.cycle.days;
    final emptyCycle = cycleDays.isEmpty;
    // The placeholder feeds page planning and the form grid only.
    final windowDays = emptyCycle
        ? [DailyEntry(date: DateOnly.normalize(evaluation.cycle.startDate))]
        : cycleDays
              .sublist(
                window.firstDayIndex,
                window.firstDayIndex + window.dayCount,
              )
              .toList(growable: false);
    final drawing = pdfCurveDrawing(
      cycle: evaluation,
      overlay: model.overlays[window.cycleIndex],
      range: model.temperatureRange,
      windowFirstIndex: window.firstDayIndex,
      windowDayCount: window.dayCount,
      computedSuz: (
        suzBegins: evaluation.suzBegins,
        suzRule: evaluation.suzRule,
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(_pageMargin),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _cycleHeader(
              ordinal: model.ordinalOf(window.cycleIndex),
              pageInCycle: window.pageIndexInCycle,
              pagesInCycle: windowsPerCycle[window.cycleIndex] ?? 1,
              exportDate: exportDate,
              facts: pdfHeaderFacts(
                model: model,
                anonymized: options.anonymized,
                cycleIndex: window.cycleIndex,
                cycleWindow: emptyCycle
                    ? null
                    : (first: cycleDays.first.date, last: cycleDays.last.date),
              ),
            ),
            pw.SizedBox(height: 4),
            _paperFormGrid(
              // The page window's day-number labels key on the cycle's
              // normalized start day (calendar offsets — never the page
              // window's tracked positions).
              cycleStart: DateOnly.normalize(evaluation.cycle.startDate),
              windowDays: windowDays,
              drawing: drawing,
              axis: PdfCurveAxis(
                range: model.temperatureRange,
                plotHeight: _curvePlotHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  return doc.save();
}

// ---------------------------------------------------------------------------
// Page geometry: landscape A4 (842 × 595 pt) with the 28 pt margins. The
// header block is fixed; the scaffold's rows sum against the printable
// height, the rotated notes area absorbing the remainder (the only flex
// child — so the grid never overflows the page).
// ---------------------------------------------------------------------------

const double _pageMargin = 28;
const double _headerHeight = 58;
const double _dayNumberRowHeight = 10;
const double _dateRowHeight = 14;
const double _bleedingRowHeight = 12;
const double _tempValueRowHeight = 12;

/// The curve block's painted plot region (fine scale + curve + overlay
/// marks + the in-plot glyph rows: sex X, mucus letters, peak dot, the
/// Mittelschmerz M and the evaluation day numbers).
const double _curvePlotHeight = 185;

/// The below-plot strip rows.
const double _timeRowHeight = 15;
const double _disturbanceRowHeight = 14;
const double _cervixRowHeight = 10;
const double _painRowHeight = 10;

final pw.TextStyle _label = const pw.TextStyle(fontSize: 6.5);
final pw.TextStyle _tiny = const pw.TextStyle(fontSize: 5.2);
final pw.TextStyle _tinyAccent = const pw.TextStyle(
  fontSize: 5.2,
  fontWeight: pw.FontWeight.bold,
  color: PdfColor.fromInt(0xFF3556A8),
);

final PdfColor _ink = PdfColor.fromInt(0x1B1B1F);
final PdfColor _markAccent = PdfColor.fromInt(0xFF3556A8);
final PdfColor _bleedingRed = PdfColor.fromInt(0xFFC0392B);
final PdfColor _gridGray = PdfColor.fromInt(0xFFC4C4C4);
final PdfColor _ruleGray = PdfColor.fromInt(0xFF8A8A8A);

/// The paper-white the halo backings paint with: a backing erases the ink
/// behind its glyph — the stand-in for the screen's stroke halo (why a
/// stroke halo is unavailable: docs/dev-notes.md, "Paper-form PDF
/// export").
final PdfColor _paper = PdfColor.fromInt(0xFFFFFFFF);

/// The weekend column band's shade: all-equal LIGHT GRAY — made
/// print-safe (never a pale COLOR, which would collapse in B/W
/// printing), near-white enough to keep every letter/mark legible, and
/// lighter than the grid gray (196) so the grid stays visible on top of
/// it (band 230, ink 27, accent gray ~85).
final PdfColor pdfWeekendShade = PdfColor.fromInt(0xFFE6E6E6);

const pw.BorderSide _hairline = pw.BorderSide(width: 0.35);

pw.Widget _cycleHeader({
  required int ordinal,
  required int pageInCycle,
  required int pagesInCycle,
  required DateTime exportDate,
  required List<({String label, String value})> facts,
}) {
  const bold = pw.TextStyle(fontSize: 10.5);
  const normal = pw.TextStyle(fontSize: 6.4);
  final continuation = pagesInCycle > 1
      ? ' — Blatt ${pageInCycle + 1}/$pagesInCycle'
      : '';
  return pw.SizedBox(
    height: _headerHeight,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(pdfAppIdentifier, style: bold),
              pw.SizedBox(height: 3),
              pw.Text('Zyklus $ordinal$continuation', style: bold),
              pw.SizedBox(height: 3),
              pw.Text(
                'Exportiert am ${_formatDate(exportDate)}',
                style: normal,
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final fact in facts)
                pw.Text('${fact.label}: ${fact.value}', style: normal),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One page window's paper-form scaffold. The raster is ALWAYS the full
/// 40 columns (rail + columns), labels only in the window's tracked
/// columns — the day-number labels count CALENDAR offsets from the cycle's
/// start day, the other rows read the window's tracked days.
pw.Widget _paperFormGrid({
  required DateTime cycleStart,
  required List<DailyEntry> windowDays,
  required PdfCurveDrawing drawing,
  required PdfCurveAxis axis,
}) {
  // The window's weekend columns: every scaffold row paints its band in
  // exactly these columns, so the band runs through the FULL sheet height.
  final weekend = weekendPositions(windowDays);
  return pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _dayNumberRow(cycleStart, windowDays, weekend),
        _dateRow(windowDays.length, windowDays, weekend),
        _bleedingRow(windowDays.length, windowDays, weekend),
        // The strip ends at bleeding: the Mittelschmerz M and the day
        // numbers render inside the curve block's plot, like the sex/mucus
        // marks (paper-form parity with the cycle tab's in-plot glyph rows).
        _curveBlock(windowDays, drawing, axis, weekend),
        // The numeric values render BELOW the plot, right above the
        // measured times.
        _tempValueRow(windowDays.length, windowDays, weekend),
        _timeRow(windowDays.length, windowDays, weekend),
        _disturbanceRow(windowDays.length, windowDays, weekend),
        _cervixRow(windowDays.length, windowDays, weekend),
        _painRow(windowDays.length, windowDays, weekend),
        // The rotated notes area absorbs the remaining page height.
        pw.Expanded(
          child: _paperRow(
            height: 0,
            railCaption: 'Notizen',
            windowDayCount: windowDays.length,
            weekend: weekend,
            cell: (position) => windowDays[position].notes == null
                ? null
                : _centerRotated(joinedNoteText(windowDays[position].notes!)),
          ),
        ),
      ],
    ),
  );
}

/// One scaffold row: the fixed rail slot plus the 40 fixed-width columns
/// (a hairline between columns, a hairline on the row's top edge — the
/// paper's horizontal rules). Empty cells keep the column rhythm.
pw.Widget _paperRow({
  required double height,
  required String? railCaption,
  required int windowDayCount,
  required List<int> weekend,
  required pw.Widget? Function(int position) cell,
}) {
  return pw.Container(
    height: height,
    decoration: const pw.BoxDecoration(border: pw.Border(top: _hairline)),
    child: _gridColumns(
      railCaption: railCaption,
      windowDayCount: windowDayCount,
      weekend: weekend,
      cell: cell,
    ),
  );
}

/// The 40 fixed columns behind every row (with the rail at their left).
/// A weekend column's container keeps its band UNDER the cell content;
/// untracked columns never shade.
pw.Widget _gridColumns({
  required String? railCaption,
  required int windowDayCount,
  required List<int> weekend,
  required pw.Widget? Function(int position) cell,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(
        width: pdfRailWidth,
        child: railCaption == null
            ? null
            : pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 1,
                ),
                child: pw.Align(
                  alignment: pw.Alignment.topLeft,
                  child: pw.Text(
                    railCaption,
                    style: _tiny,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
              ),
      ),
      pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(right: _hairline)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < defaultMaxDaysPerPage; k++)
              pw.SizedBox(
                width: pdfColumnWidth,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: const pw.Border(left: _hairline),
                    color: weekend.contains(k) ? pdfWeekendShade : null,
                  ),
                  child: k < windowDayCount ? cell(k) : null,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The day-number labels: offset 0 from the cycle's start opens the cycle
/// ("1. Tag"), otherwise the offset counts cycle days ("N."). Pure and
/// exported so the snapshot pins the rule without the pdf package.
String cycleDayNumberLabel(int calendarOffset) =>
    calendarOffset == 0 ? '1. Tag' : '${calendarOffset + 1}.';

/// The day-number row labels the CALENDAR cycle days, so an interior
/// untracked gap keeps its day numbers and the "1. Tag" sits only on the
/// day the cycle start mark anchored — even when that mark lies before
/// the cycle's first TRACKED day. Continuation pages derive their numbers
/// from the dates the same way.
pw.Widget _dayNumberRow(
  DateTime cycleStart,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _dayNumberRowHeight,
    railCaption: pdfRailCaptionDayNumbers,
    windowDayCount: windowDays.length,
    weekend: weekend,
    cell: (position) => pw.Center(
      child: pw.Text(
        cycleDayNumberLabel(
          DateOnly.daysBetween(windowDays[position].date, cycleStart),
        ),
        style: _tiny,
        textAlign: pw.TextAlign.center,
      ),
    ),
  );
}

/// The date row: the calendar day of month; every FIRST-OF-MONTH column
/// carries the month name + year (stacked, tiny) so a multi-month window
/// still reads right. The rail legend is plain "Datum": every window is at
/// most 40 days and thus necessarily contains a first-of-month column, and
/// a legend date could mislead on multi-month windows (the year's home is
/// the header's "Zykluszeitraum" fact).
pw.Widget _dateRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _dateRowHeight,
    railCaption: pdfRailCaptionDates,
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) => _dateCell(windowDays[position].date),
  );
}

pw.Widget _dateCell(DateTime date) {
  const tiny = pw.TextStyle(fontSize: 5);
  if (date.day != 1) {
    return pw.Center(
      child: pw.Text(
        '${date.day}.',
        style: tiny,
        textAlign: pw.TextAlign.center,
      ),
    );
  }
  return pw.Center(
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          _monthAbbreviation(date.month),
          style: tiny,
        ), // the year line fits only at the smallest size
        pw.Text('${date.year}', style: const pw.TextStyle(fontSize: 4.6)),
      ],
    ),
  );
}

const _germanMonthAbbreviations = [
  'Jan',
  'Feb',
  'Mär',
  'Apr',
  'Mai',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Okt',
  'Nov',
  'Dez',
];

String _monthAbbreviation(int month) => _germanMonthAbbreviations[month - 1];

/// The bleeding row: bottom-anchored red band pieces per the shared
/// symbol's semantics (spotting dotted in the bottom quarter; heavier
/// levels a solid fraction) — positioned containers in the cell's Stack.
pw.Widget _bleedingRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _bleedingRowHeight,
    railCaption: 'Blutung',
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) {
      final fill = bleedingFill(windowDays[position].bleeding);
      if (fill == null) return null;
      final bandHeight = _bleedingRowHeight * fill.heightFraction;
      if (!fill.dotted) {
        return pw.Stack(
          children: [
            pw.Positioned(
              left: 0.5,
              right: 0.5,
              bottom: 0,
              child: pw.Container(height: bandHeight, color: _bleedingRed),
            ),
          ],
        );
      }
      return pw.Stack(
        children: [
          pw.Positioned(
            left: 0.5,
            right: 0.5,
            bottom: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 4; i++)
                  pw.Container(
                    width: 2.2,
                    height: 2.2,
                    decoration: pw.BoxDecoration(
                      color: _bleedingRed,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The numeric temperature value row, below the plot: the measured value
/// with one German comma decimal, "—" unmeasured.
pw.Widget _tempValueRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _tempValueRowHeight,
    railCaption: pdfRailCaptionTemperatureValues,
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) => pw.Center(
      child: pw.Text(
        windowDays[position].bbtC == null
            ? '—'
            : windowDays[position].bbtC!
                  .toStringAsFixed(1)
                  .replaceFirst('.', ','),
        style: _tiny,
        textAlign: pw.TextAlign.center,
      ),
    ),
  );
}

/// The curve block: the painted plot row with the in-plot glyph seam (rail
/// = scale labels, day columns = the painter's canvas + the positioned
/// glyph widgets). The block's boundaries are the plot's own hairlines.
pw.Widget _curveBlock(
  List<DailyEntry> windowDays,
  PdfCurveDrawing drawing,
  PdfCurveAxis axis,
  List<int> weekend,
) {
  return pw.Container(
    height: _curvePlotHeight,
    decoration: const pw.BoxDecoration(border: pw.Border(top: _hairline)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // The rail: the scale labels positioned exactly at their grid y.
        pw.SizedBox(
          width: pdfRailWidth,
          child: pw.Stack(
            children: [
              for (final label in axis.axisLabels())
                pw.Positioned(
                  left: 2,
                  right: 3,
                  top: (axis.yFor(label.value) - 3.4).clamp(
                    0.0,
                    _curvePlotHeight - 7,
                  ),
                  child: pw.Text(
                    label.text,
                    style: _tiny,
                    textAlign: pw.TextAlign.right,
                  ),
                ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.CustomPaint(
            size: PdfPoint(pdfGridRightEdge - pdfRailWidth, _curvePlotHeight),
            painter: (canvas, size) => _paintCurveBlock(
              canvas,
              size.x,
              size.y,
              drawing,
              axis,
              weekend,
            ),
            child: pw.Stack(
              children: [
                _inPlotChartMarks(windowDays, drawing, axis),
                // The computed SUZ's rule letter rides its line's
                // column (a positioned widget above the geometry).
                if (drawing.suzLine case final line?)
                  pw.Positioned(
                    left: (line.x * pdfColumnWidth - 4).clamp(
                      0.0,
                      defaultMaxDaysPerPage * pdfColumnWidth - 8,
                    ),
                    top: 0,
                    child: pw.Text(line.ruleLetter ?? 'S', style: _tinyAccent),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The in-plot glyph rows on the stack seam: one X per recorded sex timing
/// at its column slot (1/6 · 1/2 · 5/6), the mucus sign letter (+ the S
/// quality superscript) centered in the day column, the peak dot at the
/// peak day's column center, the Mittelschmerz M under its column and the
/// evaluation day numbers — all placed by the shared mapper (chartDayMarks:
/// the M rides painMittelschmerz, the numbers feed through from
/// PdfCurveDrawing.lowNumbers). Each row hides independently with the
/// settings range (chartMarkRowVisible / the numbers' bottom rule
/// dayNumbersRowVisible: a narrow range pushes a row's center past the plot
/// edge). The top-anchored rows pitch DOWN from the plot's top edge —
/// `axis.yFor(value)` runs down from it (pdf_axis y convention), half the
/// glyph box subtracted to center the ink; the numbers are the one
/// BOTTOM-anchored row and center on `yFor(min + offset)`.
pw.Widget _inPlotChartMarks(
  List<DailyEntry> windowDays,
  PdfCurveDrawing drawing,
  PdfCurveAxis axis,
) {
  final sexVisible = chartMarkRowVisible(sexRowCenterOffsetK, axis.range);
  final peakVisible = chartMarkRowVisible(peakDotCenterOffsetK, axis.range);
  final mucusVisible = chartMarkRowVisible(mucusRowCenterOffsetK, axis.range);
  final mVisible = chartMarkRowVisible(mRowCenterOffsetK, axis.range);
  final numbersVisible = dayNumbersRowVisible(axis.range);
  if (!sexVisible &&
      !peakVisible &&
      !mucusVisible &&
      !mVisible &&
      !numbersVisible) {
    return pw.SizedBox();
  }

  final marks = chartDayMarks(
    {for (var i = 0; i < windowDays.length; i++) i: windowDays[i]},
    peakIndexes: drawing.peakIndexes,
    numbers: drawing.lowNumbers,
  );

  Iterable<pw.Widget> placements() sync* {
    for (var i = 0; i < windowDays.length; i++) {
      final record = marks[i];
      if (record == null) continue;
      if (sexVisible) {
        for (final slot in record.sexSlots) {
          yield _haloedSlot(
            left:
                (i + slot.columnFraction) * pdfColumnWidth -
                sexGlyphBoxWidth / 2,
            slotWidth: sexGlyphBoxWidth,
            top:
                axis.yFor(axis.range.max - sexRowCenterOffsetK) -
                _glyphBoxHeight / 2,
            ink: pw.Text('X', style: _label),
          );
        }
      }
      if (peakVisible && record.mucusPeak) {
        yield pw.Positioned(
          left: i * pdfColumnWidth + (pdfColumnWidth - _peakHaloSize) / 2,
          top:
              axis.yFor(axis.range.max - peakDotCenterOffsetK) -
              _peakHaloSize / 2,
          child: pw.Stack(
            alignment: pw.Alignment.center,
            children: [
              pw.Container(
                width: _peakHaloSize,
                height: _peakHaloSize,
                decoration: pw.BoxDecoration(
                  color: _paper,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.Container(
                width: _peakDotSize,
                height: _peakDotSize,
                decoration: pw.BoxDecoration(
                  color: _markAccent,
                  shape: pw.BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      }
      if (mucusVisible) {
        if (record.mucus case final display?) {
          yield _haloedSlot(
            left: i * pdfColumnWidth,
            slotWidth: pdfColumnWidth,
            top:
                axis.yFor(axis.range.max - mucusRowCenterOffsetK) -
                _glyphBoxHeight / 2,
            haloWidth: _mucusHaloBox,
            ink: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                // Base glyph + raised superscript: a composed row (pdf's
                // RichText baseline offset drops the raised token at tiny
                // sizes).
                if (display.symbol case final symbol?)
                  pw.Text(symbol, style: _label),
                if (display.superscript case final quality?)
                  pw.Transform.translate(
                    offset: PdfPoint(0, 2.6),
                    child: pw.Text(quality, style: _mucusQualityStyle),
                  ),
              ],
            ),
          );
        }
      }
      if (mVisible && record.mittelschmerz) {
        yield _haloedSlot(
          left: i * pdfColumnWidth,
          slotWidth: pdfColumnWidth,
          top:
              axis.yFor(axis.range.max - mRowCenterOffsetK) -
              _glyphBoxHeight / 2,
          ink: pw.Text('M', style: _label),
        );
      }
      if (numbersVisible) {
        if (record.dayNumber case final number?) {
          yield _haloedSlot(
            left: i * pdfColumnWidth,
            slotWidth: pdfColumnWidth,
            top:
                axis.yFor(axis.range.min + dayNumbersRowCenterOffsetK) -
                _glyphBoxHeight / 2,
            ink: pw.Text('$number', style: _tinyAccent),
          );
        }
      }
    }
  }

  return pw.Stack(children: [...placements()]);
}

/// One positioned glyph slot: the paper-colored halo box under the ink —
/// `pw`'s text widgets cannot paint a stroke pass, so the box stands in for
/// the screen's stroke halo. Box and ink share the slot's center (both are
/// non-positioned Stack children of the one slot widget), so their
/// placement cannot drift; the box overprints grid, band and curve ink
/// locally exactly where a halo would (accepted).
pw.Widget _haloedSlot({
  required double left,
  required double slotWidth,
  required double top,
  required pw.Widget ink,
  double haloWidth = _glyphHaloBox,
}) {
  return pw.Positioned(
    left: left,
    top: top,
    child: pw.SizedBox(
      width: slotWidth,
      height: _glyphBoxHeight,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        // The raised mucus quality token may poke past the slot — keep it
        // unclipped.
        overflow: pw.Overflow.visible,
        children: [
          pw.Container(
            width: haloWidth,
            height: _glyphBoxHeight,
            color: _paper,
          ),
          ink,
        ],
      ),
    ),
  );
}

/// The in-plot glyph box (X / letter cells centered within), pt.
const double _glyphBoxHeight = 8;

/// The peak dot's diameter, pt.
const double _peakDotSize = 4.6;

/// The halo behind one small in-plot text glyph (X / M / day number), pt.
const double _glyphHaloBox = 8;

/// The mucus letter (+ its raised quality token) rides a wider halo box, pt.
const double _mucusHaloBox = 12;

/// The peak dot's halo circle: the dot outgrown by the shared halo stroke
/// width on both sides — the screen halo circle's diameter rule.
const double _peakHaloSize = _peakDotSize + 2 * chartMarkHaloStrokeWidth;

/// The mucus quality tokens ride raised at this smaller size.
final pw.TextStyle _mucusQualityStyle = const pw.TextStyle(fontSize: 4.8);

/// All painted geometry of the plot region: the 0.1 °C graduation (light),
/// the dashed window bounds, the column hairlines, the curve (dots +
/// range-clipped pieces, dimmed over ignoreTemperature-marked days), the
/// dashed R10 baseline pieces, the candidate marks (rings on circled
/// dots, arrow-up glyphs below arrowed ones) and the SUZ glyphs.
void _paintCurveBlock(
  PdfGraphics canvas,
  double plotWidth,
  double plotHeight,
  PdfCurveDrawing drawing,
  PdfCurveAxis axis,
  List<int> weekend,
) {
  // The painter's PdfGraphics origin is the box's bottom-left (PDF y-up),
  // while the axis returns distances DOWN from the top — every geometric y
  // goes through this conversion.
  double yOf(double value) => plotHeight - axis.yFor(value);

  // The weekend bands FIRST — everything above stays in front of the shade.
  canvas.setFillColor(pdfWeekendShade);
  for (final k in weekend) {
    canvas.drawRect(k * pdfColumnWidth, 0, pdfColumnWidth, plotHeight);
    canvas.fillPath();
  }

  // 0.1 °C graduation lines (the paper's fine scale).
  canvas.setStrokeColor(_gridGray);
  canvas.setLineWidth(0.25);
  for (final line in axis.gridLines()) {
    canvas.drawLine(0, yOf(line.value), plotWidth, yOf(line.value));
    canvas.strokePath();
  }

  // Column hairlines through the plot region.
  canvas.setStrokeColor(_gridGray);
  canvas.setLineWidth(0.35);
  for (var k = 0; k <= defaultMaxDaysPerPage; k++) {
    canvas.drawLine(k * pdfColumnWidth, 0, k * pdfColumnWidth, plotHeight);
    canvas.strokePath();
  }

  void dashed(double x1, double y1, double x2, double y2) {
    canvas.setLineDashPattern(const [2.2, 2.2]);
    canvas.drawLine(x1, y1, x2, y2);
    canvas.strokePath();
    canvas.setLineDashPattern(const []);
  }

  canvas.setStrokeColor(_ruleGray);
  canvas.setLineWidth(0.5);
  dashed(0, plotHeight - 0.2, plotWidth, plotHeight - 0.2);
  dashed(0, 0.2, plotWidth, 0.2);

  // The curve's line pieces first (under the dots). DIMMING: the PDF
  // number operators carry no alpha (a PdfColor's alpha is dropped), so
  // ignoreTemperature dimming goes through an ExtGState applied while the
  // ignored piece draws, reset right after (same alpha constant as the
  // chart, so chart and export cannot drift).
  for (final piece in drawing.pieces) {
    if (piece.ignored) {
      canvas.setGraphicState(PdfGraphicState(opacity: ignoredTemperatureAlpha));
    }
    canvas.setStrokeColor(_ink);
    canvas.setLineWidth(piece.ignored ? 0.5 : 0.8);
    canvas.drawLine(
      (piece.startX + 0.5) * pdfColumnWidth,
      yOf(piece.startValue),
      (piece.endX + 0.5) * pdfColumnWidth,
      yOf(piece.endValue),
    );
    canvas.strokePath();
    if (piece.ignored) {
      canvas.setGraphicState(const PdfGraphicState(opacity: 1.0));
    }
  }

  // The R10 baseline pieces (dashed, accent color).
  canvas.setStrokeColor(_markAccent);
  canvas.setLineWidth(0.6);
  for (final baseline in drawing.baseline) {
    dashed(
      baseline.startX * pdfColumnWidth,
      yOf(baseline.value),
      baseline.endX * pdfColumnWidth,
      yOf(baseline.value),
    );
  }

  for (final dot in drawing.dots) {
    if (dot.ignored) {
      canvas.setGraphicState(PdfGraphicState(opacity: ignoredTemperatureAlpha));
    }
    canvas.setFillColor(_ink);
    pdfFillCircle(
      canvas,
      _columnCenterX(dot.index),
      yOf(dot.value),
      pdfCurveDotRadiusPt,
    );
    if (dot.ignored) {
      canvas.setGraphicState(const PdfGraphicState(opacity: 1.0));
    }
  }

  // Rings around the circled candidates — centered EXACTLY on the dot's
  // drawn position (the shared circle helper keeps the two aligned).
  canvas.setStrokeColor(_markAccent);
  canvas.setLineWidth(0.7);
  for (final ring in drawing.rings) {
    pdfStrokeCircle(canvas, _columnCenterX(ring.index), yOf(ring.value), 3.0);
  }

  // Arrow-up glyphs BELOW the arrow-marked dots — the tip sits clear of
  // the dot (drop carried on PdfArrowMark.tipDropPt).
  canvas.setFillColor(_markAccent);
  for (final arrow in drawing.arrows) {
    final x = _columnCenterX(arrow.index);
    final tipY = (yOf(arrow.value) - arrow.tipDropPt).clamp(8.0, plotHeight);
    canvas
      ..moveTo(x, tipY)
      ..lineTo(x - 3, tipY - 4)
      ..lineTo(x + 3, tipY - 4)
      ..closePath()
      ..fillPath();
    canvas.drawRect(x - 0.75, tipY - 8, 1.5, 5);
    canvas.fillPath();
  }

  // The user-placed SUZ marks drawn as the CYCLE CHART's glyph (same
  // shape, orientation and anchoring — constants shared via
  // suz_glyph.dart): a vertical bar hanging down from the plot's top
  // border plus the right-pointing arrow below it (arrow geometry mirrors
  // paintSuzArrowGlyph). Morning bars anchor at the column START, evening
  // bars at the column middle.
  for (final bar in drawing.suzBars) {
    final x = bar.x * pdfColumnWidth;
    // A hang beyond the window degenerates to the plot's full height.
    final barBottom =
        plotHeight - axis.yFor(axis.range.max - suzBarHangSpanDegrees);
    canvas
      ..setStrokeColor(_markAccent)
      ..setLineWidth(2)
      ..drawLine(x, plotHeight, x, barBottom)
      ..strokePath();
    // The arrow: base at the bar, centered on the arrow inset below the
    // top border.
    final anchorY =
        plotHeight - axis.yFor(axis.range.max - suzArrowTopInsetDegrees);
    canvas
      ..setFillColor(_markAccent)
      ..drawRect(x, anchorY - 1, 8, 2)
      ..fillPath();
    canvas
      ..moveTo(x + 15, anchorY)
      ..lineTo(x + 8, anchorY - 5.5)
      ..lineTo(x + 8, anchorY + 5.5)
      ..closePath()
      ..fillPath();
  }

  // The computed SUZ: a thin solid vertical line through the whole plot —
  // deliberately distinct from the user marks' bar+arrow glyph; the rule
  // letter is a positioned widget (kept out of the canvas-font path).
  if (drawing.suzLine case final line?) {
    canvas
      ..setStrokeColor(_ink)
      ..setLineWidth(0.6)
      ..drawLine(
        line.x * pdfColumnWidth,
        0,
        line.x * pdfColumnWidth,
        plotHeight,
      )
      ..strokePath();
  }
}

double _columnCenterX(int windowColumn) =>
    (windowColumn + 0.5) * pdfColumnWidth;

/// Fills a circle centered at (x, y) with the given radius.
///
/// SEMANTICS PIN: PdfGraphics.drawEllipse(x, y, r1, r2) draws an ellipse
/// CENTERED on (x, y) with r1/r2 as HALF-axes — corner+size arithmetic
/// drifts every circle off-center and double its size (pinned byte-level
/// in test/pdf/pdf_circle_geometry_test.dart).
void pdfFillCircle(PdfGraphics canvas, double x, double y, double radius) {
  canvas
    ..drawEllipse(x, y, radius, radius)
    ..fillPath();
}

/// Strokes a circle centered at (x, y) with the given radius (see
/// [pdfFillCircle] for the drawEllipse semantics pin).
void pdfStrokeCircle(PdfGraphics canvas, double x, double y, double radius) {
  canvas
    ..drawEllipse(x, y, radius, radius)
    ..strokePath();
}

/// The measurement-time row: the recorded time-of-day as a vertical
/// "HH:mm" (the ~18 pt paper column cannot hold "08:33" lying down).
pw.Widget _timeRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _timeRowHeight,
    railCaption: 'Zeit',
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) {
      final text = measuredAtText(windowDays[position].measuredAtMinutes);
      if (text == null) return null;
      return _centerRotated(text);
    },
  );
}

/// The disturbance row: the stacked letter codes (one per set flag), the
/// shared letter vocabulary.
pw.Widget _disturbanceRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _disturbanceRowHeight,
    railCaption: 'Störung',
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) {
      final codes = disturbanceCodes(windowDays[position]);
      if (codes.isEmpty) return null;
      return pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            for (final code in codes)
              pw.Text(code, style: _tiny, textAlign: pw.TextAlign.center),
          ],
        ),
      );
    },
  );
}

/// The cervix row: position letter + firmness shorthand (the OPENING is
/// not displayed — entry-form-only field).
pw.Widget _cervixRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _cervixRowHeight,
    railCaption: 'Muttermund',
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) {
      final letters = cervixLetters(windowDays[position]);
      if (letters == null) return null;
      return pw.Center(
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(letters, style: _tiny, textAlign: pw.TextAlign.center),
        ),
      );
    },
  );
}

/// The pain row: the breast-tenderness letter B (the Mittelschmerz M
/// renders inside the plot — see the in-plot glyph seam).
pw.Widget _painRow(
  int windowDayCount,
  List<DailyEntry> windowDays,
  List<int> weekend,
) {
  return _paperRow(
    height: _painRowHeight,
    railCaption: 'Schmerz',
    windowDayCount: windowDayCount,
    weekend: weekend,
    cell: (position) => _centerLetter(painLetter(windowDays[position]), _label),
  );
}

pw.Widget? _centerLetter(String? letter, pw.TextStyle style) => letter == null
    ? null
    : pw.Center(
        child: pw.Text(letter, style: style, textAlign: pw.TextAlign.center),
      );

/// A column's text written bottom-up through the narrow column, centered
/// in the cell. The line lays out along the CELL'S HEIGHT —
/// pw.Transform.rotateBox with unconstrained child + relaid bounding box
/// does the constraint swap (plain pw.Transform.rotate would clip the
/// line after a few characters). Text beyond the cell height wraps into a
/// (dropped) second line — overflowing notes clip at the cell bounds.
pw.Widget _centerRotated(String text) => pw.LayoutBuilder(
  builder: (context, constraints) {
    final length = constraints?.maxHeight ?? 0;
    if (length <= 0) {
      return pw.SizedBox();
    }
    return pw.Center(
      child: pw.Transform.rotateBox(
        angle: -math.pi / 2,
        // Unconstrained: after the rotation the strip fills the cell's
        // height and rotateBox relayouts the bounding box.
        unconstrained: true,
        child: pw.SizedBox(
          width: length,
          child: pw.Text(
            text,
            style: _tiny,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  },
);

/// The German calendar-date format "24.12.1980" (no intl dependency — the
/// document fixed its German wording).
String _formatDate(DateTime date) => [
  date.day.toString().padLeft(2, '0'),
  date.month.toString().padLeft(2, '0'),
  date.year.toString(),
].join('.');
