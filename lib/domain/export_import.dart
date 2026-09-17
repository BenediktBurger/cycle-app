// JSON export/import for the whole local database — PURE domain layer.
//
// Export document shape (schema version 4):
//
//   {
//     "schema_version": 4,
//     "exported_at": "<ISO 8601 UTC>",
//     "profiles": [{"id": 1, "name": "main", "ordinal": 0}, ...],
//     "entries":  [{"profile_id": 1, "date": "2026-03-01", "bbt_c": 36.6,
//                    "measured_at_minutes": 405, (nullable, v2+; minutes
//                    since midnight, when the temperature was measured —
//                    only ever set together with bbt_c; the import side
//                    drops a stray time, never the row)
//                    "bleeding": 3, (numeric level, v3; see the version note
//                    below) "exclude_illness": false,
//                    "mucus_sign": "s", "mucus_quality": "ew", (both
//                    nullable; quality only ever together with S)
//                    "pain_breast": false, "pain_mittelschmerz": false,
//                    (the letter-coded pain options B and M, v4+)
//                    "cervix_position": "high",
//                    "cervix_opening": "open", (Muttermund
//                    observation tokens, see the v4 note below)
//                    "cervix_firmness": "hard", (Muttermund firmness token,
//                    v4, see the version note below)
//                    "sex_timings": 2, (SexTiming bitmask 0..7, v4, see the
//                    version note below)
//                    ..., "notes": null}, ...],
//     "marks":    [{"profile_id": 1, "entry_date": "2026-03-12",
//                   "mark_type": "baseline", "author": "user"}, ...]
//   }
//
// Per-version entry fields: v1 omitted `measured_at_minutes` and carried
// bleeding as one of the legacy string tokens none/period/spotting; v2
// added `measured_at_minutes` but still carried token bleeding; v3 carries
// the numeric bleeding level (0=none … 4=heavy); v4 replaces the generic
// `pain` flag with the letter-coded pain options `pain_breast` (B) and
// `pain_mittelschmerz` (M). The import side is STRICT per version about
// which fields exist, and LENIENT within the accepted set: field values
// are parsed per field by the shared helpers regardless of the version
// (see tryParseBleeding / tryParseMeasuredAtMinutes), so an old document
// and the current one flow through the same field parsers. Legacy ≤v3
// documents may still carry the generic `pain: true` flag: it has no B/M
// identity, so it is TOLERATED but dropped by the field mapping (the row
// stays valid, the flag information is not carried over).
//
// Version note on the v4 REDEFINITION (pre-release): v4 was never published
// before the sex/cervix vocabulary landed, so its shape was redefined in
// place instead of growing a v5 — the old v4 `sex` boolean is REPLACED by
// the `sex_timings` bitmask (0..7, the SexTiming bits; see models.dart) and
// `cervix_firmness` (the lib/domain/cervix.dart firmness token) extends v4
// ADDITIVELY. The free-text `cervix` note key was later dropped from v4 the
// same way (owner decision: the three Muttermund vocabularies carry the
// observation; prose belongs in `notes`). No legacy tolerance shims exist
// for any of these keys: there are no v4 documents in the wild with an old
// shape, and a stray `sex` or `cervix` key is simply ignored (unknown keys
// never error — see below).
//
// Additive fields without a version bump: v4 ALSO carries the two
// Muttermund (cervix) observation fields `cervix_position` /
// `cervix_opening` (tokens of the lib/domain/cervix.dart vocabularies) —
// additively, with NO schema-version change, because the reader ignores
// unknown/extra keys in BOTH directions: older apps reading a newer
// document keep every other field (the new keys are ignored, not an
// error), and newer apps read old documents that simply omit the fields.
// An unknown/out-of-vocabulary token collapses to null on import without
// dropping the row (never a row killer, same principle as mucus); an
// out-of-range `sex_timings` mask likewise collapses to 0.
//
// The document builds from GENERIC row maps so this layer stays decoupled
// from drift data classes; the drift <-> map conversion lives in
// lib/db/export_adapter.dart. Only the JSON shape/semantics live here.
//
// Import merge policy (resolved decision, see exportMergePolicy): entries
// merge by (profile, date) with an OVERWRITE of the stored day; marks are
// idempotent (existing marks are skipped, never duplicated); unknown
// profiles are re-created. The planner only COUNTS what will happen — the
// actual writes are performed by the db adapter against the same plan.

import 'dart:convert';

import 'date_only.dart';
import 'models.dart';

/// Bump when the document shape changes; importers accept older/newer
/// documents per the rules in [parseExportJson]. Version 2 added the
/// `measured_at_minutes` entry field (records when the temperature was
/// measured); a v1 entry simply omits the field. Version 3 made the entry
/// field `bleeding` numeric (0=none … 4=heavy) — v1/v2 documents carry
/// bleeding as one of the legacy string tokens none/period/spotting, and
/// the field parser accepts both shapes regardless of the version.
/// Version 4 replaced the generic `pain` entry flag with the letter-coded
/// pain options `pain_breast` (B) and `pain_mittelschmerz` (M); the legacy
/// `pain` flag of ≤v3 documents is tolerated and dropped on import. v4 was
/// also (pre-release) REDEFINED IN PLACE: the boolean `sex` entry flag is
/// replaced by the `sex_timings` bitmask (0..7), and the Muttermund fields
/// `cervix_position` / `cervix_opening` / `cervix_firmness` extend v4
/// ADDITIVELY with no version bump — the reader ignores unknown keys in
/// both directions (see the version note in the header comment).
const int exportSchemaVersion = 4;

/// Human-readable statement of the entry merge policy (shown by UI text and
/// documented in CONTRIBUTING; importers MUST behave exactly like this).
const String exportMergePolicy = 'overwrite';

/// Row maps of the three exported tables. Values are plain JSON-decodable
/// scalars (String / num / bool / null / nested lists/maps).
final class ExportBlob {
  const ExportBlob({
    required this.profiles,
    required this.entries,
    required this.marks,
    required this.exportedAt,
  });

  final List<Map<String, Object?>> profiles;
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
    'profiles': blob.profiles,
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
/// `{1 .. exportSchemaVersion}` (currently {1, 2, 3, 4}) — kept explicit,
/// no forward negotiation: old exports exist as real files on user devices,
/// so every shape ever published stays importable, while anything AFTER
/// the current version is rejected strictly (no data may be silently
/// mis-read). Field semantics are strict per version (which fields a
/// version carries — see the header comment); within the accepted set the
/// per-field parsers are version-agnostic (numeric and legacy token
/// bleeding both parse, via tryParseBleeding). Unknown/extra keys are
/// ignored (forward compatibility).
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
    profiles: _listOfMaps(decoded['profiles'], 'profiles'),
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

/// Counted import plan. The db adapter executes exactly these writes.
final class ImportSummary {
  const ImportSummary({
    this.profilesToInsert = 0,
    this.entriesNew = 0,
    this.entriesOverwritten = 0,
    this.entriesInvalid = 0,
    this.duplicateEntryRows = 0,
    this.marksNew = 0,
    this.marksSkipped = 0,
    this.marksInvalid = 0,
  });

  /// Unknown profile ids that must be re-created on import.
  final int profilesToInsert;

  /// Entries absent on this device (to insert).
  final int entriesNew;

  /// Entries present on this device (to overwrite, per the merge policy).
  final int entriesOverwritten;

  /// Rows rejected because they are structurally invalid (bad/missing date
  /// or profile id, bleeding outside the stored vocabulary — exactly the
  /// rows the db writer drops, see the shared helpers used by both sides).
  final int entriesInvalid;

  /// Rows whose (profile, date) key appears twice IN the document itself;
  /// the first occurrence wins.
  final int duplicateEntryRows;

  /// Marks absent on this device (to add).
  final int marksNew;

  /// Identical marks already present (skipped idempotently).
  final int marksSkipped;

  final int marksInvalid;

  /// Total rows that end up stored for the entries table.
  int get entriesWritten => entriesNew + entriesOverwritten;
}

/// Stable key of an entry row for the (profile, date) uniqueness; also part
/// of the adapter contract (the db layer looks up existing rows by exactly
/// this key).
String importEntryKey(int profileId, String isoDay) => '$profileId|$isoDay';

/// Stable key of a mark row for its (profile, date, type) uniqueness.
String importMarkKey(int profileId, String isoDay, String markType) =>
    '$profileId|$isoDay|$markType';

/// Plans the import of [doc] into an existing dataset.
///
/// [existingEntryKeys] / [existingMarkKeys] contain the keys of all rows
/// already on the device (built with [importEntryKey]/[importMarkKey]);
/// [existingProfileIds] lists known profile ids. Only counts are produced —
/// no writes happen here, keeping this function pure and testable.
ImportSummary planMerge(
  ExportBlob doc, {
  required Set<String> existingEntryKeys,
  required Set<String> existingMarkKeys,
  required Set<int> existingProfileIds,
}) {
  var profilesToInsert = 0;
  var entriesNew = 0;
  var entriesOverwritten = 0;
  var entriesInvalid = 0;
  var duplicateEntryRows = 0;
  var marksNew = 0;
  var marksSkipped = 0;
  var marksInvalid = 0;

  // Profiles in the document that the device does not know yet must be
  // re-created with their DOCUMENTED OWN data (name/ordinal).
  for (final row in doc.profiles) {
    final id = parseExportId(row['id']);
    if (id != null && !existingProfileIds.contains(id)) {
      profilesToInsert++;
    }
  }

  final seenEntryKeys = <String>{};

  for (final row in doc.entries) {
    // Same field-level gates as the db writer (tryDailyEntryFromExport):
    // profile id and day through the shared helpers, and bleeding through
    // the SHARED vocabulary helper tryParseBleeding (models.dart) instead of
    // a planner-local rule — the writer rejecting a field must never happen
    // after the planner counted the row as a write. The writer's remaining
    // field handling (bbt/flags defaults, mucus/entries coercion to null)
    // never drops a row, so no further planner gate exists.
    final profileId = parseExportId(row['profile_id']);
    final day =
        row['date'] is String ? tryParseIsoDay(row['date'] as String) : null;
    final bleeding = tryParseBleeding(row['bleeding']);
    if (profileId == null || day == null || bleeding == null) {
      entriesInvalid++;
      continue;
    }
    final key = importEntryKey(profileId, formatIsoDay(day));
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
    final profileId = parseExportId(row['profile_id']);
    final day = row['entry_date'] is String
        ? tryParseIsoDay(row['entry_date'] as String)
        : null;
    final type = row['mark_type'];
    if (profileId == null || day == null || type is! String || type.isEmpty) {
      marksInvalid++;
      continue;
    }
    final key = importMarkKey(profileId, formatIsoDay(day), type);
    if (existingMarkKeys.contains(key)) {
      marksSkipped++;
    } else {
      marksNew++;
    }
  }

  return ImportSummary(
    profilesToInsert: profilesToInsert,
    entriesNew: entriesNew,
    entriesOverwritten: entriesOverwritten,
    entriesInvalid: entriesInvalid,
    duplicateEntryRows: duplicateEntryRows,
    marksNew: marksNew,
    marksSkipped: marksSkipped,
    marksInvalid: marksInvalid,
  );
}

/// Parses a numeric export id that may arrive as `int`, or as a numeric
/// string (boxed from lossy systems — some tools serialize ids as strings);
/// anything else is invalid. Plan counting and every row writer MUST use
/// this same helper so a counted row is always a written row.
int? parseExportId(Object? raw) {
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw);
  return null;
}
