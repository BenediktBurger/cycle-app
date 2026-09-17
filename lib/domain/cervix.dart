// The Muttermund (cervix) observations of a day: POSITION and OPENING.
//
// Two independent per-day options with the vocabularies asked for by the
// product wishlist — position: tief/mittel/hoch/sehr hoch/unerreichbar,
// opening: geschlossen/mittel/offen. Neither rules nor conclusions from
// them anywhere in this app (Mode M posture, ADR-0001): only the raw
// observation is recorded and shown.
//
// Storage rule (like the mucus vocabulary, lib/domain/mucus.dart): the enum
// NAMES are the TEXT tokens stored in the database (engine-level CHECK) and
// in the export document. A rename of any value is therefore a data
// migration — the tests pin every token; treat a rename as a schema change,
// not a refactor. Display glyphs are derived helpers, never stored.
//
// Note the deliberate token distinction between the two vocabularies:
// position "medium" vs. opening "middle" — both render "mittel" in German,
// but the stored tokens never collide (a row with opening='medium' or
// position='middle' cannot exist behind the SQL CHECKs).

/// How DEEP the cervix was felt on the day (Muttermund-Position), from
/// lowest [low] to past-everything [unreachable]:
///
/// - `low`: tief
/// - `medium`: mittel
/// - `high`: hoch
/// - `veryHigh`: sehr hoch
/// - `unreachable`: unerreichbar
enum CervixPosition { low, medium, high, veryHigh, unreachable }

/// How OPEN the cervix felt on the day (Muttermund-Öffnung):
///
/// - `closed`: geschlossen
/// - `middle`: mittel
/// - `open`: offen
enum CervixOpening { closed, middle, open }

/// Parses a stored/exported position token back into the enum, or null for
/// anything else. SHARED by the db mapper and the export/import writer —
/// like tryParseMucusSign (lib/domain/mucus.dart), the single source of
/// truth for this field's validation, so a row a writer would drop is never
/// counted as a write. Accepts `Object?`: export rows arrive JSON-decoded
/// as the loosest shape.
CervixPosition? tryParseCervixPosition(Object? raw) {
  if (raw is! String) return null;
  for (final position in CervixPosition.values) {
    if (position.name == raw) return position;
  }
  return null;
}

/// Parses a stored/exported opening token back into the enum, or null for
/// anything else. Same contract as [tryParseCervixPosition].
CervixOpening? tryParseCervixOpening(Object? raw) {
  if (raw is! String) return null;
  for (final opening in CervixOpening.values) {
    if (opening.name == raw) return opening;
  }
  return null;
}

/// Chart glyph of a position for the cycle-tab symbol row: the first letter
/// of the German vocabulary word — `t` tief, `m` mittel, `h` hoch, `sh`
/// (sehr hoch, two letters to stay distinct from plain `h`), `u`
/// (unerreichbar). The opening is NOT displayed on the chart.
///
/// TODO(user-review): these letters are an ad-hoc display choice — the NER
/// cheat sheet defines no cervix glyphs. In particular `t` visually equals
/// the mucus dry-sign glyph `t`; the chart distinguishes them only by color
/// (neutral on-surface vs. the tertiary mucus color). INER experts may want
/// different symbols.
String cervixPositionSymbol(CervixPosition position) => switch (position) {
      CervixPosition.low => 't',
      CervixPosition.medium => 'm',
      CervixPosition.high => 'h',
      CervixPosition.veryHigh => 'sh',
      CervixPosition.unreachable => 'u',
    };
