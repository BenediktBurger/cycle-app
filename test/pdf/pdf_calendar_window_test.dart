// The PDF's calendar-window contract: a page's day columns are the cycle's
// CONSECUTIVE CALENDAR days (cycleCalendarDays, lib/domain/cycle_grouping.dart)
// — untracked days between tracked ones, and between the opening mark and the
// first tracked day, keep their labeled column instead of dropping out of the
// sheet.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_content.dart'
    show PdfTextRun, countPageMarkers, extractPageContent;
import '../support/pdf_fixtures.dart' show fixtureFontBytes;

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

final _today = d(2026, 9, 28);

DailyEntry entry(int y, int m, int day, {Bleeding bleeding = Bleeding.none}) =>
    DailyEntry(date: d(y, m, day), bleeding: bleeding);

CycleMark start(int y, int m, int day) =>
    CycleMark(date: d(y, m, day), type: CycleMarkTypes.cycleStart);

/// One mark-opened cycle (Jan 1 – Jan 31, 2020; the Feb 1 mark bounds it)
/// with tracked entries ONLY on Jan 1 and Jan 10 — the days Jan 2–9 sit
/// untracked between them.
PdfExportModel gappyModel() => buildPdfExportModel(
  entries: [
    entry(2020, 1, 1, bleeding: Bleeding.medium),
    entry(2020, 1, 10),
  ],
  marks: [start(2020, 1, 1), start(2020, 2, 1)],
  selectedStartDates: {d(2020, 1, 1)},
  today: _today,
);

/// Font-size comparisons against rendered runs need a tolerance because
/// the pdf package rounds sizes on export.
const _fontSizeTolerance = 0.05;

/// The scaffold's day-number labels (cycleDayNumberLabel) in the sheet's
/// tiny ink style. (The pdf package splits "1. Tag" at the space into
/// '1.' + 'Tag'; the digit run is the predicate's subject.)
bool _dayNumberRun(PdfTextRun run) =>
    (run.fontSize - pdfTinyFontSize).abs() < _fontSizeTolerance &&
    RegExp(r'^\d+\.$').hasMatch(run.text);

/// The date row's runs: _dateCell's tiny ink sits at fontSize 5 (the
/// day-number row and the rail captions at 5.2, the first-of-month year
/// line at 4.6), so the size filter isolates the month names + dates.
bool _dateRun(PdfTextRun run) => (run.fontSize - 5).abs() < _fontSizeTolerance;

/// The page's day-number labels (cycleDayNumberLabel), parsed back to
/// their numbers so the expectations read as calendar sequences.
List<int> dayNumbersOf(List<PdfTextRun> runs) => [
  for (final run in runs)
    if (_dayNumberRun(run)) int.parse(run.text.replaceAll('.', '')),
];

void main() {
  test('every calendar day of the span owns a day-number column, untracked '
      'days included', () async {
    final bytes = await generatePdfBytes(
      model: gappyModel(),
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    expect(countPageMarkers(bytes), 1);
    final (runs, _) = extractPageContent(bytes);
    expect(
      dayNumbersOf(runs),
      [for (var i = 1; i <= 31; i++) i],
      reason:
          'the sheet lists 31 consecutive calendar days Jan 1–31, the '
          'untracked Jan 2–9 among them',
    );
  });

  test('the date row labels the untracked gap days with their calendar '
      'dates', () async {
    final bytes = await generatePdfBytes(
      model: gappyModel(),
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    final (runs, _) = extractPageContent(bytes);
    expect(
      [
        for (final run in runs)
          if (_dateRun(run)) run.text,
      ],
      ['Jan', for (var i = 2; i <= 31; i++) '$i.'],
      reason:
          'Jan 1 is the window\'s first-of-month column (month stacked '
          'above the year), then every calendar day 2–31 follows — the '
          'untracked Jan 2–9 carry their own dates',
    );
  });

  test('an opening mark before the first tracked day anchors the first '
      'labeled day on the mark day', () async {
    final model = buildPdfExportModel(
      entries: [entry(2020, 1, 4)],
      marks: [start(2020, 1, 1), start(2020, 2, 1)],
      selectedStartDates: {d(2020, 1, 1)},
      today: _today,
    );
    final bytes = await generatePdfBytes(
      model: model,
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    final (runs, _) = extractPageContent(bytes);
    expect(
      [
        for (final run in runs)
          if (_dateRun(run)) run.text,
      ],
      ['Jan', for (var i = 2; i <= 31; i++) '$i.'],
      reason:
          'the first labeled column is the mark day Jan 1 (cycle day 1), '
          'not the first tracked day Jan 4',
    );
  });

  test('a cycle with an interior gap pages by CALENDAR count — day numbers '
      'continue correctly across the page break', () async {
    // Jan 1 – Feb 29, 2020 (the Mar 1 mark bounds it): 60 calendar days;
    // tracked only Jan 1 and Jan 12 — the 10 untracked days Jan 2–11 sit
    // inside. Windows: Jan 1–Feb 9 (40 days), Feb 10–29 (20 days).
    final model = buildPdfExportModel(
      entries: [entry(2020, 1, 1), entry(2020, 1, 12)],
      marks: [start(2020, 1, 1), start(2020, 3, 1)],
      selectedStartDates: {d(2020, 1, 1)},
      today: _today,
    );
    final bytes = await generatePdfBytes(
      model: model,
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
    expect(countPageMarkers(bytes), 2);
    for (final (page, first) in [(0, 1), (1, 41)]) {
      final (runs, _) = extractPageContent(bytes, page: page);
      expect(
        dayNumbersOf(runs),
        [for (var i = first; i < first + 40 && i <= 60; i++) i],
        reason:
            'page ${page + 1}\'s window slices 40 consecutive calendar '
            'days, the day numbers continuing across the page break',
      );
    }
  });
}
