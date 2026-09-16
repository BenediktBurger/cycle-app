// Drift <-> export JSON adapter: converts rows of the database into the
// generic export maps understood by lib/domain/export_import.dart and
// executes that module's import plan against the DAOs.
//
// Import semantics (per the merge policy over there):
//  - entries: full replace of a day via EntriesDao.upsertDaily for rows whose
//    (profile, date) key exists on-device; inserts otherwise; structurally
//    invalid rows are skipped and counted.
//  - marks: added idempotently via MarksDao.addMark (existing ones skipped).
//  - profiles required by imported rows are available on the device after
//    preparation: a DOCUMENT profile id that already exists on this device
//    addresses that same profile (the merge key is the profile id), an
//    unknown id gets the profile re-created (exported name/ordinal when the
//    document lists it, a neutral fallback name otherwise; new AUTO id) and
//    the document id is REMAPPED to the actual row id during the writes
//    below. Rows referencing an id that could not be prepared are skipped.

import '../domain/export_import.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import 'cycle_database.dart';

/// Wraps an unexpected error raised while the import transaction was
/// running (constraint failures, storage errors, ...). The transaction has
/// rolled back by then, so NO part of the import reached the database; the
/// UI shows one localized failure message instead of a crash.
final class ImportFailedException implements Exception {
  ImportFailedException(this.cause);

  /// The original error thrown inside the transaction.
  final Object cause;

  @override
  String toString() => 'ImportFailedException: $cause';
}

/// First matching row of [rows] by a predicate on the profile id helper.
Map<String, Object?>? _firstProfileDefinition(
  List<Map<String, Object?>> rows,
  bool Function(Map<String, Object?>) test,
) {
  for (final row in rows) {
    if (test(row)) return row;
  }
  return null;
}

// --- export (rows -> ExportBlob -> JSON string) ---------------------------

/// Collects every table of [db] into the export document.
Future<ExportBlob> exportDatabaseToBlob(CycleDatabase db) async {
  final profiles = await db.profilesDao.allProfiles();
  final entries = await db.entriesDao.allEntriesForAllProfiles();
  final marks = await db.marksDao.allMarksForAllProfiles();

  return ExportBlob(
    exportedAt: DateTime.now(),
    profiles: [
      for (final p in profiles)
        {'id': p.id, 'name': p.name, 'ordinal': p.ordinal},
    ],
    entries: [
      for (final e in entries)
        {
          'profile_id': e.profileId,
          'date': formatIsoDay(e.date),
          'bbt_c': e.bbtC,
          'measured_at_minutes': e.measuredAtMinutes,
          'bleeding': _legacyBleedingToken(e.bleeding),
          'exclude_illness': e.excludeIllness,
          'exclude_alcohol': e.excludeAlcohol,
          'exclude_travel': e.excludeTravel,
          'exclude_other': e.excludeOther,
          'mucus_sign': e.mucusSign,
          'mucus_quality': e.mucusQuality,
          'cervix': e.cervix,
          'pain': e.pain,
          'mood': e.mood,
          'desire': e.desire,
          'sex': e.sex,
          'notes': e.notes,
        },
    ],
    marks: [
      for (final m in marks)
        {
          'profile_id': m.profileId,
          'entry_date': formatIsoDay(m.entryDate),
          'mark_type': m.markType,
          'author': m.author,
        },
    ],
  );
}

/// Convenience: full pretty-printed JSON string, ready for
/// clipboard/download and re-import.
Future<String> exportDatabaseToJson(CycleDatabase db) =>
    exportDatabaseToBlob(db).then(buildExportJson);

/// The bleeding token an export document carries for a stored bleeding
/// value: the legacy vocabulary (none / period / spotting) for the
/// menstruation levels, exactly the way the shared parser reads those tokens
/// back (period -> medium, lib/domain/models.dart). Written this way so a
/// document cycle-app itself produces can always be re-imported by it; the
/// per-level numeric field is the successor of this token.
String _legacyBleedingToken(Bleeding b) => switch (b) {
      Bleeding.none => 'none',
      Bleeding.spotting => 'spotting',
      Bleeding.light || Bleeding.medium || Bleeding.heavy => 'period',
    };

// --- import (JSON string -> ExportBlob -> plan -> writes) -----------------

/// Earliest neutral profile name for rows whose document doesn't describe
/// the profile they belong to (fallback; visible in the merged dataset).
const String importFallbackProfileName = 'migration-unknown';

/// Validates the document with [parseExportJson] and COUNTS the import plan
/// against the current database state (no writes). Useful for showing the
/// user a summary BEFORE applying (not wired into the UI yet — kept for the
/// verification flow and tests).
Future<ImportSummary> planDatabaseImport(CycleDatabase db, String raw) async {
  final doc = parseExportJson(raw);
  final existing = await _existingKeys(db);
  return planMerge(
    doc,
    existingEntryKeys: existing.entryKeys,
    existingMarkKeys: existing.markKeys,
    existingProfileIds: existing.profileIds,
  );
}

/// Parses, plans and writes the import into [db]; returns the executed
/// counts for the confirmation text.
///
/// The write phase runs in ONE transaction: a failure mid-way rolls
/// everything back. Structural validity was already checked by the plan;
/// per-row failures inside the transaction are not expected — any thrown
/// error aborts the whole import instead of leaving half-imported data.
///
/// Errors around the transaction: a [FormatException] rethrows as-is (the
/// document itself is invalid); everything else is wrapped into an
/// [ImportFailedException] so callers can show ONE failure state without
/// leaking driver internals as an app crash.
Future<ImportSummary> importJsonToDatabase(CycleDatabase db, String raw) async {
  try {
    return await db.transaction(() async {
      final doc = parseExportJson(raw);
      final existing = await _existingKeys(db);
      final summary = planMerge(
        doc,
        existingEntryKeys: existing.entryKeys,
        existingMarkKeys: existing.markKeys,
        existingProfileIds: existing.profileIds,
      );

      // 1) Make every (referenced) profile id available on this device and
      //    learn the ACTUAL id to write for it: re-created profiles get
      //    their own auto id, which may differ from the document's id.
      final remap = await _prepareProfiles(db, doc, existing.profileIds);

      // 2) Entries in document order. Duplicate (profile, date) keys inside
      //    the document were counted and excluded by the plan; the FIRST
      //    occurrence of a key wins. The document's profile id is remapped
      //    to the actual (possibly re-created) profile id on write.
      for (final row in doc.entries) {
        final entry = tryDailyEntryFromExport(row);
        if (entry == null) continue;
        final actualProfileId = remap[entry.profileId];
        if (actualProfileId == null) continue; // profile not preparable
        await db.entriesDao.upsertDaily(entry, profileId: actualProfileId);
      }

      // 3) Marks idempotently (addMark skips existing ones silently), under
      //    the remapped profile ids as well.
      for (final row in doc.marks) {
        // Shared id tolerance (planner + writers); a raw `as int?` cast
        // would abort the whole transaction on a numeric-string id.
        final docProfileId = parseExportId(row['profile_id']);
        final actualProfileId =
            docProfileId == null ? null : remap[docProfileId];
        final day = row['entry_date'] is String
            ? tryParseIsoDay(row['entry_date'] as String)
            : null;
        final type = row['mark_type'];
        final authority = row['author'];
        if (actualProfileId == null ||
            day == null ||
            type is! String ||
            type.isEmpty) {
          continue;
        }
        await db.marksDao.addMark(
          actualProfileId,
          day,
          type,
          author:
              authority is String && authority.isNotEmpty ? authority : 'user',
        );
      }

      return summary;
    });
  } on FormatException {
    rethrow; // invalid DOCUMENT (not JSON / wrong schema): see parseExportJson
  } catch (error, stack) {
    // The transaction has rolled back; surface a single failure state
    // instead of crashing the app.
    Error.throwWithStackTrace(ImportFailedException(error), stack);
  }
}

/// Document profile id -> the profile id to WRITE for it after preparation:
/// known device ids map to themselves; unknown ids are re-created on the
/// device (with the document's name/ordinal when defined) and map to the
/// ACTUAL id of the new row. Referenced ids whose re-creation fails stay
/// absent from the map — their rows are skipped by the writer.
Future<Map<int, int>> _prepareProfiles(
  CycleDatabase db,
  ExportBlob doc,
  Set<int> deviceProfileIds,
) async {
  final referenced = <int>{};
  Map<String, Object?>? definitionOf(int id) => _firstProfileDefinition(
      doc.profiles, (p) => parseExportId(p['id']) == id);

  String? nameOf(int id) {
    final row = definitionOf(id);
    if (row == null) return null;
    final name = row['name'];
    return name is String && name.isNotEmpty ? name : null;
  }

  int? ordinalOf(int id) {
    final ordinal = definitionOf(id)?['ordinal'];
    return ordinal is int ? ordinal : null;
  }

  // Same shared id tolerance as the planner (parser accepts numeric
  // strings); ids the planner already accepted must still be prepared here.
  for (final row in doc.entries) {
    final id = parseExportId(row['profile_id']);
    if (id != null) referenced.add(id);
  }
  for (final row in doc.marks) {
    final id = parseExportId(row['profile_id']);
    if (id != null) referenced.add(id);
  }
  for (final row in doc.profiles) {
    final id = parseExportId(row['id']);
    if (id != null) referenced.add(id);
  }

  final remap = <int, int>{
    for (final id in deviceProfileIds) id: id,
  };
  for (final id in referenced) {
    if (remap.containsKey(id)) continue;
    try {
      final created = await db.profilesDao.addProfile(
        nameOf(id) ?? importFallbackProfileName,
        ordinal: ordinalOf(id),
      );
      remap[id] = created.id;
    } catch (_) {
      continue; // leave the id unprepared; its rows are skipped below.
    }
  }
  return remap;
}

final class _Existing {
  _Existing(this.profileIds, this.entryKeys, this.markKeys);

  final Set<int> profileIds;
  final Set<String> entryKeys;
  final Set<String> markKeys;
}

Future<_Existing> _existingKeys(CycleDatabase db) async {
  final profiles = await db.profilesDao.allProfiles();
  final entries = await db.entriesDao.allEntriesForAllProfiles();
  final marks = await db.marksDao.allMarksForAllProfiles();

  return _Existing(
    {for (final p in profiles) p.id},
    {
      for (final e in entries) importEntryKey(e.profileId, formatIsoDay(e.date))
    },
    {
      for (final m in marks)
        importMarkKey(m.profileId, formatIsoDay(m.entryDate), m.markType),
    },
  );
}

/// Row map -> [DailyEntry], or null when structurally invalid (bad date,
/// unknown/missing bleeding value, ...) — the exact gates the merge planner
/// applies, so a counted row is always written. Coercible fields are nulled,
/// NEVER row killers: out-of-vocabulary / non-string mucus_sign and
/// mucus_quality tokens collapse to null here, and a quality token without
/// an S sign keeps the row with its quality nulled (both via the shared
/// mucus parse helpers + the pair sanitize rule, lib/domain/mucus.dart).
DailyEntry? tryDailyEntryFromExport(Map<String, Object?> row) {
  // parseExportId (shared with the merge planner) accepts numeric-string
  // ids as well — otherwise planner-counted rows would be silently skipped
  // here.
  final profileId = parseExportId(row['profile_id']);
  final day =
      row['date'] is String ? tryParseIsoDay(row['date'] as String) : null;
  if (profileId == null || day == null) return null;

  // Shared vocabulary helper (models.dart) — the SAME function the planner
  // validates bleeding with; a planner-local duplicate is exactly what let
  // counted and written rows diverge before.
  final bleeding = tryParseBleeding(row['bleeding']);
  if (bleeding == null) return null;

  // The (sign, quality) pair from foreign data through the shared helpers,
  // then the quality-requires-S rule: the only state this writer can
  // legally construct.
  final mucus = sanitizeMucusPair(
    sign: tryParseMucusSign(row['mucus_sign']),
    quality: tryParseMucusQuality(row['mucus_quality']),
  );

  final bbt = row['bbt_c'];
  bool flag(Object? key) => row[key] == true;

  // Coercible field: broken or absent time tokens collapse to null (v1
  // documents omit the field entirely).
  final measuredAtMinutes =
      tryParseMeasuredAtMinutes(row['measured_at_minutes']);

  try {
    return DailyEntry(
      date: day,
      profileId: profileId,
      bbtC: bbt is num ? bbt.toDouble() : null,
      measuredAtMinutes: measuredAtMinutes,
      bleeding: bleeding,
      excludeIllness: flag('exclude_illness'),
      excludeAlcohol: flag('exclude_alcohol'),
      excludeTravel: flag('exclude_travel'),
      excludeOther: flag('exclude_other'),
      mucusSign: mucus.sign,
      mucusQuality: mucus.quality,
      cervix: row['cervix'] is String ? row['cervix'] as String : null,
      pain: flag('pain'),
      mood: flag('mood'),
      desire: flag('desire'),
      sex: flag('sex'),
      notes: row['notes'] is String ? row['notes'] as String : null,
    );
  } on AssertionError {
    return null; // e.g. an out-of-scale value smuggled in another field
  }
}
