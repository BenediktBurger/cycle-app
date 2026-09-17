// Widget tests of the cycle tab's recorded-fact glyphs in the symbol row
// under the temperature curve: the temperature measurement time (a small
// clock glyph whenever a temperature with a recorded measurement time
// exists), sex (an X), and the letter-coded pain flags B (breast) and
// M (Mittelschmerz). Days without the respective fact render nothing, and
// the legend names all three symbols. Same harness pattern as
// test/cycle_chart_cervix_test.dart (localized en, plus a de legend check).
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

DateTime _day(int index) => DateTime.utc(2026, 9, 7 + index);

// Seven chart days:
//  0: temperature WITH a recorded measurement time (6:30) -> clock glyph
//  1: temperature WITHOUT a recorded time                  -> no clock
//  2: sex, no temperature                                  -> X, no clock
//  3: breast pain only                                     -> B, no M
//  4: Mittelschmerz only                                   -> M, no B
//  5: sex AND both pains                                   -> X, B, M
//  6: plain temperature day                                -> nothing new
List<DailyEntry> _entries() => [
      DailyEntry(
        date: _day(0),
        bbtC: 36.5,
        measuredAtMinutes: 6 * 60 + 30,
      ),
      DailyEntry(date: _day(1), bbtC: 36.4),
      DailyEntry(date: _day(2), sex: true),
      DailyEntry(date: _day(3), painBreast: true),
      DailyEntry(date: _day(4), painMittelschmerz: true),
      DailyEntry(date: _day(5), sex: true, painBreast: true,
          painMittelschmerz: true),
      DailyEntry(date: _day(6), bbtC: 36.6),
    ];

Finder _cell(int i) => find.byKey(ValueKey('symbolCell-$i'));

Finder _inCell(int i, Finder inner) =>
    find.descendant(of: _cell(i), matching: inner);

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
  testWidgets('the measurement time renders a clock glyph on days with a '
      'recorded measurement time — and nowhere else', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(0, find.byIcon(Icons.schedule)), findsOneWidget,
        reason: 'the temperature day WITH a recorded time shows the clock '
            'glyph');
    expect(_inCell(1, find.byIcon(Icons.schedule)), findsNothing,
        reason: 'a temperature WITHOUT a recorded time shows no clock glyph');
    expect(_inCell(2, find.byIcon(Icons.schedule)), findsNothing,
        reason: 'a temperature-free day can never carry a measurement time '
            '(the domain drops the time without a temperature)');
    expect(_inCell(6, find.byIcon(Icons.schedule)), findsNothing,
        reason: 'a plain temperature day without a time shows no glyph');
  });

  testWidgets('sex renders an X only on days with sex recorded',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(2, find.text('X')), findsOneWidget,
        reason: 'the sex day shows the X glyph in its own cell');
    expect(_inCell(0, find.text('X')), findsNothing,
        reason: 'no X on a temperature day without sex');
    expect(_inCell(6, find.text('X')), findsNothing);
  });

  testWidgets('pain renders B and M independently, both on a combined day',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(3, find.text('B')), findsOneWidget,
        reason: 'breast pain shows the B letter');
    expect(_inCell(3, find.text('M')), findsNothing,
        reason: 'no Mittelschmerz letter without the flag');
    expect(_inCell(4, find.text('M')), findsOneWidget,
        reason: 'Mittelschmerz shows the M letter');
    expect(_inCell(4, find.text('B')), findsNothing,
        reason: 'no breast letter without the flag');
    expect(_inCell(5, find.text('B')), findsOneWidget);
    expect(_inCell(5, find.text('M')), findsOneWidget);
    expect(_inCell(6, find.text('B')), findsNothing,
        reason: 'a plain day shows neither pain letter');
    expect(_inCell(6, find.text('M')), findsNothing);
  });

  testWidgets('a combined day carries the sex X alongside both pain letters',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(5, find.text('X')), findsOneWidget,
        reason: 'the sex X and the pain letters coexist in one cell');
  });

  testWidgets('the legend names the measurement time, sex, and pain symbols',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(find.text('Measurement time'), findsOneWidget,
        reason: 'the clock glyph needs a legend entry');
    expect(find.text('Sex'), findsOneWidget,
        reason: 'the X glyph needs a legend entry');
    expect(find.text('Pain (B breast, M Mittelschmerz)'), findsOneWidget,
        reason: 'the B/M letters need a legend entry');
  });

  testWidgets('the German legend uses the German wording', (tester) async {
    await tester.pumpWidget(_chartHarness(
        entries: _entries(), locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(find.text('Messzeitpunkt'), findsOneWidget);
    expect(find.text('Sex'), findsOneWidget,
        reason: 'the diary already uses "Sex" in the German vocabulary');
    expect(find.text('Schmerz (B Brust, M Mittelschmerz)'), findsOneWidget);
  });
}
