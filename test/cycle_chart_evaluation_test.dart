import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the computed evaluation marks on the cycle chart (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks; the UI
// derives and renders the candidate circles/arrows (kind decided PER
// CANDIDATE: arrows at or before the peak day, circles strictly after — R4),
// the solid peak dot in its own in-plot row, the 1–6 low numbering inside
// the plot's bottom edge and the baseline SEGMENT (low #6 to the last
// marked candidate — R10). Derived
// artifacts are computed at render time only — these tests pin how the
// artifacts of lib/domain/evaluation.dart surface on the chart.
//

// 2026-09-03 is a Thursday, so this sequence runs Sun (9/6) .. Wed (9/16).
// Day indexes: 9/6 -> 0 ... 9/16 -> 10. (The scenario data lives in
// support/fixtures.dart; these constants name the days for the assertions.)
final _sun6 = DateTime.utc(2026, 9, 6);
final _sat12 = DateTime.utc(2026, 9, 12);
final _sun13 = DateTime.utc(2026, 9, 13);
final _mon14 = DateTime.utc(2026, 9, 14);
final _tue15 = DateTime.utc(2026, 9, 15);
final _wed16 = DateTime.utc(2026, 9, 16);
final _thu17 = DateTime.utc(2026, 9, 17);
final _fri18 = DateTime.utc(2026, 9, 18);

/// Main evaluation scenario (peak before the rise -> CIRCLES) — the
/// shared fixture in support/fixtures.dart; see the per-day role comments
/// there.
final _evaluationEntries = evaluationScenarioEntries();

final _marks = evaluationScenarioMarks();

/// The baseline segment bars (R10): the dashed two-spot bars drawn in the
/// baseline color (secondary) — one per evaluated cycle with a marked
/// candidate. Horizontal by construction, so the vertical SUZ bars (same
/// secondary color) are excluded here.
List<LineChartBarData> _baselineBars(WidgetTester tester) => chartData(tester)
    .lineBarsData
    .where(
      (bar) =>
          bar.color == chartScheme(tester).secondary &&
          bar.spots.first.y == bar.spots.last.y,
    )
    .toList();

/// The SUZ bars: vertical two-spot bars in the secondary color (one per
/// user-placed SUZ mark) — the same evaluation-family color as the baseline
/// segment, distinguished by orientation.
List<LineChartBarData> _suzBars(WidgetTester tester) => chartData(tester)
    .lineBarsData
    .where(
      (bar) =>
          bar.color == chartScheme(tester).secondary &&
          bar.spots.first.x == bar.spots.last.x,
    )
    .toList();

/// The SUZ arrow: the spot + painter of the SUZ arrow glyph, or null when
/// no user SUZ mark renders an arrow.
(FlSpot, FlDotPainter)? _suzArrowSpot(WidgetTester tester) {
  for (final bar in dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final painter = bar.dotData.getDotPainter(bar.spots[i], 0, bar, i);
      if (painter is SuzArrowDotPainter) return (bar.spots[i], painter);
    }
  }
  return null;
}

/// Identity helper: true when [entry]'s date is exactly [day]'s calendar day
/// (used to patch the scenario above).
bool _sameDay(DailyEntry entry, DateTime day) =>
    entry.date.year == day.year &&
    entry.date.month == day.month &&
    entry.date.day == day.day;

void main() {
  group('R6 — the peak renders as a solid dot inside the plot, not on '
      'the curve', () {
    testWidgets('the peak day keeps a plain temperature dot — no ring on '
        'the curve', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/12 (idx 6) carries the mucus-peak mark: the curve dot there is
      // an ORDINARY temperature dot — the ring painter is gone from the
      // peak day (R6).
      final painter = dotPainter(tester, 6);
      expect(
        painter,
        isNot(isA<RingDotPainter>()),
        reason: 'the peak ring was removed from the temperature curve',
      );
      expect(painter, isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets('curve rings exist only for the candidate measurements, '
        'not for the peak', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // A ring appears exactly on the three circled candidates (idx
      // 8..10), never on the peak day (idx 6).
      final rings = candidateKinds(tester).rings;
      expect(rings, {
        8,
        9,
        10,
      }, reason: 'rings wrap only the circled candidates (R6/R1)');
      for (final index in rings) {
        final painter = dotPainter(tester, index) as RingDotPainter;
        expect(
          painter.ringColor,
          chartScheme(tester).primary,
          reason: 'circled candidates are temperature-family',
        );
      }
    });

    testWidgets('the peak renders as a solid dot INSIDE the plot, in its '
        'own row in the top rows', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/12 (idx 6) carries the peak mark -> solid in-plot dot.
      expect(inPlotPeakDot(6), findsOneWidget);
      // Neighboring days carry no peak dot.
      expect(inPlotPeakDot(5), findsNothing);
      expect(inPlotPeakDot(7), findsNothing);

      // The dot is SOLID and in the mucus color family (tertiary), at the
      // shared glyph alpha.
      final dot = tester.widget<Container>(inPlotPeakDot(6));
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        chartScheme(tester).tertiary.withValues(alpha: chartMarkAlpha),
        reason: 'the peak belongs to the mucus color family',
      );

      // The dot rides its own row inside the plot's top rows: the pixel
      // drop below the top border is the owner-eyeball row geometry, so
      // the test keeps the renderable relation, not a mirrored mapping.
      final plot = tester.getRect(find.byType(LineChart));
      final dotY = tester.getRect(inPlotPeakDot(6)).center.dy;
      expect(dotY, greaterThan(plot.top));
      expect(
        dotY,
        lessThan(plot.center.dy),
        reason:
            'the peak dot sits in the plot\'s top rows, above every '
            'bottom-anchored row',
      );
    });

    testWidgets('a peak day without an entry still renders the dot and '
        'does not crash', (tester) async {
      // 9/12 has NO entry at all: the dot hangs on the peak mark itself,
      // so it renders alone in the day's column.
      final entries = _evaluationEntries
          .where((e) => !_sameDay(e, _sat12))
          .toList();
      await pumpChart(tester, chartHarness(entries: entries, marks: _marks));

      expect(
        inPlotPeakDot(6),
        findsOneWidget,
        reason: 'the dot rides the mark, entry or not',
      );
      // The circled candidates (idx 8..10) are unaffected by the missing
      // peak entry; what must be ABSENT is the peak ring — i.e. no ring in
      // the mucus color family (tertiary).
      for (final index in candidateKinds(tester).rings) {
        final painter = dotPainter(tester, index) as RingDotPainter;
        expect(painter.ringColor, isNot(chartScheme(tester).tertiary));
      }
    });
  });

  group('R1/R4 — candidate circles and arrows follow the new decision', () {
    testWidgets('circled candidates: every measured day above the baseline '
        'from the rise onward, capped and ended by rule D', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // The candidates (idx 8..10) render circled ...
      for (final index in [8, 9, 10]) {
        final painter = dotPainter(tester, index);
        expect(
          painter,
          isA<RingDotPainter>(),
          reason: 'circled higher measurement at day index $index',
        );
        expect(
          (painter as RingDotPainter).ringColor,
          chartScheme(tester).primary,
          reason: 'circled higher measurements are temperature-family',
        );
      }
      // ... the pre-rise rise (idx 0, 36.9 above the baseline 36.4) is NOT
      // a candidate (R3) — an ordinary dot.
      expect(dotPainter(tester, 0), isNot(isA<RingDotPainter>()));
      expect(dotPainter(tester, 0), isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets('the four-cap: four arrows carry ordinals; the beyond-cap '
        'arrow STAYS in the sequence — unnumbered, but still an arrow '
        '(R4: a late sequence is not cut off at the cap)', (tester) async {
      // Peak unmarked: every candidate (R4) becomes an arrow. Five
      // above-baseline days exist (9/14..9/18) and all five render — the
      // 5th is beyond its kind's cap, so it carries no ordinal, but it
      // stays part of the connected sequence (R4): the sequence only ends
      // at a SUZ trigger or a break, and arrows never trigger a SUZ.
      final entries = [..._evaluationEntries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 36.5));
      final marks = [
        CycleMark(date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: marks));

      for (final index in [8, 9, 10, 11, 12]) {
        expect(
          dotPainter(tester, index),
          isA<ArrowUpDotPainter>(),
          reason:
              'no peak -> arrow at $index (R4; the '
              'beyond-cap candidate renders unnumbered)',
        );
      }
      // Nothing is circled anywhere.
      expect(candidateKinds(tester).rings, isEmpty);
    });

    testWidgets('the 4th CIRCLED candidate renders when rule E fires '
        '(the 3rd was below the 0.2 K margin)', (tester) async {
      // 9/14..9/17 all 36.5 (+0.1 above the baseline): the 3rd candidate is
      // below the rule-D margin, so the 4th candidate triggers rule E —
      // and all four render as circles. The 5th (9/18) stays unmarked.
      final entries = [
        ..._evaluationEntries.take(8),
        DailyEntry(date: _mon14, bbtC: 36.5),
        DailyEntry(date: _tue15, bbtC: 36.5),
        DailyEntry(date: _wed16, bbtC: 36.5),
        DailyEntry(date: _thu17, bbtC: 36.5),
        DailyEntry(date: _fri18, bbtC: 36.5),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: _marks));

      for (final index in [8, 9, 10, 11]) {
        expect(
          dotPainter(tester, index),
          isA<RingDotPainter>(),
          reason: 'the 4th circled candidate exists under rule E',
        );
      }
      expect(dotPainterOrNull(tester, 12), isNotNull);
      expect(
        dotPainter(tester, 12),
        isNot(isA<RingDotPainter>()),
        reason: 'the sequence ended at the rule-E trigger',
      );
    });

    testWidgets('a MIXED sequence: the peak-day candidate is an arrow and '
        'circles follow it chronologically (R4 per candidate)', (tester) async {
      // The peak mark sits ON 9/15 (idx 9), between the marked rise (9/14)
      // and the later candidates: 9/14 and the peak day's own candidate are
      // ARROWS; everything strictly after the peak (9/16..9/18) is
      // CIRCLED, with the circle ordinals restarting at 1 (the 3rd circle,
      // 9/18 at 37.0, is >= 0.2 K above the baseline -> rule D fires and
      // ends the sequence there).
      final entries = [..._evaluationEntries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 37.0));
      final marks = [
        CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        CycleMark(date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: marks));

      // Collected kinds across the whole curve, indexed by day.
      final (:arrows, rings: circles) = candidateKinds(tester);

      // At or before the peak day (9/14, 9/15): arrows.
      expect(
        arrows,
        {8, 9},
        reason:
            'candidates at or before the peak are arrows (R4) — '
            'the peak day itself included',
      );
      // Strictly after the peak (9/16..9/18): circles.
      expect(circles, {
        10,
        11,
        12,
      }, reason: 'candidates after the peak are circles (R4)');
      // Chronological arrows-then-circles — no interleaving.
      expect(
        arrows.every((a) => circles.every((c) => a < c)),
        isTrue,
        reason: 'arrows precede circles (R4)',
      );
    });
  });

  group('numbering', () {
    testWidgets('the six low days carry 1–6 inside the plot, counted back '
        'from the first higher', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/13..9/8 (idx 7..2) = numbers 1..6.
      expect(numberUnder(tester, 7), '1');
      expect(numberUnder(tester, 6), '2');
      expect(numberUnder(tester, 5), '3');
      expect(numberUnder(tester, 4), '4');
      expect(numberUnder(tester, 3), '5');
      expect(numberUnder(tester, 2), '6');
      // Outside the six-window: no numbers.
      expect(numberUnder(tester, 0), isNull, reason: '9/6: outside the window');
      expect(numberUnder(tester, 1), isNull, reason: '9/7: 7th prior day');
      expect(
        numberUnder(tester, 8),
        isNull,
        reason: '9/14: the first higher itself is not a low',
      );
    });

    testWidgets('the numbers render in the primary color, bold and small', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      final ink = tester.widget<Text>(dayNumberGlyph(7, 1)).style!;
      expect(ink.color, chartScheme(tester).primary);
      expect(ink.fontWeight, FontWeight.bold);
      expect(ink.fontSize, 9);
    });

    testWidgets('a surface-colored halo layer renders behind the number '
        'ink at the same spot', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      final halo = find.byKey(const ValueKey('inPlotHaloDayNumber-7-1'));
      expect(halo, findsOneWidget, reason: 'one halo layer behind the ink');
      expect(
        tester.getRect(halo).center,
        tester.getRect(dayNumberGlyph(7, 1)).center,
        reason: 'the halo is centered exactly behind its ink glyph',
      );
    });

    testWidgets('the numbers share one bottom row inside the plot and center '
        'under their day column', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      // The numbers ride one bottom-anchored row: the same center height on
      // every numbered day, inside the plot's bottom half. The exact offset
      // above the scale min is the owner-eyeball row pitch — not pinned.
      final plot = tester.getRect(find.byType(LineChart));
      final numberYs = <double>[];
      for (var i = 2; i <= 7; i++) {
        final glyph = tester.getRect(
          find.byKey(ValueKey('inPlotDayNumber-$i-${8 - i}')),
        );
        numberYs.add(glyph.center.dy);
        expect(
          glyph.center.dx,
          closeTo(chartDotX(tester, i), 1),
          reason: 'day $i: the number centers under its day column',
        );
      }
      expect(
        numberYs,
        everyElement(numberYs.first),
        reason: 'every numbered day shares the same bottom row height',
      );
      expect(
        numberYs.first,
        greaterThan(plot.center.dy),
        reason: 'the numbers row sits in the plot\'s bottom half',
      );
      expect(
        numberYs.first,
        lessThan(plot.bottom),
        reason: 'the numbers row stays inside the plot',
      );
    });
  });

  group('baseline — R10 segment', () {
    testWidgets('the baseline draws as a SEGMENT: from the left edge of '
        'low #6\'s column to the last marked candidate (+ half a day), '
        'clamped to the plot bounds', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      final bars = _baselineBars(tester);
      expect(bars, hasLength(1), reason: 'one evaluated cycle -> one segment');
      final bar = bars.single;
      expect(
        bar.color,
        chartScheme(tester).secondary,
        reason: 'the baseline keeps its theme-derived secondary color',
      );
      expect(
        bar.dashArray,
        baselineDashPattern,
        reason: 'the dashed style stays',
      );
      // START: the left edge of low #6's column — low #6 is 9/8 (idx 2),
      // so the segment begins at x 1.5.
      // END: the last marked candidate (9/16, idx 10 — the rule-D trigger)
      // plus half a day = x 10.5 — the domain extends half a column past
      // the last day, so the clamp no longer bites here.
      final first = bar.spots.first;
      final last = bar.spots.last;
      expect(
        first.x,
        closeTo(1.5, 1e-9),
        reason: 'the segment starts under low #6 (left column edge)',
      );
      expect(
        last.x,
        closeTo(10.5, 1e-9),
        reason:
            'last candidate idx 10 + half a day, inside the domain '
            '(lastX = dayCount − 0.5 = 10.5)',
      );
      expect(first.y, 36.4);
      expect(last.y, 36.4, reason: 'the segment runs at the baseline value');
    });

    testWidgets('the segment ends half a day past the last candidate\'s '
        'column when recorded days continue past it', (tester) async {
      // 9/17 sits AT the baseline (36.4): a gap day, not a candidate — the
      // sequence ended at the rule-D trigger on 9/16, so the R10 segment
      // ends at 9/16's day column + half a day = x 10.5 (no clamp needed).
      final entries = [
        ..._evaluationEntries,
        DailyEntry(date: _thu17, bbtC: 36.4),
      ];
      await pumpChart(tester, chartHarness(entries: entries, marks: _marks));

      final spots = _baselineBars(tester).single.spots;
      expect(
        spots.first.x,
        closeTo(1.5, 1e-9),
        reason: 'the segment starts under low #6 (left column edge)',
      );
      expect(
        spots.last.x,
        closeTo(10.5, 1e-9),
        reason: 'last marked candidate 9/16 (idx 10) + half a day',
      );
    });

    testWidgets('no marked candidate -> no baseline segment', (tester) async {
      // Peak only: no first-higher mark, so no low window and no segment.
      await pumpChart(
        tester,
        chartHarness(
          entries: _evaluationEntries,
          marks: [CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay)],
        ),
      );
      expect(_baselineBars(tester), isEmpty);

      // First higher marked, but every day from the rise on sits AT or
      // below the baseline: no marked candidate exists, so R10 draws no
      // segment at all (not even a partial one through the low window).
      final flat = [
        for (final e in _evaluationEntries)
          e.date.isAfter(_sun13) ? DailyEntry(date: e.date, bbtC: 36.4) : e,
      ];
      await pumpChart(tester, chartHarness(entries: flat, marks: _marks));
      expect(
        _baselineBars(tester),
        isEmpty,
        reason: 'R10: a cycle with no marked candidate draws no segment',
      );
    });
  });

  group('no marks', () {
    testWidgets('nothing evaluation-related is drawn when no marks exist', (
      tester,
    ) async {
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: const []),
      );

      expect(
        _baselineBars(tester),
        isEmpty,
        reason: 'no marks -> no baseline segment',
      );
      for (var i = 0; i < 11; i++) {
        expect(
          numberUnder(tester, i),
          isNull,
          reason: 'no marks -> no numbers',
        );
        expect(
          inPlotPeakDot(i),
          findsNothing,
          reason: 'no marks -> no peak dot',
        );
      }
      final kinds = candidateKinds(tester);
      expect(kinds.rings, isEmpty);
      expect(kinds.arrows, isEmpty);
    });
  });

  group('all mucus peaks render (from the marks stream)', () {
    testWidgets('two peak marks in one cycle render two solid dots — even '
        'when no evaluation exists, and still alongside a full evaluation', (
      tester,
    ) async {
      // ONLY peak marks: without a first-higher mark no evaluation can
      // exist, yet every placed peak must render — the dots come from the
      // MARKS STREAM, not from the single domain-anchored peak.
      await pumpChart(
        tester,
        chartHarness(
          entries: _evaluationEntries,
          marks: [
            CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
            CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
          ],
        ),
      );

      expect(
        inPlotPeakDot(6),
        findsOneWidget,
        reason: 'the first peak renders',
      );
      expect(
        inPlotPeakDot(9),
        findsOneWidget,
        reason:
            'the second peak renders too, though the evaluation has '
            'nothing to anchor (no rise marked)',
      );
      expect(
        inPlotPeakDot(8),
        findsNothing,
        reason: 'a day without a peak mark renders no dot',
      );

      await pumpFreshChart(
        tester,
        () => chartHarness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
          ],
        ),
      );
      expect(inPlotPeakDot(6), findsOneWidget);
      expect(inPlotPeakDot(9), findsOneWidget);
    });
  });

  group('SUZ marks render (user-placed only)', () {
    // The glyph's top anchoring: the bar hangs DOWN from the chart's top
    // border and the arrow anchors inside the hung band, so the whole glyph
    // sits inside the top rows of the plot. The drop/inset sizes are
    // owner-eyeball values (shared with the PDF export via suz_glyph.dart —
    // the cross-surface parity contract the lib layer owns), so the tests
    // keep the anchor relations only, not the numeric offsets.
    testWidgets('a suzEvening mark renders a vertical bar hanging from the '
        'chart\'s top border at the column middle, plus a right-pointing '
        'arrow whose base starts at the bar near the top', (tester) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _wed16, type: CycleMarkTypes.suzEvening),
          ],
        ),
      );

      final data = chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1), reason: 'one user SUZ mark -> one bar');
      final bar = bars.single;
      // suzEvening anchors the bar at the day column's MIDDLE (x = day
      // index); the bar hangs DOWN from the chart's top border by a fixed
      // °C drop instead of spanning the whole plot height.
      expect(
        bar.spots.first.x,
        10.0,
        reason: 'suzEvening anchors at the column middle (9/16, idx 10)',
      );
      expect(bar.spots.last.x, 10.0);
      expect(
        bar.spots.first.y,
        data.maxY,
        reason: 'the bar hangs from the chart\'s top border',
      );
      expect(
        bar.spots.last.y,
        lessThan(data.maxY),
        reason:
            'the bar spans a °C drop below the top border instead of '
            'spanning the whole plot height',
      );
      expect(
        bar.spots.last.y,
        greaterThan(data.minY),
        reason: 'the hang stops short of the plot\'s bottom border',
      );
      expect(
        bar.color,
        chartScheme(tester).secondary,
        reason:
            'the SUZ bar shares the baseline\'s evaluation-family '
            'color role (secondary)',
      );

      // The right-pointing arrow: base at the bar, anchored inside the
      // hung band (no longer at the cycle's baseline value — the
      // baseline-anchor concept is retired).
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull, reason: 'the SUZ arrow renders with the bar');
      final (spot, painter) = arrow!;
      expect(spot.x, 10.0, reason: 'the arrow base starts at the bar');
      expect(
        spot.y,
        lessThan(data.maxY),
        reason: 'the arrow anchors below the top border, inside the hung band',
      );
      expect(
        spot.y,
        greaterThan(bar.spots.last.y),
        reason: 'the arrow anchors above the bar\'s lower end — the hung band',
      );
      expect(painter, isA<SuzArrowDotPainter>());
      expect(
        (painter as SuzArrowDotPainter).color,
        chartScheme(tester).secondary,
        reason: 'the SUZ arrow shares the evaluation-family color role',
      );
    });

    testWidgets('a suzMorning mark anchors the bar at the column START '
        '(x − 0.5)', (tester) async {
      await pumpChart(
        tester,
        chartHarness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _tue15, type: CycleMarkTypes.suzMorning),
          ],
        ),
      );

      final bars = _suzBars(tester);
      expect(bars, hasLength(1));
      final bar = bars.single;
      expect(
        bar.spots.first.x,
        8.5,
        reason: 'suzMorning anchors at the column start (9/15, idx 9 − 0.5)',
      );
      expect(bar.spots.last.x, 8.5);
      // The hang-span/inset values do not depend on the x anchoring — the
      // top-anchor relations live on the suzEvening test above.
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull);
      expect(arrow!.$1.x, 8.5, reason: 'the arrow base starts at the bar');
    });

    testWidgets(
      'a suzMorning mark on the FIRST recorded day anchors the bar at '
      'the plot\'s left edge (x − 0.5 = minX, no cut-back)',
      (tester) async {
        // With the half-column-shifted domain the first day's column starts
        // at −0.5, so its column-START bar sits exactly at the plot's left
        // edge instead of being clamped onto the day index.
        await pumpChart(
          tester,
          chartHarness(
            entries: _evaluationEntries,
            marks: [
              ..._marks,
              CycleMark(date: _sun6, type: CycleMarkTypes.suzMorning),
            ],
          ),
        );

        final bars = _suzBars(tester);
        expect(bars, hasLength(1));
        final bar = bars.single;
        expect(
          bar.spots.first.x,
          -0.5,
          reason: 'day 0\'s column start is the domain\'s minX (−0.5)',
        );
        expect(bar.spots.last.x, -0.5);
        // The clamping concerns only x — the top-anchor y relations are the
        // shared glyph behavior tested on the suzEvening bar above.
        final arrow = _suzArrowSpot(tester);
        expect(arrow, isNotNull);
        expect(arrow!.$1.x, -0.5, reason: 'the arrow base starts at the bar');
      },
    );

    testWidgets('no SUZ glyph renders without a user mark — the computed '
        'suzBegins suggests only, it never renders', (tester) async {
      // The main scenario's arithmetic fires rule D on 9/16 — but no user
      // SUZ mark exists, so the chart draws no SUZ bar and no arrow.
      await pumpChart(
        tester,
        chartHarness(entries: _evaluationEntries, marks: _marks),
      );

      expect(
        _suzBars(tester),
        isEmpty,
        reason: 'the computed SUZ never renders on the chart',
      );
      expect(_suzArrowSpot(tester), isNull);
    });
  });

  group('latest-rise anchor renders in the UI (re-marking supersedes)', () {
    testWidgets(
      'two rise marks: the LATER one drives the evaluation; the earlier '
      'rise day renders no candidate',
      (tester) async {
        // Two firstHigher marks: 9/14 and 9/15. The LATER mark (9/15) anchors
        // the evaluation — and re-derives the six-low window with it (R9):
        // the lows before 9/15 are 9/9..9/14, so the baseline moves to 9/14's
        // 36.9 (the earlier rise mark's day itself becomes a low!). From the
        // walk start 9/15: 9/15 sits AT the new baseline (gap day, no
        // candidate), 9/16 (37.0) is circle #1 — no SUZ with a single circle.
        // Under the old earliest-anchor semantics the circles would be
        // {8, 9, 10} against the 36.4 baseline; the later mark wins instead.
        await pumpChart(
          tester,
          chartHarness(
            entries: _evaluationEntries,
            marks: [
              CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
              CycleMark(
                date: _mon14,
                type: CycleMarkTypes.firstHigherMeasurement,
              ),
              CycleMark(
                date: _tue15,
                type: CycleMarkTypes.firstHigherMeasurement,
              ),
            ],
          ),
        );

        final rings = candidateKinds(tester).rings;
        expect(
          rings,
          {10},
          reason:
              'the LATEST rise mark anchors the evaluation: the '
              're-derived baseline (36.9 through the earlier rise day, now '
              'low #1) leaves 9/16 as the only candidate',
        );
        // The earlier rise mark's day (9/14, idx 8) renders no candidate —
        // it sits at the new baseline as a low.
        expect(
          dotPainter(tester, 8),
          isNot(isA<RingDotPainter>()),
          reason: 'the earlier rise mark renders no candidate',
        );
        expect(dotPainter(tester, 8), isNot(isA<ArrowUpDotPainter>()));
        // And the marked rise day itself (9/15) sits at the re-derived
        // baseline: no candidate there either.
        expect(dotPainter(tester, 9), isNot(isA<RingDotPainter>()));
        expect(dotPainter(tester, 9), isNot(isA<ArrowUpDotPainter>()));
      },
    );
  });

  testWidgets('the bottom-anchored day numbers hide when the span drops '
      'below 0.10 and stay visible at the boundary', (tester) async {
    // Numbers hidden: the center at min + 0.05 = 36.05 exceeds max − 0.05
    // = 36.03 when the span is 0.08.
    await pumpChart(
      tester,
      chartHarness(
        entries: _evaluationEntries,
        marks: _marks,
        temperatureRange: const TemperatureRange(min: 36.0, max: 36.08),
      ),
    );
    for (var i = 0; i < _evaluationEntries.length; i++) {
      expect(
        numberUnder(tester, i),
        isNull,
        reason: 'day $i: the 0.08 K span hides the numbers row',
      );
    }

    // Boundary span 0.10: the center at min + 0.05 = max − 0.05 — visible.
    await pumpFreshChart(
      tester,
      () => chartHarness(
        entries: _evaluationEntries,
        marks: _marks,
        temperatureRange: const TemperatureRange(min: 36.0, max: 36.1),
      ),
    );
    expect(
      numberUnder(tester, 7),
      '1',
      reason: 'the numbers row reads the boundary equality as visible',
    );
  });
}
