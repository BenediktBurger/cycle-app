// Tests of the PDF curve/overlay draw-list composition
// (lib/pdf/pdf_curve.dart): the pure helper builds the page's drawing from
// the model's cycle evaluation + per-cycle overlay + the page window, and
// DELEGATES the curve structure itself to the chart's pure helpers
// (lib/ui/cycle_curve.dart — curveRuns / curveSegments /
// visibleCurveSegments / isBbtCInRange are imported, never reimplemented:
// the PDF draws exactly the chart's curve rule set).
//
// Coordinate spaces, kept apart by the helper: the model overlay's indexes
// are CALENDAR offsets from the cycle's start day (see
// lib/domain/pdf_export_model.dart's header note), and the page windows
// slice the same calendar space (cycleCalendarDays) — overlay index and
// window column coincide. The resulting draw items use COLUMN
// coordinates: window day i's column spans [i, i+1] — dots, row cells and
// the computed-SUZ line center at i + 0.5, a user SUZ bar's column start
// at i (morning) or the middle at i + 0.5 (evening).
import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
import 'package:cycle_app/domain/evaluation_overlay.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/pdf/pdf_curve.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime day(int n) => DateTime.utc(2026, 3, n);

const _range = TemperatureRange(min: 36.0, max: 38.0);

/// One gapless 13-tracked-day cycle (Mar 1–13, tracked daily):
///
///  days 0–3: ordinary low curve (36.1 / 36.2 / 36.1 / 36.3), day 2 marked
///            ignoreTemperature (its curve pieces render lighter),
///  days 4–9: the six low measurements (all 36.2) → numbered 6…1,
///  day 9:    mucus-peak mark,
///  day 10:   36.8, marked first higher → circled candidate (after peak),
///  day 11:   37.0, ordinary, sex recorded,
///  day 12:   38.4 — OUTSIDE the 36–38 °C window (clips the curve line),
///  day 13:   unmeasured (connectivity break behind day 12).
List<DailyEntry> cycleEntries() => [
  for (var i = 0; i <= 12; i++)
    DailyEntry(
      date: day(1 + i),
      bbtC: switch (i) {
        0 => 36.1,
        1 => 36.2,
        2 => 36.1,
        3 => 36.3,
        >= 4 && <= 9 => 36.2,
        10 => 36.8,
        11 => 37.0,
        12 => 38.4,
        _ => 36.2,
      },
      sexTimings: i == 11 ? 2 : 0,
      notes: i == 11 ? 'Kaffee später getrunken ß' : null,
    ),
];

List<CycleMark> cycleMarks() => [
  CycleMark(date: day(1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: day(3), type: CycleMarkTypes.ignoreTemperature),
  CycleMark(date: day(10), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(date: day(11), type: CycleMarkTypes.firstHigherMeasurement),
  CycleMark(date: day(4), type: CycleMarkTypes.suzMorning),
  CycleMark(date: day(6), type: CycleMarkTypes.suzEvening),
];

(PdfExportModel, PdfCycleOverlay) fixture() {
  final model = buildPdfExportModel(
    entries: cycleEntries(),
    marks: cycleMarks(),
  );
  return (model, model.overlays[0]);
}

void main() {
  final (model, overlay) = fixture();
  final cycle = model.cycles[0];

  group('curve structure (delegated to the chart\'s rule set)', () {
    final drawing = pdfCurveDrawing(
      cycle: cycle,
      overlay: overlay,
      range: _range,
      windowFirstIndex: 0,
      windowDayCount: 13,
      computedSuz: (suzBegins: null, suzRule: null),
    );

    test('one dot per measured IN-RANGE day, raw value kept', () {
      // Days 0…11 are measured and inside 36–38 °C; day 12's 38,4 is out
      // of range (dropped, not clamped onto the plot).
      expect(drawing.dots.length, 12);
      expect(drawing.dots[10].value, 36.8);
      expect(drawing.dots.any((d) => d.index == 12), isFalse);
      expect(drawing.dots.any((d) => d.value > 38.0), isFalse);
    });

    test(
      'adjacent measured days connect; the line clips at the range bound',
      () {
        final lastPiece = drawing.pieces.reduce(
          (a, b) => b.startX > a.startX ? b : a,
        );
        expect(
          lastPiece.endX,
          closeTo(11 + 5 / 7, 1e-6),
          reason:
              'the piece from day 11 (37,0) to day 12 (38,4) clips at '
              'the 38,0 boundary — 5/7 of the way between the columns',
        );
        expect(lastPiece.startValue, 37.0);
        expect(lastPiece.endValue, 38.0);
        // The unmeasured day 13 sits behind the clip: nothing renders there.
        expect(drawing.pieces.any((p) => p.endX > 12.5), isFalse);
        expect(drawing.dots.any((d) => d.index == 13), isFalse);
      },
    );

    test('pieces touching an ignoreTemperature-marked day render lighter', () {
      final lighterXs = {
        for (final p in drawing.pieces.where((p) => p.ignored)) p.startX,
      };
      expect(lighterXs, {
        1.0,
        2.0,
      }, reason: 'day 2 marked: exactly the pieces 1→2 and 2→3 dim');
      final solidStartXs = {
        for (final p in drawing.pieces.where((p) => !p.ignored)) p.startX,
      };
      expect(solidStartXs, contains(3.0));
      expect(solidStartXs, isNot(contains(2.0)));
      // The marked day's own dot still renders — lighter.
      final dot = drawing.dots.firstWhere((d) => d.index == 2);
      expect(dot.ignored, isTrue);
      expect(drawing.dots.firstWhere((d) => d.index == 3).ignored, isFalse);
    });
  });

  group(
    'evaluation overlay shapes (carried from the model, not re-derived)',
    () {
      final drawing = pdfCurveDrawing(
        cycle: cycle,
        overlay: overlay,
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: 13,
        computedSuz: (suzBegins: day(11), suzRule: SuzRule.d),
      );

      test('the circled candidates carry rings on their dots', () {
        // The domain lists EVERY above-baseline measured day from the marked
        // rise onward (R1) — the marked rise (day 10) plus the unmarked
        // days 11/12, all strictly after the peak ⇒ circles. Day 12's 38.4
        // is OUT of the display range: like the chart (whose dot painter
        // never runs for out-of-range spots), the PDF draws NOTHING there
        // — no dot and no clamped edge-ring.
        expect(overlay.circledIndexes, {10, 11, 12});
        expect(
          drawing.rings.map((r) => (r.index, r.value)),
          contains((10, 36.8)),
        );
        expect(drawing.rings, hasLength(2));
        expect(
          drawing.rings.any((r) => r.value > 38.0 || r.value.isNaN),
          isFalse,
        );
      });

      test('every ring marks a DRAWN dot\'s exact (column, value) position '
          '(the painter centers the ring on the dot — one shared mapping)', () {
        final dotPositions = {
          for (final dot in drawing.dots) (dot.index, dot.value),
        };
        for (final ring in drawing.rings) {
          expect(
            dotPositions,
            contains((ring.index, ring.value)),
            reason:
                'ring (index ${ring.index}, value ${ring.value}) must sit '
                'on the dot drawn at the same position',
          );
        }
      });

      test('an ARROW candidate below its dot: without a mucus peak the '
          'first-higher kind is the arrow-up glyph, never a ring, and the '
          'tip clears the dot by its radius plus the fixed gap', () {
        final arrowFixture = [
          for (var i = 0; i < 7; i++)
            DailyEntry(date: day(1 + i), bbtC: i == 5 ? 37.9 : 36.2),
        ];
        final model = buildPdfExportModel(
          entries: arrowFixture,
          marks: [
            CycleMark(date: day(1), type: CycleMarkTypes.cycleStart),
            CycleMark(
              date: day(6),
              type: CycleMarkTypes.firstHigherMeasurement,
            ),
          ],
        );
        final drawing = pdfCurveDrawing(
          cycle: model.cycles[0],
          overlay: model.overlays[0],
          range: _range,
          windowFirstIndex: 0,
          windowDayCount: 7,
          computedSuz: (suzBegins: null, suzRule: null),
        );
        expect(drawing.arrows, hasLength(1));
        final arrow = drawing.arrows.single;
        expect(
          arrow.tipDropPt,
          closeTo(pdfCurveDotRadiusPt + pdfArrowClearanceBelowDotPt, 1e-9),
          reason:
              'the tip drops the dot\'s radius (its bottom edge) PLUS the '
              'clearance gap — the glyph must never touch the dot',
        );
        expect(pdfArrowClearanceBelowDotPt, greaterThan(0));
        expect(arrow.index, 5);
        expect(arrow.value, 37.9);
        expect(model.overlays[0].arrowIndexes, {
          5,
        }, reason: 'without the peak the first-higher kind stays an arrow');
        expect(
          drawing.rings,
          isEmpty,
          reason: 'rings need the mucus-peak-backed R1 rule — none here',
        );
      });

      test('the 1–6 low numbers land under their low dots', () {
        expect(drawing.lowNumbers, {
          4: 6,
          5: 5,
          6: 4,
          7: 3,
          8: 2,
          9: 1,
        }, reason: 'the measured day at rise−i carries number i');
      });

      test('the solid peak dot rides every placed peak', () {
        expect(drawing.peakIndexes, {9});
      });

      test('the R10 baseline runs from the left edge of the first numbered low '
          'to half a column past the last marked candidate', () {
        final piece = drawing.baseline.single;
        expect(piece.startX, 4.0);
        expect(
          piece.endX,
          closeTo(13.0, 1e-9),
          reason:
              'the last candidate is day 12 (the auto-candidacy above '
              'the rise, R1) — the piece runs half a column past it',
        );
        expect(
          piece.value,
          36.2,
          reason: 'the baseline sits through the HIGHEST of the six lows',
        );
      });

      test(
        'user SUZ bars: morning → column start, evening → column middle',
        () {
          expect(
            drawing.suzBars.map((b) => b.x).toSet(),
            {3.0, 5.5},
            reason:
                'day 3\'s morning bar rides its column left edge (x = 3), '
                'day 5\'s evening bar its middle (x = 5.5)',
          );
          expect(drawing.suzBars.where((b) => b.morning).single.x, 3.0);
        },
      );

      test('the computed SUZ renders as its own artifact: a thin line at the '
          'suzBegins day with the rule letter', () {
        final line = drawing.suzLine!;
        expect(
          line.x,
          closeTo(10.5, 1e-9),
          reason: 'the line rides the suzBegins column\'s middle',
        );
        expect(line.ruleLetter, 'D');
      });

      test('without a computed SUZ there is no line artifact', () {
        final drawing = pdfCurveDrawing(
          cycle: cycle,
          overlay: overlay,
          range: _range,
          windowFirstIndex: 0,
          windowDayCount: 13,
          computedSuz: (suzBegins: null, suzRule: null),
        );
        expect(drawing.suzLine, isNull);
        expect(
          drawing.suzBars,
          hasLength(2),
          reason: 'the user-placed marks render regardless',
        );
      });
    },
  );

  group('window slicing (continuation pages get the same helper)', () {
    // Page window = tracked positions 5…9 (cycle days 6–10): the last
    // window column is low #1 + peak; the candidate day 10 is the NEXT
    // page's column 0.
    late final drawing = pdfCurveDrawing(
      cycle: cycle,
      overlay: overlay,
      range: _range,
      windowFirstIndex: 5,
      windowDayCount: 5,
      computedSuz: (suzBegins: day(11), suzRule: SuzRule.e),
    );

    test('only the window\'s tracked days produce dots and pieces', () {
      expect(drawing.dots.map((d) => d.index), [0, 1, 2, 3, 4]);
      expect(drawing.dots.map((d) => d.value), [36.2, 36.2, 36.2, 36.2, 36.2]);
      for (final piece in drawing.pieces) {
        expect(piece.startX, inInclusiveRange(0, 5));
        expect(piece.endX, inInclusiveRange(0, 5));
      }
    });
  });

  group('index space (calendar offsets vs. tracked positions)', () {
    test('a mark on an untracked gap day renders in its own calendar '
        'column; the page window counts every calendar day of the span', () {
      // The same cycle, but WITHOUT Mar 2's entry: the calendar day list
      // keeps Mar 2 (data-less), so the peak mark placed there renders on
      // its own column and every later mark rides its calendar offset —
      // the tracked positions behind the gap shift by one, the calendar
      // positions do not.
      final entries = [
        for (final e in cycleEntries())
          if (!DateOnly.sameDay(e.date, day(2))) e,
      ];
      final marks = [
        // A peak placed on the now-untracked Mar 2.
        CycleMark(date: day(2), type: CycleMarkTypes.mucusPeakDay),
        ...cycleMarks(),
      ];
      // The window size is the calendar-day count, so pin the clock: the
      // still-running cycle's span otherwise reaches the wall clock.
      final model = buildPdfExportModel(
        entries: entries,
        marks: marks,
        today: day(13),
      );
      final drawing = pdfCurveDrawing(
        cycle: model.cycles[0],
        overlay: model.overlays[0],
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: cycleCalendarDays(model.cycles[0].cycle).length,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      expect(
        drawing.peakIndexes,
        equals({1, 9}),
        reason:
            'the gap-day peak (Mar 2) rides its own calendar column 1; '
            'the day 10 peak rides calendar offset 9 — window position '
            'and overlay index coincide on the calendar window',
      );
    });

    test('interior untracked calendar days SPLIT the curve runs (exactly '
        'the chart\'s run-break rule): measured days around the gap are '
        'NOT connected by a piece, consecutive tracked days still are', () {
      // The gap fixture again (Mar 2 untracked): Mar 1 (measured 36.1,
      // column 0) and Mar 3 (measured 36.1, column 2) both draw dots on
      // their own calendar columns — but their CALENDAR offsets differ by
      // two (the untracked day between them), so no line piece may
      // connect them.
      final entries = [
        for (final e in cycleEntries())
          if (!DateOnly.sameDay(e.date, day(2))) e,
      ];
      final model = buildPdfExportModel(
        entries: entries,
        marks: cycleMarks(),
        // Same reason as the gap test above: pin the clock for a
        // deterministic calendar-day window count.
        today: day(13),
      );
      final drawing = pdfCurveDrawing(
        cycle: model.cycles[0],
        overlay: model.overlays[0],
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: cycleCalendarDays(model.cycles[0].cycle).length,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      expect(drawing.dots.any((d) => d.index == 0), isTrue);
      expect(drawing.dots.any((d) => d.index == 2), isTrue);
      expect(
        drawing.pieces.where((p) => p.startX == 0.0 || p.endX == 0.0),
        isEmpty,
        reason:
            'the Mar 1 dot starts no line: its direct CALENDAR successor '
            '(Mar 3) sits two columns ahead, not adjacent to a connected '
            'run',
      );
      expect(
        drawing.pieces.any((p) => p.startX == 2.0 && p.endX == 3.0),
        isTrue,
        reason: 'the consecutive tracked days Mar 3 -> Mar 4 still connect',
      );
    });

    test('a peak on a DATA-LESS SPAN-EXTENSION day draws: the page window\'s '
        'columns are the cycle\'s calendar days (cycleCalendarDays), so the '
        'mark maps to its calendar position', () {
      // Tracked Mar 1–13; `today` pins the still-running cycle's span to
      // Mar 17, so Mar 14–17 enter the span list as data-less span days.
      final model = buildPdfExportModel(
        entries: cycleEntries(),
        marks: [
          ...cycleMarks(),
          CycleMark(date: day(15), type: CycleMarkTypes.mucusPeakDay),
        ],
        today: day(17),
      );
      final cycle = model.cycles[0];
      expect(cycleCalendarDays(cycle.cycle).length, 17);
      final drawing = pdfCurveDrawing(
        cycle: cycle,
        overlay: model.overlays[0],
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: 17,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      // Mar 15 = calendar offset 14 from the cycle start, and the
      // placeholder days occupy their own calendar positions in order.
      expect(drawing.peakIndexes, {9, 14});
    });
  });

  group('continuation-page slicing (long cycle over several pages)', () {
    // A gapless 45-tracked-day cycle (Mar 1 – Apr 14): the default 40-day
    // column budget splits it into windows [40, 5] — page 1 tracks day
    // indexes 0–39, page 2 the trailing 40–44. A peak mark, a low number
    // and an evening SUZ mark on cycle index 42 (page 2's third column)
    // and a baseline segment spanning indexes 20–44 (it OPENS on page 1
    // and RUNS THROUGH page 2) pin the window-relative mapping the page
    // builder applies to every overlay artifact: subtract firstDayIndex,
    // filter to the window.
    final base = DateTime.utc(2026, 3, 1); // 45 days: Mar 1 – Apr 14
    final entries = [
      for (var i = 0; i < 45; i++)
        DailyEntry(date: base.add(Duration(days: i)), bbtC: 36.5),
    ];
    final marks = [
      CycleMark(date: base, type: CycleMarkTypes.cycleStart),
      // Cycle index 42 = Mar 1 + 42 days = Apr 12.
      CycleMark(
        date: base.add(const Duration(days: 42)),
        type: CycleMarkTypes.mucusPeakDay,
      ),
    ];
    final model = buildPdfExportModel(
      entries: entries,
      marks: marks,
      // The span extension would run this single (last) cycle out to
      // "today"; the fixture pins the clock at the last tracked day so
      // the 45-day slicing stays the subject.
      today: base.add(const Duration(days: 44)),
    );
    final cycle = model.cycles.single;

    // The overlay is assembled BY HAND (not derived): the point here is
    // the page builder's slice of the draw list, not the domain rule set.
    const overlay = PdfCycleOverlay(
      peakIndexes: {42},
      numbersByIndex: {42: 3},
      suzMarks: [SuzOverlayMark(dayIndex: 42, morning: false)],
      baselineSegments: [
        BaselineSegment(startIndex: 20, endIndex: 44, value: 36.5),
      ],
    );

    test('overlay artifacts map to window-relative positions or drop out', () {
      final drawing = pdfCurveDrawing(
        cycle: cycle,
        overlay: overlay,
        range: _range,
        windowFirstIndex: 40,
        windowDayCount: 5,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      expect(drawing.peakIndexes, {
        2,
      }, reason: 'the cycle index 42 sits at page 2\'s column 3');
      expect(drawing.dots.map((d) => d.index), [0, 1, 2, 3, 4]);
      expect(drawing.lowNumbers, {2: 3});
      expect(
        drawing.suzBars.map((b) => b.x),
        [2.5],
        reason: 'the evening SUZ mark rides its window-relative column middle',
      );
      expect(drawing.rings, isEmpty);
      expect(drawing.arrows, isEmpty);

      // Window 1 sees none of the day-42 artifacts: they are page 2's
      // business, so they drop out of the earlier page's draw list.
      final window1 = pdfCurveDrawing(
        cycle: cycle,
        overlay: overlay,
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: 40,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      expect(window1.peakIndexes, isEmpty);
      expect(window1.lowNumbers, isEmpty);
      expect(window1.suzBars, isEmpty);
    });

    test('window 2 carries the baseline piece for the cycle\'s tail', () {
      final drawing = pdfCurveDrawing(
        cycle: cycle,
        overlay: overlay,
        range: _range,
        windowFirstIndex: 40,
        windowDayCount: 5,
        computedSuz: (suzBegins: null, suzRule: null),
      );
      final piece = drawing.baseline.single;
      expect(
        piece.startX,
        0.0,
        reason:
            'the segment opens on page 1 — page 2 draws from the '
            'window\'s left edge',
      );
      expect(
        piece.endX,
        closeTo(5.0, 1e-9),
        reason:
            'the segment ends at the cycle\'s last day (index 44); '
            'the half-column padding runs into the window\'s right edge',
      );
      expect(piece.value, 36.5);
    });

    test('window 1 (indexes 0–39) clips the overlay pieces at the planner\'s '
        'window edge', () {
      final drawing = pdfCurveDrawing(
        cycle: cycle,
        overlay: overlay,
        range: _range,
        windowFirstIndex: 0,
        windowDayCount: 40,
        // suzBegins at cycle index 42 rides page 2: page 1 must clamp the
        // line to its own right edge.
        computedSuz: (
          suzBegins: base.add(const Duration(days: 42)),
          suzRule: SuzRule.d,
        ),
      );
      expect(
        drawing.peakIndexes,
        isEmpty,
        reason: 'the day-42 marker is page 2\'s business',
      );
      final piece = drawing.baseline.single;
      expect(piece.startX, 20.0);
      expect(
        piece.endX,
        closeTo(40.0, 1e-9),
        reason:
            "the piece clips at the window edge — the segment "
            'continues onto page 2',
      );
      final line = drawing.suzLine!;
      expect(
        line.x,
        closeTo(40.0, 1e-9),
        reason: 'the suzBegins line clamps to the same window edge',
      );
      expect(line.ruleLetter, 'D');
    });
  });
}
