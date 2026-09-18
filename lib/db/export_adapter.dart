// Drift <-> export JSON adapter: converts rows of the database into the
// generic export maps understood by lib/domain/export_import.dart and
// executes that module's import plan against the DAOs.
//
// Import semantics (per the merge policy over there):
//  - entries: full replace of a day via EntriesDao.upsertDaily for rows whose
//    day key exists on-device; inserts otherwise; structurally invalid rows
//    are skipped and counted.
//  - marks: added idempotently via MarksDao.addMark (existing ones skipped).
//  - old documents (v1–4) carry profile keys (`profile_id` on every row, a
//    root `profiles` list): both are ACCEPTED and IGNORED — rows merge by
//    day / (day, mark_type), never by profile. Their exclude_* keys
//    translate into the temp_disturbances mask bits (illness → kr, alcohol
//    → alk; travel/other have no flag any more) AND any of the four true
//    derives an ignoreTemperature mark (author 'import') for that day,
//    preserving the old interrupted-day analysis semantics. The derived
//    marks are written inside the import transaction (idempotently, like
//    the document's own marks); they are not part of the planner's counts.

import '../domain/cervix.dart';
import '../domain/export_import.dart';
import '../domain/marks.dart';
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

// --- export (rows -> ExportBlob -> JSON string) ---------------------------

/// Collects every table of [db] into the export document (profile-free:
/// the v5 document carries no profile keys anywhere).
Future<ExportBlob> exportDatabaseToBlob(CycleDatabase db) async {
  final entries = await db.entriesDao.allEntries();
  final marks = await db.marksDao.allMarks();

  return ExportBlob(
    exportedAt: DateTime.now(),
    entries: [
      for (final e in entries)
        {
          'date': formatIsoDay(e.date),
          'bbt_c': e.bbtC,
          // The measurement time is metadata of the temperature (see
          // DailyEntry.measuredAtMinutes): a document never carries a time
          // without its temperature. The copy here normalizes on top of the
          // constructor rule so legacy rows (written before the rule, e.g.
          // by an older app version) export clean too — the export → import
          // round trip is idempotent.
          'measured_at_minutes': e.bbtC == null ? null : e.measuredAtMinutes,
          'bleeding': e.bleeding.level,
          'temp_disturbances': e.tempDisturbances,
          'mucus_sign': e.mucusSign,
          'mucus_quality': e.mucusQuality,
          'cervix_position': e.cervixPosition,
          'cervix_opening': e.cervixOpening,
          'cervix_firmness': e.cervixFirmness,
          'pain_breast': e.painBreast,
          'pain_mittelschmerz': e.painMittelschmerz,
          'sex_timings': e.sexTimings,
          'notes': e.notes,
        },
    ],
    marks: [
      for (final m in marks)
        {
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

// --- import (JSON string -> ExportBlob -> plan -> writes) -----------------

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
      );

      // 1) Entries in document order. Duplicate same-day keys inside the
      //    document were counted and excluded by the merge plan; the FIRST
      //    occurrence of a key wins (this also collapses old multi-profile
      //    rows that differed only by profile_id — the key is the day).
      //    The seen key is added ONLY for structurally valid rows (exactly
      //    like the merge planner counts: an invalid row never consumes a
      //    key, so
      //    a later valid row for the same day still writes) — counted ==
      //    written.
      final excludedDays = <String>{};
      final seenEntryKeys = <String>{};
      for (final row in doc.entries) {
        final entry = tryDailyEntryFromExport(row);
        if (entry == null) continue;
        final key = formatIsoDay(entry.date);
        if (!seenEntryKeys.add(key)) continue; // duplicate: first wins
        await db.entriesDao.upsertDaily(entry);

        // Old-document translation: any of the four exclude_* keys derives
        // the analysis-exclusion mark for that day (author 'import') — the
        // raw-data side of the translation (illness/alcohol mask bits)
        // already happened inside tryDailyEntryFromExport.
        if (_oldDocExcluded(row)) {
          final day = formatIsoDay(entry.date);
          excludedDays.add(day);
        }
      }

      // 2) Marks idempotently (addMark skips existing ones silently). The
      //    document's own ignoreTemperature rows suppress the derived
      //    ones for the same day (no duplicates, no double marks).
      final documentExcludedDays = {
        for (final row in doc.marks)
          if (row['mark_type'] == CycleMarkTypes.ignoreTemperature &&
              row['entry_date'] is String)
            row['entry_date']! as String,
      };
      for (final day in excludedDays) {
        if (documentExcludedDays.contains(day)) continue;
        await db.marksDao.addMark(
          tryParseIsoDay(day)!,
          CycleMarkTypes.ignoreTemperature,
          author: 'import',
        );
      }
      for (final row in doc.marks) {
        final day = row['entry_date'] is String
            ? tryParseIsoDay(row['entry_date'] as String)
            : null;
        final type = row['mark_type'];
        final authority = row['author'];
        if (day == null || type is! String || type.isEmpty) {
          continue;
        }
        await db.marksDao.addMark(
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

/// Whether the (old-document) row carries any of the four legacy exclusion
/// keys as `true` — the trigger for the derived ignoreTemperature mark.
bool _oldDocExcluded(Map<String, Object?> row) =>
    row['exclude_illness'] == true ||
    row['exclude_alcohol'] == true ||
    row['exclude_travel'] == true ||
    row['exclude_other'] == true;

final class _Existing {
  _Existing(this.entryKeys, this.markKeys);

  final Set<String> entryKeys;
  final Set<String> markKeys;
}

Future<_Existing> _existingKeys(CycleDatabase db) async {
  final entries = await db.entriesDao.allEntries();
  final marks = await db.marksDao.allMarks();

  return _Existing(
    {for (final e in entries) importEntryKey(formatIsoDay(e.date))},
    {
      for (final m in marks)
        importMarkKey(formatIsoDay(m.entryDate), m.markType),
    },
  );
}

/// Row map -> [DailyEntry], or null when structurally invalid (bad date,
/// unknown/missing bleeding value, ...) — the exact gates the merge planner
/// applies, so a counted row is always written. Coercible fields are nulled
/// (or collapsed to their neutral value), NEVER row killers:
/// out-of-vocabulary / non-string mucus_sign and mucus_quality tokens
/// collapse to null here, a quality token without an S sign keeps the row
/// with its quality nulled (both via the shared mucus parse helpers + the
/// pair sanitize rule, lib/domain/mucus.dart), an out-of-vocabulary
/// cervix token collapses to null (lib/domain/cervix.dart helpers), and an
/// out-of-range sex_timings or temp_disturbances mask collapses to 0.
///
/// Old-document translation (v1–4 documents): `exclude_illness` maps onto
/// the kr bit (8), `exclude_alcohol` onto the alk bit (4) — OR-combined
/// with the v5 `temp_disturbances` field when one is present. The other
/// two keys (`exclude_travel` / `exclude_other`) leave NO mask bit (no
/// equivalent flag exists; their analysis effect is the DERIVED mark,
/// written by the import transaction). `mood` / `desire` keys are dropped
/// (the row stays valid, notes untouched) — and the `profile_id` /
/// `profiles` keys are simply never read.
DailyEntry? tryDailyEntryFromExport(Map<String, Object?> row) {
  final day =
      row['date'] is String ? tryParseIsoDay(row['date'] as String) : null;
  if (day == null) return null;

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

  // The raw disturbance mask: an int within the 0..15 TempDisturbance
  // vocabulary is taken verbatim; anything else — a missing key (older
  // documents predate the field), a non-int, an out-of-range value —
  // collapses to 0 ("no disturbance"), never a row killer (same principle
  // as mucus). The old-document exclude_* keys contribute their bits on
  // top (illness → kr, alcohol → alk) — see the doc comment above.
  final mask = tryParseTempDisturbances(row['temp_disturbances']) |
      (flag('exclude_illness') ? TempDisturbance.kr.bit : 0) |
      (flag('exclude_alcohol') ? TempDisturbance.alk.bit : 0);

  // The sex timings mask: an int within the 0..7 SexTiming vocabulary is
  // taken verbatim; anything else — a missing key (older documents predate
  // the field), a non-int, an out-of-range value — collapses to 0 ("no sex
  // recorded"), never a row killer. The ≤(redefined-v4) boolean `sex` flag
  // is deliberately NOT read here: it has no mask identity.
  final rawTimings = row['sex_timings'];
  final sexTimings =
      rawTimings is int && rawTimings >= 0 && rawTimings <= 7 ? rawTimings : 0;

  try {
    return DailyEntry(
      date: day,
      bbtC: bbt is num ? bbt.toDouble() : null,
      measuredAtMinutes: measuredAtMinutes,
      bleeding: bleeding,
      tempDisturbances: mask,
      mucusSign: mucus.sign,
      mucusQuality: mucus.quality,
      // Muttermund options through the shared vocabulary helpers
      // (lib/domain/cervix.dart): out-of-vocabulary / non-string tokens
      // collapse to null — NEVER row killers, same principle as mucus.
      cervixPosition: tryParseCervixPosition(row['cervix_position']),
      cervixOpening: tryParseCervixOpening(row['cervix_opening']),
      cervixFirmness: tryParseCervixFirmness(row['cervix_firmness']),
      sexTimings: sexTimings,
      // The generic `pain` flag of ≤v3 documents is deliberately NOT read
      // here: it has no B/M identity, so the flag is dropped while the row
      // itself stays valid. The dropped `mood` / `desire` keys are never
      // read either.
      painBreast: flag('pain_breast'),
      painMittelschmerz: flag('pain_mittelschmerz'),
      notes: row['notes'] is String ? row['notes'] as String : null,
    );
  } on AssertionError {
    return null; // e.g. an out-of-scale value smuggled in another field
  }
}
