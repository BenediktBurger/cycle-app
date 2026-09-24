// The PDF layer's pure per-day symbol mappings: a recorded day's
// observations mapped onto the paper form's cell contents — the bleeding
// fill, the mucus glyph (with quality superscript), the sex/cervix/pain
// letter cells, the disturbance codes and the measurement-time text.
//
// Display mapping only (Mode M, ADR-0001): every helper delegates to the
// existing domain display helpers where they exist (mucusDisplay and its
// sanitize rule, the cervix chart glyphs, the shared disturbance letter
// vocabulary in lib/domain/disturbances.dart) — nothing is reinterpreted
// or reworded here, so the PDF cannot drift from the chart's conventions.
import '../domain/date_only.dart';
import '../domain/disturbances.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../domain/cervix.dart';

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

/// A day's mucus glyph for the recording row above the plot: the base symbol
/// plus — only on the S sign — the quality as a superscript token, exactly
/// the shared `mucusDisplay` mapping (quality dropped for any non-S sign).
/// Both fields null when the day recorded no sign.
MucusDisplay mucusText(DailyEntry? day) =>
    mucusDisplay(sign: day?.mucusSign, quality: day?.mucusQuality);

/// The sex glyph: a single X per recorded day (any recorded time slot —
/// the timing's own thirds stay the chart's finer rendering; the narrow
/// paper column carries one X).
String? sexGlyph(DailyEntry? day) =>
    day != null && day.sexTimings != 0 ? 'X' : null;

/// The cervix letter cell: position glyph first, then the firmness
/// shorthand (h / h-w / w), space-joined — the chart's cell text, same
/// glyphs. The opening is deliberately not displayed (entry-form-only
/// field). Null when neither observation was recorded.
String? cervixLetters(DailyEntry? day) {
  if (day == null) return null;
  final position = day.cervixPosition == null
      ? null
      : cervixPositionSymbol(day.cervixPosition!);
  final firmness = day.cervixFirmness == null
      ? null
      : cervixFirmnessSymbol(day.cervixFirmness!);
  if (position == null && firmness == null) return null;
  return [
    if (position != null) position,
    if (firmness != null) firmness,
  ].join(' ');
}

/// The pain row's letter cell: 'B' for breast tenderness (the
/// letter-coded pain option's letter). Mittelschmerz alone on ITS OWN row
/// beneath the mucus letters ([mittelschmerzLetter]) — two rows, two
/// letters, never mixed.
String? painLetter(DailyEntry? day) =>
    day != null && day.painBreast ? 'B' : null;

/// The Mittelschmerz letter cell: 'M' under the column (the paper sheet
/// writes M beneath the mucus letters; in this export the row sits above
/// the plot).
String? mittelschmerzLetter(DailyEntry? day) =>
    day != null && day.painMittelschmerz ? 'M' : null;

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
