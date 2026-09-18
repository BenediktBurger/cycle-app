// Widget tests of the per-signal rows under the cycle chart (the paper's
// recording rows): one always-rendered row per signal — bleeding, mucus
// (with the reserved solid peak-dot slot above the glyph), cervix, sex,
// pain, measurement time. The rows hold ONLY day cells — their sample
// glyphs and localized row names live in the frozen left rail (see
// test/cycle_chart_left_rail_test.dart), keyed `${row}Corner` there. The
// measurement time renders as localized HH:mm text ONLY when the day
// column is wide enough; no per-day clock icon exists anywhere in the
// rows. Tapping a row cell opens the day's mark-entry sheet.
//
// Same harness pattern as test/cycle_chart_time_sex_pain_test.dart.
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

// Nine chart days covering one recorded fact per signal:
//  0: temperature WITH a recorded measurement time (6:30)
//  1: bleeding light
//  2: bleeding spotting
//  3: bleeding heavy
//  4: mucus S with EW quality, Mittelschmerz
//  5: cervix position low + firmness soft
//  6: sex at the START slot
//  7: breast pain
//  8: entry WITHOUT any facts (untracked-looking day, but recorded)
final _entries = <DailyEntry>[
  DailyEntry(date: _day(0), bbtC: 36.5, measuredAtMinutes: 6 * 60 + 30),
  DailyEntry(date: _day(1), bbtC: 36.6, bleeding: Bleeding.light),
  DailyEntry(date: _day(2), bbtC: 36.7, bleeding: Bleeding.spotting),
  DailyEntry(date: _day(3), bbtC: 36.4, bleeding: Bleeding.heavy),
  DailyEntry(
    date: _day(4),
    bbtC: 36.5,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.ew,
    painMittelschmerz: true,
  ),
  DailyEntry(
    date: _day(5),
    bbtC: 36.8,
    cervixPosition: CervixPosition.low,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(date: _day(6), bbtC: 37.0, sexTimings: SexTiming.start.bit),
  DailyEntry(date: _day(7), bbtC: 36.9, painBreast: true),
  DailyEntry(date: _day(8)),
];

const _dayCount = 9;

// The chart block's recording rows, top-down in render order: the top
// block inside the temperature grid (bleeding, mucus, Mittelschmerz M,
// sex), then below the curve: cervix, pain, disturbance (the disturbance
// letters sit at the bottom of the chart block), then below the chart
// block: time, note (the note indicator at the very bottom — the paper
// sheet's remarks home).
const _signalRows = [
  'bleeding',
  'mucus',
  'mittelschmerz',
  'sex',
  'cervix',
  'pain',
  'disturbance',
  'time',
  'note',
];

Finder _cell(int i, String row) => find.byKey(ValueKey('${row}Cell-$i'));

Finder _corner(String row) => find.byKey(ValueKey('${row}Corner'));

Finder _inCell(int i, String row, Finder inner) =>
    find.descendant(of: _cell(i, row), matching: inner);

Widget _chartHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(const <CycleMark>[])),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const Scaffold(body: ZyklusScreen()),
      ),
    );

/// The bleeding blob (the circle Container) inside the bleeding cell of
/// [index].
Container _bleedingBlob(WidgetTester tester, int index) => tester
    .widgetList<Container>(find.descendant(
        of: _cell(index, 'bleeding'), matching: find.byType(Container)))
    .firstWhere((container) =>
        (container.decoration! as BoxDecoration).shape == BoxShape.circle);

void main() {
  group('paper layout: bleeding, mucus, M and sex at the top of the '
      'temperature block', () {
    testWidgets(
        'the top signal rows render INSIDE the chart block above the '
        'curve; cervix, pain and time stay below it', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      for (final row in ['bleeding', 'mucus', 'mittelschmerz', 'sex']) {
        expect(tester.getRect(_cell(0, row)).top, lessThan(chartTop),
            reason: 'the $row row renders in the TOP of the temperature '
                'block, above the curve (paper sheet)');
      }
      for (final row in ['cervix', 'pain', 'time']) {
        expect(tester.getRect(_cell(0, row)).top, greaterThan(chartBottom),
            reason: 'the $row row stays below the temperature block');
      }
    });

    testWidgets(
        'the rows render in the paper order — bleeding, mucus, M '
        '(Mittelschmerz directly beneath the mucus row), sex — and the '
        'below-block rows follow the curve segment', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      double top(String row) => tester.getRect(_corner(row)).top;
      expect(
        ['bleeding', 'mucus', 'mittelschmerz', 'sex']
            .map(top)
            .toList(),
        [...['bleeding', 'mucus', 'mittelschmerz', 'sex'].map(top)]..sort(),
        reason: 'M sits directly beneath the mucus row (paper sheet), '
            'sex after it, bleeding on top');
      // The below-block rows keep their relative order (cervix before
      // pain before time) with a clear gap across the curve between the
      // segments.
      expect(top('cervix'), greaterThan(tester.getRect(_corner('sex')).bottom),
          reason: 'the below-block segment starts after the top segment '
              'and the curve');
      expect(top('pain'), greaterThan(top('cervix')));
      expect(top('time'), greaterThan(top('pain')));
    });

    testWidgets(
        'the Mittelschmerz letter M renders in its own row beneath the '
        'mucus row; the below-block pain row carries only B',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // Day 4 = the fixture's Mittelschmerz day (beside its mucus S): the
      // M letter renders in the mittelschmerz cell, directly beneath the
      // day's mucus glyph.
      expect(_inCell(4, 'mittelschmerz', find.text('M')), findsOneWidget,
          reason: 'Mittelschmerz renders its M letter in its own row, '
              'directly beneath the mucus row (paper sheet)');
      expect(_inCell(4, 'pain', find.text('M')), findsNothing,
          reason: 'the M letter moved out of the below-block pain row — '
              'flagged with TODO(user-review) in the chart code');
      expect(_inCell(7, 'pain', find.text('B')), findsOneWidget,
          reason: 'breast pain B stays in the below-block pain row');
      expect(_inCell(7, 'mittelschmerz', find.text('M')), findsNothing,
          reason: 'no M without the Mittelschmerz flag');
    });

    testWidgets('tapping a top-block cell opens the day sheet',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      await tester.tap(_cell(4, 'mucus'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, _day(4),
          reason: 'the moved top-block mucus cell keeps its tap behavior');
    });
  });

  group('per-signal rows', () {
    testWidgets(
        'every signal row renders for every windowed day, in order '
        'bleeding, mucus, mittelschmerz, sex, cervix, pain, time',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      for (var i = 0; i < _dayCount; i++) {
        for (final row in _signalRows) {
          expect(_cell(i, row), findsOneWidget,
              reason: 'row $row renders a cell for day index $i '
                  '(rows always render, even empty/untracked days)');
        }
      }

      // Row ORDER: the corner slots appear top-down bleeding .. time
      // (paper layout: the first four inside the top of the temperature
      // block, the rest below).
      final corners = _signalRows.map((row) => tester.getRect(_corner(row)));
      final tops = corners.map((r) => r.top).toList();
      expect(tops, equals([...tops]..sort()),
          reason: 'the signal rows render in the paper\'s order');
    });

    testWidgets(
        'each row\'s corner slot carries a sample glyph with a tooltip '
        'and a semantics label carrying the localized row name (en)',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      final rowNames = {
        'bleeding': 'Bleeding',
        'mucus': 'Fertility sign (mucus)',
        'mittelschmerz': 'Mittelschmerz',
        'cervix': 'Cervix',
        'sex': 'Sex',
        'pain': 'Pain',
        'disturbance': 'Disturbed measurement',
        'time': 'Measurement time',
        'note': 'Note',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        expect(find.byKey(ValueKey('${key}Corner')), findsOneWidget);
        final tooltips = tester
            .widgetList<Tooltip>(find.descendant(
                of: _corner(key), matching: find.byType(Tooltip)))
            .map((t) => t.message)
            .toList();
        expect(tooltips, [value],
            reason: 'row $key\'s corner slot carries the localized row name');
        expect(
          find.descendant(
              of: _corner(key),
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.label == value)),
          findsOneWidget,
          reason: 'row $key\'s corner slot announces the row name to '
              'screen readers',
        );
      }

      // The sample glyphs: a bleeding blob, the S mucus glyph, the
      // Mittelschmerz M, a cervix letter, the X, the B pain letter, and
      // the clock icon.
      expect(
          find.descendant(
              of: _corner('bleeding'), matching: find.byType(Container)),
          findsOneWidget,
          reason: 'the bleeding corner shows the blob sample');
      expect(
          find.descendant(
              of: _corner('mucus'), matching: find.byType(MucusSymbolText)),
          findsOneWidget,
          reason: 'the mucus corner shows the glyph sample');
      // Plain S, no quality qualifier: the superscript renders as a
      // Text('EW') WidgetSpan child when one is set — it must be absent.
      final mucusSample =
          tester.widget<MucusSymbolText>(find.descendant(
              of: _corner('mucus'), matching: find.byType(MucusSymbolText)));
      expect(mucusSample.display.superscript, isNull,
          reason: 'the mucus corner sample is the plain S glyph');
      expect(
          find.descendant(of: _corner('mucus'), matching: find.text('EW')),
          findsNothing,
          reason: 'the mucus corner sample carries no EW superscript');
      expect(
          find.descendant(
              of: _corner('mittelschmerz'), matching: find.text('M')),
          findsOneWidget,
          reason: 'the mittelschmerz corner shows the M sample');
      expect(find.descendant(of: _corner('cervix'), matching: find.text('m')),
          findsOneWidget,
          reason: 'the cervix corner shows a position letter sample');
      expect(find.descendant(of: _corner('sex'), matching: find.text('X')),
          findsOneWidget,
          reason: 'the sex corner shows the X sample');
      expect(find.descendant(of: _corner('pain'), matching: find.text('B')),
          findsOneWidget,
          reason: 'the pain corner shows the B sample '
              '(the Mittelschmerz M has its own row/corner)');
      expect(find.descendant(of: _corner('pain'), matching: find.text('M')),
          findsNothing);
      expect(
          find.descendant(
              of: _corner('time'), matching: find.byIcon(Icons.schedule)),
          findsOneWidget,
          reason: 'the time corner keeps the clock icon sample');
    });

    testWidgets('the row names use the German wording in de', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      final rowNames = {
        'bleeding': 'Blutung',
        'mucus': 'Fruchtbarkeitszeichen (Schleim)',
        'mittelschmerz': 'Mittelschmerz',
        'cervix': 'Muttermund',
        'sex': 'Sex',
        'pain': 'Schmerz',
        'disturbance': 'Messstörung',
        'time': 'Messzeitpunkt',
        'note': 'Notiz',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        final tooltips = tester
            .widgetList<Tooltip>(find.descendant(
                of: _corner(key), matching: find.byType(Tooltip)))
            .map((t) => t.message)
            .toList();
        expect(tooltips, [value], reason: 'de: row $key is $value');
      }
    });

    testWidgets('long-pressing a corner slot shows the row-name tooltip',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // The tooltip overlay shows the localized row name. The bare text
      // can pre-exist elsewhere (the legend's "Bleeding" entry), so pin
      // the OVERLAY as one additional occurrence of the word.
      final before = tester.widgetList<Text>(find.text('Bleeding')).length;
      await tester.longPress(find.byKey(const ValueKey('bleedingCorner')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Bleeding'), findsNWidgets(before + 1),
          reason: 'long-press shows the row-name tooltip overlay');
    });

    testWidgets('a recorded measurement time renders localized HH:mm text',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // 9 days fit the viewport comfortably: the columns are wide enough
      // for the time text. intl's localized Hm pattern is the padded
      // HH:mm form ("06:30") in both test locales here.
      expect(tester.getRect(_cell(0, 'time')).width, greaterThan(32),
          reason: 'precondition: a comfortable column width');
      expect(
          find.descendant(of: _cell(0, 'time'), matching: find.text('06:30')),
          findsOneWidget,
          reason: 'the localized HH:mm form of 6:30');
      expect(
          find.descendant(of: _cell(1, 'time'), matching: find.text('06:30')),
          findsNothing,
          reason: 'a day without a recorded time shows nothing');
    });

    testWidgets('the German locale renders the German HH:mm form',
        (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(
          find.descendant(of: _cell(0, 'time'), matching: find.text('06:30')),
          findsOneWidget,
          reason: 'the German locale keeps the padded HH:mm form');
    });

    testWidgets(
        'at minimum column width the time renders vertically — never '
        'dropped (wide columns keep the horizontal text, see the wide '
        'HH:mm test above and cycle_chart_time_sex_pain_test.dart)',
        (tester) async {
      Finder timeCellFinder() => find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('timeCell-'));

      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), below the horizontal threshold. The initial
      // auto-scroll puts the newest days' cells on screen.
      await tester.pumpWidget(_chartHarness(entries: [
        for (var i = 0; i < 60; i++)
          DailyEntry(
            date: _day(i),
            bbtC: 36.5,
            measuredAtMinutes: 6 * 60 + 30,
          ),
      ]));
      await tester.pumpAndSettle();

      expect(timeCellFinder(), findsWidgets,
          reason: 'the initial window renders time cells');
      expect(
          find.descendant(of: timeCellFinder(), matching: find.text('06:30')),
          findsWidgets,
          reason: 'the recorded time renders at the minimum column width — '
              'vertically (the old behavior dropped it)');
      expect(
          find.descendant(of: timeCellFinder(), matching: find.byType(Text)),
          findsWidgets);
    });

    testWidgets('no per-day clock icon exists anywhere in the signal rows',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      // The ONLY clock icon in the signal rows is the time row's corner
      // sample; the day cells never carry one (the old per-day clock
      // glyph is gone).
      for (var i = 0; i < _dayCount; i++) {
        expect(
            find.descendant(
                of: _cell(i, 'time'), matching: find.byIcon(Icons.schedule)),
            findsNothing,
            reason: 'day $i: no clock icon in the time cell');
      }
      expect(
          find.descendant(
              of: _corner('time'), matching: find.byIcon(Icons.schedule)),
          findsOneWidget,
          reason: 'only the corner sample keeps a clock icon');
    });

    testWidgets('tapping a signal row cell opens the day\'s sheet',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      await tester.tap(_cell(3, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, _day(3), reason: 'the tapped bleeding cell owns day 3');
    });

    testWidgets('the bleeding blob keeps the graded-opacity convention',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      final errorColor =
          Theme.of(tester.element(_cell(1, 'bleeding'))).colorScheme.error;

      // Day 2 = spotting: the hollow ring (transparent fill, visible border).
      final spotting = _bleedingBlob(tester, 2).decoration! as BoxDecoration;
      expect(spotting.shape, BoxShape.circle);
      expect(spotting.color, Colors.transparent);
      expect((spotting.border as Border).top.color, errorColor);

      // Day 1 = light: filled at 0.6.
      final light = _bleedingBlob(tester, 1).decoration! as BoxDecoration;
      expect(light.color, errorColor.withValues(alpha: 0.6));

      // Day 3 = heavy: filled at full strength.
      final heavy = _bleedingBlob(tester, 3).decoration! as BoxDecoration;
      expect(heavy.color, errorColor.withValues(alpha: 1.0));
    });
  });
}
