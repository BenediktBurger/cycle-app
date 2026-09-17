// Widget tests of the cycle tab's recorded-fact glyphs in the symbol row
// under the temperature curve: the temperature measurement time (a small
// clock glyph whenever a temperature with a recorded measurement time
// exists), the sex time slots (one X glyph per SET SexTiming bit, drawn at
// that slot's third of the day column — multiple bits render multiple X
// marks), and the letter-coded pain flags B (breast) and M (Mittelschmerz).
// Days without the respective fact render nothing, and the legend names the
// symbols. Same harness pattern as test/cycle_chart_cervix_test.dart
// (localized en, plus a de legend check).
import 'package:cycle_app/domain/cervix.dart';
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
List<DailyEntry> _entries() => [
      DailyEntry(
        date: _day(0),
        bbtC: 36.5,
        measuredAtMinutes: 6 * 60 + 30,
      ),
      DailyEntry(date: _day(1), bbtC: 36.4),
      DailyEntry(date: _day(2), sexTimings: SexTiming.start.bit),
      DailyEntry(date: _day(3), painBreast: true),
      DailyEntry(date: _day(4), painMittelschmerz: true),
      DailyEntry(
        date: _day(5),
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
        painBreast: true,
        painMittelschmerz: true,
      ),
      DailyEntry(date: _day(6), bbtC: 36.6),
      DailyEntry(
        date: _day(7),
        cervixFirmness: CervixFirmness.soft,
      ),
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

  testWidgets('sex renders X marks only on days with recorded time slots',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(2, find.text('X')), findsOneWidget,
        reason: 'the sex day shows the X glyph in its own cell');
    expect(_inCell(0, find.text('X')), findsNothing,
        reason: 'no X on a temperature day without sex');
    expect(_inCell(6, find.text('X')), findsNothing);
  });

  testWidgets('every set sex time slot renders its own X — multiple slots '
      'render multiple X marks on one day', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(5, find.text('X')), findsNWidgets(2),
        reason: 'two recorded slots (start + end) render two X marks');
    expect(_inCell(2, find.text('X')), findsOneWidget,
        reason: 'a single recorded slot renders exactly one X');
  });

  testWidgets('each X sits at its slot\'s third of the day column',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    double fractionOf(Rect cell, Rect glyph) =>
        (glyph.center.dx - cell.left) / cell.width;

    final cell2 = tester.getRect(find.byKey(const ValueKey('symbolCell-2')));
    final startX = tester.getRect(_inCell(2, find.text('X')));
    expect(fractionOf(cell2, startX), closeTo(1 / 6, 0.05),
        reason: 'a start-slot X renders in the START third (center ~1/6) of '
            'the day column');

    final cell5 = tester.getRect(find.byKey(const ValueKey('symbolCell-5')));
    final xRects = _inCell(5, find.text('X')).evaluate().map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList()
      ..sort((a, b) => a.center.dx.compareTo(b.center.dx));
    expect(xRects, hasLength(2),
        reason: 'both X marks must sit inside their own day column');
    expect(fractionOf(cell5, xRects.first), closeTo(1 / 6, 0.05),
        reason: 'the first X belongs to the start slot (left third)');
    expect(fractionOf(cell5, xRects.last), closeTo(5 / 6, 0.05),
        reason: 'the second X belongs to the end slot (right third)');
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

  testWidgets('a combined day carries the sex X marks alongside both pain '
      'letters', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(5, find.text('X')), findsNWidgets(2),
        reason: 'the sex X marks and the pain letters coexist in one cell');
  });

  testWidgets('a firmness-only day renders its glyph with no position '
      'letters', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(_inCell(7, find.text('w')), findsOneWidget,
        reason: 'the soft-firmness glyph (paper shorthand w) renders in its '
            'own cell');
    for (final glyph in ['t', 'm', 'h', 'sh', 'u']) {
      expect(_inCell(7, find.text(glyph)), findsNothing,
          reason: 'no position letter ($glyph) without a position '
              'observation');
    }
  });

  testWidgets('the legend names the measurement time, sex, firmness, and '
      'pain symbols', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(find.text('Measurement time'), findsOneWidget,
        reason: 'the clock glyph needs a legend entry');
    expect(find.text('Sex (X per time of day)'), findsOneWidget,
        reason: 'the X glyph needs a legend entry; the wording mentions the '
            'per-slot X now that a day can carry several');
    expect(find.text('Cervix firmness'), findsOneWidget,
        reason: 'the firmness glyph needs a legend entry, parallel to the '
            'position entry');
    expect(find.text('Pain (B breast, M Mittelschmerz)'), findsOneWidget,
        reason: 'the B/M letters need a legend entry');
  });

  testWidgets('the German legend uses the German wording', (tester) async {
    await tester.pumpWidget(_chartHarness(
        entries: _entries(), locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(find.text('Messzeitpunkt'), findsOneWidget);
    expect(find.text('Sex (X je Zeitpunkt)'), findsOneWidget,
        reason: 'the diary already uses "Sex" in the German vocabulary');
    expect(find.text('Muttermund-Festigkeit'), findsOneWidget);
    expect(find.text('Schmerz (B Brust, M Mittelschmerz)'), findsOneWidget);
  });
}
