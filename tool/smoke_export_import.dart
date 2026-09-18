// Runtime smoke-verification for the export/import pipeline (NOT part of the
// shipped test suite). Host-VM twin of the plain test suite: it executes
// core assertions against the REAL drift engine (NativeDatabase.memory()) —
// quickly and with fewer moving parts than the test runner.
//
// Run from repo root:  ~/flutter/bin/dart run tool/smoke_export_import.dart
//
// (flutter analyze analyzes this production code; it is a CLT tool, prints
// are expected there — lint suppressed locally.)

// ignore_for_file: avoid_print

import 'package:drift/native.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/decimal_input.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError('SMOKE FAIL: $label');
  print('ok   $label');
}

Future<void> main() async {
  // --- pure logic ----------------------------------------------------------
  check(parseDecimalInput('36,6') == 36.6, 'decimal comma parses');
  check(parseDecimalInput('36.65') == 36.65, 'decimal dot parses');
  check(parseDecimalInput('36,654') == null,
      'more than two fraction digits rejected');
  check(parseDecimalInput('fünf') == null, 'letters rejected');
  check(!isWithinBbtRange(51.0), 'BBT range gate upper bound');
  check(isWithinBbtRange(36.5), 'BBT range gate accepts normal value');

  check(tryParseMucusSign('s') == MucusSign.s,
      'fertility sign parses by stable token');
  check(tryParseMucusSign('a') == MucusSign.a,
      'the Ausfluss sign parses by its stable token');
  check(tryParseMucusSign('fs') == MucusSign.fs,
      "the f/S sign parses by its stable token ('fs')");
  check(tryParseMucusSign('wet') == null, 'out-of-vocabulary sign is null');
  check(
      tryParseMucusQuality('gl') == MucusQuality.gl &&
          tryParseMucusQuality('glb') == MucusQuality.glb &&
          MucusQuality.gl != MucusQuality.glb,
      'glasig (gl) and gelblich (glb) are distinct qualities');
  check(
      sanitizeMucusPair(sign: MucusSign.f, quality: MucusQuality.w).quality ==
          null,
      'quality collapses without the S sign');
  check(
      sanitizeMucusPair(sign: MucusSign.fs, quality: MucusQuality.ew).quality ==
          null,
      "quality collapses for the 'fs' sign too");
  check(
      mucusDisplay(sign: MucusSign.s, quality: MucusQuality.ew).superscript ==
          'EW',
      'S with EW quality renders the uppercase superscript token');
  check(mucusSignSymbol(MucusSign.fs) == 'f/S',
      "the 'fs' sign renders as the f/S glyph");

  check(tryParseTempDisturbances(15) == 15,
      'the temp_disturbances mask parses verbatim inside 0..15');
  check(tryParseTempDisturbances(999) == 0,
      'an out-of-range mask collapses to 0 (never a row killer)');

  check(formatIsoDay(DateTime(2026, 3, 5)) == '2026-03-05',
      'ISO day formatting padded');
  final parsedBack = tryParseIsoDay('2026-03-05');
  check(
      parsedBack != null && DateOnly.sameDay(parsedBack, DateTime(2026, 3, 5)),
      'ISO day parses');
  check(tryParseIsoDay('2026-02-30') == null, 'impossible dates rejected');

  // --- round trip over the REAL engine -------------------------------------
  final source = CycleDatabase(NativeDatabase.memory());
  await source.entriesDao.upsertDaily(
    DailyEntry(
      date: DateTime(2026, 3, 2),
      bleeding: Bleeding.medium,
      bbtC: 36.1,
      tempDisturbances: TempDisturbance.sp.bit,
    ),
  );
  await source.entriesDao.upsertDaily(
    DailyEntry(
      date: DateTime(2026, 3, 3),
      bleeding: Bleeding.medium,
      bbtC: 36.05,
      mucusSign: MucusSign.s,
      mucusQuality: MucusQuality.mi,
    ),
  );
  await source.entriesDao.upsertDaily(
    DailyEntry(
      date: DateTime(2026, 3, 5),
      bleeding: Bleeding.heavy,
      // The current document fields: the Ausfluss sign (no quality exists
      // for it), the firmness token, and the sex-timings bitmask
      // (start|end → multiple X on one day).
      mucusSign: MucusSign.a,
      cervixFirmness: CervixFirmness.hard,
      sexTimings: SexTiming.start.bit | SexTiming.end.bit,
    ),
  );
  await source.marksDao
      .addMark(DateTime(2026, 3, 12), CycleMarkTypes.ignoreTemperature);
  await source.entriesDao.upsertDaily(
    DailyEntry(date: DateTime(2026, 3, 4), bleeding: Bleeding.none),
  );

  final json = await exportDatabaseToJson(source);
  check(json.contains('"schema_version": $exportSchemaVersion'),
      'document carries schema version 5');
  // The document shape carries bleeding as NUMERIC levels (Bleeding.level):
  // heavy(4) from the added day, none(0) from the neutral day.
  check(json.contains('"bleeding": 4') && json.contains('"bleeding": 0'),
      'export carries bleeding as numeric levels');
  check(
      json.contains('"mucus_sign": "s"') &&
          json.contains('"mucus_quality": "mi"'),
      'export carries the fertility-sign tokens');
  check(json.contains('"mucus_sign": "a"'),
      'export carries the Ausfluss sign token');
  check(
      json.contains('"cervix_firmness": "hard"') &&
          json.contains(
              '"sex_timings": ${SexTiming.start.bit | SexTiming.end.bit}'),
      'export carries the redefined-v4 keys (cervix_firmness, sex_timings)');
  check(json.contains('"temp_disturbances": 1'),
      'export carries the raw disturbance mask');
  // Profile-free document: no profile keys anywhere.
  check(!json.contains('profile_id') && !json.contains('"profiles"'),
      'the export document is profile-free');

  // Malformed documents must be rejected BEFORE any write.
  var rejected = false;
  try {
    parseExportJson('{"schema_version": 42}');
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'wrong schema version rejected');

  // Planning against a fresh target dataset.
  final target = CycleDatabase(NativeDatabase.memory());
  final plan = await planDatabaseImport(target, json);
  check(plan.entriesNew == 4, 'plan counts all 4 entries as new ($plan)');
  check(plan.marksNew == 1, 'plan counts the exclusion mark as new');

  // Merge: target already holds one day that the document overwrites.
  final overwrittenDay = DateOnly.normalize(DateTime(2026, 3, 3));
  await target.entriesDao.upsertDaily(
    DailyEntry(
      date: DateTime(2026, 3, 3),
      bleeding: Bleeding.spotting,
      bbtC: 40.0, // obviously different content to prove the replace
    ),
  );
  final plan2 = await planDatabaseImport(target, json);
  check(plan2.entriesOverwritten == 1 && plan2.entriesNew == 3,
      'plan flips the pre-existing day to overwrite');

  final summary = await importJsonToDatabase(target, json);
  check(
      summary.entriesNew == 3 &&
          summary.entriesOverwritten == 1 &&
          summary.marksNew == 1,
      'executed counts match the plan: $summary');
  final migrated = await target.entriesDao.allEntries();
  check(migrated.length == 4, 'import wrote 4 entry rows total');
  final day2 = migrated.firstWhere((e) => e.date == overwrittenDay);
  check(day2.bleeding == Bleeding.medium && day2.bbtC == 36.05,
      'import OVERWROTE the existing day with document content');
  // CycleEntry exposes bleeding as the mapped enum (int storage, converter
  // in the db layer) and the mucus signs as raw TEXT tokens (mapping in the
  // mapper layer); check that both survived the round trip.
  check(day2.mucusSign == 's' && day2.mucusQuality == 'mi',
      'mucus fertility-sign tokens survive the round trip');
  final heavyRow = migrated
      .firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 3, 5)));
  check(heavyRow.bleeding == Bleeding.heavy,
      'the heavy level survives the export/import round trip');
  // The current document fields: CycleEntry carries the firmness as the raw
  // TEXT token, the sex times as the raw INTEGER mask, and the raw
  // disturbance mask verbatim — check that all of it survived.
  check(heavyRow.mucusSign == 'a',
      'the Ausfluss sign survives the export/import round trip');
  check(heavyRow.cervixFirmness == 'hard',
      'the firmness token survives the export/import round trip');
  check(heavyRow.sexTimings == SexTiming.start.bit | SexTiming.end.bit,
      'the sex-timings mask survives the export/import round trip');
  final flaggedRow = migrated
      .firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 3, 2)));
  check(flaggedRow.tempDisturbances == TempDisturbance.sp.bit,
      'the raw disturbance mask survives the round trip verbatim');
  check((await target.marksDao.marksForDay(DateTime(2026, 3, 12))).length == 1,
      'mark imported idempotently on day 12');

  // Re-import of the SAME document: everything is now idempotent/skipped.
  final second = await importJsonToDatabase(target, json);
  check(second.entriesOverwritten == 4 && second.marksSkipped == 1,
      're-import overwrites all days and skips no marks: $second');
  final afterSecond = await target.entriesDao.allEntries();
  check(afterSecond.length == 4, 're-import keeps exactly 4 rows');

  check((await source.entriesDao.allEntries()).length == 4,
      'source untouched by import');

  // --- old-document translation (v1–4) -------------------------------------
  // Old documents carry profile keys (accepted and IGNORED) and the legacy
  // exclude_* booleans: illness → the kr bit, alcohol → the alk bit, and
  // ANY of the four true derives an ignoreTemperature mark (author
  // 'import') inside the import transaction — the interrupted-day analysis
  // semantics survive the shape change.
  final oldDocTarget = CycleDatabase(NativeDatabase.memory());
  const oldDocJson = '{"schema_version": 3, '
      '"exported_at": "2026-04-01T00:00:00Z", '
      '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
      '"entries": ['
      '{"profile_id": 1, "date": "2026-04-02", "bleeding": 2, '
      '"exclude_illness": true}, '
      '{"profile_id": 1, "date": "2026-04-03", "bleeding": 2, '
      '"exclude_alcohol": true}, '
      '{"profile_id": 1, "date": "2026-04-04", "bleeding": 2, '
      '"exclude_travel": true, "mood": true, "desire": true}], '
      '"marks": []}';
  final oldSummary = await importJsonToDatabase(oldDocTarget, oldDocJson);
  check(oldSummary.entriesNew == 3,
      'old-document rows import (profile keys ignored): $oldSummary');
  final oldRows = await oldDocTarget.entriesDao.allEntries();
  final illnessDay =
      oldRows.firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 2)));
  check(illnessDay.tempDisturbances == TempDisturbance.kr.bit,
      'exclude_illness translates into the kr mask bit');
  final alcoholDay =
      oldRows.firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 3)));
  check(alcoholDay.tempDisturbances == TempDisturbance.alk.bit,
      'exclude_alcohol translates into the alk mask bit');
  final travelDay =
      oldRows.firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 4, 4)));
  check(travelDay.tempDisturbances == 0,
      'exclude_travel leaves no mask bit (travel has no flag any more)');
  final exclusionMarks = (await oldDocTarget.marksDao.allMarks())
      .where((m) => m.markType == CycleMarkTypes.ignoreTemperature)
      .toList()
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
  check(
      exclusionMarks.length == 3 &&
          exclusionMarks.every((m) => m.author == 'import') &&
          DateOnly.sameDay(
              exclusionMarks.first.entryDate, DateTime(2026, 4, 2)),
      'every old excluded day derives an ignoreTemperature mark '
      "(author 'import') — the analysis semantics survive");
  // Re-import: the derived marks are idempotent (no duplicates).
  final oldSecond = await importJsonToDatabase(oldDocTarget, oldDocJson);
  check(
      (await oldDocTarget.marksDao.allMarks()).length == 3,
      'derived marks are idempotent on re-import (${oldSecond.marksSkipped} '
      'skipped)');

  // --- invalid bleeding vocabulary: plan counts only writable rows ---------
  // tryDailyEntryFromExport drops rows whose bleeding value the shared
  // parser rejects (numeric out of range or unknown token), so the merge
  // planner must count such rows in the invalid bucket instead of as writes
  // (counted == written).
  final invalidBleedingTarget = CycleDatabase(NativeDatabase.memory());
  final invalidBleedingDoc = buildExportJson(ExportBlob(
    exportedAt: DateTime(2026, 4, 1),
    entries: [
      {'date': '2026-04-05', 'bleeding': 'monsoon'},
      {'date': '2026-04-06', 'bleeding': 3},
    ],
    marks: const [],
  ));
  final invalidPlan =
      await planDatabaseImport(invalidBleedingTarget, invalidBleedingDoc);
  check(
      invalidPlan.entriesInvalid == 1 &&
          invalidPlan.entriesNew == 1 &&
          invalidPlan.entriesOverwritten == 0,
      'plan buckets the unparsable-bleeding row as invalid ($invalidPlan)');
  final invalidSummary =
      await importJsonToDatabase(invalidBleedingTarget, invalidBleedingDoc);
  check(invalidSummary.entriesInvalid == 1 && invalidSummary.entriesNew == 1,
      'invalid-bleeding row reported invalid, not written: $invalidSummary');
  final validOnlyRows = await invalidBleedingTarget.entriesDao.allEntries();
  check(validOnlyRows.length == 1,
      'only the valid-bleeding row reached the database');
  check(validOnlyRows.single.bleeding == Bleeding.medium,
      'the valid numeric level (3) read back as medium');
  await invalidBleedingTarget.close();
  await oldDocTarget.close();

  // --- storage-level failure surfaces as ONE typed error -------------------
  // After close, any engine error must be wrapped (transaction rolled back,
  // nothing half-imported) instead of leaking a raw driver state.
  await target.close();
  var importFailed = false;
  try {
    await importJsonToDatabase(target, json);
  } on ImportFailedException {
    importFailed = true;
  }
  check(importFailed, 'storage-level failure becomes ImportFailedException');

  // --- DAO facade additions work on the real schema ------------------------
  final marks = await source.marksDao.allMarks();
  check(marks.length == 1 && marks.single.markType == 'ignoreTemperature',
      'allMarks facade');

  await source.close();
  print('\nAll export/import runtime smoke checks passed.');
}
