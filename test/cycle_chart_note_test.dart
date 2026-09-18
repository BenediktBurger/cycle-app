// Widget tests of the day-note indicator on the cycle chart: a day whose
// entry carries a non-empty notes text shows a small indicator glyph in
// its day column in the row BELOW the chart block (per the paper sheet,
// whose remarks block sits under the Uhrzeit strip at the very bottom —
// placement flagged TODO(user-review) in the chart code). Days with an
// empty/absent notes field render nothing. Tapping the indicator cell
// opens the day's mark-entry sheet like every other cell.
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

// Four chart days:
//  0: plain temperature, no notes                 -> no indicator
//  1: temperature WITH a note                     -> indicator
//  2: notes = empty string                        -> no indicator
//  3: temperature WITHOUT a recorded note field   -> no indicator
final _entries = <DailyEntry>[
  DailyEntry(date: _day(0), bbtC: 36.5),
  DailyEntry(date: _day(1), bbtC: 36.6, notes: 'Impfung heute'),
  DailyEntry(date: _day(2), bbtC: 36.7, notes: ''),
  DailyEntry(date: _day(3), bbtC: 36.4),
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
      'a day with a non-empty note renders the indicator glyph in its '
      'day column, below the chart block', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    // The glyph rides in the day's column (below the time row, paper
    // "Bemerkungen" home).
    final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
    final noteRect = tester.getRect(_cell(1, 'note'));
    expect(noteRect.top, greaterThan(chartBottom),
        reason: 'the note-indicator row sits below the chart block');
    expect(tester.getRect(_cell(1, 'time')).top, lessThan(noteRect.top),
        reason: 'the note indicator renders below the measurement-time '
            'row, below the chart block');
    final cell = tester.getRect(_cell(1, 'bleeding'));
    expect(noteRect.left, closeTo(cell.left, 0.5),
        reason: 'the note cell shares the day column geometry');

    // The indicator glyphs: the sticky-note icon, one per noted day.
    expect(
        _inCell(1, 'note',
            find.byIcon(Icons.sticky_note_2_outlined)),
        findsOneWidget,
        reason: 'noted day 1 shows the indicator glyph in its column');
  });

  testWidgets('empty/absent notes render nothing', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    for (final i in [0, 2, 3]) {
      expect(
          _inCell(i, 'note', find.byIcon(Icons.sticky_note_2_outlined)),
          findsNothing,
          reason: 'day $i carries no note text');
    }
  });

  testWidgets('tapping a note-indicator cell opens the day sheet',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    await tester.tap(_cell(1, 'note'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _day(1), reason: 'the tapped note cell owns day 1');
  });

  testWidgets('the note row has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    expect(_corner('note'), findsOneWidget);
    final tooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: _corner('note'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(tooltips, ['Note'],
        reason: 'the note corner carries the localized row name');

    final cornerCenter = tester.getRect(_corner('note')).center.dy;
    final cellCenter = tester.getRect(_cell(1, 'note')).center.dy;
    expect(cornerCenter, closeTo(cellCenter, 0.5),
        reason: 'the note rail glyph is vertically centered on the row');

    await tester.pumpWidget(
        _chartHarness(entries: _entries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    final deTooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: _corner('note'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(deTooltips, ['Notiz'], reason: 'de: the note row is "Notiz"');
  });

  testWidgets('the help sheet explains the note indicator (en and de)',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text(
                'Note (this day carries a note in the Diary)')),
        findsOneWidget,
        reason: 'the indicator glyph needs a glossary entry');
  });

  testWidgets('the German help sheet explains the note indicator (de)',
      (tester) async {
    await tester.pumpWidget(
        _chartHarness(entries: _entries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text('Notiz (für diesen Tag ist eine Notiz '
                'im Tagebuch vorhanden)')),
        findsOneWidget,
        reason: 'de: the indicator glyph needs the German glossary entry');
  });
}
