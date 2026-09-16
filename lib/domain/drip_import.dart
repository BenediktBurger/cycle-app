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

import 'export_import.dart';
import 'models.dart';
import 'mucus.dart';

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

/// Maps a raw drip CSV export into a v1 export document.
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
    // below deliberately does not count a lone time cell as data.
    final measuredAtMinutes =
        _parseDripTimeMinutes(cell(dataRow, 'temperature.time'));
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
    // desire.value is drip's 0=low/1=medium/2=high intensity vocabulary —
    // NOT a real boolean (the flag collapses it: intensity is not storable
    // here, see the mapping table). Any present cell means desire; only a
    // literal trimmed `false` is ignored entirely — not data, not desire
    // (drip lowercases every string cell, so a real export says just
    // `false`).
    final desireCell = cell(dataRow, 'desire.value');
    final desire = desireCell != null && desireCell.trim() != 'false';
    final sex = boolCell(dataRow, 'sex.solo') || boolCell(dataRow, 'sex.partner');

    final dayNote = cell(dataRow, 'note.value');
    final tempNote = cell(dataRow, 'temperature.note');
    final painNote = cell(dataRow, 'pain.note');
    final sexNote = cell(dataRow, 'sex.note');
    final moodNote = cell(dataRow, 'mood.note');
    final pain = flagInFamily(dataRow, 'pain') || painNote != null;
    final mood = flagInFamily(dataRow, 'mood') || moodNote != null;

    // A row is only worth an entry when something mappable was recorded.
    // Dropped columns (bleeding/mucus/cervix excludes, contraceptive flags
    // without activity, symptom-flag FALSEs) are NOT data — otherwise every
    // blank drip day would import. A measured time belongs to its
    // measurement, so a time cell alone never makes a blank day an entry.
    final hasData = bbtC != null ||
        excludeOther ||
        bleeding != null ||
        mucus != null ||
        cervix != null ||
        desire ||
        sex ||
        pain ||
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
      'bleeding': bleeding?.name ?? Bleeding.none.name,
      'exclude_illness': false,
      'exclude_alcohol': false,
      'exclude_travel': false,
      'exclude_other': excludeOther,
      'mucus_sign': mucus?.sign?.name,
      'mucus_quality': mucus?.quality?.name,
      'cervix': cervix,
      'pain': pain,
      'mood': mood,
      'desire': desire,
      'sex': sex,
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
/// 1–3 collapse to the day-level `period` value — cycle-app stores no
/// heaviness yet. Out-of-range indexes mean no observation.
/// TODO(user-review): the light/medium/heavy collapse (roadmap already
/// tracks "different bleeding levels" as a future split).
Bleeding? _parseBleeding(String? raw) {
  final v = raw == null ? null : int.tryParse(raw);
  if (v == null || v < 0 || v > 3) return null;
  return v == 0 ? Bleeding.spotting : Bleeding.period;
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
