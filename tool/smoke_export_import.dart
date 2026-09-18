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
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/decimal_input.dart';
import 'package:cycle_app/domain/export_import.dart';
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
  check(tryParseMucusSign('wet') == null, 'out-of-vocabulary sign is null');
  check(tryParseMucusQuality('gl') == MucusQuality.gl &&
      tryParseMucusQuality('glb') == MucusQuality.glb &&
      MucusQuality.gl != MucusQuality.glb,
      'glasig (gl) and gelblich (glb) are distinct qualities');
  check(
      sanitizeMucusPair(sign: MucusSign.f, quality: MucusQuality.w).quality ==
          null,
      'quality collapses without the S sign');
  check(mucusDisplay(sign: MucusSign.s, quality: MucusQuality.ew).superscript ==
          'EW',
      'S with EW quality renders the uppercase superscript token');

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
      excludeTravel: true,
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
    ),
  );
  await source.marksDao.addMark(1, DateTime(2026, 3, 12), 'baseline');
  final partner = await source.profilesDao.addProfile('partner', ordinal: 1);
  await source.entriesDao.upsertDaily(
    DailyEntry(date: DateTime(2026, 3, 4), bleeding: Bleeding.none),
    profileId: partner.id,
  );

  final json = await exportDatabaseToJson(source);
  check(json.contains('"schema_version": $exportSchemaVersion'),
      'document carries schema version');
  // The current document shape carries bleeding as NUMERIC levels
  // (Bleeding.level): heavy(4) from the added day, none(0) from the
  // partner's day.
  check(json.contains('"bleeding": 4') && json.contains('"bleeding": 0'),
      'export carries bleeding as numeric levels');
  check(json.contains('"mucus_sign": "s"') &&
          json.contains('"mucus_quality": "mi"'),
      'export carries the fertility-sign tokens');
  check(json.contains('partner'), 'profile list exported');

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
  check(plan.marksNew == 1, 'plan counts the baseline mark as new');
  check(plan.profilesToInsert == 1, 'plan re-creates the partner profile only');

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
          summary.profilesToInsert == 1 &&
          summary.marksNew == 1,
      'executed counts match the plan: $summary');
  final migrated = await target.entriesDao.allEntriesForAllProfiles();
  check(migrated.length == 4, 'import wrote 4 entry rows total');
  final day2 = migrated.firstWhere((e) => e.date == overwrittenDay);
  check(day2.bleeding == Bleeding.medium && day2.bbtC == 36.05,
      'import OVERWROTE the existing day with document content');
  // CycleEntry exposes bleeding as the mapped enum (int storage, converter
  // in the db layer) and the mucus signs as raw TEXT tokens (mapping in the
  // mapper layer); check that both survived the round trip.
  check(day2.mucusSign == 's' && day2.mucusQuality == 'mi',
      'mucus fertility-sign tokens survive the round trip');
  final heavyRow =
      migrated.firstWhere((e) => DateOnly.sameDay(e.date, DateTime(2026, 3, 5)));
  check(heavyRow.bleeding == Bleeding.heavy,
      'the heavy level survives the export/import round trip');

  final targetProfiles = await target.profilesDao.allProfiles();
  check(targetProfiles.where((p) => p.name == 'partner').length == 1,
      'partner profile re-created by name');
  final partnerInTarget = targetProfiles.firstWhere((p) => p.name == 'partner');
  check(migrated.where((e) => e.profileId == partnerInTarget.id).length == 1,
      'partner entry landed under the re-created profile');
  check(
      (await target.marksDao.marksForDay(1, DateTime(2026, 3, 12))).length == 1,
      'mark imported idempotently on day 12');

  // Re-import of the SAME document: everything is now idempotent/skipped.
  final second = await importJsonToDatabase(target, json);
  check(second.entriesOverwritten == 4 && second.marksSkipped == 1,
      're-import overwrites all days and skips no marks: $second');
  final afterSecond = await target.entriesDao.allEntriesForAllProfiles();
  check(afterSecond.length == 4, 're-import keeps exactly 4 rows');

  check((await source.entriesDao.allEntriesForAllProfiles()).length == 4,
      'source untouched by import');

  // --- profile-id remap: document ids that collide differently -------------
  // The target already knows profile ids 1 and 2; the document references
  // profile 4 (unknown here). Re-creation assigns the AUTO id 3, so every
  // document row for profile 4 must be written under id 3 — without the
  // remap this aborted the ENTIRE import on the foreign-key violation.
  final mixed = CycleDatabase(NativeDatabase.memory());
  final resident = await mixed.profilesDao.addProfile('resident', ordinal: 1);
  check(resident.id == 2, 'fixture: device ids are main=1 and resident=2');
  final remapDoc = buildExportJson(ExportBlob(
    exportedAt: DateTime(2026, 4, 1),
    profiles: const [
      {'id': 1, 'name': 'main', 'ordinal': 0},
      {'id': 4, 'name': 'partner-doc', 'ordinal': 1},
    ],
    entries: [
      // Hand-written rows carry the CURRENT document shape: bleeding is the
      // numeric level (0 none … 4 heavy).
      {'profile_id': 4, 'date': '2026-04-02', 'bleeding': 4},
      {
        'profile_id': 1,
        'date': '2026-04-10',
        'bleeding': 2,
        'bbt_c': 36.4,
      },
    ],
    marks: [
      {
        'profile_id': 4,
        'entry_date': '2026-04-20',
        'mark_type': 'peak',
        'author': 'user',
      },
    ],
  ));
  final remapSummary = await importJsonToDatabase(mixed, remapDoc);
  check(
      remapSummary.entriesNew == 2 &&
          remapSummary.profilesToInsert == 1 &&
          remapSummary.marksNew == 1 &&
          remapSummary.entriesOverwritten == 0,
      'remap plan counts executed as expected: $remapSummary');
  final profilesAfter = await mixed.profilesDao.allProfiles();
  final partnerActual =
      profilesAfter.singleWhere((p) => p.name == 'partner-doc');
  check(partnerActual.id != 4,
      'partner-doc re-created under auto id ${partnerActual.id}, not 4');
  final allAfter = await mixed.entriesDao.allEntriesForAllProfiles();
  check(
      allAfter.length == 2 &&
          allAfter.any((e) =>
              e.profileId == partnerActual.id &&
              e.bleeding == Bleeding.heavy &&
              DateOnly.sameDay(e.date, DateTime(2026, 4, 2))),
      'document row for profile 4 written under the ACTUAL profile id '
      '(numeric level 4 read back as heavy)');
  check(
      allAfter.any((e) =>
          e.profileId == 1 &&
          e.bleeding == Bleeding.light &&
          DateOnly.sameDay(e.date, DateTime(2026, 4, 10))),
      'row for a device-known profile id stays on that profile '
      '(numeric level 2 read back as light)');
  final markRows = await mixed.marksDao.allMarksForAllProfiles();
  check(markRows.single.profileId == partnerActual.id,
      'mark remapped to the actual profile id as well');

  // Import-summary structure intact after the round trips.
  check(remapSummary.duplicateEntryRows == 0, 'no duplicate rows counted');

  // --- numeric-string ids must import exactly once, like int ids -----------
  // Some tools serialize profile ids as strings ('"profile_id": "1"');
  // the merge planner accepts them, so the writer must too. Pre-fix these
  // rows were counted in the summary but silently skipped (entries) or
  // aborted the whole transaction (marks: `as int?` TypeError).
  final stringIdTarget = CycleDatabase(NativeDatabase.memory());
  final stringIdDoc = buildExportJson(ExportBlob(
    exportedAt: DateTime(2026, 4, 1),
    profiles: const [
      {'id': '1', 'name': 'main', 'ordinal': 0},
    ],
    entries: [
      {'profile_id': '1', 'date': '2026-04-02', 'bleeding': 1},
    ],
    marks: [
      {
        'profile_id': '1',
        'entry_date': '2026-04-03',
        'mark_type': 'baseline',
        'author': 'user',
      },
    ],
  ));
  final stringIdSummary = await importJsonToDatabase(stringIdTarget, stringIdDoc);
  check(
      stringIdSummary.entriesNew == 1 &&
          stringIdSummary.marksNew == 1 &&
          stringIdSummary.profilesToInsert == 0,
      'string-id document planned as counted: $stringIdSummary');
  final stringIdRows = await stringIdTarget.entriesDao.allEntriesForAllProfiles();
  check(
      stringIdRows.length == 1 &&
          stringIdRows.single.profileId == 1 &&
          stringIdRows.single.bleeding == Bleeding.spotting,
      'string id "1" addresses the known device profile 1 (level 1 '
      'read back as spotting)');
  check(
      (await stringIdTarget.marksDao.allMarksForAllProfiles()).length == 1,
      'string-id mark landed under profile 1');
  check(await stringIdTarget.profilesDao.allProfiles().then((p) => p.length) == 1,
      'no duplicate profile created for the string id');

  // --- invalid bleeding vocabulary: plan counts only writable rows ---------
  // tryDailyEntryFromExport drops rows whose bleeding value the shared
  // parser rejects (numeric out of range or unknown token), so the merge
  // planner must count such rows in the invalid bucket instead of as writes
  // (counted == written).
  final invalidBleedingTarget = CycleDatabase(NativeDatabase.memory());
  final invalidBleedingDoc = buildExportJson(ExportBlob(
    exportedAt: DateTime(2026, 4, 1),
    profiles: const [],
    entries: [
      {'profile_id': 1, 'date': '2026-04-05', 'bleeding': 'monsoon'},
      {'profile_id': 1, 'date': '2026-04-06', 'bleeding': 3},
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
  check(
      invalidSummary.entriesInvalid == 1 && invalidSummary.entriesNew == 1,
      'invalid-bleeding row reported invalid, not written: $invalidSummary');
  final validOnlyRows =
      await invalidBleedingTarget.entriesDao.allEntriesForAllProfiles();
  check(validOnlyRows.length == 1,
      'only the valid-bleeding row reached the database');
  check(validOnlyRows.single.bleeding == Bleeding.medium,
      'the valid numeric level (3) read back as medium');
  await invalidBleedingTarget.close();

  // --- storage-level failure surfaces as ONE typed error -------------------
  // After close, any engine error must be wrapped (transaction rolled back,
  // nothing half-imported) instead of leaking a raw driver state.
  await mixed.close();
  var importFailed = false;
  try {
    await importJsonToDatabase(mixed, json);
  } on ImportFailedException {
    importFailed = true;
  }
  check(importFailed, 'storage-level failure becomes ImportFailedException');

  // --- DAO facade additions work on the real schema ------------------------
  final marks = await source.marksDao.allMarksForAllProfiles();
  check(marks.length == 1 && marks.single.markType == 'baseline',
      'allMarksForAllProfiles facade');

  await source.close();
  await target.close();
  print('\nAll export/import runtime smoke checks passed.');
}
