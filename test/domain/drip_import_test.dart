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
import 'package:cycle_app/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The committed drip export specimen, read straight from disk (working dir
/// is the repo root when the host test runner starts).
final String dripExportSampleCsv = File(
  'test/fixtures/drip-export-sample.csv',
).readAsStringSync();

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

/// A minimal bleeding-block header (header order as drip writes it) for the
/// `bleeding.exclude` pins: the replay-skip flag rides next to the bleeding
/// value, exactly like `temperature.exclude` rides next to its value.
const List<String> bleedingExcludeHeader = [
  'date',
  'bleeding.value',
  'bleeding.exclude',
];

/// Builds a drip CSV: [header] plus one data [row] joined the way drip
/// writes its files (plain comma join, plain newlines).
String dripOneRowCsv(List<String> header, List<String> row) =>
    dripCsv(header, [row]);

/// Same for several data rows at once.
String dripCsv(List<String> header, List<List<String>> rows) =>
    [header.join(','), ...rows.map((r) => r.join(','))].join('\n');

/// Cells aligned to [bleedingExcludeHeader]: [exclude] writes the
/// `bleeding.exclude=true` cell, every other cell stays empty.
List<String> bleedingExcludeCells(
  String date, {
  String? value,
  bool exclude = false,
}) => [date, value ?? '', exclude ? 'true' : ''];

/// Runs one data row ([cells] aligned to [header]) through the importer and
/// returns the single produced entry row map of the document.
Map<String, Object?> entryOf(
  List<String> cells, {
  List<String> header = dripHeader,
}) {
  final result = dripCsvToExportJson(dripOneRowCsv(header, cells));
  final doc = jsonDecode(result.json) as Map<String, Object?>;
  final entries = doc['entries']! as List;
  expect(
    entries,
    hasLength(1),
    reason: 'this row must map to exactly one entry',
  );
  return entries.single as Map<String, Object?>;
}

/// Same as [entryOf] but returns the WHOLE document map (for asserting the
/// derived mark rows that ride alongside the entry).
Map<String, Object?> docOf(
  List<String> cells, {
  List<String> header = dripHeader,
}) =>
    jsonDecode(dripCsvToExportJson(dripOneRowCsv(header, cells)).json)
        as Map<String, Object?>;

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
        'date,note.value\n2026-01-01,"has, comma. period and ""quotes"""',
      );
      expect(rows[1], ['2026-01-01', 'has, comma. period and "quotes"']);
    });

    test('quoted field may span multiple lines (multi-line note)', () {
      final rows = splitDripCsv(
        'date,note.value\n2026-01-01,"line one\nline two"\n2026-01-02,',
      );
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
      expect(
        () => parseDripCsv('note.value,desire.value\nhello,3'),
        throwsA(isA<FormatException>()),
      );
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

    test('temperature: value parses, note rides; exclude becomes the '
        'derived exclusion mark (no raw exclude key)', () {
      final doc = docOf(
        cells('2026-01-01', {1: '36.2', 2: 'true', 3: 'measured late'}),
      );
      final e = (doc['entries']! as List).single as Map<String, Object?>;
      expect(e['bbt_c'], 36.2);
      // drip's "not usable for fertility detection" maps to the
      // ignoreTemperature MARK (author 'import') — NOT to raw entry
      // data: the day carries temp_disturbances 0 (drip has no reason
      // column, so no mask bits come from drip).
      expect(e['temp_disturbances'], 0);
      expect(
        e.containsKey('exclude_illness'),
        isFalse,
        reason: 'the v5 shape carries no exclude_* keys',
      );
      expect(
        e.containsKey('exclude_other'),
        isFalse,
        reason: 'the v5 shape carries no exclude_* keys',
      );
      expect(e['notes'], '[temp] measured late');
      expect(doc['marks'], [
        {
          'entry_date': '2026-01-01',
          'mark_type': 'ignoreTemperature',
          'author': 'import',
        },
      ]);
    });

    test('temperature.exclude=false (or empty) derives no exclusion mark', () {
      expect(
        (docOf(cells('2026-01-01', {1: '36.5', 2: 'false'}))['marks']! as List),
        isEmpty,
      );
      expect(
        (docOf(cells('2026-01-01', {1: '36.5'}))['marks']! as List),
        isEmpty,
      );
    });

    test('replay-mark derivation over row maps that OMIT the bleeding key '
        'behaves like bleeding-none days', () {
      // The sparse document shape omits neutral keys; the derived marks
      // replay EXACTLY the row maps a document carries. Deriving over maps
      // without the `bleeding` key must not crash and must produce the
      // SAME marks as the same rows carrying the explicit neutral level 0.
      List<Map<String, Object?>> paddedWithNone(
        List<Map<String, Object?>> rows,
      ) => [
        for (final row in rows)
          {...row, if (!row.containsKey('bleeding')) 'bleeding': 0},
      ];

      // A menstruation onset mid-set (none days before, heavy after — no
      // bleeding continuity) must still suggest its cycleStart mark from
      // sparse rows, and the excluded day keeps its ignoreTemperature.
      final sparseRows = <Map<String, Object?>>[
        {'date': '2026-06-01', 'bleeding': 4},
        {'date': '2026-06-02'}, // excluded day (temperature excluded)
        {'date': '2026-06-03', 'bbt_c': 36.5}, // no bleeding key at all
        {'date': '2026-06-20'}, // neutral day, key omitted
        {'date': '2026-06-21', 'notes': 'flagged'},
        {'date': '2026-06-22', 'bleeding': 4},
      ];

      final sparseMarks = deriveDripMarks(sparseRows, {'2026-06-02'}, {});
      final explicitMarks = deriveDripMarks(paddedWithNone(sparseRows), {
        '2026-06-02',
      }, {});

      expect(
        sparseMarks,
        explicitMarks,
        reason: 'an omitted bleeding key replays exactly like level 0',
      );
      expect(
        sparseMarks,
        containsAll([
          {
            'entry_date': '2026-06-02',
            'mark_type': 'ignoreTemperature',
            'author': 'import',
          },
          {
            'entry_date': '2026-06-01',
            'mark_type': 'cycleStart',
            'author': 'import',
          },
          {
            'entry_date': '2026-06-22',
            'mark_type': 'cycleStart',
            'author': 'import',
          },
        ]),
        reason:
            'the none-day semantics hold through the sparse replay: '
            'the excluded day derives its ignoreTemperature and '
            'menstruation onsets still suggest cycleStart (with no '
            'suppression where the preceding day is a sparse none day)',
      );
    });

    test('deriveDripMarks turns an unparsable bleeding value into an '
        'explicit ArgumentError', () {
      // Only reachable from outside the mapper's contract (a hand-edited
      // or corrupted document): junk tokens, bools and doubles parse to
      // null in tryParseBleeding, while a missing key means "none" and
      // legacy token strings map to members. The error must self-explain
      // instead of dying on a bare null check.
      final rows = [
        {'date': '2026-06-01', 'bleeding': 'junk-token'},
      ];
      expect(
        () => deriveDripMarks(rows, {}, {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            contains('junk-token'),
          ),
        ),
        reason: 'the error names the offending bleeding value',
      );
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
        expect(
          e['mucus_sign'],
          expected.$1,
          reason: 'nfp $dripNfp → sign ${expected.$1}',
        );
        expect(
          e['mucus_quality'],
          expected.$2,
          reason: 'nfp $dripNfp → quality ${expected.$2}',
        );
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

    test('mucus: feeling+texture composite ports drip getNfpMucus exactly', () {
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
        expect(
          e['mucus_sign'],
          expected.$1,
          reason: 'feeling $feeling + texture $texture → nfp $nfp',
        );
        expect(e['mucus_quality'], expected.$2, reason: 'nfp $nfp');
      }
    });

    test('mucus: a composite needs BOTH parts (null when either missing)', () {
      expect(
        entryOf(cells('2026-01-01', {5: '2', 4: '2'}))['mucus_sign'],
        isNull,
        reason: 'a feeling without a texture carries no mucus',
      );
      expect(
        entryOf(cells('2026-01-01', {6: '2', 4: '2'}))['mucus_sign'],
        isNull,
        reason: 'a texture without a feeling carries no mucus',
      );
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

    test('cervix: the free-text composite key stays dropped', () {
      // The owner re-confirmed (2026-09-17) that drip's free-text cervix
      // composite stays dropped: the opening/firmness/position vocabulary
      // indexes map ONLY into the structured fields (pinned in the
      // structured and firmness tests below), never into a `cervix`
      // string — whatever cells the row carries.
      expect(
        entryOf(cells('2026-01-01', {8: '1', 9: '1', 10: '1'}))['cervix'],
        isNull,
      );
      // partial observations map only structurally, too
      expect(entryOf(cells('2026-01-01', {8: '0'}))['cervix'], isNull);
      expect(entryOf(cells('2026-01-01', {10: '2'}))['cervix'], isNull);
      // and a fully empty triple carries no cervix key either
      expect(entryOf(cells('2026-01-01', {4: '2'}))['cervix'], isNull);
    });

    test('cervix: structured tokens decode the 0-based vocabulary indexes '
        'by position, out-of-range → null', () {
      // The structured observation (_cervixObservation) is INDEX-based:
      // position {0: low, 1: medium, 2: high}, opening {0: closed,
      // 1: middle, 2: open}. These pins exist so an enum reorder or an
      // index shift (CervixPosition.values[p]) fails loudly here instead of
      // silently importing shifted values. Header indices: 8 = opening,
      // 10 = position.
      // position 0/1/2 → low/medium/high, with a neutral opening.
      expect(
        entryOf(cells('2026-01-01', {10: '0', 8: '0'}))['cervix_position'],
        'low',
      );
      expect(
        entryOf(cells('2026-01-01', {10: '1', 8: '0'}))['cervix_position'],
        'medium',
      );
      expect(
        entryOf(cells('2026-01-01', {10: '2', 8: '0'}))['cervix_position'],
        'high',
      );
      // opening 0/1/2 → closed/middle/open (drip's "medium" → cycle-app's
      // "middle" — same value, different storage name), with a neutral
      // position.
      expect(
        entryOf(cells('2026-01-01', {8: '0', 10: '0'}))['cervix_opening'],
        'closed',
      );
      expect(
        entryOf(cells('2026-01-01', {8: '1', 10: '0'}))['cervix_opening'],
        'middle',
      );
      expect(
        entryOf(cells('2026-01-01', {8: '2', 10: '0'}))['cervix_opening'],
        'open',
      );
      // Out-of-range indexes → null for THAT dimension only; the other
      // dimension (and the clamping free-text line) keep their values. The
      // bleeding cell keeps the row a data row in the non-numeric case.
      expect(
        entryOf(cells('2026-01-01', {10: '3', 8: '1'}))['cervix_position'],
        isNull,
        reason: 'position index 3 is outside 0..2',
      );
      expect(
        entryOf(cells('2026-01-01', {10: '3', 8: '1'}))['cervix_opening'],
        'middle',
      );
      expect(
        entryOf(cells('2026-01-01', {8: '7', 10: '1'}))['cervix_opening'],
        isNull,
        reason: 'opening index 7 is outside 0..2',
      );
      expect(
        entryOf(cells('2026-01-01', {8: '7', 10: '1'}))['cervix_position'],
        'medium',
      );
      expect(
        entryOf(cells('2026-01-01', {10: '-1', 8: '0'}))['cervix_position'],
        isNull,
        reason: 'a negative index is out of range',
      );
      // Non-numeric cells never map structurally (they also stay out of
      // the clamping free text), so the row needs another data anchor.
      expect(
        entryOf(
          cells('2026-01-01', {8: 'x', 10: 'y', 4: '2'}),
        )['cervix_opening'],
        isNull,
      );
      expect(
        entryOf(
          cells('2026-01-01', {8: 'x', 10: 'y', 4: '2'}),
        )['cervix_position'],
        isNull,
      );
      // Absent columns behave like empty cells (no structured tokens).
      final absent = entryOf(
        ['2026-01-01', '2'],
        header: ['date', 'bleeding.value'],
      );
      expect(absent['cervix_position'], isNull);
      expect(absent['cervix_opening'], isNull);
    });

    test('cervix: firmness maps into the structured field, 0→hard, 1→soft, '
        'out-of-range clamps like the free text', () {
      // drip's firmness vocabulary is hard/soft (0-based, length 2). The
      // structured field is set IN ADDITION to the (clamping) free-text
      // line. Header index: 9 = cervix.firmness.
      expect(
        entryOf(cells('2026-01-01', {9: '0', 4: '2'}))['cervix_firmness'],
        'hard',
      );
      expect(
        entryOf(cells('2026-01-01', {9: '1', 4: '2'}))['cervix_firmness'],
        'soft',
      );
      // The shipped hand-authored specimen carries firmness=2, out of
      // drip's vocabulary: it clamps to soft, exactly like the free-text
      // word (and unlike position/opening, which map out-of-range to null).
      expect(
        entryOf(cells('2026-01-01', {9: '2', 4: '2'}))['cervix_firmness'],
        'soft',
        reason: 'the out-of-range specimen index clamps to soft',
      );
      expect(
        entryOf(cells('2026-01-01', {9: '-1', 4: '2'}))['cervix_firmness'],
        'hard',
        reason: 'a negative index clamps to the nearest valid one',
      );
      expect(
        entryOf(cells('2026-01-01', {9: '7', 4: '2'}))['cervix_firmness'],
        'soft',
        reason: 'a far-out index clamps to the nearest valid one',
      );
      // Non-numeric cells stay unstructured (and out of the free text too).
      expect(
        entryOf(cells('2026-01-01', {9: 'x', 4: '2'}))['cervix_firmness'],
        isNull,
      );
      // Absent column behaves like an empty cell.
      final absent = entryOf(
        ['2026-01-01', '2'],
        header: ['date', 'bleeding.value'],
      );
      expect(absent['cervix_firmness'], isNull);
    });

    test('desire: values are dropped entirely — not data, no key, no flag', () {
      // drip's desire vocabulary is 0=low/1=medium/2=high — the intensity
      // is not storable here AND the dropped flag is no longer data at all
      // (Lust is removed everywhere). Any desire-only row imports nothing.
      expect(
        entryOf(cells('2026-01-01', {12: '0', 4: '2'})).containsKey('desire'),
        isFalse,
        reason: 'the v5 shape carries no `desire` key',
      );
      expect(
        entryOf(
          cells('2026-01-01', {12: 'false', 4: '2'}),
        ).containsKey('desire'),
        isFalse,
      );
      // A desire-only row (any value, including a literal `false`) carries
      // no data at all → skipped empty, exactly like the mapping table's
      // data rule.
      for (final desireValue in ['0', '1', '2', 'false', ' false ']) {
        final result = dripCsvToExportJson(
          dripOneRowCsv(dripHeader, cells('2026-01-01', {12: desireValue})),
        );
        expect(
          result.stats.rowsImported,
          0,
          reason: 'a desire-only row ($desireValue) is not a data row',
        );
        expect(result.stats.rowsSkippedEmpty, 1);
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        expect(doc['entries'] as List, isEmpty);
      }
    });

    test('pain options: drip ovulation pain → Mittelschmerz (M), tender '
        'breasts → breast (B)', () {
      // drip's ovulation pain kind is exactly the Mittelschmerz (M) day
      // option; drip's tender breasts kind is the breast-pain (B) option.
      // The two stay independent day flags — B without M and both at once.
      // (cells() indices align 0-based with painHeader.)
      final mDay = entryOf(
        cells('2026-01-01', {2: 'true'}),
        header: painHeader,
      );
      expect(mDay['pain_mittelschmerz'], true);
      expect(mDay['pain_breast'], false);
      final bDay = entryOf(
        cells('2026-01-01', {3: 'true'}),
        header: painHeader,
      );
      expect(bDay['pain_breast'], true);
      expect(bDay['pain_mittelschmerz'], false);
      final both = entryOf(
        cells('2026-01-01', {2: 'true', 3: 'true'}),
        header: painHeader,
      );
      expect(both['pain_mittelschmerz'], true);
      expect(both['pain_breast'], true);
    });

    test('pain: kinds without a cycle-app option are dropped like other '
        'dropped columns', () {
      // cramps/headache/… have no storage option; a row whose ONLY data is
      // such a flag is skipped entirely (dropped columns are not data),
      // while the pain NOTE keeps any recorded pain day importable.
      final crampsOnly = dripCsvToExportJson(
        dripOneRowCsv(painHeader, cells('2026-01-01', {1: 'true'})),
      );
      expect(
        crampsOnly.stats.rowsImported,
        0,
        reason: 'cramps alone are not mappable, the row carries no data',
      );
      expect(crampsOnly.stats.rowsSkippedEmpty, 1);
      final noteOnly = dripCsvToExportJson(
        dripOneRowCsv(painHeader, cells('2026-01-01', {5: 'cramps day'})),
      );
      expect(
        noteOnly.stats.rowsImported,
        1,
        reason: 'the pain note is mapped data (the [pain] line)',
      );
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
      test(
        'partner + none → the sex observation (the only mapped variant)',
        () {
          final e = entryOf(
            sexCells('2026-01-01', {2: 'true', 10: 'true'}),
            header: sexHeader,
          );
          // Time-less drip sex maps onto the MIDDLE time of day (owner
          // decision); drip carries no time-of-day for sex itself.
          expect(e['sex_timings'], SexTiming.middle.bit);
          expect(
            e.containsKey('sex'),
            isFalse,
            reason: 'the v4 export shape carries no `sex` flag any more',
          );
        },
      );

      test('partner + none with the note → sex mask and [sex] note line', () {
        final e = entryOf(
          sexCells('2026-01-01', {2: 'true', 10: 'true', 12: 'good day'}),
          header: sexHeader,
        );
        expect(e['sex_timings'], SexTiming.middle.bit);
        expect(e['notes'], '[sex] good day');
      });

      test('partner with any contraceptive method → not sex', () {
        // The [sex] note keeps the day importable in every variant; the
        // sex observation itself stays unset (mask 0).
        for (final method in [3, 4, 5, 6, 7, 8, 9, 11]) {
          final result = dripCsvToExportJson(
            dripOneRowCsv(
              sexHeader,
              sexCells('2026-01-01', {2: 'true', method: 'true', 12: 'n'}),
            ),
          );
          final doc = jsonDecode(result.json) as Map<String, Object?>;
          final e = (doc['entries']! as List).single as Map<String, Object?>;
          expect(
            e['sex_timings'],
            0,
            reason: 'method index $method is a contraception',
          );
          expect(e['notes'], '[sex] n');
        }
      });

      test('partner + none + a method together → not sex (contradictory)', () {
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            sexHeader,
            sexCells('2026-01-01', {2: 'true', 10: 'true', 3: 'true', 12: 'n'}),
          ),
        );
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(
          e['sex_timings'],
          0,
          reason: 'a recorded method contradicts the none confirmation',
        );
      });

      test('partner with no contraceptive info at all → the sex observation '
          '(absence of methods counts as none)', () {
        // There is no explicit none=true requirement any more (owner
        // decision, 2026-09-17): partner sex with no contraceptive method
        // flag set — including no method column filled in at all — counts
        // as partner sex without contraception. drip is a single
        // non-authoritative import source; its absent method answer must
        // not force the app's sex model to demand a positive "none"
        // confirmation.
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            sexHeader,
            sexCells('2026-01-01', {2: 'true', 12: 'n'}),
          ),
        );
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(e['sex_timings'], SexTiming.middle.bit);
        expect(e['notes'], '[sex] n');
      });

      test('solo never maps to the sex observation, even with none', () {
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            sexHeader,
            sexCells('2026-01-01', {1: 'true', 10: 'true', 12: 'n'}),
          ),
        );
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).single as Map<String, Object?>;
        expect(e['sex_timings'], 0, reason: 'solo is not partner sex');
        expect(e['notes'], '[sex] n');
      });

      test('solo-only / method-only rows are skipped entirely', () {
        // Unmappable sex flags alone are NOT data — the same rule as the
        // unmappable pain kinds (the row carries no other mapped field).
        // Under the owner rule of 2026-09-17 partner-without-method IS
        // mapped data, so the skipped set shrunk to the activity-less and
        // solo-only variants.
        for (final Map<int, String> variant in [
          {1: 'true'}, // solo
          {3: 'true'}, // condom
          {10: 'true'}, // none, no activity
        ]) {
          final result = dripCsvToExportJson(
            dripOneRowCsv(sexHeader, sexCells('2026-01-01', variant)),
          );
          expect(
            result.stats.rowsImported,
            0,
            reason: 'variant $variant maps to nothing',
          );
          expect(
            result.stats.rowsSkippedEmpty,
            1,
            reason: 'variant $variant is not data',
          );
        }
      });

      test('partner-only and solo+partner rows map (solo is ignored)', () {
        // The mapping rule keys on partner plus the absence of a method;
        // a co-recorded solo flag changes nothing about that.
        for (final Map<int, String> variant in [
          {2: 'true'}, // partner, no contraceptive info
          {1: 'true', 2: 'true'}, // solo + partner
        ]) {
          final result = dripCsvToExportJson(
            dripOneRowCsv(sexHeader, sexCells('2026-01-01', variant)),
          );
          expect(
            result.stats.rowsImported,
            1,
            reason: 'variant $variant is partner sex without contraception',
          );
          final doc = jsonDecode(result.json) as Map<String, Object?>;
          final e = (doc['entries']! as List).single as Map<String, Object?>;
          expect(
            e['sex_timings'],
            SexTiming.middle.bit,
            reason: 'variant $variant maps to the middle time of day',
          );
        }
      });
    });

    test('mood: flags are dropped; the [mood] note stays data', () {
      // Mood (Stimmung) is removed everywhere — the flags are NOT data:
      // a mood-flag-only row imports nothing. The mood NOTE is a raw note
      // (still data) and keeps such a day importable, with the '[mood]'
      // line preserved; the entry carries no `mood` key either way.
      final flagOnly = dripCsvToExportJson(
        dripOneRowCsv(dripHeader, cells('2026-01-01', {19: 'true'})),
      );
      expect(
        flagOnly.stats.rowsImported,
        0,
        reason: 'a mood flag alone is not mappable data',
      );
      expect(flagOnly.stats.rowsSkippedEmpty, 1);

      final moodNote = entryOf(cells('2026-01-01', {20: 'deadline stress'}));
      expect(
        moodNote.containsKey('mood'),
        isFalse,
        reason: 'the v5 shape carries no `mood` key',
      );
      expect(moodNote['notes'], '[mood] deadline stress');
    });

    test('notes: day note first, then [temp]/[pain]/[sex]/[mood] lines', () {
      final e = entryOf(
        cells('2026-01-01', {
          1: '36.6',
          3: 'measured late',
          11: 'slept badly',
          18: 'cramps',
          16: 'with partner',
          20: 'stressed',
        }),
      );
      expect(
        e['notes'],
        'slept badly\n'
        '[temp] measured late\n'
        '[pain] cramps\n'
        '[sex] with partner\n'
        '[mood] stressed',
      );
    });

    test('stats: empty rows are skipped, date-only rows import nothing', () {
      final result = dripCsvToExportJson(
        dripCsv(dripHeader, [cells('2026-01-01', {})]),
      );
      expect(result.stats.rowsTotal, 1);
      expect(result.stats.rowsSkippedEmpty, 1);
      expect(result.stats.rowsImported, 0);
      expect(result.stats.rowsInvalid, 0);
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['entries'] as List, isEmpty);
    });

    test(
      'stats: a contraceptive-only row counts as empty (column dropped)',
      () {
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {15: 'true'}),
          ]),
        );
        expect(result.stats.rowsSkippedEmpty, 1);
        expect(result.stats.rowsImported, 0);
      },
    );

    test('stats: broken dates count invalid, never imported', () {
      final result = dripCsvToExportJson(
        dripCsv(dripHeader, [
          cells('2026-13-01', {4: '2'}), // impossible month
          cells('not a date', {4: '2'}), // no ISO shape
          cells('2026-01-01', {4: '1'}), // the good row
        ]),
      );
      expect(result.stats.rowsTotal, 3);
      expect(result.stats.rowsInvalid, 2);
      expect(result.stats.rowsImported, 1);
      expect(result.stats.rowsSkippedEmpty, 0);
    });

    test('stats: total accounting adds up per csv', () {
      final result = dripCsvToExportJson(
        dripCsv(dripHeader, [
          cells('2026-01-01', {4: '2'}),
          cells('2026-01-02', {}), // empty
          cells('bogus', {4: '1'}), // invalid
          cells('2026-01-04', {1: '36.2'}),
        ]),
      );
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
      final row = [
        ...cells('2026-01-01', {7: '2'}),
        'zzz',
        'iq 90',
      ];
      final result = dripCsvToExportJson(dripOneRowCsv(header, row));
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final e = (doc['entries']! as List).first as Map<String, Object?>;
      expect(e['mucus_sign'], 'f');
      expect(
        e.containsKey('desire'),
        isFalse,
        reason:
            'unknown columns carry no data, and the dropped flag '
            'exists nowhere in the v5 shape',
      );
    });

    test('tolerance: missing known columns simply carry no data', () {
      final header = ['date', 'bleeding.value'];
      final result = dripCsvToExportJson(
        dripOneRowCsv(header, ['2026-01-01', '1']),
      );
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final e = (doc['entries']! as List).first as Map<String, Object?>;
      expect(
        e['bleeding'],
        2,
        reason: 'drip value 1 (light) is the stored level 2',
      );
      expect(e['bbt_c'], isNull);
      expect(e['mucus_sign'], isNull);
    });

    test(
      'tolerance: truncated header with longer rows (extra cells dropped)',
      () {
        final header = ['date', 'temperature.value', 'bleeding.value'];
        final result = dripCsvToExportJson(
          dripOneRowCsv(header, const [
            '2026-01-01',
            '36.2',
            '2',
            'junk',
            'more junk',
          ]),
        );
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final e = (doc['entries']! as List).first as Map<String, Object?>;
        expect(e['bbt_c'], 36.2);
        expect(e['bleeding'], 3);
      },
    );

    test('tolerance: short rows are padded with empty cells', () {
      final header = ['date', 'temperature.value', 'bleeding.value'];
      final result = dripCsvToExportJson(
        dripOneRowCsv(header, const ['2026-01-01']),
      );
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['entries'] as List, isEmpty, reason: 'date-only row');
      expect(result.stats.rowsSkippedEmpty, 1);
    });

    test('document shape: current-version profile-free blob with the '
        'derived cycleStart mark', () {
      final result = dripCsvToExportJson(
        dripOneRowCsv(dripHeader, cells('2026-01-01', {4: '2', 1: '36.2'})),
      );
      final doc = jsonDecode(result.json) as Map<String, Object?>;
      expect(doc['schema_version'], exportSchemaVersion);
      // No profile keys anywhere in the document — drip used to write into
      // profile 1; now the document root is exactly version / exported_at /
      // entries / marks.
      expect(doc.containsKey('profiles'), isFalse);
      // A menstruation-level day that is the episode's first day derives a
      // cycleStart mark with author 'import' (bleeding only SUGGESTS a
      // cycle start; the mark is what the boundaries consume).
      expect(doc['marks'], [
        {
          'entry_date': '2026-01-01',
          'mark_type': 'cycleStart',
          'author': 'import',
        },
      ]);
      expect(doc['exported_at'], isA<String>());
      // The produced document passes the shared validator untouched.
      final blob = parseExportJson(result.json);
      expect(blob.entries, hasLength(1));
      final e = blob.entries.single;
      expect(
        e.containsKey('profile_id'),
        isFalse,
        reason: 'no profile dimension exists any more',
      );
      expect(e['date'], '2026-01-01');
      expect(
        e['bleeding'],
        3,
        reason: 'drip value 2 (medium) is the stored level 3',
      );
      expect(e['bbt_c'], 36.2);
    });

    test('fixture: stats accounting on the real 73-row export specimen', () {
      final result = dripCsvToExportJson(dripExportSampleCsv);
      expect(result.stats.rowsTotal, 73);
      expect(result.stats.rowsInvalid, 0);
      expect(
        result.stats.rowsImported,
        27,
        reason:
            '2026-08-20 (desire + mood flags only) imports nothing: '
            'mood/desire are no longer data',
      );
      expect(
        result.stats.rowsSkippedEmpty,
        46,
        reason: '45 blank calendar days + the desire/mood-only day',
      );
      expect(
        result.stats.rowsImported + result.stats.rowsSkippedEmpty,
        result.stats.rowsTotal,
      );

      final doc = jsonDecode(result.json) as Map<String, Object?>;
      final entries = (doc['entries'] as List).cast<Map<dynamic, dynamic>>();
      final marks = (doc['marks'] as List).cast<Map<dynamic, dynamic>>();
      Map by(String date) => entries.where((e) => e['date'] == date).single;
      // mucus day: value 2 ('f') wins over the 2+1 parts, firmness clamps
      expect(by('2026-07-15')['mucus_sign'], 'f');
      expect(
        by('2026-07-15')['cervix'],
        isNull,
        reason:
            'the free-text cervix composite stays dropped; the '
            'firmness index maps only into the structured field',
      );
      expect(
        by('2026-07-15')['cervix_firmness'],
        'soft',
        reason:
            'the specimen firmness index 2 clamps to soft, also '
            'in the structured field',
      );
      // excluded temperature day: the day carries NO raw exclude key and a
      // neutral mask; the exclusion rides as the derived mark instead.
      expect(by('2026-09-13')['temp_disturbances'], 0);
      expect(by('2026-09-13').containsKey('exclude_other'), isFalse);
      expect(by('2026-09-13')['bbt_c'], 36.7);
      expect(by('2026-09-13')['notes'], '[temp] measured late');
      // Deep matcher on the filtered list: json-decoded maps carry no
      // structural ==, so the shape is compared element shape by shape.
      expect(marks.where((m) => m['mark_type'] == 'ignoreTemperature'), [
        {
          'entry_date': '2026-09-13',
          'mark_type': 'ignoreTemperature',
          'author': 'import',
        },
      ], reason: 'temperature.exclude derives the ignore-temperature mark');
      // note-only day
      expect(by('2026-09-15')['notes'], 'cramps again, expecting menses soon.');
      // bleeding + mood-note day (drip value 2 = medium → level 3); the
      // mood FLAG is dropped, the [mood] note stays.
      expect(by('2026-08-31')['bleeding'], 3);
      expect(by('2026-08-31').containsKey('mood'), isFalse);
      expect(by('2026-08-31')['notes'], '[mood] first day jitters');
      // the desire + mood-flag-only day (2026-08-20) is gone entirely
      expect(
        entries.where((e) => e['date'] == '2026-08-20'),
        isEmpty,
        reason: 'a desire/mood-only row is skipped-empty now',
      );
      // Sex observations: partner days without a contraceptive method map
      // to the sex timings mask (an unfilled method column counts as "no
      // method" — owner rule of 2026-09-17). Of the specimen's sex days
      // only 2026-08-16 passes that rule (partner, the only contraceptive
      // info being condom=false/pill=false); 2026-07-17 carries a condom
      // and 2026-09-12 is solo — both stay mask-free.
      final noMethodNamed = by('2026-08-16');
      expect(
        noMethodNamed['sex_timings'],
        SexTiming.middle.bit,
        reason:
            'partner with condom=false/pill=false and nothing else: '
            'no method flag set → the mapped variant',
      );
      final withCondom = by('2026-07-17');
      expect(
        withCondom['sex_timings'],
        0,
        reason: 'partner sex with a condom is not the mapped variant',
      );
      expect(
        withCondom.containsKey('desire'),
        isFalse,
        reason: 'desire is dropped entirely',
      );
      expect(withCondom['notes'], '[sex] with condom, quite good');
      final soloDay = by('2026-09-12');
      expect(soloDay['sex_timings'], 0, reason: 'solo is not partner sex');
      expect(soloDay['notes'], '[sex] morning');
      // breast-pain (B) + pain-note day (drip pain.tenderBreasts → B)
      expect(by('2026-08-25')['pain_breast'], true);
      expect(by('2026-08-25')['pain_mittelschmerz'], false);
      expect(by('2026-08-25')['notes'], '[pain] tender in the evening');
      // temperature measurement times ride through as measured_at_minutes
      expect(
        by('2026-07-05')['measured_at_minutes'],
        7 * 60 + 15,
        reason: 'drip temperature.time 07:15',
      );
      expect(
        by('2026-08-02')['measured_at_minutes'],
        6 * 60 + 50,
        reason: 'drip temperature.time 06:50',
      );
      // a temperature without a recorded time stays null, never fabricated
      expect(
        by('2026-09-13')['measured_at_minutes'],
        isNull,
        reason: '2026-09-13 has a temperature but no time cell',
      );
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

      List<String> timeCells(String date, String value, String time) => [
        date,
        value,
        time,
        '',
      ];

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

      test('a time without a temperature value is not mapped', () {
        // The measured time belongs to its temperature measurement; a row
        // carrying only the time (value deleted in drip, say) maps with the
        // time dropped, never with a stray time that this app would not
        // store either.
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            timeHeader,
            const ['2026-01-01', '', '07:15', '2'], // bleeding keeps the row
          ),
        );
        final doc = jsonDecode(result.json) as Map<String, Object?>;
        final entries = doc['entries']! as List;
        expect(entries, hasLength(1), reason: 'the row itself stays data');
        expect((entries.single as Map)['measured_at_minutes'], isNull);
      });

      test('a dropped temperature.time column stays null', () {
        // Header-driven parser: a drip version that never records the time
        // behaves exactly like an empty cell.
        final e = entryOf(cells('2026-01-01', {1: '36.2'}));
        expect(e['measured_at_minutes'], isNull);
      });

      test('malformed or out-of-range times degrade to null, row survives', () {
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
            dripOneRowCsv(timeHeader, timeCells('2026-01-01', '36.2', bad)),
          );
          final doc = jsonDecode(result.json) as Map<String, Object?>;
          final entries = doc['entries']! as List;
          expect(entries, hasLength(1), reason: '"$bad" must not drop the row');
          expect(
            (entries.single as Map)['measured_at_minutes'],
            isNull,
            reason: '"$bad" is not a recording time',
          );
        }
      });

      test('a time cell alone is not data (row skipped when else empty)', () {
        final timeOnlyHeader = ['date', 'temperature.time'];
        final result = dripCsvToExportJson(
          dripOneRowCsv(timeOnlyHeader, const ['2026-01-01', '07:15']),
        );
        expect(
          result.stats.rowsImported,
          0,
          reason: 'a lone time without its measurement is meaningless',
        );
        expect(result.stats.rowsSkippedEmpty, 1);
      });
    });

    group('cycleStart mark derivation (foreign drip imports)', () {
      /// The marks rows of the produced document, in document order.
      List<Map<String, Object?>> marksOf(DripCsvImport result) =>
          ((jsonDecode(result.json) as Map<String, Object?>)['marks']! as List)
              .cast<Map<String, Object?>>();

      /// The one derived mark shape of this feature: type cycleStart,
      /// author 'import'; the rows carry no profile id (there is none).
      Map<String, Object?> derivedMark(String iso) => {
        'entry_date': iso,
        'mark_type': 'cycleStart',
        'author': 'import',
      };

      /// The derived temperature-ignore mark (drip temperature.exclude →
      /// the ignoreTemperature mark; author 'import').
      Map<String, Object?> exclusionMark(String iso) => {
        'entry_date': iso,
        'mark_type': 'ignoreTemperature',
        'author': 'import',
      };

      /// The cycleStart marks of the produced document.
      List<Map<String, Object?>> cycleStartsOf(DripCsvImport result) =>
          marksOf(result).where((m) => m['mark_type'] == 'cycleStart').toList();

      test('the first menstruation-level day of an episode derives one '
          'cycleStart mark (author import)', () {
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {1: '36.2'}), // tracked, no bleeding
            cells('2026-01-02', {4: '2'}), // medium onset
            cells('2026-01-03', {4: '2'}), // continues the flow
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-02')]);
      });

      test('mid-flow continuation derives nothing (light still continues '
          'the flow)', () {
        // drip 2 → stored level 3 (medium); drip 1 → stored level 2
        // (light). Every stored bleeding level (1–4) both opens and
        // continues a row of bleedings, so only the episode's FIRST day
        // derives a mark; the continuations derive nothing.
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {4: '2'}),
            cells('2026-01-02', {4: '2'}),
            cells('2026-01-03', {4: '1'}),
            cells('2026-01-04', {4: '1'}),
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-01')]);
      });

      test('spotting is bleeding: it continues the flow (the next bleeding '
          'day derives no mark)', () {
        // drip 2 → stored level 3 (medium); drip 0 → stored level 1
        // (spotting). ANY stored bleeding level (1–4) both opens and
        // continues a row of bleedings (spotting is full-coverage
        // bleeding): the spotting day continues 01-01's flow, and 01-03
        // continues the spotting day — only the episode's first day
        // derives a mark.
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {4: '2'}),
            cells('2026-01-02', {4: '0'}),
            cells('2026-01-03', {4: '2'}),
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-01')]);
      });

      test('the hand-authored specimen derives exactly one cycleStart mark '
          'per bleeding episode (three in total) plus the exclusion mark '
          'for the temperature.exclude day', () {
        // The specimen's bleeding sequences: 2026-07-05..09, 2026-08-02..05
        // and 2026-08-30..09-02 — each episode's first day is an onset (the
        // day before it carries no menstruation-level entry), every other
        // bleeding day continues the previous day's flow. NOT one mark for
        // the whole file: one per episode. Additionally the temperature-
        // excluded day (2026-09-13) derives its ignoreTemperature mark.
        final result = dripCsvToExportJson(dripExportSampleCsv);
        expect(cycleStartsOf(result), [
          derivedMark('2026-07-05'),
          derivedMark('2026-08-02'),
          derivedMark('2026-08-30'),
        ]);
        expect(
          marksOf(result).where((m) => m['mark_type'] == 'ignoreTemperature'),
          [exclusionMark('2026-09-13')],
        );
      });

      test('CSV row order never changes the derived marks (day-ordered '
          'replay)', () {
        // The suppression check runs over the DAY order, not the CSV row
        // order: 2026-01-03's menstruation-level row appears BEFORE its
        // prior day's row here, and must still be suppressed by it.
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-03', {4: '2'}),
            cells('2026-01-01', {1: '36.2'}),
            cells('2026-01-02', {4: '2'}),
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-02')]);
      });

      test('duplicated dates follow the merge plan: the first occurrence '
          'wins', () {
        // The merge plan counts duplicate same-day keys once, first
        // occurrence winning; the derivation replay applies the same rule,
        // so the stored (first) shape of the day decides suppression.
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {1: '36.2'}), // first occurrence: no bleeding
            cells('2026-01-01', {4: '2'}), // duplicate: not a counted write
            cells('2026-01-02', {4: '2'}),
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-02')]);
      });

      test('an ignored (temperature-excluded) day derives the mark AND its '
          "own cycleStart suggestion; the next day stays suppressed by "
          "bleeding continuity", () {
        // drip temperature.exclude maps onto the ignoreTemperature MARK
        // (author 'import', no raw exclude key, mask 0). The mark is
        // temperature-evaluation-scoped: it does NOT suppress the
        // suggestion any more — 2026-01-01 (bleeding level 2, no previous
        // bleeding day) SUGGESTS and derives its own cycleStart mark,
        // while 2026-01-02 stays mid-flow (the previous calendar day also
        // BLEEDS, level >= 1) and derives nothing.
        final result = dripCsvToExportJson(
          dripCsv(dripHeader, [
            cells('2026-01-01', {4: '2', 2: 'true'}),
            cells('2026-01-02', {4: '2'}),
          ]),
        );
        expect(
          marksOf(result),
          unorderedEquals([
            derivedMark('2026-01-01'),
            exclusionMark('2026-01-01'),
          ]),
        );
      });

      test('a single menstruation-level day with no other tracked days '
          'derives a mark', () {
        final result = dripCsvToExportJson(
          dripOneRowCsv(dripHeader, cells('2026-01-01', {4: '2'})),
        );
        expect(result.stats.rowsImported, 1);
        expect(marksOf(result), [derivedMark('2026-01-01')]);
      });

      test('a spotting-only bleeding day derives a mark (out-of-range '
          'still does not)', () {
        // Spotting (drip 0) is stored level 1 — full bleeding: it opens a
        // row of bleedings and derives the mark. Out-of-range means no
        // observation (stored level 0): it neither opens nor continues.
        final spotting = dripCsvToExportJson(
          dripOneRowCsv(dripHeader, cells('2026-01-01', {4: '0'})),
        );
        expect(marksOf(spotting), [derivedMark('2026-01-01')]);
        final outOfRange = dripCsvToExportJson(
          dripOneRowCsv(dripHeader, cells('2026-01-01', {4: '7', 1: '36.2'})),
        );
        expect(marksOf(outOfRange), isEmpty);
      });

      test('an excluded bleeding day neither opens nor continues: the next '
          'non-excluded bleeding day is an onset again', () {
        // bleeding.exclude is a replay-skip flag only: the excluded day
        // (01-02, drip 1 → stored level 2) derives no mark, cannot
        // continue 01-01's flow and cannot suppress 01-03 — the next
        // non-excluded bleeding day is a fresh onset. The stored entry
        // keeps its bleeding level either way.
        final result = dripCsvToExportJson(
          dripCsv(bleedingExcludeHeader, [
            bleedingExcludeCells('2026-01-01', value: '2'),
            bleedingExcludeCells('2026-01-02', value: '1', exclude: true),
            bleedingExcludeCells('2026-01-03', value: '1'),
          ]),
        );
        expect(marksOf(result), [
          derivedMark('2026-01-01'),
          derivedMark('2026-01-03'),
        ]);
      });

      test('an excluded FIRST day of a bleeding row derives no mark: the '
          'following calendar day is a fresh onset', () {
        // The row's first day is the excluded one (01-01, drip 1 → stored
        // level 2): it derives nothing and cannot continue/suppress
        // anything — the next non-excluded bleeding day (01-02) is NOT
        // suppressed by it and is a fresh onset itself. The stored entry
        // keeps its bleeding level either way.
        final result = dripCsvToExportJson(
          dripCsv(bleedingExcludeHeader, [
            bleedingExcludeCells('2026-01-01', value: '1', exclude: true),
            bleedingExcludeCells('2026-01-02', value: '1'),
          ]),
        );
        expect(marksOf(result), [derivedMark('2026-01-02')]);
      });

      test('bleeding.exclude never derives an ignoreTemperature mark', () {
        // The ignoreTemperature mark is temperature-only: the bleeding
        // exclusion feeds ONLY the cycleStart replay (where the excluded
        // day is skipped entirely — it cannot open either).
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            bleedingExcludeHeader,
            bleedingExcludeCells('2026-01-01', value: '1', exclude: true),
          ),
        );
        expect(
          marksOf(result).where((m) => m['mark_type'] == 'ignoreTemperature'),
          isEmpty,
        );
        expect(marksOf(result), isEmpty, reason: 'an excluded day cannot open');
      });

      test('a bleeding.exclude-only row is not data (skipped empty)', () {
        // Symmetric to temperature.exclude: the exclusion itself is only
        // meaningful alongside mapped data — without a bleeding value (or
        // another data anchor) the blank calendar day skips as usual.
        final result = dripCsvToExportJson(
          dripOneRowCsv(
            bleedingExcludeHeader,
            bleedingExcludeCells('2026-01-01', exclude: true),
          ),
        );
        expect(result.stats.rowsImported, 0);
        expect(result.stats.rowsSkippedEmpty, 1);
      });
    });
  });
}
