// Tests of the in-plot chart-mark ink of the generated PDF page
// (lib/pdf/cycle_pdf.dart): the sex X per timing slot, the mucus letters
// with their quality superscript, the peak dot, the Mittelschmerz M, the
// evaluation day numbers and the halo backings behind the glyphs — plus
// how the rows' visibility follows the temperature range.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/pdf/cycle_pdf.dart';
import 'package:cycle_app/pdf/pdf_axis.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_content.dart'
    show PdfInkPath, PdfTextRun, extractPageContent;
import '../support/pdf_fixtures.dart' show d, fixtureFontBytes;

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
void main() {
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
}
