// Canary over the shipped examples/ samples: the files a user loads into the
// app or the web demo must parse with the CURRENT readers and sit at the
// current schema version, so a brokenly edited or outdated sample fails the
// suite instead of surprising an importer. Detailed import behavior is
// covered in the export/import and drip suites — only sample health here.
// Pure Dart — no DB instances, host VM / CI.

import 'dart:convert';
import 'dart:io';

import 'package:cycle_app/domain/drip_import.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final exampleCycleRaw = File(
    'examples/example-cycle.json',
  ).readAsStringSync();
  final pregnancyRaw = File(
    'examples/pregnancy-cycles.json',
  ).readAsStringSync();

  group('examples: JSON export format', () {
    test('both samples parse at the current schema version', () {
      for (final raw in [exampleCycleRaw, pregnancyRaw]) {
        final root = jsonDecode(raw) as Map<String, Object?>;
        expect(root['schema_version'], exportSchemaVersion);
        parseExportJson(raw);
      }
    });

    test('entry and cycleStart counts are the documented ones', () {
      final example = parseExportJson(exampleCycleRaw);
      final pregnancy = parseExportJson(pregnancyRaw);

      // One complete cycle of diary days.
      expect(example.entries, hasLength(27));
      int startsOf(ExportBlob blob) =>
          blob.marks.where((m) => m['mark_type'] == 'cycleStart').length;
      expect(startsOf(example), 2);

      // The pregnancy series: 3 cycleStart marks for the anovulatory gap
      // and the postpartum return.
      expect(pregnancy.entries, hasLength(159));
      expect(startsOf(pregnancy), 3);
    });
  });

  group('examples: drip CSV format', () {
    test('both samples map cleanly with nothing dropped', () {
      for (final path in [
        'examples/example-cycle-drip-format.csv',
        'examples/drip-export-sample.csv',
      ]) {
        final csv = File(path).readAsStringSync();
        final result = dripCsvToExportJson(csv);
        final entries = (jsonDecode(result.json) as Map)['entries']! as List;
        expect(entries, hasLength(27), reason: path);
        // Broken rows land in the invalid bucket and are silently absent
        // from the mapped document — a shipped sample must never trip it.
        expect(result.stats.rowsInvalid, 0, reason: path);
      }
    });
  });
}
