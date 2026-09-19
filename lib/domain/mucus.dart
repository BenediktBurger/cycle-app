// The "Zeichen der Fruchtbarkeit" vocabulary from the INER cheat sheet
// (docs/cheatsheet.md): fertility signs t / Ø (nichts) / f / S / A
// (Ausfluss), with quality qualifiers that are ONLY valid together with the
// sign S (the discharge sign A has no quality of its own).
//
// Mode M posture (ADR-0001, docs/adr/0001-iner-mode-m-hypothesis.md): the app
// records these observations faithfully and NEVER interprets them — no rule
// from the cheat sheet evaluation is encoded here or anywhere in the code.
//
// Storage rule: the enum NAMES are the TEXT tokens stored in the database and
// in the export document (unlike bleeding, which stores the numeric
// Bleeding.level — see models.dart). A rename of any value is therefore a
// data migration — the tests pin every token; treat a rename as a schema
// change, not a refactor. Display glyphs (Ø, EW, …) are derived helpers,
// never stored.

/// A fertility sign observed on a day:
///
/// - `t`: trocken (dry)
/// - `nothing`: nichts gesehen/gespürt — displays as `Ø`
/// - `f`: feucht, reine Empfindung (moist feeling, no mucus)
/// - `s`: S = Schleim aus den Krypten des Gebärmutterhalses (mucus)
/// - `fs`: f/S — "f vor S an einem Tag" (the moist feeling before the
///   mucus, observed on ONE day); displays as `f/S`. A sign of its own:
///   NOT combinable with a quality qualifier (the quality qualifiers stay
///   exclusive to S — the general quality-requires-S rule covers it).
/// - `a`: Ausfluss (discharge) — displays as `A`; no quality exists for it,
///   the quality qualifiers stay exclusive to S.
enum MucusSign { t, nothing, f, s, fs, a }

/// A quality qualifier of the mucus sign S (bare S without a qualifier is
/// equally valid). ONE vocabulary from the cheat sheet, split only by the
/// sheet's "lesser" / "best" table columns:
///
/// - lesser: `w` (weißlich/dicklich/klebrig/zäh), `mi` (milchig), `cr`
///   (cremig), `kl` (klumpig), `glb` (gelblich, dünnflüssiger), `g`
///   (deutlich gelb)
/// - best: `ew` (rohes Eiweiß/Eiklar, fadenziehend — displays `EW`), `gl`
///   (glasig/glasklar/dehnbar), `fl` (flüssig), `ns` (nass/schlüpfrig)
///
/// Note the token collision: `gl` (glasig) and `glb` (gelblich) share a
/// prefix but are two DIFFERENT values — never normalize one into the other.
enum MucusQuality { w, mi, cr, kl, glb, g, ew, gl, fl, ns }

/// Parses a stored/exported sign token back into the enum, or null for
/// anything else. SHARED by the db layer and the export/import writer — the
/// single source of truth for this field's validation, like tryParseBleeding
/// (models.dart), so a row a writer would drop is never counted as a write.
/// Accepts `Object?`: export rows arrive JSON-decoded as the loosest shape.
MucusSign? tryParseMucusSign(Object? raw) {
  if (raw is! String) return null;
  for (final sign in MucusSign.values) {
    if (sign.name == raw) return sign;
  }
  return null;
}

/// Parses a stored/exported quality token back into the enum, or null for
/// anything else. Same contract as [tryParseMucusSign]; the returned value is
/// NOT yet checked against the sign (see [sanitizeMucusPair] for that rule).
MucusQuality? tryParseMucusQuality(Object? raw) {
  if (raw is! String) return null;
  for (final quality in MucusQuality.values) {
    if (quality.name == raw) return quality;
  }
  return null;
}

/// The (sign, quality) pair after the quality-requires-S rule.
///
/// Dart record type so the guard can round-trip BOTH fields; `quality` is
/// null whenever the sign does not permit one.
typedef MucusPair = ({MucusSign? sign, MucusQuality? quality});

/// Enforces "a quality only exists together with sign S" — the one Dart
/// counterpart of the SQL CHECK constraint on cycle_entries.mucus_quality:
/// for any sign other than S (including no sign at all) the quality
/// collapses to null; bare S keeps its (possibly null) quality. The import
/// writer uses this before constructing a [MucusPair] from foreign data.
MucusPair sanitizeMucusPair({
  MucusSign? sign,
  MucusQuality? quality,
}) =>
    (
      sign: sign,
      quality: sign == MucusSign.s ? quality : null,
    );

/// Display glyph of a sign (cheat sheet): `t`, `Ø` for `nothing`, `f`, `S`,
/// `f/S` for `fs` ("f vor S an einem Tag"), `A` for `a` (Ausfluss).
String mucusSignSymbol(MucusSign sign) => switch (sign) {
      MucusSign.t => 't',
      MucusSign.nothing => 'Ø',
      MucusSign.f => 'f',
      MucusSign.s => 'S',
      MucusSign.fs => 'f/S',
      MucusSign.a => 'A',
    };

/// Display token of a quality (cheat sheet): everything keeps its token
/// letter-case except `ew`, which the sheet writes as uppercase `EW`.
String mucusQualityToken(MucusQuality quality) =>
    quality == MucusQuality.ew ? 'EW' : quality.name;

/// The rendered shape of a mucus observation: a base symbol (plus, for S,
/// the quality as a superscript token). Both fields may be null — the UI
/// composes them into `Text.rich` (`Sᴱᵂ`-style) and renders nothing at all
/// when the whole record is null (no observation recorded that day).
typedef MucusDisplay = ({String? symbol, String? superscript});

/// Builds the display record for a (sign, quality) pair. Any `quality` on a
/// sign other than S (or without one) is dropped first via
/// [sanitizeMucusPair], so a mismatched raw pair can never render a
/// superscript on a non-S glyph.
MucusDisplay mucusDisplay({MucusSign? sign, MucusQuality? quality}) {
  final sanitized = sanitizeMucusPair(sign: sign, quality: quality);
  final symbol =
      sanitized.sign == null ? null : mucusSignSymbol(sanitized.sign!);
  final superscript =
      sanitized.quality == null ? null : mucusQualityToken(sanitized.quality!);
  return (symbol: symbol, superscript: superscript);
}
