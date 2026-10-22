// Export-adapter tests: the JSON document boundary — build/import/plan
// round trips, the version stamp, sparse row shapes and method snapshots.
//
// Pure Dart against NativeDatabase.memory() — no platform channels. Same
// Linux system-sqlite note as test/db/cycle_database_test.dart.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/db/settings_store.dart';

/// The single entries row of an exported document, decoded — the
/// custom-marks tests assert the DOCUMENT shape, not pretty-printed text.
Map<String, Object?> exportedSingleEntryRow(String json) =>
    ((jsonDecode(json) as Map<String, Object?>)['entries']! as List).single
        as Map<String, Object?>;

void main() {
  // Not final: setUp assigns a fresh in-memory database before every test
  // (closed again by the per-test tearDown registered inside setUp).
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  group('export adapter: import/export without profiles', () {
    // v5 documents carry NO profile keys anywhere — the document root is
    // exactly schema_version / exported_at / entries / marks.
    ExportBlob simpleDoc() => ExportBlob(
      exportedAt: DateTime.utc(2026, 4, 1),
      entries: const [
        {'date': '2026-04-02', 'bleeding': 'period'},
        {'date': '2026-04-10', 'bleeding': 'period', 'bbt_c': 36.4},
      ],
      marks: const [
        {
          'entry_date': '2026-04-20',
          'mark_type': 'mucusPeakDay',
          'author': 'user',
        },
      ],
    );

    test(
      'a profile-free document imports day-keyed, no profile handling',
      () async {
        final summary = await importJsonToDatabase(
          db,
          buildExportJson(simpleDoc()),
        );
        expect(summary.entriesNew, 2);
        expect(summary.marksNew, 1);
        final rows = await db.entriesDao.allEntries();
        expect(rows, hasLength(2));
        final byKey = {for (final r in rows) formatIsoDay(r.date): r};
        expect(
          byKey['2026-04-10']!.bbtC,
          36.4,
          reason: 'the row lands on its day, identified by the day alone',
        );
        final mark = (await db.marksDao.allMarks()).single;
        expect(DateOnly.sameDay(mark.entryDate, DateTime(2026, 4, 20)), isTrue);
      },
    );

    test(
      're-importing the same document is idempotent (day/type keys)',
      () async {
        final doc = buildExportJson(simpleDoc());
        await importJsonToDatabase(db, doc);

        final second = await importJsonToDatabase(db, doc);
        expect(second.entriesNew, 0);
        expect(second.entriesOverwritten, 2);
        expect(second.marksNew, 0);
        expect(
          second.marksSkipped,
          1,
          reason:
              'marks are skip-idempotent on the (entry_date, mark_type) '
              'key',
        );

        final rows = await db.entriesDao.allEntries();
        expect(rows, hasLength(2), reason: 'no duplicate days on re-import');
        expect(await db.marksDao.allMarks(), hasLength(1));
      },
    );

    test('old-document profile keys are accepted and ignored', () async {
      // v1–4 documents carry `profile_id` on every row and a root
      // `profiles` list. The v5 reader tolerates both keys (unknown keys
      // never error) and NEVER reads them: rows merge by day /
      // (entry_date, mark_type) alone.
      const oldJson =
          '{"schema_version": 3, '
          '"exported_at": "2026-04-01T00:00:00Z", '
          '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
          '"entries": [{"profile_id": 1, "date": "2026-04-02", '
          '"bleeding": 3}], '
          '"marks": [{"profile_id": 1, "entry_date": "2026-04-03", '
          '"mark_type": "mucusPeakDay", "author": "user"}]}';
      final summary = await importJsonToDatabase(db, oldJson);
      expect(summary.entriesNew, 1);
      expect(summary.marksNew, 1);

      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(
        DateOnly.sameDay(rows.single.date, DateTime(2026, 4, 2)),
        isTrue,
        reason: 'the day merge key holds regardless of profile_id',
      );
      expect(await db.marksDao.allMarks(), hasLength(1));
    });

    test('old-document exclude_* keys derive an ignoreTemperature mark '
        "(author 'import')", () async {
      // The old-document translation (inside the import transaction):
      // any of the four true exclude_* keys derives the analysis mark for
      // that day — and the current mark token is ignoreTemperature
      // (temperature-evaluation-scoped only — the mark does not affect
      // cycle-start suggestions any more). The derived token is pinned
      // here (a rename of the
      // stored vocabulary is a data-visible change, even with no schema
      // bump).
      const oldJson =
          '{"schema_version": 3, '
          '"exported_at": "2026-04-01T00:00:00Z", '
          '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
          '"entries": [{"profile_id": 1, "date": "2026-04-02", '
          '"bleeding": 3, "exclude_travel": true}], '
          '"marks": []}';
      final summary = await importJsonToDatabase(db, oldJson);
      expect(summary.entriesNew, 1);
      expect(
        summary.marksNew,
        0,
        reason:
            'the derived marks ride inside the transaction without '
            'being counted (document rows only)',
      );

      final marks = await db.marksDao.allMarks();
      expect(
        marks,
        hasLength(1),
        reason: 'exclude_travel=true derives the temperature-ignore mark',
      );
      expect(
        marks.single.markType,
        CycleMarkTypes.ignoreTemperature,
        reason:
            'the derived mark token is the RENAMED one — the old '
            'name is gone from the production vocabulary (an escape '
            'hatch of the open-TEXT column would fail this pin)',
      );
      expect(marks.single.author, 'import');
    });

    test('old rows differing only by profile_id collapse to one day key '
        '(first occurrence wins)', () async {
      // Consequence of ignoring the profile dimension: two same-day rows
      // that differed only by profile_id now share ONE merge key; the plan
      // counts the second as a duplicate and the first occurrence wins.
      final doc = buildExportJson(
        ExportBlob(
          exportedAt: DateTime.utc(2026, 4, 1),
          entries: [
            {'profile_id': 1, 'date': '2026-04-02', 'bleeding': 3},
            {'profile_id': 3, 'date': '2026-04-02', 'bleeding': 0},
          ],
          marks: const [],
        ),
      );
      final summary = await planDatabaseImport(db, doc);
      expect(
        summary.duplicateEntryRows,
        1,
        reason: 'the (profile, day) key collapsed to the day key',
      );
      expect(summary.entriesNew, 1);

      await importJsonToDatabase(db, doc);
      final rows = await db.entriesDao.allEntries();
      expect(rows, hasLength(1));
      expect(
        rows.single.bleeding,
        Bleeding.medium,
        reason: 'the FIRST occurrence wins (bleeding level 3 = medium)',
      );
    });

    test(
      'unparsable bleeding rows are reported invalid and NOT written',
      () async {
        // The counting-vs-writing guarantee for field-level gates: the plan
        // counts exactly the rows the writer produces, so a row the writer
        // drops (unknown bleeding vocabulary) must appear in the invalid
        // bucket and must not reach the database.
        final doc = buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 4, 1),
            entries: [
              {'date': '2026-05-01', 'bleeding': 'heavy'},
              {'date': '2026-05-02', 'bleeding': 'period'},
            ],
            marks: const [
              {
                'entry_date': '2026-05-03',
                'mark_type': 'mucusPeakDay',
                'author': 'user',
              },
            ],
          ),
        );

        final summary = await planDatabaseImport(db, doc);
        expect(summary.entriesInvalid, 1);
        expect(summary.entriesNew, 1);
        expect(summary.entriesWritten, 1);

        final summary2 = await importJsonToDatabase(db, doc);
        expect(summary2.entriesInvalid, 1);
        expect(summary2.entriesNew, 1);
        final rows = await db.entriesDao.allEntries();
        expect(
          rows,
          hasLength(1),
          reason: 'the unparsable-bleeding row is never stored',
        );
        expect(
          DateOnly.sameDay(rows.single.date, DateTime(2026, 5, 2)),
          isTrue,
        );
        // The mark row was untouched by the entry gate.
        expect(await db.marksDao.allMarks(), hasLength(1));
      },
    );

    group('measured time-of-day in the EXPORT version boundary', () {
      test(
        'export carries the stored minutes; fresh db keeps it on import',
        () async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 4, 2),
              bbtC: 36.4,
              measuredAtMinutes: 405, // 06:45
            ),
          );

          final json = await exportDatabaseToJson(db);
          expect(json, contains('"measured_at_minutes": 405'));

          final target = CycleDatabase(NativeDatabase.memory());
          addTearDown(target.close);
          final summary = await importJsonToDatabase(target, json);
          expect(summary.entriesNew, 1);
          final row = await target.entriesDao.entryFor(DateTime(2026, 4, 2));
          expect(row!.measuredAtMinutes, 405);
        },
      );

      test(
        'export normalizes a stored time without a temperature to null',
        () async {
          // A legacy-style row (raw SQL): time stored without a temperature,
          // e.g. written before the app enforced the pairing. The export
          // document must not carry the stray time — what it carries is what
          // a re-import would store.
          final legacyDay = DateTime(2026, 6, 20);
          final legacyEpochDay = DateOnly.normalize(
            legacyDay,
          ).difference(DateTime.utc(1970)).inDays;
          await db.customStatement(
            'INSERT INTO cycle_entries (date, measured_at_minutes) '
            'VALUES ($legacyEpochDay, 405)',
          );

          final blob = await exportDatabaseToBlob(db);
          final legacyRow = blob.entries.singleWhere(
            (e) => e['date'] == formatIsoDay(legacyDay),
          );
          expect(legacyRow['bbt_c'], isNull);
          expect(
            legacyRow['measured_at_minutes'],
            isNull,
            reason:
                'the export document never carries a time without its '
                'temperature',
          );
        },
      );

      test(
        'old export documents without the field import with no time',
        () async {
          // A v1 document (shape published before the field existed). Raw
          // JSON on purpose: this pins the backward compatibility of the
          // actual file content (note the old profile keys: tolerated and
          // ignored), not a hand-built blob.
          const oldJson =
              '{"schema_version": 1, '
              '"exported_at": "2026-04-01T00:00:00Z", '
              '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
              '"entries": [{"profile_id": 1, "date": "2026-05-01", '
              '"bbt_c": 36.4, "bleeding": "none"}], '
              '"marks": []}';
          final summary = await importJsonToDatabase(db, oldJson);
          expect(summary.entriesNew, 1);

          final row = await db.entriesDao.entryFor(DateTime(2026, 5, 1));
          expect(row!.bbtC, 36.4);
          expect(
            row.measuredAtMinutes,
            isNull,
            reason:
                'pre-field exports carry no time; that must not fail '
                'and must not fabricate one either',
          );
        },
      );
    });

    group('bleeding levels in the export version boundary', () {
      test('export carries numeric bleeding levels and the current schema'
          ' version', () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 4, 2), bleeding: Bleeding.heavy),
        );
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 4, 3), bleeding: Bleeding.none),
        );

        final json = await exportDatabaseToJson(db);
        final decoded = jsonDecode(json) as Map<String, Object?>;
        expect(
          decoded['schema_version'],
          exportSchemaVersion,
          reason: 'documents always stamp the version they were written in',
        );
        expect(
          json,
          contains('"bleeding": 4'),
          reason: 'heavy is exported as its numeric level',
        );
        expect(
          json,
          isNot(contains('"bleeding": 0')),
          reason:
              'the sparse shape omits the bleeding key of none days '
              'entirely — the reader treats a missing key as no bleeding '
              'recorded',
        );
        expect(
          json,
          isNot(contains('"bleeding": "')),
          reason: 'documents no longer carry bleeding string tokens',
        );
        // The v5 document carries no profile keys at all.
        expect(json, isNot(contains('profile_id')));
        expect(json, isNot(contains('profiles')));
      });

      test(
        'legacy v1 token documents import and read back as mapped levels',
        () async {
          // A v1 document (published before heaviness existed) with the legacy
          // token vocabulary; the profile keys are tolerated and ignored.
          // Raw JSON on purpose: pins the actual file content of old exports,
          // not a hand-built blob.
          const oldJson =
              '{"schema_version": 1, '
              '"exported_at": "2026-04-01T00:00:00Z", '
              '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
              '"entries": ['
              '{"profile_id": 1, "date": "2026-05-01", "bleeding": "period"}, '
              '{"profile_id": 1, "date": "2026-05-02", "bleeding": "spotting"}], '
              '"marks": []}';
          final summary = await importJsonToDatabase(db, oldJson);
          expect(summary.entriesInvalid, 0);
          expect(summary.entriesWritten, 2);

          expect(
            (await db.entriesDao.entryFor(DateTime(2026, 5, 1)))!.bleeding,
            Bleeding.medium,
            reason: 'period (generic menstruation) degrades to medium',
          );
          expect(
            (await db.entriesDao.entryFor(DateTime(2026, 5, 2)))!.bleeding,
            Bleeding.spotting,
          );
        },
      );
    });

    group('sparse entry rows at the export document boundary', () {
      test('the writer omits every neutral key and the round trip is '
          'lossless (idempotence)', () async {
        // A fully neutral day (level-0 bleeding, no temperature, no other
        // observation) — the sparse document carries ONLY its date.
        await db.entriesDao.upsertDaily(DailyEntry(date: DateTime(2026, 4, 2)));
        // A rich day with every observation at a non-neutral value.
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 4, 3),
            bbtC: 36.4,
            measuredAtMinutes: 405,
            bleeding: Bleeding.medium,
            tempDisturbances: TempDisturbance.kr.bit,
            mucusSign: MucusSign.s,
            mucusQuality: MucusQuality.ew,
            cervixPosition: CervixPosition.veryHigh,
            cervixOpening: CervixOpening.open,
            cervixFirmness: CervixFirmness.soft,
            painBreast: true,
            painMittelschmerz: true,
            sexTimings: SexTiming.midday.bit,
            notes: 'rich day',
          ),
        );

        final json = await exportDatabaseToJson(db);
        expect(
          json,
          isNot(contains('"bleeding": 0')),
          reason:
              'the sparse shape never writes the neutral bleeding '
              'level — a level-0 day leaves the key out entirely',
        );
        expect(
          json,
          isNot(contains(': null')),
          reason:
              'entry rows carry no null-valued keys in the sparse '
              'shape',
        );

        final decoded = jsonDecode(json) as Map<String, Object?>;
        final rows = [
          for (final raw in decoded['entries'] as List)
            Map<String, Object?>.from(raw as Map),
        ];
        final neutral = rows.singleWhere((r) => r['date'] == '2026-04-02');
        expect(neutral.keys, {
          'date',
        }, reason: 'a fully neutral day exports only its date');
        final rich = rows.singleWhere((r) => r['date'] == '2026-04-03');
        expect(rich.keys, {
          'date',
          'bbt_c',
          'measured_at_minutes',
          'bleeding',
          'temp_disturbances',
          'mucus_sign',
          'mucus_quality',
          'cervix_position',
          'cervix_opening',
          'cervix_firmness',
          'pain_breast',
          'pain_mittelschmerz',
          'sex_timings',
          'notes',
        });
        expect(rich.values, everyElement(isNotNull));

        // Master criterion: export → parse → import → exactly the same
        // DailyEntry set; a re-export of the imported data stays sparse
        // with the same underlying row maps.
        final target = CycleDatabase(NativeDatabase.memory());
        addTearDown(target.close);
        final summary = await importJsonToDatabase(target, json);
        expect(summary.entriesInvalid, 0);
        expect(summary.entriesWritten, 2);
        // The export document carries only observation keys — never the
        // createdAt/updatedAt audit columns — and importing the day stamps
        // fresh audit values for it. The round trip is therefore compared on
        // the stored day data (via dailyEntryFromDrift), not on the audit
        // columns, which keeps this deterministic instead of wall-clock
        // dependent.
        expect(
          [
            for (final row in await target.entriesDao.allEntries())
              dailyEntryFromDrift(row),
          ],
          unorderedEquals([
            for (final row in await db.entriesDao.allEntries())
              dailyEntryFromDrift(row),
          ]),
          reason: 'import stores exactly the source day set',
        );

        Map<String, Map<String, Object?>> byDay(
          List<Map<String, Object?>> exported,
        ) => {for (final row in exported) row['date']! as String: row};
        final firstExport = await exportDatabaseToBlob(db);
        final reExported = await exportDatabaseToBlob(target);
        expect(
          byDay(reExported.entries),
          byDay(firstExport.entries),
          reason: 'a previously sparse dataset re-exports sparse',
        );
        expect(reExported.marks, firstExport.marks);
      });
    });

    group('measurement method snapshots at the export boundary', () {
      test(
        'a snapshot-free database exports exactly the four root keys',
        () async {
          // The byte-compatibility decision: a dataset without snapshots
          // emits NO methods key at all, so the pinned four-key document
          // shape survives unchanged.
          final json = await exportDatabaseToJson(db);
          final decoded = jsonDecode(json) as Map<String, Object?>;
          expect(decoded.keys.toSet(), {
            'schema_version',
            'exported_at',
            'entries',
            'marks',
          });
        },
      );

      test('export carries seeded snapshots in the sparse row shape', () async {
        await db.measurementMethodsDao.upsertByDate(
          date: DateTime(2026, 2, 1),
          route: MeasurementRoute.vaginal,
          thermometer: 'ThermaPen',
        );
        await db.measurementMethodsDao.upsertByDate(
          date: DateTime(2026, 3, 15),
          route: MeasurementRoute.oral,
        );

        final json = await exportDatabaseToJson(db);
        expect(json, contains('"methods"'));
        expect(
          json,
          isNot(contains(': null')),
          reason: 'the thermometer key is omitted when null, never null',
        );

        final decoded = jsonDecode(json) as Map<String, Object?>;
        final rows = [
          for (final raw in decoded['methods']! as List)
            Map<String, Object?>.from(raw as Map),
        ];
        expect(rows, [
          {
            'date': '2026-02-01',
            'method': 'vaginal',
            'thermometer': 'ThermaPen',
          },
          // The sparse shape: no thermometer key on the name-less row.
          {'date': '2026-03-15', 'method': 'oral'},
        ], reason: 'ordered by day');
      });

      test(
        'import writes snapshots via the DAO, overwriting stored days',
        () async {
          await db.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 2, 1),
            route: MeasurementRoute.vaginal,
            thermometer: 'ThermaPen',
          );
          await db.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 3, 15),
            route: MeasurementRoute.oral,
          );

          final target = CycleDatabase(NativeDatabase.memory());
          addTearDown(target.close);
          // A stored snapshot on a day the document also carries: the
          // entries merge rule — overwrite, never a duplicate row.
          await target.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 2, 1),
            route: MeasurementRoute.other,
            thermometer: 'Obsolete',
          );

          final json = await exportDatabaseToJson(db);
          final summary = await importJsonToDatabase(target, json);
          expect(summary.methodsNew, 1, reason: '2026-03-15 is new');
          expect(summary.methodsOverwritten, 1, reason: '2026-02-01 stored');
          expect(summary.methodsWritten, 2);

          // Read back through the domain mapper (same read the rest of the
          // app uses), ordered ascending by day — two rows, no duplicate.
          final rows = [
            for (final row in await target.measurementMethodsDao.allSnapshots())
              measurementSnapshotFromDrift(row),
          ];
          expect(rows, [
            MeasurementMethodSnapshot(
              date: DateTime(2026, 2, 1),
              route: MeasurementRoute.vaginal,
              thermometer: 'ThermaPen',
            ),
            MeasurementMethodSnapshot(
              date: DateTime(2026, 3, 15),
              route: MeasurementRoute.oral,
            ),
          ]);
        },
      );

      test(
        'an old (pre-methods) document leaves stored methods untouched',
        () async {
          // The additive root key: a document that simply omits it must not
          // touch the device's snapshots (missing key = no snapshots).
          await db.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 2, 1),
            route: MeasurementRoute.rectal,
            thermometer: 'Alt',
          );
          const oldJson =
              '{"schema_version": 3, '
              '"exported_at": "2026-04-01T00:00:00Z", '
              '"profiles": [{"id": 1, "name": "main", "ordinal": 0}], '
              '"entries": [{"profile_id": 1, "date": "2026-04-02", '
              '"bleeding": 3}], '
              '"marks": []}';

          final summary = await importJsonToDatabase(db, oldJson);
          expect(summary.entriesNew, 1);
          expect(summary.methodsNew, 0);

          final rows = [
            for (final row in await db.measurementMethodsDao.allSnapshots())
              measurementSnapshotFromDrift(row),
          ];
          expect(rows, [
            MeasurementMethodSnapshot(
              date: DateTime(2026, 2, 1),
              route: MeasurementRoute.rectal,
              thermometer: 'Alt',
            ),
          ]);
        },
      );

      test(
        'invalid method rows are counted AND skipped (counted == written)',
        () async {
          final doc = buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 4, 1),
              entries: const [],
              marks: const [],
              methods: [
                {'date': '2026-05-01', 'method': 'vaginal'},
                // The SQL CHECK cannot store this token — a plan that
                // counted it as a write would break the writer-parity rule.
                {'date': '2026-05-02', 'method': 'sublingual'},
              ],
            ),
          );

          final plan = await planDatabaseImport(db, doc);
          expect(plan.methodsInvalid, 1);
          expect(plan.methodsWritten, 1);

          final summary = await importJsonToDatabase(db, doc);
          expect(summary.methodsInvalid, 1);
          expect(summary.methodsWritten, 1);
          final rows = [
            for (final row in await db.measurementMethodsDao.allSnapshots())
              measurementSnapshotFromDrift(row),
          ];
          expect(rows, hasLength(1));
          expect(rows.single.route, MeasurementRoute.vaginal);
        },
      );

      test(
        'the duplicate first-wins rule holds for same-day document rows',
        () async {
          final doc = buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 4, 1),
              entries: const [],
              marks: const [],
              methods: const [
                {'date': '2026-05-01', 'method': 'vaginal'},
                {'date': '2026-05-01', 'method': 'oral'},
              ],
            ),
          );

          final summary = await importJsonToDatabase(db, doc);
          expect(summary.methodsNew, 1);
          expect(summary.duplicateMethodRows, 1);
          final rows = [
            for (final row in await db.measurementMethodsDao.allSnapshots())
              measurementSnapshotFromDrift(row),
          ];
          expect(rows, hasLength(1));
          expect(
            rows.single.route,
            MeasurementRoute.vaginal,
            reason: 'the FIRST occurrence wins (the entries merge rule)',
          );
        },
      );

      test(
        'planDatabaseImport preview counts include the methods fields',
        () async {
          await db.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 5, 5),
            route: MeasurementRoute.other,
          );
          final json = await exportDatabaseToBlob(db).then(buildExportJson);

          final target = CycleDatabase(NativeDatabase.memory());
          addTearDown(target.close);
          await target.measurementMethodsDao.upsertByDate(
            date: DateTime(2026, 5, 5),
            route: MeasurementRoute.oral,
          );

          final plan = await planDatabaseImport(target, json);
          expect(plan.methodsNew, 0);
          expect(plan.methodsOverwritten, 1);
          expect(plan.methodsInvalid, 0);
          expect(plan.methodsWritten, 1);
        },
      );
    });

    group('custom category definitions in the document', () {
      test(
        'a definitions-free database exports NO customCategories key',
        () async {
          final decoded =
              jsonDecode(await exportDatabaseToJson(db))
                  as Map<String, Object?>;
          expect(
            decoded.containsKey('customCategories'),
            isFalse,
            reason: 'the pinned four-key document shape survives unchanged',
          );
        },
      );

      test('the export carries the stored definitions as stored', () async {
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']),
          const CustomCategory(name: 'Medikamente', visible: false),
        ]);

        final blob = await exportDatabaseToBlob(db);
        expect(blob.customCategories, [
          {
            'name': 'Sport',
            'visible': true,
            'items': ['Joggen', 'Kraft'],
          },
          {'name': 'Medikamente', 'visible': false, 'items': <Object?>[]},
        ]);
      });

      test(
        'the definitions-free export round-trips with an empty list',
        () async {
          final blob = await exportDatabaseToBlob(db);
          expect(blob.customCategories, isEmpty);
        },
      );

      test(
        'importing a document merges its definitions into the stored list',
        () async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ]);

          final doc = buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: const [
                {
                  'name': 'Sport',
                  'visible': true,
                  'items': ['Kraft'],
                  'future': 'ignored',
                },
                {'name': 'Medikamente', 'visible': false},
              ],
            ),
          );

          final summary = await importJsonToDatabase(db, doc);

          final expected = [
            const CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']),
            const CustomCategory(name: 'Medikamente', visible: false),
          ];
          final settings = await SettingsStore(db.settingsDao).load();
          expect(settings.customDiaryCategories, expected);
          expect(
            summary.customCategories,
            expected,
            reason:
                'the summary exposes the merged list the row was '
                'written from',
          );
          expect(summary.customCategoriesAdded, 1);
          expect(summary.customCategoriesChanged, isTrue);
          final raw = await db.settingsDao.readValue(
            SettingKeys.customDiaryCategories,
          );
          expect(
            raw,
            jsonEncode([for (final category in expected) category.toJson()]),
            reason: 'the row is written through the canonical shape',
          );
        },
      );

      test(
        'a definitions-free device adopts the document definitions',
        () async {
          final summary = await importJsonToDatabase(
            db,
            buildExportJson(
              ExportBlob(
                exportedAt: DateTime.utc(2026, 9, 15, 12),
                entries: const [],
                marks: const [],
                customCategories: const [
                  {
                    'name': 'Sport',
                    'visible': true,
                    'items': ['Joggen'],
                  },
                ],
              ),
            ),
          );

          expect(summary.customCategoriesChanged, isTrue);
          expect(summary.customCategoriesAdded, 1);
          final settings = await SettingsStore(db.settingsDao).load();
          expect(settings.customDiaryCategories, [
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ]);
        },
      );

      test('a colliding name keeps its stored position', () async {
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen']),
          const CustomCategory(name: 'Medikamente', visible: false),
        ]);

        final summary = await importJsonToDatabase(
          db,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: const [
                {'name': 'Medikamente', 'visible': false},
                {
                  'name': 'Sport',
                  'visible': true,
                  'items': ['Kraft'],
                },
              ],
            ),
          ),
        );

        expect(
          [for (final c in summary.customCategories) c.name],
          ['Sport', 'Medikamente'],
        );
        final settings = await SettingsStore(db.settingsDao).load();
        expect(
          [for (final c in settings.customDiaryCategories) c.name],
          ['Sport', 'Medikamente'],
        );
        expect(settings.customDiaryCategories.first.items, ['Joggen', 'Kraft']);
      });

      test('a definition merge leaves stored days and their custom marks '
          'alone', () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(
            date: DateTime(2026, 4, 2),
            bleeding: Bleeding.medium,
            customMarks: const {
              'Sport': ['Joggen'],
            },
          ),
        );
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ]);

        await importJsonToDatabase(
          db,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: const [
                {
                  'name': 'Sport',
                  'visible': true,
                  'items': ['Kraft'],
                },
              ],
            ),
          ),
        );

        final row = await db.entriesDao.entryFor(DateTime(2026, 4, 2));
        expect(dailyEntryFromDrift(row!).customMarks, {
          'Sport': ['Joggen'],
        }, reason: 'a tick keeps the label it was stored with');
      });

      test(
        'the document visibility wins and the summary lists the name',
        () async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ]);

          final summary = await importJsonToDatabase(
            db,
            buildExportJson(
              ExportBlob(
                exportedAt: DateTime.utc(2026, 9, 15, 12),
                entries: const [],
                marks: const [],
                customCategories: const [
                  {'name': 'Sport', 'visible': false, 'items': <String>[]},
                ],
              ),
            ),
          );

          final settings = await SettingsStore(db.settingsDao).load();
          expect(settings.customDiaryCategories.single.visible, isFalse);
          expect(summary.customCategoryVisibilityChanges, ['Sport']);
          expect(summary.customCategoriesChanged, isTrue);
        },
      );

      test('identical definitions write no settings row', () async {
        // A non-canonical extra key: any rewrite would canonicalize it away,
        // so the byte-identical row proves the no-write gate.
        final seeded = jsonEncode([
          {
            'name': 'Sport',
            'visible': true,
            'items': ['Joggen'],
            'future': 'kept verbatim',
          },
        ]);
        await db.settingsDao.writeValue(
          SettingKeys.customDiaryCategories,
          seeded,
        );

        final summary = await importJsonToDatabase(
          db,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: const [
                {
                  'name': 'Sport',
                  'visible': true,
                  'items': ['Joggen'],
                },
              ],
            ),
          ),
        );

        expect(summary.customCategoriesChanged, isFalse);
        expect(summary.customCategories, [
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ]);
        expect(
          await db.settingsDao.readValue(SettingKeys.customDiaryCategories),
          seeded,
          reason: 'an unchanged merge must not rewrite the settings row',
        );
      });

      test('a second import of the same document is idempotent', () async {
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ]);
        final doc = buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 9, 15, 12),
            entries: const [],
            marks: const [],
            customCategories: const [
              {
                'name': 'Sport',
                'visible': true,
                'items': ['Kraft'],
              },
              {
                'name': 'Neu',
                'visible': true,
                'items': ['X'],
              },
            ],
          ),
        );

        await importJsonToDatabase(db, doc);
        final afterFirst = await db.settingsDao.readValue(
          SettingKeys.customDiaryCategories,
        );

        final second = await importJsonToDatabase(db, doc);

        expect(second.customCategoriesChanged, isFalse);
        expect(second.customCategoriesAdded, 0);
        expect(second.customCategoryVisibilityChanges, isEmpty);
        expect(
          await db.settingsDao.readValue(SettingKeys.customDiaryCategories),
          afterFirst,
        );
      });

      test('blank-name and duplicate-name rows are skipped while the valid '
          'rows merge', () async {
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ]);

        final summary = await importJsonToDatabase(
          db,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: const [
                {
                  'name': '   ',
                  'items': ['x'],
                },
                {
                  'name': 'Neu',
                  'visible': true,
                  'items': ['X'],
                },
                {
                  'name': 'Neu',
                  'visible': false,
                  'items': ['Y'],
                },
              ],
            ),
          ),
        );

        expect(summary.customCategoriesInvalid, 1);
        expect(summary.duplicateCustomCategoryRows, 1);
        expect(summary.customCategoriesAdded, 1);
        final settings = await SettingsStore(db.settingsDao).load();
        expect(settings.customDiaryCategories, [
          const CustomCategory(name: 'Sport', items: ['Joggen']),
          const CustomCategory(name: 'Neu', items: ['X']),
        ]);
      });

      test('a merge beyond the UI caps is stored untruncated', () async {
        final longLabel = List.filled(customLabelMaxLength + 1, 'x').join();
        await SettingsStore(db.settingsDao).persistCustomCategories([
          for (var i = 0; i < maxCustomCategories; i++)
            CustomCategory(name: 'Kat$i', items: const ['gespeichert']),
        ]);

        await importJsonToDatabase(
          db,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 15, 12),
              entries: const [],
              marks: const [],
              customCategories: [
                {
                  'name': 'KatNeu1',
                  'items': ['neu'],
                },
                {
                  'name': 'KatNeu2',
                  'items': ['neu'],
                },
                {
                  'name': 'Kat0',
                  'items': [
                    for (var i = 0; i < maxCustomCategoryEntries; i++)
                      'Label$i',
                    longLabel,
                  ],
                },
              ],
            ),
          ),
        );

        final settings = await SettingsStore(db.settingsDao).load();
        final stored = settings.customDiaryCategories;
        expect(stored, hasLength(maxCustomCategories + 2));
        expect(stored.first.items, hasLength(1 + maxCustomCategoryEntries + 1));
        expect(stored.first.items.last, longLabel);
      });

      test('preview and apply report the same merge', () async {
        await SettingsStore(db.settingsDao).persistCustomCategories([
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ]);
        final doc = buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 9, 15, 12),
            entries: const [],
            marks: const [],
            customCategories: const [
              {
                'name': 'Sport',
                'visible': false,
                'items': ['Kraft'],
              },
              {
                'name': 'Neu',
                'visible': true,
                'items': ['X'],
              },
            ],
          ),
        );

        final plan = await planDatabaseImport(db, doc);
        expect(
          (await SettingsStore(db.settingsDao).load()).customDiaryCategories,
          [
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ],
          reason: 'the preview writes nothing',
        );

        final applied = await importJsonToDatabase(db, doc);

        expect(plan.customCategories, applied.customCategories);
        expect(plan.customCategoriesAdded, applied.customCategoriesAdded);
        expect(
          plan.customCategoryVisibilityChanges,
          applied.customCategoryVisibilityChanges,
        );
        expect(plan.customCategoriesChanged, applied.customCategoriesChanged);
        expect(plan.customCategoriesChanged, isTrue);
        expect(applied.customCategoryVisibilityChanges, ['Sport']);
      });

      test('importing an old-style document WITHOUT the key keeps the stored '
          'definitions', () async {
        const stored = [
          CustomCategory(name: 'Sport', items: ['Joggen']),
        ];
        await SettingsStore(db.settingsDao).persistCustomCategories(stored);

        final summary = await importJsonToDatabase(
          db,
          buildExportJson(simpleDoc()),
        );
        expect(summary.entriesNew, 2);
        expect(summary.customCategories, stored);
        expect(summary.customCategoriesChanged, isFalse);

        final settings = await SettingsStore(db.settingsDao).load();
        expect(
          settings.customDiaryCategories,
          stored,
          reason: 'an absent key carries no definitions data',
        );
      });

      test('an explicitly EMPTY customCategories key keeps the stored '
          'definitions', () async {
        const stored = [
          CustomCategory(name: 'Sport', items: ['Joggen']),
        ];
        await SettingsStore(db.settingsDao).persistCustomCategories(stored);

        // Raw JSON on purpose: the writer omits an empty list, so only a
        // hand-edited document carries this key shape.
        final doc = jsonEncode(<String, Object?>{
          'schema_version': exportSchemaVersion,
          'exported_at': '2026-09-15T12:00:00Z',
          'entries': <Object?>[],
          'marks': <Object?>[],
          'customCategories': <Object?>[],
        });

        final summary = await importJsonToDatabase(db, doc);

        expect(summary.customCategories, stored);
        expect(summary.customCategoriesChanged, isFalse);
        final settings = await SettingsStore(db.settingsDao).load();
        expect(settings.customDiaryCategories, stored);
      });

      test(
        'a corrupt customCategories value fails the import loudly',
        () async {
          // Raw JSON on purpose: the corrupt mixed list cannot be expressed
          // through the typed blob (row maps only) — exactly the hand-edited
          // document shape the gate exists for.
          final doc = jsonEncode(<String, Object?>{
            'schema_version': exportSchemaVersion,
            'exported_at': '2026-09-15T12:00:00Z',
            'entries': [
              {'date': '2026-04-02', 'bleeding': 3},
            ],
            'marks': <Object?>[],
            'customCategories': [
              {'name': 'Sport'},
              42,
            ],
          });

          await expectLater(
            importJsonToDatabase(db, doc),
            throwsA(isA<FormatException>()),
            reason: 'a non-object member is a document error',
          );
          expect(
            await db.entriesDao.allEntries(),
            isEmpty,
            reason: 'the failed import wrote NOTHING (transaction rollback)',
          );
        },
      );
    });

    group('custom marks in the document', () {
      String stringFormMarksDocument() => buildExportJson(
        ExportBlob(
          exportedAt: DateTime.utc(2026, 4, 1),
          entries: [
            {
              'date': '2026-04-02',
              'bleeding': 3,
              'custom_marks': jsonEncode({
                'Sport': ['Joggen'],
              }),
            },
          ],
          marks: const [],
        ),
      );

      test(
        'a day with custom marks survives the export → import round trip',
        () async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 4, 2),
              bleeding: Bleeding.medium,
              customMarks: const {
                'Sport': ['Joggen'],
              },
            ),
          );

          final json = await exportDatabaseToJson(db);
          final row = exportedSingleEntryRow(json);
          expect(
            row['custom_marks'],
            {
              'Sport': ['Joggen'],
            },
            reason:
                'the document carries the marks as a nested JSON object, '
                'not the stored column string',
          );

          final target = CycleDatabase(NativeDatabase.memory());
          addTearDown(target.close);
          final summary = await importJsonToDatabase(target, json);
          expect(summary.entriesNew, 1);
          final imported = await target.entriesDao.entryFor(
            DateTime(2026, 4, 2),
          );
          expect(dailyEntryFromDrift(imported!).customMarks, {
            'Sport': ['Joggen'],
          }, reason: 'the marks ride through the document, not just the day');
        },
      );

      test(
        "a document's custom_marks object imports as the day's marks",
        () async {
          final doc = buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 4, 1),
              entries: const [
                {
                  'date': '2026-04-02',
                  'bleeding': 3,
                  'custom_marks': {
                    'Sport': ['Joggen'],
                  },
                },
              ],
              marks: const [],
            ),
          );

          final summary = await importJsonToDatabase(db, doc);
          expect(summary.entriesNew, 1);
          final row = await db.entriesDao.entryFor(DateTime(2026, 4, 2));
          expect(
            dailyEntryFromDrift(row!).customMarks,
            {
              'Sport': ['Joggen'],
            },
            reason: 'the object form is the document shape the reader accepts',
          );
        },
      );

      test(
        "a document's custom_marks JSON string imports as the day's marks",
        () async {
          final summary = await importJsonToDatabase(
            db,
            stringFormMarksDocument(),
          );

          expect(summary.entriesNew, 1);
          final row = await db.entriesDao.entryFor(DateTime(2026, 4, 2));
          expect(
            dailyEntryFromDrift(row!).customMarks,
            {
              'Sport': ['Joggen'],
            },
            reason:
                'a stored-column JSON string carries the same label-keyed '
                'marks as the object form',
          );
        },
      );

      test('a string-form custom_marks imports and re-exports as the '
          'object form', () async {
        await importJsonToDatabase(db, stringFormMarksDocument());

        final row = exportedSingleEntryRow(await exportDatabaseToJson(db));
        expect(
          row['custom_marks'],
          {
            'Sport': ['Joggen'],
          },
          reason:
              'the string form is an input shape only, never an output shape',
        );
      });

      test(
        'a string-form document keeps the ticks of the day it overwrites',
        () async {
          await db.entriesDao.upsertDaily(
            DailyEntry(
              date: DateTime(2026, 4, 2),
              bleeding: Bleeding.medium,
              customMarks: const {
                'Sport': ['Joggen'],
              },
            ),
          );

          final summary = await importJsonToDatabase(
            db,
            stringFormMarksDocument(),
          );
          expect(
            summary.entriesOverwritten,
            1,
            reason: 'the import replaces the stored day',
          );
          final row = await db.entriesDao.entryFor(DateTime(2026, 4, 2));
          expect(dailyEntryFromDrift(row!).customMarks, {
            'Sport': ['Joggen'],
          }, reason: 'a full-replace overwrite must not wipe read ticks');
        },
      );

      test(
        'a corrupt stored custom_marks column exports no custom_marks key',
        () async {
          await db
              .into(db.cycleEntries)
              .insert(
                CycleEntriesCompanion.insert(
                  date: DateTime(2026, 4, 2),
                  bleeding: const Value(Bleeding.medium),
                  customMarks: const Value('not json'),
                ),
              );

          final json = await exportDatabaseToJson(db);
          final row = exportedSingleEntryRow(json);
          expect(
            row['date'],
            '2026-04-02',
            reason: 'the corrupt column never costs the day its export',
          );
          expect(
            row.containsKey('custom_marks'),
            isFalse,
            reason:
                'the corrupt column decodes to no marks a document may '
                'carry, so no key rides',
          );
        },
      );

      test('a day without custom marks exports no custom_marks key', () async {
        await db.entriesDao.upsertDaily(
          DailyEntry(date: DateTime(2026, 4, 3), bleeding: Bleeding.medium),
        );

        final json = await exportDatabaseToJson(db);
        expect(
          json,
          isNot(contains('"custom_marks"')),
          reason: 'the sparse shape omits the key of a marks-free day',
        );
      });

      test('a junk custom_marks value imports leniently, never killing '
          'the row', () async {
        // The accepted shapes are the label-keyed object and its
        // stored-column JSON string; anything else — undecodable text, a
        // JSON string of a non-object, a non-object value, malformed
        // members — is junk.
        final doc = buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 4, 1),
            entries: const [
              {'date': '2026-04-02', 'bleeding': 3, 'custom_marks': 'not json'},
              {
                'date': '2026-04-03',
                'bleeding': 3,
                'custom_marks': ['Joggen'],
              },
              {
                'date': '2026-04-04',
                'bleeding': 3,
                'custom_marks': {'Sport': 42},
              },
              {
                'date': '2026-04-05',
                'bleeding': 3,
                'custom_marks': {
                  'Sport': ['Joggen', 7],
                },
              },
              {
                'date': '2026-04-06',
                'bleeding': 3,
                'custom_marks': '["Joggen"]',
              },
            ],
            marks: const [],
          ),
        );

        final summary = await importJsonToDatabase(db, doc);
        expect(summary.entriesNew, 5);
        for (final day in [
          DateTime(2026, 4, 2),
          DateTime(2026, 4, 3),
          DateTime(2026, 4, 4),
          DateTime(2026, 4, 5),
          DateTime(2026, 4, 6),
        ]) {
          final row = await db.entriesDao.entryFor(day);
          expect(
            dailyEntryFromDrift(row!).customMarks,
            isEmpty,
            reason: 'a junk value decodes to the empty map like the mapper',
          );
        }
      });
    });

    test('unexpected errors surface as ImportFailedException', () async {
      // Nothing half-imported survives a mid-transaction failure: the
      // wrapper turns any engine error into the typed failure the UI can
      // message instead of a raw crash. The engine fails here because the
      // database is closed.
      // The `broken` instance is alive next to the per-test `db` for this
      // one test, so drift's singleton debug warning would print on every
      // run — scope-limited suppression. The flag must be set BEFORE the
      // database is constructed (the warning fires at construction time)
      // and is restored by the harness afterwards.
      final previousWarningFlag =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningFlag,
      );
      final broken = CycleDatabase(NativeDatabase.memory());
      // Ensure the lazy native executor has actually opened before closing —
      // closing a never-opened database is a no-op for drift, and the import
      // below would casually reopen it.
      await broken.entriesDao.allEntries();
      await broken.close();
      await expectLater(
        importJsonToDatabase(broken, buildExportJson(simpleDoc())),
        throwsA(isA<ImportFailedException>()),
      );
    });
  });
}
