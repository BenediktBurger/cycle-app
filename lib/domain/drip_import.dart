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
// On top of the mapped entries the mapper DERIVES marks (author 'import')
// from the CSV content: cycleStart marks from the bleeding sequence via the
// shared suggestion predicate (isSuggestedCycleStart,
// lib/domain/cycle_grouping.dart) — bleeding only SUGGESTS a cycle start;
// the derived mark is what the mark-driven cycle grouping consumes (see
// lib/domain/marks.dart) — and ignoreTemperature marks from
// temperature.exclude (drip's "not usable for fertility detection": the
// roadmap's "drip excluded temp → a mark, not an observation"). Cycle-app's
// own export already carries its marks verbatim, so re-importing an app
// export never re-derives anything: the derivation lives only in this CSV
// mapping. The produced document (and every row map in it) is profile-free.
//
// Mapping decisions live in the mapping table right below; every
// assumption an INER expert should re-check carries a
// TODO(user-review) marker.

import 'cervix.dart';
import 'cycle_grouping.dart';
import 'date_only.dart';
import 'export_import.dart';
import 'marks.dart';
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
  /// — profile-free: the document root is exactly schema_version /
  /// exported_at / entries / marks — with the mapped entries and the
  /// DERIVED marks (author 'import'): cycleStart marks for the suggested
  /// cycle-start days and ignoreTemperature marks for the
  /// temperature.exclude days (drip has no mark analogue of its own, so
  /// foreign imports get their cycle boundaries and analysis exclusions
  /// derived from the imported data).
  final String json;

  final DripCsvStats stats;
}

/// Maps a raw drip CSV export into a current-version export document (see
/// lib/domain/export_import.dart for the document shape).
///
/// A row maps to an entry only when at least one MAPPED field carries data;
/// otherwise it counts as skipped-empty (drip exports a row for every day
/// it knows, most of which are blank). Only a broken date invalidates a
/// data row; every other wart degrades field-by-field. Unknown header
/// columns are ignored, known-but-missing columns carry no data. The row
/// shape mirrors lib/db/export_adapter.dart's export rows exactly, so the
/// existing writer/planner gates (bleeding vocabulary, quality-requires-S)
/// never drop one of these rows — and the derived cycleStart marks ride
/// the same merge plan (any non-empty mark_type is accepted; the marks
/// writer adds idempotently).
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

  String? prefixedLine(String tag, String? text) =>
      text == null ? null : '$tag $text';

  final entries = <Map<String, Object?>>[];
  final excludedDays = <String>{};
  var skippedEmpty = 0;
  var invalid = 0;

  for (final dataRow in rows.sublist(1)) {
    final dateCell = cell(dataRow, 'date');
    final day = dateCell == null ? null : tryParseIsoDay(dateCell);

    final bbtC = _parseBbtC(cell(dataRow, 'temperature.value'));
    // drip's "not usable for fertility detection" (temperature.exclude)
    // maps to the derived ignoreTemperature MARK (author 'import') —
    // NOT to an entry flag and NOT to mask bits (drip has no reason
    // column). The day still counts as a data row (the exclusion is
    // meaningful data, and the mark needs its day), but the entry itself
    // carries the neutral mask 0 and no exclude_* key.
    final excluded = boolCell(dataRow, 'temperature.exclude');
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
    // drip ALSO carries the cervix vocabulary indexes (0-based), which map
    // onto the structured Muttermund fields: position low/medium/high,
    // opening closed/medium/open, and firmness hard/soft (an out-of-range
    // firmness index clamps to the nearest valid one). Out-of-range or
    // non-numeric position/opening indexes map to null per field.
    final cervixObservation = _cervixObservation(
      opening: cell(dataRow, 'cervix.opening'),
      firmness: cell(dataRow, 'cervix.firmness'),
      position: cell(dataRow, 'cervix.position'),
    );
    // desire.value is DROPPED entirely (Lust is removed everywhere): the
    // intensity was never storable and the flag is not data any more — a
    // desire-only row imports nothing (skipped-empty).
    // drip tracks sex as activity (solo/partner) plus the contraceptive
    // methods used (condom, pill, iud, patch, ring, implant, diaphragm,
    // other — and `none`, the "no contraception used" choice;
    // drip: components/helpers/labels.js). cycle-app's sex observation
    // models partner sex WITHOUT contraception, so the mapped variant is
    // sex.partner=true with no contraceptive method flag true — the
    // explicit `none` confirmation is NOT required: an unfilled method
    // column also counts as no contraception (owner decision,
    // 2026-09-17 — drip is a single non-authoritative import source and
    // must not force the app's sex model to demand a positive "none"
    // answer). The stored variant keeps the MIDDLE time of day, because
    // drip carries no time-of-day for sex. Every other activity variant —
    // solo sex, a method used, even none=true next to a method — maps to
    // nothing and is NOT data: a row carrying only such flags is skipped
    // entirely (see the data rule below). The [sex] note line keeps its
    // note-driven behavior independent of the flag.
    // TODO(user-review): solo sex and the contraceptive methods have no
    // storage option; whether solo sex deserves an option of its own. The
    // middle-of-day choice for the mapped variant is likewise a mapping
    // convenience: drip is a single non-authoritative import source and
    // must not force the app's design.
    final sexPartner = boolCell(dataRow, 'sex.partner');
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
    final sex = sexPartner && !sexMethod;

    final dayNote = cell(dataRow, 'note.value');
    final tempNote = cell(dataRow, 'temperature.note');
    final painNote = cell(dataRow, 'pain.note');
    final sexNote = cell(dataRow, 'sex.note');
    // The mood NOTE is raw note text — still data (notes are raw notes).
    // The mood FLAGS are dropped (Stimmung is removed everywhere).
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

    // A row is only worth an entry when something mappable was recorded.
    // Dropped columns (bleeding/mucus/cervix excludes, the sex variants
    // that do not map — solo, a contraceptive method —, unmappable pain
    // kinds, symptom-flag FALSEs, the dropped mood/desire FLAGS) are NOT
    // data — otherwise every blank drip day would import. A measured time
    // belongs to its measurement, so a time cell alone never makes a blank
    // day an entry. A row carrying ONLY an out-of-range cervix
    // position/opening index is skipped as well — such an index decodes to
    // no stored observation (the clamp word the old free-text helper
    // fabricated was noise).
    final hasData = bbtC != null ||
        excluded ||
        bleeding != null ||
        mucus != null ||
        cervixObservation != null ||
        sex ||
        painBreast ||
        painMittelschmerz ||
        painNote != null ||
        moodNote != null ||
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

    if (excluded) {
      excludedDays.add(formatIsoDay(day));
    }
    final entry = <String, Object?>{
      'date': formatIsoDay(day),
      'bbt_c': bbtC,
      'measured_at_minutes': measuredAtMinutes,
      'bleeding': bleeding ?? 0,
      'temp_disturbances': 0,
      'mucus_sign': mucus?.sign?.name,
      'mucus_quality': mucus?.quality?.name,
      'cervix_position': cervixObservation?.position?.name,
      'cervix_opening': cervixObservation?.opening?.name,
      'cervix_firmness': cervixObservation?.firmness?.name,
      'pain_breast': painBreast,
      'pain_mittelschmerz': painMittelschmerz,
      'sex_timings': sex ? SexTiming.middle.bit : 0,
      'notes': notes.isEmpty ? null : notes,
    };
    entries.add(entry);
  }

  final blob = ExportBlob(
    entries: entries,
    marks: deriveDripMarks(entries, excludedDays),
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

/// Derives the foreign-import marks from the mapped entry rows (drip has
/// no mark analogue of its own, so the cycle-start boundaries and the
/// analysis exclusions are derived from the imported data; the derivation
/// replays the exact rows that the export document carries, and the
/// idempotent marks writer makes a repeated import of the same CSV a
/// no-op). The rows carry no profile id (there is none).
///
/// Two mark kinds, both with author 'import':
/// - `cycleStart`: replayed through the SHARED suggestion predicate
///   [isSuggestedCycleStart] — no derivation-local bleeding rule: a
///   menstruation-level day (light or heavier) that does not continue the
///   previous calendar day's menstruation-level flow suggests a cycle
///   start. The suppression is keyed PURELY to bleeding continuity
///   (temperature-only semantics): [excludedDays] (the temperature.exclude
///   days) does NOT feed the predicate — an ignored bleeding day derives
///   its own cycleStart mark like any other menstruation-level day.
/// - `ignoreTemperature`: one per temperature.exclude day — the roadmap's
///   "drip excluded temp → a mark, not an observation". Drip has no reason
///   column, so no mask bits come from drip.
///
/// Replay details (kept in step with the import merge plan):
/// - the rows are judged in DAY order, not CSV row order (drip exports one
///   row per calendar day, but the previous-day check of the predicate
///   must always see the prior day, wherever it sat in the file);
/// - duplicated same-day keys keep their FIRST occurrence, like the merge
///   plan counts them;
/// - the derived rows are ordered by day, then type (deterministic
///   document order; the merge is idempotent regardless of order).
///
/// Row contract: each entry map carries a parsable `date`, and its
/// `bleeding` value (when the key is present at all) is a bleeding level
/// the shared parser accepts — a MISSING key is "no bleeding recorded"
/// through tryParseBleeding's null rule. [entries] are the SAME row maps
/// the export document carries (they replay verbatim).
List<Map<String, Object?>> deriveDripMarks(
    List<Map<String, Object?>> entries, Set<String> excludedDays) {
  final seenDates = <String>{};
  final replayed = <DailyEntry>[];
  for (final row in entries) {
    final iso = row['date'] as String?;
    if (iso == null || !seenDates.add(iso)) continue;
    final day = tryParseIsoDay(iso);
    if (day == null) continue;
    replayed.add(DailyEntry(
      date: day,
      // No fallback: the shared parser maps a MISSING key (JSON null) to
      // "no bleeding recorded" itself, and the mapper above emits only
      // accepted levels in this field.
      bleeding: tryParseBleeding(row['bleeding'])!,
    ));
  }
  replayed.sort((a, b) => DateOnly.daysBetween(a.date, b.date));

  final marks = <Map<String, Object?>>[];
  for (var i = 0; i < replayed.length; i++) {
    final entry = replayed[i];
    final iso = formatIsoDay(entry.date);
    if (excludedDays.contains(iso)) {
      marks.add(<String, Object?>{
        'entry_date': iso,
        'mark_type': CycleMarkTypes.ignoreTemperature,
        'author': 'import',
      });
    }
    // The ignored-day set feeds ONLY the ignoreTemperature mark
    // derivation above — the suggestion predicate reads bleeding
    // continuity alone (temperature-only semantics, owner decision
    // 2026-09-18).
    final previous = i == 0 ? null : replayed[i - 1];
    if (isSuggestedCycleStart(entry, previous)) {
      marks.add(<String, Object?>{
        'entry_date': iso,
        'mark_type': CycleMarkTypes.cycleStart,
        'author': 'import',
      });
    }
  }
  marks.sort((a, b) {
    final byDay =
        (a['entry_date']! as String).compareTo(b['entry_date']! as String);
    if (byDay != 0) return byDay;
    return (a['mark_type']! as String).compareTo(b['mark_type']! as String);
  });
  return marks;
}

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
/// these rows. The stored scale's top level maximum(5) has no drip
/// equivalent — drip's scale tops out at heavy(4), so a drip import can
/// never produce it.
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
/// vocabulary CLAMPS to the nearest valid one (the shipped hand-authored
/// specimen contains `cervix.firmness=2`). TODO(user-review): whether that
/// clamping asymmetry is acceptable (position/opening null, firmness
/// clamped).
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
  return (
    position: mappedPosition,
    opening: mappedOpening,
    firmness: mappedFirmness
  );
}
