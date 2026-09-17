// Widget tests of the per-signal rows under the cycle chart (the paper's
// recording rows): one always-rendered row per signal — bleeding, mucus
// (with the reserved solid peak-dot slot above the glyph), cervix, sex,
// pain, measurement time — each with its 44 px corner slot carrying a
// sample glyph plus the localized row name (tooltip + semantics). The
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
//  4: mucus S with EW quality
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

const _signalRows = [
  'bleeding',
  'mucus',
  'cervix',
  'sex',
  'pain',
  'time',
];

Finder _cell(int i, String row) => find.byKey(ValueKey('${row}Cell-$i'));

Finder _corner(String row) => find.byKey(ValueKey('${row}Corner'));

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
Container _bleedingBlob(WidgetTester tester, int index) =>
    tester.widgetList<Container>(find.descendant(
        of: _cell(index, 'bleeding'), matching: find.byType(Container)))
        .firstWhere((container) =>
            (container.decoration! as BoxDecoration).shape == BoxShape.circle);

void main() {
  group('per-signal rows', () {
    testWidgets('every signal row renders for every windowed day, in order '
        'bleeding, mucus, cervix, sex, pain, time', (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries));
      await tester.pumpAndSettle();

      for (var i = 0; i < _dayCount; i++) {
        for (final row in _signalRows) {
          expect(_cell(i, row), findsOneWidget,
              reason: 'row $row renders a cell for day index $i '
                  '(rows always render, even empty/untracked days)');
        }
      }

      // Row ORDER: the corner slots appear top-down bleeding .. time.
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
        'cervix': 'Cervix',
        'sex': 'Sex',
        'pain': 'Pain',
        'time': 'Measurement time',
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
              matching: find.byWidgetPredicate((w) =>
                  w is Semantics && w.properties.label == value)),
          findsOneWidget,
          reason: 'row $key\'s corner slot announces the row name to '
              'screen readers',
        );
      }

      // The sample glyphs: a bleeding blob, the S mucus glyph, a cervix
      // letter, the X, the B/M pain letters, and the clock icon.
      expect(find.descendant(of: _corner('bleeding'), matching: find.byType(Container)),
          findsOneWidget, reason: 'the bleeding corner shows the blob sample');
      expect(find.descendant(of: _corner('mucus'), matching: find.byType(MucusSymbolText)),
          findsOneWidget, reason: 'the mucus corner shows the glyph sample');
      expect(find.descendant(of: _corner('cervix'), matching: find.text('m')),
          findsOneWidget, reason: 'the cervix corner shows a position letter sample');
      expect(find.descendant(of: _corner('sex'), matching: find.text('X')),
          findsOneWidget, reason: 'the sex corner shows the X sample');
      expect(find.descendant(of: _corner('pain'), matching: find.text('B')),
          findsOneWidget, reason: 'the pain corner shows the B/M sample');
      expect(find.descendant(of: _corner('pain'), matching: find.text('M')),
          findsOneWidget);
      expect(find.descendant(of: _corner('time'), matching: find.byIcon(Icons.schedule)),
          findsOneWidget, reason: 'the time corner keeps the clock icon sample');
    });

    testWidgets('the row names use the German wording in de', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      final rowNames = {
        'bleeding': 'Blutung',
        'mucus': 'Fruchtbarkeitszeichen (Schleim)',
        'cervix': 'Muttermund',
        'sex': 'Sex',
        'pain': 'Schmerz',
        'time': 'Messzeitpunkt',
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
      final before =
          tester.widgetList<Text>(find.text('Bleeding')).length;
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
      expect(find.descendant(of: _cell(0, 'time'), matching: find.text('06:30')),
          findsOneWidget,
          reason: 'the localized HH:mm form of 6:30');
      expect(find.descendant(of: _cell(1, 'time'), matching: find.text('06:30')),
          findsNothing,
          reason: 'a day without a recorded time shows nothing');
    });

    testWidgets('the German locale renders the German HH:mm form',
        (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: _cell(0, 'time'), matching: find.text('06:30')),
          findsOneWidget,
          reason: 'the German locale keeps the padded HH:mm form');
    });

    testWidgets(
        'at minimum column width the time cell stays empty — and between '
        'the minimum and the threshold too', (tester) async {
      Finder timeCellFinder() => find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('timeCell-'));

      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), below the time-text threshold. The initial
      // auto-scroll puts the newest days' cells on screen.
      await tester.pumpWidget(_chartHarness(entries: [
        for (var i = 0; i < 60; i++) DailyEntry(date: _day(i % 9), bbtC: 36.5),
      ]));
      await tester.pumpAndSettle();

      expect(timeCellFinder(), findsWidgets,
          reason: 'the initial window renders time cells');
      expect(
          find.descendant(
              of: timeCellFinder(), matching: find.byType(Text)),
          findsNothing,
          reason: 'no time text renders at the minimum column width');
      expect(
          find.descendant(
              of: timeCellFinder(), matching: find.byIcon(Icons.schedule)),
          findsNothing,
          reason: 'no per-day clock icon anywhere at min column width');

      // Between minimum and threshold: 25 days fit the viewport but leave
      // only ~29 px per column — still below the threshold, so the cell
      // stays empty.
      await tester.pumpWidget(_chartHarness(entries: [
        for (var i = 0; i < 25; i++) DailyEntry(date: _day(i % 9), bbtC: 36.5),
      ]));
      await tester.pumpAndSettle();

      expect(timeCellFinder(), findsWidgets);
      expect(
          find.descendant(
              of: timeCellFinder(), matching: find.byType(Text)),
          findsNothing,
          reason: 'a ~29 px column is still too narrow for the time text');
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
      expect(find.descendant(of: _corner('time'), matching: find.byIcon(Icons.schedule)),
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

      final errorColor = Theme.of(tester.element(_cell(1, 'bleeding')))
          .colorScheme
          .error;

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
