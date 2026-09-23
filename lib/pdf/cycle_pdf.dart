// The PDF document generation layer: turns a [PdfExportModel] into the
// PDF byte stream the file_transfer seam saves.
//
// Decisions & documented behavior:
//
// - ONE CYCLE PER PAGE (the roadmap rule): the pure layout planner
//   (pdf_layout.dart) decides the (cycle -> pages) split; this builder
//   draws exactly one planned window per physical page, so a long cycle
//   (e.g. a pregnancy-style span) continues onto further pages mid-cycle
//   while NO page ever mixes two cycles. Continuation pages repeat the
//   identical scaffold with the next window ("Blatt k/n" unchanged).
// - PAPER-FORM SCAFFOLD: every page draws the classic Sympto-Thermal
//   sheet's structure — a left rail (the temperature scale in the curve
//   block; small row names elsewhere), 40 day columns across the full
//   printable width, and the row stack top-down: day numbers ("1. Tag"
//   first; the rail legends "Zyklustag"/"Datum" name the header rows —
//   the curve block has no caption row of its own any more: the °C lives
//   in every scale label, so the former "Temperatur in °C" header row was
//   removed and its 9 pt now flow into the rotated notes flex below),
//   dates (day-of-month; month + year stacked on every first-of-month
//   column so multi-month windows read right), the recording rows ABOVE
//   the plot like the cycle tab (bleeding bands, mucus glyphs with the
//   peak-dot slot and quality superscripts, the Mittelschmerz M, the sex
//   X), the CURVE BLOCK (plot + the 1–6 low-number row), the numeric
//   temperature values BELOW the plot, whose rail legend reads
//   "Temperatur in °C" (the row legend style of "Zyklustag"/"Datum" — it
//   moved here from the removed header row; the earlier "Temp" short
//   form named the row only cryptically)
//   (immediately above the times, so out-of-range readings stay readable),
//   the recorded measurement times (vertical, narrow-column convention),
//   then disturbance/cervix/pain and the rotated notes area. Columns the
//   window does not track stay empty — like the paper sheet's unused
//   columns.
// - THE TEMPERATURE CURVE IS DRAWN (in the painter): solid dots per
//   measured in-range day, straight connecting pieces that clip at
//   the scale's window bounds, dimmed pieces/dots where the day carries
//   the ignoreTemperature mark, the dashed window bounds, the fine 0.1 °C
//   graduation and — where the marked candidate sequence supports it —
//   the dashed R10 baseline piece. The numeric value row sits below the
//   plot (right above the measured times) so out-of-range/clipped
//   readings lose no data. The draw list
//   (dots/pieces/dim flags) is composed ONCE by lib/pdf/pdf_curve.dart
//   from the chart's pure helpers; this file only paints geometry.
// - THE EVALUATION OVERLAY IS DRAWN from the model's per-cycle overlay
//   (lib/pdf/pdf_curve.dart maps it into draw items; nothing here
//   re-derives a rule): rings around circled candidates (centered on the
//   dot's drawn position — dot and ring share one circle-emission helper,
//   pdfFillCircle/pdfStrokeCircle, whose center+radius call matches
//   PdfGraphics.drawEllipse's center+half-axes semantics), arrow-up glyphs
//   hanging CLEAR below their dots (tip = dot radius + clearance, carried
//   on the draw list's PdfArrowMark.tipDropPt), the 1–6 low numbers under
//   their dots, the solid peak dot above the mucus glyph and the
//   user-placed SUZ marks drawn as the CYCLE CHART's glyph (a vertical bar
//   hanging from the plot's top border by suzBarHangSpanDegrees of the
//   scale plus its right-pointing arrow glyph at
//   suzArrowTopInsetDegrees — the same shape, orientation, anchoring and
//   −0.5/middle x anchor the chart paints; the constants live in
//   lib/ui/suz_glyph.dart — pure Dart, so this generation layer keeps no
//   material import for the host smoke scripts — and flow through
//   lib/ui/cycle_marks.dart's re-export to the chart. The bar's morning
//   anchor is the column's START edge, the evening's the column middle). The computed suzBegins
//   is deliberately a DIFFERENT artifact — a thin solid vertical line at
//   that day plus the rule letter D/E (decided: the evaluation document
//   shows the computed boundary as the sheet's suggestion line, visually
//   distinct at a glance from the user-placed bars; the chart draws only
//   user marks, the PDF is for teacher/doctor and adds the line).
// - INDEX SPACES: the model overlay's day indexes are calendar offsets
//   from the cycle's start day; page windows slice tracked positions.
//   lib/pdf/pdf_curve.dart maps explicitly between the two (marks on
//   untracked gap days drop out); the scaffold draws window-relative
//   positions only.
// - VERTICAL NOTES: every tracked day column carries its note text
//   rotated 90° into the column's footer area — the
//   narrow paper-form way of writing notes out vertically. Multi-line
//   diary notes fold into ONE line before rendering (see
//   [joinedNoteText] in lib/pdf/pdf_symbols.dart): embedded line breaks
//   and whitespace runs collapse to single spaces, so the whole note
//   reads vertically instead of stacking its lines illegibly into the
//   narrow column. ACCEPTED, DOCUMENTED LIMITATION: a note longer than
//   the notes area overflows/clips at that area's bounds (paper sheets
//   behave the same
//   when the handwriting runs out of room); there is no overflow marker
//   and no follow-to-next-page rendering — extending that is future work,
//   deliberately out of scope.
// - HEADER PER PAGE: page-constant paper-form facts (identifying values,
//   the cycle count, the shortest cycle, the earliest first higher, each
//   under the anonymize rules) plus the per-cycle observation window
//   ("Zykluszeitraum", with the year — anonymization does NOT hide it)
//   and the per-page facts: app identifier, the exported cycle number
//   ("Zyklus N", "Blatt k/n" while a cycle continues over pages) and the
//   export date. The window fact and the export date put the year on the
//   document.
// - ANONYMIZE (per export, not persisted): the toggle HIDES the stored
//   name and birth date in the document regardless of what the settings
//   hold, and marks the header "anonymisiert" — see [pdfHeaderFacts], the
//   pure mapping keeping the semantics testable without bytes.
// - DENSE-GLYPH NOTE (accepted): at ~18 pt columns the superset cells
//   (mucus "S" + quality superscript, stacked disturbance codes, cervix
//   "sh h-w") render in footnotesized type kept to the cell; longer runs
//   clip at the cell the way the notes area already documents. Verify on
//   dense fixtures (the plan of record lists this risk).
// - DOCUMENT LANGUAGE: German. The PDF replaces the German paper form
//   (NFR/Rötzer practice; the export's audience is teacher/doctor), and
//   the JSON export precedent is language-free data; the app's UI strings
//   stay l10n-driven (arbs), while THIS document's labels live here,
//   German-first. Localizing the document is future work, not wired yet.
//
// The generated text is drawn with the bundled Noto Sans TTF (OFL license,
// assets/fonts/) instead of the Latin-1-only CoreFonts, so note text
// beyond Latin-1 (umlaut compositions aside: symbols, Greek, Cyrillic,
// further scripts/symbol ranges) renders verbatim. Symbols OUTSIDE the
// font's own coverage (e.g. arrows, emoji) draw as the notdef box — the
// byte generation itself never fails on them.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/date_only.dart';
import '../domain/models.dart';
import '../domain/pdf_export_model.dart';
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
/// mapping from model + per-export anonymize toggle to the paper-form
/// info. Every missing value becomes the "—" convention.
///
/// The anonymize mapping (decided): the stored name and birth date NEVER
/// reach the document when the toggle was on — the name line itself reads
/// "anonymisiert", the birth date collapses to "—" — and an extra marker
/// line states the anonymization, so the recipient sees it even when no
/// identifying value was stored at all. The OBSERVATION WINDOW (when
/// carried: the header's cycle's first–last tracked day, with the year)
/// is NOT anonymized — the window belongs to the evaluation, not to the
/// person.
List<({String label, String value})> pdfHeaderFacts({
  required PdfExportModel model,
  required bool anonymized,
  ({DateTime first, DateTime last})? cycleWindow,
}) {
  final birthDate = model.birthDate == null
      ? null
      : _formatDate(DateOnly.normalize(model.birthDate!));
  final earliestHigher =
      model.earliestFirstHigherCycleDay.afterMucusPeak ??
      model.earliestFirstHigherCycleDay.any;
  return [
    if (anonymized) (label: 'Anonymisierung', value: 'anonymisiert'),
    (label: 'Name', value: anonymized ? 'anonymisiert' : (model.name ?? '—')),
    (label: 'Geburtsdatum', value: anonymized ? '—' : (birthDate ?? '—')),
    (label: 'Beobachtete Zyklen', value: '${model.observedCycleCount}'),
    (
      label: 'Kürzester Zyklus',
      value: model.shortestCycleLength == null
          ? '—'
          : '${model.shortestCycleLength} Tage',
    ),
    (
      label: 'Früheste erste höhere Messung',
      value: earliestHigher == null ? '—' : 'Zyklustag $earliestHigher',
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

/// The app identifier printed in every page header (the document's own
/// wording, German — see the file-header language decision).
const String pdfAppIdentifier = 'Zyklus-App';

/// The scaffold's rail legends — the pure pin-able strings the private
/// row builders place into the left rail (document language: German, see
/// the file header).
///
/// The curve block itself has NO caption row (the former "Temperatur in
/// °C" header row above the plot was removed: the °C already lives in
/// every scale label — "37,5 °C" — so that naming was redundant; its
/// height flows into the rotated notes area below). The temperature
/// naming now lives where the numbers live: the below-plot VALUE row's
/// legend reads exactly [pdfRailCaptionTemperatureValues].
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
/// `fontBytes` carries the BUNDLED TTF's bytes (the app loads them via
/// rootBundle; host smoke scripts read the asset file directly); the font
/// is registered as the document's base font so note text renders beyond
/// Latin-1 (see the file header for the exact coverage statement).
///
/// `compress` is a generation flag: production keeps the default
/// (compressed streams); the smoke tests flip it to count the
/// uncompressed page markers for their structural checks.
///
/// Page count and window layout follow the layout planner exactly: one
/// physical page per [CyclePagePlan] entry, each drawing ONE cycle's day
/// window — never days of two cycles on one page.
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

  final dayCounts = [
    for (final evaluation in model.cycles) evaluation.cycle.days.length,
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
    final windowDays = cycleDays
        .sublist(window.firstDayIndex, window.firstDayIndex + window.dayCount)
        .toList(growable: false);
    // The page's curve/overlay draw list: the calendar-offset overlay
    // space mapped onto this window's tracked positions (pure Dart).
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
                // This page's cycle's observation window (first–last tracked
                // day), carried WITH the year into the header facts.
                cycleWindow: (
                  first: cycleDays.first.date,
                  last: cycleDays.last.date,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            _paperFormGrid(
              windowDays: windowDays,
              windowFirstIndex: window.firstDayIndex,
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

/// The recording rows above the plot (the cycle tab's top-block order:
/// bleeding → mucus → Mittelschmerz → sex).
const double _mucusBandHeight = 14;
const double _sexRowHeight = 11;

/// The curve block's painted plot region (fine scale + curve + overlay
/// marks). Its per-column text band rides INSIDE the block below it —
/// the 1–6 numbers under the low dots (the mucus glyphs, the
/// Mittelschmerz letters and the sex X moved above the plot, mirroring
/// the cycle tab's strip).
const double _curvePlotHeight = 185;
const double _lowNumbersRowHeight = 10;

/// The recording rows above the plot (the cycle tab's top-strip order:
/// bleeding → mucus → Mittelschmerz → sex).
const double _mittelschmerzRowHeight = 10;

/// The below-plot strip rows, in the strip order (value → time →
/// disturbance → cervix → pain → note).
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
/// columns — narrow pages keep the sheet's column geometry, so the curve
/// painter and every row's text agree through the pdf_axis geometry.
pw.Widget _paperFormGrid({
  required List<DailyEntry> windowDays,
  required int windowFirstIndex,
  required PdfCurveDrawing drawing,
  required PdfCurveAxis axis,
}) {
  return pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _dayNumberRow(windowDays.length, windowFirstIndex),
        _dateRow(windowDays.length, windowDays),
        _bleedingRow(windowDays.length, windowDays),
        // The cycle tab's top strip order, above the plot: bleeding →
        // mucus (peak dot above the glyph) → Mittelschmerz M → sex.
        _mucusBand(windowDays.length, windowDays, drawing),
        _mittelschmerzRow(windowDays.length, windowDays),
        _sexRow(windowDays.length, windowDays),
        _curveBlock(windowDays.length, drawing, axis),
        // The numeric values render BELOW the plot (mirror of the curve
        // tab's below-chart strip): the curve/dots stay above, and the
        // readings sit right above the measured times.
        _tempValueRow(windowDays.length, windowDays),
        _timeRow(windowDays.length, windowDays),
        _disturbanceRow(windowDays.length, windowDays),
        _cervixRow(windowDays.length, windowDays),
        _painRow(windowDays.length, windowDays),
        // The rotated notes area absorbs the remaining page height (the
        // bottom repeats of the day numbers were removed — the header
        // rows above the curve are the one day-number row).
        pw.Expanded(
          child: _paperRow(
            height: 0,
            railCaption: 'Notizen',
            windowDayCount: windowDays.length,
            cell: (position) => windowDays[position].notes == null
                ? null
                // Multi-line notes fold to one line: the rotated column
                // reads a note bottom-up as a single string (see the
                // VERTICAL NOTES file-header bullet; overflow still clips,
                // documented acceptance).
                : _centerRotated(joinedNoteText(windowDays[position].notes!)),
          ),
        ),
      ],
    ),
  );
}

/// One scaffold row: the fixed rail slot plus the 40 fixed-width columns
/// (a hairline between columns, a hairline on the row's top edge — the
/// paper's horizontal rules). Empty cells keep the column rhythm; the
/// wrapping column container closes the right edge.
pw.Widget _paperRow({
  required double height,
  required String? railCaption,
  required int windowDayCount,
  required pw.Widget? Function(int position) cell,
}) {
  return pw.Container(
    height: height,
    decoration: const pw.BoxDecoration(border: pw.Border(top: _hairline)),
    child: _gridColumns(
      railCaption: railCaption,
      windowDayCount: windowDayCount,
      cell: cell,
    ),
  );
}

/// The 40 fixed columns behind every row (with the rail at their left).
pw.Widget _gridColumns({
  required String? railCaption,
  required int windowDayCount,
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
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(left: _hairline),
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

/// The day-number row: "1. Tag" labels the sheet's first column; the
/// numbers otherwise keep counting over the cycle's tracked days (a
/// continuation page's first column carries its continuing cycle day).
/// The rail legend "Zyklustag" names this row for the reader — the paper
/// sheet writes its labels into the same margin column.
pw.Widget _dayNumberRow(int windowDayCount, int windowFirstIndex) {
  return _paperRow(
    height: _dayNumberRowHeight,
    railCaption: pdfRailCaptionDayNumbers,
    windowDayCount: windowDayCount,
    cell: (position) => pw.Center(
      child: pw.Text(
        windowFirstIndex + position == 0
            ? '1. Tag'
            : '${windowFirstIndex + position + 1}.',
        style: _tiny,
        textAlign: pw.TextAlign.center,
      ),
    ),
  );
}

/// The date row: the calendar day of month; every FIRST-OF-MONTH column
/// carries the month name + year (stacked, tiny) so a multi-month window
/// still reads right. The rail legend is plain "Datum" (CHOSEN, VARIANT
/// (a) of two): the month/year context comes from the first-of-month
/// columns themselves — every window is at most 40 days, so EVERY page
/// window necessarily contains a first-of-month column, and a legend
/// date carrying the window's first month/year could mislead on windows
/// spanning several months. The full-width home of the window's year is
/// the header's "Zykluszeitraum" fact.
pw.Widget _dateRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _dateRowHeight,
    railCaption: pdfRailCaptionDates,
    windowDayCount: windowDayCount,
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
pw.Widget _bleedingRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _bleedingRowHeight,
    railCaption: 'Blutung',
    windowDayCount: windowDayCount,
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
      // Dotted spotting: round dots spread over the band — the same
      // convention the shared symbol renders in the app.
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

/// The numeric temperature value row, BELOW the plot (right above the
/// measured times; kept so out-of-range/clipped readings lose no data):
/// the measured value with one German comma decimal, "—" unmeasured.
/// Its rail legend is exactly "Temperatur in °C" (this is where the
/// temperature naming lives since the curve block's caption row was
/// removed — see the rail-legends constants).
pw.Widget _tempValueRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _tempValueRowHeight,
    railCaption: pdfRailCaptionTemperatureValues,
    windowDayCount: windowDayCount,
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

/// The curve block: the painted plot row (rail = scale labels, day
/// columns = the painter's canvas) and the plot's 1–6 low-number band
/// below it. NO caption row above the plot any more: the former
/// "Temperatur in °C" header slot was removed — the scale labels carry
/// the unit on every number and the temperature naming now lives on the
/// numeric value row's rail legend (below the plot). The block's row
/// boundaries stay the plot's own hairlines: the top hairline on the
/// plot container is the block's edge against the sex row, the low
/// numbers row follows directly below.
pw.Widget _curveBlock(
  int windowDayCount,
  PdfCurveDrawing drawing,
  PdfCurveAxis axis,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
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
                size: PdfPoint(
                  pdfGridRightEdge - pdfRailWidth,
                  _curvePlotHeight,
                ),
                painter: (canvas, size) =>
                    _paintCurveBlock(canvas, size.x, size.y, drawing, axis),
                child: pw.Stack(
                  children: [
                    // The computed SUZ's rule letter rides its line's
                    // column (a positioned widget above the geometry).
                    if (drawing.suzLine case final line?)
                      pw.Positioned(
                        left: (line.x * pdfColumnWidth - 4).clamp(
                          0.0,
                          defaultMaxDaysPerPage * pdfColumnWidth - 8,
                        ),
                        top: 0,
                        child: pw.Text(
                          line.ruleLetter ?? 'S',
                          style: _tinyAccent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _lowNumbersRow(windowDayCount, drawing),
    ],
  );
}

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
) {
  // The painter's PdfGraphics origin is the box's bottom-left corner
  // (PDF y-up), while the axis returns distances DOWN from the top —
  // every geometric y goes through this conversion (see pdf_axis.dart's
  // file header).
  double yOf(double value) => plotHeight - axis.yFor(value);

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

  // Dashed strokes (the window bounds, the baseline) reset their dash.
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

  // The curve's line pieces first (under the dots), dimmed per the model.
  // DIMMING: the PDF number operators carry no alpha — a PdfColor's alpha
  // is dropped by setStrokeColor/setFillColor — so the ignoreTemperature
  // dimming goes through an ExtGState (setGraphicState) applied while the
  // ignored piece draws and reset right after. Same constant as the chart
  // (ignoredTemperatureAlpha), so chart and export cannot drift.
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

  // Dots (solid), dimmed on marked-ignored days (same ExtGState dimming
  // as the ignored line pieces above).
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
  // drawn position: same column-center x, same yFor(value) conversion and
  // clamping as the dot above (one shared circle helper keeps the two
  // from ever disagreeing).
  canvas.setStrokeColor(_markAccent);
  canvas.setLineWidth(0.7);
  for (final ring in drawing.rings) {
    pdfStrokeCircle(canvas, _columnCenterX(ring.index), yOf(ring.value), 3.0);
  }

  // Arrow-up glyphs BELOW the arrow-marked dots: head + short stem
  // pointing UP at the dot (the paper writes the arrow under the column's
  // dot), with the tip CLEAR of the dot — the drop from the dot's center
  // (radius + clearance) is carried on the draw item itself
  // (PdfArrowMark.tipDropPt), clamped so the stem stays inside the plot.
  canvas.setFillColor(_markAccent);
  for (final arrow in drawing.arrows) {
    final x = _columnCenterX(arrow.index);
    // Canvas y-up: the glyph hangs BELOW the dot — the tip sits
    // [tipDropPt] under the dot's center, head + stem extend further
    // down (smaller y).
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
  // shape, orientation and anchoring — the constants are shared with
  // lib/ui/cycle_marks.dart): a vertical bar hanging DOWN from the plot's
  // top border by [suzBarHangSpanDegrees] of the temperature scale, plus
  // its right-pointing arrow whose base is anchored at the bar, centered
  // on [suzArrowTopInsetDegrees] below that border (the chart's glyph
  // pair; the arrow's painted geometry mirrors paintSuzArrowGlyph: an
  // 8-pt shaft, a 7-pt head, 11 pt high). Morning bars anchor at the
  // column START (= the bar's x), evening bars at the column middle —
  // exactly the chart's barX rule.
  for (final bar in drawing.suzBars) {
    final x = bar.x * pdfColumnWidth;
    // Canvas y-up: the bar spans from the top edge down by the hang span
    // (expressed in scale degrees via the axis, like the chart does); a
    // hang beyond the window degenerates to the plot's full height.
    final barBottom =
        plotHeight - axis.yFor(axis.range.max - suzBarHangSpanDegrees);
    canvas
      ..setStrokeColor(_markAccent)
      ..setLineWidth(2)
      ..drawLine(x, plotHeight, x, barBottom)
      ..strokePath();
    // The arrow: base at the bar (x anchored as above), centered on the
    // arrow inset below the top border. Same head/shaft proportions as
    // the chart's paintSuzArrowGlyph.
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

  // The computed SUZ: a thin solid vertical line through the whole plot
  // at the suzBegins column's middle — deliberately DISTINCT from the
  // user marks' bar+arrow glyph above (the file header's decision note),
  // its rule letter is a positioned widget (kept out of the canvas-font
  // path).
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
/// CENTERED on (x, y) with r1/r2 as HALF-axes (its curves run through
/// x±r1 / y±r2) — corner+size arithmetic here drifts every circle
/// off-center and double its size (the ring-centering defect this helper
/// fixes, pinned byte-level in test/pdf/pdf_circle_geometry_test.dart).
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

/// The 1–6 low numbers under their low dots (bold accent — the paper
/// writes the numbers inside the low band; the thin row keeps them off
/// the plotted dots).
pw.Widget _lowNumbersRow(int windowDayCount, PdfCurveDrawing drawing) {
  return _paperRow(
    height: _lowNumbersRowHeight,
    railCaption: 'Zahl',
    windowDayCount: windowDayCount,
    cell: (position) {
      final number = drawing.lowNumbers[position];
      if (number == null) return null;
      return pw.Center(child: pw.Text('$number', style: _tinyAccent));
    },
  );
}

/// The mucus row (above the plot, the cycle tab's top-strip order
/// bleeding → mucus → Mittelschmerz → sex): the base glyph with the
/// superscript quality token and the reserved solid peak-dot slot above
/// the glyph.
pw.Widget _mucusBand(
  int windowDayCount,
  List<DailyEntry> windowDays,
  PdfCurveDrawing drawing,
) {
  return _paperRow(
    height: _mucusBandHeight,
    railCaption: 'Zeichen',
    windowDayCount: windowDayCount,
    cell: (position) {
      const mucusGlyph = pw.TextStyle(fontSize: 6.4);
      const mucusQuality = pw.TextStyle(fontSize: 4.8);
      final display = mucusText(windowDays[position]);
      if (display.symbol == null && display.superscript == null) return null;
      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SizedBox(
            height: 5,
            child: drawing.peakIndexes.contains(position)
                ? pw.Center(
                    child: pw.Container(
                      width: 4.6,
                      height: 4.6,
                      decoration: pw.BoxDecoration(
                        color: _markAccent,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          // Base glyph + raised superscript: a composed row (pdf's
          // RichText baseline offset proved unreliable here — the raised
          // token may render on the same line or drop out at tiny sizes).
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (display.symbol case final symbol?)
                pw.Text(symbol, style: mucusGlyph),
              if (display.superscript case final quality?)
                pw.Transform.translate(
                  offset: PdfPoint(0, 2.6),
                  child: pw.Text(quality, style: mucusQuality),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// The Mittelschmerz row: the letter M under its column — ABOVE the plot
/// like in the cycle tab's top strip (directly beneath the mucus row,
/// before the sex X). TODO(user-review): the exact M home is an
/// owner-eyeball choice — the paper writes it under the mucus letters;
/// clinicians may want it twice, with the below-strip pain row as well.
pw.Widget _mittelschmerzRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _mittelschmerzRowHeight,
    railCaption: 'Mittelschmerz',
    windowDayCount: windowDayCount,
    cell: (position) =>
        _centerLetter(mittelschmerzLetter(windowDays[position]), _label),
  );
}

/// The sex row: the X cell (any recorded time slot; the timing's own
/// thirds stay the chart's finer rendering).
pw.Widget _sexRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _sexRowHeight,
    railCaption: 'Sex',
    windowDayCount: windowDayCount,
    cell: (position) => _centerLetter(sexGlyph(windowDays[position]), _label),
  );
}

/// The measurement-time row: the recorded time-of-day of the temperature
/// measurement as a vertical "HH:mm" — the app's narrow-column rendering
/// convention (the ~18 pt paper column cannot hold "08:33" lying down;
/// the row only exists where a temperature (and therefore a time) exists).
/// CHOOSE-DOCUMENTED: vertical text is chosen over dropping the time.
pw.Widget _timeRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _timeRowHeight,
    railCaption: 'Zeit',
    windowDayCount: windowDayCount,
    cell: (position) {
      final text = measuredAtText(windowDays[position].measuredAtMinutes);
      if (text == null) return null;
      return _centerRotated(text);
    },
  );
}

/// The disturbance row: the stacked letter codes (one per set flag), the
/// shared letter vocabulary.
pw.Widget _disturbanceRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _disturbanceRowHeight,
    railCaption: 'Störung',
    windowDayCount: windowDayCount,
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
/// not displayed — entry-form-only field, matching the chart row).
pw.Widget _cervixRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _cervixRowHeight,
    railCaption: 'Muttermund',
    windowDayCount: windowDayCount,
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

/// The pain row: the breast-tenderness letter B (Mittelschmerz M has its
/// own row above the plot, directly beneath the mucus letters).
pw.Widget _painRow(int windowDayCount, List<DailyEntry> windowDays) {
  return _paperRow(
    height: _painRowHeight,
    railCaption: 'Schmerz',
    windowDayCount: windowDayCount,
    cell: (position) => _centerLetter(painLetter(windowDays[position]), _label),
  );
}

pw.Widget? _centerLetter(String? letter, pw.TextStyle style) => letter == null
    ? null
    : pw.Center(
        child: pw.Text(letter, style: style, textAlign: pw.TextAlign.center),
      );

/// A column's text written bottom-up through the narrow column (the
/// paper's vertical strip handwriting), centered in the cell. The line
/// lays out along the CELL'S HEIGHT — pw.Transform.rotateBox with
/// unconstrained child + relaid bounding box does the constraint swap
/// (plain pw.Transform.rotate lays the line out in the narrow column's
/// WIDTH — the pdf widget tree enforces the incoming maximum, so a longer
/// line would clip after a few characters). [pw.LayoutBuilder] reads the
/// cell height for the reading length; text beyond it wraps into the
/// (dropped) second line — overflowing notes clip at the cell bounds —
/// the same documented acceptance as the paper's running-out handwriting.
pw.Widget _centerRotated(String text) => pw.LayoutBuilder(
  builder: (context, constraints) {
    final length = constraints?.maxHeight ?? 0;
    if (length <= 0) {
      return pw.SizedBox();
    }
    return pw.Center(
      child: pw.Transform.rotateBox(
        angle: -math.pi / 2,
        // Unconstrained: the child (fixed-length strip) may exceed the
        // narrow column's width — after rotation it fills the cell's
        // height, and pw.Transform.rotateBox relayouts the bounding box
        // so Center positions it like any other child.
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

/// The German calendar-date format "24.12.1980" (the document fixed its
/// German wording, so it formats German too — no intl dependency here).
String _formatDate(DateTime date) => [
  date.day.toString().padLeft(2, '0'),
  date.month.toString().padLeft(2, '0'),
  date.year.toString(),
].join('.');
