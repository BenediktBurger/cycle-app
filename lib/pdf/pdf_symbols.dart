// The PDF layer's pure per-day symbol mappings: a recorded day's
// observations mapped onto the paper form's cell contents — the bleeding
// fill, the pain letter cell, the disturbance codes and the
// measurement-time text.
//
// The in-plot glyphs (the sex X marks, the mucus sign letters, the
// Mittelschmerz M and the evaluation day numbers) are not mapped here:
// they render inside the plot (see cycle_pdf.dart's in-plot glyph seam),
// placed by the shared chart-marks mapper, whose mucus letters come
// straight from mucusDisplay (lib/ui/chart_marks.dart). The cervix cells
// (opening circles, firmness letters) and the merged band's zone layout
// come straight from the band module (../domain/band_layout.dart) the
// cycle tab uses — no PDF-side re-mapping.
//
// Display mapping only (Mode M, ADR-0001): every helper delegates to the
// existing domain display helpers where they exist (the shared
// disturbance letter vocabulary in lib/domain/disturbances.dart) —
// nothing is reinterpreted or reworded here, so the PDF cannot drift from
// the chart's conventions.
import '../domain/date_only.dart';
import '../domain/disturbances.dart';
import '../domain/measurement_method.dart';
import '../domain/models.dart';

/// The bleed fill of one row cell, bottom-anchored like the shared
/// bleeding symbol (lib/ui/bleeding_symbol.dart): level 1 (spotting)
/// renders DOTTED inside the bottom quarter band; heavier levels render
/// solid (level − 1)/4 of the cell height (¼ … ½ … ¾ … full). Level 0
/// (none) gets no fill at all — null.
final class PdfBleedingFill {
  const PdfBleedingFill({required this.dotted, required this.heightFraction});

  /// Dotted (spotting) vs. solid fill.
  final bool dotted;

  /// The bottom-anchored fraction of the cell height the band occupies.
  final double heightFraction;
}

PdfBleedingFill? bleedingFill(Bleeding bleeding) {
  if (bleeding.level == 0) return null;
  return PdfBleedingFill(
    dotted: bleeding == Bleeding.spotting,
    heightFraction: bleeding == Bleeding.spotting
        ? 1 / 4
        : (bleeding.level - 1) / 4,
  );
}

/// The pain row's letter cell: 'B' for breast tenderness (the
/// letter-coded pain option's letter). The Mittelschmerz M renders inside
/// the plot (the in-plot glyph seam in cycle_pdf.dart), not here.
String? painLetter(DailyEntry? day) =>
    day != null && day.painBreast ? 'B' : null;

/// The disturbance strip row's stacked letter codes, straight from the
/// shared vocabulary (one code per set flag; empty on flag-free days).
/// An alias of the domain function itself — the PDF and the chart call
/// the SAME function, one vocabulary.
final disturbanceCodes = disturbanceLetters;

/// The note column's cell text: a diary note may be recorded MULTI-LINE
/// (embedded line breaks) but the rotated notes column renders a note as
/// one vertical line — every whitespace run (line breaks included) folds
/// into a single space and edge whitespace drops off. The caller passes
/// non-null notes only (`notes == null` renders the empty cell); overflow
/// beyond the notes area still clips (documented acceptance — see the
/// VERTICAL NOTES bullet in lib/pdf/cycle_pdf.dart's file header).
String joinedNoteText(String notes) =>
    notes.replaceAll(RegExp(r'\s+'), ' ').trim();

// The measurement-method texts of the paper form: the German route wording
// lives ONCE here, so the header's fact line and the band's method note
// cannot drift (the document layer has no l10n — it replaces the German
// paper form).

/// The route's German word for the sheet.
String pdfMethodRouteLabel(MeasurementRoute route) => switch (route) {
  MeasurementRoute.vaginal => 'vaginal',
  MeasurementRoute.rectal => 'rektal',
  MeasurementRoute.oral => 'oral',
  MeasurementRoute.other => 'andere',
};

/// The header's method-fact value: the route plus, when a thermometer name
/// is known, the name after the comma.
String pdfMethodFactText(MeasurementRoute route, String? thermometer) {
  final label = pdfMethodRouteLabel(route);
  return thermometer == null ? label : '$label, $thermometer';
}

/// The band's synthesized snapshot-day note: the route word alone, or the
/// thermometer name comma-attached after it — the same wording as the
/// header's fact line. No glyph prefix: the bundled font's cmap covers
/// neither U+1F321 nor U+2668 (fc-query on assets/fonts/NotoSans-Regular.ttf),
/// so one would draw as the notdef box.
String pdfMethodChangeNote(MeasurementRoute route, String? thermometer) =>
    pdfMethodFactText(route, thermometer);

/// The rotated notes cell's text for one day: the custom-marks line, the
/// stored free note and the method change's synthesis merged in that
/// order, joined by the em-dash. The marks argument carries the day's
/// custom-marks line (customMarksNote, the shared render line) and the
/// synthesis happens at RENDER time — the caller passes the day's stored
/// notes untouched. Empty in all slots → null (the empty cell the row
/// renders today).
String? pdfNotesCellText(String? marks, String? notes, String? methodChange) {
  final text = notes == null ? null : joinedNoteText(notes);
  final parts = [
    if (marks case final line? when line.isNotEmpty) line,
    if (text case final note? when note.isNotEmpty) note,
    if (methodChange case final change? when change.isNotEmpty) change,
  ].join(' — ');
  return parts.isEmpty ? null : parts;
}

/// One page window's WEEKEND columns: the tracked-day positions whose
/// calendar date falls on a Saturday or Sunday. Judged purely by the DATE
/// via [DateOnly.isWeekend] — the same pure predicate the cycle tab's
/// weekend bands use — never by a column-index rule, so continuation
/// pages and multi-month windows keep the true weekday rhythm wherever
/// the window happens to start. The scaffold paints a print-friendly
/// light-gray band through every one of these columns (and the painter
/// through the plot's); see [pdfWeekendShade] in cycle_pdf.dart.
List<int> weekendPositions(List<DailyEntry> windowDays) => [
  for (var i = 0; i < windowDays.length; i++)
    if (DateOnly.isWeekend(windowDays[i].date)) i,
];

/// The measurement row's cell text: the recorded time-of-day of the
/// temperature measurement as German "HH:mm" (minutes since midnight,
/// 0–1439 — the parser's vocabulary); null when nothing was recorded or
/// the minute value is out of range.
///
/// The row only exists for days WITH a temperature — `measuredAtMinutes`
/// is metadata of the temperature and can never be set without `bbtC`
/// (the DailyEntry constructor drops a time without one), so null means
/// "measurement without recorded time" and renders no cell content.
String? measuredAtText(int? minutes) {
  if (minutes == null || minutes < 0 || minutes > 1439) return null;
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
