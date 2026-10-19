// Tests of the generated PDF cycle pages: header facts, the merged notes
// band, in-plot chart marks, calendar-window columns and data-less cycles.
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:cycle_app/pdf/pdf_axis.dart';
import 'package:cycle_app/pdf/pdf_layout.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_content.dart'
    show
        PdfInkPath,
        PdfTextRun,
        countPageMarkers,
        extractPageContent,
        firstPageContentStream;
import '../support/pdf_fixtures.dart' show d, fixtureFontBytes;

const _fakeModel = PdfExportModel(
  cycles: [],
  markOpenedIndexes: [0],
  overlays: [],
  observedCyclesOutsideApp: 3,
  name: 'Maria Muster',
  birthDate: null,
  shortestCycleLengths: [27],
  earliestFirstHigherCycleDays: [14],
);

/// Fixture data: two mark-opened cycles (Mar 1..28: 28 days; Mar 29..Apr 28:
/// 31 days), notes on some days with umlauts and non-Latin-1 glyphs.
List<DailyEntry> fixtureEntries() => [
  for (var i = 0; i < 28; i++)
    DailyEntry(
      date: d(3, 1 + i),
      bbtC: 36.0 + (i % 10) / 10,
      notes: i == 3
          ? 'Querdenken im Büro — schöner Tag ß'
          : (i == 10 ? 'Ж α ž' : null),
    ),
  for (var i = 0; i < 31; i++) DailyEntry(date: d(3, 29 + i), bbtC: 36.2),
];

List<CycleMark> fixtureMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 29), type: CycleMarkTypes.cycleStart),
];

PdfExportModel fixtureModel() => buildPdfExportModel(
  entries: fixtureEntries(),
  marks: fixtureMarks(),
  observedCyclesOutsideApp: 3,
  name: 'Maria Muster',
  birthDate: d(12, 24),
  // The span extension runs the LAST cycle out to "today"; the fixture
  // pins the clock at the second cycle's last tracked day so the 2-cycle
  // plan below stays deterministic.
  today: d(4, 28),
);

String valueOf(List<({String label, String value})> facts, String label) =>
    facts.firstWhere((f) => f.label == label).value;

/// All fill-color operations (`r g b rg`) of one page content stream, as
/// channel tuples in emission order. Uncompressed generation emits the
/// colors verbatim; the pdf package's number formatting is absorbed by
/// the comparison tolerance below.
List<List<double>> fillColorTuples(String stream) => [
  for (final match in RegExp(
    r'([0-9.]+) ([0-9.]+) ([0-9.]+) rg',
  ).allMatches(stream))
    [
      double.parse(match.group(1)!),
      double.parse(match.group(2)!),
      double.parse(match.group(3)!),
    ],
];

/// Whether a fill tuple is the weekend shade ([pdfWeekendShade]); the pdf
/// package's number formatting is absorbed by the comparison tolerance.
bool isWeekendShadeFill(List<double> t) {
  bool near(double channel, double reference) =>
      (channel - reference).abs() < 0.002;
  return near(t[0], pdfWeekendShade.red) &&
      near(t[1], pdfWeekendShade.green) &&
      near(t[2], pdfWeekendShade.blue);
}

/// The generated fixture document, uncompressed so the content streams
/// stay verbatim (byte-level checks).
Future<List<int>> generateFixture() => generatePdfBytes(
  model: fixtureModel(),
  fontBytes: fixtureFontBytes(),
  options: PdfExportOptions(anonymized: false),
  compress: false,
);

// ---------------------------------------------------------------------------
// The merged notes-band fixture: day 0 records the full stack (closed
// opening in the low slot + soft firmness + breast pain + note), day 1 an
// unreachable open cervix with the half-soft firmness alone, day 2 breast
// pain + note without any cervix observation and day 3 a middle opening
// in the middle slot alone — on a continuous window (column == calendar
// offset from the Mar 1 cycle start), one page.
// ---------------------------------------------------------------------------

List<DailyEntry> bandFixtureEntries() => [
  DailyEntry(
    date: d(3, 1),
    bbtC: 36.5,
    cervixPosition: CervixPosition.low,
    cervixOpening: CervixOpening.closed,
    cervixFirmness: CervixFirmness.soft,
    painBreast: true,
    notes: 'Erste Notiz',
  ),
  DailyEntry(
    date: d(3, 2),
    bbtC: 36.5,
    cervixPosition: CervixPosition.unreachable,
    cervixOpening: CervixOpening.open,
    cervixFirmness: CervixFirmness.halfSoft,
  ),
  DailyEntry(
    date: d(3, 3),
    bbtC: 36.5,
    painBreast: true,
    notes: 'Zweite Notiz',
  ),
  DailyEntry(
    date: d(3, 4),
    bbtC: 36.5,
    cervixPosition: CervixPosition.medium,
    cervixOpening: CervixOpening.middle,
  ),
  for (var i = 4; i < 14; i++) DailyEntry(date: d(3, 1 + i), bbtC: 36.5),
];

List<CycleMark> bandFixtureMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
];

PdfExportModel bandFixtureModel({
  List<MeasurementMethodSnapshot> measurementSnapshots = const [],
}) => buildPdfExportModel(
  entries: bandFixtureEntries(),
  marks: bandFixtureMarks(),
  measurementSnapshots: measurementSnapshots,
  today: d(3, 14),
);

Future<List<int>> generateBandFixture({
  List<MeasurementMethodSnapshot> measurementSnapshots = const [],
}) => generatePdfBytes(
  model: bandFixtureModel(measurementSnapshots: measurementSnapshots),
  fontBytes: fixtureFontBytes(),
  options: PdfExportOptions(anonymized: false),
  compress: false,
);
// The measurement-method GAP fixture: tracked Mar 1–3 and Mar 7–9 (the
// interior days Mar 4–6 carry no data) — a change dated Mar 5 renders on
// the FIRST TRACKED day at or after it (Mar 7), which owns calendar
// column 6 of the calendar-consecutive window.
List<DailyEntry> gapMethodEntries() => [
  for (var i = 1; i <= 3; i++) DailyEntry(date: d(3, i), bbtC: 36.4),
  for (var i = 7; i <= 9; i++) DailyEntry(date: d(3, i), bbtC: 36.2),
];

PdfExportModel gapMethodModel() => buildPdfExportModel(
  entries: gapMethodEntries(),
  marks: [CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart)],
  measurementSnapshots: [
    MeasurementMethodSnapshot(
      date: DateTime.utc(2026, 2, 20),
      route: MeasurementRoute.vaginal,
    ),
    MeasurementMethodSnapshot(
      date: DateTime.utc(2026, 3, 5),
      route: MeasurementRoute.other,
    ),
  ],
  today: d(3, 9),
);

Future<List<int>> generateGapMethodFixture() => generatePdfBytes(
  model: gapMethodModel(),
  fontBytes: fixtureFontBytes(),
  options: PdfExportOptions(anonymized: false),
  compress: false,
);

// ---------------------------------------------------------------------------
// The in-plot chart-marks fixture: sex (one triple-timing day, one end-only
// day), mucus signs (S with quality, f/S), a mucus-peak mark on the S day and
// a Mittelschmerz day — on a continuous window (column == calendar offset
// from the Mar 1 cycle start), one page.
// ---------------------------------------------------------------------------

List<DailyEntry> markFixtureEntries() => [
  for (var i = 0; i < 14; i++)
    DailyEntry(
      date: d(3, 1 + i),
      bbtC: 36.5,
      sexTimings: i == 2
          ? (SexTiming.morning.bit |
                SexTiming.midday.bit |
                SexTiming.evening.bit)
          : (i == 3 ? SexTiming.evening.bit : 0),
      mucusSign: i == 5 ? MucusSign.s : (i == 6 ? MucusSign.fs : null),
      mucusQuality: i == 5 ? MucusQuality.ew : null,
      painMittelschmerz: i == 8,
    ),
];

List<CycleMark> markFixtureMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 6), type: CycleMarkTypes.mucusPeakDay),
];

PdfExportModel markFixtureModel({TemperatureRange? range}) =>
    buildPdfExportModel(
      entries: markFixtureEntries(),
      marks: markFixtureMarks(),
      temperatureRange: range ?? TemperatureRange.defaults,
      today: d(3, 14),
    );

Future<List<int>> generateMarkFixture({TemperatureRange? range}) =>
    generatePdfBytes(
      model: markFixtureModel(range: range),
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );
// The in-plot day-numbers fixture: six low measurements at 36.2, then the
// first higher on day 7 (marked) — the evaluation numbers the lows 6…1, and
// a mucus S on one low day anchors the rows' relative geometry. One page.
List<DailyEntry> numberFixtureEntries() => [
  for (var i = 0; i <= 7; i++)
    DailyEntry(
      date: d(3, 1 + i),
      bbtC: i <= 5 ? 36.2 : 36.8,
      mucusSign: i == 3 ? MucusSign.s : null,
    ),
];

List<CycleMark> numberFixtureMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 7), type: CycleMarkTypes.firstHigherMeasurement),
];

PdfExportModel numberFixtureModel({TemperatureRange? range}) =>
    buildPdfExportModel(
      entries: numberFixtureEntries(),
      marks: numberFixtureMarks(),
      temperatureRange: range ?? TemperatureRange.defaults,
      today: d(3, 8),
    );

Future<List<int>> generateNumberFixture({TemperatureRange? range}) =>
    generatePdfBytes(
      model: numberFixtureModel(range: range),
      fontBytes: fixtureFontBytes(),
      options: PdfExportOptions(anonymized: false),
      compress: false,
    );

DateTime _calendarDate(int y, int m, int day) => DateTime.utc(y, m, day);

final _calendarToday = _calendarDate(2026, 9, 28);

DailyEntry entry(int y, int m, int day, {Bleeding bleeding = Bleeding.none}) =>
    DailyEntry(date: _calendarDate(y, m, day), bleeding: bleeding);

CycleMark start(int y, int m, int day) =>
    CycleMark(date: _calendarDate(y, m, day), type: CycleMarkTypes.cycleStart);

/// One mark-opened cycle (Jan 1 – Jan 31, 2020; the Feb 1 mark bounds it)
/// with tracked entries ONLY on Jan 1 and Jan 10 — the days Jan 2–9 sit
/// untracked between them.
PdfExportModel gappyModel() => buildPdfExportModel(
  entries: [
    entry(2020, 1, 1, bleeding: Bleeding.medium),
    entry(2020, 1, 10),
  ],
  marks: [start(2020, 1, 1), start(2020, 2, 1)],
  selectedStartDates: {_calendarDate(2020, 1, 1)},
  today: _calendarToday,
);

/// Font-size comparisons against rendered runs need a tolerance because
/// the pdf package rounds sizes on export.
const _fontSizeTolerance = 0.05;

/// The scaffold's day-number labels (cycleDayNumberLabel) in the sheet's
/// tiny ink style. (The pdf package splits "1. Tag" at the space into
/// '1.' + 'Tag'; the digit run is the predicate's subject.)
bool _calendarDayNumberRun(PdfTextRun run) =>
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
    if (_calendarDayNumberRun(run)) int.parse(run.text.replaceAll('.', '')),
];

DateTime _emptyDate(int y, int m, int day) => DateTime.utc(y, m, day);

final _emptyToday = _emptyDate(2026, 9, 28);

/// Three data-less mark cycles in 2020 (no tracked entries anywhere);
/// selecting the first names a cycle whose span the mark arithmetic fixes:
/// Jan 1 -> Jan 31 (the day before the Feb 1 mark).
List<CycleMark> _farPastMarks() => [
  CycleMark(date: _emptyDate(2020, 1, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: _emptyDate(2020, 2, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: _emptyDate(2020, 3, 1), type: CycleMarkTypes.cycleStart),
];

PdfExportModel emptyCycleModel() => buildPdfExportModel(
  entries: const [],
  marks: _farPastMarks(),
  selectedStartDates: {_emptyDate(2020, 1, 1)},
  today: _emptyToday,
);

/// The scaffold's day-number labels (cycleDayNumberLabel) in the sheet's
/// tiny ink style — the runs a span-wide blank sheet must carry. (The pdf
/// package splits "1. Tag" at the space into '1.' + 'Tag'; the digit run
/// is the predicate's subject.)
bool _emptyDayNumberRun(PdfTextRun run) =>
    (run.fontSize - pdfTinyFontSize).abs() < 0.05 &&
    RegExp(r'^\d+\.$').hasMatch(run.text);

void main() {
  group('header facts (pure)', () {
    test('a named export shows the identifying values and the numbers', () {
      final facts = pdfHeaderFacts(
        model: _fakeModel,
        anonymized: false,
        cycleIndex: 0,
      );

      expect(valueOf(facts, 'Name'), 'Maria Muster');
      // No birth date stored: the "—" convention.
      expect(valueOf(facts, 'Geburtsdatum'), '—');
      // The count is the page's ordinal (the "Zyklus" line's exact source
      // figure): outside-app 3 + this cycle's 0-based index 0 + 1.
      expect(valueOf(facts, 'Beobachtete Zyklen'), '4');
      expect(valueOf(facts, 'Kürzester Zyklus'), '27 Tage');
      expect(valueOf(facts, 'Früheste erste höhere Messung'), 'Zyklustag 14');
    });

    test('a stored birth date is formatted as the German calendar date', () {
      final model = PdfExportModel(
        cycles: const [],
        markOpenedIndexes: const [0],
        overlays: const [],
        observedCyclesOutsideApp: 0,
        name: null,
        birthDate: DateTime.utc(1980, 12, 24),
        shortestCycleLengths: [null],
        earliestFirstHigherCycleDays: [null],
      );
      final facts = pdfHeaderFacts(
        model: model,
        anonymized: false,
        cycleIndex: 0,
      );

      expect(valueOf(facts, 'Name'), '—');
      expect(valueOf(facts, 'Geburtsdatum'), '24.12.1980');
      // The count-up can never be empty: it IS the cycle's ordinal (≥ 1).
      expect(valueOf(facts, 'Beobachtete Zyklen'), '1');
      // A first cycle has no completed earlier cycle and no earlier rise:
      // the "—" convention on both statistics.
      expect(valueOf(facts, 'Kürzester Zyklus'), '—');
      expect(valueOf(facts, 'Früheste erste höhere Messung'), '—');
    });

    test('the anonymize toggle hides name and birth date REGARDLESS of the '
        'stored settings and marks the document', () {
      final facts = pdfHeaderFacts(
        model: _fakeModel,
        anonymized: true,
        cycleIndex: 0,
      );

      expect(
        valueOf(facts, 'Name'),
        'anonymisiert',
        reason: 'the stored name must never reach the document',
      );
      expect(
        valueOf(facts, 'Geburtsdatum'),
        '—',
        reason: 'the birth date stays hidden, even when stored',
      );
      expect(
        facts.map((f) => f.value),
        isNot(contains('Maria Muster')),
        reason: 'no identifying value anywhere in the header facts',
      );
      expect(
        facts.any(
          (f) => f.label == 'Anonymisierung' && f.value == 'anonymisiert',
        ),
        isTrue,
        reason: 'the marker line states that the export was anonymized',
      );
    });

    test('the earliest header fact prints "—" when the record fact has no '
        'umrandete value', () {
      final model = PdfExportModel(
        cycles: const [],
        markOpenedIndexes: const [0],
        overlays: const [],
        observedCyclesOutsideApp: 0,
        name: null,
        birthDate: null,
        shortestCycleLengths: [28],
        earliestFirstHigherCycleDays: [null],
      );
      final facts = pdfHeaderFacts(
        model: model,
        anonymized: false,
        cycleIndex: 0,
      );
      expect(valueOf(facts, 'Früheste erste höhere Messung'), '—');
    });

    test('the earliest header fact prints the record\'s umrandete figure '
        'as is — the header never derives a figure of its own', () {
      final model = PdfExportModel(
        cycles: const [],
        markOpenedIndexes: const [0],
        overlays: const [],
        observedCyclesOutsideApp: 0,
        name: null,
        birthDate: null,
        shortestCycleLengths: [28],
        earliestFirstHigherCycleDays: [14],
      );
      final facts = pdfHeaderFacts(
        model: model,
        anonymized: false,
        cycleIndex: 0,
      );
      expect(valueOf(facts, 'Früheste erste höhere Messung'), 'Zyklustag 14');
    });

    test('the three cumulative facts are read PER CYCLE at the given '
        'cycleIndex (the paper-form count-up point of view)', () {
      final model = PdfExportModel(
        cycles: const [],
        markOpenedIndexes: const [0, 1],
        overlays: const [],
        observedCyclesOutsideApp: 0,
        name: null,
        birthDate: null,
        shortestCycleLengths: [27, 25],
        earliestFirstHigherCycleDays: [14, 12],
      );
      final first = pdfHeaderFacts(
        model: model,
        anonymized: false,
        cycleIndex: 0,
      );
      final second = pdfHeaderFacts(
        model: model,
        anonymized: false,
        cycleIndex: 1,
      );
      expect(valueOf(first, 'Beobachtete Zyklen'), '1');
      expect(valueOf(first, 'Kürzester Zyklus'), '27 Tage');
      expect(valueOf(first, 'Früheste erste höhere Messung'), 'Zyklustag 14');
      expect(valueOf(second, 'Beobachtete Zyklen'), '2');
      expect(valueOf(second, 'Kürzester Zyklus'), '25 Tage');
      expect(valueOf(second, 'Früheste erste höhere Messung'), 'Zyklustag 12');
    });

    test('"Beobachtete Zyklen" is the SAME source figure as the "Zyklus N" '
        'header line: model.ordinalOf(cycleIndex) — the count and the '
        'cycle number cannot drift', () {
      final facts = pdfHeaderFacts(
        model: _fakeModel,
        anonymized: false,
        cycleIndex: 0,
      );
      expect(
        valueOf(facts, 'Beobachtete Zyklen'),
        '${_fakeModel.ordinalOf(0)}',
      );
    });

    group('the measurement-method fact (Messmethode line)', () {
      PdfExportModel methodModel(
        ({MeasurementRoute route, String? thermometer})? fact,
      ) => PdfExportModel(
        cycles: const [],
        markOpenedIndexes: const [0],
        overlays: const [],
        observedCyclesOutsideApp: 0,
        name: null,
        birthDate: null,
        shortestCycleLengths: [null],
        earliestFirstHigherCycleDays: [null],
        measurementMethods: [fact],
      );

      test('the fact prints the German route wording and the thermometer '
          'name; it is NOT a person identifier (it stays when anonymized)', () {
        expect(
          valueOf(
            pdfHeaderFacts(
              model: methodModel((
                route: MeasurementRoute.vaginal,
                thermometer: 'ThermaPen',
              )),
              anonymized: false,
              cycleIndex: 0,
            ),
            'Messmethode',
          ),
          'vaginal, ThermaPen',
        );
        expect(
          valueOf(
            pdfHeaderFacts(
              model: methodModel((
                route: MeasurementRoute.vaginal,
                thermometer: 'ThermaPen',
              )),
              anonymized: true,
              cycleIndex: 0,
            ),
            'Messmethode',
          ),
          'vaginal, ThermaPen',
        );
      });

      test('a fact without a thermometer prints the route alone', () {
        expect(
          valueOf(
            pdfHeaderFacts(
              model: methodModel((
                route: MeasurementRoute.rectal,
                thermometer: null,
              )),
              anonymized: false,
              cycleIndex: 0,
            ),
            'Messmethode',
          ),
          'rektal',
        );
      });

      test('a cycle without the fact (no governing snapshot, no temperature) '
          'keeps the "—" convention', () {
        expect(
          valueOf(
            pdfHeaderFacts(
              model: methodModel(null),
              anonymized: false,
              cycleIndex: 0,
            ),
            'Messmethode',
          ),
          '—',
        );
      });

      test('a model with fewer facts than cycles (shorter list) renders '
          '"—" instead of throwing', () {
        expect(
          valueOf(
            pdfHeaderFacts(model: _fakeModel, anonymized: false, cycleIndex: 0),
            'Messmethode',
          ),
          '—',
        );
      });
    });

    group('the observation window fact (Zykluszeitraum)', () {
      test('the window row carries the exported cycle\'s dates WITH year', () {
        final facts = pdfHeaderFacts(
          model: _fakeModel,
          anonymized: false,
          cycleIndex: 0,
          cycleWindow: (
            first: DateTime.utc(2026, 3, 1),
            last: DateTime.utc(2026, 3, 28),
          ),
        );
        expect(valueOf(facts, 'Zykluszeitraum'), '01.03.2026 – 28.03.2026');
      });

      test('the observation window fact (with year) stays on the anonymized '
          'export too', () {
        final facts = pdfHeaderFacts(
          model: _fakeModel,
          anonymized: true,
          cycleIndex: 0,
          cycleWindow: (
            first: DateTime.utc(2026, 3, 29),
            last: DateTime.utc(2026, 5, 2),
          ),
        );
        expect(valueOf(facts, 'Zykluszeitraum'), '29.03.2026 – 02.05.2026');
      });

      test('a page outside any cycle facts (degenerate) keeps the "—"', () {
        final facts = pdfHeaderFacts(
          model: _fakeModel,
          anonymized: false,
          cycleIndex: 0,
        );
        expect(
          facts.any((f) => f.label == 'Zykluszeitraum'),
          isFalse,
          reason: 'no window was carried — the fact row never renders',
        );
      });
    });
  });

  group('the header fact lines on the rendered page', () {
    test('every fact label of page 1 renders inside the fixed 58 pt '
        'header band', () async {
      final model = fixtureModel();
      final span = cycleSpanDays(model.cycles.first.cycle);
      final labels = [
        for (final fact in pdfHeaderFacts(
          model: model,
          anonymized: false,
          cycleIndex: 0,
          cycleWindow: (first: span.first.date, last: span.last.date),
        ))
          fact.label,
      ];
      expect(labels, isNotEmpty, reason: 'the fixture must carry facts to pin');
      final bytes = await generateFixture();
      final (runs, _) = extractPageContent(bytes);
      // The fact lines paint at the header font inside the top header
      // block: the A4 landscape page height (PdfPageFormat.a4.landscape,
      // inline in cycle_pdf.dart's page builder) minus the page margin and
      // the header height; fragments join in paint order, the lost TJ
      // spaces stripped.
      final bandTop = 595 - pdfPageMargin - pdfHeaderHeight;
      final factText = [
        for (final run in runs)
          if ((run.fontSize - pdfHeaderFactFontSize).abs() < 0.05 &&
              run.y > bandTop)
            run.text,
      ].join().replaceAll(' ', '');
      for (final label in labels) {
        expect(
          factText,
          contains("${label.replaceAll(' ', '')}:"),
          reason: 'the fact line "$label" survives the fixed header height',
        );
      }
    });
  });

  group('weekend shading (the cycle tab\'s weekend bands, print-friendly)', () {
    // The fixture's first cycle runs Mar 1–28 2026 — Mar 1 is a SUNDAY, so
    // the tracked weekend dates are 1, 7, 8, 14, 15, 21, 22, 28 and the
    // bands occupy window positions 0, 6, 7, 13, 14, 20, 21, 27.
    test('the generated page carries fills in the light-gray weekend '
        'shade — repeated: one band through EVERY scaffold row per '
        'weekend column', () async {
      final bytes = await generateFixture();
      final tuples = fillColorTuples(firstPageContentStream(bytes));
      final weekendFills = [
        for (final t in tuples)
          if (isWeekendShadeFill(t)) t,
      ];
      expect(weekendFills, isNotEmpty);
      // Cycle 1's page: 8 weekend columns × the rows the band runs
      // through (day numbers … notes area) plus the painted plot bands —
      // well above 8 fill emissions.
      expect(weekendFills.length, greaterThanOrEqualTo(8));
    });
  });

  group('cycle-day numbering (calendar offsets from the cycle start)', () {
    test("'1. Tag' labels the start day; the numbers keep counting per "
        'calendar day on the normal, gapless fixture', () {
      final cycleOne = fixtureModel().cycles.first;
      final cycleStart = DateOnly.normalize(cycleOne.cycle.startDate);
      expect(
        [
          for (final day in cycleOne.cycle.days.take(3))
            cycleDayNumberLabel(DateOnly.daysBetween(day.date, cycleStart)),
        ],
        ['1. Tag', '2.', '3.'],
        reason: 'the tracked date at offset k labels cycle day k + 1',
      );
    });

    test('a cycleStart mark on an untracked gap day (start BEFORE the first '
        'tracked day): the first column still labels the calendar cycle '
        'day, and the columns behind an interior untracked gap show the '
        'correct offset', () {
      // The mark is placed Apr 1, but the first TRACKED day is Apr 2; the
      // tracked list then skips Apr 4–6 (an interior untracked gap). The
      // labels must follow the CALENDAR offsets from the mark — never the
      // tracked positions (which would print "1." with a lost day).
      final entries = [
        DailyEntry(date: d(4, 2), bbtC: 36.5),
        DailyEntry(date: d(4, 3), bbtC: 36.4),
        DailyEntry(date: d(4, 7), bbtC: 36.5),
        DailyEntry(date: d(4, 8), bbtC: 36.6),
      ];
      final marks = [CycleMark(date: d(4, 1), type: CycleMarkTypes.cycleStart)];
      final model = buildPdfExportModel(entries: entries, marks: marks);
      final cycle = model.cycles.single;
      final cycleStart = DateOnly.normalize(cycle.cycle.startDate);
      expect(
        cycleStart,
        d(4, 1),
        reason:
            'the opening mark anchors the cycle a day BEFORE the first '
            'tracked day — offsets from it must count that gap day',
      );
      // The first page window's leading columns, labeled exactly the way
      // the day-number row labels them (offset from the cycle start).
      expect(
        [
          for (final day in cycle.cycle.days.take(4))
            cycleDayNumberLabel(DateOnly.daysBetween(day.date, cycleStart)),
        ],
        ['2.', '3.', '7.', '8.'],
        reason:
            'the untracked Apr 4–6 own no column; the next tracked '
            'column (Apr 7) carries the calendar cycle day 7',
      );
    });
  });

  group('generated bytes (smoke)', () {
    test(
      'the byte stream is non-empty and starts with the PDF signature',
      () async {
        final bytes = await generateFixture();
        expect(bytes, isNotEmpty);
        final signature = '%PDF-'.codeUnits;
        for (var i = 0; i < signature.length; i++) {
          expect(bytes[i], signature[i]);
        }
      },
    );

    test('the document page count equals the layout planner split (1 cycle '
        'per page under the 40-column budget: 28-day -> 1 page, '
        '31-day -> 1 page)', () async {
      final bytes = await generateFixture();
      final plan = planCyclePages(
        fixtureModel().cycles
            .map((e) => cycleSpanDays(e.cycle).length)
            .toList(),
      );
      expect(plan.length, 2);
      expect(countPageMarkers(bytes), plan.length);
    });

    test('notes with umlauts and non-Latin-1 glyphs survive the generation '
        '(bundled TTF registered as base font)', () async {
      final bytes = await generateFixture();
      final (runs, _) = extractPageContent(bytes);
      // TJ runs split at spaces; the space-free join makes each note cell's
      // words contiguous in the extracted text again.
      final text = runs.map((r) => r.text).join().replaceAll(' ', '');
      expect(
        text,
        contains('Жαž'),
        reason: 'Cyrillic/Greek glyphs render via the registered TTF',
      );
      expect(
        text,
        contains('QuerdenkenimBüro—schönerTagß'),
        reason: 'umlauts and the dashes/ß render via the registered TTF',
      );
    });
  });

  group('merged notes band (cervix zones, pain and notes in one row)', () {
    const x0 = pdfPageMargin + pdfRailWidth;

    double runYOf(List<PdfTextRun> runs, String exact) => runs
        .firstWhere(
          (r) => r.text == exact,
          orElse: () => throw TestFailure('no "$exact" text run rendered'),
        )
        .y;

    /// The painted cervix openings: the filled ink-dark circles (the
    /// closed dot fills; the outlined rings stroke and don't fill), ONE
    /// per cervix day, in the merged band's region (below the disturbance
    /// row's caption — the temperature dots live above it).
    List<PdfInkPath> bandDots(List<PdfInkPath> paths, double bandTopY) => [
      for (final p in paths)
        if (p.color.every((c) => c <= 0.2) &&
            (p.maxX - p.minX) >= 3.4 &&
            (p.maxX - p.minX) <= 4.6 &&
            ((p.maxX - p.minX) - (p.maxY - p.minY)).abs() <= 1 &&
            p.maxY < bandTopY)
          p,
    ];

    /// The painted cervix rings: the stroked ink circles (see [bandDots]
    /// for the closed dot's fill counterpart), gated into the merged
    /// band's region the same way.
    List<PdfInkPath> bandRings(List<PdfInkPath> paths, double bandTopY) => [
      for (final p in paths)
        if (p.color.every((c) => c <= 0.2) &&
            (p.maxX - p.minX) >= 5 &&
            (p.maxX - p.minX) <= 9 &&
            ((p.maxX - p.minX) - (p.maxY - p.minY)).abs() <= 1 &&
            p.maxY < bandTopY)
          p,
    ];

    test('the band columns carry the cervix letters and the pain B at the '
        'tiny ink size, like the cycle tab\'s glyph rows', () async {
      final bytes = await generateBandFixture();
      final (runs, _) = extractPageContent(bytes);
      List<PdfTextRun> byText(String text, double size) => runs
          .where((r) => r.text == text && (r.fontSize - size).abs() < 0.05)
          .toList();
      expect(
        byText('w', pdfTinyFontSize),
        isNotEmpty,
        reason: "day 0's soft firmness 'w' renders its letter",
      );
      expect(
        byText('h-w', pdfTinyFontSize),
        isNotEmpty,
        reason: "day 1's halfSoft firmness 'h-w' renders its letter",
      );
      expect(
        byText('B', pdfTinyFontSize),
        isNotEmpty,
        reason: "the breast-pain days' B renders in the band's pain zone",
      );
    });

    test('the middle and open openings paint their outlined rings in their '
        'day columns inside the band, sized 6 / 8 pt like the screen '
        'shapes', () async {
      final bytes = await generateBandFixture();
      final (runs, paths) = extractPageContent(bytes);
      final stoerungY = runYOf(runs, 'Störung');
      final rings = bandRings(paths, stoerungY);
      List<PdfInkPath> ringsIn(int column) => [
        for (final p in rings)
          if ((p.minX + p.maxX) / 2 > x0 + column * pdfColumnWidth + 1 &&
              (p.minX + p.maxX) / 2 < x0 + (column + 1) * pdfColumnWidth - 1)
            p,
      ];
      expect(
        ringsIn(2),
        isEmpty,
        reason: "day 2 records no cervix opening — the band paints no rings",
      );
      final middleRing = ringsIn(3).single;
      expect(
        middleRing.maxX - middleRing.minX,
        closeTo(cervixMiddleCircleSize, 0.05),
        reason: "day 3's middle opening paints the 6 pt circle's width",
      );
      expect(
        middleRing.maxY - middleRing.minY,
        closeTo(cervixMiddleCircleSize, 0.05),
        reason: "day 3's middle ring paints square",
      );
      final openRing = ringsIn(1).single;
      expect(
        openRing.maxX - openRing.minX,
        closeTo(cervixOpenCircleSize, 0.05),
        reason: "day 1's open opening paints the 8 pt circle's width",
      );
      expect(
        openRing.maxY - openRing.minY,
        closeTo(cervixOpenCircleSize, 0.05),
        reason: "day 1's open ring paints square",
      );
    });

    test('the closed opening paints its dot in its day column inside the '
        'band; the cervix-free day paints none', () async {
      final bytes = await generateBandFixture();
      final (runs, paths) = extractPageContent(bytes);
      final stoerungY = runYOf(runs, 'Störung');
      final dots = bandDots(paths, stoerungY);
      final day0Dots = [
        for (final p in dots)
          if ((p.minX + p.maxX) / 2 > x0 + 0 * pdfColumnWidth + 1 &&
              (p.minX + p.maxX) / 2 < x0 + 1 * pdfColumnWidth - 1)
            p,
      ];
      expect(
        day0Dots,
        hasLength(1),
        reason: "day 0's closed opening paints exactly one filled 4 pt dot",
      );
      final day2Dots = [
        for (final p in dots)
          if ((p.minX + p.maxX) / 2 > x0 + 2 * pdfColumnWidth + 1 &&
              (p.minX + p.maxX) / 2 < x0 + 3 * pdfColumnWidth - 1)
            p,
      ];
      expect(
        day2Dots,
        isEmpty,
        reason: "day 2 records no cervix — the band paints no circles",
      );
    });

    test(
      'the note text anchors at its zone top, like the cycle tab\'s '
      'reading direction (the vertical line reads starting at the top)',
      () async {
        final bytes = await generateBandFixture();
        final (runs, _) = extractPageContent(bytes);
        // The caption sits at the band's top edge; a top-anchored note's
        // first glyph lands a note zone's worth below it — the cervix-free
        // pain day's noteTop is 12 pt (pain row only). The TJ runs split
        // words, so the lookup anchors on the notes' FIRST fragments (the
        // fragment of the line's start).
        final captionY = runYOf(runs, pdfRailCaptionNotesBand);
        final day2NoteY = runs
            .firstWhere(
              (r) =>
                  r.text.contains('Zweite') &&
                  (r.fontSize - pdfTinyFontSize).abs() < 0.05,
              orElse: () => throw TestFailure(
                "no day-2 note text run ('Zweite' fragment) rendered",
              ),
            )
            .y;
        expect(
          captionY - day2NoteY,
          lessThan(20),
          reason:
              'the note starts at the top of its zone, a pain row below '
              "the band's caption — not mid-band as a centered/bottom-up "
              'line would place it',
        );
        // The cervix-stack day's note sits below the full 48 pt top block.
        final day0NoteY = runs
            .firstWhere(
              (r) =>
                  r.text.contains('Erste') &&
                  (r.fontSize - pdfTinyFontSize).abs() < 0.05,
              orElse: () => throw TestFailure(
                "no day-0 note text run ('Erste' fragment) rendered",
              ),
            )
            .y;
        expect(
          captionY - day0NoteY,
          inInclusiveRange(40, 65),
          reason:
              "day 0's note starts below the 26 pt glyph zone, 10 pt letter "
              'row and 12 pt pain row (~48 pt)',
        );
      },
    );
  });

  group('measurement method: band note (render-time synthesis)', () {
    const x0 = pdfPageMargin + pdfRailWidth;

    /// The tiny ink runs whose line sits in [column]'s x window at the
    /// band's own height, joined in reading order (a rotated vertical line
    /// descends the page, so the earlier fragments have the larger y).
    /// The threshold reaches a hairline past the band's top edge (the
    /// first rotated glyph's baseline does too); the rows ABOVE the band
    /// (day numbers, values, times) sit clearly higher on the page and
    /// never fall in. Word runs the TJ operator split lose their
    /// separating spaces — comparisons strip them ([compact]).
    String cellText(List<PdfTextRun> runs, int column) {
      final bandTopY =
          runs.firstWhere((r) => r.text == pdfRailCaptionNotesBand).y + 7;
      final left = x0 + column * pdfColumnWidth;
      final fragments =
          runs
              .where((r) => (r.fontSize - pdfTinyFontSize).abs() < 0.05)
              .where((r) => r.y < bandTopY)
              .where((r) => r.x > left && r.x < left + pdfColumnWidth)
              .toList()
            ..sort((a, b) => b.y.compareTo(a.y));
      return fragments.map((r) => r.text).join();
    }

    /// [s] with the TJ split's lost spaces removed.
    String compact(String s) => s.replaceAll(' ', '');

    test('a change day WITH user notes renders note and synthesis as one '
        'cell text, joined by the em-dash separator', () async {
      final bytes = await generateBandFixture(
        measurementSnapshots: [
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 2, 20),
            route: MeasurementRoute.vaginal,
            thermometer: 'ThermaPen',
          ),
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 3, 3),
            route: MeasurementRoute.rectal,
          ),
        ],
      );
      final (runs, _) = extractPageContent(bytes);
      expect(
        compact(cellText(runs, 2)),
        'BZweiteNotiz—rektal',
        reason:
            "day 2 (Mar 3) carries the note AND the snapshot day's synthesis "
            "(the day's own 'B' pain letter rides the zone above)",
      );
    });

    test('a snapshot day whose snapshot names a thermometer renders the '
        'name after the route word', () async {
      final bytes = await generateBandFixture(
        measurementSnapshots: [
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 2, 20),
            route: MeasurementRoute.vaginal,
          ),
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 3, 3),
            route: MeasurementRoute.rectal,
            thermometer: 'ThermaPen',
          ),
        ],
      );
      final (runs, _) = extractPageContent(bytes);
      expect(
        compact(cellText(runs, 2)),
        'BZweiteNotiz—rektal,ThermaPen',
        reason: 'the band note carries the snapshot\'s name like the fact line',
      );
    });

    test('a change date marks exactly ONE band column: the neighboring '
        'columns render no synthesis', () async {
      final bytes = await generateBandFixture(
        measurementSnapshots: [
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 2, 20),
            route: MeasurementRoute.vaginal,
            thermometer: 'ThermaPen',
          ),
          MeasurementMethodSnapshot(
            date: DateTime.utc(2026, 3, 3),
            route: MeasurementRoute.rectal,
          ),
        ],
      );
      final (runs, _) = extractPageContent(bytes);
      expect(
        cellText(runs, 0),
        isNot(contains('rektal')),
        reason:
            "day 0 (Mar 1): the governing snapshot predates the cycle start "
            "so it does not echo — its note stays alone",
      );
      expect(
        cellText(runs, 3),
        isEmpty,
        reason: "day 3 (Mar 4) carries neither a note nor a synthesis",
      );
    });

    test('the synthesized text keeps the MODEL untouched: the fixture day '
        'still carries its stored note after a full generation', () async {
      final model = bandFixtureModel(
        measurementSnapshots: [
          MeasurementMethodSnapshot(
            date: d(2, 20),
            route: MeasurementRoute.vaginal,
            thermometer: 'ThermaPen',
          ),
          MeasurementMethodSnapshot(
            date: d(3, 3),
            route: MeasurementRoute.rectal,
          ),
        ],
      );
      final noteDay = model.cycles[0].cycle.days
          .where((e) => DateOnly.sameDay(e.date, d(3, 3)))
          .single;
      expect(
        noteDay.notes,
        'Zweite Notiz',
        reason: 'the synthesis joins at RENDER time only',
      );
    });

    test('a change on an untracked mid-span gap day renders on the FIRST '
        'tracked day at or after it (its own calendar column)', () async {
      final bytes = await generateGapMethodFixture();
      final (runs, _) = extractPageContent(bytes);
      // Mar 7 is the window's 7th calendar day => column 6 of the single
      // page. The Mar 5 snapshot's synthesis alone fills that noteless
      // cell; the gap day Mar 5 owns a column but carries no note.
      expect(
        compact(cellText(runs, 6)),
        'andere',
        reason:
            'the note joins the first TRACKED day at/after the snapshot '
            'date (Mar 7) — the derivation keys tracked span days, never '
            'the data-less gap day itself',
      );
      expect(
        cellText(runs, 5),
        isEmpty,
        reason: "no synthesis lands on the snapshot day's NEIGHBOR",
      );
      // Page-plan exactness: the synthesis rides the EXISTING band row.
      expect(countPageMarkers(bytes), 1);
    });

    test('a change whose column lies BEYOND the first page window renders '
        'in the later window\'s column (the synthesis follows the page '
        'plan)', () async {
      final entries = [
        for (var i = 1; i <= 45; i++) DailyEntry(date: d(3, i), bbtC: 36.2),
      ];
      final change = MeasurementMethodSnapshot(
        date: d(3, 42),
        route: MeasurementRoute.other,
      );
      final model = buildPdfExportModel(
        entries: entries,
        marks: [CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart)],
        measurementSnapshots: [
          MeasurementMethodSnapshot(
            date: d(2, 20),
            route: MeasurementRoute.vaginal,
          ),
          change,
        ],
        today: d(3, 45),
      );
      // 45 span days: page 1 holds the window offsets 0..39, the change
      // (Mar 42, offset 41) rides page 2's column 1.
      expect(model.overlays[0].methodChanges, {41: change});
      final bytes = await generatePdfBytes(
        model: model,
        fontBytes: fixtureFontBytes(),
        options: PdfExportOptions(anonymized: false),
        compress: false,
      );
      expect(countPageMarkers(bytes), 2);
      final (runs, _) = extractPageContent(bytes, page: 1);
      final page2Text = runs
          .where((r) => (r.fontSize - pdfTinyFontSize).abs() < 0.05)
          .map((r) => r.text)
          .join(' ');
      expect(page2Text, contains('andere'));
      expect(
        page2Text,
        isNot(contains('Messmethode')),
        reason: 'the band note is the route word alone, no label prefix',
      );
    });
  });

  group(
    'in-plot chart marks (sex X / mucus letters / peak dot / M / day numbers)',
    () {
      // The settled geometry: the text glyph rows pitch between the 0.1 °C
      // grid lines, BELOW the plot's top border (the chart-marks row
      // offsets at the sex X / peak dot / letters / Mittelschmerz M
      // pitches), while the day numbers anchor from the BOTTOM at
      // min + the day-numbers pitch — all INSIDE the plot. The page's
      // pinned row seams frame the plot REGION: the bleeding row's caption
      // above, the temperature value row's below (the sheet's strip rows
      // end at bleeding — the M and the numbers are in-plot glyphs).
      // Rail-bound page x: the page margin + the rail + the day fraction ×
      // pdfColumnWidth.
      const x0 = pdfPageMargin + pdfRailWidth;
      const plotHeightPt = pdfCurvePlotHeight;
      final defaultSpan = TemperatureRange.defaults.span;
      // The letters' center sits span − (mucus + day-numbers pitches)
      // above the numbers' center; the two rows' ink baselines track that
      // gap on the plot's °C scale.
      final lettersToNumbersGapPt =
          (defaultSpan - (mucusRowCenterOffsetK + dayNumbersRowCenterOffsetK)) *
          plotHeightPt /
          defaultSpan;

      double runY(List<PdfTextRun> runs, String exact) => runs
          .firstWhere(
            (r) => r.text == exact,
            orElse: () => throw TestFailure('no "$exact" text run rendered'),
          )
          .y;
      PdfTextRun? runOf(List<PdfTextRun> runs, String exact, double fontSize) =>
          runs
              .where(
                (r) => r.text == exact && (r.fontSize - fontSize).abs() < 0.05,
              )
              .firstOrNull;

      /// The small accent-filled circles (the letters/X draw as ink text; the
      /// only small accent fill in the plot is the peak dot — candidate arrow
      /// sticks are excluded by the width gate).
      List<PdfInkPath> accentDots(List<PdfInkPath> paths) => [
        for (final p in paths)
          if ((p.color[0] - 0x35 / 255).abs() < 0.004 &&
              (p.color[1] - 0x56 / 255).abs() < 0.004 &&
              (p.color[2] - 0xA8 / 255).abs() < 0.004 &&
              (p.maxX - p.minX) >= 3 &&
              (p.maxX - p.minX) <= 6.5 &&
              (p.maxY - p.minY) >= 3 &&
              (p.maxY - p.minY) <= 6.5)
            p,
      ];

      /// The halo backings: paper-white fills behind the in-plot glyphs (the
      /// PDF's halo equivalent — see the backing's slot comment in
      /// cycle_pdf.dart).
      List<PdfInkPath> whiteBackings(List<PdfInkPath> paths) => [
        for (final p in paths)
          if (p.color.every((c) => (c - 1.0).abs() < 0.002)) p,
      ];

      /// Whether a white backing of [paths] sits in [column]'s day column,
      /// vertically centered on [inkBaselineY] — a text glyph's halo box
      /// shares the ink's slot center.
      bool backedIn(List<PdfInkPath> paths, int column, double inkBaselineY) {
        return whiteBackings(paths).any((p) {
          final cx = (p.minX + p.maxX) / 2;
          final cy = (p.minY + p.maxY) / 2;
          return cx > x0 + column * pdfColumnWidth + 1 &&
              cx < x0 + (column + 1) * pdfColumnWidth - 1 &&
              (cy - inkBaselineY).abs() < 3.5;
        });
      }

      /// Whether any backing of [paths] sits in [column]'s day column —
      /// column-only, for the rows whose ink (and backing) must be absent.
      bool backedInColumn(List<PdfInkPath> paths, int column) {
        return whiteBackings(paths).any(
          (p) =>
              (p.minX + p.maxX) / 2 > x0 + column * pdfColumnWidth + 1 &&
              (p.minX + p.maxX) / 2 < x0 + (column + 1) * pdfColumnWidth - 1,
        );
      }

      /// The evaluation day-number ink runs: the digits 1–6 at the
      /// numbers' tiny ink size.
      bool isNumberRun(PdfTextRun r) =>
          {'1', '2', '3', '4', '5', '6'}.contains(r.text) &&
          (r.fontSize - pdfTinyFontSize).abs() < 0.05;

      test(
        'the sex X marks render in the plot at their per-timing slots',
        () async {
          final bytes = await generateMarkFixture();
          final (runs, _) = extractPageContent(bytes);
          final blutungY = runY(runs, 'Blutung');
          final tempY = runY(runs, 'Temperatur');
          bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
          final xRuns = [
            for (final r in runs)
              if (r.text == 'X' && inPlot(r)) r,
          ]..sort((a, b) => a.x.compareTo(b.x));
          // Day 2 carries all three timings (slots 1/6, 1/2, 5/6), day 3 end
          // only (5/6). All X runs share one glyph, so their BASELINE-x offsets
          // fold to exactly the slot fractions of the column pitch.
          expect(xRuns.map((r) => r.x).toList(), [
            closeTo(x0 + (2 + 1 / 6) * pdfColumnWidth, 2.5),
            closeTo(x0 + (2 + 1 / 2) * pdfColumnWidth, 2.5),
            closeTo(x0 + (2 + 5 / 6) * pdfColumnWidth, 2.5),
            closeTo(x0 + (3 + 5 / 6) * pdfColumnWidth, 2.5),
          ], reason: 'the timing slots sit at 1/6, 1/2, 5/6 of the day column');
          expect(
            xRuns,
            hasLength(4),
            reason:
                'the paper-form sex strip row is gone — only the in-plot Xs remain',
          );
        },
      );

      test('the mucus sign letters ride their day columns in the plot (S with '
          'its quality superscript, f/S), pitched below the sex row', () async {
        final bytes = await generateMarkFixture();
        final (runs, _) = extractPageContent(bytes);
        final blutungY = runY(runs, 'Blutung');
        final tempY = runY(runs, 'Temperatur');
        bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
        final s = runOf(runs, 'S', pdfLabelFontSize);
        final fs = runOf(runs, 'f/S', pdfLabelFontSize);
        final quality = runOf(runs, 'EW', pdfMucusQualityFontSize);
        expect(
          s,
          isNotNull,
          reason:
              'the S letter renders INSIDE the plot '
              '(the in-plot letters use the row letters\' _label size)',
        );
        expect(fs, isNotNull, reason: 'f/S renders in the plot too');
        expect(quality, isNotNull, reason: 'the quality token renders with S');
        for (final (name, run) in [('S', s!), ('f/S', fs!), ('EW', quality!)]) {
          expect(
            inPlot(run),
            isTrue,
            reason: 'the $name letter renders inside the plot region',
          );
        }
        // Both letter baselines share the mucus row; the quality superscript
        // rides raised (the rows' composed glyph, token raised by its offset).
        expect((s.y - fs.y).abs(), lessThan(0.001));
        expect(quality.y, greaterThan(s.y + 0.5));
        // The settled row pitches: the letters ride the mucus pitch BELOW
        // the X's sex row — 0.2 K apart, mapped by the plot's °C scale.
        final sexY = runOf(runs, 'X', pdfLabelFontSize)!.y;
        expect(
          sexY - s.y,
          closeTo(
            (mucusRowCenterOffsetK - sexRowCenterOffsetK) *
                plotHeightPt /
                defaultSpan,
            0.001,
          ),
        );
        // The letters center in their day columns (S on day 5, f/S on day 6;
        // the run boxes are width-constrained, so the baselines fall inside
        // the column interval).
        expect(
          s.x,
          allOf(
            greaterThan(x0 + 5 * pdfColumnWidth + 0.5),
            lessThan(x0 + 6 * pdfColumnWidth - 0.5),
          ),
        );
        expect(
          fs.x,
          allOf(
            greaterThan(x0 + 6 * pdfColumnWidth + 0.5),
            lessThan(x0 + 7 * pdfColumnWidth - 0.5),
          ),
        );
      });

      test(
        'the mucus peak dot renders as one small accent circle between the '
        'sex row and the letter row, centered in the peak day\'s column',
        () async {
          final bytes = await generateMarkFixture();
          final (runs, paths) = extractPageContent(bytes);
          final blutungY = runY(runs, 'Blutung');
          final s = runOf(runs, 'S', pdfLabelFontSize);
          final sexY = runOf(runs, 'X', pdfLabelFontSize)!.y;
          final dots = accentDots(paths);
          expect(
            dots,
            hasLength(1),
            reason: 'the peak-marked day carries exactly one peak dot',
          );
          final dot = dots.single;
          final centerX = (dot.minX + dot.maxX) / 2;
          final centerY = (dot.minY + dot.maxY) / 2;
          // The dot rides the peak day's column center (day 5), its own
          // row pitch ([peakDotCenterOffsetK]) between the letter
          // row and the sex row.
          expect(centerX, closeTo(x0 + 5.5 * pdfColumnWidth, 0.001));
          expect(
            centerY,
            lessThan(blutungY),
            reason: 'the dot renders inside the plot',
          );
          expect(centerY, greaterThan(s!.y + 2));
          expect(centerY, lessThan(sexY - 4));
        },
      );

      test('a marked entry-less placeholder column paints NO ink beyond the '
          'mark\'s dot — no mucus letter, no day number', () async {
        // Mar 1–14 carry entries; `today` pins the span extension to
        // Mar 17, so Mar 15–17 are entry-less placeholder columns and
        // the peak mark lands on placeholder column 14 (Mar 15).
        final model = buildPdfExportModel(
          entries: markFixtureEntries(),
          marks: [
            CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
            CycleMark(date: d(3, 15), type: CycleMarkTypes.mucusPeakDay),
          ],
          temperatureRange: TemperatureRange.defaults,
          today: d(3, 17),
        );
        final bytes = await generatePdfBytes(
          model: model,
          fontBytes: fixtureFontBytes(),
          options: PdfExportOptions(anonymized: false),
          compress: false,
        );
        final (runs, _) = extractPageContent(bytes);
        final blutungY = runY(runs, 'Blutung');
        final tempY = runY(runs, 'Temperatur');
        bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
        final columnStart = x0 + 14 * pdfColumnWidth + 0.5;
        final columnEnd = x0 + 15 * pdfColumnWidth - 0.5;
        final joinedInk = [
          for (final r in runs)
            if (inPlot(r) &&
                r.x > columnStart &&
                r.x < columnEnd &&
                {
                  pdfMucusQualityFontSize,
                  pdfTinyFontSize,
                  pdfLabelFontSize,
                }.any((s) => (r.fontSize - s).abs() < 0.05))
              r,
        ];
        expect(
          joinedInk,
          isEmpty,
          reason: 'no mucus letter or day number joins the empty column',
        );
      });

      test('the Mittelschmerz letter M renders INSIDE the plot at the M '
          'row pitch ([mRowCenterOffsetK]), below the mucus letters, '
          'centered in its record day\'s column', () async {
        final bytes = await generateMarkFixture();
        final (runs, _) = extractPageContent(bytes);
        final blutungY = runY(runs, 'Blutung');
        final tempY = runY(runs, 'Temperatur');
        bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
        final mRuns = [
          for (final r in runs)
            if (r.text == 'M' && inPlot(r)) r,
        ];
        expect(
          mRuns,
          hasLength(1),
          reason: 'the plot carries exactly one Mittelschmerz M',
        );
        final m = mRuns.single;
        expect(
          m.fontSize,
          closeTo(pdfLabelFontSize, 0.05),
          reason: "the M shares the in-plot letters' ink family",
        );
        // The M pitch: the letters' row minus one grid line (0.1 K).
        final s = runOf(runs, 'S', pdfLabelFontSize)!;
        expect(
          s.y - m.y,
          closeTo(
            (mRowCenterOffsetK - mucusRowCenterOffsetK) *
                plotHeightPt /
                defaultSpan,
            0.001,
          ),
        );
        expect(
          m.x,
          allOf(
            greaterThan(x0 + 8 * pdfColumnWidth + 0.5),
            lessThan(x0 + 9 * pdfColumnWidth - 0.5),
          ),
          reason: "the M centers in the fixture day's column (day 8)",
        );
      });

      test(
        'the 1–6 evaluation numbers render INSIDE the plot near the '
        'bottom, one per low column, in the low-number band\'s ink family',
        () async {
          final bytes = await generateNumberFixture();
          final (runs, paths) = extractPageContent(bytes);
          final blutungY = runY(runs, 'Blutung');
          final tempY = runY(runs, 'Temperatur');
          bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
          final numberRuns = [
            for (final r in runs)
              if (isNumberRun(r)) r,
          ]..sort((a, b) => a.x.compareTo(b.x));
          expect(
            numberRuns.map((r) => r.text).toList(),
            ['6', '5', '4', '3', '2', '1'],
            reason:
                'the six low columns number from the first higher '
                'measurement backwards (the domain numbering, fed to the '
                'plot unchanged)',
          );
          expect(
            numberRuns.first.fontSize,
            closeTo(pdfTinyFontSize, 0.05),
            reason: 'the numbers render in the low-number band\'s ink family',
          );
          for (final run in numberRuns) {
            expect(
              inPlot(run),
              isTrue,
              reason: "the number '${run.text}' renders inside the plot region",
            );
          }
          for (final (index, run) in numberRuns.indexed) {
            expect(
              run.x,
              allOf(
                greaterThan(x0 + index * pdfColumnWidth + 0.5),
                lessThan(x0 + (index + 1) * pdfColumnWidth - 0.5),
              ),
              reason:
                  "the number '${run.text}' centers in its low day's column",
            );
          }
          // The numbers ride the BOTTOM gridline gap: their ink baseline
          // sits the mucus+numbers row pitch of plot scale below the
          // letters row's baseline. The rows' different ink sizes shift
          // their baselines by their fonts' different ascent-to-box
          // offsets — bounded by one em of the size gap (the epsilon).
          final s = runOf(runs, 'S', pdfLabelFontSize)!;
          expect(
            s.y - numberRuns.first.y,
            closeTo(lettersToNumbersGapPt, pdfLabelFontSize - pdfTinyFontSize),
          );
          // On the in-plot seam each glyph renders on its halo backing.
          for (final (index, run) in numberRuns.indexed) {
            expect(
              backedIn(paths, index, run.y),
              isTrue,
              reason: "the number '${run.text}' rides its halo backing",
            );
          }
        },
      );

      test(
        'a paper-colored halo backing renders behind each in-plot glyph, '
        'shared with the ink\'s slot (the ink sits exactly over it)',
        () async {
          final bytes = await generateMarkFixture();
          final (runs, paths) = extractPageContent(bytes);
          final s = runOf(runs, 'S', pdfLabelFontSize)!;
          final m = [
            for (final r in runs)
              if (r.text == 'M') r,
          ].single;
          final dot = accentDots(paths).single;
          expect(
            backedIn(paths, 5, s.y),
            isTrue,
            reason: 'the mucus letters ride a backing in their column',
          );
          expect(
            backedIn(paths, 8, m.y),
            isTrue,
            reason: 'the M rides a backing in its column',
          );
          // The peak dot's halo circle: bigger than the dot and exactly
          // centered under it — dot diameter + the shared halo stroke
          // width on both sides.
          final circle = [
            for (final p in whiteBackings(paths))
              if (((p.minX + p.maxX) / 2 - (dot.minX + dot.maxX) / 2).abs() <
                      1.5 &&
                  ((p.minY + p.maxY) / 2 - (dot.minY + dot.maxY) / 2).abs() <
                      1.5)
                p,
          ];
          expect(
            circle,
            hasLength(1),
            reason: 'the dot rides exactly one backing',
          );
          expect(
            circle.single.maxX - circle.single.minX,
            allOf(
              greaterThan(dot.maxX - dot.minX),
              lessThan(dot.maxX - dot.minX + 4 * chartMarkHaloStrokeWidth),
            ),
            reason: 'the halo circle outgrows the ink dot without blotting out',
          );
        },
      );

      test('the paper form drops the mucus band, the sex row, the '
          'Mittelschmerz row and the Zahl row — bleeding is the last strip '
          'row above the glyphs inside the plot', () async {
        final bytes = await generateMarkFixture();
        final (runs, _) = extractPageContent(bytes);
        final rendered = runs.map((r) => r.text).toList();
        expect(
          rendered,
          isNot(contains('Zeichen')),
          reason: 'the mucus band renders as in-plot glyphs, not a strip row',
        );
        expect(
          rendered,
          isNot(contains('Sex')),
          reason: 'the Xs render in the plot, not as a strip row',
        );
        expect(
          rendered,
          isNot(contains('Mittelschmerz')),
          reason: 'the M renders in the plot, not as a strip row',
        );
        expect(
          rendered,
          isNot(contains('Zahl')),
          reason: 'the day numbers render in the plot, not as a strip row',
        );
        const kept = [
          // The calendar day-number row: the cycle-day labels above the
          // plot, distinct from the evaluation numbering inside it.
          pdfRailCaptionDayNumbers,
          pdfRailCaptionDates,
          'Blutung',
          // The exporter draws words as separate runs; the caption's anchor
          // word is 'Temperatur'.
          'Temperatur',
          'Zeit',
          'Störung',
          // The merged band's one rail caption — the cervix and pain zones
          // share it.
          pdfRailCaptionNotesBand,
        ];
        for (final caption in kept) {
          expect(
            rendered,
            contains(caption),
            reason: 'the kept scaffold row "$caption" stays',
          );
        }
        for (final dropped in ['Muttermund', 'Schmerz']) {
          expect(
            rendered,
            isNot(contains(dropped)),
            reason:
                'the merged band\'s row carries no "$dropped" caption — '
                'the zones ride its one row',
          );
        }
      });

      test(
        'a span-0.20 range keeps the sex row AND the peak dot (decoupled '
        'rows); the mucus letters, the M and their halo backs hide',
        () async {
          final bytes = await generateMarkFixture(
            range: const TemperatureRange(min: 37.8, max: 38.0),
          );
          final (runs, paths) = extractPageContent(bytes);
          final blutungY = runY(runs, 'Blutung');
          final tempY = runY(runs, 'Temperatur');
          bool inPlot(PdfTextRun r) => r.y > tempY && r.y < blutungY;
          // The letters render nowhere on the page when hidden.
          expect(
            runs.where(
              (r) => r.text == 'S' || r.text == 'f/S' || r.text == 'EW',
            ),
            isEmpty,
          );
          expect(
            runs.where((r) => r.text == 'M'),
            isEmpty,
            reason: 'the M hides with its own row below the letters',
          );
          final xRuns = [
            for (final r in runs)
              if (r.text == 'X' && inPlot(r)) r,
          ];
          expect(
            xRuns,
            hasLength(4),
            reason: 'the sex Xs stay, at their timing slots in the plot',
          );
          expect(
            accentDots(paths),
            hasLength(1),
            reason:
                'the peak dot keeps ITS OWN row (0.15): at span 0.20 it '
                'stays visible, decoupled from the letters band',
          );
          final dot = accentDots(paths).single;
          // A hidden row's halo backs follow their glyph's visibility.
          expect(
            backedInColumn(paths, 6),
            isFalse,
            reason: "the hidden f/S letter's backing hides too",
          );
          expect(
            backedInColumn(paths, 8),
            isFalse,
            reason: "the hidden M's backing hides too",
          );
          final circle = [
            for (final p in whiteBackings(paths))
              if (((p.minX + p.maxX) / 2 - (dot.minX + dot.maxX) / 2).abs() <
                      1.5 &&
                  ((p.minY + p.maxY) / 2 - (dot.minY + dot.maxY) / 2).abs() <
                      1.5)
                p,
          ];
          expect(
            circle,
            hasLength(1),
            reason: 'the visible dot keeps its backing',
          );
        },
      );

      test('a span below 0.10 hides the bottom-anchored day numbers with '
          'their row — no number ink and no halo backing anywhere', () async {
        final bytes = await generateNumberFixture(
          range: const TemperatureRange(min: 37.9, max: 37.96),
        );
        final (runs, paths) = extractPageContent(bytes);
        expect(
          runs.where(isNumberRun),
          isEmpty,
          reason:
              'the numbers hide when their center exceeds the top edge '
              'margin: min + 0.05 ≤ max − 0.05 fails at span 0.06',
        );
        expect(
          whiteBackings(paths),
          isEmpty,
          reason: 'the halo backs follow their glyph\'s row visibility',
        );
        expect(
          accentDots(paths),
          isEmpty,
          reason: 'the other in-plot rows hide at this span too',
        );
      });
    },
  );

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
      selectedStartDates: {_calendarDate(2020, 1, 1)},
      today: _calendarToday,
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
      selectedStartDates: {_calendarDate(2020, 1, 1)},
      today: _calendarToday,
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
          if (_emptyDayNumberRun(run)) run.text,
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
      selectedStartDates: {_emptyDate(2020, 3, 1)},
      today: _emptyDate(2020, 4, 10),
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
          if (_emptyDayNumberRun(run)) run.text,
      ],
      ['41.'],
    );
    // The continuation page repeats the identical scaffold ("Blatt k/n").
    expect(runs.map((r) => r.text), contains('Blatt'));
    expect(runs.map((r) => r.text), contains('2/2'));
  });
}
