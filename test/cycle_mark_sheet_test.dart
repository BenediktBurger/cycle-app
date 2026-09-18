// Widget tests of the mark-entry bottom sheet on the cycle tab (Mode M,
// ADR-0001): tapping a chart day opens a modal sheet with the "edit day"
// action, the contextual set/remove actions for the mucus peak, the first
// higher measurement, the SUZ start and the cycle start (the authoritative
// cycle boundary — bleeding only suggests it), and the computed info lines
// (derived artifacts such as the baseline value, the 1-6 low numbering, the
// difference to the baseline for marked candidates and the
// stopped-evaluation notice).
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
final _peakMark = CycleMark(
    profileId: defaultProfileId,
    date: _d(12),
    type: CycleMarkTypes.mucusPeakDay);
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
  final initialSelected =
      DateOnly.normalize(selectedDate ?? DateTime.utc(2026, 9, 1));
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

void main() {
  testWidgets('tapping a chart day opens the mark-entry sheet, not the form',
      (tester) async {
    await _pump(tester,
        entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

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
    // No stopped-evaluation notice in an intact evaluation.
    expect(
        find.byKey(const ValueKey('cycleSheetEvaluationStopped')), findsNothing,
        reason: 'the evaluation did not stop — no notice');
  });

  testWidgets('the info line shows the computed baseline on the baseline day',
      (tester) async {
    await _pump(tester,
        entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    await _tapDay(tester, 3); // 9/9: highest of the six lows = baseline

    expect(find.text('Baseline: 36.40'), findsOneWidget,
        reason: 'the derived baseline value is shown on its own day');
    expect(find.text('Low measurement 5'), findsOneWidget,
        reason: 'the baseline day is also the 5th low (both facts hold)');
  });

  testWidgets('R7: circled days show the difference to the baseline',
      (tester) async {
    await _pump(tester,
        entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    await _tapDay(tester, 8); // 9/14: circled candidate #1, +0.50 K

    expect(find.text('+0.50 K above the baseline'), findsOneWidget,
        reason: 'the difference to the baseline is shown for easy checking');
    expect(find.text('Circled higher measurement 1'), findsOneWidget,
        reason: 'the ordinal of the circled candidate stays visible');
  });

  testWidgets(
      'R7: arrowed days show the difference too — without the '
      'circled ordinal line', (tester) async {
    // Peak unmarked: the candidates become arrows (R4) — the difference
    // display applies to circled AND arrowed days.
    await _pump(tester, entries: _entries, seedMarks: [_firstHigherMark]);

    await _tapDay(tester, 8); // 9/14: arrowed candidate #1, +0.50 K

    expect(find.text('+0.50 K above the baseline'), findsOneWidget,
        reason: 'arrowed candidates show the difference too (R7)');
    expect(find.text('Circled higher measurement 1'), findsNothing,
        reason: 'nothing is circled without a peak before the rise');
  });

  testWidgets(
      'a beyond-cap arrow keeps the difference line — it stays a '
      'marked candidate, just unnumbered (R4)', (tester) async {
    // Peak unmarked: every candidate is an arrow; the 5th (9/18) is beyond
    // its kind's four-cap, so it carries no ordinal — but it stays in the
    // connected sequence (R4) and still shows the R7 difference line.
    final entries = [
      ..._entries,
      DailyEntry(date: _d(17), bbtC: 36.5),
      DailyEntry(date: _d(18), bbtC: 36.5),
    ];
    await _pump(tester, entries: entries, seedMarks: [_firstHigherMark]);

    await _tapDay(tester, 12); // 9/18: beyond-cap arrow, +0.10 K

    expect(find.text('+0.10 K above the baseline'), findsOneWidget,
        reason: 'beyond-cap candidates stay marked (R4) and show R7');
    expect(find.text('Circled higher measurement 1'), findsNothing,
        reason: 'arrow ordinals never surface in the sheet');
  });

  testWidgets(
      'R4 per-kind ordinals: the circle ordinal restarts after the '
      'arrows — the sheet shows the circle number, not the overall count',
      (tester) async {
    // Peak 9/15 lies between the marked rise (9/14) and the later
    // candidates: 9/14 and the peak day itself are arrows, 9/16 is the
    // FIRST circle — its sheet line counts within the circle kind only.
    final entries = [..._entries, DailyEntry(date: _d(17), bbtC: 36.5)];
    await _pump(tester, entries: entries, seedMarks: [
      CycleMark(
          profileId: defaultProfileId,
          date: _d(15),
          type: CycleMarkTypes.mucusPeakDay),
      _firstHigherMark,
    ]);

    await _tapDay(tester, 10); // 9/16: first circle after the arrows

    expect(find.text('Circled higher measurement 1'), findsOneWidget,
        reason: 'the circle ordinal restarts within its own kind (R4)');
    expect(find.text('Circled higher measurement 3'), findsNothing,
        reason: 'the sheet shows the CIRCLE number, not the overall '
            'candidate count');
    expect(find.text('+0.60 K above the baseline'), findsOneWidget,
        reason: '9/16 is 37.0 — 0.60 K above the baseline 36.4');
  });

  testWidgets(
      'setting a mucus peak persists through the DAO and '
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
    // R6: the peak renders as a solid dot in the SYMBOL ROW — not as a
    // ring on the temperature curve.
    expect(find.byKey(const ValueKey('peakDot-6')), findsOneWidget,
        reason: 'the symbol row re-renders from the marks stream');
    expect(_dotPainter(tester, 6), isNot(isA<RingDotPainter>()),
        reason: 'the peak day keeps a plain dot on the curve (R6)');
  });

  testWidgets('tapping the same action again removes the mark', (tester) async {
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
    // The placement leaves the mark inconsistent (36.20 on 9/12 lies
    // below the baseline 36.90 of its window 9/6..9/11), so the owner
    // warning pops; Keep keeps the mark so the toggles stay independent.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Keep')));
    await tester.pumpAndSettle();

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

  testWidgets(
      '"edit day" writes the selected date + Tagebuch tab and closes '
      'the sheet', (tester) async {
    await _pump(
      tester,
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
    await _pump(tester,
        entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

    // warnIfMissed: false — the tap point may fall on the cell's fixed-height
    // sign slot, which does not absorb hits itself; the enclosing InkWell's
    // pointer listener still receives it (same as the marks-row taps above).
    await tester.tap(find.byKey(const ValueKey('bleedingCell-2')),
        warnIfMissed: false); // 9/8
    await tester.pumpAndSettle();

    expect(find.text('Edit day'), findsOneWidget);
    expect(find.text('Low measurement 6'), findsOneWidget,
        reason: '9/8 is the 6th (outermost) low');
  });

  testWidgets(
      'a broken sequence shows the stopped-evaluation notice '
      '(R2: the user re-marks the rise)', (tester) async {
    // Candidate 1 on 9/14, then TWO untracked days (9/15, 9/16), then 9/17
    // above the baseline: the automatic evaluation stops (R2).
    final entries = <DailyEntry>[
      DailyEntry(date: _d(6), bbtC: 36.2),
      DailyEntry(date: _d(7), bbtC: 36.1),
      DailyEntry(date: _d(8), bbtC: 36.4),
      DailyEntry(date: _d(9), bbtC: 36.3),
      DailyEntry(date: _d(10), bbtC: 36.2),
      DailyEntry(date: _d(11), bbtC: 36.3),
      DailyEntry(date: _d(12), bbtC: 36.1), // peak day
      DailyEntry(date: _d(13), bbtC: 36.3),
      DailyEntry(date: _d(14), bbtC: 36.8), // marked rise -> candidate 1
      // 9/15 + 9/16 untracked -> two gap days -> break.
      DailyEntry(date: _d(17), bbtC: 36.9), // would-be candidate, NOT marked
    ];
    await _pump(tester, entries: entries, seedMarks: [
      CycleMark(
          profileId: defaultProfileId,
          date: _d(12),
          type: CycleMarkTypes.mucusPeakDay),
      _firstHigherMark,
    ]);

    await _tapDay(tester, 11); // 9/17: the day after the break

    expect(find.byKey(const ValueKey('cycleSheetEvaluationStopped')),
        findsOneWidget,
        reason: 'the broken sequence surfaces the stopped state (R2)');
  });

  testWidgets('a day outside any evaluation data shows no info line',
      (tester) async {
    await _pump(tester,
        entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

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
      '+0.50 K above the baseline',
      'Circled higher measurement 1',
    ]) {
      expect(find.text(info), findsNothing,
          reason: 'no derived artifact exists for this day');
    }
    expect(
        find.byKey(const ValueKey('cycleSheetEvaluationStopped')), findsNothing,
        reason: 'the evaluation did not stop — no notice');
  });

  group('cycleStart toggle (the authoritative cycle-boundary mark)', () {
    testWidgets(
        'setting the cycle start persists a user-authored cycleStart mark '
        'and flips the action to the remove wording', (tester) async {
      await _pump(tester, entries: _entries); // no marks yet

      await _tapDay(tester, 4); // 9/10, an arbitrary day
      await tester.tap(find.text('Set cycle start'));
      await tester.pumpAndSettle();

      final stored = await _db!.marksDao.marksForDay(defaultProfileId, _d(10));
      expect(stored.map((m) => m.markType),
          contains(CycleMarkTypes.cycleStart),
          reason: 'the cycle start is persisted through the MarksDao '
              '(the user places the mark — bleeding only suggests)');
      final mark =
          stored.singleWhere((m) => m.markType == CycleMarkTypes.cycleStart);
      expect(mark.author, 'user',
          reason: 'the sheet placement is user-authored');
      expect(mark.profileId, defaultProfileId,
          reason: 'the mark binds to the sheet\'s profile');
      expect(find.text('Remove cycle start'), findsOneWidget,
          reason: 'the sheet re-renders contextually after the write');
      expect(find.text('Set cycle start'), findsNothing);
    });

    testWidgets('a present cycle start shows the removal wording and '
        'the remove action deletes it', (tester) async {
      await _pump(tester, entries: _entries, seedMarks: [
        CycleMark(
            profileId: defaultProfileId,
            date: _d(10),
            type: CycleMarkTypes.cycleStart),
      ]);

      await _tapDay(tester, 4); // 9/10: the marked day
      expect(find.text('Remove cycle start'), findsOneWidget,
          reason: 'the day already carries the mark -> the remove action');

      await tester.tap(find.text('Remove cycle start'));
      await tester.pumpAndSettle();

      expect(await _storedTypes(_d(10)), isEmpty,
          reason: 'the cycle start is removed from storage');
      expect(find.text('Set cycle start'), findsOneWidget,
          reason: 'the action flips back to the set wording');
    });
  });

  group('SUZ mark + suggestion (the app suggests, the user places)', () {
    testWidgets(
        'the computed SUZ day suggests the start with the EVENING phrasing, '
        'naming rule D', (tester) async {
      // Main scenario: the 3rd circled candidate (9/16, 37.0) is >= 0.2 K
      // above the baseline 36.4 -> rule D fires, SUZ begins 9/16 evening.
      await _pump(tester,
          entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

      await _tapDay(tester, 10); // 9/16: the computed suzBegins

      expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')), findsOneWidget,
          reason: 'the viewed day equals the computed suzBegins and '
              'no user SUZ mark exists anywhere in the cycle');
      expect(find.textContaining('begins this evening (rule D)'),
          findsOneWidget,
          reason: 'rule D: the suggestion names the rule AND carries the '
              'evening phrasing (rule D begins the SUZ that evening)');
      expect(find.textContaining('begins this morning'), findsNothing,
          reason: 'rule D must NOT render the morning phrasing');
    });

    testWidgets(
        'the suggestion carries the MORNING phrasing when rule E fires on '
        'the 4th circle', (tester) async {
      // 9/14..9/17 all 36.5 (+0.1 above the baseline): the 3rd circled
      // candidate is below the rule-D margin, so the 4th (9/17) fires
      // rule E — and rule E begins the SUZ in the MORNING (owner-corrected:
      // the SUZ begins the morning of the 4th circled measurement, not the
      // evening).
      final entries = [
        ..._entries.take(8),
        DailyEntry(date: _d(14), bbtC: 36.5),
        DailyEntry(date: _d(15), bbtC: 36.5),
        DailyEntry(date: _d(16), bbtC: 36.5),
        DailyEntry(date: _d(17), bbtC: 36.5),
      ];
      await _pump(tester,
          entries: entries, seedMarks: [_peakMark, _firstHigherMark]);

      await _tapDay(tester, 11); // 9/17: the computed suzBegins

      expect(find.byKey(const ValueKey('cycleSheetSuzSuggestion')),
          findsOneWidget);
      expect(find.textContaining('begins this morning (rule E)'),
          findsOneWidget,
          reason: 'rule E: the suggestion names the rule AND carries the '
              'morning phrasing (rule E begins the SUZ that morning)');
      expect(find.textContaining('begins this evening'), findsNothing,
          reason: 'rule E must NOT render the evening phrasing — the SUZ '
              'begins in the morning of the 4th circled day');
    });

    testWidgets(
        'the suggestion is suppressed once a user SUZ mark exists in the '
        'cycle', (tester) async {
      await _pump(tester, entries: _entries, seedMarks: [
        _peakMark,
        _firstHigherMark,
        CycleMark(
            profileId: defaultProfileId,
            date: _d(13),
            type: CycleMarkTypes.suzMorning),
      ]);

      await _tapDay(tester, 10); // 9/16: the computed suzBegins

      expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')), findsNothing,
          reason: 'a user SUZ mark anywhere in the cycle suppresses the '
              'suggestion');
    });

    testWidgets('no suggestion on days that are not the computed SUZ day',
        (tester) async {
      await _pump(tester,
          entries: _entries, seedMarks: [_peakMark, _firstHigherMark]);

      await _tapDay(tester, 8); // 9/14: the marked rise, not the SUZ day

      expect(
          find.byKey(const ValueKey('cycleSheetSuzSuggestion')), findsNothing);
    });

    testWidgets(
        'SUZ actions on any day: set evening, variant-switch to morning, '
        'remove', (tester) async {
      await _pump(tester, entries: _entries);
      await _tapDay(tester, 4); // 9/10 — an arbitrary day (actions on ANY day)

      await tester.tap(find.text('SUZ from this evening'));
      await tester.pumpAndSettle();
      expect(await _storedTypes(_d(10)), contains(CycleMarkTypes.suzEvening),
          reason: 'the SUZ mark is persisted through the MarksDao');
      expect(find.text('Remove SUZ from this evening'), findsOneWidget,
          reason: 'the removal label when the variant is present');

      // Variant switch: placing the other variant removes the one present.
      await tester.tap(find.text('SUZ from this morning'));
      await tester.pumpAndSettle();
      expect(await _storedTypes(_d(10)),
          unorderedEquals([CycleMarkTypes.suzMorning]),
          reason: 'placing one variant removes the other');
      expect(find.text('Remove SUZ from this morning'), findsOneWidget);
      expect(find.text('SUZ from this evening'), findsOneWidget,
          reason: 'the evening action flips back to its set label');

      await tester.tap(find.text('Remove SUZ from this morning'));
      await tester.pumpAndSettle();
      expect(await _storedTypes(_d(10)), isEmpty,
          reason: 'the removal action deletes the mark');
      expect(find.text('SUZ from this morning'), findsOneWidget,
          reason: 'the morning action flips back to its set label');
    });

    testWidgets('the sheet shows the day\'s recorded measurement time',
        (tester) async {
      // Wide chart columns spell the time as text in the time row, but the
      // sheet remains where the value surfaces unconditionally (at narrow
      // column widths the row cell stays empty).
      final entries = [..._entries];
      entries[4] = entries[4].copyWith(measuredAtMinutes: 6 * 60 + 30);
      await _pump(tester, entries: entries);

      await _tapDay(tester, 4); // 9/10

      expect(find.textContaining('Measurement time:'), findsOneWidget,
          reason: 'the recorded measurement time value is shown in the day '
              'sheet');
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.textContaining('6:30')),
          findsOneWidget,
          reason: 'the time itself is locale-formatted into the sheet line '
              '(the chart\'s time cell may spell the same text, so the '
              'assertion is scoped to the sheet)');
    });

    testWidgets('no measurement-time line on a day without a recorded time',
        (tester) async {
      await _pump(tester, entries: _entries);

      await _tapDay(tester, 4); // 9/10: temperature without a recorded time

      expect(find.textContaining('Measurement time:'), findsNothing,
          reason: 'nothing is shown when no measurement time was recorded');
    });

    testWidgets(
        'a manual SUZ mark never alters the arithmetic — the evaluation '
        'info lines stay as computed', (tester) async {
      await _pump(tester, entries: _entries, seedMarks: [
        _peakMark,
        _firstHigherMark,
        CycleMark(
            profileId: defaultProfileId,
            date: _d(12),
            type: CycleMarkTypes.suzEvening),
      ]);

      await _tapDay(tester, 8); // 9/14: circled candidate #1

      expect(find.text('+0.50 K above the baseline'), findsOneWidget,
          reason: 'the difference to the baseline is unchanged by the SUZ '
              'mark (compute-only separation)');
      expect(find.text('Circled higher measurement 1'), findsOneWidget,
          reason: 'the candidate sequence is unchanged by the SUZ mark');
    });
  });

  group('rise-mark consistency warning (owner decision 2026-09-17)', () {
    // The six-previous-calendar-day window of a mark on 9/13 is 9/7..9/12,
    // whose baseline is 36.40 (9/9); the marked day itself carries 36.30 —
    // NOT strictly above the baseline, so the placement is inconsistent.
    CycleMark markOn13() => CycleMark(
        profileId: defaultProfileId,
        date: _d(13),
        type: CycleMarkTypes.firstHigherMeasurement);

    testWidgets(
        'placing an inconsistent mark warns with the arithmetic and '
        'Keep keeps the mark', (tester) async {
      await _pump(tester, entries: _entries); // no marks yet

      await _tapDay(tester, 7); // 9/13: 36.30 below the baseline 36.40
      await tester.tap(find.text('Set first higher measurement'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'the inconsistent placement warns immediately');
      expect(find.text('First higher measurement'), findsOneWidget,
          reason: 'the dialog title names the mark, never a verdict');
      expect(
          find.text(
              '36.30 °C on the marked day is not above the baseline 36.40 °C.'),
          findsOneWidget,
          reason: 'the dialog shows the arithmetic fact: marked value vs '
              'baseline value');
      // Keep (like dismissing the dialog) leaves the mark standing.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Keep')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'the dialog is non-blocking: Keep only closes it');
      expect(await _storedTypes(_d(13)), contains('firstHigherMeasurement'),
          reason: 'Keep keeps the just-placed mark');
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the sheet stays open across the warning');
      expect(find.text('Remove first higher measurement'), findsOneWidget,
          reason: 'the toggle flipped by the kept mark');
    });

    testWidgets('the Remove choice removes the just-placed mark',
        (tester) async {
      await _pump(tester, entries: _entries);

      await _tapDay(tester, 7);
      await tester.tap(find.text('Set first higher measurement'));
      await tester.pumpAndSettle();

      // The sheet action carries the same label once the mark stands —
      // scope the tap to the dialog's Remove choice.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove first higher measurement')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await _storedTypes(_d(13)), isEmpty,
          reason: 'Remove undoes the placement through the toggle path');
      expect(find.text('Set first higher measurement'), findsOneWidget,
          reason: 'the toggle flipped back after the removal');
    });

    testWidgets('placing a consistent mark shows no dialog', (tester) async {
      await _pump(tester, entries: _entries);

      await _tapDay(tester, 8); // 9/14: 36.90 above the baseline 36.40
      await tester.tap(find.text('Set first higher measurement'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'only an INCONSISTENT placement warns');
      expect(await _storedTypes(_d(14)), contains('firstHigherMeasurement'),
          reason: 'the consistent mark is placed without the choice');
    });

    testWidgets(
        'a marked day without a usable temperature warns without a '
        'value arithmetic', (tester) async {
      final entries = [
        ..._entries.take(7), // 9/6..9/12 measured
        DailyEntry(date: _d(13)), // 9/13 tracked but UNMEASURED
        ..._entries.skip(8),
      ];
      await _pump(tester, entries: entries);

      await _tapDay(tester, 7); // 9/13: the unmeasured day (baseline 36.40)
      await tester.tap(find.text('Set first higher measurement'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'The marked day carries no usable temperature (unmeasured or '
              'interrupted).'),
          findsOneWidget,
          reason: 'without a marked value only the fact is stated');
    });

    testWidgets(
        'a merely-opened sheet for an existing inconsistent mark shows '
        'the PERSISTENT warning, no dialog', (tester) async {
      await _pump(tester, entries: _entries, seedMarks: [markOn13()]);

      await _tapDay(tester, 7); // 9/13: the marked day

      expect(find.byKey(const ValueKey('cycleSheetRiseConsistency')),
          findsOneWidget,
          reason: 'the inconsistency stays visible on every sheet open '
              '(later data edits cannot silently invalidate the mark)');
      expect(
          find.text(
              'No measurement on the marked day is above the baseline 36.40 °C.'),
          findsOneWidget,
          reason: 'the warning states the arithmetic fact only');
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'merely opening the sheet never pops the dialog');
    });

    testWidgets(
        'a later data edit that raises the baseline flips the warning on '
        '(the persistent line covers edits)', (tester) async {
      // The mark on 9/14 was placed over the baseline 36.40; an edited
      // 9/11 temperature 36.95 raises the window's baseline past the
      // marked 36.90 — the warning must show without re-placing the mark.
      final entries = [..._entries];
      entries[5] = entries[5].copyWith(bbtC: 36.95); // 9/11, in the window
      await _pump(tester, entries: entries, seedMarks: [_firstHigherMark]);

      await _tapDay(tester, 8); // 9/14: the marked day

      expect(find.byKey(const ValueKey('cycleSheetRiseConsistency')),
          findsOneWidget,
          reason: 'the warning recomputes with the changed baseline');
    });

    testWidgets('a consistent mark shows no warning line', (tester) async {
      await _pump(tester, entries: _entries, seedMarks: [_firstHigherMark]);

      await _tapDay(tester, 8); // 9/14: 36.90 above the baseline 36.40

      expect(find.byKey(const ValueKey('cycleSheetRiseConsistency')),
          findsNothing);
    });
  });
}
