// Tests for the drip CSV import domain logic: the RFC-4180-style CSV
// tokenizer ("csv parsing") and the drip → export-document field mapping
// ("drip mapping"). Pure Dart — no DB instances, host VM / CI.
//
// The tokenizer spec is drip's own writer (lib/import-export/export-to-csv.js
// in the drip project): string cells containing \n \t , ; . ' are wrapped in
// double quotes with inner quotes escaped as "", and the file uses plain
// newlines that may arrive as \r\n from spreadsheet round-trips.
//
// The committed fixture test/fixtures/drip-export-sample.csv is a copy of
// drip's own export specimen; tests assert VALUES, never byte equality.
//
// The mapping tests replicate drip's observation vocabularies (0-based,
// drip: components/helpers/labels.js) and drip's own getNfpMucus numerics
// (its test/nfp-mucus.spec.js), then pin how each maps onto the cycle-app
// export document (current schema version, mucus as sign/quality tokens).

import 'dart:convert';
import 'dart:io' show File;

import 'package:cycle_app/domain/drip_import.dart';
import 'package:cycle_app/domain/export_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// The committed drip export specimen, read straight from disk (working dir
/// is the repo root when the host test runner starts).
final String dripExportSampleCsv =
    File('test/fixtures/drip-export-sample.csv').readAsStringSync();

/// A minimal, realistic drip CSV column set (header order as drip writes
/// it, columns irrelevant to the mapping under test may be omitted — the
/// parser must be header-driven).
const List<String> dripHeader = [
  'date',
  'temperature.value',
  'temperature.exclude',
  'temperature.note',
  'bleeding.value',
  'mucus.feeling',
  'mucus.texture',
  'mucus.value',
  'cervix.opening',
  'cervix.firmness',
  'cervix.position',
  'note.value',
  'desire.value',
  'sex.solo',
  'sex.partner',
  'sex.condom',
  'sex.note',
  'pain.cramps',
  'pain.note',
  'mood.sad',
  'mood.note',
];

/// The full drip pain-column family (drip writes every symptom as
/// `<symptom>.<kind>` booleans plus an (optional) note). Used to pin the
/// B/M pain-kind mapping separately from the shared minimal header above.
const List<String> painHeader = [
  'date',
  'pain.cramps',
  'pain.ovulationPain',
  'pain.tenderBreasts',
  'pain.headache',
  'pain.note',
];

/// The full drip sex-column family in drip's own column order (drip:
/// labels.js — activity solo/partner, contraceptives condom/pill/iud/patch/
/// ring/implant/diaphragm/none/other, then the note). Used to pin the sex
/// observation rule ("only with a partner, without contraception")
/// separately from the shared minimal header above.
const List<String> sexHeader = [
  'date',
  'sex.solo',
  'sex.partner',
  'sex.condom',
  'sex.pill',
  'sex.iud',
  'sex.patch',
  'sex.ring',
  'sex.implant',
  'sex.diaphragm',
  'sex.none',
  'sex.other',
  'sex.note',
];

/// Builds a drip CSV: [header] plus one data [row] joined the way drip
/// writes its files (plain comma join, plain newlines).
String dripOneRowCsv(List<String> header, List<String> row) =>
    dripCsv(header, [row]);

/// Same for several data rows at once.
String dripCsv(List<String> header, List<List<String>> rows) =>
    [header.join(','), ...rows.map((r) => r.join(','))].join('\n');

/// Runs one data row ([cells] aligned to [header]) through the importer and
/// returns the single produced entry row map of the document.
Map<String, Object?> entryOf(
  List<String> cells, {
  List<String> header = dripHeader,
}) {
  final result = dripCsvToExportJson(dripOneRowCsv(header, cells));
  final doc = jsonDecode(result.json) as Map<String, Object?>;
  final entries = doc['entries']! as List;
  expect(entries, hasLength(1),
      reason: 'this row must map to exactly one entry');
  return entries.single as Map<String, Object?>;
}

void main() {
  group('csv parsing', () {
    test('plain rows split on commas, header preserved', () {
      final rows = splitDripCsv('date,temperature.value\n2026-07-05,36.2');
      expect(rows, [
        ['date', 'temperature.value'],
        ['2026-07-05', '36.2'],
      ]);
    });

    test('quoted field keeps comma, period and escaped quotes verbatim', () {
      final rows = splitDripCsv(
          'date,note.value\n2026-01-01,"has, comma. period and ""quotes"""');
      expect(rows[1], [
        '2026-01-01',
        'has, comma. period and "quotes"',
      ]);
    });

    test('quoted field may span multiple lines (multi-line note)', () {
      final rows = splitDripCsv(
          'date,note.value\n2026-01-01,"line one\nline two"\n2026-01-02,');
      expect(rows, [
        ['date', 'note.value'],
        ['2026-01-01', 'line one\nline two'],
        ['2026-01-02', ''],
      ]);
    });

    test('tolerates \r\n line endings', () {
      final rows = splitDripCsv('date,note.value\r\n2026-01-01,x\r\n');
      expect(rows, [
        ['date', 'note.value'],
        ['2026-01-01', 'x'],
      ]);
    });

    test('a trailing empty line does not produce an extra empty row', () {
      expect(splitDripCsv('a,b\nc,d\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(splitDripCsv('a,b\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('the drip export fixture tokenizes into uniform rows', () {
      final raw = dripExportSampleCsv;
      final rows = splitDripCsv(raw);
      expect(rows.first.first, 'date');
      expect(rows.first[5], 'bleeding.value');
      expect(rows.first.last, 'mood.note');
      expect(rows[1][0], '2026-07-05');
      expect(rows[1][1], '36.2');
      // Real quoted cells survive: the fixture's [sex]-note line contains a
      // comma and a period, so drip wrapped it in quotes.
      final quoted = rows
          .where((r) => r.first == '2026-07-17')
          .map((r) => r[28])
          .single;
      expect(quoted, 'with condom, quite good');
    });

    test('header without a date column is rejected as a format error', () {
      expect(() => parseDripCsv('note.value,desire.value\nhello,3'),
          throwsA(isA<FormatException>()));
      expect(() => parseDripCsv(''), throwsA(isA<FormatException>()));
    });
  });

  group('drip → domain mapping', () {
    /// Data row cells aligned to [dripHeader]; the 0th cell is always the
    /// date, everything not mentioned stays an empty cell.
    List<String> cells(String date, Map<int, String> byIndex) {
      final c = List.filled(dripHeader.length, '');
      c[0] = date;
      byIndex.forEach((i, v) => c[i] = v);
      return c;
    }

    test('vocabulary: drip scale 0–3 → the +1-shifted numeric levels, '
        'empty → 0 (none)', () {
      // drip: 0=spotting, 1=light, 2=medium, 3=heavy; the export document
      // carries the stored numeric levels (drip scale shifted by +1, so an
      // explicit none=0 exists).
      expect(entryOf(cells('2026-01-01', {4: '0'}))['bleeding'], 1);
      expect(entryOf(cells('2026-01-01', {4: '1'}))['bleeding'], 2);
      expect(entryOf(cells('2026-01-01', {4: '2'}))['bleeding'], 3);
      expect(entryOf(cells('2026-01-01', {4: '3'}))['bleeding'], 4);
      // No bleeding observation at all — the day still imports when other
      // fields carry data (bleeding takes the neutral level 0 = none).
      expect(entryOf(cells('2026-01-01', {1: '36.2'}))['bleeding'], 0);
      // Out-of-range index: treated as no observation.
      expect(entryOf(cells('2026-01-01', {4: '7', 1: '36.2'}))['bleeding'], 0);
      // The entry map carries NUMBERS, never string tokens.
      expect(entryOf(cells('2026-01-01', {4: '3'}))['bleeding'], isA<int>());
    });

    test('temperature: value parses, exclude → exclude_other, note rides', () {
      final e = entryOf(
          cells('2026-01-01', {1: '36.2', 2: 'true', 3: 'measured late'}));
      expect(e['bbt_c'], 36.2);
      expect(e['exclude_other'], true);
      expect(e['notes'], '[temp] measured late');
    });

    test('temperature.exclude=false (or empty) is not an exclusion', () {
      expect(
          entryOf(cells('2026-01-01', {1: '36.5', 2: 'false'}))['exclude_other'],
          false);
      expect(entryOf(cells('2026-01-01', {1: '36.5'}))['exclude_other'], false);
    });

    test('mucus: drip nfp number 0..4 decodes onto sign/quality tokens', () {
      // drip: 0=t, 1=Ø, 2=f, 3=S (bare), 4=S+ ≙ S with the sheet's best
      // quality ew. The underlying feeling/texture of a bare S is not
      // recoverable from the number.
      final cases = <String, (String?, String?)>{
        '0': ('t', null),
        '1': ('nothing', null),
        '2': ('f', null),
        '3': ('s', null),
        '4': ('s', 'ew'),
      };
      cases.forEach((dripNfp, expected) {
        final e = entryOf(cells('2026-01-01', {7: dripNfp}));
        expect(e['mucus_sign'], expected.$1,
            reason: 'nfp $dripNfp → sign ${expected.$1}');
        expect(e['mucus_quality'], expected.$2,
            reason: 'nfp $dripNfp → quality ${expected.$2}');
      });
      // Out of the 0..4 scale: no mucus at all.
      final odd = entryOf(cells('2026-01-01', {7: '5', 4: '2'}));
      expect(odd['mucus_sign'], isNull);
      expect(odd['mucus_quality'], isNull);
    });

    test('mucus: quality only rides an S sign (collapse rule)', () {
      // Defensive: the decode itself never produces this combination, but
      // the pipeline through tryParse/sanitize must still collapse it.
      final e = entryOf(cells('2026-01-01', {7: '2', 4: '2'}));
      expect(e['mucus_sign'], 'f');
      expect(e['mucus_quality'], isNull);
    });

    test('mucus: feeling+texture composite ports drip getNfpMucus exactly',
        () {
      // Transcribed from drip's test/nfp-mucus.spec.js:
      // (feeling, texture) → nfp number via max(mapping); the number then
      // decodes exactly like the mucus.value row.
      const spec = <(int, int, int)>[
        (0, 0, 0), // dry + nothing → t
        (1, 0, 1), // nothing + nothing → Ø
        (2, 0, 2), // wet + nothing → f
        (0, 1, 3), // dry + creamy → S
        (1, 1, 3),
        (2, 1, 3),
        (0, 2, 4), // dry + eggWhite → S+
        (1, 2, 4),
        (2, 2, 4),
        (3, 2, 4), // slippery + eggWhite → S+
        (3, 1, 4), // slippery + creamy → S+
        (3, 0, 4), // slippery alone → S+
      ];
      for (final (feeling, texture, nfp) in spec) {
        final expected = switch (nfp) {
          0 => ('t', null),
          1 => ('nothing', null),
          2 => ('f', null),
          3 => ('s', null),
          _ => ('s', 'ew'),
        };
        final e = entryOf(cells('2026-01-01', {5: '$feeling', 6: '$texture'}));
        expect(e['mucus_sign'], expected.$1,
            reason: 'feeling $feeling + texture $texture → nfp $nfp');
        expect(e['mucus_quality'], expected.$2, reason: 'nfp $nfp');
      }
    });

    test('mucus: a composite needs BOTH parts (null when either missing)', () {
      expect(
          entryOf(cells('2026-01-01', {5: '2', 4: '2'}))['mucus_sign'],
          isNull,
          reason: 'a feeling without a texture carries no mucus');
      expect(
          entryOf(cells('2026-01-01', {6: '2', 4: '2'}))['mucus_sign'],
          isNull,
          reason: 'a texture without a feeling carries no mucus');
    });

    test('mucus: out-of-range feeling/texture codes carry no mucus', () {
      final e = entryOf(cells('2026-01-01', {5: '4', 6: '2', 4: '2'}));
      expect(e['mucus_sign'], isNull);
      expect(e['mucus_quality'], isNull);
    });

    test('mucus: mucus.value wins when it is present next to its parts', () {
      // value 3 (bare S) beats what the composite of 2+2 would give (S+).
      final e = entryOf(cells('2026-01-01', {5: '2', 6: '2', 7: '3'}));
      expect(e['mucus_sign'], 's');
      expect(e['mucus_quality'], isNull);
    });

    test('cervix: english words, opening/firmness/position order, clamp', () {
      expect(
          entryOf(
              cells('2026-01-01', {8: '1', 9: '1', 10: '1'}))['cervix'],
          'medium, soft, medium');
      expect(
          entryOf(
              cells('2026-01-01', {8: '2', 9: '0', 10: '0'}))['cervix'],
          'open, hard, low');
      // the specimen's firmness index 2 is out of range → clamps to soft
      expect(
          entryOf(
              cells('2026-01-01', {8: '1', 9: '2', 10: '1'}))['cervix'],
          'medium, soft, medium');
      // partial observations still map
      expect(entryOf(cells('2026-01-01', {8: '0'}))['cervix'], 'closed');
      expect(entryOf(cells('2026-01-01', {10: '2'}))['cervix'], 'high');
      // a fully empty triple → no cervix field
      expect(entryOf(cells('2026-01-01', {4: '2'}))['cervix'], isNull);
    });

    test('desire: intensity values 0/1/2 count, literal false does not', () {
      // drip's desire vocabulary is 0=low/1=medium/2=high — not a boolean;
      // any present value means "desire happened", intensity is lost.
      expect(entryOf(cells('2026-01-01', {12: '0'}))['desire'], true);
      expect(entryOf(cells('2026-01-01', {12: '1'}))['desire'], true);
      expect(entryOf(cells('2026-01-01', {12: '2'}))['desire'], true);
      // A hypothetically rendered literal `false` is NOT data and NOT
      // desire — same treatment as an empty cell. Trimmed, since drip
      // lowercases but a spreadsheet round-trip may add padding.
      expect(entryOf(cells('2026-01-01', {12: 'false', 4: '2'}))['desire'],
          isFalse, reason: 'false is ignored for the flag');
      expect(
          entryOf(cells('2026-01-01', {12: ' false ', 1: '36.2'}))['desire'],
          isFalse,
          reason: 'false is ignored even with padding');
      // A false-only row carries no data at all → skipped empty, exactly
      // like the mapping table's data rule.
      final result = dripCsvToExportJson(dripOneRowCsv(dripHeader,
          cells('2026-01-01', {12: 'false'})));
      expect(result.stats.rowsImported, 0,
          reason: 'a desire=false row is not a data row');
      expect(result.stats.rowsSkippedEmpty, 1);
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['entries'] as List, isEmpty);
    });

    test(
        'pain options: drip ovulation pain → Mittelschmerz (M), tender '
        'breasts → breast (B)', () {
      // drip's ovulation pain kind is exactly the Mittelschmerz (M) day
      // option; drip's tender breasts kind is the breast-pain (B) option.
      // The two stay independent day flags — B without M and both at once.
      // (cells() indices align 0-based with painHeader.)
      final mDay = entryOf(cells('2026-01-01', {2: 'true'}),
          header: painHeader);
      expect(mDay['pain_mittelschmerz'], true);
      expect(mDay['pain_breast'], false);
      final bDay = entryOf(cells('2026-01-01', {3: 'true'}),
          header: painHeader);
      expect(bDay['pain_breast'], true);
      expect(bDay['pain_mittelschmerz'], false);
      final both = entryOf(cells('2026-01-01', {2: 'true', 3: 'true'}),
          header: painHeader);
      expect(both['pain_mittelschmerz'], true);
      expect(both['pain_breast'], true);
    });

    test(
        'pain: kinds without a cycle-app option are dropped like other '
        'dropped columns', () {
      // cramps/headache/… have no storage option; a row whose ONLY data is
      // such a flag is skipped entirely (dropped columns are not data),
      // while the pain NOTE keeps any recorded pain day importable.
      final crampsOnly = dripCsvToExportJson(
          dripOneRowCsv(painHeader, cells('2026-01-01', {1: 'true'})));
      expect(crampsOnly.stats.rowsImported, 0,
          reason: 'cramps alone are not mappable, the row carries no data');
      expect(crampsOnly.stats.rowsSkippedEmpty, 1);
      final noteOnly = dripCsvToExportJson(
          dripOneRowCsv(painHeader, cells('2026-01-01', {5: 'cramps day'})));
      expect(noteOnly.stats.rowsImported, 1,
          reason: 'the pain note is mapped data (the [pain] line)');
    });

    group('sex: only with partner without contraception maps', () {
      /// Data row cells aligned to [sexHeader] (0 = date, 1..12 the sex
      /// family in drip's column order).
      List<String> sexCells(String date, Map<int, String> byIndex) {
        final c = List.filled(sexHeader.length, '');
        c[0] = date;
        byIndex.forEach((i, v) => c[i] = v);
        return c;
      }

      // sexHeader indices: 1 solo, 2 partner, 3 condom, 4 pill, 5 iud,
      // 6 patch, 7 ring, 8 implant, 9 diaphragm, 10 none, 11 other,
      // 12 note. The note anchors the row in the not-mapped cases (the
      // unmappable flags alone would leave the row data-less and skipped).
      test('partner + none → the sex observation (the only mapped variant)',
          () {
        final e = entryOf(sexCells('2026-01-01', {2: 'true', 10: 'true'}),
            header: sexHeader);
        expect(e['sex'], isTrue);
      });

      test('partner + none with the note → sex flag and [sex] note line', () {
        final e = entryOf(
            sexCells('2026-01-01', {2: 'true', 10: 'true', 12: 'good day'}),
            header: sexHeader);
        expect(e['sex'], isTrue);
        expect(e['notes'], '[sex] good day');
      });

      test('partner with any contraceptive method → not sex', () {
        // The [sex] note keeps the day importable in every variant; the
        // sex observation itself stays unset.
        for (final method in [3, 4, 5, 6, 7, 8, 9, 11]) {
          final result = dripCsvToExportJson(
              dripOneRowCsv(
                  sexHeader,
                  sexCells(
                      '2026-01-01', {2: 'true', method: 'true', 12: 'n'})));
          final doc = jsonDecode(result.json) as Map<String, Object?>;
          final e = (doc['entries']! as List).single as Map<String, Object?>;
          expect(e['sex'], isFalse,
              reason: 'method index $method is a contraception');
          expect(e['notes'], '[sex] n');
        }
      });

      test('partner + none + a method together → not sex (contradictory)',
          () {
        final result = dripCsvToExportJson(dripOneRowCsv(
            sexHeader,
            sexCells('2026-01-01',
                {2: 'true', 10: 'true', 3: 'true', 12: 'n'})));
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(e['sex'], isFalse,
            reason: 'a recorded method contradicts the none confirmation');
      });

      test('partner without any contraceptive info → not sex (ambiguous)', () {
        // No generous defaults: only an explicit none=true confirms "no
        // contraception"; absent columns are unknown, not "none".
        final result = dripCsvToExportJson(dripOneRowCsv(
            sexHeader, sexCells('2026-01-01', {2: 'true', 12: 'n'})));
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(e['sex'], isFalse);
        expect(e['notes'], '[sex] n');
      });

      test('solo never maps to the sex observation, even with none', () {
        final result = dripCsvToExportJson(dripOneRowCsv(
            sexHeader,
            sexCells('2026-01-01', {1: 'true', 10: 'true', 12: 'n'})));
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(e['sex'], isFalse, reason: 'solo is not partner sex');
        expect(e['notes'], '[sex] n');
      });

      test('solo-only / partner-only / method-only rows are skipped entirely',
          () {
        // Unmappable sex flags alone are NOT data — the same rule as the
        // unmappable pain kinds (the row carries no other mapped field).
        for (final Map<int, String> variant in [
          {1: 'true'}, // solo
          {2: 'true'}, // partner, no contraceptive info
          {3: 'true'}, // condom
          {10: 'true'}, // none, no activity
          {
            1: 'true',
            2: 'true',
          }, // solo + partner without contraceptive info
        ]) {
          final result = dripCsvToExportJson(
              dripOneRowCsv(sexHeader, sexCells('2026-01-01', variant)));
          expect(result.stats.rowsImported, 0,
              reason: 'variant $variant maps to nothing');
          expect(result.stats.rowsSkippedEmpty, 1,
              reason: 'variant $variant is not data');
        }
      });
    });

    test('desire/sex/pain/mood: flags and note-only days', () {
      expect(entryOf(cells('2026-01-01', {12: '2'}))['desire'], true);
      // Solo sex and partner sex WITHOUT the positive "no contraception"
      // confirmation are dropped (the detailed variants are pinned in the
      // dedicated sex group below) — such rows carry no data at all.
      final soloOnly =
          dripCsvToExportJson(dripOneRowCsv(dripHeader, cells('2026-01-01', {
            13: 'true',
          })));
      expect(soloOnly.stats.rowsImported, 0,
          reason: 'solo sex maps to nothing, the row has no other data');
      expect(soloOnly.stats.rowsSkippedEmpty, 1);
      final partnerOnly =
          dripCsvToExportJson(dripOneRowCsv(dripHeader, cells('2026-01-01', {
            14: 'true',
          })));
      expect(partnerOnly.stats.rowsImported, 0,
          reason: 'partner sex without contraception info is not mapped');
      expect(partnerOnly.stats.rowsSkippedEmpty, 1);
      // contraceptive columns are ignored (no model for them) — a row with
      // no activity beyond them is data-less and skipped entirely (its
      // stats are pinned separately below)
      final noActivity =
          dripCsvToExportJson(dripOneRowCsv(dripHeader, cells('2026-01-01', {
            15: 'true',
          })));
      expect(noActivity.stats.rowsImported, 0,
          reason: 'condom alone is dropped, row has no other data');
      expect(noActivity.stats.rowsSkippedEmpty, 1);
      // A pain note without an ovulation/breast flag still marks the day
      // as a data row; the pain options themselves stay unset.
      final noted = entryOf(cells('2026-01-01', {18: 'cramps day'}));
      expect(noted['pain_breast'], false);
      expect(noted['pain_mittelschmerz'], false);
      expect(noted['notes'], '[pain] cramps day');
      expect(entryOf(cells('2026-01-01', {19: 'true'}))['mood'], true);
      final moodNote = entryOf(cells('2026-01-01', {20: 'deadline stress'}));
      expect(moodNote['mood'], true);
      expect(moodNote['notes'], '[mood] deadline stress');
    });

    test('notes: day note first, then [temp]/[pain]/[sex]/[mood] lines', () {
      final e = entryOf(cells('2026-01-01', {
        1: '36.6',
        3: 'measured late',
        11: 'slept badly',
        18: 'cramps',
        16: 'with partner',
        20: 'stressed',
      }));
      expect(
          e['notes'],
          'slept badly\n'
          '[temp] measured late\n'
          '[pain] cramps\n'
          '[sex] with partner\n'
          '[mood] stressed');
    });

    test('stats: empty rows are skipped, date-only rows import nothing', () {
      final result = dripCsvToExportJson(dripCsv(dripHeader, [
        cells('2026-01-01', {}),
      ]));
      expect(result.stats.rowsTotal, 1);
      expect(result.stats.rowsSkippedEmpty, 1);
      expect(result.stats.rowsImported, 0);
      expect(result.stats.rowsInvalid, 0);
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['entries'] as List, isEmpty);
    });

    test('stats: a contraceptive-only row counts as empty (column dropped)',
        () {
      final result = dripCsvToExportJson(dripCsv(dripHeader, [
        cells('2026-01-01', {15: 'true'}),
      ]));
      expect(result.stats.rowsSkippedEmpty, 1);
      expect(result.stats.rowsImported, 0);
    });

    test('stats: broken dates count invalid, never imported', () {
      final result = dripCsvToExportJson(dripCsv(dripHeader, [
        cells('2026-13-01', {4: '2'}), // impossible month
        cells('not a date', {4: '2'}), // no ISO shape
        cells('2026-01-01', {4: '1'}), // the good row
      ]));
      expect(result.stats.rowsTotal, 3);
      expect(result.stats.rowsInvalid, 2);
      expect(result.stats.rowsImported, 1);
      expect(result.stats.rowsSkippedEmpty, 0);
    });

    test('stats: total accounting adds up per csv', () {
      final result = dripCsvToExportJson(dripCsv(dripHeader, [
        cells('2026-01-01', {4: '2'}),
        cells('2026-01-02', {}), // empty
        cells('bogus', {4: '1'}), // invalid
        cells('2026-01-04', {1: '36.2'}),
      ]));
      expect(result.stats.rowsTotal, 4);
      expect(
        result.stats.rowsImported +
            result.stats.rowsSkippedEmpty +
            result.stats.rowsInvalid,
        result.stats.rowsTotal,
      );
      expect(result.stats.rowsImported, 2);
    });

    test('tolerance: unknown columns are ignored', () {
      final header = [...dripHeader, 'future.symptom', 'other.thing'];
      final row = [...cells('2026-01-01', {7: '2'}), 'zzz', 'iq 90'];
      final result = dripCsvToExportJson(dripOneRowCsv(header, row));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final e = (doc['entries']! as List).first as Map<String, Object?>;
      expect(e['mucus_sign'], 'f');
      expect(e['desire'], false, reason: 'unknown columns carry no data');
    });

    test('tolerance: missing known columns simply carry no data', () {
      final header = ['date', 'bleeding.value'];
      final result =
          dripCsvToExportJson(dripOneRowCsv(header, ['2026-01-01', '1']));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final e = (doc['entries']! as List).first as Map<String, Object?>;
      expect(e['bleeding'], 2,
          reason: 'drip value 1 (light) is the stored level 2');
      expect(e['bbt_c'], isNull);
      expect(e['mucus_sign'], isNull);
    });

    test('tolerance: truncated header with longer rows (extra cells dropped)',
        () {
      final header = ['date', 'temperature.value', 'bleeding.value'];
      final result = dripCsvToExportJson(dripOneRowCsv(
          header, const ['2026-01-01', '36.2', '2', 'junk', 'more junk']));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final e = (doc['entries']! as List).first as Map<String, Object?>;
      expect(e['bbt_c'], 36.2);
      expect(e['bleeding'], 3);
    });

    test('tolerance: short rows are padded with empty cells', () {
      final header = ['date', 'temperature.value', 'bleeding.value'];
      final result = dripCsvToExportJson(dripOneRowCsv(
        header,
        const ['2026-01-01'],
      ));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['entries'] as List, isEmpty, reason: 'date-only row');
      expect(result.stats.rowsSkippedEmpty, 1);
    });

    test('document shape: current-version blob with the main profile and '
        'no marks', () {
      final result = dripCsvToExportJson(dripOneRowCsv(
          dripHeader, cells('2026-01-01', {4: '2', 1: '36.2'})));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['schema_version'], exportSchemaVersion);
      expect(doc['profiles'], [
        {'id': 1, 'name': 'main', 'ordinal': 0},
      ]);
      expect(doc['marks'] as List, isEmpty);
      expect(doc['exported_at'], isA<String>());
      // The produced document passes the shared validator untouched.
      final blob = parseExportJson(result.json);
      expect(blob.entries, hasLength(1));
      final e = blob.entries.single;
      expect(e['profile_id'], 1);
      expect(e['date'], '2026-01-01');
      expect(e['bleeding'], 3,
          reason: 'drip value 2 (medium) is the stored level 3');
      expect(e['bbt_c'], 36.2);
    });

    test('fixture: stats accounting on the real 73-row export specimen', () {
      final result = dripCsvToExportJson(dripExportSampleCsv);
      expect(result.stats.rowsTotal, 73);
      expect(result.stats.rowsInvalid, 0);
      expect(
        result.stats.rowsImported + result.stats.rowsSkippedEmpty,
        result.stats.rowsTotal,
      );
      expect(result.stats.rowsImported, greaterThan(15),
          reason: 'the specimen carries ~25 titled days');

      final entries = ((jsonDecode(result.json)
              as Map<String, Object?>)['entries'] as List)
          .cast<Map<dynamic, dynamic>>();
      Map by(String date) =>
          entries.where((e) => e['date'] == date).single;
      // mucus day: value 2 ('f') wins over the 2+1 parts, firmness clamps
      expect(by('2026-07-15')['mucus_sign'], 'f');
      expect(by('2026-07-15')['cervix'], 'medium, soft, medium');
      // excluded temperature day
      expect(by('2026-09-13')['exclude_other'], true);
      expect(by('2026-09-13')['bbt_c'], 36.7);
      expect(by('2026-09-13')['notes'], '[temp] measured late');
      // note-only day
      expect(
          by('2026-09-15')['notes'], 'cramps again, expecting menses soon.');
      // bleeding + mood/mood-note day (drip value 2 = medium → level 3)
      expect(by('2026-08-31')['bleeding'], 3);
      expect(by('2026-08-31')['mood'], true);
      expect(by('2026-08-31')['notes'], '[mood] first day jitters');
      // desire + mood-flag day
      expect(by('2026-08-20')['desire'], true);
      expect(by('2026-08-20')['mood'], true);
      // Sex observations: only with-partner-without-contraception days map
      // to sex. The specimen's sex days all fail that rule — 2026-07-17
      // (partner WITH a condom), 2026-08-16 (partner, but the only
      // contraceptive info is condom=false/pill=false: no explicit none,
      // the rest unknown → ambiguous, dropped entirely), 2026-09-12
      // (solo) — so no day carries sex=true.
      expect(entries.any((e) => e['date'] == '2026-08-16'), isFalse,
          reason: 'ambiguous partner day without contraception info: '
              'not sex, not data');
      final withCondom = by('2026-07-17');
      expect(withCondom['sex'], isFalse,
          reason: 'partner sex with a condom is not the mapped variant');
      expect(withCondom['desire'], isTrue);
      expect(withCondom['notes'], '[sex] with condom, quite good');
      final soloDay = by('2026-09-12');
      expect(soloDay['sex'], isFalse, reason: 'solo is not partner sex');
      expect(soloDay['notes'], '[sex] morning');
      // breast-pain (B) + pain-note day (drip pain.tenderBreasts → B)
      expect(by('2026-08-25')['pain_breast'], true);
      expect(by('2026-08-25')['pain_mittelschmerz'], false);
      expect(by('2026-08-25')['notes'], '[pain] tender in the evening');
      // temperature measurement times ride through as measured_at_minutes
      expect(by('2026-07-05')['measured_at_minutes'], 7 * 60 + 15,
          reason: 'drip temperature.time 07:15');
      expect(by('2026-08-02')['measured_at_minutes'], 6 * 60 + 50,
          reason: 'drip temperature.time 06:50');
      // a temperature without a recorded time stays null, never fabricated
      expect(by('2026-09-13')['measured_at_minutes'], isNull,
          reason: '2026-09-13 has a temperature but no time cell');
      expect(by('2026-08-20')['measured_at_minutes'], isNull,
          reason: 'no temperature at all on 2026-08-20');
    });

    group('temperature.time → measured_at_minutes', () {
      /// Header as drip writes it for a row carrying a measured temperature;
      /// the bleeding cell stays empty on purpose (the temperature fields
      /// already make the row a data row).
      const timeHeader = [
        'date',
        'temperature.value',
        'temperature.time',
        'bleeding.value',
      ];

      List<String> timeCells(String date, String value, String time) =>
          [date, value, time, ''];

      test('HH:MM parses to minutes since midnight', () {
        for (final (hhmm, minutes) in [
          ('07:15', 7 * 60 + 15),
          ('06:50', 6 * 60 + 50),
          ('0:00', 0), // midnight
          ('23:59', 23 * 60 + 59), // last minute of the day
          ('7:05', 7 * 60 + 5), // single-digit hour tolerated
          ('07:15:00', 7 * 60 + 15), // optional trailing seconds dropped
          (' 09:30 ', 9 * 60 + 30), // spreadsheet round-trip padding
        ]) {
          final e = entryOf(
            timeCells('2026-01-01', '36.2', hhmm),
            header: timeHeader,
          );
          expect(
            e['measured_at_minutes'],
            minutes,
            reason: 'drip time "$hhmm" → $minutes minutes',
          );
        }
      });

      test('no time cell on the sheet stays null (not fabricated)', () {
        final absent = entryOf(
          timeCells('2026-01-01', '36.2', ''),
          header: timeHeader,
        );
        expect(absent['measured_at_minutes'], isNull);
      });

      test('a dropped temperature.time column stays null', () {
        // Header-driven parser: a drip version that never records the time
        // behaves exactly like an empty cell.
        final e = entryOf(cells('2026-01-01', {1: '36.2'}));
        expect(e['measured_at_minutes'], isNull);
      });

      test('malformed or out-of-range times degrade to null, row survives',
          () {
        for (final bad in [
          '25:00', // hour out of range
          '07:60', // minute out of range
          '-07:15', // negative
          'random', // no time shape
          '0715', // no colon (drip always writes HH:MM)
          '12', // bare number, ambiguous
          'ab:cd', // non-numeric parts
        ]) {
          final result = dripCsvToExportJson(
            dripOneRowCsv(
              timeHeader,
              timeCells('2026-01-01', '36.2', bad),
            ),
          );
          final doc = jsonDecode(result.json) as Map<String, Object?>;
          final entries = doc['entries']! as List;
          expect(entries, hasLength(1),
              reason: '"$bad" must not drop the row');
          expect(
            (entries.single as Map)['measured_at_minutes'],
            isNull,
            reason: '"$bad" is not a recording time',
          );
        }
      });

      test('a time cell alone is not data (row skipped when else empty)', () {
        final timeOnlyHeader = ['date', 'temperature.time'];
        final result = dripCsvToExportJson(dripOneRowCsv(
          timeOnlyHeader,
          const ['2026-01-01', '07:15'],
        ));
        expect(result.stats.rowsImported, 0,
            reason: 'a lone time without its measurement is meaningless');
        expect(result.stats.rowsSkippedEmpty, 1);
      });
    });
  });
}
