// Tests for the JSON export/import domain logic (export document assembly,
// parsing/validation, and the (profile, date) overwrite merge plan).
// Pure Dart — no DB instances, runs on the host VM / CI. The writer-parity
// group additionally pins the row converter of lib/db/export_adapter.dart,
// which is a pure row-map function exercising the domain vocabulary helpers
// (still no database needed).

import 'dart:convert';

import 'package:cycle_app/db/export_adapter.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('export/import JSON codec', () {
    test('buildExportJson assembles the schema-version document', () {
      final json = buildExportJson(ExportBlob(
        profiles: const [
          {'id': 1, 'name': 'main', 'ordinal': 0},
        ],
        entries: const [
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'period'},
        ],
        marks: const [],
        exportedAt: DateTime.utc(2026, 9, 15, 12),
      ));

      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['schema_version'], exportSchemaVersion);
      expect(
          (decoded['exported_at'] as String).startsWith('2026-09-15'), isTrue);
      expect((decoded['profiles'] as List).length, 1);
      expect((decoded['entries'] as List).length, 1);
      expect(decoded['marks'] as List, isEmpty);
    });

    test('parseExportJson round-trips a document it built', () {
      final json = buildExportJson(ExportBlob(
        profiles: const [
          {'id': 2, 'name': 'partner', 'ordinal': 1},
        ],
        entries: const [
          {'profile_id': 2, 'date': '2026-04-10', 'bleeding': 'spotting'},
        ],
        marks: const [
          {
            'profile_id': 2,
            'entry_date': '2026-04-10',
            'mark_type': 'baseline',
            'author': 'user',
          },
        ],
        exportedAt: DateTime.utc(2026, 9, 15, 12),
      ));

      final doc = parseExportJson(json);
      expect(doc.profiles.single['name'], 'partner');
      expect(doc.entries.single['date'], '2026-04-10');
      expect(doc.marks.single['mark_type'], 'baseline');
    });

    test('parseExportJson validates the exported-at timestamp', () {
      expect(
          () => parseExportJson(jsonEncode(<String, Object?>{
                'schema_version': exportSchemaVersion,
                // exported_at is missing entirely
                'profiles': <Object?>[],
                'entries': <Object?>[],
                'marks': <Object?>[],
              })),
          throwsA(isA<FormatException>()));
    });

    test('parseExportJson rejects malformed documents', () {
      expect(() => parseExportJson('not json at all'),
          throwsA(isA<FormatException>()));
      expect(() => parseExportJson(jsonEncode(<String, Object?>{})),
          throwsA(isA<FormatException>()));
      expect(
          () => parseExportJson(jsonEncode(<String, Object?>{
                'schema_version': 99,
                'exported_at': '2026-09-15T00:00:00Z',
                'profiles': <Object?>[],
                'entries': <Object?>[],
                'marks': <Object?>[],
              })),
          throwsA(isA<FormatException>()));
    });

    test('planMerge counts new entries, overwrites and marks correctly', () {
      final doc = ExportBlob(
        profiles: const [
          {'id': 1, 'name': 'main', 'ordinal': 0},
        ],
        entries: const <Map<String, Object?>>[
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'period'},
          {'profile_id': 1, 'date': '2026-03-02', 'bleeding': 'none'},
          // overwrites the existing day (merge policy: overwrite)
          {'profile_id': 1, 'date': '2026-03-05', 'bleeding': 'spotting'},
        ],
        marks: const <Map<String, Object?>>[
          {
            'profile_id': 1,
            'entry_date': '2026-03-03',
            'mark_type': 'baseline',
            'author': 'user',
          },
          {
            'profile_id': 1,
            'entry_date': '2026-03-04',
            'mark_type': 'baseline',
            'author': 'user',
          },
        ],
        exportedAt: DateTime.utc(2026, 9, 15),
      );

      final summary = planMerge(
        doc,
        existingEntryKeys: {importEntryKey(1, '2026-03-05')},
        existingMarkKeys: {importMarkKey(1, '2026-03-03', 'baseline')},
        existingProfileIds: const {1},
      );

      expect(summary.profilesToInsert, 0, reason: 'profile 1 does exist');
      expect(summary.duplicateEntryRows, 0, reason: 'no date repeated in doc');
      expect(summary.entriesNew, 2, reason: '03-01, 03-02');
      expect(summary.entriesOverwritten, 1, reason: '03-05 exists');
      expect(summary.marksNew, 1, reason: '03-04 only; 03-03 exists');
      expect(summary.marksSkipped, 1);
    });

    test('unparsable bleeding values are counted invalid, never as writes', () {
      final doc = ExportBlob(
        profiles: const [],
        entries: const <Map<String, Object?>>[
          // Unknown vocabulary — the db writer drops this row.
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'heavy'},
          // Missing entirely — the writer cannot produce an enum either.
          {'profile_id': 1, 'date': '2026-03-02'},
          {'profile_id': 1, 'date': '2026-03-03', 'bleeding': 'none'},
        ],
        marks: const [],
        exportedAt: DateTime.utc(2026, 9, 15),
      );

      final summary = planMerge(
        doc,
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );

      // The plan counts EXACTLY what the writer will write: the two
      // unparsable rows land in the invalid bucket, only the valid one is
      // counted as new.
      expect(summary.entriesInvalid, 2);
      expect(summary.entriesNew, 1);
      expect(summary.entriesOverwritten, 0);
      expect(summary.entriesWritten, 1);
    });

    test('repeated (profile, date) rows inside one document are reported', () {
      final doc = ExportBlob(
        profiles: const [],
        entries: const <Map<String, Object?>>[
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'period'},
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'none'},
        ],
        marks: const [],
        exportedAt: DateTime.utc(2026, 9, 15),
      );

      final summary = planMerge(
        doc,
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.duplicateEntryRows, 1);
      // The first occurrence wins; the later one is the counted duplicate.
      expect(summary.entriesNew, 1);
    });

    test('numeric-string profile ids plan the same as int ids', () {
      final doc = ExportBlob(
        profiles: const [
          {'id': '5', 'name': 'from-another-tool', 'ordinal': 0},
        ],
        entries: const <Map<String, Object?>>[
          {'profile_id': '5', 'date': '2026-03-01', 'bleeding': 'period'},
          // Same id, boxed differently: must count as a duplicate key.
          {'profile_id': 5, 'date': '2026-03-01', 'bleeding': 'none'},
        ],
        marks: const <Map<String, Object?>>[
          {
            'profile_id': '5',
            'entry_date': '2026-03-02',
            'mark_type': 'baseline',
            'author': 'user',
          },
        ],
        exportedAt: DateTime.utc(2026, 9, 15),
      );

      final summary = planMerge(
        doc,
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {},
      );

      // The writer re-creates the profile for these rows, so the plan must
      // count it, and one written row must exist per counted row.
      expect(summary.profilesToInsert, 1);
      expect(summary.entriesNew, 1, reason: 'the second row is a duplicate');
      expect(summary.duplicateEntryRows, 1);
      expect(summary.marksNew, 1);
    });

    test('entry/mark key helpers are stable and unambiguous', () {
      expect(importEntryKey(1, '2026-03-05'), contains('|2026-03-05'));
      expect(importEntryKey(12, '2026-03-05'),
          isNot(importEntryKey(1, '2026-03-05'.padLeft(10, '1'))));
      expect(importMarkKey(1, '2026-03-05', 'baseline'),
          isNot(importMarkKey(1, '2026-03-05', 'mucusPeakDay')));
    });

    test('merge policy constant documents the overwrite behaviour', () {
      expect(exportMergePolicy, 'overwrite');
    });

    test('documents of every published schema version parse', () {
      ExportBlob blobFor(int version) => parseExportJson(jsonEncode(
            <String, Object?>{
              'schema_version': version,
              'exported_at': '2026-09-15T12:00:00Z',
              'profiles': <Object?>[],
              'entries': <Object?>[],
              'marks': <Object?>[],
            },
          ));

      // Old exports live on as real files on user devices, so every shape
      // ever published stays importable until an explicit retirement rule
      // says otherwise; anything AFTER the current version stays rejected.
      expect(blobFor(1).exportedAt, DateTime.utc(2026, 9, 15, 12),
          reason: 'documents from before the measured-time field import');
      expect(blobFor(2).exportedAt, DateTime.utc(2026, 9, 15, 12),
          reason: 'documents from the measured-time release');
      expect(blobFor(3).exportedAt, DateTime.utc(2026, 9, 15, 12),
          reason: 'documents since bleeding became a numeric level');
      expect(blobFor(4).exportedAt, DateTime.utc(2026, 9, 15, 12),
          reason: 'documents since the pain options replaced the '
              'generic pain flag');
      expect(
          () => parseExportJson('{"schema_version": 5, "exported_at": '
              '"2026-09-15T12:00:00Z"}'),
          throwsA(isA<FormatException>()));
    });
  });

  group('tryParseBleeding: dual-format bleeding parser', () {
    test('int 0-4 map to the five levels by their stored level', () {
      // Mapped BY the numeric level, never by declaration index: the
      // name/number pairs below hold even if the enum is ever re-declared
      // in a different member order.
      expect(tryParseBleeding(0)?.name, 'none');
      expect(tryParseBleeding(1)?.name, 'spotting');
      expect(tryParseBleeding(2)?.name, 'light');
      expect(tryParseBleeding(3)?.name, 'medium');
      expect(tryParseBleeding(4)?.name, 'heavy');
    });

    test('values outside the accepted shapes are invalid', () {
      const invalid = <Object?>[
        null, // missing field
        true, // bool sneaks through as int in JS-land, not here
        false,
        -1, // below the scale
        5, // above the scale
        '2', // numeric STRING is not a level
        'light', // NEW names are not valid string tokens (only legacy ones)
        'medium',
        'heavy',
        '', // empty token
        'monsoon', // out-of-vocabulary token
        36.6, // double
        <String, Object?>{}, // nested junk never parses
      ];
      for (final bad in invalid) {
        expect(tryParseBleeding(bad), isNull, reason: '$bad must be invalid');
      }
    });

    test('legacy v1 tokens survive with period pinned to medium', () {
      // The v1 export vocabulary stored generic menstruation without
      // heaviness; `period` degrades to the central menstruation level
      // (medium) on import. TODO(user-review): experts re-check the default.
      expect(tryParseBleeding('period')?.name, 'medium');
      expect(tryParseBleeding('none')?.name, 'none');
      expect(tryParseBleeding('spotting')?.name, 'spotting');
    });
  });

  group('mucus tokens ride along as coercible fields', () {
    ExportBlob docWithMucus(Map<String, Object?> mucusFields) => ExportBlob(
          profiles: const [],
          entries: [
            {
              'profile_id': 1,
              'date': '2026-03-01',
              'bleeding': 'period',
              ...mucusFields,
            },
          ],
          marks: const [],
          exportedAt: DateTime.utc(2026, 9, 15),
        );

    test('planner: out-of-vocabulary mucus tokens never invalidate a row', () {
      final summary = planMerge(
        docWithMucus(const {'mucus_sign': 'zzz', 'mucus_quality': 'qqq'}),
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.entriesInvalid, 0,
          reason: 'mucus content is coerced, not gated');
      expect(summary.entriesWritten, 1,
          reason: 'mucus never drops an otherwise valid row');
    });

    test('writer: out-of-vocabulary mucus tokens are nulled, row is kept', () {
      final entry = tryDailyEntryFromExport(<String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'mucus_sign': 'zzz',
        'mucus_quality': 'qqq',
      });
      expect(entry, isNotNull,
          reason: 'the plan counted this row, so it must be written');
      expect(entry!.mucusSign, isNull);
      expect(entry.mucusQuality, isNull);
    });

    test('writer: quality without an S sign is kept as a row, quality null',
        () {
      final entry = tryDailyEntryFromExport(<String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'mucus_sign': 'f',
        'mucus_quality': 'w',
      });
      expect(entry, isNotNull, reason: 'planner/writer parity: not a drop');
      expect(entry!.mucusSign, MucusSign.f);
      expect(entry.mucusQuality, isNull,
          reason: 'only an S sign may carry a quality');
    });

    test('writer: an S sign with a quality token survives verbatim', () {
      final entry = tryDailyEntryFromExport(<String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'mucus_sign': 's',
        'mucus_quality': 'ew',
      });
      expect(entry!.mucusSign, MucusSign.s);
      expect(entry.mucusQuality, MucusQuality.ew);
    });
  });

  group('measured time-of-day rides along as a coercible field', () {
    test('the vocabulary helper accepts exactly the valid minute range', () {
      expect(tryParseMeasuredAtMinutes(0), 0);
      expect(tryParseMeasuredAtMinutes(1439), 1439);
      expect(tryParseMeasuredAtMinutes(405), 405);

      // Null is "not recorded", never invalid; numeric strings survive the
      // same lossy-export tolerance as ids; anything else is not a time.
      expect(tryParseMeasuredAtMinutes(null), isNull);
      expect(tryParseMeasuredAtMinutes('405'), 405);
      expect(tryParseMeasuredAtMinutes('06:45'), isNull);
      expect(tryParseMeasuredAtMinutes(1439 + 1), isNull);
      expect(tryParseMeasuredAtMinutes(-1), isNull);
      expect(tryParseMeasuredAtMinutes(36.5), isNull);
      expect(tryParseMeasuredAtMinutes(true), isNull);
    });

    test('planner gates unchanged: the minutes field never invalidates a row',
        () {
      final summary = planMerge(
        ExportBlob(
          profiles: const [],
          entries: const <Map<String, Object?>>[
            {
              'profile_id': 1,
              'date': '2026-03-01',
              'bleeding': 'period',
              'measured_at_minutes': 9999,
            },
          ],
          marks: const [],
          exportedAt: DateTime.utc(2026, 9, 15),
        ),
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.entriesInvalid, 0,
          reason: 'a broken time is coerced, not gated');
      expect(summary.entriesWritten, 1);
    });

    test('writer: a measured document carries the stored minutes over', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bbt_c': 36.4,
        'bleeding': 'period',
        'measured_at_minutes': 405,
      });
      expect(entry!.measuredAtMinutes, 405);
    });

    test('writer: a time without a temperature is not imported', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'measured_at_minutes': 405,
      });
      expect(entry, isNotNull,
          reason: 'the time is a field, never a row killer');
      expect(entry!.measuredAtMinutes, isNull,
          reason: 'the app never stores a measurement time without the '
              'temperature it belongs to; foreign/legacy documents with a '
              'stray time normalize on import');
    });

    test('writer: out-of-range minutes collapse to null, row is kept', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'measured_at_minutes': 9999,
      });
      expect(entry, isNotNull,
          reason: 'the plan counted this row, so it must be written');
      expect(entry!.measuredAtMinutes, isNull);
    });

    test('writer: document rows without the field import with no time', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
      });
      expect(entry!.measuredAtMinutes, isNull,
          reason: 'older exports omit the field; that is null, not "now"');
    });
  });

  group('pain options (breast B, Mittelschmerz M) in the writer', () {
    test('writer: the letter-coded pain options map to the domain flags', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'period',
        'pain_breast': true,
      });
      expect(entry!.painBreast, isTrue);
      expect(entry.painMittelschmerz, isFalse);

      final other = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-02',
        'bleeding': 'none',
        'pain_mittelschmerz': true,
      });
      expect(other!.painBreast, isFalse);
      expect(other.painMittelschmerz, isTrue);
    });

    test('writer: rows without pain keys parse with both options unset', () {
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'none',
      });
      expect(entry!.painBreast, isFalse);
      expect(entry.painMittelschmerz, isFalse);
    });

    test('writer: the legacy generic pain flag is tolerated and dropped', () {
      // ≤v3 documents carry a generic `pain: true` with no B/M identity.
      // The day row itself stays a valid write (like every coercible
      // field), only the flag information is not carried over — the
      // merge policy overwrites such a day with the rest of its fields.
      final entry = tryDailyEntryFromExport(const <String, Object?>{
        'profile_id': 1,
        'date': '2026-03-01',
        'bleeding': 'none',
        'pain': true,
      });
      expect(entry, isNotNull,
          reason: 'a legacy pain flag must not invalidate the row');
      expect(entry!.painBreast, isFalse,
          reason: 'the generic flag has no breast-pain identity');
      expect(entry.painMittelschmerz, isFalse,
          reason: 'the generic flag has no Mittelschmerz identity');
    });

    test('planner: legacy pain/unknown pain keys never invalidate a row', () {
      final summary = planMerge(
        ExportBlob(
          profiles: const [],
          entries: const <Map<String, Object?>>[
            {
              'profile_id': 1,
              'date': '2026-03-01',
              'bleeding': 'none',
              'pain': true,
              'pain_breast': true,
            },
          ],
          marks: const [],
          exportedAt: DateTime.utc(2026, 9, 15),
        ),
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.entriesInvalid, 0,
          reason: 'boolean pain fields are coercible, never row killers');
      expect(summary.entriesWritten, 1);
    });
  });

  group('sex timings / cervix firmness / mucus A in the reader (import side)',
      () {
    Map<String, Object?> rowWith(Map<String, Object?> fields) =>
        <String, Object?>{
          'profile_id': 1,
          'date': '2026-03-01',
          'bleeding': 'none',
          ...fields,
        };

    test('reader: the sex_timings mask carries over verbatim within 0..7',
        () {
      for (final mask in [0, 1, 2, 4, 5, 7]) {
        final entry = tryDailyEntryFromExport(rowWith({'sex_timings': mask}));
        expect(entry, isNotNull, reason: 'mask $mask must never kill the row');
        expect(entry!.sexTimings, mask, reason: 'mask $mask');
      }
    });

    test('reader: out-of-range / negative / missing sex_timings collapse to 0',
        () {
      for (final bad in <Object?>[8, -1, 999, '3', null]) {
        final entry = tryDailyEntryFromExport(rowWith({'sex_timings': bad}));
        expect(entry, isNotNull,
            reason: 'a broken mask ($bad) is coerced, not a row killer');
        expect(entry!.sexTimings, 0, reason: 'bad mask $bad collapses to 0');
      }
    });

    test('reader: the old boolean `sex` flag is gone from the shape', () {
      // v4 was redefined in place pre-release (no published v4 documents
      // exist): `sex_timings` REPLACES `sex`. A row still carrying the old
      // flag loses it silently — no shim, the row stays valid.
      final entry = tryDailyEntryFromExport(rowWith({'sex': true}));
      expect(entry, isNotNull);
      expect(entry!.sexTimings, 0,
          reason: 'the legacy flag has no mask identity');
    });

    test('reader: cervix_firmness tokens parse into the structured field',
        () {
      final cases = <String, CervixFirmness>{
        'hard': CervixFirmness.hard,
        'halfSoft': CervixFirmness.halfSoft,
        'soft': CervixFirmness.soft,
      };
      cases.forEach((token, expected) {
        final entry = tryDailyEntryFromExport(rowWith({
          'cervix_firmness': token,
        }));
        expect(entry!.cervixFirmness, expected, reason: 'token "$token"');
      });
      final clean = tryDailyEntryFromExport(rowWith({}));
      expect(clean!.cervixFirmness, isNull,
          reason: 'older documents simply omit the field');
    });

    test('reader: an out-of-vocabulary firmness token collapses to null', () {
      final entry = tryDailyEntryFromExport(rowWith({
        'cervix_firmness': 'zzz',
      }));
      expect(entry, isNotNull,
          reason: 'coercible fields never drop an otherwise valid row');
      expect(entry!.cervixFirmness, isNull);
    });

    test('planner: sex_timings / cervix_firmness never invalidate a row', () {
      final summary = planMerge(
        ExportBlob(
          profiles: const [],
          entries: [
            rowWith({'sex_timings': 8, 'cervix_firmness': 'zzz'}),
          ],
          marks: const [],
          exportedAt: DateTime.utc(2026, 9, 15),
        ),
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.entriesInvalid, 0,
          reason: 'both fields are coercible, never gated');
      expect(summary.entriesWritten, 1);
    });

    test('reader: the mucus token a flows through to the A sign', () {
      final entry = tryDailyEntryFromExport(rowWith({'mucus_sign': 'a'}));
      expect(entry!.mucusSign, MucusSign.a);
      expect(entry.mucusQuality, isNull, reason: 'A carries no quality');
    });

    test('round trip: a full document keeps the new fields', () {
      final json = buildExportJson(ExportBlob(
        profiles: const [
          {'id': 1, 'name': 'main', 'ordinal': 0},
        ],
        entries: [
          {
            'profile_id': 1,
            'date': '2026-03-01',
            'bleeding': 'none',
            'sex_timings': 3,
            'cervix_firmness': 'halfSoft',
            'mucus_sign': 'a',
          },
        ],
        marks: const [],
        exportedAt: DateTime.utc(2026, 9, 15, 12),
      ));

      final doc = parseExportJson(json);
      final entry = tryDailyEntryFromExport(doc.entries.single)!;
      expect(entry.sexTimings, 3);
      expect(entry.cervixFirmness, CervixFirmness.halfSoft);
      expect(entry.mucusSign, MucusSign.a);
    });
  });

  group('bleeding levels in the export version boundary', () {
    test('the writer emits the schema version with the pain options', () {
      expect(exportSchemaVersion, 4,
          reason: 'v3 was the numeric-bleeding release; v4 replaces the '
              'generic `pain` flag with the pain_breast / pain_mittelschmerz '
              'options (B/M) and — redefined in place pre-release — the '
              'boolean `sex` flag with the `sex_timings` mask plus the '
              'additive `cervix_firmness` field');
    });

    test('documents with numeric bleeding build, parse and round-trip', () {
      final json = buildExportJson(ExportBlob(
        profiles: const [
          {'id': 1, 'name': 'main', 'ordinal': 0},
        ],
        entries: const <Map<String, Object?>>[
          {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 4},
          {'profile_id': 1, 'date': '2026-03-02', 'bleeding': 0},
        ],
        marks: const [],
        exportedAt: DateTime.utc(2026, 9, 15, 12),
      ));

      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['schema_version'], exportSchemaVersion,
          reason: 'the writer stamps the current version');

      final doc = parseExportJson(json);
      final summary = planMerge(
        doc,
        existingEntryKeys: {},
        existingMarkKeys: {},
        existingProfileIds: const {1},
      );
      expect(summary.entriesInvalid, 0,
          reason: 'numeric levels in range are valid vocabulary');
      expect(summary.entriesWritten, 2);
      expect(tryDailyEntryFromExport(doc.entries.first)!.bleeding,
          Bleeding.heavy);
      expect(tryDailyEntryFromExport(doc.entries.last)!.bleeding,
          Bleeding.none);
    });

    test('a hand-written v3 document parses with its numeric bleeding', () {
      // Raw JSON on purpose: pins the published document shape itself.
      const v3Json = '{"schema_version": 3, '
          '"exported_at": "2026-09-15T12:00:00Z", '
          '"profiles": [], '
          '"entries": [{"profile_id": 1, "date": "2026-03-01", '
          '"bleeding": 2}], '
          '"marks": []}';
      final doc = parseExportJson(v3Json);
      expect(tryDailyEntryFromExport(doc.entries.single)!.bleeding,
          Bleeding.light);
    });

    test('legacy v1 AND v2 documents carry string tokens that still plan '
        'and count correctly', () {
      // v2 documents exported by dev builds between the measured-time
      // release and the bleeding levels carry STRING bleeding — treating
      // v2 as numeric would misparse them, so both legacy versions stay
      // token-shaped.
      Iterable<Map<String, Object?>> tokenDoc(int version) sync* {
        yield {
          'schema_version': version,
          'exported_at': '2026-09-15T12:00:00Z',
          'profiles': <Object?>[],
          'entries': <Object?>[
            {'profile_id': 1, 'date': '2026-03-01', 'bleeding': 'period'},
            {'profile_id': 1, 'date': '2026-03-02', 'bleeding': 'spotting'},
            {'profile_id': 1, 'date': '2026-03-03', 'bleeding': 'none'},
            {'profile_id': 1, 'date': '2026-03-04', 'bleeding': 'heavy'},
          ],
          'marks': <Object?>[],
        };
      }

      for (final version in const [1, 2]) {
        final doc =
            parseExportJson(jsonEncode(tokenDoc(version).single));
        final summary = planMerge(
          doc,
          existingEntryKeys: {},
          existingMarkKeys: {},
          existingProfileIds: const {1},
        );
        expect(summary.entriesInvalid, 1,
            reason: 'v$version: the unknown token counts as invalid');
        expect(summary.entriesWritten, 3,
            reason: 'v$version: the three legacy tokens are valid writes');

        final periodDay = tryDailyEntryFromExport(doc.entries[0])!;
        expect(periodDay.bleeding, Bleeding.medium,
            reason: 'v$version: period degrades to medium');
        expect(tryDailyEntryFromExport(doc.entries[1])!.bleeding,
            Bleeding.spotting, reason: 'v$version: spotting stays spotting');
        expect(tryDailyEntryFromExport(doc.entries[2])!.bleeding,
            Bleeding.none, reason: 'v$version: none stays none');
      }
    });
  });
}
