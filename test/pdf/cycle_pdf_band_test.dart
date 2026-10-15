// Tests of the merged notes band on the generated PDF page
// (lib/pdf/cycle_pdf.dart): the cervix rings and dots, the pain letter
// and the note text of the band's zones, and the render-time
// measurement-method synthesis (the change date's route word in the band
// note, also across untracked gaps and page windows).
import 'package:cycle_app/domain/band_layout.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/measurement_method.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:cycle_app/pdf/pdf_axis.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_content.dart'
    show PdfInkPath, PdfTextRun, countPageMarkers, extractPageContent;
import '../support/pdf_fixtures.dart' show d, fixtureFontBytes;

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
// interior days Mar 4–6 carry no page column) — a change dated Mar 5 must
// render on the FIRST tracked column at or after it (Mar 7, the window's
// fourth column: the page window position, not the calendar offset 6).
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
void main() {
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
        'tracked column at or after it (the window-day column, not the '
        'calendar offset)', () async {
      final bytes = await generateGapMethodFixture();
      final (runs, _) = extractPageContent(bytes);
      // Mar 7 is the span list's 4th day => column 3 of the single page.
      // The Mar 5 snapshot's synthesis alone fills that noteless cell.
      expect(
        compact(cellText(runs, 3)),
        'andere',
        reason: 'Mar 5 sits inside the Mar 4–6 gap: no column of its own',
      );
      expect(
        cellText(runs, 2),
        isEmpty,
        reason: "no synthesis slides onto the snapshot day's NEIGHBOR before",
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
}
