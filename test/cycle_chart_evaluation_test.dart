// Widget tests of the computed evaluation marks on the cycle chart (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks; the UI
// derives and renders the candidate circles/arrows (kind decided PER
// CANDIDATE: arrows at or before the peak day, circles strictly after — R4),
// the solid peak dot in the symbol row, the 1–6 low numbering and the
// baseline SEGMENT (low #6 to the last marked candidate — R10). Derived
// artifacts are computed at render time only — these tests pin how the
// artifacts of lib/domain/evaluation.dart surface on the chart.
//
// Same harness pattern as test/cycle_chart_weekend_test.dart (ProviderScope
// with fixed entry/marks streams).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-03 is a Thursday, so this sequence runs Sun (9/6) .. Wed (9/16).
// Day indexes: 9/6 -> 0 ... 9/16 -> 10.
final _sun6 = DateTime.utc(2026, 9, 6);
final _mon7 = DateTime.utc(2026, 9, 7);
final _tue8 = DateTime.utc(2026, 9, 8);
final _wed9 = DateTime.utc(2026, 9, 9);
final _thu10 = DateTime.utc(2026, 9, 10);
final _fri11 = DateTime.utc(2026, 9, 11);
final _sat12 = DateTime.utc(2026, 9, 12);
final _sun13 = DateTime.utc(2026, 9, 13);
final _mon14 = DateTime.utc(2026, 9, 14);
final _tue15 = DateTime.utc(2026, 9, 15);
final _wed16 = DateTime.utc(2026, 9, 16);
final _thu17 = DateTime.utc(2026, 9, 17);
final _fri18 = DateTime.utc(2026, 9, 18);

/// Main evaluation scenario (peak before the rise -> CIRCLES):
///
/// - 9/6 (idx 0): 36.9 — a rise BEFORE the marked first higher: never a
///   candidate (R3), renders as an ordinary temperature dot.
/// - 9/7 (idx 1): 36.3 — the 7th day before the first higher, outside the
///   six-low window -> no number.
/// - 9/8..9/13 (idx 2..7): the six low measurements, numbered BACK from the
///   first higher (9/13 = 1 ... 9/8 = 6).
/// - 9/9 (idx 3, 36.4): the HIGHEST of the six lows -> baseline 36.4.
/// - 9/12 (idx 6): mucus-peak mark -> SOLID DOT in the symbol row (R6),
///   NO ring on the temperature curve.
/// - 9/14 (idx 8): first-higher mark; 36.9 -> circled #1.
/// - 9/15 (idx 9): 36.9 -> circled #2.
/// - 9/16 (idx 10): 37.0 -> circled #3, >= 0.2 K above the baseline ->
///   rule D fires, the sequence ends here (SUZ evening).
final _entries = <DailyEntry>[
  DailyEntry(date: _sun6, bbtC: 36.9),
  DailyEntry(date: _mon7, bbtC: 36.3),
  DailyEntry(date: _tue8, bbtC: 36.2),
  DailyEntry(date: _wed9, bbtC: 36.4),
  DailyEntry(date: _thu10, bbtC: 36.3),
  DailyEntry(date: _fri11, bbtC: 36.1),
  DailyEntry(date: _sat12, bbtC: 36.2),
  DailyEntry(date: _sun13, bbtC: 36.3),
  DailyEntry(date: _mon14, bbtC: 36.9),
  DailyEntry(date: _tue15, bbtC: 36.9),
  DailyEntry(date: _wed16, bbtC: 37.0),
];

/// The mucus-peak mark lies BEFORE the first higher measurement (9/12 <
/// 9/14), so the candidates render CIRCLED (R4).
final _marks = <CycleMark>[
  CycleMark(profileId: 1, date: _sat12, type: CycleMarkTypes.mucusPeakDay),
  CycleMark(
      profileId: 1, date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
];

Widget _harness(
        {required List<DailyEntry> entries, required List<CycleMark> marks}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ProviderScope(
        overrides: [
          dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          marksProvider.overrideWith((ref) => Stream.value(marks)),
          selectedDateProvider.overrideWith((ref) => entries.first.date),
        ],
        child: const Scaffold(body: ZyklusScreen()),
      ),
    );

LineChartData _chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

/// The dot-only bars (invisible line) whose per-spot dot painters decide how
/// each temperature renders.
List<LineChartBarData> _dotBars(WidgetTester tester) =>
    _chartData(tester).lineBarsData.where((bar) {
      final color = bar.color;
      return color == null || color.a == 0;
    }).toList();

/// The baseline segment bars (R10): the dashed two-spot bars drawn in the
/// baseline color (secondary) — one per evaluated cycle with a marked
/// candidate. Horizontal by construction, so the vertical SUZ bars (same
/// secondary color) are excluded here.
List<LineChartBarData> _baselineBars(WidgetTester tester) => _chartData(tester)
    .lineBarsData
    .where((bar) =>
        bar.color == _scheme(tester).secondary &&
        bar.spots.first.y == bar.spots.last.y)
    .toList();

/// The SUZ bars: vertical two-spot bars in the secondary color (one per
/// user-placed SUZ mark) — the same evaluation-family color as the baseline
/// segment, distinguished by orientation.
List<LineChartBarData> _suzBars(WidgetTester tester) => _chartData(tester)
    .lineBarsData
    .where((bar) =>
        bar.color == _scheme(tester).secondary &&
        bar.spots.first.x == bar.spots.last.x)
    .toList();

/// The SUZ arrow: the spot + painter of the SUZ arrow glyph, or null when
/// no user SUZ mark renders an arrow.
(FlSpot, FlDotPainter)? _suzArrowSpot(WidgetTester tester) {
  for (final bar in _dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final painter = bar.dotData.getDotPainter(bar.spots[i], 0, bar, i);
      if (painter is SuzArrowDotPainter) return (bar.spots[i], painter);
    }
  }
  return null;
}

/// The dot painter the chart would use for the temperature dot of [dayIndex]
/// (fails when that day has no temperature point on the chart).
FlDotPainter _dotPainter(WidgetTester tester, int dayIndex) {
  for (final bar in _dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final spot = bar.spots[i];
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, i);
      }
    }
  }
  fail('no temperature dot at day index $dayIndex');
}

/// The dot painter for a day index, or null when the day has no temperature
/// point on the chart.
FlDotPainter? _dotPainterOrNull(WidgetTester tester, int dayIndex) {
  for (final bar in _dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final spot = bar.spots[i];
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, i);
      }
    }
  }
  return null;
}

/// The number shown in the marks row under [dayIndex], or null when none.
String? _numberUnder(WidgetTester tester, int dayIndex) {
  final texts = tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey('marksCell-$dayIndex')),
        matching: find.byType(Text),
      ))
      .toList();
  return texts.isEmpty ? null : texts.single.data;
}

ColorScheme _scheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme;

/// The peak-dot slot inside the symbol-row cell of [dayIndex].
Finder _peakDot(int dayIndex) => find.byKey(ValueKey('peakDot-$dayIndex'));

void main() {
  group(
      'R6 — the peak renders as a solid dot in the symbol row, not on '
      'the curve', () {
    testWidgets(
        'the peak day keeps a plain temperature dot — no ring on '
        'the curve', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/12 (idx 6) carries the mucus-peak mark: the curve dot there is
      // an ORDINARY temperature dot — the ring painter is gone from the
      // peak day (R6).
      final painter = _dotPainter(tester, 6);
      expect(painter, isNot(isA<RingDotPainter>()),
          reason: 'the peak ring was removed from the temperature curve');
      expect(painter, isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets(
        'curve rings exist only for the candidate measurements, '
        'not for the peak', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // Walk every temperature dot: a ring appears exactly on the three
      // circled candidates (idx 8..10), never on the peak day (idx 6).
      final ringIndexes = <int>{};
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is RingDotPainter) ringIndexes.add(spot.x.round());
        }
      }
      expect(ringIndexes, {8, 9, 10},
          reason: 'rings wrap only the circled candidates (R6/R1)');
      for (final index in ringIndexes) {
        final painter = _dotPainter(tester, index) as RingDotPainter;
        expect(painter.ringColor, _scheme(tester).primary,
            reason: 'circled candidates are temperature-family');
      }
    });

    testWidgets(
        'the peak renders as a solid dot ABOVE the mucus glyph in '
        'the symbol row (classic NER position)', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/12 (idx 6) carries the peak mark -> solid dot in the symbol row.
      expect(_peakDot(6), findsOneWidget);
      // Neighboring days carry no peak dot.
      expect(_peakDot(5), findsNothing);
      expect(_peakDot(7), findsNothing);

      // The dot sits ABOVE the mucus glyph of the same cell.
      final dotTop = tester.getTopLeft(find.byKey(ValueKey('peakDot-6'))).dy;
      final mucusTop = tester
          .getTopLeft(find
              .descendant(
                of: find.byKey(const ValueKey('symbolCell-6')),
                matching: find.byType(MucusSymbolText),
              )
              .first)
          .dy;
      expect(dotTop, lessThan(mucusTop),
          reason: 'the peak dot renders above the mucus entry (R6)');

      // The dot is SOLID and in the mucus color family (tertiary).
      final dot = tester.widget<Container>(_peakDot(6));
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, _scheme(tester).tertiary,
          reason: 'the peak belongs to the mucus color family');
    });

    testWidgets(
        'a peak day without an entry keeps rendering no dot and '
        'does not crash', (tester) async {
      // 9/12 has NO entry at all: the symbol cell stays empty (flagged
      // rendering assumption, see cycle.dart).
      final entries = _entries.where((e) => !_sameDay(e, _sat12)).toList();
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsNothing,
          reason: 'no entry -> the symbol row renders nothing for the day');
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          // The circled candidates (idx 8..10) are unaffected by the
          // missing peak entry; what must be ABSENT is the peak ring —
          // i.e. no ring in the mucus color family (tertiary).
          if (painter is RingDotPainter) {
            expect(painter.ringColor, isNot(_scheme(tester).tertiary));
          }
        }
      }
    });
  });

  group('R1/R4 — candidate circles and arrows follow the new decision', () {
    testWidgets(
        'circled candidates: every measured day above the baseline '
        'from the rise onward, capped and ended by rule D', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // The candidates (idx 8..10) render circled ...
      for (final index in [8, 9, 10]) {
        final painter = _dotPainter(tester, index);
        expect(painter, isA<RingDotPainter>(),
            reason: 'circled higher measurement at day index $index');
        expect((painter as RingDotPainter).ringColor, _scheme(tester).primary,
            reason: 'circled higher measurements are temperature-family');
      }
      // ... the pre-rise rise (idx 0, 36.9 above the baseline 36.4) is NOT
      // a candidate (R3) — an ordinary dot.
      expect(_dotPainter(tester, 0), isNot(isA<RingDotPainter>()));
      expect(_dotPainter(tester, 0), isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets(
        'the four-cap: four arrows carry ordinals; the beyond-cap '
        'arrow STAYS in the sequence — unnumbered, but still an arrow '
        '(R4: a late sequence is not cut off at the cap)', (tester) async {
      // Peak unmarked: every candidate (R4) becomes an arrow. Five
      // above-baseline days exist (9/14..9/18) and all five render — the
      // 5th is beyond its kind's cap, so it carries no ordinal, but it
      // stays part of the connected sequence (R4): the sequence only ends
      // at a SUZ trigger or a break, and arrows never trigger a SUZ.
      final entries = [..._entries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 36.5));
      final marks = [
        CycleMark(
            profileId: 1,
            date: _mon14,
            type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: marks));
      await tester.pumpAndSettle();

      for (final index in [8, 9, 10, 11, 12]) {
        expect(_dotPainter(tester, index), isA<ArrowUpDotPainter>(),
            reason: 'no peak -> arrow at $index (R4; the '
                'beyond-cap candidate renders unnumbered)');
      }
      // Nothing is circled anywhere.
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          expect(painter, isNot(isA<RingDotPainter>()));
        }
      }
    });

    testWidgets(
        'the 4th CIRCLED candidate renders when rule E fires '
        '(the 3rd was below the 0.2 K margin)', (tester) async {
      // 9/14..9/17 all 36.5 (+0.1 above the baseline): the 3rd candidate is
      // below the rule-D margin, so the 4th candidate triggers rule E —
      // and all four render as circles. The 5th (9/18) stays unmarked.
      final entries = [
        ..._entries.take(8),
        DailyEntry(date: _mon14, bbtC: 36.5),
        DailyEntry(date: _tue15, bbtC: 36.5),
        DailyEntry(date: _wed16, bbtC: 36.5),
        DailyEntry(date: _thu17, bbtC: 36.5),
        DailyEntry(date: _fri18, bbtC: 36.5),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      for (final index in [8, 9, 10, 11]) {
        expect(_dotPainter(tester, index), isA<RingDotPainter>(),
            reason: 'the 4th circled candidate exists under rule E');
      }
      expect(_dotPainterOrNull(tester, 12), isNotNull);
      expect(_dotPainter(tester, 12), isNot(isA<RingDotPainter>()),
          reason: 'the sequence ended at the rule-E trigger');
    });

    testWidgets(
        'a MIXED sequence: the peak-day candidate is an arrow and '
        'circles follow it chronologically (R4 per candidate)', (tester) async {
      // The peak mark sits ON 9/15 (idx 9), between the marked rise (9/14)
      // and the later candidates: 9/14 and the peak day's own candidate are
      // ARROWS; everything strictly after the peak (9/16..9/18) is
      // CIRCLED, with the circle ordinals restarting at 1 (the 3rd circle,
      // 9/18 at 37.0, is >= 0.2 K above the baseline -> rule D fires and
      // ends the sequence there).
      final entries = [..._entries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 37.0));
      final marks = [
        CycleMark(
            profileId: 1, date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        CycleMark(
            profileId: 1,
            date: _mon14,
            type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: marks));
      await tester.pumpAndSettle();

      // Collected kinds across the whole curve, indexed by day.
      final arrows = <int>{};
      final circles = <int>{};
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is ArrowUpDotPainter) arrows.add(spot.x.round());
          if (painter is RingDotPainter) circles.add(spot.x.round());
        }
      }

      // At or before the peak day (9/14, 9/15): arrows.
      expect(arrows, {8, 9},
          reason: 'candidates at or before the peak are arrows (R4) — '
              'the peak day itself included');
      // Strictly after the peak (9/16..9/18): circles.
      expect(circles, {10, 11, 12},
          reason: 'candidates after the peak are circles (R4)');
      // Chronological arrows-then-circles — no interleaving.
      expect(arrows.every((a) => circles.every((c) => a < c)), isTrue,
          reason: 'arrows precede circles (R4)');
    });
  });

  group('numbering', () {
    testWidgets(
        'the six low days carry 1–6, counted back from the first '
        'higher', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/13..9/8 (idx 7..2) = numbers 1..6.
      expect(_numberUnder(tester, 7), '1');
      expect(_numberUnder(tester, 6), '2');
      expect(_numberUnder(tester, 5), '3');
      expect(_numberUnder(tester, 4), '4');
      expect(_numberUnder(tester, 3), '5');
      expect(_numberUnder(tester, 2), '6');
      // Outside the six-window: no numbers.
      expect(_numberUnder(tester, 0), isNull,
          reason: '9/6: outside the window');
      expect(_numberUnder(tester, 1), isNull, reason: '9/7: 7th prior day');
      expect(_numberUnder(tester, 8), isNull,
          reason: '9/14: the first higher itself is not a low');
    });
  });

  group('baseline — R10 segment', () {
    testWidgets(
        'the baseline draws as a SEGMENT: from the left edge of '
        'low #6\'s column to the last marked candidate (+ half a day), '
        'clamped to the recorded range', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      final bars = _baselineBars(tester);
      expect(bars, hasLength(1), reason: 'one evaluated cycle -> one segment');
      final bar = bars.single;
      expect(bar.color, _scheme(tester).secondary,
          reason: 'the baseline keeps its theme-derived secondary color');
      expect(bar.dashArray, const [6, 4], reason: 'the dashed style stays');
      // START: the left edge of low #6's column — low #6 is 9/8 (idx 2),
      // so the segment begins at x 1.5.
      // END: the last marked candidate (9/16, idx 10 — the rule-D trigger)
      // plus half a day = x 10.5, but the chart's last recorded day is
      // also idx 10 (no data to the right), so the clamp holds it at 10.
      final first = bar.spots.first;
      final last = bar.spots.last;
      expect(first.x, closeTo(1.5, 1e-9),
          reason: 'the segment starts under low #6 (left column edge)');
      expect(last.x, closeTo(10.0, 1e-9),
          reason: 'the half-day padding is clamped by the chart edge here');
      expect(first.y, 36.4);
      expect(last.y, 36.4, reason: 'the segment runs at the baseline value');
    });

    testWidgets(
        'the segment ends half a day past the last candidate\'s '
        'column when recorded days continue past it', (tester) async {
      // 9/17 sits AT the baseline (36.4): a gap day, not a candidate — the
      // sequence ended at the rule-D trigger on 9/16, so the R10 segment
      // ends at 9/16's day column + half a day = x 10.5 (no clamp needed).
      final entries = [..._entries, DailyEntry(date: _thu17, bbtC: 36.4)];
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      final spots = _baselineBars(tester).single.spots;
      expect(spots.first.x, closeTo(1.5, 1e-9),
          reason: 'the segment starts under low #6 (left column edge)');
      expect(spots.last.x, closeTo(10.5, 1e-9),
          reason: 'last marked candidate 9/16 (idx 10) + half a day');
    });

    testWidgets('no marked candidate -> no baseline segment', (tester) async {
      // Peak only: no first-higher mark, so no low window and no segment.
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          CycleMark(
              profileId: 1, date: _sat12, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();
      expect(_baselineBars(tester), isEmpty);

      // First higher marked, but every day from the rise on sits AT or
      // below the baseline: no marked candidate exists, so R10 draws no
      // segment at all (not even a partial one through the low window).
      final flat = [
        for (final e in _entries)
          e.date.isAfter(_sun13) ? DailyEntry(date: e.date, bbtC: 36.4) : e,
      ];
      await tester.pumpWidget(_harness(entries: flat, marks: _marks));
      await tester.pumpAndSettle();
      expect(_baselineBars(tester), isEmpty,
          reason: 'R10: a cycle with no marked candidate draws no segment');
    });
  });

  group('no marks', () {
    testWidgets('nothing evaluation-related is drawn when no marks exist',
        (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: const []));
      await tester.pumpAndSettle();

      expect(_baselineBars(tester), isEmpty,
          reason: 'no marks -> no baseline segment');
      for (var i = 0; i < 11; i++) {
        expect(_numberUnder(tester, i), isNull,
            reason: 'no marks -> no numbers');
        expect(_peakDot(i), findsNothing, reason: 'no marks -> no peak dot');
      }
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          expect(painter, isNot(isA<RingDotPainter>()));
          expect(painter, isNot(isA<ArrowUpDotPainter>()));
        }
      }
    });
  });

  group('legend', () {
    testWidgets(
        'the legend explains the new glyphs: solid peak dot, '
        'circled and arrowed higher measurements, baseline', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(find.text('Mucus peak'), findsOneWidget,
          reason: 'the solid-dot legend entry replaced the old ring entry');
      expect(find.text('Circled higher measurements'), findsOneWidget);
      expect(find.text('Higher measurement (arrow)'), findsOneWidget,
          reason: 'arrows now mean: no peak before the rise (R4)');
      expect(find.text('Baseline'), findsOneWidget);
      // The pre-peak wording is gone (R4 removed the special case).
      expect(find.text('Higher measurement before the peak'), findsNothing);
    });

    testWidgets('the legend explains the SUZ glyph', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(find.text('Sicher unfruchtbare Zeit (SUZ)'), findsOneWidget,
          reason: 'the SUZ bar+arrow glyph has its own legend entry');
    });
  });

  group('all mucus peaks render (from the marks stream)', () {
    testWidgets(
        'two peak marks in one cycle render two solid dots — even '
        'when no evaluation exists', (tester) async {
      // ONLY peak marks: without a first-higher mark no evaluation can
      // exist, yet every placed peak must render — the dots come from the
      // MARKS STREAM, not from the single domain-anchored peak.
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          CycleMark(
              profileId: 1, date: _sat12, type: CycleMarkTypes.mucusPeakDay),
          CycleMark(
              profileId: 1, date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsOneWidget, reason: 'the first peak renders');
      expect(_peakDot(9), findsOneWidget,
          reason: 'the second peak renders too, though the evaluation has '
              'nothing to anchor (no rise marked)');
      expect(_peakDot(8), findsNothing,
          reason: 'a day without a peak mark renders no dot');
    });

    testWidgets('two peaks render alongside a full evaluation', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          ..._marks,
          CycleMark(
              profileId: 1, date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsOneWidget);
      expect(_peakDot(9), findsOneWidget);
    });
  });

  group('SUZ marks render (user-placed only)', () {
    testWidgets(
        'a suzEvening mark renders a vertical bar at the column middle '
        'spanning the plot height, plus a right-pointing arrow whose '
        'base starts at the bar', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          ..._marks,
          CycleMark(
              profileId: 1, date: _wed16, type: CycleMarkTypes.suzEvening),
        ],
      ));
      await tester.pumpAndSettle();

      final data = _chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1), reason: 'one user SUZ mark -> one bar');
      final bar = bars.single;
      // suzEvening anchors the bar at the day column's MIDDLE (x = day
      // index); the bar spans the whole plot height.
      expect(bar.spots.first.x, 10.0,
          reason: 'suzEvening anchors at the column middle (9/16, idx 10)');
      expect(bar.spots.last.x, 10.0);
      expect(bar.spots.first.y, data.minY,
          reason: 'the bar spans the plot height');
      expect(bar.spots.last.y, data.maxY);
      expect(bar.color, _scheme(tester).secondary,
          reason: 'the SUZ bar shares the baseline\'s evaluation-family '
              'color role (secondary)');

      // The right-pointing arrow: base at the bar, vertically anchored at
      // the cycle's baseline value (geometry flagged for owner review).
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull, reason: 'the SUZ arrow renders with the bar');
      final (spot, painter) = arrow!;
      expect(spot.x, 10.0, reason: 'the arrow base starts at the bar');
      expect(spot.y, 36.4,
          reason: 'the arrow anchors at the cycle\'s baseline value');
      expect(painter, isA<SuzArrowDotPainter>());
      expect((painter as SuzArrowDotPainter).color, _scheme(tester).secondary,
          reason: 'the SUZ arrow shares the evaluation-family color role');
    });

    testWidgets(
        'a suzMorning mark anchors the bar at the column START '
        '(x − 0.5)', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          ..._marks,
          CycleMark(
              profileId: 1, date: _tue15, type: CycleMarkTypes.suzMorning),
        ],
      ));
      await tester.pumpAndSettle();

      final bars = _suzBars(tester);
      expect(bars, hasLength(1));
      final bar = bars.single;
      expect(bar.spots.first.x, 8.5,
          reason: 'suzMorning anchors at the column start (9/15, idx 9 − 0.5)');
      expect(bar.spots.last.x, 8.5);
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull);
      expect(arrow!.$1.x, 8.5, reason: 'the arrow base starts at the bar');
      expect(arrow.$1.y, 36.4,
          reason: 'the arrow anchors at the cycle\'s baseline value');
    });

    testWidgets(
        'no SUZ glyph renders without a user mark — the computed '
        'suzBeginsEvening suggests only, it never renders', (tester) async {
      // The main scenario's arithmetic fires rule D on 9/16 — but no user
      // SUZ mark exists, so the chart draws no SUZ bar and no arrow.
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(_suzBars(tester), isEmpty,
          reason: 'the computed SUZ never renders on the chart');
      expect(_suzArrowSpot(tester), isNull);
    });
  });

  group('latest-rise anchor renders in the UI (re-marking supersedes)', () {
    testWidgets(
        'two rise marks: the LATER one drives the evaluation; the earlier '
        'rise day renders no candidate', (tester) async {
      // Two firstHigher marks: 9/14 and 9/15. The LATER mark (9/15) anchors
      // the evaluation — and re-derives the six-low window with it (R9):
      // the lows before 9/15 are 9/9..9/14, so the baseline moves to 9/14's
      // 36.9 (the earlier rise mark's day itself becomes a low!). From the
      // walk start 9/15: 9/15 sits AT the new baseline (gap day, no
      // candidate), 9/16 (37.0) is circle #1 — no SUZ with a single circle.
      // Under the old earliest-anchor semantics the circles would be
      // {8, 9, 10} against the 36.4 baseline; the later mark wins instead.
      await tester.pumpWidget(_harness(
        entries: _entries,
        marks: [
          CycleMark(
              profileId: 1, date: _sat12, type: CycleMarkTypes.mucusPeakDay),
          CycleMark(
              profileId: 1,
              date: _mon14,
              type: CycleMarkTypes.firstHigherMeasurement),
          CycleMark(
              profileId: 1,
              date: _tue15,
              type: CycleMarkTypes.firstHigherMeasurement),
        ],
      ));
      await tester.pumpAndSettle();

      final rings = <int>{};
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is RingDotPainter) rings.add(spot.x.round());
        }
      }
      expect(rings, {10},
          reason: 'the LATEST rise mark anchors the evaluation: the '
              're-derived baseline (36.9 through the earlier rise day, now '
              'low #1) leaves 9/16 as the only candidate');
      // The earlier rise mark's day (9/14, idx 8) renders no candidate —
      // it sits at the new baseline as a low.
      expect(_dotPainter(tester, 8), isNot(isA<RingDotPainter>()),
          reason: 'the earlier rise mark renders no candidate');
      expect(_dotPainter(tester, 8), isNot(isA<ArrowUpDotPainter>()));
      // And the marked rise day itself (9/15) sits at the re-derived
      // baseline: no candidate there either.
      expect(_dotPainter(tester, 9), isNot(isA<RingDotPainter>()));
      expect(_dotPainter(tester, 9), isNot(isA<ArrowUpDotPainter>()));
    });
  });
}

/// Identity helper: true when [entry]'s date is exactly [day]'s calendar day
/// (used to patch the scenario above).
bool _sameDay(DailyEntry entry, DateTime day) =>
    entry.date.year == day.year &&
    entry.date.month == day.month &&
    entry.date.day == day.day;
