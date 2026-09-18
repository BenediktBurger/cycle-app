// Widget tests of the evaluation table under the cycle chart (the paper's
// bottom summary): one ROW per attribute — cycle length, period start,
// period end, mucus peak, SUZ start, evaluation status — and one COLUMN per
// cycle group, computed purely at render time from evaluateCycles +
// groupIntoCycles (mark-driven boundaries: the scenarios' cycleStart marks
// open the groups). Nothing is persisted (ADR-0001): a marks re-emit
// live-updates the table without any database write. Missing values render
// as the "—" dash. More cycles than fit the viewport scroll horizontally so
// the attribute rows stay readable.
//
// Two harnesses: direct CycleSummaryTable construction (cell values, keys,
// both locales) and the ZyklusScreen integration (the harness pattern of
// test/cycle_chart_rows_test.dart, with stream controllers for the live
// marks update).
import 'dart:async';

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

final _seedColor = const Color(0xFF6750A4);

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

/// The diary's localized date form (the widget must render the same form).
String yMd(DateTime date, String locale) =>
    DateFormat.yMd(locale).format(DateOnly.normalize(date).toLocal());

// ---------------------------------------------------------------------------
// Scenario A: three cycle groups — two finished cycles (starts 2026-03-01
// and 2026-03-28) plus one open third (start 2026-04-20), with a rules-D
// evaluation marked in cycle 1.
// ---------------------------------------------------------------------------

/// Cycle 1: starts 2026-03-01, bleeding Mar 1-3 (heavy -> medium -> light),
/// spotting Mar 4 (level 1 — does NOT extend the period end), the six-low
/// window Mar 9-14 at 36.4 (baseline 36.4), the rise Mar 15-17 at 36.7.
final _twoCycleEntries = <DailyEntry>[
  DailyEntry(date: d(3, 1), bbtC: 36.4, bleeding: Bleeding.heavy),
  DailyEntry(date: d(3, 2), bbtC: 36.4, bleeding: Bleeding.medium),
  DailyEntry(date: d(3, 3), bbtC: 36.4, bleeding: Bleeding.light),
  DailyEntry(date: d(3, 4), bbtC: 36.4, bleeding: Bleeding.spotting),
  DailyEntry(date: d(3, 5), bbtC: 36.4),
  DailyEntry(date: d(3, 6), bbtC: 36.4),
  DailyEntry(date: d(3, 7), bbtC: 36.4),
  DailyEntry(date: d(3, 8), bbtC: 36.4),
  DailyEntry(date: d(3, 9), bbtC: 36.4),
  DailyEntry(date: d(3, 10), bbtC: 36.4),
  DailyEntry(date: d(3, 11), bbtC: 36.4),
  DailyEntry(date: d(3, 12), bbtC: 36.4),
  DailyEntry(date: d(3, 13), bbtC: 36.4),
  DailyEntry(date: d(3, 14), bbtC: 36.4),
  DailyEntry(date: d(3, 15), bbtC: 36.7),
  DailyEntry(date: d(3, 16), bbtC: 36.7),
  DailyEntry(date: d(3, 17), bbtC: 36.7),
  DailyEntry(date: d(3, 18), bbtC: 36.7),
  DailyEntry(date: d(3, 27), bbtC: 36.7),
  // Cycle 2: starts 2026-03-28, bleeding Mar 28-30, then a gap of
  // untracked days until cycle 3's start mark (the gap keeps the length
  // arithmetic calendar-honest — the length spans it).
  DailyEntry(date: d(3, 28), bleeding: Bleeding.heavy),
  DailyEntry(date: d(3, 29), bleeding: Bleeding.medium),
  DailyEntry(date: d(3, 30), bleeding: Bleeding.light),
  DailyEntry(date: d(3, 31)),
  // Cycle 3: starts 2026-04-20, open (no further start mark recorded).
  DailyEntry(date: d(4, 20), bleeding: Bleeding.heavy),
];

/// The marks of the rules-D scenario: the peak on Mar 14 and the first
/// higher measurement on Mar 15 (so Mar 15-17 are CIRCLES — all after the
/// peak — and the 3rd circle clears the 0.2 K margin → SUZ on Mar 17).
/// The cycleStart marks open the three cycle groups (at the days that used
/// to be the bleeding onsets — the mark is the authoritative boundary).
final _ruleDMarks = <CycleMark>[
  CycleMark(profileId: 1, date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(profileId: 1, date: d(3, 28), type: CycleMarkTypes.cycleStart),
  CycleMark(profileId: 1, date: d(4, 20), type: CycleMarkTypes.cycleStart),
  CycleMark(profileId: 1, date: d(3, 14), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(
      profileId: 1,
      date: d(3, 15),
      type: CycleMarkTypes.firstHigherMeasurement),
];

List<CycleEvaluation> _evaluations(List<DailyEntry> entries,
        [List<CycleMark> marks = const []]) =>
    evaluateCycles(entries, marks);

// ---------------------------------------------------------------------------
// Scenario B: a leading group predates the first cycleStart mark (Feb 25-28, spotting
// on Feb 26) before scenario A's cycles.
// ---------------------------------------------------------------------------

final _leadingEntries = <DailyEntry>[
  DailyEntry(date: d(2, 25), bbtC: 36.4),
  DailyEntry(date: d(2, 26), bbtC: 36.4, bleeding: Bleeding.spotting),
  DailyEntry(date: d(2, 27), bbtC: 36.4),
  DailyEntry(date: d(2, 28), bbtC: 36.4),
  DailyEntry(date: d(3, 1), bleeding: Bleeding.heavy),
  DailyEntry(date: d(3, 28), bleeding: Bleeding.heavy),
  DailyEntry(date: d(4, 20), bleeding: Bleeding.heavy),
];

/// The leading group (Feb 25-28) predates the first cycleStart mark — it
/// keeps `startsAtMenstruation == false` while the marked days open the
/// three cycle groups.
final _leadingMarks = <CycleMark>[
  CycleMark(profileId: 1, date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(profileId: 1, date: d(3, 28), type: CycleMarkTypes.cycleStart),
  CycleMark(profileId: 1, date: d(4, 20), type: CycleMarkTypes.cycleStart),
];

// ---------------------------------------------------------------------------
// Scenario C: the R2 stop — the first higher measurement on Mar 10, one
// above-baseline candidate, then TWO untracked days (Mar 11-12) before the
// next above-baseline value: more than one intervening gap day stops the
// automatic evaluation (no SUZ, the localized stopped note in the status).
// ---------------------------------------------------------------------------

final _stoppedEntries = <DailyEntry>[
  DailyEntry(date: d(3, 1), bbtC: 36.4, bleeding: Bleeding.heavy),
  DailyEntry(date: d(3, 2), bbtC: 36.4),
  DailyEntry(date: d(3, 3), bbtC: 36.4),
  DailyEntry(date: d(3, 4), bbtC: 36.4),
  DailyEntry(date: d(3, 5), bbtC: 36.4),
  DailyEntry(date: d(3, 6), bbtC: 36.4),
  DailyEntry(date: d(3, 7), bbtC: 36.4),
  DailyEntry(date: d(3, 8), bbtC: 36.4),
  DailyEntry(date: d(3, 9), bbtC: 36.4),
  DailyEntry(date: d(3, 10), bbtC: 36.7),
  DailyEntry(date: d(3, 13), bbtC: 36.7),
];

final _stoppedMarks = <CycleMark>[
  CycleMark(profileId: 1, date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(
      profileId: 1,
      date: d(3, 10),
      type: CycleMarkTypes.firstHigherMeasurement),
];

// ---------------------------------------------------------------------------
// Scenario D: several plain cycle starts for the scroll-behavior tests.
// ---------------------------------------------------------------------------

List<DailyEntry> _onsetEntries(int count) => [
      for (var i = 0; i < count; i++) ...[
        DailyEntry(date: d(3, 1).add(Duration(days: 25 * i)), bleeding: Bleeding.heavy),
        DailyEntry(
            date: d(3, 1).add(Duration(days: 25 * i + 1)),
            bleeding: Bleeding.light),
      ],
    ];

/// The cycle starts matching [_onsetEntries]: one cycleStart mark per
/// 25-day period on the first of its two bleeding days.
List<CycleMark> _onsetMarks(int count) => [
      for (var i = 0; i < count; i++)
        CycleMark(
            profileId: 1,
            date: d(3, 1).add(Duration(days: 25 * i)),
            type: CycleMarkTypes.cycleStart),
    ];

// ---------------------------------------------------------------------------
// Harnesses.
// ---------------------------------------------------------------------------

Widget _tableHarness({
  required List<CycleEvaluation> evaluations,
  Locale locale = const Locale('en'),
  double width = 800,
}) =>
    MaterialApp(
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: CycleSummaryTable(evaluations: evaluations),
          ),
        ),
      ),
    );

Widget _screenHarness({
  required Stream<List<DailyEntry>> entries,
  Stream<List<CycleMark>>? marks,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => entries),
        marksProvider
            .overrideWith((ref) => marks ?? Stream.value(const <CycleMark>[])),
        selectedDateProvider.overrideWith((ref) => _twoCycleEntries.first.date),
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

Finder _cell(String attribute, int column) =>
    find.byKey(ValueKey('cycleSummaryCell-$attribute-$column'));

Finder _header(int column) =>
    find.byKey(ValueKey('cycleSummaryHeader-$column'));

Finder _scroll() => find.byKey(const ValueKey('cycleSummaryScroll'));

double _maxScrollExtent(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(
            of: _scroll(), matching: find.byType(Scrollable)))
        .position
        .maxScrollExtent;

void main() {
  group('attribute rows and per-cycle columns (direct construction)', () {
    testWidgets(
        'one column per cycle group with the localized attribute-row labels '
        '(en)', (tester) async {
      await tester.pumpWidget(_tableHarness(
          evaluations: _evaluations(_twoCycleEntries, _ruleDMarks)));
      await tester.pumpAndSettle();

      // Six attribute rows, localized:
      for (final label in [
        'Cycle length',
        'Period start',
        'Period end',
        'Mucus peak',
        'SUZ start',
        'Evaluation',
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'the attribute row "$label" renders with its label');
      }

      // One column per cycle group: three marked starts, numbered.
      expect(_header(0), findsOneWidget);
      expect(_header(1), findsOneWidget);
      expect(_header(2), findsOneWidget);
      expect(find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('cycleSummaryHeader-')),
          findsNWidgets(3), reason: 'exactly one column per cycle group');
      expect(find.text('Cycle 1'), findsOneWidget);
      expect(find.text('Cycle 2'), findsOneWidget);
      expect(find.text('Cycle 3'), findsOneWidget);
    });

    testWidgets('the German wording in de', (tester) async {
      await tester.pumpWidget(_tableHarness(
          evaluations: _evaluations(_twoCycleEntries, _ruleDMarks),
          locale: const Locale('de')));
      await tester.pumpAndSettle();

      for (final label in [
        'Zykluslänge',
        'Mensbeginn',
        'Mensende',
        'Schleimhöhepunkt',
        'SUZ-Beginn',
        'Auswertung',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'de: "$label"');
      }
      expect(find.text('Zyklus 1'), findsOneWidget);
      expect(find.text('Zyklus 2'), findsOneWidget);
      expect(find.text('Zyklus 3'), findsOneWidget);
    });

    testWidgets(
        'cell values: lengths, period start/end, mucus peak, SUZ with rule '
        'D, status', (tester) async {
      await tester.pumpWidget(_tableHarness(
          evaluations: _evaluations(_twoCycleEntries, _ruleDMarks)));
      await tester.pumpAndSettle();

      // Cycle length: days between consecutive marked starts (Mar 1 ->
      // Mar 28 = 27
      // days, Mar 28 -> Apr 20 = 23); the open last cycle shows the dash.
      expect(find.descendant(of: _cell('length', 0), matching: find.text('27 days')),
          findsOneWidget);
      expect(find.descendant(of: _cell('length', 1), matching: find.text('23 days')),
          findsOneWidget);
      expect(find.descendant(of: _cell('length', 2), matching: find.text('—')),
          findsOneWidget);

      // Period start: each marked group's own bleeding onset date.
      expect(find.descendant(of: _cell('start', 0), matching: find.text(yMd(d(3, 1), 'en'))),
          findsOneWidget);
      expect(find.descendant(of: _cell('start', 1), matching: find.text(yMd(d(3, 28), 'en'))),
          findsOneWidget);
      expect(find.descendant(of: _cell('start', 2), matching: find.text(yMd(d(4, 20), 'en'))),
          findsOneWidget);

      // Period end: the LAST menstruation-level (>= 2) bleeding day of the
      // group — the spotting continuation on Mar 4 does not extend cycle 1.
      // The open cycle 3 has its first day itself bleeding, so its period
      // end is the marked start day (only its LENGTH stays undetermined —
      // no next start exists yet).
      expect(find.descendant(of: _cell('end', 0), matching: find.text(yMd(d(3, 3), 'en'))),
          findsOneWidget);
      expect(find.descendant(of: _cell('end', 1), matching: find.text(yMd(d(3, 30), 'en'))),
          findsOneWidget);
      expect(find.descendant(of: _cell('end', 2), matching: find.text(yMd(d(4, 20), 'en'))),
          findsOneWidget);

      // Mucus peak: the user-placed mark of cycle 1; unmarked cycles show
      // the dash.
      expect(find.descendant(of: _cell('peak', 0), matching: find.text(yMd(d(3, 14), 'en'))),
          findsOneWidget);
      expect(find.descendant(of: _cell('peak', 1), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('peak', 2), matching: find.text('—')),
          findsOneWidget);

      // SUZ begin + rule: Mar 17 under rule D (rule-to-time phrasing, "in
      // the evening" for D).
      final suz0 = tester.widget<Text>(find.descendant(
              of: _cell('suz', 0), matching: find.byType(Text)))
          .data!;
      expect(suz0, contains(yMd(d(3, 17), 'en')),
          reason: 'the SUZ cell carries the begin day');
      expect(suz0, contains('rule D'),
          reason: 'the SUZ cell carries the rule (D)');
      expect(find.descendant(of: _cell('suz', 1), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('suz', 2), matching: find.text('—')),
          findsOneWidget);

      // Status: SUZ day + rule once determined, the dash otherwise.
      final status0 = tester.widget<Text>(find.descendant(
              of: _cell('status', 0), matching: find.byType(Text)))
          .data!;
      expect(status0, contains('SUZ from'),
          reason: 'the status names the SUZ begin');
      expect(status0, contains(yMd(d(3, 17), 'en')));
      expect(status0, contains('rule D'));
      expect(find.descendant(of: _cell('status', 1), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('status', 2), matching: find.text('—')),
          findsOneWidget);
    });

    testWidgets(
        'the leading group shows the dash for the bleeding attributes and '
        'its own header', (tester) async {
      await tester.pumpWidget(
          _tableHarness(evaluations: _evaluations(_leadingEntries, _leadingMarks)));
      await tester.pumpAndSettle();

      // Four columns: the leading group plus three marked groups.
      expect(find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('cycleSummaryHeader-')),
          findsNWidgets(4));

      // The leading group's header mirrors the Tagebuch's leading-group
      // label, ending at the group's last day (the begin is unknown).
      expect(find.text('Before the first cycle start (until 2/28/2026)'),
          findsOneWidget);
      expect(find.text('Cycle 1'), findsOneWidget,
          reason: 'the marked groups keep their numbering');

      // The bleeding attributes show the dash in the leading group — it
      // predates the first cycleStart mark, so the bleeding begin/end and
      // the cycle length are unknowable there (the spotting on Feb 26
      // counts neither as a period start nor as a period end).
      expect(find.descendant(of: _cell('length', 0), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('start', 0), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('end', 0), matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: _cell('length', 1), matching: find.text('27 days')),
          findsOneWidget,
          reason: 'the following marked group is unaffected: the length is '
              'counted between its own start (Mar 1) and the next start '
              '(Mar 28), never via the leading group');
      expect(find.descendant(of: _cell('start', 1), matching: find.text(yMd(d(3, 1), 'en'))),
          findsOneWidget);
    });

    testWidgets(
        'the R2 stop renders the localized stopped note in the status row '
        'and keeps the SUZ undetermined', (tester) async {
      await tester.pumpWidget(
          _tableHarness(evaluations: _evaluations(_stoppedEntries, _stoppedMarks)));
      await tester.pumpAndSettle();

      expect(_header(0), findsOneWidget);
      expect(find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('cycleSummaryHeader-')),
          findsNWidgets(1),
          reason: 'exactly one cycle group exists in this scenario');

      expect(find.descendant(of: _cell('suz', 0), matching: find.text('—')),
          findsOneWidget,
          reason: 'a connectedness break leaves the SUZ undetermined');
      expect(find.descendant(of: _cell('status', 0),
              matching: find.textContaining(
                  'The automatic evaluation has stopped')),
          findsOneWidget,
          reason: 'the status shows the localized R2 stopped note');
    });
  });

  group('scroll behavior', () {
    testWidgets('more than ~3 cycles scroll horizontally', (tester) async {
      await tester.pumpWidget(_tableHarness(
        evaluations: _evaluations(_onsetEntries(4), _onsetMarks(4)),
        width: 500,
      ));
      await tester.pumpAndSettle();

      expect(_maxScrollExtent(tester), greaterThan(0),
          reason: '4 columns no longer fit a 500 px viewport: the columns '
              'scroll instead of squeezing the attribute rows');
    });

    testWidgets('~3 cycles fit the viewport without scrolling', (tester) async {
      await tester.pumpWidget(_tableHarness(
        evaluations: _evaluations(_onsetEntries(3), _onsetMarks(3)),
        width: 500,
      ));
      await tester.pumpAndSettle();

      expect(_maxScrollExtent(tester), 0.0,
          reason: '3 columns still fit: nothing to scroll');
    });
  });

  group('on the Zyklus screen', () {
    testWidgets(
        'the table renders below the chart card and above the arithmetic '
        'note, with the seeded values', (tester) async {
      // A taller surface: the chart card plus the table would otherwise
      // overflow the default test viewport (the vertical list builds its
      // children lazily).
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_screenHarness(
        entries: Stream.value(_twoCycleEntries),
        marks: Stream.value(_ruleDMarks),
      ));
      await tester.pumpAndSettle();

      // The table is present with the seeded values.
      expect(_scroll(), findsOneWidget);
      expect(find.descendant(of: _cell('length', 0), matching: find.text('27 days')),
          findsOneWidget);
      expect(find.descendant(of: _cell('peak', 0),
              matching: find.text(yMd(d(3, 14), 'en'))),
          findsOneWidget);
      final suz0 = tester.widget<Text>(find.descendant(
              of: _cell('suz', 0), matching: find.byType(Text)))
          .data!;
      expect(suz0, contains('rule D'));

      // Placement: below the chart card's horizontal scroll block (the
      // chart block's scroller is the other horizontal one on the screen)
      // and above the arithmetic note.
      final chartRect = tester.getRect(find.descendant(
          of: find.byType(ZyklusScreen),
          matching: find.byWidgetPredicate((w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal &&
              w.key != const ValueKey('cycleSummaryScroll'))));
      final tableRect = tester.getRect(_scroll());
      final noteRect =
          tester.getRect(find.textContaining('Evaluation marks:'));
      expect(tableRect.top, greaterThan(chartRect.bottom),
          reason: 'the table sits below the chart card');
      expect(noteRect.top, greaterThan(tableRect.bottom),
          reason: 'the arithmetic note sits below the table');
    });

    testWidgets(
        're-emitting the marks live-updates the table — computed at render '
        'time, nothing persisted (ADR-0001)', (tester) async {
      final marks = StreamController<List<CycleMark>>.broadcast();
      addTearDown(marks.close);
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_screenHarness(
        entries: Stream.value(_twoCycleEntries),
        marks: marks.stream,
      ));
      await tester.pumpAndSettle();

      // No marks yet: the peak cell shows the dash.
      expect(find.descendant(of: _cell('peak', 0), matching: find.text('—')),
          findsOneWidget);

      // Place the marks (re-emit the stream): the table recomputes at
      // render time — no database write is involved (the harness streams
      // are read-only by construction; ADR-0001).
      marks.add(_ruleDMarks);
      await tester.pumpAndSettle();

      expect(find.descendant(of: _cell('peak', 0),
              matching: find.text(yMd(d(3, 14), 'en'))),
          findsOneWidget,
          reason: 'the placed peak renders in the table immediately');
      final status0 = tester.widget<Text>(find.descendant(
              of: _cell('status', 0), matching: find.byType(Text)))
          .data!;
      expect(status0, contains('SUZ from'),
          reason: 'the status follows the marks too');

      // The bleeding attributes (entry-derived, not mark-derived) are
      // untouched by the marks re-emit.
      expect(find.descendant(of: _cell('length', 0), matching: find.text('27 days')),
          findsOneWidget);
    });
  });
}
