// Drip CSV import — a PURE domain mapper, host-VM testable (no drift, no
// Flutter, no new dependencies). A drip CSV export becomes a
// current-version export document (see lib/domain/export_import.dart)
// that the write phase feeds through the EXISTING importJsonToDatabase —
// no second db writer for this feature. The mapper derives the
// foreign-import marks (author 'import') from the CSV data —
// deriveDripMarks below; the CSV file format itself is defined in
// docs/dev-notes.md ("Drip CSV import format").

import 'cervix.dart';
import 'date_only.dart';
import 'export_import.dart';
import 'marks.dart';
import 'mucus.dart';
import 'models.dart';

// --- CSV tokenizer ---------------------------------------------------------

/// Tokenizes a drip CSV export into rows of string cells: RFC-4180-style
/// state parsing, because drip quotes notes containing commas, periods or
/// newlines (a naive comma split would corrupt those). A quoted field may
/// span several physical lines and carry `""`-escaped quotes; `\r\n` line
/// endings are tolerated; a trailing newline does not produce an extra
/// empty row.
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
      if (c == 0x22 /* " */ ) {
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
    if (c == 0x2C /* , */ ) {
      endField();
      i++;
      continue;
    }
    if (c == 0x0A /* newline */ ) {
      endRow();
      i++;
      continue;
    }
    if (c == 0x0D /* carriage return */ ) {
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

/// Tokenizes [raw] and validates the drip header (the `date` column is
/// the one column the mapping cannot exist without). Throws a
/// [FormatException] when the input has no header row or no `date`
/// column — the "this is not a drip export" signal for the UI.
List<List<String>> parseDripCsv(String raw) {
  final rows = splitDripCsv(raw);
  final hasDate = rows.isNotEmpty && rows.first.contains('date');
  if (!hasDate) {
    throw const FormatException(
      'not a drip CSV export: no "date" column in the header row',
    );
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

  /// Rows without any data — structured or rescued note text (drip exports
  /// blank calendar days too).
  final int rowsSkippedEmpty;

  /// Rows with data but an unparsable date.
  final int rowsInvalid;

  @override
  String toString() =>
      'DripCsvStats(rowsTotal: $rowsTotal, '
      'rowsImported: $rowsImported, rowsSkippedEmpty: $rowsSkippedEmpty, '
      'rowsInvalid: $rowsInvalid)';
}

/// The result of mapping a drip CSV: the export document plus the
/// parser-side statistics.
final class DripCsvImport {
  const DripCsvImport({required this.json, required this.stats});

  /// A current-version export document (see lib/domain/export_import.dart)
  /// with the mapped entries and the DERIVED marks (author 'import') —
  /// detail in [deriveDripMarks].
  final String json;

  final DripCsvStats stats;
}

/// Maps a raw drip CSV export into a current-version export document
/// (see lib/domain/export_import.dart).
///
/// A row maps to an entry when it carries observations the app stores, or
/// when a stored field's raw text would otherwise be lost — the unmappable
/// drip columns surface as `[tag]` note lines (desire, sex
/// activities/methods, pain kinds, mood flags, mucus/cervix rescue tokens).
/// Every other row counts as skipped-empty (drip exports a row for every
/// day it knows, most of which are blank). Only a broken date invalidates
/// a data row; every other wart degrades field-by-field. The row shape
/// mirrors lib/db/export_adapter.dart's export rows exactly, so the
/// existing writer/planner gates (bleeding vocabulary,
/// quality-requires-S) never drop one of these rows.
///
/// Throws a [FormatException] when [raw] is not a drip CSV at all — see
/// [parseDripCsv].
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

  /// Assembles one `[tag]` note line: the structured tokens joined with
  /// ', ', then the free note appended after a single space; when no token
  /// decoded the line is just the note (and `null` when both parts are
  /// empty).
  String? tagLine(String tag, String structured, String? note) =>
      switch ((structured.isEmpty, note == null)) {
        (true, true) => null,
        (true, false) => '$tag $note',
        (false, true) => '$tag $structured',
        (false, false) => '$tag $structured $note',
      };

  final entries = <Map<String, Object?>>[];
  final excludedDays = <String>{};
  final bleedingExcludedDays = <String>{};
  var skippedEmpty = 0;
  var invalid = 0;

  for (final dataRow in rows.sublist(1)) {
    final dateCell = cell(dataRow, 'date');
    final day = dateCell == null ? null : tryParseIsoDay(dateCell);

    final bbtC = _parseBbtC(cell(dataRow, 'temperature.value'));
    // drip's "not usable for fertility detection" (temperature.exclude)
    // maps to the derived ignoreTemperature MARK — not to an entry flag or
    // mask bits (drip has no reason column); the day still counts as a
    // data row, its entry keeps the neutral mask 0.
    final excluded = boolCell(dataRow, 'temperature.exclude');
    // A time belongs to its measurement: a lone time cell is not data, and
    // the time maps only when a temperature value exists (the same rule
    // DailyEntry enforces on storage).
    final measuredAtMinutes = bbtC == null
        ? null
        : _parseDripTimeMinutes(cell(dataRow, 'temperature.time'));
    final bleeding = _parseBleeding(cell(dataRow, 'bleeding.value'));
    // bleeding.exclude ("ignored" bleeding) is not data, but its day feeds
    // the cycleStart replay's skip set (the entry keeps its bleeding
    // level); when a bleeding value sits under the flag, the level rides
    // with a `[bleedingExclude]` note line.
    final bleedingExcluded = boolCell(dataRow, 'bleeding.exclude');
    final mucusValue = cell(dataRow, 'mucus.value');
    final mucusFeeling = cell(dataRow, 'mucus.feeling');
    final mucusTexture = cell(dataRow, 'mucus.texture');
    final mucus = _mucusObservation(
      nfpNumber: mucusValue,
      feeling: mucusFeeling,
      texture: mucusTexture,
    );
    final cervixOpening = cell(dataRow, 'cervix.opening');
    final cervixFirmness = cell(dataRow, 'cervix.firmness');
    final cervixPosition = cell(dataRow, 'cervix.position');
    final cervixObservation = _cervixObservation(
      opening: cervixOpening,
      firmness: cervixFirmness,
      position: cervixPosition,
    );
    final desireCell = cell(dataRow, 'desire.value');
    // drip tracks sex as activity (solo/partner) plus the contraceptive
    // methods (condom, pill, iud, patch, ring, implant, diaphragm, other —
    // and `none`; drip: components/helpers/labels.js). The stored variant
    // is partner sex WITHOUT contraception, at the MIDDLE time of day
    // (drip carries none) — an unfilled method column also counts as no
    // contraception (owner decision 2026-09-17: drip is a
    // non-authoritative import source). Every other activity/method
    // combination has no stored option of its own; the whole choice is
    // rescued into the [sex] note line below (`sex.none` is a "no method"
    // answer and renders nothing).
    final sexSolo = boolCell(dataRow, 'sex.solo');
    final sexPartner = boolCell(dataRow, 'sex.partner');
    final sexMethods = [
      for (final (column, token) in _sexMethodColumns)
        if (boolCell(dataRow, column)) token,
    ];
    final sex = sexPartner && sexMethods.isEmpty;
    // Structured part of the [sex] line: the activities joined ', ', the
    // methods as a parenthetical glued on with a single space
    // (`[sex] partner (condom)`, `[sex] solo (condom)`, method-only
    // `[sex] (condom)`, `solo + partner` → `[sex] solo, partner`).
    final sexMethodParenthetical = sexMethods.isEmpty
        ? null
        : '(${sexMethods.join(', ')})';
    final sexActivities = [
      if (sexSolo) 'solo',
      if (sexPartner) 'partner',
    ].join(', ');
    final sexStructured = sexMethodParenthetical == null
        ? sexActivities
        : sexActivities.isEmpty
        ? sexMethodParenthetical
        : '$sexActivities $sexMethodParenthetical';
    final sexNote = cell(dataRow, 'sex.note');

    final dayNote = cell(dataRow, 'note.value');
    final tempNote = cell(dataRow, 'temperature.note');

    // drip's pain kinds map onto the letter-coded pain options where a
    // storage option exists: ovulation pain is exactly the Mittelschmerz
    // (M) option, tender breasts the breast-pain (B) option. The kinds
    // without a cycle-app option are rescued into the [pain] note line.
    final painKindTokens = [
      for (final (column, token) in _painKindColumns)
        if (boolCell(dataRow, column)) token,
    ];
    final painBreast = boolCell(dataRow, 'pain.tenderBreasts');
    final painMittelschmerz = boolCell(dataRow, 'pain.ovulationPain');
    final painNote = cell(dataRow, 'pain.note');
    // The mood NOTE is raw note text; the FLAGS have no stored option of
    // their own (Stimmung is removed everywhere) and are rescued into the
    // [mood] note line.
    final moodFlagTokens = [
      for (final column in _moodFlagColumns)
        if (boolCell(dataRow, column)) column.substring('mood.'.length),
    ];
    final moodNote = cell(dataRow, 'mood.note');

    // The rescued note tokens per family: cells whose information the
    // structured decode did NOT capture. `excluded` rides first when the
    // exclusion flag is set, then the family's tokens in drip's column
    // order.
    final mucusTokens = [
      if (boolCell(dataRow, 'mucus.exclude')) 'excluded',
      ..._lostMucusTokens(
        value: mucusValue,
        feeling: mucusFeeling,
        texture: mucusTexture,
        decoded: mucus,
      ),
    ];
    final cervixTokens = [
      if (boolCell(dataRow, 'cervix.exclude')) 'excluded',
      ..._unmappedCervixTokens(
        opening: cervixOpening,
        firmness: cervixFirmness,
        position: cervixPosition,
      ),
    ];

    // Day note first, then the per-symptom note lines in fixed order.
    final notes = [
      dayNote,
      prefixedLine('[temp]', tempNote),
      prefixedLine(
        '[bleedingExclude]',
        bleeding != null && bleedingExcluded ? 'exclude' : null,
      ),
      mucusTokens.isEmpty ? null : '[mucus] ${mucusTokens.join(', ')}',
      cervixTokens.isEmpty ? null : '[cervix] ${cervixTokens.join(', ')}',
      prefixedLine('[desire]', desireCell),
      tagLine('[pain]', painKindTokens.join(', '), painNote),
      tagLine('[sex]', sexStructured, sexNote),
      tagLine('[mood]', moodFlagTokens.join(', '), moodNote),
    ].whereType<String>().where((n) => n.isNotEmpty).join('\n');

    // The structured list holds only signals that map to entry columns or
    // marks and never produce a note token; anything without a stored
    // option rides in `notes` instead.
    final hasData =
        bbtC != null ||
        excluded ||
        bleeding != null ||
        mucus != null ||
        cervixObservation != null ||
        sex ||
        painBreast ||
        painMittelschmerz ||
        notes.isNotEmpty;

    if (day == null || !hasData) {
      if (hasData) {
        invalid++; // data, but an unparsable date
      } else {
        skippedEmpty++; // a blank calendar day
      }
      continue;
    }

    if (excluded) {
      excludedDays.add(formatIsoDay(day));
    }
    if (bleedingExcluded) {
      bleedingExcludedDays.add(formatIsoDay(day));
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
      'sex_timings': sex ? SexTiming.midday.bit : 0,
      'notes': notes.isEmpty ? null : notes,
    };
    entries.add(entry);
  }

  final blob = ExportBlob(
    entries: entries,
    marks: deriveDripMarks(entries, excludedDays, bleedingExcludedDays),
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

/// The drip contraceptive-method columns in drip's CSV order, with the
/// token each renders as inside the [sex] line's parenthetical;
/// `sex.none` is a "no method" answer and renders nothing.
const _sexMethodColumns = <(String, String)>[
  ('sex.condom', 'condom'),
  ('sex.pill', 'pill'),
  ('sex.iud', 'iud'),
  ('sex.patch', 'patch'),
  ('sex.ring', 'ring'),
  ('sex.implant', 'implant'),
  ('sex.diaphragm', 'diaphragm'),
  ('sex.other', 'other'),
];

/// The pain-kind columns without a cycle-app storage option, in drip's CSV
/// order, with the token each renders as in the [pain] line; tenderBreasts
/// and ovulationPain stay structured day flags.
const _painKindColumns = <(String, String)>[
  ('pain.cramps', 'cramps'),
  ('pain.headache', 'headache'),
  ('pain.backache', 'backache'),
  ('pain.nausea', 'nausea'),
  ('pain.migraine', 'migraine'),
  ('pain.other', 'other'),
];

/// The mood-flag columns (no stored option for any of them), in drip's CSV
/// order; each renders under its column suffix in the [mood] line.
const _moodFlagColumns = [
  'mood.happy',
  'mood.sad',
  'mood.stressed',
  'mood.balanced',
  'mood.fine',
  'mood.anxious',
  'mood.energetic',
  'mood.fatigue',
  'mood.angry',
  'mood.other',
];

// The onset-replay lookback: one bleeding-free calendar day does not end
// a bleeding episode — the rule and constant of drip: lib/cycle.js
// isMensesStart.
const _dripMaxBreakInBleeding = 1;

/// Derives the foreign-import marks (author 'import') from the mapped
/// entry rows [entries] carries (replayed verbatim, same rows the export
/// document has; the idempotent marks writer makes a repeated import a
/// no-op). Two mark kinds:
///
/// - `cycleStart`: the drip onset rule (_isDripOnset) — a non-excluded
///   bleeding day at ANY stored level is a cycle start unless another
///   non-excluded bleeding day sits within the previous
///   [_dripMaxBreakInBleeding] + 1 calendar days; bleeding-excluded days
///   are transparent to that lookback (they cannot open) and their
///   entries keep the stored bleeding level.
/// - `ignoreTemperature`: one per [ignoreTemperatureDays] day —
///   bleeding-excluded days alone derive none.
///
/// Rows are judged in DAY order, not CSV row order (the onset rule's
/// lookback must always see the prior days); duplicated day keys keep
/// their first occurrence, like the import merge plan counts them; the
/// derived rows sort deterministically by day, then type.
///
/// Contract: every entry map's `date` parses as an ISO day, and its
/// `bleeding` value — when the key exists at all — is a bleeding level
/// the shared parser accepts (a missing key is "no bleeding recorded").
List<Map<String, Object?>> deriveDripMarks(
  List<Map<String, Object?>> entries,
  Set<String> ignoreTemperatureDays,
  Set<String> bleedingExcludedDays,
) {
  final seenDates = <String>{};
  final replayed = <DailyEntry>[];
  for (final row in entries) {
    final iso = row['date'] as String?;
    if (iso == null || !seenDates.add(iso)) continue;
    final day = tryParseIsoDay(iso);
    if (day == null) continue;
    // A null parse means outside input (junk token, bool, double) — an
    // explicit argument error, not an opaque null-check crash.
    final bleedingRaw = row['bleeding'];
    final bleeding = tryParseBleeding(bleedingRaw);
    if (bleeding == null) {
      throw ArgumentError.value(
        bleedingRaw,
        'bleeding',
        'not an accepted bleeding level (row date: $iso)',
      );
    }
    replayed.add(DailyEntry(date: day, bleeding: bleeding));
  }
  replayed.sort((a, b) => DateOnly.daysBetween(a.date, b.date));

  final marks = <Map<String, Object?>>[];
  DateTime? lastNonExcludedBleeding;
  for (final entry in replayed) {
    final iso = formatIsoDay(entry.date);
    if (ignoreTemperatureDays.contains(iso)) {
      marks.add(<String, Object?>{
        'entry_date': iso,
        'mark_type': CycleMarkTypes.ignoreTemperature,
        'author': 'import',
      });
    }
    if (_isDripOnset(entry, lastNonExcludedBleeding, bleedingExcludedDays)) {
      marks.add(<String, Object?>{
        'entry_date': iso,
        'mark_type': CycleMarkTypes.cycleStart,
        'author': 'import',
      });
    }
    if (entry.bleeding.level >= 1 && !bleedingExcludedDays.contains(iso)) {
      lastNonExcludedBleeding = entry.date;
    }
  }
  marks.sort((a, b) {
    final byDay = (a['entry_date']! as String).compareTo(
      b['entry_date']! as String,
    );
    if (byDay != 0) return byDay;
    return (a['mark_type']! as String).compareTo(b['mark_type']! as String);
  });
  return marks;
}

/// The drip onset rule of the cycleStart replay, ported from drip's
/// isMensesStart (lib/cycle.js): ANY stored bleeding level (1–4; spotting
/// is full-coverage bleeding) opens a cycle unless a non-excluded
/// bleeding day sits within the previous [_dripMaxBreakInBleeding] + 1
/// calendar days — [lastNonExcludedBleeding] carries the most recent such
/// day. An excluded day cannot open and never counts as that suppressing
/// day, but it does not shield either: the calendar days behind it still
/// count toward the window.
bool _isDripOnset(
  DailyEntry entry,
  DateTime? lastNonExcludedBleeding,
  Set<String> bleedingExcludedDays,
) {
  if (bleedingExcludedDays.contains(formatIsoDay(entry.date))) return false;
  if (entry.bleeding.level < 1) return false;
  final last = lastNonExcludedBleeding;
  if (last == null) return true;
  return DateOnly.daysBetween(entry.date, last) > _dripMaxBreakInBleeding + 1;
}

/// Parses a drip temperature cell (`36.2`); any non-number means no
/// measurement (dot decimals only, as drip writes them).
double? _parseBbtC(String? raw) => raw == null ? null : double.tryParse(raw);

/// Parses drip's `temperature.time` cell into minutes since midnight —
/// the vocabulary of [DailyEntry.measuredAtMinutes]. drip writes plain
/// `HH:MM` (24 h, zero-padded); tolerated on top: a single-digit hour,
/// optional `:SS` seconds (`minute` is the storage grain), and
/// surrounding whitespace from spreadsheet round-trips. Anything else —
/// an absent/malformed/out-of-range cell — is null: a time is stored
/// only when drip actually recorded one, never fabricated.
int? _parseDripTimeMinutes(String? raw) {
  final m = RegExp(
    r'^\s*(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?\s*$',
  ).firstMatch(raw ?? '');
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Drip's bleeding heaviness scale (0=spotting … 3=heavy) mapped onto the
/// stored levels +1: the export scale stores an explicit none as 0, which
/// drip represents only as an absent cell. Out-of-range indexes mean no
/// observation (null).
int? _parseBleeding(String? raw) {
  final v = raw == null ? null : int.tryParse(raw);
  if (v == null || v < 0 || v > 3) return null;
  return v + 1; // drip scale → stored level (+1 shift for the explicit none)
}

/// The mucus observation of a drip row: the stored NFP number
/// (`mucus.value`, 0..4) when present, otherwise drip's feeling+texture
/// composite via drip's own getNfpMucus — null unless BOTH parts exist,
/// exactly like drip (drip: lib/nfp-mucus.js). The number decodes onto
/// the TWO-COLUMN mucus model (db columns mucus_sign/mucus_quality):
/// 0 → t, 1 → nothing, 2 → f, 3 → bare s, 4 → s + ew; the pair goes
/// through [sanitizeMucusPair] (quality never rides a non-S sign). Whatever
/// the decode cannot carry back — the parts a number bypasses, a lone
/// part, or an out-of-range composite — rides into the `[mucus]` note
/// line instead (see [_lostMucusTokens]).
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

/// The mucus cells the structured decode cannot carry back, as the
/// `[mucus]` tokens: a `mucus.value` bypasses a present composite, a lone
/// part cannot decode, and an out-of-range composite decodes to nothing —
/// each loses the raw feeling/texture cells, so they are noted verbatim.
/// Nothing is lost when a full in-range composite decoded or no part
/// exists at all.
List<String> _lostMucusTokens({
  required String? value,
  required String? feeling,
  required String? texture,
  required MucusPair? decoded,
}) {
  final tokens = [
    if (feeling != null) 'feeling $feeling',
    if (texture != null) 'texture $texture',
  ];
  if (tokens.isEmpty) return const [];
  if (value != null) return tokens; // the stored value bypassed the composite
  if (feeling == null || texture == null) return tokens; // composite partial
  return decoded == null ? tokens : const []; // composite out of range
}

/// The drip-side NFP number of a row (see [_mucusObservation]): the
/// stored `mucus.value` when parseable, otherwise drip's getNfpMucus
/// composite — feeling {0→0, 1→1, 2→2, 3→4}, texture {0→0, 1→3, 2→4},
/// take the max.
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

/// Structured Muttermund tokens of a drip row, decoded from drip's
/// 0-based vocabularies (drip: labels.js): position {0: low, 1: medium,
/// 2: high}, opening {0: closed, 1: middle, 2: open}, firmness {0: hard,
/// 1: soft} — the two-step firmness scale has no half-soft analogue, so
/// only the two outer values map. drip's "medium" opening token maps onto
/// cycle-app's `middle` (same value, different storage name — see
/// lib/domain/cervix.dart). An out-of-range position/opening index means
/// no stored observation for that dimension (its raw cell rides into the
/// `[cervix]` note line, see [_unmappedCervixTokens]); an out-of-range
/// firmness index CLAMPS to the nearest valid one (the shipped specimen
/// carries `cervix.firmness=2`) and leaves a `firmness <i> → soft` trace
/// in the note line.
/// TODO(user-review): whether that clamping asymmetry is acceptable
/// (position/opening null with the raw cell noted, firmness clamped).
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
    // Clamped both ways, like the free-text `word` helper.
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
    firmness: mappedFirmness,
  );
}

/// The cervix cells whose structured decode came up empty, as `[cervix]`
/// tokens: a position/opening cell that is non-numeric or outside 0..2
/// notes its raw cell verbatim (the information would be lost), while
/// firmness notes only the clamp that actually fired — a raw index of 2
/// or more (a negative index also clamps to hard but leaves no trace,
/// like raw 0/1 which need no clamp, and non-numeric stays unstructured).
List<String> _unmappedCervixTokens({
  required String? opening,
  required String? firmness,
  required String? position,
}) {
  String? unmapped(String kind, String? raw) {
    if (raw == null) return null;
    final index = int.tryParse(raw);
    if (index != null && index >= 0 && index <= 2) return null;
    return '$kind $raw (unmapped)';
  }

  final openingToken = unmapped('opening', opening);
  final positionToken = unmapped('position', position);
  final firmnessIndex = firmness == null ? null : int.tryParse(firmness);
  final firmnessToken = firmnessIndex != null && firmnessIndex >= 2
      ? 'firmness $firmness → soft'
      : null;
  return [?openingToken, ?firmnessToken, ?positionToken];
}
