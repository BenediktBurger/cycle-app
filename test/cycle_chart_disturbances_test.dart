// Widget tests of the temperature-disturbance letters at the bottom of
// the cycle chart block: a day carrying one of the NER disturbance flags
// (late to bed, night awakening, alcohol, illness) renders its letter
// code in the disturbance row — in the day's column, keyed like the
// other rows — while plain days render nothing. The letters are the raw
// TempDisturbance tokens of the day's tempDisturbances mask, read
// through a single letter-mapping seam (see the comment on
// disturbanceLetters in lib/ui/cycle.dart). The interrupted curve
// rendering is keyed to the ignoreTemperature MARK, not this mask —
// pinned by test/cycle_chart_temperature_test.dart.
//
// Same harness pattern as test/cycle_chart_rows_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

// Six chart days:
//  0: plain temperature, no disturbance flag   -> nothing in the row
//  1: illness (kr bit)                         -> kr
//  2: alcohol (alk bit)                        -> alk
//  3: late to bed (sp bit)                     -> sp
//  4: night awakening (a bit)                  -> a
//  5: all four flags together                  -> kr, alk, sp, a stacked
final _entries = <DailyEntry>[
  DailyEntry(date: _day(0), bbtC: 36.5),
  DailyEntry(
      date: _day(1), bbtC: 36.6, tempDisturbances: TempDisturbance.kr.bit),
  DailyEntry(
      date: _day(2), bbtC: 36.7, tempDisturbances: TempDisturbance.alk.bit),
  DailyEntry(
      date: _day(3), bbtC: 36.4, tempDisturbances: TempDisturbance.sp.bit),
  DailyEntry(
      date: _day(4), bbtC: 36.5, tempDisturbances: TempDisturbance.a.bit),
  DailyEntry(
    date: _day(5),
    bbtC: 36.8,
    tempDisturbances: TempDisturbance.values.fold(0, (mask, d) => mask | d.bit),
  ),
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

void main() {
  testWidgets(
      'each exclusion flag renders its letter code in the disturbance row '
      'at the bottom of the chart block, in the day\'s column',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
    for (final entry in {
      1: 'kr',
      2: 'alk',
      3: 'sp',
      4: 'a',
    }.entries) {
      final cellRect = tester.getRect(_cell(entry.key, 'disturbance'));
      expect(cellRect.top, greaterThan(chartBottom),
          reason: 'the disturbance row sits at the bottom of the chart '
              'block, below the curve');
      expect(_inCell(entry.key, 'disturbance', find.text(entry.value)),
          findsOneWidget,
          reason: 'day ${entry.key} carries its disturbance flag\'s letter '
              'code (${entry.value}) in the day\'s column');
      // The letter sits inside its day column horizontally (same column
      // geometry as every other row).
      final curveCell = tester.getRect(_cell(entry.key, 'bleeding'));
      expect(cellRect.left, closeTo(curveCell.left, 0.5),
          reason: 'the disturbance cell shares the day column geometry');
    }
  });

  testWidgets('plain days render nothing in the disturbance row',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      expect(_inCell(0, 'disturbance', find.text(letter)), findsNothing,
          reason: 'a plain day shows no letter code');
    }
  });

  testWidgets('a multi-flag day renders its letters stacked in one cell',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    final cell = tester.getRect(_cell(5, 'disturbance'));
    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      final rects = _inCell(5, 'disturbance', find.text(letter))
          .evaluate()
          .map((element) {
        final box = element.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }).toList();
      expect(rects, hasLength(1),
          reason: 'the $letter code renders exactly once');
      final rect = rects.single;
      expect(rect.left, greaterThanOrEqualTo(cell.left - 0.5));
      expect(rect.right, lessThanOrEqualTo(cell.right + 0.5),
          reason: 'the stacked letters stay inside the day column');
    }
    // Stacked: the letters render at DIFFERENT vertical positions (the
    // paper sheet writes disturbance codes one under the other). Render
    // order follows the mask's token order — alk (bit 4) stacks above
    // kr (bit 8).
    final krRect = tester.getRect(_inCell(5, 'disturbance', find.text('kr')));
    final alkRect =
        tester.getRect(_inCell(5, 'disturbance', find.text('alk')));
    expect(alkRect.bottom, lessThanOrEqualTo(krRect.top),
        reason: 'the stacked letters do not overlap');
  });

  testWidgets('tapping a disturbance cell opens the day sheet',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    await tester.tap(_cell(1, 'disturbance'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _day(1),
        reason: 'the tapped disturbance cell owns day 1');
  });

  testWidgets(
      'the disturbance row has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    expect(_corner('disturbance'), findsOneWidget);
    final tooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: _corner('disturbance'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(tooltips, ['Disturbed measurement'],
        reason: 'the disturbance corner carries the localized row name');

    // Vertical alignment with its row (shared row heights, like every
    // other rail glyph).
    final cornerCenter = tester.getRect(_corner('disturbance')).center.dy;
    final cellCenter =
        tester.getRect(_cell(3, 'disturbance')).center.dy;
    expect(cornerCenter, closeTo(cellCenter, 0.5),
        reason: 'the disturbance rail glyph is vertically centered on the '
            'row');

    await tester.pumpWidget(_chartHarness(
        entries: _entries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    final deTooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: _corner('disturbance'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(deTooltips, ['Messstörung'],
        reason: 'de: the disturbance row carries the German row name');
  });

  testWidgets('the help sheet explains the disturbance letters (en)',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text(
                'Interrupted days (kr illness, alk alcohol, R travel, '
                'a other)')),
        findsOneWidget,
        reason: 'the letter codes need a legend entry naming today\'s '
            'vocabulary (the NER-scheme item may re-vocabulary it)');
  });

  testWidgets('the German help sheet explains the disturbance letters (de)',
      (tester) async {
    await tester.pumpWidget(
        _chartHarness(entries: _entries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text(
                'Gestörte Messung (kr krank, alk Alkohol, R Reise, '
                'a anderes)')),
        findsOneWidget,
        reason: 'de: the letter codes carry the German vocabulary');
  });
}
