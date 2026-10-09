// The merged notes band's geometry, shared between the cycle tab's band
// (lib/ui) and the paper-form PDF's merged band row (lib/pdf/cycle_pdf.dart:
// the band constants' original home re-exports this module). Pure Dart.
//
// The numbers are the SCREEN's logical pixels; the PDF paints the same
// absolute geometry (pdf points at print scale), so one set of numbers
// serves both renderers and neither can drift from the other.
import 'cervix.dart';
import 'models.dart';

/// The merged below-chart notes band's height: the cervix zone, the letter
/// row, the breast-pain row and the note text zone share it.
///
/// TODO(user-review): the height is an owner-eyeball rendering detail, not
/// a settled rule.
const double notesBandHeight = 64;

/// The band's cervix glyph zone, anchored at the band TOP: the same
/// reserved block height on every cervix day, so the position evolution
/// stays comparable at a glance whatever the note below.
const double cervixGlyphZoneHeight = 26;

/// The fixed letter row below the glyph zone: the firmness letter renders
/// here iff a value exists, never moving the slot ink above it.
const double cervixLetterRowHeight = 10;

/// The dedicated breast-pain letter row, directly above the note zone (at
/// the band top on cervix-free days): rendered only on pain days, never
/// reserved on pain-free ones.
const double painRowHeight = 12;

/// The band's painted cervix-opening circles' diameters (the opening is
/// communicated by diameter, like the course notation) and their outline
/// stroke.
///
/// TODO(user-review): the diameters and the stroke are owner-eyeball
/// rendering details.
const double cervixClosedDotSize = 4;
const double cervixMiddleCircleSize = 6;
const double cervixOpenCircleSize = 8;
const double cervixCircleStrokeWidth = 1.3;

/// The cervix glyph zone's position slot for a position, counted TOP-DOWN:
/// veryHigh is the topmost reachable slot, unreachable — past everything —
/// sits above it, and low at the very bottom.
int cervixSlotIndex(CervixPosition position) =>
    CervixPosition.values.length - 1 - position.index;

/// A position slot's ink-center Y inside the glyph zone: the slots keep
/// the largest circle's half diameter plus a stroke's worth of edge room
/// at both ends, evenly spaced between.
double cervixSlotCenterY(int slotIndex) {
  const edge = cervixOpenCircleSize / 2 + cervixCircleStrokeWidth;
  return edge +
      slotIndex *
          (cervixGlyphZoneHeight - 2 * edge) /
          (CervixPosition.values.length - 1);
}

/// One day's band layout: which zones render and where they start. Both
/// renderers (the screen's band Stack and the PDF's band cell) place the
/// cervix circle in the glyph zone, the firmness letter at
/// [cervixGlyphZoneHeight], the pain letter at [painRowTop] and the note
/// at [noteTop] — one stack, one geometry.
typedef NotesBandLayout = ({
  /// Any cervix observation reserves the band's top block, whatever the
  /// zones inside paint.
  bool hasCervix,

  /// The painted circle's slot (see [cervixSlotIndex]); null → the glyph
  /// zone stays empty. The circle needs an OPENING value; a position value
  /// without one paints nothing.
  int? slotIndex,

  /// The circle's opening value; null → nothing paints in the glyph zone.
  CervixOpening? opening,

  /// The pain row renders only on pain days ([painRowTop]); pain-free days
  /// never reserve it.
  bool hasPain,
  double painRowTop,
  double noteTop,
});

NotesBandLayout notesBandLayout(DailyEntry? day) {
  final hasCervix =
      day != null &&
      (day.cervixPosition != null ||
          day.cervixOpening != null ||
          day.cervixFirmness != null);
  final hasPain = day?.painBreast ?? false;
  final painRowTop = hasCervix
      ? cervixGlyphZoneHeight + cervixLetterRowHeight
      : 0.0;
  final opening = day?.cervixOpening;
  return (
    hasCervix: hasCervix,
    slotIndex: opening == null
        ? null
        : cervixSlotIndex(day!.cervixPosition ?? CervixPosition.medium),
    opening: opening,
    hasPain: hasPain,
    painRowTop: painRowTop,
    noteTop: hasPain ? painRowTop + painRowHeight : painRowTop,
  );
}
