import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:cycle_app/ui/cycle.dart';
import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle tab's recorded-fact glyphs in the per-signal
// rows under the temperature curve: the measurement time renders as
// localized HH:mm text in its OWN row BELOW the chart block (the first
// row of the below-chart strip) — rotated
// vertically when the day column is narrower than the text (never dropped,
// the narrow-space tradeoff), horizontal in wide columns (the clock lives
// only in the row corner, never on the day cells),
// the sex time slots (one X glyph per SET SexTiming bit, drawn at
// that slot's third of the day column — multiple bits render multiple X
// marks), the letter-coded pain flag B (breast, in the notes band's pain
// row) and M (Mittelschmerz, inside the plot below the mucus
// letters). Days without
// the respective fact render nothing.

// Seven-plus-one chart days:
//  0: temperature WITH a recorded measurement time (6:30) -> clock glyph
//  1: temperature WITHOUT a recorded time                  -> no clock
//  2: sex at the START slot, no temperature                -> X (start third)
//  3: breast pain only                                     -> B, no M
//  4: Mittelschmerz only                                   -> M, no B
//  5: sex at TWO slots AND both pains                      -> X, X, B, M
//  6: plain temperature day                                -> nothing new
//  7: cervix FIRMNESS only (no position) -> firmness glyph, no position
//     letters
List<DailyEntry> _timeSexPainEntries() => [
  DailyEntry(date: septSevenDay(0), bbtC: 36.5, measuredAtMinutes: 6 * 60 + 30),
  DailyEntry(date: septSevenDay(1), bbtC: 36.4),
  DailyEntry(date: septSevenDay(2), sexTimings: SexTiming.morning.bit),
  DailyEntry(date: septSevenDay(3), painBreast: true),
  DailyEntry(date: septSevenDay(4), painMittelschmerz: true),
  DailyEntry(
    date: septSevenDay(5),
    sexTimings: SexTiming.morning.bit | SexTiming.evening.bit,
    painBreast: true,
    painMittelschmerz: true,
  ),
  DailyEntry(date: septSevenDay(6), bbtC: 36.6),
  DailyEntry(date: septSevenDay(7), cervixFirmness: CervixFirmness.soft),
];

void main() {
  group('measurement time — its own row below the chart block, first in '
      'the below-chart strip', () {
    testWidgets(
      'the time row renders BELOW the chart block, at the strip\'s top '
      '— above the disturbance row and the notes band — for every '
      'day with a recorded measurement time',
      (tester) async {
        await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

        final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
        // Own row below the block, first in the strip: the time row starts
        // after the chart, but above disturbance and the band (owner order:
        // time first in the below-chart strip).
        expect(
          tester.getRect(chartCell(0, 'time')).top,
          greaterThan(chartBottom),
          reason: 'the time row is not part of the chart block',
        );
        expect(
          tester.getRect(chartCell(0, 'time')).bottom,
          lessThan(tester.getRect(chartCell(0, 'disturbance')).top),
          reason: 'the time row renders above the disturbance row',
        );
        expect(
          tester.getRect(chartCell(0, 'time')).top,
          lessThan(tester.getRect(chartCell(0, 'notesBand')).top),
          reason:
              'the time row renders above the notes band — time is '
              'the first row of the below-chart strip',
        );
        // Every day with a recorded time renders its HH:mm (the fixture's
        // only recorded time is day 0).
        expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
      },
    );

    testWidgets(
      'the time STILL renders at every column width — rotated vertically '
      '(RotatedBox) under the width threshold, horizontal above it '
      '(regression: the time used to be dropped entirely at the space '
      'constraint)',
      (tester) async {
        List<DailyEntry> timedEntries(int count) => [
          // Give EVERY day a recorded measurement time so the narrow checks
          // exercise the row everywhere.
          for (var i = 0; i < count; i++)
            DailyEntry(
              date: septSevenDay(i),
              bbtC: 36.5,
              measuredAtMinutes: 6 * 60 + 30,
            ),
        ];
        Finder timeCells() => find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('timeCell-'),
        );

        final orientationCases =
            <
              (
                String label,
                List<DailyEntry> entries,
                int checkedDay,
                Matcher columnWidth,
                bool vertical,
                bool everyCellRotates,
              )
            >[
              (
                // 60 days overflow the viewport: columns render at the
                // minimum usable width (21 px), far below the horizontal
                // text threshold.
                '60 days, columns at the minimum usable width',
                timedEntries(60),
                59,
                closeTo(minDayColumnWidth, 0.5),
                true,
                true,
              ),
              (
                // 25 days fit the viewport but leave only ~30 px per column
                // — below the threshold, so still vertical.
                '25 days, a narrow non-minimum ~30 px column',
                timedEntries(25),
                24,
                closeTo(30, 1.5),
                true,
                false,
              ),
              (
                'wide columns',
                _timeSexPainEntries(),
                0,
                greaterThan(32),
                false,
                false,
              ),
            ];

        for (final (
              label,
              entries,
              checkedDay,
              columnWidth,
              vertical,
              everyCellRotates,
            )
            in orientationCases) {
          await pumpFreshChart(tester, () => chartHarness(entries: entries));

          expect(
            tester.getRect(chartCell(checkedDay, 'time')).width,
            columnWidth,
            reason: 'precondition: $label',
          );
          if (vertical) {
            // The time text survives the space constraint: the rendered
            // time cells carry the rotated HH:mm text (RotatedBox), never
            // empty — it is NEVER dropped.
            final rotatedTime = find.descendant(
              of: chartCell(checkedDay, 'time'),
              matching: find.text('06:30'),
            );
            expect(
              rotatedTime,
              findsOneWidget,
              reason:
                  '$label: the time renders vertically — it is NEVER '
                  'dropped',
            );
            final rotatedBox = find
                .ancestor(of: rotatedTime, matching: find.byType(RotatedBox))
                .first;
            expect(
              tester.widget<RotatedBox>(rotatedBox).quarterTurns,
              1,
              reason:
                  '$label: the vertical time reads top→bottom, like the '
                  "band's note teaser",
            );
            // The time text scales to fill the row's full 30 px height, so
            // geometry can't tell a top anchor from a centered one — pin the
            // anchor itself instead.
            final anchor = find
                .ancestor(of: rotatedBox, matching: find.byType(Align))
                .first;
            expect(
              tester.widget<Align>(anchor).alignment,
              Alignment.topCenter,
              reason:
                  '$label: the vertical time anchors its reading start '
                  'at the row top',
            );
            if (everyCellRotates) {
              expect(
                find.descendant(
                  of: timeCells(),
                  matching: find.byType(RotatedBox),
                ),
                findsWidgets,
                reason: '$label: the narrow cells rotate the time text',
              );
            } else {
              expect(
                find.descendant(
                  of: chartCell(checkedDay, 'time'),
                  matching: find.byType(RotatedBox),
                ),
                findsOneWidget,
              );
            }
          } else {
            expect(
              find.descendant(
                of: chartCell(checkedDay, 'time'),
                matching: find.byType(RotatedBox),
              ),
              findsNothing,
              reason: '$label: keeps the horizontal HH:mm text',
            );
            expect(
              chartCellContent(checkedDay, 'time', find.text('06:30')),
              findsOneWidget,
            );
          }
        }
      },
    );
  });
  testWidgets(
    'the measurement time renders localized HH:mm text on days with a '
    'recorded measurement time — and nothing elsewhere (en and de)',
    (tester) async {
      for (final locale in [const Locale('en'), const Locale('de')]) {
        // 8+1 chart days fit the viewport comfortably, so the columns are
        // wide enough for the time text.
        await pumpChart(
          tester,
          chartHarness(entries: _timeSexPainEntries(), locale: locale),
        );

        expect(
          chartCellContent(0, 'time', find.text('06:30')),
          findsOneWidget,
          reason:
              '$locale: the temperature day WITH a recorded time shows the '
              'padded HH:mm text in its own time cell',
        );
        expect(
          chartCellContent(1, 'time', find.text('06:30')),
          findsNothing,
          reason:
              '$locale: a temperature WITHOUT a recorded time shows no '
              'time text',
        );
        expect(
          chartCellContent(2, 'time', find.byType(Text)),
          findsNothing,
          reason:
              '$locale: a temperature-free day can never carry a '
              'measurement time (the domain drops the time without a '
              'temperature)',
        );
        expect(
          chartCellContent(6, 'time', find.byType(Text)),
          findsNothing,
          reason:
              '$locale: a plain temperature day without a time shows nothing',
        );
        expect(
          chartCellContent(2, 'time', find.byIcon(Icons.schedule)),
          findsNothing,
          reason:
              '$locale: no per-day clock icon — the clock lives only in '
              'the row corner slot',
        );
      }
    },
  );

  testWidgets('sex renders X marks only on days with recorded time slots', (
    tester,
  ) async {
    await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

    expect(
      find.byKey(const ValueKey('inPlotSex-2-morning')),
      findsOneWidget,
      reason: 'the sex day shows its X glyph inside the plot',
    );
    expect(
      find.byKey(const ValueKey('inPlotSex-0-morning')),
      findsNothing,
      reason: 'no X on a temperature day without sex',
    );
    expect(find.byKey(const ValueKey('inPlotSex-6-morning')), findsNothing);
  });

  testWidgets('every set sex time slot renders its own X — multiple slots '
      'render multiple X marks on one day', (tester) async {
    await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

    // day 5 recorded start + end: middle is the only absent timing.
    expect(
      find.byKey(const ValueKey('inPlotSex-5-midday')),
      findsNothing,
      reason: 'no X for an unrecorded timing',
    );
    expect(
      find.byKey(const ValueKey('inPlotSex-5-morning')),
      findsOneWidget,
      reason: 'two recorded slots (start + end) render their X marks',
    );
    expect(find.byKey(const ValueKey('inPlotSex-5-evening')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotSex-2-morning')),
      findsOneWidget,
      reason: 'a single recorded slot renders exactly one X',
    );
  });

  testWidgets('pain renders B in its band row; Mittelschmerz renders M '
      'inside the plot', (tester) async {
    await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

    expect(
      find.byKey(const ValueKey('painBreastGlyph-3')),
      findsOneWidget,
      reason: 'breast pain shows the B letter in its band row',
    );
    expect(
      chartCellContent(3, 'notesBand', find.text('M')),
      findsNothing,
      reason: 'no Mittelschmerz letter without the flag',
    );
    expect(
      find.byKey(const ValueKey('inPlotM-4')),
      findsOneWidget,
      reason: 'Mittelschmerz shows the M letter inside the plot',
    );
    expect(
      find.byKey(const ValueKey('painBreastGlyph-4')),
      findsNothing,
      reason: 'no breast letter without the flag',
    );
    expect(find.byKey(const ValueKey('painBreastGlyph-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotM-5')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('painBreastGlyph-6')),
      findsNothing,
      reason: 'a plain day shows no pain letter',
    );
    expect(find.byKey(const ValueKey('inPlotM-6')), findsNothing);
  });

  testWidgets('a combined day carries the sex X marks alongside the band '
      'pain row and the Mittelschmerz M inside the plot', (tester) async {
    await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

    expect(
      find.byKey(const ValueKey('inPlotSex-5-evening')),
      findsOneWidget,
      reason: 'the sex X marks render inside the plot',
    );
    expect(
      find.byKey(const ValueKey('painBreastGlyph-5')),
      findsOneWidget,
      reason:
          'the B letter renders in the day\'s pain row beside the in-plot '
          'sex marks',
    );
    expect(
      find.byKey(const ValueKey('inPlotM-5')),
      findsOneWidget,
      reason: 'the Mittelschmerz letter renders inside the plot',
    );
  });

  testWidgets('a firmness-only day renders its glyph with no position '
      'ink at all', (tester) async {
    await pumpChart(tester, chartHarness(entries: _timeSexPainEntries()));

    expect(
      find.byKey(const ValueKey('cervixFirmnessGlyph-7')),
      findsOneWidget,
      reason:
          'the soft-firmness glyph (paper shorthand w) renders pinned '
          'in the band\'s cervix zone',
    );
    for (final glyph in ['t', 'm', 'h', 'sh', 'u']) {
      expect(
        chartCellContent(7, 'notesBand', find.text(glyph)),
        findsNothing,
        reason: 'positions paint circles, never letters — ($glyph incl.)',
      );
    }
    expect(
      find.byKey(const ValueKey('cervixSlotGlyph-7')),
      findsNothing,
      reason: 'no slot glyph on a day whose opening was never recorded',
    );
  });
}
