// The PDF's data-less-cycle contract: a mark-opened cycle with no tracked
// days keeps its calendar span (cycleSpanDays: the days from the opening
// mark day to the next mark / today), so the page plan counts that span and
// the sheet renders it as blank columns with day numbers counted from the
// opening mark day.
import 'dart:io';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cycle_pdf_test.dart'
    show PdfTextRun, countPageMarkers, extractPageContent;

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

final _today = d(2026, 9, 28);

/// Three data-less mark cycles in 2020 (no tracked entries anywhere);
/// selecting the first names a cycle whose span the mark arithmetic fixes:
/// Jan 1 -> Jan 31 (the day before the Feb 1 mark).
List<CycleMark> _farPastMarks() => [
  CycleMark(date: d(2020, 1, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(2020, 2, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(2020, 3, 1), type: CycleMarkTypes.cycleStart),
];

/// Read from the checkout rather than rootBundle: the generator takes bare
/// font bytes.
List<int> fixtureFontBytes() =>
    File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();

PdfExportModel emptyCycleModel() => buildPdfExportModel(
  entries: const [],
  marks: _farPastMarks(),
  selectedStartDates: {d(2020, 1, 1)},
  today: _today,
);

/// The scaffold's day-number labels (cycleDayNumberLabel) in the doc's
/// 5.2 pt style — the runs a span-wide blank sheet must carry. (The pdf
/// package splits "1. Tag" at the space into '1.' + 'Tag'; the digit run
/// is the predicate's subject.)
bool _dayNumberRun(PdfTextRun run) =>
    (run.fontSize - 5.2).abs() < 0.05 && RegExp(r'^\d+\.$').hasMatch(run.text);

void main() {
  test('the exported data-less cycle keeps its empty tracked list; its '
      'span is the one the marks fix', () {
    final model = emptyCycleModel();
    expect(model.cycles, hasLength(1));
    expect(model.cycles.single.cycle.days, isEmpty);
    // Jan 1 -> Jan 31: 31 span days, counted from the opening mark day.
    expect(cycleSpanDays(model.cycles.single.cycle).length, 31);
    expect(model.ordinalOf(0), 1);
  });

  test('the data-less span prints as one page whose sheet lists every span '
      'day blank and numbered from the opening mark day', () async {
    final model = emptyCycleModel();
    final bytes = await generatePdfBytes(
      model: model,
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    expect(bytes, isNotEmpty);
    // 31 span days <= the 40-column budget: ever the one page.
    expect(countPageMarkers(bytes), 1);
    final (runs, _) = extractPageContent(bytes);
    expect(
      [
        for (final run in runs)
          if (_dayNumberRun(run)) run.text,
      ],
      [for (var i = 1; i <= 31; i++) '$i.'],
      reason:
          'every span day owns a numbered blank column — one page, '
          'counted from the opening mark day',
    );
    // The header reads the window off the span list (the data-less cycle
    // carries no tracked days at all); the extractor splits the drawn line
    // at spaces.
    final texts = [for (final run in runs) run.text];
    expect(texts, contains('Zykluszeitraum:'));
    expect(texts, contains('01.01.2020'));
    expect(texts, contains('31.01.2020'));
  });

  test('a data-less span beyond the 40-column budget continues onto '
      'further pages, their windows slicing the span list', () async {
    // The last mark cycle (Mar 1, 2020) runs to the pinned today: Mar 1 ->
    // Apr 10 = 41 span days -> pages [40, 1].
    final model = buildPdfExportModel(
      entries: const [],
      marks: _farPastMarks(),
      selectedStartDates: {d(2020, 3, 1)},
      today: d(2020, 4, 10),
    );
    final bytes = await generatePdfBytes(
      model: model,
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    expect(countPageMarkers(bytes), 2);
    final (runs, _) = extractPageContent(bytes, page: 1);
    // The second window's single day is span offset 40: cycle day 41.
    expect(
      [
        for (final run in runs)
          if (_dayNumberRun(run)) run.text,
      ],
      ['41.'],
    );
    // The continuation page repeats the identical scaffold ("Blatt k/n").
    expect(runs.map((r) => r.text), contains('Blatt'));
    expect(runs.map((r) => r.text), contains('2/2'));
  });
}
