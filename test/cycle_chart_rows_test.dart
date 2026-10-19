import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/ui/bleeding_symbol.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

// Widget tests of the per-signal rows under the cycle chart (the paper's
// recording rows): one always-rendered row per signal — bleeding, mucus
// (with the reserved solid peak-dot slot above the glyph), measurement
// time, disturbance, and the merged notes band. The rows hold ONLY day
// cells — their sample glyphs and localized row names live in the frozen
// left rail (the left-rail tests), keyed `${row}Corner` there. The
// measurement time renders as localized HH:mm text ONLY when the day
// column is wide enough; no per-day clock icon exists anywhere in the
// rows. Tapping a row cell opens the day's mark-entry sheet.
//

// Nine chart days covering one recorded fact per signal — the shared
// per-signal rows fixture from support/fixtures.dart (day 4 WITH the
// Mittelschmerz flag).
final _rowsEntries = nineDayRowsFixture(
  day: septSevenDay,
  withMittelschmerz: true,
);

const _dayCount = 9;

// The chart block's recording rows, top-down in render order: the single
// top strip row (bleeding), then the single below-chart strip in the
// owner-decided order — measurement time first, the disturbance letters,
// then the merged notes band at the very bottom (the paper sheet's
// remarks home). The mucus letters, sex Xs, Mittelschmerz M and
// evaluation numbers render inside the plot (the in-plot glyphs below).
const _signalRows = ['bleeding', 'time', 'disturbance', 'notesBand'];

// The bleeding row's dedicated level fixture: every level recorded once,
// on consecutive days — day 0 none(0), day 1 light, day 2 spotting,
// day 3 medium, day 4 heavy, day 5 maximum. Every day carries a
// temperature: with no measurement recorded anywhere the chart renders
// only its "no temperature" placeholder instead of the signal rows, so
// the bleeding cells would never exist to assert on.
final _bleedingRowEntries = [
  DailyEntry(date: septSevenDay(0), bbtC: 36.5),
  DailyEntry(date: septSevenDay(1), bbtC: 36.5, bleeding: Bleeding.light),
  DailyEntry(date: septSevenDay(2), bbtC: 36.5, bleeding: Bleeding.spotting),
  DailyEntry(date: septSevenDay(3), bbtC: 36.5, bleeding: Bleeding.medium),
  DailyEntry(date: septSevenDay(4), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: septSevenDay(5), bbtC: 36.5, bleeding: Bleeding.maximum),
];

/// All bleed-fill regions (the shared symbol's fill widgets) inside the
/// bleeding cell of [index]: the solid bottom bar of a menstruation-level
/// day, or the dots of a spotting day.

void main() {
  group('paper layout: bleeding is the one top strip row', () {
    testWidgets('bleeding is the ONLY top strip row, above the curve; '
        'disturbance and the notes band stay below the block', (tester) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      expect(
        tester.getRect(chartCell(0, 'bleeding')).top,
        lessThan(chartTop),
        reason:
            'the bleeding row renders in the TOP of the temperature '
            'block, above the curve (paper sheet)',
      );
      for (final row in ['time', 'disturbance', 'notesBand']) {
        expect(
          tester.getRect(chartCell(0, row)).top,
          greaterThan(chartBottom),
          reason: 'the $row row stays below the temperature block',
        );
      }
    });

    testWidgets('no Mittelschmerz row and no numbering row remain on the '
        'card: no cells, no corners', (tester) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      for (var i = 0; i < _dayCount; i++) {
        expect(
          find.byKey(ValueKey('mittelschmerzCell-$i')),
          findsNothing,
          reason: 'the M renders inside the plot (inPlotM), not as a cell',
        );
        expect(
          find.byKey(ValueKey('marksCell-$i')),
          findsNothing,
          reason:
              'the 1–6 numbering renders inside the plot '
              '(inPlotDayNumber), not as a cell',
        );
      }
      expect(chartCellCorner('mittelschmerz'), findsNothing);
    });

    testWidgets('the rows render in the paper order — bleeding alone on '
        'top — and the below-chart strip follows with time first, notes '
        'last', (tester) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      double top(String row) => tester.getRect(chartCellCorner(row)).top;
      // The below-chart strip keeps the owner-decided order (time first,
      // notes last): time, disturbance, notes band after the top
      // segment and the curve.
      expect(
        top('time'),
        greaterThan(tester.getRect(chartCellCorner('bleeding')).bottom),
        reason:
            'the below-chart strip starts after the top segment '
            'and the curve',
      );
      expect(top('disturbance'), greaterThan(top('time')));
      expect(top('notesBand'), greaterThan(top('disturbance')));
    });

    testWidgets('the Mittelschmerz M renders INSIDE the plot below the '
        'mucus letters, column-centered; the band keeps only B', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / _dayCount;
      final mRect = tester.getRect(find.byKey(const ValueKey('inPlotM-4')));
      // Day 4 = the fixture's Mittelschmerz day (beside its mucus S).
      expect(
        mRect.center.dy,
        greaterThan(plot.top),
        reason:
            'the M row renders inside the plot, not in the '
            'below-chart strip',
      );
      expect(
        mRect.center.dx,
        closeTo(plot.left + (4 + 0.5) * colW, 1),
        reason: 'the M centers in its day column',
      );
      expect(
        mRect.center.dy,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('inPlotMucus-4'))).bottom,
        ),
        reason: 'the M renders below the day\'s mucus letters',
      );
      expect(
        find.byKey(const ValueKey('inPlotHaloM-4')),
        findsOneWidget,
        reason: 'the M ink carries its halo layer',
      );
      // The other days carry no M; the band keeps only B.
      expect(find.byKey(const ValueKey('inPlotM-7')), findsNothing);
      expect(
        chartCellContent(4, 'notesBand', find.text('M')),
        findsNothing,
        reason: 'the band never carries the M letter',
      );
      expect(
        find.byKey(const ValueKey('painBreastGlyph-7')),
        findsOneWidget,
        reason: 'breast pain B renders in the band\'s pain row',
      );
    });

    testWidgets('tapping a top-strip cell opens the day sheet', (tester) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      await tester.tap(chartCell(4, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(
        sheet.day,
        septSevenDay(4),
        reason: 'the top-strip bleeding cell keeps its tap behavior',
      );
    });
  });

  group('per-signal rows', () {
    testWidgets('every signal row renders for every windowed day, in order '
        'bleeding, time, disturbance, notes band', (tester) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      for (var i = 0; i < _dayCount; i++) {
        for (final row in _signalRows) {
          expect(
            chartCell(i, row),
            findsOneWidget,
            reason:
                'row $row renders a cell for day index $i '
                '(rows always render, even empty/untracked days)',
          );
        }
      }

      // Row ORDER: the corner slots appear top-down bleeding .. notes band
      // (paper layout: bleeding alone inside the top of the temperature
      // block, the rest in the below-chart strip, time first).
      final corners = _signalRows.map(
        (row) => tester.getRect(chartCellCorner(row)),
      );
      final tops = corners.map((r) => r.top).toList();
      expect(
        tops,
        equals([...tops]..sort()),
        reason: 'the signal rows render in the paper\'s order',
      );
    });

    testWidgets('each row\'s corner slot carries a sample glyph with a tooltip '
        'and a semantics label carrying the localized row name (en)', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      final rowNames = {
        'bleeding': 'Bleeding',
        'disturbance': 'Disturbed measurement',
        'time': 'Measurement time',
        'notesBand': 'Note',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        expect(find.byKey(ValueKey('${key}Corner')), findsOneWidget);
        expect(tooltipMessages(tester, chartCellCorner(key)), [
          value,
        ], reason: 'row $key\'s corner slot carries the localized row name');
        expect(
          find.descendant(
            of: chartCellCorner(key),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == value,
            ),
          ),
          findsOneWidget,
          reason:
              'row $key\'s corner slot announces the row name to '
              'screen readers',
        );
      }

      // The corner sample glyphs: a bleeding box and the sticky-note band
      // sample.
      expect(
        find.descendant(
          of: chartCellCorner('bleeding'),
          matching: find.byType(BleedingSymbol),
        ),
        findsOneWidget,
        reason:
            'the bleeding corner shows the box sample (dotted '
            'spotting, like the row\'s cells render it)',
      );
      expect(
        find.descendant(
          of: chartCellCorner('notesBand'),
          matching: find.byIcon(Icons.sticky_note_2_outlined),
        ),
        findsOneWidget,
        reason:
            'the band corner shows the sticky-note sample (the cervix '
            'and breast-pain vocabulary has no extra rail corner: it '
            'lives in the band itself)',
      );
      expect(
        find.descendant(
          of: chartCellCorner('time'),
          matching: find.byIcon(Icons.schedule),
        ),
        findsOneWidget,
        reason: 'the time corner keeps the clock icon sample',
      );
    });

    testWidgets('the row names use the German wording in de', (tester) async {
      await pumpChart(
        tester,
        chartHarness(entries: _rowsEntries, locale: const Locale('de')),
      );

      final rowNames = {
        'bleeding': 'Blutung',
        'disturbance': 'Messstörung',
        'time': 'Messzeitpunkt',
        'notesBand': 'Notiz',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        expect(tooltipMessages(tester, chartCellCorner(key)), [
          value,
        ], reason: '$key: the corner slot carries the German row name');
      }
    });

    testWidgets('long-pressing a corner slot shows the row-name tooltip', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      // The tooltip overlay shows the localized row name. The bare text
      // can pre-exist elsewhere (the legend's "Bleeding" entry), so pin
      // the OVERLAY as one additional occurrence of the word.
      final before = tester.widgetList<Text>(find.text('Bleeding')).length;
      await tester.longPress(find.byKey(const ValueKey('bleedingCorner')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Bleeding'),
        findsNWidgets(before + 1),
        reason: 'long-press shows the row-name tooltip overlay',
      );
    });

    testWidgets('at minimum column width the time renders vertically — never '
        'dropped (wide columns keep the horizontal text, see the wide '
        'HH:mm test above and the measurement-time tests)', (tester) async {
      Finder timeCellFinder() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('timeCell-'),
      );

      // 60 days overflow the viewport: columns render at the minimum
      // usable width (21 px), below the horizontal threshold. The initial
      // auto-scroll puts the newest days' cells on screen.
      await pumpChart(
        tester,
        chartHarness(
          entries: [
            for (var i = 0; i < 60; i++)
              DailyEntry(
                date: septSevenDay(i),
                bbtC: 36.5,
                measuredAtMinutes: 6 * 60 + 30,
              ),
          ],
        ),
      );

      expect(
        timeCellFinder(),
        findsWidgets,
        reason: 'the initial window renders time cells',
      );
      expect(
        find.descendant(of: timeCellFinder(), matching: find.text('06:30')),
        findsWidgets,
        reason:
            'the recorded time renders at the minimum column width — '
            'vertically, never dropped',
      );
      expect(
        find.descendant(of: timeCellFinder(), matching: find.byType(Text)),
        findsWidgets,
      );
    });

    testWidgets('tapping a signal row cell opens the day\'s sheet', (
      tester,
    ) async {
      await pumpChart(tester, chartHarness(entries: _rowsEntries));

      await tester.tap(chartCell(3, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(
        sheet.day,
        septSevenDay(3),
        reason: 'the tapped bleeding cell owns day 3',
      );
    });

    // The bleeding row hands its cell bounds to the shared square-box
    // symbol (lib/ui/bleeding_symbol.dart); the fill layout per level is
    // that symbol's convention, owned by test/bleeding_symbol_test.dart —
    // here only that every recorded level renders it at all.
    testWidgets('bleeding cells render the shared symbol: exactly one fill per '
        'menstruation level, interrupted dots for spotting, no fill for '
        'bleeding none', (tester) async {
      await pumpChart(tester, chartHarness(entries: _bleedingRowEntries));

      for (final index in [1, 3, 4, 5]) {
        expect(
          bleedingFills(index),
          findsOneWidget,
          reason: 'day $index: the recorded level shows one solid fill',
        );
      }
      expect(
        bleedingFills(2),
        findsWidgets,
        reason: 'spotting shows the shared symbol\'s interrupted dots',
      );
      expect(
        bleedingFills(0),
        findsNothing,
        reason: 'bleeding none keeps the empty cell',
      );
    });

    // Cross-check at a narrow viewport (the same device class the diary
    // sign-row repro used): the in-plot mucus letters render at the
    // minimum usable column width (21 px, forced by a 13-day range longer
    // than the 320 dp viewport). The two widest glyph shapes (the
    // two-glyph f/S token, and the S glyph with its EW superscript) must
    // lay out without a framework exception in their 21 px columns.
    testWidgets('the in-plot mucus letters render at the minimum column width '
        'without a framework exception', (tester) async {
      useNarrowPhoneViewport(tester);

      final entries = [
        for (var i = 0; i < 13; i++)
          DailyEntry(
            date: septSevenDay(i),
            bbtC: 36.5,
            mucusSign: switch (i) {
              10 => MucusSign.fs,
              11 => MucusSign.s,
              _ => null,
            },
            mucusQuality: i == 11 ? MucusQuality.ew : null,
          ),
      ];

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);
      try {
        await pumpChart(tester, chartHarness(entries: entries));
      } finally {
        FlutterError.onError = originalOnError;
      }

      // The initial auto-scroll parks the window on the newest days, so
      // both mucus days render — the letters are keyed glyphs themselves.
      final fDay = tester.widget<MucusSymbolText>(
        find.byKey(const ValueKey('inPlotMucus-10')),
      );
      expect(fDay.display!.symbol, 'f/S');
      final sDay = tester.widget<MucusSymbolText>(
        find.byKey(const ValueKey('inPlotMucus-11')),
      );
      expect(sDay.display!.superscript, 'EW');
      expect(
        errors,
        isEmpty,
        reason:
            'the mucus glyphs must lay out without a framework '
            'exception at the minimum column width',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // The raw sex/mucus observations, the mucus peak and the Mittelschmerz M
  // render INSIDE the temperature plot (mapped by the pure layer in
  // lib/ui/chart_marks.dart) — in the day's column, at the row pitches
  // −0.05 K (sex X), −0.15 K (peak dot), −0.25 K (mucus letter) and −0.35 K
  // (M) below the scale max, keyed `inPlot*` per day; every ink glyph
  // carries a `inPlotHalo*` stroke pass behind it. The top strip carries
  // only bleeding (see the rows tests above).

  // Five chart days:
  //  0: mucus S with EW quality AND the peak mark on it -> letter + dot
  //  1: sex at all three timings            -> three X marks in one column
  //  2: sex at the START slot only          -> one X at the start fraction
  //  3: mucus f (plain, no peak mark)       -> bare letter, no dot
  //  4: plain temperature day               -> no in-plot glyphs
  List<DailyEntry> inPlotEntries() => [
    DailyEntry(
      date: septSevenDay(0),
      bbtC: 36.5,
      mucusSign: MucusSign.s,
      mucusQuality: MucusQuality.ew,
    ),
    DailyEntry(
      date: septSevenDay(1),
      bbtC: 36.6,
      sexTimings:
          SexTiming.morning.bit | SexTiming.midday.bit | SexTiming.evening.bit,
    ),
    DailyEntry(
      date: septSevenDay(2),
      bbtC: 36.7,
      sexTimings: SexTiming.morning.bit,
    ),
    DailyEntry(date: septSevenDay(3), bbtC: 36.4, mucusSign: MucusSign.f),
    DailyEntry(date: septSevenDay(4), bbtC: 36.5),
  ];

  final inPlotMarks = [
    CycleMark(date: septSevenDay(0), type: CycleMarkTypes.mucusPeakDay),
  ];

  testWidgets('the in-plot glyph rows render per day: sex X marks by timing, '
      'mucus letters, and the peak dot on every peak-marked day — with its '
      'entry or alone', (tester) async {
    await pumpChart(
      tester,
      chartHarness(entries: inPlotEntries(), marks: inPlotMarks),
    );

    expect(find.byKey(const ValueKey('inPlotMucus-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotPeakDot-0')), findsOneWidget);
    for (final timing in SexTiming.values) {
      expect(
        find.byKey(ValueKey('inPlotSex-1-${timing.name}')),
        findsOneWidget,
        reason: 'the all-three-timings day renders the $timing X',
      );
    }
    expect(find.byKey(const ValueKey('inPlotSex-2-morning')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotSex-2-midday')),
      findsNothing,
      reason: 'no X for an unrecorded timing',
    );
    expect(find.byKey(const ValueKey('inPlotMucus-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotPeakDot-3')),
      findsNothing,
      reason: 'no dot without the peak mark',
    );
    expect(
      find.byKey(const ValueKey('inPlotMucus-4')),
      findsNothing,
      reason: 'a sign-free day renders no letter',
    );
    expect(find.byKey(const ValueKey('inPlotSex-4-morning')), findsNothing);
  });

  testWidgets('a peak-marked interior GAP day renders the dot alone: the dot '
      'hangs on the day, no letter X M or number joins it there, and an '
      'unflagged gap day draws no dot', (tester) async {
    final gapEntries = [
      DailyEntry(date: septSevenDay(0), bbtC: 36.5, mucusSign: MucusSign.s),
      DailyEntry(
        date: septSevenDay(2),
        bbtC: 36.7,
        sexTimings: SexTiming.morning.bit,
      ),
      DailyEntry(date: septSevenDay(4), bbtC: 36.5),
    ];
    final gapMarks = [
      CycleMark(date: septSevenDay(1), type: CycleMarkTypes.mucusPeakDay),
    ];
    await pumpChart(tester, chartHarness(entries: gapEntries, marks: gapMarks));

    expect(find.byKey(const ValueKey('inPlotPeakDot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotHaloPeakDot-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotMucus-1')),
      findsNothing,
      reason: 'a day without an entry renders no letter',
    );
    for (final timing in SexTiming.values) {
      expect(find.byKey(ValueKey('inPlotSex-1-${timing.name}')), findsNothing);
    }
    expect(find.byKey(const ValueKey('inPlotM-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('inPlotPeakDot-3')),
      findsNothing,
      reason: 'the unflagged gap day 3 carries no dot',
    );
  });

  testWidgets('each in-plot glyph sits at its column center (multi-timing '
      'Xs at their timing fraction) and the glyph rows keep their '
      'top→bottom order', (tester) async {
    await pumpChart(
      tester,
      chartHarness(entries: inPlotEntries(), marks: inPlotMarks),
    );

    final plot = tester.getRect(find.byType(LineChart));
    final colW = plot.width / inPlotEntries().length;

    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotMucus-0'))).center.dx,
      closeTo(plot.left + 0.5 * colW, 1),
      reason: 'the mucus letter centers in its day column',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotPeakDot-0'))).center.dx,
      closeTo(plot.left + 0.5 * colW, 1),
      reason: 'the peak dot centers in its day column',
    );

    // The rows are horizontal glyph bands inside the plot's top rows: the
    // Xs share one center height across their columns, and the peak dot
    // rides its own row BETWEEN the sex row above and the letters row
    // below. The exact pitches are the owner-eyeball row geometry — the
    // test keeps this order relation, not a mirrored pixel mapping.
    final sexY = tester
        .getRect(find.byKey(const ValueKey('inPlotSex-1-morning')))
        .center
        .dy;
    final dotY = tester
        .getRect(find.byKey(const ValueKey('inPlotPeakDot-0')))
        .center
        .dy;
    final letterY = tester
        .getRect(find.byKey(const ValueKey('inPlotMucus-0')))
        .center
        .dy;
    for (final timing in const ['1-midday', '1-evening']) {
      expect(
        tester.getRect(find.byKey(ValueKey('inPlotSex-$timing'))).center.dy,
        sexY,
        reason: 'the three timing Xs share the topmost glyph row',
      );
    }
    expect(
      dotY,
      greaterThan(sexY),
      reason: 'the sex X rides the row above the dot',
    );
    expect(
      dotY,
      lessThan(letterY),
      reason: 'the dot rides its own row above the letters',
    );
    for (final y in [sexY, dotY, letterY]) {
      expect(y, greaterThan(plot.top));
      expect(
        y,
        lessThan(plot.bottom),
        reason: 'every glyph row stays inside the plot',
      );
    }

    final fractions = {'morning': 1 / 6, 'midday': 0.5, 'evening': 5 / 6};
    for (final MapEntry(:key, :value) in fractions.entries) {
      expect(
        tester.getRect(find.byKey(ValueKey('inPlotSex-1-$key'))).center.dx,
        closeTo(plot.left + (1 + value) * colW, 1),
        reason: 'the $key-timing X sits at its fraction in ONE column',
      );
    }
    expect(
      tester
          .getRect(find.byKey(const ValueKey('inPlotSex-2-morning')))
          .center
          .dx,
      closeTo(plot.left + (2 + 1 / 6) * colW, 1),
    );
  });

  testWidgets('a surface-colored halo layer renders behind the sex, mucus '
      'and peak-dot glyphs, exactly centered', (tester) async {
    await pumpChart(
      tester,
      chartHarness(entries: inPlotEntries(), marks: inPlotMarks),
    );

    for (final haloKey in const [
      'inPlotHaloSex-2-morning',
      'inPlotHaloMucus-0',
      'inPlotHaloPeakDot-0',
    ]) {
      final halo = find.byKey(ValueKey(haloKey));
      expect(halo, findsOneWidget, reason: '$haloKey renders behind its ink');
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotHaloPeakDot-0'))).center,
      tester.getRect(inPlotPeakDot(0)).center,
      reason: 'the dot\'s halo backing sits exactly behind the dot',
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('inPlotHaloSex-2-morning')))
          .center,
      tester.getRect(find.byKey(const ValueKey('inPlotSex-2-morning'))).center,
      reason: 'the X halo sits exactly behind the ink',
    );
  });

  testWidgets('the in-plot glyphs keep the rows\' color roles at the shared '
      'mark alpha: X onSurface, letter and dot tertiary', (tester) async {
    await pumpChart(
      tester,
      chartHarness(entries: inPlotEntries(), marks: inPlotMarks),
    );

    final scheme = chartScheme(tester);
    // MucusSymbolText's outer RichText carries the DEFAULT text style; the
    // tertiary ink is the wrapped base span inside it.
    final letterSpan =
        tester
                .widgetList<RichText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('inPlotMucus-0')),
                    matching: find.byType(RichText),
                  ),
                )
                .map((rich) => rich.text)
                .whereType<TextSpan>()
                .where((span) => span.children != null)
                .single
                .children!
                .single
            as TextSpan;
    expect(
      letterSpan.style!.color,
      scheme.tertiary.withValues(alpha: chartMarkAlpha),
      reason: 'the mucus letter keeps the tertiary ink at 0.85 alpha',
    );
    expect(
      (tester.widget<Container>(inPlotPeakDot(0)).decoration as BoxDecoration)
          .color,
      scheme.tertiary.withValues(alpha: chartMarkAlpha),
      reason: 'the peak dot shares the letter\'s tertiary ink',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('inPlotSex-2-morning')))
          .style!
          .color,
      scheme.onSurface.withValues(alpha: chartMarkAlpha),
      reason: 'the sex X keeps the neutral onSurface ink at 0.85 alpha',
    );
  });

  testWidgets('a span-0.20 range keeps the sex row AND the peak dot '
      '(decoupled rows) and hides the mucus letters', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: inPlotEntries(),
        marks: inPlotMarks,
        temperatureRange: const TemperatureRange(min: 37.8, max: 38.0),
      ),
    );

    expect(
      find.byKey(const ValueKey('inPlotMucus-0')),
      findsNothing,
      reason: 'the 0.2 K span leaves no room for the letter row',
    );
    expect(find.byKey(const ValueKey('inPlotMucus-3')), findsNothing);
    expect(
      inPlotPeakDot(0),
      findsOneWidget,
      reason:
          'the peak dot is its own row: at span 0.20 its center lands '
          'exactly on the bottom margin — visible',
    );
    for (final timing in SexTiming.values) {
      expect(
        find.byKey(ValueKey('inPlotSex-1-${timing.name}')),
        findsOneWidget,
        reason: 'the $timing X stays — the sex row hides independently',
      );
    }
  });

  testWidgets('the plot renders exactly the mucus letters, the Mittelschmerz '
      'M, the sex X marks and their halos', (tester) async {
    await pumpChart(tester, chartHarness(entries: _rowsEntries));

    // The fixture's recorded observations are day 4's S+EW mucus plus
    // its Mittelschmerz M and day 6's start-slot sex.
    final inPlotKeys = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('inPlot'),
          ),
        )
        .map((w) => (w.key! as ValueKey<String>).value)
        .toSet();
    expect(
      inPlotKeys,
      {
        'inPlotMucus-4',
        'inPlotHaloMucus-4',
        'inPlotM-4',
        'inPlotHaloM-4',
        'inPlotSex-6-morning',
        'inPlotHaloSex-6-morning',
      },
      reason:
          'the plot carries the mucus letters, the M, the X marks '
          'and their halos',
    );
  });
}
