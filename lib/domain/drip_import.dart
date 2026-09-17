// Drip CSV import — PURE domain layer, host-VM testable (no drift, no
// Flutter, no new dependencies).
//
// Input is the CSV export of the sibling "drip" app (sibling repository
// `drip`): one header row of flattened CycleDay columns like
// `temperature.value`, then one row per calendar day. The format spec is
// drip's own writer (drip: lib/import-export/export-to-csv.js):
//
//  - fields are comma-separated; string cells containing \n \t , ; . '
//    are wrapped in double quotes with inner quotes escaped as "",
//  - rows are joined with plain \n (this parser also tolerates \r\n),
//  - the header lists the columns of whichever drip version exported the
//    file, so all parsing is header-driven: unknown columns are ignored,
//    known-but-missing columns simply carry no data.
//
// Output is a standard export document of the CURRENT schema version (see
// lib/domain/export_import.dart) that the write phase feeds through the
// EXISTING importJsonToDatabase — no second db writer for this feature.
//
// Mapping decisions live in the tables below and in the plan document;
// every assumption an INER expert should re-check carries a
// TODO(user-review) marker.

import 'cervix.dart';
import 'export_import.dart';
import 'mucus.dart';
import 'models.dart';

// --- CSV tokenizer ---------------------------------------------------------

/// Tokenizes a drip CSV export into rows of string cells.
///
/// RFC-4180-style state parsing (drip quotes notes containing commas,
/// periods or newlines — a naive comma split would corrupt those). A quoted
/// field may contain `,` and `""`-escaped quotes and may span several
/// physical lines. `\r\n` line endings are tolerated. A trailing newline
/// does not produce an extra empty row.
List<List<String>> splitDripCsv(String raw) {
  final rows = <List<String>>[];
  final field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  final chars = raw.codeUnits;
  var i = 0;
  while (i < chars.length) {
    final c = chars[i];
    if (inQuotes) {
      if (c == 0x22 /* " */) {
        if (i + 1 < chars.length && chars[i + 1] == 0x22) {
          field.writeCharCode(c); // escaped inner quote
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.writeCharCode(c);
      i++;
      continue;
    }
    if (c == 0x2C /* , */) {
      endField();
      i++;
      continue;
    }
    if (c == 0x0A /* newline */) {
      endRow();
      i++;
      continue;
    }
    if (c == 0x0D /* carriage return */) {
      // Tolerate \r\n; a lone \r also ends the row.
      endRow();
      i++;
      if (i < chars.length && chars[i] == 0x0A) i++;
      continue;
    }
    if (c == 0x22 && field.isEmpty) {
      inQuotes = true; // opening quote of the field
      i++;
      continue;
    }
    field.writeCharCode(c);
    i++;
  }
  // Flush the final row — but not the phantom empty row a trailing newline
  // would otherwise create.
  if (row.isNotEmpty || field.isNotEmpty) endRow();
  return rows;
}

/// Tokenizes [raw] and validates the drip header (the `date` column is the
/// one column the mapping cannot exist without). Throws a [FormatException]
/// when the input has no header row or no `date` column — the "this is not
/// a drip export" signal for the UI.
List<List<String>> parseDripCsv(String raw) {
  final rows = splitDripCsv(raw);
  final hasDate = rows.isNotEmpty && rows.first.contains('date');
  if (!hasDate) {
    throw const FormatException(
        'not a drip CSV export: no "date" column in the header row');
  }
  return rows;
}

// --- drip → export document mapping ---------------------------------------

/// Counts of what [dripCsvToExportJson] saw in the CSV, for the UI summary.
final class DripCsvStats {
  const DripCsvStats({
    required this.rowsTotal,
    required this.rowsImported,
    required this.rowsSkippedEmpty,
    required this.rowsInvalid,
  });

  /// Data rows under the header row (drip exports one row per known day).
  final int rowsTotal;

  /// Rows that produced an entry.
  final int rowsImported;

  /// Rows without any mapped data (drip exports blank calendar days too).
  final int rowsSkippedEmpty;

  /// Rows with data but an unparsable date.
  final int rowsInvalid;

  @override
  String toString() => 'DripCsvStats(rowsTotal: $rowsTotal, '
      'rowsImported: $rowsImported, rowsSkippedEmpty: $rowsSkippedEmpty, '
      'rowsInvalid: $rowsInvalid)';
}

/// The result of mapping a drip CSV: the export document as a JSON string
/// (ready for importJsonToDatabase, lib/db/export_adapter.dart) plus the
/// parser-side statistics.
final class DripCsvImport {
  const DripCsvImport({required this.json, required this.stats});

  /// A current-version export document (see lib/domain/export_import.dart)
  /// with the seeded main profile `[{id: 1, name: 'main', ordinal: 0}]`,
  /// entries only, and an empty marks list — drip has no mark analogue.
  final String json;

  final DripCsvStats stats;
}

/// Maps a raw drip CSV export into a current-version export document (see
/// lib/domain/export_import.dart for the document shape).
///
/// Every row lands under profile 1 (drip has no multi-profile concept). A
/// row maps to an entry only when at least one MAPPED field carries data;
/// otherwise it counts as skipped-empty (drip exports a row for every day
/// it knows, most of which are blank). Only a broken date invalidates a
/// data row; every other wart degrades field-by-field. Unknown header
/// columns are ignored, known-but-missing columns carry no data. The row
/// shape mirrors lib/db/export_adapter.dart's export rows exactly, so the
/// existing writer/planner gates (bleeding vocabulary, quality-requires-S)
/// never drop one of these rows.
///
/// Throws a [FormatException] when [raw] is not a drip CSV at all (no
/// header row / no `date` column) — see [parseDripCsv].
DripCsvImport dripCsvToExportJson(String raw) {
  final rows = parseDripCsv(raw);
  final header = rows.first;
  // First occurrence wins for a doubled column name (defensive; drip never
  // emits duplicates).
  final col = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    col.putIfAbsent(header[i], () => i);
  }

  String cellAt(List<String> row, int index) =>
      index < row.length ? row[index] : '';

  // Column accessors (header-driven: an absent column behaves like an
  // empty cell).
  String? cell(List<String> row, String name) {
    final i = col[name];
    if (i == null) return null;
    final value = cellAt(row, i);
    return value.isEmpty ? null : value;
  }

  bool boolCell(List<String> row, String name) =>
      cell(row, name)?.toLowerCase() == 'true';

  /// Any nonempty cell in the `<family>.*` columns except the family's note.
  bool flagInFamily(List<String> row, String family) {
    final noteColumn = '$family.note';
    final prefix = '$family.';
    for (var i = 0; i < header.length; i++) {
      final name = header[i];
      if (!name.startsWith(prefix) || name == noteColumn) continue;
      if (cellAt(row, i).toLowerCase() == 'true') return true;
    }
    return false;
  }

  String? prefixedLine(String tag, String? text) =>
      text == null ? null : '$tag $text';

  final entries = <Map<String, Object?>>[];
  var skippedEmpty = 0;
  var invalid = 0;

  for (final dataRow in rows.sublist(1)) {
    final dateCell = cell(dataRow, 'date');
    final day = dateCell == null ? null : tryParseIsoDay(dateCell);

    final bbtC = _parseBbtC(cell(dataRow, 'temperature.value'));
    // TODO(user-review): drip's "not usable for fertility detection" is
    // mapped to cycle-app's day-level excludeOther (interrupted day) because
    // drip has no reason field; per-symptom excludes have no storage here.
    final excludeOther = boolCell(dataRow, 'temperature.exclude');
    // drip records the measurement's time of day in temperature.time as
    // plain `HH:MM` (24 h). A time belongs to its measurement — hasData
    // below deliberately does not count a lone time cell as data, and the
    // time is only mapped when a temperature value exists (the same rule
    // DailyEntry enforces on storage; the document must not carry a time
    // this app would never store).
    final measuredAtMinutes = bbtC == null
        ? null
        : _parseDripTimeMinutes(cell(dataRow, 'temperature.time'));
    final bleeding = _parseBleeding(cell(dataRow, 'bleeding.value'));
    final mucus = _mucusObservation(
      nfpNumber: cell(dataRow, 'mucus.value'),
      feeling: cell(dataRow, 'mucus.feeling'),
      texture: cell(dataRow, 'mucus.texture'),
    );
    final cervix = _cervixText(
      opening: cell(dataRow, 'cervix.opening'),
      firmness: cell(dataRow, 'cervix.firmness'),
      position: cell(dataRow, 'cervix.position'),
    );
    // drip ALSO carries the cervix vocabulary indexes (0-based), which map
    // onto the structured Muttermund fields: position low/medium/high,
    // opening closed/medium/open, and firmness hard/soft (an out-of-range
    // firmness index clamps to the nearest valid one — the same clamping
    // rule as the free-text line below). Out-of-range or non-numeric
    // position/opening indexes map to null per field. The free text keeps
    // its (clamping) behavior and is written IN ADDITION to the structured
    // fields — historical fidelity for the hand-authored specimen rows.
    final cervixObservation = _cervixObservation(
      opening: cell(dataRow, 'cervix.opening'),
      firmness: cell(dataRow, 'cervix.firmness'),
      position: cell(dataRow, 'cervix.position'),
    );
    // desire.value is drip's 0=low/1=medium/2=high intensity vocabulary —
    // NOT a real boolean (the flag collapses it: intensity is not storable
    // here, see the mapping table). Any present cell means desire; only a
    // literal trimmed `false` is ignored entirely — not data, not desire
    // (drip lowercases every string cell, so a real export says just
    // `false`).
    final desireCell = cell(dataRow, 'desire.value');
    final desire = desireCell != null && desireCell.trim() != 'false';
    // drip tracks sex as activity (solo/partner) plus the contraceptive
    // methods used (condom, pill, iud, patch, ring, implant, diaphragm,
    // other — and `none`, the explicit "no contraception used" choice;
    // drip: components/helpers/labels.js). cycle-app's sex observation
    // models partner sex WITHOUT contraception, so only a positive
    // confirmation of both halves maps: sex.partner=true AND sex.none=true
    // AND no contraceptive method flag true — and it stores as the MIDDLE
    // time of day, because drip carries no time-of-day for sex (owner
    // decision, see the TODO below). Every other variant — solo sex, a
    // method used, a missing contraceptive answer (partner with no
    // contraceptive column set at all), even none=true next to a method —
    // maps to nothing and is NOT data: a row carrying only such flags is
    // skipped entirely (see the data rule below). The [sex] note line
    // keeps its note-driven behavior independent of the flag.
    // TODO(user-review): solo sex and the contraceptive methods have no
    // storage option; whether solo sex deserves an option of its own. The
    // middle-of-day choice for the mapped variant is likewise a mapping
    // convenience: drip is a single non-authoritative import source and
    // must not force the app's design.
    final sexPartner = boolCell(dataRow, 'sex.partner');
    final sexNone = boolCell(dataRow, 'sex.none');
    final sexMethod = [
      'sex.condom',
      'sex.pill',
      'sex.iud',
      'sex.patch',
      'sex.ring',
      'sex.implant',
      'sex.diaphragm',
      'sex.other',
    ].any((name) => boolCell(dataRow, name));
    final sex = sexPartner && sexNone && !sexMethod;

    final dayNote = cell(dataRow, 'note.value');
    final tempNote = cell(dataRow, 'temperature.note');
    final painNote = cell(dataRow, 'pain.note');
    final sexNote = cell(dataRow, 'sex.note');
    final moodNote = cell(dataRow, 'mood.note');
    // drip's pain kinds map onto the letter-coded pain options where a
    // storage option exists: ovulation pain is exactly the Mittelschmerz
    // (M) option, tender breasts the breast-pain (B) option.
    final painBreast = boolCell(dataRow, 'pain.tenderBreasts');
    final painMittelschmerz = boolCell(dataRow, 'pain.ovulationPain');
    // Kinds without a cycle-app option (cramps, headache, …) are dropped
    // like the other dropped columns — NOT data: a row carrying only such
    // a flag imports nothing (but the pain note below still does).
    // TODO(user-review): whether the remaining pain kinds deserve options
    // of their own instead of being dropped.
    final mood = flagInFamily(dataRow, 'mood') || moodNote != null;

    // A row is only worth an entry when something mappable was recorded.
    // Dropped columns (bleeding/mucus/cervix excludes, the sex variants that
    // do not map — solo, a contraceptive method, missing contraceptive
    // info —, unmappable pain kinds, symptom-flag FALSEs) are
    // NOT data — otherwise every blank drip day would import. A measured
    // time belongs to its measurement, so a time cell alone never makes a
    // blank day an entry.
    final hasData = bbtC != null ||
        excludeOther ||
        bleeding != null ||
        mucus != null ||
        cervix != null ||
        desire ||
        sex ||
        painBreast ||
        painMittelschmerz ||
        painNote != null ||
        mood ||
        dayNote != null ||
        tempNote != null ||
        sexNote != null;

    if (day == null || !hasData) {
      if (hasData) {
        invalid++; // data, but an unparsable date
      } else {
        skippedEmpty++; // a blank calendar day
      }
      continue;
    }

    // Notes assembly: day note first, then the per-symptom notes in fixed
    // [temp] → [pain] → [sex] → [mood] order.
    // TODO(user-review): the "[tag] text" note format itself.
    final notes = [
      dayNote,
      prefixedLine('[temp]', tempNote),
      prefixedLine('[pain]', painNote),
      prefixedLine('[sex]', sexNote),
      prefixedLine('[mood]', moodNote),
    ].whereType<String>().where((n) => n.isNotEmpty).join('\n');

    final entry = <String, Object?>{
      'profile_id': 1,
      'date': formatIsoDay(day),
      'bbt_c': bbtC,
      'measured_at_minutes': measuredAtMinutes,
      'bleeding': bleeding ?? 0,
      'exclude_illness': false,
      'exclude_alcohol': false,
      'exclude_travel': false,
      'exclude_other': excludeOther,
      'mucus_sign': mucus?.sign?.name,
      'mucus_quality': mucus?.quality?.name,
      'cervix': cervix,
      'cervix_position': cervixObservation?.position?.name,
      'cervix_opening': cervixObservation?.opening?.name,
      'cervix_firmness': cervixObservation?.firmness?.name,
      'pain_breast': painBreast,
      'pain_mittelschmerz': painMittelschmerz,
      'mood': mood,
      'desire': desire,
      'sex_timings': sex ? SexTiming.middle.bit : 0,
      'notes': notes.isEmpty ? null : notes,
    };
    entries.add(entry);
  }

  final blob = ExportBlob(
    profiles: const [
      {'id': 1, 'name': 'main', 'ordinal': 0},
    ],
    entries: entries,
    marks: const <Map<String, Object?>>[],
    exportedAt: DateTime.now(),
  );

  return DripCsvImport(
    json: buildExportJson(blob),
    stats: DripCsvStats(
      rowsTotal: rows.length - 1,
      rowsImported: entries.length,
      rowsSkippedEmpty: skippedEmpty,
      rowsInvalid: invalid,
    ),
  );
}

// --- vocabulary tables (drip: components/helpers/labels.js, 0-based) -------

/// Parses a drip temperature cell (`36.2`); any non-number means no
/// measurement (dot decimals only, as drip writes them).
double? _parseBbtC(String? raw) => raw == null ? null : double.tryParse(raw);

/// Parses drip's `temperature.time` cell into minutes since midnight — the
/// vocabulary of [DailyEntry.measuredAtMinutes] / the export document's
/// `measured_at_minutes` field.
///
/// drip writes plain `HH:MM` (24 h, zero-padded); tolerated on top: a
/// single-digit hour, optional `:SS` seconds (ignored — minute is the
/// storage grain), and surrounding whitespace from spreadsheet round-trips.
/// Anything else — an absent/malformed/out-of-range cell (25:00, 07:60,
/// no time shape at all, a bare number) — is null: a time is only stored
/// when drip actually recorded one, never fabricated. Mirrors the
/// tolerant-parse pattern of [tryParseMeasuredAtMinutes] (lib/domain/
/// models.dart), which the db writer re-runs on the produced document.
int? _parseDripTimeMinutes(String? raw) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?\s*$').firstMatch(
    raw ?? '',
  );
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Drip's bleeding heaviness scale: 0=spotting, 1=light, 2=medium, 3=heavy.
/// Maps onto the stored numeric levels shifted by +1 (1=spotting … 4=heavy)
/// because the export document's scale also stores an explicit none (0);
/// drip represents "no bleeding" only as an absent CSV cell. Out-of-range
/// indexes mean no observation (null). The returned values are exactly the
/// numbers the shared parser accepts (tryParseBleeding, models.dart), so
/// the writer/planner gates (export_import.dart) can never drop one of
/// these rows.
int? _parseBleeding(String? raw) {
  final v = raw == null ? null : int.tryParse(raw);
  if (v == null || v < 0 || v > 3) return null;
  return v + 1; // drip scale → stored level (+1 shift for the explicit none)
}

/// The mucus observation of a drip row: the stored combined NFP number
/// (`mucus.value`, 0..4) when present, otherwise the feeling+texture
/// composite via drip's own getNfpMucus — null unless BOTH parts exist,
/// exactly like drip (drip: lib/nfp-mucus.js, its spec counts feeling-only
/// rows as null). Out-of-range numbers/part indexes mean no observation.
///
/// The NFP number decodes onto the TWO-COLUMN mucus model (db columns
/// mucus_sign/mucus_quality, no numeric or feeling mucus field exists):
/// 0 → t, 1 → nothing, 2 → f, 3 → bare s, 4 → s + ew ("S+ ≙ S EW"). The
/// returned pair goes through the shared [sanitizeMucusPair], so a quality
/// can never ride a non-S sign (the SQL CHECK rule).
/// TODO(user-review): the number-level decode is a 1:1 scale match
/// (identical letters in both apps) but loses texture nuances drip itself
/// never stored: NFP 3 written from texture "creamy" would carry quality
/// `cr` if mapped per token, and NFP 4 written from feeling "slippery"
/// alone reads as `ew` here though the cheat sheet would say `ns`.
MucusPair? _mucusObservation({
  required String? nfpNumber,
  required String? feeling,
  required String? texture,
}) {
  final nfp = _resolveNfp(
    nfpNumber: nfpNumber,
    feeling: feeling,
    texture: texture,
  );
  if (nfp == null || nfp < 0 || nfp > 4) return null;
  final sign = switch (nfp) {
    0 => MucusSign.t,
    1 => MucusSign.nothing,
    2 => MucusSign.f,
    _ => MucusSign.s, // 3 and 4
  };
  final quality = nfp == 4 ? MucusQuality.ew : null;
  return sanitizeMucusPair(sign: sign, quality: quality);
}

/// The drip-side NFP number of a row (see [_mucusObservation]): the stored
/// `mucus.value` when parseable, otherwise drip's getNfpMucus composite —
/// feeling {0→0, 1→1, 2→2, 3→4}, texture {0→0, 1→3, 2→4}, take the max.
/// Stored value wins (drip always keeps them consistent).
int? _resolveNfp({
  required String? nfpNumber,
  required String? feeling,
  required String? texture,
}) {
  final stored = nfpNumber == null ? null : int.tryParse(nfpNumber);
  if (stored != null) return stored;
  final f = feeling == null ? null : int.tryParse(feeling);
  final t = texture == null ? null : int.tryParse(texture);
  if (f == null || t == null) return null; // both parts required, like drip
  const feelingToNfp = {0: 0, 1: 1, 2: 2, 3: 4};
  const textureToNfp = {0: 0, 1: 3, 2: 4};
  final nfpF = feelingToNfp[f];
  final nfpT = textureToNfp[t];
  if (nfpF == null || nfpT == null) return null;
  return nfpF > nfpT ? nfpF : nfpT; // Math.max
}

/// Builds the free-text cervix note from drip's 0-based vocabularies
/// (drip: labels.js — opening closed/medium/open, firmness hard/soft,
/// position low/medium/high), joined `, ` in reading order
/// (opening, firmness, position). Out-of-range indexes clamp to the nearest
/// valid one (the shipped hand-authored specimen contains
/// `cervix.firmness=2`); a fully empty triple is null.
/// TODO(user-review): the English wording and the clamping rule.
String? _cervixText({
  required String? opening,
  required String? firmness,
  required String? position,
}) {
  const openingWords = ['closed', 'medium', 'open'];
  const firmnessWords = ['hard', 'soft'];
  const positionWords = ['low', 'medium', 'high'];

  String? word(String? raw, List<String> vocabulary) {
    if (raw == null) return null;
    final v = int.tryParse(raw);
    if (v == null) return null;
    final clamped = v < 0 ? 0 : (v > vocabulary.length - 1 ? vocabulary.length - 1 : v);
    return vocabulary[clamped];
  }

  final parts = [
    word(opening, openingWords),
    word(firmness, firmnessWords),
    word(position, positionWords),
  ].whereType<String>().toList();
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

/// Structured Muttermund tokens of a drip row, decoded from drip's 0-based
/// vocabularies (drip: labels.js): position {0: CervixPosition.low,
/// 1: medium, 2: high}, opening {0: CervixOpening.closed, 1: middle,
/// 2: open}, and firmness {0: CervixFirmness.hard, 1: soft} — drip's
/// two-step firmness scale (hard/soft) has no half-soft analogue, so only
/// the two outer values map. drip's "medium" opening token maps onto
/// cycle-app's `middle` (same value, different storage name — see
/// lib/domain/cervix.dart for the deliberate token distinction). A
/// position/opening index outside the vocabulary means no stored
/// observation for that dimension; a firmness index outside its two-step
/// vocabulary CLAMPS to the nearest valid one — the same clamping rule the
/// free-text line applies (the shipped hand-authored specimen contains
/// `cervix.firmness=2`). TODO(user-review): whether that clamping asymmetry
/// is acceptable (position/opening null, firmness clamped) now that the
/// structured firmness field exists — the free-text line clamps either way.
({CervixPosition? position, CervixOpening? opening, CervixFirmness? firmness})?
    _cervixObservation({
  required String? opening,
  required String? firmness,
  required String? position,
}) {
  final p = position == null ? null : int.tryParse(position);
  final o = opening == null ? null : int.tryParse(opening);
  final f = firmness == null ? null : int.tryParse(firmness);
  final mappedPosition = p == null || p < 0 || p > 2
      ? null
      : CervixPosition.values[p]; // 0, 1, 2 = the first three values
  final mappedOpening = o == null || o < 0 || o > 2
      ? null
      : CervixOpening.values[o]; // 0, 1, 2 = all three values
  final mappedFirmness = switch (f) {
    // Clamp both ways, like the free-text `word` helper: drip's vocabulary
    // is only hard(0)/soft(1), and the specimen's out-of-range 2 lands on
    // soft exactly as it does in the free text.
    null => null,
    final v when v <= 0 => CervixFirmness.hard,
    _ => CervixFirmness.soft, // anything >= 1 clamps to soft
  };
  if (mappedPosition == null &&
      mappedOpening == null &&
      mappedFirmness == null) {
    return null;
  }
  return (position: mappedPosition, opening: mappedOpening,
      firmness: mappedFirmness);
}
