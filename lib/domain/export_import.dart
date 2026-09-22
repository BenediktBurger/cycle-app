// JSON export/import for the whole local database — PURE domain layer.
//
// Export document shape (schema version 6, profile-free):
//
//   {
//     "schema_version": 6,
//     "exported_at": "<ISO 8601 UTC>",
//     "entries":  [{"date": "2026-03-01", "bbt_c": 36.6,
//                    "measured_at_minutes": 405, ...
//
//                    SPARSE entry rows (v6): every entry key whose value
//                    equals the field's NEUTRAL value is omitted — no
//                    not-recorded/not-observed field is written at all:
//                      - `date` always;
//                      - `bbt_c` only when a temperature exists
//                        (`measured_at_minutes` only when it also carries a
//                        recorded time inside 0..1439 — minutes since
//                        midnight, when the temperature was measured; a time
//                        never rides without its temperature, and the import
//                        side drops a stray time, never the row);
//                      - `bleeding` only for the non-neutral levels 1..5
//                        (a MISSING key — or an explicit JSON null — reads
//                        as level 0 = "no bleeding recorded");
//                      - `temp_disturbances`, `sex_timings` only when their
//                        masks are non-zero (`temp_disturbances` carries the
//                        raw disturbance mask 0..15; the analysis exclusion
//                        is NOT entry raw data — it rides as an
//                        ignoreTemperature mark row);
//                      - `pain_breast`, `pain_mittelschmerz` only when true;
//                      - `mucus_sign`, `mucus_quality`,
//                        `cervix_position`, `cervix_opening`,
//                        `cervix_firmness`, `notes` only when non-null
//                    ...}, ...],
//     "marks":    [{"entry_date": "2026-03-12",
//                   "mark_type": "ignoreTemperature",
//                   "author": "user"}, ...]
//   }
//
// Marks rows are NOT sparse: all three keys are carried always.
//
// An EMPTY-STRING `notes` is non-null and thus KEPT — only null is omitted.
// The reader accepts FULL maps just the same: extra keys and explicit
// neutral values (a level-0 `bleeding`, false pain flags, null fields)
// never error, so old full-key documents and hand-built maps stay valid
// inputs. The bleeding key carries a NUMERIC level (0=none … 5); see the
// version note below.
//
// The document root is exactly schema_version / exported_at / entries /
// marks — there are NO profile keys anywhere (the Profiles table, the
// profile_id columns and the per-profile machinery are gone from the
// schema; see the version note below). Old (v1–4) documents DO carry
// `profile_id` on every row and a root `profiles` list: those keys are
// ACCEPTED and IGNORED on import — rows merge by day / (day, mark_type),
// never by profile.
//
// Per-version entry fields: v1 omitted `measured_at_minutes` and carried
// bleeding as one of the legacy string tokens none/period/spotting; v2
// added `measured_at_minutes` but still carried token bleeding; v3 carries
// the numeric bleeding level (0=none … 4=heavy); v4 replaced the generic
// `pain` flag with the letter-coded pain options `pain_breast` (B) and
// `pain_mittelschmerz` (M). v5 aligns the data entry with the NER scheme:
// entries drop the exclude_* booleans and the mood/desire
// flags and gain `temp_disturbances` (the raw disturbance mask 0..15,
// sp/a/alk/kr; see models.dart); the analysis exclusion rides as the
// ignoreTemperature MARK row. v6 (current) makes the ENTRY rows sparse —
// every neutral-valued key is omitted, and a missing `bleeding` key means
// "no bleeding recorded" on the reader side (see
// tryParseBleeding in models.dart). The version bump is a LOUD gate for old
// readers: a ≤v5 reader treats a missing bleeding key as row-INVALID and
// would silently drop every bleeding-free day of a sparse document
// (temperatures included), so old apps fail visibly with "unsupported
// schema_version" instead of losing data invisibly. The current export
// scale's numeric bleeding
// field spans 0=none … 5=maximum — the level-5 member was added after v5
// was pinned, without a schema_version bump (the version-agnostic field
// parser accepts both older and extended v5 documents; see
// tryParseBleeding). Old-document translation (inside the
// import transaction, lib/db/export_adapter.dart): `exclude_illness` →
// the kr bit (8), `exclude_alcohol` → the alk bit (4), `exclude_travel` /
// `exclude_other` dropped as raw data (no equivalent flag exists) — and
// ANY of the four true derives an ignoreTemperature mark (author
// 'import') for that day, preserving the old interrupted-day analysis
// semantics; `mood` / `desire` are dropped (the row stays valid, notes
// untouched).
//
// The import side is LENIENT within the accepted version set: field values
// are parsed per field by the shared helpers regardless of the version
// (see tryParseBleeding / tryParseMeasuredAtMinutes /
// tryParseTempDisturbances), so an old document and the current one flow
// through the same field parsers. Legacy ≤v3 documents may still carry the
// generic `pain: true` flag: it has no B/M identity, so it is TOLERATED but
// dropped by the field mapping (the row stays valid, the flag information
// is not carried over).
//
// Version note on the v4 REDEFINITION (pre-release): v4 was never published
// before the sex/cervix vocabulary landed, so its shape was redefined in
// place instead of growing a version — the old `sex` boolean is REPLACED by
// the `sex_timings` bitmask (0..7, the SexTiming bits; see models.dart) and
// `cervix_firmness` extends it ADDITIVELY. The free-text `cervix` note key
// was later dropped the same way (owner decision: the three Muttermund
// vocabularies carry the observation; prose belongs in `notes`). No legacy
// tolerance shims exist for any of these keys: there are no such documents
// in the wild with an old shape, and a stray `sex` or `cervix` key is
// simply ignored (unknown keys never error — see below).
//
// Additive fields without a version bump: the Muttermund observation
// fields `cervix_position` / `cervix_opening` (tokens of the
// lib/domain/cervix.dart vocabularies) ride ADDITIVELY, because the reader
// ignores unknown/extra keys in BOTH directions: older apps reading a
// newer document keep every other field (the new keys are ignored, not an
// error), and newer apps read old documents that simply omit the fields.
// An unknown/out-of-vocabulary token collapses to null on import without
// dropping the row (never a row killer, same principle as mucus); an
// out-of-range `sex_timings` mask or `temp_disturbances` mask likewise
// collapses to 0.
//
// The document builds from GENERIC row maps so this layer stays decoupled
// from drift data classes; the drift <-> map conversion lives in
// lib/db/export_adapter.dart. Only the JSON shape/semantics live here.
//
// Import merge policy (resolved decision, see exportMergePolicy): entries
// merge by DAY with an OVERWRITE of the stored day; marks are idempotent
// (existing marks are skipped, never duplicated). The planner only COUNTS
// what will happen — the actual writes are performed by the db adapter
// against the same plan.

import 'dart:convert';

import 'date_only.dart';
import 'models.dart';

/// Bump when the document shape changes; importers accept older/newer
/// documents per the rules in [parseExportJson]. Version 2 added the
/// `measured_at_minutes` entry field; version 3 made `bleeding` numeric;
/// version 4 replaced the generic `pain` flag with the letter-coded pain
/// options and (pre-release, redefined in place) the `sex` flag with the
/// `sex_timings` mask plus the additive Muttermund fields. Version 5
/// aligns the data entry with the NER scheme AND removes the profile
/// dimension completely: entries drop `profile_id`, the four `exclude_*`
/// booleans, `mood` and `desire` and gain `temp_disturbances` (raw mask
/// 0..15); marks drop `profile_id` (rows are entry_date / mark_type /
/// author only); the document has no `profiles` list at all. Old
/// (v1–4) documents keep importing: their `profile_id`/`profiles` keys are
/// accepted and ignored, their exclude_* keys translate into the mask bits
/// plus derived ignoreTemperature marks (see the header comment and
/// lib/db/export_adapter.dart).
///
/// Version 6 makes the ENTRY rows SPARSE: the writer omits every key whose
/// value equals that field's neutral value (see the header), including the
/// `bleeding` key of level-0/none days — the reader treats a missing
/// `bleeding` key (and an explicit JSON null) as "no bleeding recorded".
/// The version gates OLD readers LOUDLY instead of silently: a ≤v5 reader
/// treats a missing `bleeding` key as row-INVALID and would invisibly DROP
/// every bleeding-free day of a sparse document — losing their real data
/// (temperatures) without any error. The strict forward rejection
/// ("unsupported schema_version") is the preferred document rule, so those
/// readers fail visibly instead. v1–v5 documents stay importable
/// unchanged: old writers always emitted the `bleeding` key, so their rows
/// keep parsing exactly as before (a missing key would have meant
/// none anyway).
const int exportSchemaVersion = 6;

/// Human-readable statement of the entry merge policy (shown by UI text and
/// documented in CONTRIBUTING; importers MUST behave exactly like this).
const String exportMergePolicy = 'overwrite';

/// Row maps of the two exported tables. Values are plain JSON-decodable
/// scalars (String / num / bool / null / nested lists/maps). There is no
/// profiles list: the document is profile-free.
/// [entries] may be SPARSE (see the header): rows written by the current
/// writer carry only their non-neutral keys; full maps stay valid.
final class ExportBlob {
  const ExportBlob({
    required this.entries,
    required this.marks,
    required this.exportedAt,
  });

  final List<Map<String, Object?>> entries;
  final List<Map<String, Object?>> marks;

  final DateTime exportedAt;
}

/// Formats a date as the export/import ISO day `YYYY-MM-DD` (no time
/// component, no timezone suffix — calendar days, like everywhere else in
/// this app, see lib/domain/date_only.dart).
String formatIsoDay(DateTime d) {
  final n = DateOnly.normalize(d);
  final y = n.year.toString().padLeft(4, '0');
  final m = n.month.toString().padLeft(2, '0');
  final day = n.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Parses the `YYYY-MM-DD` export format; null when malformed (including
/// impossible calendar dates like 2026-02-30 — those are detected by
/// round-tripping the parse, since DateTime parsing silently rolls over).
DateTime? tryParseIsoDay(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final parsed = DateTime.tryParse('${s}T00:00:00Z');
  if (parsed == null) return null;
  // The round trip must reproduce the exact calendar day.
  return formatIsoDay(parsed) == s ? DateOnly.normalize(parsed) : null;
}

/// Serializes [blob] into the export document as pretty-printed JSON.
String buildExportJson(ExportBlob blob) {
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'schema_version': exportSchemaVersion,
    'exported_at': blob.exportedAt.toUtc().toIso8601String(),
    'entries': blob.entries,
    'marks': blob.marks,
  });
}

/// Validates and decodes the export document into the same [ExportBlob]
/// shape the builder produces.
///
/// Throws a [FormatException] when the input is not JSON, not an object,
/// carries an unsupported schema version, or has a broken exported_at /
/// table list. The accepted schema-version set is exactly
/// `{1 .. exportSchemaVersion}` (currently {1, 2, 3, 4, 5, 6}) — kept
/// explicit, no forward negotiation: old exports exist as real files on
/// user devices, so every shape ever published stays importable, while
/// anything AFTER the current version is rejected strictly (no data may be
/// silently mis-read). The `profiles` list is NOT required (current
/// documents have none; old documents' lists are tolerated and ignored —
/// unknown
/// keys never error). Field semantics are lenient within the accepted
/// set: the per-field parsers are version-agnostic (numeric and legacy
/// token bleeding both parse; a missing/null bleeding key parses as
/// "no bleeding recorded", via tryParseBleeding). Unknown/extra keys
/// are ignored (forward compatibility).
ExportBlob parseExportJson(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FormatException('not valid JSON');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('document root must be a JSON object');
  }

  final version = decoded['schema_version'];
  if (version is! int || version < 1 || version > exportSchemaVersion) {
    throw FormatException('unsupported schema_version: $version');
  }

  final exportedAt = decoded['exported_at'];
  final exported = exportedAt is String ? DateTime.tryParse(exportedAt) : null;
  if (exported == null) {
    throw const FormatException('exported_at missing or not a timestamp');
  }

  return ExportBlob(
    exportedAt: exported,
    entries: _listOfMaps(decoded['entries'], 'entries'),
    marks: _listOfMaps(decoded['marks'], 'marks'),
  );
}

/// Throws when any of the members is lacking or non-object-like, so
/// downstream code can rely on uniform row maps.
List<Map<String, Object?>> _listOfMaps(Object? raw, String field) {
  if (raw is! List) {
    throw FormatException('field "$field" must be a list');
  }
  final result = <Map<String, Object?>>[];
  for (final row in raw) {
    if (row is! Map) {
      throw FormatException('field "$field" must contain only JSON objects');
    }
    result.add(row.cast<String, Object?>());
  }
  return result;
}

/// Counted import plan. The db adapter executes exactly these writes
/// (plus the derived ignoreTemperature marks that OLD documents'
/// exclude_* keys translate into — see lib/db/export_adapter.dart; the
/// planner counts the document's own rows only).
final class ImportSummary {
  const ImportSummary({
    this.entriesNew = 0,
    this.entriesOverwritten = 0,
    this.entriesInvalid = 0,
    this.duplicateEntryRows = 0,
    this.marksNew = 0,
    this.marksSkipped = 0,
    this.marksInvalid = 0,
  });

  /// Entries absent on this device (to insert).
  final int entriesNew;

  /// Entries present on this device (to overwrite, per the merge policy).
  final int entriesOverwritten;

  /// Rows rejected because they are structurally invalid (a broken or
  /// missing ISO day, bleeding outside the stored vocabulary — exactly the
  /// rows the db writer drops, see the shared helpers used by both sides).
  final int entriesInvalid;

  /// Rows whose same-day key appears twice IN the document itself; the
  /// first occurrence wins.
  final int duplicateEntryRows;

  /// Marks absent on this device (to add).
  final int marksNew;

  /// Identical marks already present (skipped idempotently).
  final int marksSkipped;

  final int marksInvalid;

  /// Total rows that end up stored for the entries table.
  int get entriesWritten => entriesNew + entriesOverwritten;
}

/// Stable key of an entry row for the day uniqueness (the ISO day itself);
/// also part of the adapter contract (the db layer looks up existing rows
/// by exactly this key).
String importEntryKey(String isoDay) => isoDay;

/// Stable key of a mark row for its (day, type) uniqueness.
String importMarkKey(String isoDay, String markType) => '$isoDay|$markType';

/// Plans the import of [doc] into an existing dataset.
///
/// [existingEntryKeys] / [existingMarkKeys] contain the keys of all rows
/// already on the device (built with [importEntryKey]/[importMarkKey]).
/// The `profile_id` / `profiles` keys of old documents are NOT read here
/// (accepted and ignored — rows merge by day / (day, mark_type), and two
/// rows that differ only by profile on the same day collapse onto one
/// key: first occurrence wins, extras count as duplicates). Only counts
/// are produced — no writes happen here, keeping this function pure and
/// testable.
ImportSummary planMerge(
  ExportBlob doc, {
  required Set<String> existingEntryKeys,
  required Set<String> existingMarkKeys,
}) {
  var entriesNew = 0;
  var entriesOverwritten = 0;
  var entriesInvalid = 0;
  var duplicateEntryRows = 0;
  var marksNew = 0;
  var marksSkipped = 0;
  var marksInvalid = 0;

  final seenEntryKeys = <String>{};

  for (final row in doc.entries) {
    // Same field-level gates as the db writer (tryDailyEntryFromExport):
    // the day through the shared helper, and bleeding through the SHARED
    // vocabulary helper tryParseBleeding (models.dart) instead of a
    // planner-local rule — the writer rejecting a field must never happen
    // after the planner counted the row as a write. The writer's remaining
    // field handling (bbt/flags defaults, mucus/mask coercion to 0/null)
    // never drops a row, so no further planner gate exists.
    final day = row['date'] is String
        ? tryParseIsoDay(row['date'] as String)
        : null;
    final bleeding = tryParseBleeding(row['bleeding']);
    if (day == null || bleeding == null) {
      entriesInvalid++;
      continue;
    }
    final key = importEntryKey(formatIsoDay(day));
    if (seenEntryKeys.contains(key)) {
      duplicateEntryRows++;
      continue;
    }
    seenEntryKeys.add(key);
    if (existingEntryKeys.contains(key)) {
      entriesOverwritten++;
    } else {
      entriesNew++;
    }
  }

  for (final row in doc.marks) {
    final day = row['entry_date'] is String
        ? tryParseIsoDay(row['entry_date'] as String)
        : null;
    final type = row['mark_type'];
    if (day == null || type is! String || type.isEmpty) {
      marksInvalid++;
      continue;
    }
    final key = importMarkKey(formatIsoDay(day), type);
    if (existingMarkKeys.contains(key)) {
      marksSkipped++;
    } else {
      marksNew++;
    }
  }

  return ImportSummary(
    entriesNew: entriesNew,
    entriesOverwritten: entriesOverwritten,
    entriesInvalid: entriesInvalid,
    duplicateEntryRows: duplicateEntryRows,
    marksNew: marksNew,
    marksSkipped: marksSkipped,
    marksInvalid: marksInvalid,
  );
}
