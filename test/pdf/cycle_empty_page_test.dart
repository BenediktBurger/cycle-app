// The PDF's empty-cycle page contract: a mark-opened cycle with no tracked
// days is still counted and export-selected, so its sheet must print — as
// one planned blank day, without materializing historical placeholder days.
import 'dart:io';

import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

final _today = d(2026, 9, 28);

/// Mark spans far in the past predate the synthetic-span floor, so their
/// tracked day lists come out empty — the fixture for an empty cycle.
List<CycleMark> _farPastMarks() => [
  CycleMark(date: d(2020, 1, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(2020, 2, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(2020, 3, 1), type: CycleMarkTypes.cycleStart),
];

/// Read from the checkout rather than rootBundle: the generator takes bare
/// font bytes.
List<int> fixtureFontBytes() =>
    File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();

/// Page markers appear verbatim as `/Type/Page/` under `compress: false`;
/// the `/Pages` node's "Page" is followed by "s" and never matches.
int countPageMarkers(List<int> bytes) {
  final pattern = '/Type/Page/'.codeUnits;
  var count = 0;
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    var hit = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        hit = false;
        break;
      }
    }
    if (hit) count++;
  }
  return count;
}

PdfExportModel emptyCycleModel() => buildPdfExportModel(
  entries: const [],
  marks: _farPastMarks(),
  selectedStartDates: {d(2020, 1, 1)},
  today: _today,
);

void main() {
  test('the exported cycles keep the empty days as they are — no '
      'historical materialization sneaks into the model', () {
    final model = emptyCycleModel();
    expect(model.cycles, hasLength(1));
    expect(model.cycles.single.cycle.days, isEmpty);
    expect(model.ordinalOf(0), 1);
  });

  test('a selected empty cycle prints its own blank page — one window, '
      'the planned placeholder day feeding the form grid only', () async {
    final model = emptyCycleModel();
    final bytes = await generatePdfBytes(
      model: model,
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    expect(bytes, isNotEmpty);
    // Exactly one page: nothing drops the empty cycle's sheet.
    expect(countPageMarkers(bytes), 1);
    // Intended: an empty cycle carries no Zykluszeitraum row.
    final facts = pdfHeaderFacts(
      model: model,
      anonymized: false,
      cycleIndex: 0,
    );
    expect(facts.any((f) => f.label == 'Zykluszeitraum'), isFalse);
  });
}
