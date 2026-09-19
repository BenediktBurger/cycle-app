// Widget tests of the temperature curve's connectivity and interruption
// rendering: the line connects two temperatures ONLY when their calendar
// days are adjacent; ignored temperatures (a day carrying the
// ignoreTemperature MARK — the rendering is keyed to the mark, NOT to the
// raw disturbance mask, owner decision 2026-09-19) count as measured
// days, keep the line continuous, but render lighter (dot AND touching
// segments). The
// mark makes the state visible on the graph: a marked day without flags
// renders lighter, and a flagged day whose mark was removed renders
// normally again. Same harness pattern as test/cycle_chart_weekend_test.dart
// (with the marksProvider override pattern from the help-sheet tests).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chart_pump.dart';

// 2026-09-03 is a Thursday: Thu..Sun as a compact adjacent-day strip.
final _thu = DateTime.utc(2026, 9, 3);
final _fri = DateTime.utc(2026, 9, 4);
final _sat = DateTime.utc(2026, 9, 5);
final _sun = DateTime.utc(2026, 9, 6);

List<LineChartBarData> _bars(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;

/// The line bars the chart draws its polyline with, one entry per run of
/// adjacent days (dot-only bars, whose line is invisible, are ignored).
List<LineChartBarData> _segmentBars(WidgetTester tester) => [
      for (final bar in _bars(tester))
        if (bar.color != null && bar.color!.a > 0) bar,
    ];

/// True when some visible polyline bar connects exactly the two day indexes.
bool _connects(WidgetTester tester, int a, int b) =>
    _segmentBars(tester).any((bar) =>
        bar.spots.length == 2 &&
        bar.spots[0].x == a.toDouble() &&
        bar.spots[1].x == b.toDouble());

/// True when any visible polyline bar holds spots whose day indexes are NOT
/// adjacent — i.e. the (single-path) bar paints across a day gap.
bool _spansAGap(WidgetTester tester) => _segmentBars(tester).any((bar) {
      final xs = bar.spots.map((s) => s.x.round()).toList()..sort();
      for (var i = 1; i < xs.length; i++) {
        if (xs[i] != xs[i - 1] + 1) return true;
      }
      return false;
    });

ThemeData _themeOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

Widget _chartHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
}) =>
    chartHarness(
      entries: entries,
      marks: marks,
      darkTheme: true,
      scopeInsideMaterialApp: true,
    );

void main() {
  group('adjacent-day connectivity', () {
    testWidgets('two readings on adjacent days connect', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.6),
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'adjacent calendar days are drawn as one segment');
    });

    testWidgets('a day with no temperature between readings breaks the line',
        (tester) async {
      // Saturday has an entry, but WITHOUT a temperature, and a Sunday with
      // no entry at all behind it: neither gap may be bridged by the curve.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bleeding: Bleeding.medium),
        DailyEntry(date: _sat, bbtC: 36.7),
        DailyEntry(date: _sun, bbtC: 36.8),
      ]));
      await tester.pumpAndSettle();

      expect(_spansAGap(tester), isFalse,
          reason: 'a measured day without temperature still breaks the line');
      // The measured days BEHIND the gap stay connected among themselves.
      expect(_connects(tester, 2, 3), isTrue,
          reason: 'adjacent readings after the gap still connect');
    });

    testWidgets('a day with no entry at all breaks the line too',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _sat, bbtC: 36.7),
      ]));
      await tester.pumpAndSettle();

      // Both days are lone dots; nothing connects index 0 to index 2.
      expect(_spansAGap(tester), isFalse,
          reason: 'gap between day 0 and day 2: no segment may be drawn');
      expect(_connects(tester, 0, 2), isFalse);
    });
  });

  group('ignored temperatures render lighter (mark-keyed)', () {
    // Thu and Sat: ordinary measurements; Fri: a measured day carrying the
    // ignoreTemperature MARK (no raw flags needed — the mark is the
    // rendering key).
    final ignoredMiddle = <DailyEntry>[
      DailyEntry(date: _thu, bbtC: 36.5),
      DailyEntry(date: _fri, bbtC: 36.6),
      DailyEntry(date: _sat, bbtC: 36.7),
    ];
    final friMark =
        CycleMark(date: _fri, type: CycleMarkTypes.ignoreTemperature);

    /// The scheme color the chart derives its normal (opaque) color from.
    Color normalColor(WidgetTester tester) =>
        _themeOf(tester).colorScheme.primary;

    testWidgets('line stays continuous through the ignored day',
        (tester) async {
      await tester
          .pumpWidget(_chartHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'ignored temperature counts as a measured day');
      expect(_connects(tester, 1, 2), isTrue,
          reason: 'the line continues through the ignored day');
    });

    testWidgets('segments touching the ignored day render lighter',
        (tester) async {
      await tester
          .pumpWidget(_chartHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        final color = bar.color!;
        expect(color.a, closeTo(0.4, 1e-6),
            reason: 'both segments touch the ignored day -> lighter tint');
        // Lighter = theme color at reduced alpha, not a different hue.
        expect(color.r, normalColor(tester).r);
        expect(color.g, normalColor(tester).g);
        expect(color.b, normalColor(tester).b);
      }
    });

    testWidgets('the ignored dot renders lighter, normal dots stay opaque',
        (tester) async {
      await tester
          .pumpWidget(_chartHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      final painterByIndex = <int, Color>{};
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final spot = dotBars.first.spots[i];
        final painter = dotBars.first.dotData
            .getDotPainter(spot, 0, dotBars.first, i) as FlDotCirclePainter;
        painterByIndex[spot.x.round()] = painter.color;
      }
      expect(painterByIndex[0]!.a, 1.0,
          reason: 'an ordinary measurement keeps the full-strength dot');
      final ignored = painterByIndex[1]!;
      expect(ignored.a, closeTo(0.4, 1e-6),
          reason: 'the ignored dot renders lighter');
      expect(ignored.r, normalColor(tester).r);
      expect(ignored.g, normalColor(tester).g);
      expect(ignored.b, normalColor(tester).b);
    });

    testWidgets(
        'a marked day WITHOUT disturbance flags renders lighter '
        '(the mark alone dims the curve)', (tester) async {
      // Headline new behavior (owner decision 2026-09-19): the mark is
      // the visible state, flags are surfaced by other means (diary
      // badge). Fri carries
      // ONLY the mark — no tempDisturbances — and still renders lighter.
      final unflaggedMarked = <DailyEntry>[
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.6), // mask 0
        DailyEntry(date: _sat, bbtC: 36.7),
      ];
      await tester.pumpWidget(
          _chartHarness(entries: unflaggedMarked, marks: [friMark]));
      await tester.pumpAndSettle();

      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      final painterByIndex = <int, Color>{};
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final spot = dotBars.single.spots[i];
        final painter = dotBars.single.dotData
            .getDotPainter(spot, 0, dotBars.single, i) as FlDotCirclePainter;
        painterByIndex[spot.x.round()] = painter.color;
      }
      expect(painterByIndex[1]!.a, closeTo(0.4, 1e-6),
          reason: 'a marked day WITHOUT flags renders lighter');
      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, closeTo(0.4, 1e-6),
            reason: 'both segments touch the marked day -> lighter tint');
      }
    });

    testWidgets(
        'a flagged day WITHOUT the mark renders at FULL alpha '
        '(deleting the mark restores normal rendering)', (tester) async {
      // THE FLIP (owner decision 2026-09-19): the mark can be deleted on
      // the day sheet while the raw flags remain — the curve renders
      // normally again (the flags are surfaced by the diary badge, not
      // the curve).
      final flaggedUnmarked = <DailyEntry>[
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(
            date: _fri, bbtC: 36.6, tempDisturbances: TempDisturbance.kr.bit),
        DailyEntry(date: _sat, bbtC: 36.7),
      ];
      await tester.pumpWidget(_chartHarness(entries: flaggedUnmarked));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, 1.0,
            reason: 'flags without the mark render at full alpha — the '
                'raw mask is no longer a rendering input');
      }
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final painter = dotBars.single.dotData
                .getDotPainter(dotBars.single.spots[i], 0, dotBars.single, i)
            as FlDotCirclePainter;
        expect(painter.color.a, 1.0,
            reason: 'the flagged-but-unmarked dot keeps the full-strength '
                'color');
      }
    });

    testWidgets(
        'a marked AND flagged day renders lighter (the common auto-set '
        'path)', (tester) async {
      // Flags auto-set the mark (auto-set only), so the usual flagged day
      // carries both: mask AND mark — still lighter (mark-keyed).
      final flaggedMarked = <DailyEntry>[
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(
            date: _fri, bbtC: 36.6, tempDisturbances: TempDisturbance.kr.bit),
        DailyEntry(date: _sat, bbtC: 36.7),
      ];
      await tester
          .pumpWidget(_chartHarness(entries: flaggedMarked, marks: [friMark]));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, closeTo(0.4, 1e-6),
            reason: 'marked + flagged renders lighter (the mark is the '
                'rendering key)');
      }
    });

    testWidgets('two consecutive ignored days connect with a lighter segment',
        (tester) async {
      // Thu and Fri both measured AND both ignored (marks): one segment,
      // but every part of it — line and both dots — renders lighter.
      final marks = [
        CycleMark(date: _thu, type: CycleMarkTypes.ignoreTemperature),
        friMark,
      ];
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.6),
      ], marks: marks));
      await tester.pumpAndSettle();

      expect(_segmentBars(tester), hasLength(1),
          reason: 'the two adjacent ignored days form exactly one segment');
      final segment = _segmentBars(tester).single;
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment between two ignored days is lighter');
      expect(segment.color!.r, normalColor(tester).r);
      expect(segment.color!.g, normalColor(tester).g);
      expect(segment.color!.b, normalColor(tester).b);

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final painter = dotBars.first.dotData.getDotPainter(
            dotBars.first.spots[i], 0, dotBars.first, i) as FlDotCirclePainter;
        expect(painter.color.a, closeTo(0.4, 1e-6),
            reason: 'ignored dot ${dotBars.first.spots[i].x.round()} '
                'renders lighter');
        expect(painter.color.r, normalColor(tester).r);
        expect(painter.color.g, normalColor(tester).g);
        expect(painter.color.b, normalColor(tester).b);
      }
    });

    testWidgets('ignored dot at a run edge connects to the adjacent normal day',
        (tester) async {
      // Fri: ignored; Sat: normal. The ignored edge day is still drawn
      // connected — adjacency, not the mark, decides connectivity.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 36.2),
        DailyEntry(date: _sat, bbtC: 37.0),
      ], marks: [
        friMark
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 1, 2), isTrue,
          reason: 'ignored run-edge day connects to its adjacent day');
      final segment = _segmentBars(tester)
          .firstWhere((bar) => bar.spots.length == 2 && bar.spots[0].x == 1);
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment touching the ignored edge day is lighter');
    });

    testWidgets('ignored-temp segments stay dark in dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester
          .pumpWidget(_chartHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      final darkScheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme;
      expect(_segmentBars(tester).map((b) => b.color!),
          everyElement(equals(darkScheme.primary.withValues(alpha: 0.4))),
          reason: 'dark scheme: light primary at reduced alpha, still led by '
              'the (bright) scheme color — readable on the dark surface');
      expect(darkScheme.primary.computeLuminance(), greaterThan(0.3),
          reason: 'the lighter segments keep darkness-readable contrast');
    });
  });

  group('adaptive chart height', () {
    double chartHeight(WidgetTester tester) =>
        tester.getRect(find.byType(LineChart)).height;

    testWidgets('a small y-span keeps the base height of 260', (tester) async {
      // Five days around 36.5: the rounded bounds span 1 °C.
      await tester.pumpWidget(_chartHarness(entries: [
        for (var i = 0; i < 5; i++)
          DailyEntry(date: _thu.add(Duration(days: i)), bbtC: 36.5),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(260, 0.5),
          reason: 'a comfortable ~1 °C span needs the base height');
    });

    testWidgets('the height grows with the y-span', (tester) async {
      // 36.5 .. 40.0 → rounded bounds 36.0..40.5 (span 4.5 °C): 260 base
      // plus 1.5 °C beyond the comfortable 3 °C at 80 px per degree.
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 36.5),
        DailyEntry(date: _fri, bbtC: 40.0),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(380, 0.5),
          reason: 'a 4.5 °C span grows the plot: 260 + (4.5 − 3) × 80');
    });

    testWidgets(
        'the height is capped — a wide span does not grow without '
        'bounds', (tester) async {
      // 34.5 .. 41.5 → rounded bounds 34.0..42.0 (span 8 °C, far past the
      // growth range).
      await tester.pumpWidget(_chartHarness(entries: [
        DailyEntry(date: _thu, bbtC: 34.5),
        DailyEntry(date: _fri, bbtC: 41.5),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(400, 0.5),
          reason: 'the growth is capped at 400');
    });
  });
}
