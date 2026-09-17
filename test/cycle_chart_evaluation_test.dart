// Widget tests of the computed evaluation marks on the cycle chart (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks; the UI
// derives and renders the peak ring, circled higher measurements (arrow-up
// for pre-peak rises), the 1–6 low numbering and the baseline. Derived
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

/// Full evaluation scenario:
///
/// - 9/6 (idx 0): 36.9 — a rise BEFORE the peak -> arrow-up, never circled.
/// - 9/7 (idx 1): 36.3 — the 7th day before the first higher, outside the
///   six-low window -> no number.
/// - 9/8..9/13 (idx 2..7): the six low measurements, numbered BACK from the
///   first higher (9/13 = 1 ... 9/8 = 6).
/// - 9/9 (idx 3, 36.4): the HIGHEST of the six lows -> baseline 36.4.
/// - 9/12 (idx 6): mucus-peak mark -> ring (in the mucus color).
/// - 9/14 (idx 8): first-higher mark; after-peak higher -> circled #1.
/// - 9/15 (idx 9): after-peak higher -> circled #2.
/// - 9/16 (idx 10): after-peak higher -> circled #3 (SUZ evening).
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

void main() {
  group('mucus-peak ring', () {
    testWidgets('the peak day gets a ring around its temperature', (tester) async {
      await tester.pumpWidget(
          _harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/12 (idx 6) carries the mucus-peak mark.
      final painter = _dotPainter(tester, 6);
      expect(painter, isA<RingDotPainter>(),
          reason: 'the mucus-peak day renders circled');
      final ring = painter as RingDotPainter;
      expect(ring.ringColor, _scheme(tester).tertiary,
          reason: 'the peak belongs to the mucus color family');
      expect(ring.color.a, 1.0,
          reason: 'the peak-day temperature keeps its full-strength dot');
    });

    testWidgets('a peak day without a measured temperature draws no circle, '
        'and does not crash', (tester) async {
      // 9/12 has an entry, but no temperature: there is no dot the circle
      // could wrap (flagged rendering assumption, see cycle_marks.dart).
      final entries = [
        for (final e in _entries)
          _sameDay(e, _sat12)
              ? DailyEntry(date: _sat12, bleeding: Bleeding.light)
              : e,
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(
        _dotBars(tester).expand((b) => b.spots).map((s) => s.x.round()),
        isNot(contains(6)),
        reason: 'no temperature on the peak day -> no dot to circle');
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          // The circled higher measurements (idx 8..10) are unaffected by
          // the missing peak temperature; what must be ABSENT is the
          // mucus-peak ring (the mucus-colored ring).
          if (painter is RingDotPainter) {
            expect(painter.ringColor, isNot(_scheme(tester).tertiary));
          }
        }
      }
    });
  });

  group('higher measurements', () {
    testWidgets('circled higher measurements after the peak render a ring, '
        'pre-peak rises render arrow-up', (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      // Before the peak (idx 0): arrow-up, not circled.
      expect(_dotPainter(tester, 0), isA<ArrowUpDotPainter>());
      // After the peak (idx 8..10): circled in the temperature color.
      for (final index in [8, 9, 10]) {
        final painter = _dotPainter(tester, index);
        expect(painter, isA<RingDotPainter>(),
            reason: 'circled higher measurement at day index $index');
        expect((painter as RingDotPainter).ringColor,
            _scheme(tester).primary,
            reason: 'circled higher measurements are temperature-family');
      }
    });

    testWidgets('an unmarked peak: the position is unknowable, so higher '
        'measurements render arrow-up and nothing is circled',
        (tester) async {
      final onlyFirstHigher = _marks
          .where((m) => m.type == CycleMarkTypes.firstHigherMeasurement)
          .toList();
      await tester.pumpWidget(
          _harness(entries: _entries, marks: onlyFirstHigher));
      await tester.pumpAndSettle();

      for (final index in [0, 8, 9, 10]) {
        expect(_dotPainter(tester, index), isA<ArrowUpDotPainter>(),
            reason: 'no peak mark -> higher at $index renders arrow-up');
      }
      // Nothing circled anywhere.
      for (final bar in _dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          expect(painter, isNot(isA<RingDotPainter>()));
        }
      }
    });
  });

  group('numbering', () {
    testWidgets('the six low days carry 1–6, counted back from the first '
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
      expect(_numberUnder(tester, 0), isNull, reason: '9/6: outside the window');
      expect(_numberUnder(tester, 1), isNull, reason: '9/7: 7th prior day');
      expect(_numberUnder(tester, 8), isNull,
          reason: '9/14: the first higher itself is not a low');
    });
  });

  group('baseline', () {
    testWidgets('a horizontal line runs through the highest of the six lows',
        (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      final lines = _chartData(tester).extraLinesData.horizontalLines;
      expect(lines, hasLength(1),
          reason: 'one evaluated cycle -> one baseline');
      expect(lines.single.y, 36.4,
          reason: 'the highest of the six lows (9/9) is the baseline value');
    });
  });

  group('no marks', () {
    testWidgets('nothing evaluation-related is drawn when no marks exist',
        (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: const []));
      await tester.pumpAndSettle();

      expect(_chartData(tester).extraLinesData.horizontalLines, isEmpty,
          reason: 'no marks -> no baseline');
      for (var i = 0; i < 11; i++) {
        expect(_numberUnder(tester, i), isNull, reason: 'no marks -> no numbers');
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
    testWidgets('the legend explains the evaluation glyphs and the baseline',
        (tester) async {
      await tester.pumpWidget(_harness(entries: _entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(find.text('Mucus peak'), findsOneWidget);
      expect(find.text('First higher measurement'), findsOneWidget);
      expect(find.text('Higher measurement before the peak'), findsOneWidget);
      expect(find.text('Baseline'), findsOneWidget);
    });
  });
}

/// Identity helper: true when [entry]'s date is exactly [day]'s calendar day
/// (used to patch the scenario above).
bool _sameDay(DailyEntry entry, DateTime day) =>
    entry.date.year == day.year &&
    entry.date.month == day.month &&
    entry.date.day == day.day;
