// Widget tests of the mark-entry bottom sheet on the cycle tab (Mode M,
// ADR-0001): tapping a chart day opens a modal sheet with the "edit day"
// action, the contextual set/remove actions for the mucus peak and the
// first higher measurement, and the computed info line (derived artifacts
// such as the baseline value and the 1-6 low numbering for that day).
//
// Unlike test/cycle_chart_evaluation_test.dart (fixed marks streams), these
// tests write through the REAL MarksDao against an in-memory database —
// the sheet must persist and the surface (chart overlay, sheet labels) must
// re-render from the marks stream after every write. Same harness pattern
// as test/app_shell_test.dart; the ProviderScope wraps the MaterialApp (as
// in the real app), so the modal route the sheet is pushed onto stays
// inside the scope and can read the providers.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-09-06 is a Sunday; the run covers 9/6 (idx 0) .. 9/16 (idx 10).
DateTime _d(int day) => DateTime.utc(2026, 9, day);

/// Same evaluation scenario as test/cycle_chart_evaluation_test.dart:
/// six lows 9/8..9/13 (numbered 6..1), the highest low 9/9 = baseline 36.4,
/// mucus peak 9/12 (idx 6), first higher 9/14 (idx 8), higher 9/15, 9/16.
final _entries = <DailyEntry>[
  DailyEntry(date: _d(6), bbtC: 36.9),
  DailyEntry(date: _d(7), bbtC: 36.3),
  DailyEntry(date: _d(8), bbtC: 36.2),
  DailyEntry(date: _d(9), bbtC: 36.4),
  DailyEntry(date: _d(10), bbtC: 36.3),
  DailyEntry(date: _d(11), bbtC: 36.1),
  DailyEntry(date: _d(12), bbtC: 36.2),
  DailyEntry(date: _d(13), bbtC: 36.3),
  DailyEntry(date: _d(14), bbtC: 36.9),
  DailyEntry(date: _d(15), bbtC: 36.9),
  DailyEntry(date: _d(16), bbtC: 37.0),
];

/// Marks seeded through the DAO BEFORE the UI builds.
final _peakMark =
    CycleMark(profileId: defaultProfileId, date: _d(12), type: CycleMarkTypes.mucusPeakDay);
final _firstHigherMark = CycleMark(
    profileId: defaultProfileId,
    date: _d(14),
    type: CycleMarkTypes.firstHigherMeasurement);

/// The database instance created by the scope's override, so tests can
/// assert what was actually STORED.
CycleDatabase? _db;
ProviderContainer? _container;

Future<void> _pump(
  WidgetTester tester, {
  required List<DailyEntry> entries,
  List<CycleMark> seedMarks = const [],
  DateTime? selectedDate,
  int initialTab = 0,
}) async {
  final initialSelected = DateOnly.normalize(
      selectedDate ?? DateTime.utc(2026, 9, 1));
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) async {
        final db = CycleDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        );
        _db = db;
        ref.onDispose(db.close);
        for (final mark in seedMarks) {
          await db.marksDao.addMark(mark.profileId, mark.date, mark.type,
              author: mark.author);
        }
        return db;
      }),
      dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      selectedDateProvider.overrideWith((ref) => initialSelected),
      tabIndexProvider.overrideWith((ref) => initialTab),
    ],
  );
  _container = container;
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: ZyklusScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Opens the sheet for the chart day at [index] via the marks row cell
/// under that day (the row cells share the chart's day-index space and are
/// aligned with the chart columns).
///
/// `warnIfMissed: false` because the tap point may fall on the cell's
/// Center-with-null-child slot (no number rendered), which does not absorb
/// hits itself — the enclosing InkWell's pointer listener still receives it.
Future<void> _tapDay(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('marksCell-$index')),
      warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// The stored mark types for one calendar day, from the REAL database.
Future<List<String>> _storedTypes(DateTime day) async =>
    (await _db!.marksDao.marksForDay(defaultProfileId, day))
        .map((m) => m.markType)
        .toList();

/// The dot painter the chart uses for the temperature dot of [dayIndex].
FlDotPainter? _dotPainter(WidgetTester tester, int dayIndex) {
  final chart = tester.widget<LineChart>(find.byType(LineChart));
  for (final bar in chart.data.lineBarsData) {
    final color = bar.color;
    if (color != null && color.a != 0) continue; // only the dot-only bars
    for (final spot in bar.spots) {
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
      }
    }
  }
  return null;
}

ColorScheme _scheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme;

void main() {
  testWidgets('tapping a chart day opens the mark-entry sheet, not the form',
      (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    await _tapDay(tester, 4); // 9/10, a numbered low (4)

    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'the day tap opens the modal sheet');
    expect(find.text('Edit day'), findsOneWidget,
        reason: 'the form jump stays reachable via "edit day"');
    expect(find.text('Set mucus peak'), findsOneWidget,
        reason: 'the day carries no peak mark -> the set action');
    expect(find.text('Set first higher measurement'), findsOneWidget,
        reason: 'the day carries no first-higher mark -> the set action');
    expect(find.text('Low measurement 4'), findsOneWidget,
        reason: '9/10 is the 4th low of the six before the first higher');
    expect(find.byType(LineChart), findsOneWidget,
        reason: 'the surface stays on the cycle tab');
  });

  testWidgets('the info line shows the computed baseline on the baseline day',
      (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    await _tapDay(tester, 3); // 9/9: highest of the six lows = baseline

    expect(find.text('Baseline: 36.40'), findsOneWidget,
        reason: 'the derived baseline value is shown on its own day');
    expect(find.text('Low measurement 5'), findsOneWidget,
        reason: 'the baseline day is also the 5th low (both facts hold)');
  });

  testWidgets('setting a mucus peak persists through the DAO and '
      're-renders the sheet and the chart', (tester) async {
    await _pump(tester, entries: _entries); // no marks yet

    await _tapDay(tester, 6); // 9/12, the day to mark
    await tester.tap(find.text('Set mucus peak'));
    await tester.pumpAndSettle();

    expect(await _storedTypes(_d(12)), contains('mucusPeakDay'),
        reason: 'the mark is persisted through marksDao');
    expect(find.text('Remove mucus peak'), findsOneWidget,
        reason: 'the sheet re-renders contextually after the write');
    expect(find.text('Set mucus peak'), findsNothing);
    final painter = _dotPainter(tester, 6);
    expect(painter, isA<RingDotPainter>(),
        reason: 'the chart overlay re-renders from the marks stream');
    expect((painter as RingDotPainter).ringColor, _scheme(tester).tertiary,
        reason: 'the mucus peak renders in the mucus color family');
  });

  testWidgets('tapping the same action again removes the mark',
      (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark]);

    await _tapDay(tester, 6);
    expect(find.text('Remove mucus peak'), findsOneWidget,
        reason: 'the day already carries the peak -> the remove action');
    await tester.tap(find.text('Remove mucus peak'));
    await tester.pumpAndSettle();

    expect(await _storedTypes(_d(12)), isEmpty,
        reason: 'the mark is removed from storage');
    expect(find.text('Set mucus peak'), findsOneWidget,
        reason: 'the label flips back to the set action');
  });

  testWidgets('both marks on one day are two independent toggles',
      (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark]);

    await _tapDay(tester, 6);
    // The day already carries the peak; the first-higher mark is addable
    // on the same day (two toggles side by side).
    await tester.tap(find.text('Set first higher measurement'));
    await tester.pumpAndSettle();
    expect(await _storedTypes(_d(12)),
        unorderedEquals(['mucusPeakDay', 'firstHigherMeasurement']),
        reason: 'both marks may live on one day');

    // Removing the second mark keeps the first one untouched.
    await tester.tap(find.text('Remove first higher measurement'));
    await tester.pumpAndSettle();
    expect(await _storedTypes(_d(12)), ['mucusPeakDay'],
        reason: 'the two toggles are independent');
    expect(find.text('Remove mucus peak'), findsOneWidget,
        reason: 'the peak toggle is unaffected');
    expect(find.text('Set first higher measurement'), findsOneWidget,
        reason: 'the first-higher toggle flipped back');
  });

  testWidgets('"edit day" writes the selected date + Tagebuch tab and closes '
      'the sheet', (tester) async {
    await _pump(tester,
        entries: _entries,
        selectedDate: _d(1),
        initialTab: 2, // a non-Tagebuch tab, so the write is observable
    );

    await _tapDay(tester, 4); // 9/10
    await tester.tap(find.text('Edit day'));
    await tester.pumpAndSettle();

    expect(_container!.read(selectedDateProvider), _d(10),
        reason: 'the tapped day is pre-selected in the entry form');
    expect(_container!.read(tabIndexProvider), 0,
        reason: 'the shell switches to the Tagebuch tab');
    expect(find.text('Edit day'), findsNothing,
        reason: 'the sheet closes after the navigation');
  });

  testWidgets('a symbol-row cell opens the same sheet', (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    // warnIfMissed: false — the tap point may fall on the cell's fixed-height
    // sign slot, which does not absorb hits itself; the enclosing InkWell's
    // pointer listener still receives it (same as the marks-row taps above).
    await tester.tap(find.byKey(const ValueKey('symbolCell-2')),
        warnIfMissed: false); // 9/8
    await tester.pumpAndSettle();

    expect(find.text('Edit day'), findsOneWidget);
    expect(find.text('Low measurement 6'), findsOneWidget,
        reason: '9/8 is the 6th (outermost) low');
  });

  testWidgets('a day outside any evaluation data shows no info line',
      (tester) async {
    await _pump(tester, entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    await _tapDay(tester, 0); // 9/6: before the six-low window

    expect(find.text('Edit day'), findsOneWidget);
    expect(find.byType(Text), findsWidgets); // the sheet itself renders
    for (final info in [
      'Baseline: 36.40',
      'Low measurement 1',
      'Low measurement 2',
      'Low measurement 3',
      'Low measurement 4',
      'Low measurement 5',
      'Low measurement 6',
    ]) {
      expect(find.text(info), findsNothing,
          reason: 'no derived artifact exists for this day');
    }
  });
}
