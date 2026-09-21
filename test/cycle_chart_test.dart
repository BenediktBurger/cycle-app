// Widget tests of the cycle chart on the Zyklus screen — the whole
// chart family in one file: grid alignment, the Muttermund (cervix)
// row, per-day column labels, the temperature-disturbance letters,
// the computed evaluation marks (mucus-peak/first-higher-based
// candidates, numbering, baseline segment, SUZ), the grid lines (vertical
// day lines plus the 0.1 K horizontal temperature grid over the fixed
// settings range), the symbol help sheet, the frozen left rail, the
// day-note indicator, the per-signal rows, the temperature curve's
// connectivity and ignore rendering (the unit-level curve runs stay
// in cycle_curve_test.dart — those pin the pure rule set, these pin
// how the chart draws it), measurement time / sex / pain glyphs,
// weekend bands, the viewport-limited day window and its rebuild
// pace.
//
// Each section below (kicked off by a `════ former` banner) carries
// the former file's header comments and top-level helpers verbatim;
// test bodies were concatenated, not rewritten. Colliding helper
// names were prefixed per former file (e.g. `_day` →
// `_rowsDay`), and local line/bars/scheme/round-trip helpers that
// were byte-identical to the shared ones in test/support/ now use
// the shared ones.

// No assertion was edited: run the full gate and diff the collected
// test names against the pre-merge report — only the suite-path
// prefix changed.

import 'dart:async';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:cycle_app/ui/cycle_summary.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle chart's grid alignment invariant: day i's
// temperature dot lands exactly at the horizontal CENTER of its day column
// — the same center the day-label row, the signal rows and the evaluation
// marks row use. The chart block's scroll content holds ONLY the day
// columns (the temperature scale and the corner prototypes live in the
// frozen left rail outside the scroll), so column i's cell is centered at
// (i + 0.5) * cellWidth from the content's left edge; the chart's x domain
// is half a column shifted (minX −0.5 .. maxX dayCount − 0.5) so the
// curve's dot for day i meets that same center.
//
// Also pins the degenerate single-day chart: its domain stays a usable
// non-zero-width window (−0.5..0.5) and taps still map to the one recorded
// day.

// 2026-09-03 is a Thursday: a five-day Thu..Mon range fits the viewport.
DateTime _alignmentDay(int index) =>
    DateTime.utc(2026, 9, 3).add(Duration(days: index));

List<DailyEntry> _alignmentEntries(int count) => [
      for (var i = 0; i < count; i++)
        DailyEntry(date: _alignmentDay(i), bbtC: 36.5 + (i % 5) * 0.1),
    ];

/// The rendered global x of day [dayIndex]'s chart dot: the chart maps its
/// x domain linearly onto the plot area, which spans the chart widget's
/// full width — the stripless scroll content starts at the plot's left
/// edge (the frozen rail sits outside).
double _dotX(WidgetTester tester, int dayIndex) {
  final rect = tester.getRect(find.byType(LineChart));
  final data = tester.widget<LineChart>(find.byType(LineChart)).data;
  final t = (dayIndex - data.minX) / (data.maxX - data.minX);
  return rect.left + t * rect.width;
}

double _cellCenterX(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey(key))).center.dx;

Widget _alignmentHarness({required List<DailyEntry> entries}) =>
    chartHarness(entries: entries);

// Widget test of the Muttermund (cervix) display on the Zyklus chart: the
// recorded position renders as a glyph in the cervix row under the
// temperature curve, the firmness glyph renders BESIDE the position glyph
// (one cervix line, two observations), days without an observation stay
// empty. The glyph's
// glossary entry lives in the symbol help sheet (the help-sheet section).

List<DailyEntry> _cervixEntries() => [
      for (var i = 0; i < CervixPosition.values.length; i++)
        DailyEntry(
          date: DateTime.utc(2026, 9, 7 + i),
          bbtC: 36.5 + i * 0.1,
          cervixPosition: CervixPosition.values[i],
          // Opening must NOT be displayed on the chart: it only exists in
          // the entry form.
          cervixOpening: CervixOpening.open,
          // Day 0 additionally records a FIRMNESS, to pin that both cervix
          // observations render side by side in the same line (the 'w' for
          // soft stays letter-distinct from every position glyph).
          cervixFirmness: i == 0 ? CervixFirmness.soft : null,
        ),
      DailyEntry(date: DateTime.utc(2026, 9, 12), bbtC: 37.0),
    ];

Widget _cervixHarness({required List<DailyEntry> entries}) => chartHarness(
    entries: entries, darkTheme: true, scopeInsideMaterialApp: true);

// Widget tests of the cycle tab's per-day column labels: every day column
// shows the day of month ("21.") and the day of cycle (count from the
// cycle start, 1, 2, 3 …); on the FIRST DAY of a calendar month the
// day-of-month label is replaced by the localized short month form
// (day-of-month rule, not a cycle-start rule), and the labels are built
// windowed at their global x positions (same pattern as the signal rows,
// the windowing section below).

// A recorded range starting 2026-01-20 so the day of cycle (1, 2, …) never
// coincides with the day of month (20., 21., …) — the two label lines stay
// distinguishable.
DateTime _dayLabelsDay(int index) =>
    DateTime.utc(2026, 1, 20).add(Duration(days: index));

List<DailyEntry> _dayLabelsEntries(int count,
        {Map<int, Bleeding> bleeding = const {}}) =>
    [
      for (var i = 0; i < count; i++)
        DailyEntry(
            date: _dayLabelsDay(i),
            bbtC: 36.5,
            bleeding: bleeding[i] ?? Bleeding.none),
    ];

// A recorded range starting `start` (unlike _dayLabelsDay above, so month-first
// scenarios can begin on other calendar days).
DateTime _dayFrom(DateTime start, int index) =>
    start.add(Duration(days: index));

List<DailyEntry> _entriesFrom(DateTime start, int count,
        {Map<int, Bleeding> bleeding = const {}}) =>
    [
      for (var i = 0; i < count; i++)
        DailyEntry(
          date: _dayFrom(start, i),
          bbtC: 36.5,
          bleeding: bleeding[i] ?? Bleeding.none,
        ),
    ];

Finder _dayLabel(int index) => find.byKey(ValueKey('dayLabel-$index'));

Finder _label(int index, String text) => find.descendant(
    of: find.byKey(ValueKey('dayLabel-$index')), matching: find.text(text));

Widget _dayLabelsHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, marks: marks, locale: locale);

// Widget tests of the temperature-disturbance letters in the cycle
// chart's below-chart strip: a day carrying one of the NER disturbance
// flags (late to bed, night awakening, alcohol, illness) renders its
// letter code in the disturbance row — in the day's column, keyed like the
// other rows — while plain days render nothing. The letters are the raw
// TempDisturbance tokens of the day's tempDisturbances mask, read
// through a single letter-mapping seam (see the comment on
// disturbanceLetters in lib/ui/cycle.dart). The interrupted curve
// rendering is keyed to the ignoreTemperature MARK, not this mask —
// pinned by the temperature-curve section below.
//

DateTime _disturbanceDay(int index) => DateTime.utc(2026, 9, 7 + index);

// Six chart days:
//  0: plain temperature, no disturbance flag   -> nothing in the row
//  1: illness (kr bit)                         -> kr
//  2: alcohol (alk bit)                        -> alk
//  3: late to bed (sp bit)                     -> sp
//  4: night awakening (a bit)                  -> a
//  5: all four flags together                  -> kr, alk, sp, a stacked
final _disturbanceEntries = <DailyEntry>[
  DailyEntry(date: _disturbanceDay(0), bbtC: 36.5),
  DailyEntry(
      date: _disturbanceDay(1),
      bbtC: 36.6,
      tempDisturbances: TempDisturbance.kr.bit),
  DailyEntry(
      date: _disturbanceDay(2),
      bbtC: 36.7,
      tempDisturbances: TempDisturbance.alk.bit),
  DailyEntry(
      date: _disturbanceDay(3),
      bbtC: 36.4,
      tempDisturbances: TempDisturbance.sp.bit),
  DailyEntry(
      date: _disturbanceDay(4),
      bbtC: 36.5,
      tempDisturbances: TempDisturbance.a.bit),
  DailyEntry(
    date: _disturbanceDay(5),
    bbtC: 36.8,
    tempDisturbances: TempDisturbance.values.fold(0, (mask, d) => mask | d.bit),
  ),
];

Widget _disturbanceHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

// Widget tests of the computed evaluation marks on the cycle chart (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks; the UI
// derives and renders the candidate circles/arrows (kind decided PER
// CANDIDATE: arrows at or before the peak day, circles strictly after — R4),
// the solid peak dot in the mucus row, the 1–6 low numbering and the
// baseline SEGMENT (low #6 to the last marked candidate — R10). Derived
// artifacts are computed at render time only — these tests pin how the
// artifacts of lib/domain/evaluation.dart surface on the chart.
//

// 2026-09-03 is a Thursday, so this sequence runs Sun (9/6) .. Wed (9/16).
// Day indexes: 9/6 -> 0 ... 9/16 -> 10. (The shared scenario copy lives in
// support/fixtures.dart; these constants name the days for the assertions.)
final _sun6 = DateTime.utc(2026, 9, 6);
final _sat12 = DateTime.utc(2026, 9, 12);
final _sun13 = DateTime.utc(2026, 9, 13);
final _mon14 = DateTime.utc(2026, 9, 14);
final _tue15 = DateTime.utc(2026, 9, 15);
final _wed16 = DateTime.utc(2026, 9, 16);
final _thu17 = DateTime.utc(2026, 9, 17);
final _fri18 = DateTime.utc(2026, 9, 18);

/// Main evaluation scenario (peak before the rise -> CIRCLES) — the
/// shared fixture in support/fixtures.dart; see the per-day role comments
/// there.
final _evaluationEntries = evaluationScenarioEntries();

final _marks = evaluationScenarioMarks();

Widget _harness(
        {required List<DailyEntry> entries, required List<CycleMark> marks}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ProviderScope(
        overrides: [
          dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          marksProvider.overrideWith((ref) => Stream.value(marks)),
          selectedDateProvider.overrideWith((ref) => entries.first.date),
        ],
        child: const Scaffold(body: ZyklusScreen()),
      ),
    );

/// The baseline segment bars (R10): the dashed two-spot bars drawn in the
/// baseline color (secondary) — one per evaluated cycle with a marked
/// candidate. Horizontal by construction, so the vertical SUZ bars (same
/// secondary color) are excluded here.
List<LineChartBarData> _baselineBars(WidgetTester tester) => chartData(tester)
    .lineBarsData
    .where((bar) =>
        bar.color == chartScheme(tester).secondary &&
        bar.spots.first.y == bar.spots.last.y)
    .toList();

/// The SUZ bars: vertical two-spot bars in the secondary color (one per
/// user-placed SUZ mark) — the same evaluation-family color as the baseline
/// segment, distinguished by orientation.
List<LineChartBarData> _suzBars(WidgetTester tester) => chartData(tester)
    .lineBarsData
    .where((bar) =>
        bar.color == chartScheme(tester).secondary &&
        bar.spots.first.x == bar.spots.last.x)
    .toList();

/// The SUZ arrow: the spot + painter of the SUZ arrow glyph, or null when
/// no user SUZ mark renders an arrow.
(FlSpot, FlDotPainter)? _suzArrowSpot(WidgetTester tester) {
  for (final bar in dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final painter = bar.dotData.getDotPainter(bar.spots[i], 0, bar, i);
      if (painter is SuzArrowDotPainter) return (bar.spots[i], painter);
    }
  }
  return null;
}

/// The dot painter the chart would use for the temperature dot of [dayIndex]
/// (fails when that day has no temperature point on the chart).
FlDotPainter _dotPainter(WidgetTester tester, int dayIndex) {
  for (final bar in dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final spot = bar.spots[i];
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, i);
      }
    }
  }
  fail('no temperature dot at day index $dayIndex');
}

/// The number shown in the marks row under [dayIndex], or null when none.
String? _numberUnder(WidgetTester tester, int dayIndex) {
  final texts = tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey('marksCell-$dayIndex')),
        matching: find.byType(Text),
      ))
      .toList();
  return texts.isEmpty ? null : texts.single.data;
}

/// The peak-dot slot inside the symbol-row cell of [dayIndex].
Finder _peakDot(int dayIndex) => find.byKey(ValueKey('peakDot-$dayIndex'));

/// Identity helper: true when [entry]'s date is exactly [day]'s calendar day
/// (used to patch the scenario above).
bool _sameDay(DailyEntry entry, DateTime day) =>
    entry.date.year == day.year &&
    entry.date.month == day.month &&
    entry.date.day == day.day;

// Widget tests of the cycle chart card's vertical lines: the chart draws
// hairline vertical day lines (the paper's day columns), every row cell of
// the card carries a matching hairline right border, and every cycle start
// draws a THICK solid line through the whole card — as the chart's extra
// line at x = nextCycleStart − 0.5 and as a thick right border on the cell
// before the new cycle's first day in every row. The boundary predicate is
// derived once from the domain's mark-driven cycle grouping (lib/domain/
// cycle_grouping.dart): no line before the first cycleStart mark (the
// leading group), and a boundary is drawn even across untracked gap days.
//

// 2026-09-07 is a Monday: a 12-day run Mon .. Fri (next week).
DateTime _gridLineDay(int index) => DateTime.utc(2026, 9, 7 + index);

/// One cycle group per cycleStart mark: marks at day indexes 5 and 9,
/// none before the first — the leading group (indexes 0..4) predates the
/// first mark. The bleeding values keep the PAPER row populated; the
/// boundaries themselves come from the marks.
final _twoCycleEntries = <DailyEntry>[
  for (var i = 0; i < 12; i++)
    DailyEntry(
        date: _gridLineDay(i),
        bbtC: 36.5,
        bleeding: i == 5 || i == 9 ? Bleeding.heavy : Bleeding.none),
];

/// The cycleStart marks of the two-cycle scenario (at the marked days 5
/// and 9 — the same days that used to be bleeding onsets).
final _twoCycleMarks = <CycleMark>[
  CycleMark(date: _gridLineDay(5), type: CycleMarkTypes.cycleStart),
  CycleMark(date: _gridLineDay(9), type: CycleMarkTypes.cycleStart),
];

/// A gap scenario: day 0 tracked, days 1..4 untracked, a cycleStart mark
/// on an untracked gap day (say day 3) — the next tracked day 5 opens the
/// new cycle, and the boundary is drawn across the untracked gap days.
final _gapEntries = <DailyEntry>[
  DailyEntry(date: _gridLineDay(0), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: _gridLineDay(5), bbtC: 36.5, bleeding: Bleeding.heavy),
];

final _gapMarks = <CycleMark>[
  CycleMark(date: _gridLineDay(3), type: CycleMarkTypes.cycleStart),
];

/// The card-row border container inside the cell of [index]/[row]: the
/// cell's decoration border is a non-uniform Border (right side only),
/// unlike every glyph's own decoration (uniform Border.all or none).
Border _cellRightBorder(WidgetTester tester, int index, String row) {
  final containers = tester.widgetList<Container>(find.descendant(
      of: chartCell(index, row), matching: find.byType(Container)));
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<Border>()
      .firstWhere((b) => !b.isUniform,
          orElse: () => fail('no cell border found in cell $index of $row'));
}

Widget _gridLinesHarness(
        {required List<DailyEntry> entries,
        List<CycleMark> marks = const []}) =>
    chartHarness(entries: entries, marks: marks);

// Widget tests of the cycle tab's symbol glossary (help sheet): the
// legend left the screen — the Zyklus AppBar carries an info_outline
// action whose long-press-friendly tooltip opens a bottom sheet with the
// full symbol glossary (every entry the on-screen legend carried) plus
// the evaluation-arithmetic note. Localized in en and de.
//

List<DailyEntry> _helpSheetEntries(int count) => [
      for (var i = 0; i < count; i++)
        DailyEntry(date: DateTime.utc(2026, 9, 7 + i), bbtC: 36.5),
    ];

/// The glossary entries (en wording); each is asserted inside the help
/// sheet. The "Ignored temperature" entry presents the VISUAL consequence
/// (the lighter temperature on the curve — the mark is the rendering key,
/// owner decision 2026-09-19) while naming where the mark is set.
const _glossaryEn = [
  'BBT (temperature)',
  'Bleeding',
  'Fertility sign (mucus)',
  'Mucus peak',
  'Ignored temperature (lighter; set in the day sheet)',
  'Circled higher measurements',
  'Premature temperature rise',
  'Baseline',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Cervix position',
  'Cervix firmness',
  'Measurement time',
  'Sex (X per time of day)',
  'Mittelschmerz (M)',
  'Breast pain (B)',
  'Interrupted days (sp late to bed, a frequent night awakening, '
      'alk alcohol, kr illness)',
  'Note (this day carries a note in the Diary)',
];

const _glossaryDe = [
  'BBT (Temperatur)',
  'Blutung',
  'Zeichen der Fruchtbarkeit (Schleim)',
  'Schleimhöhepunkt',
  'Temperatur ignoriert (heller gezeichnet; im Tagesblatt gesetzt)',
  'Umrandete höhere Messungen',
  'vorzeitiger Temperaturanstieg',
  'Basislinie',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Muttermund-Position',
  'Muttermund-Festigkeit',
  'Messzeitpunkt',
  'Sex (X je Zeitpunkt)',
  'Mittelschmerz (M)',
  'Brustschmerz (B)',
  'Gestörte Messung (sp Spät ins Bett, a Nachts öfter aufstehen, '
      'alk Alkohol, kr Krank)',
  'Notiz (für diesen Tag ist eine Notiz im Tagebuch vorhanden)',
];

const _arithmeticNoteEn =
    'Evaluation marks: you place the mucus peak and the first higher '
    'measurement; numbering, baseline and circles are computed for display '
    'only — no fertility statement.';

const _arithmeticNoteDe =
    'Auswertungsmarkierungen: Schleimhöhepunkt und erste höhere Messung '
    'setzt du selbst; Nummerierung, Basislinie und Umrandungen werden nur '
    'für die Anzeige berechnet — keine Fruchtbarkeitsangabe.';

Widget _helpSheetHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale, withScaffold: false);

/// The glossary [finder]'s matches that do NOT sit inside the evaluation
/// table: the table legitimately renders its own localized row labels (its
/// "Mucus peak" row is a table attribute, not a glossary entry), so the
/// glossary-absence check filters those matches out.
Iterable<Element> outsideTable(Finder finder) =>
    finder.evaluate().where((element) {
      var insideTable = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is CycleSummaryTable) insideTable = true;
        return !insideTable;
      });
      return !insideTable;
    });

// Widget tests of the cycle chart's frozen left rail: the paper sheet's
// fixed left margin lives OUTSIDE the horizontal scroll, so it stays
// readable while the day columns slide — the owner-reported defect was the
// temperature scale vanishing once the window scrolled to recent days.
// The rail carries three things, all moved out of the scrolling content's
// leading strips:
//  1. the header corner prototypes ("14." date column / "#5" cycle-day
//     column) with their tooltips/semantics,
//  2. the temperature scale: fl_chart's left titles are DISABLED and the
//     rail paints the scale labels itself, using the exact same linear
//     value→pixel mapping as the plot (shared from the chart's min/max and
//     plot height — one source of truth), with the 0.5 °C interval and the
//     two-scale numbering (plain integers, halves with one decimal),
//  3. the per-signal-row corner sample glyphs (bleeding blob, S,
//     Mittelschmerz M, X, cervix letter, B, clock), each vertically
//     aligned with its signal row's fixed-height slot; the rows' segments
//     mirror the scroll content: the top-of-block rows (bleeding, mucus,
//     M, sex) stack between the header prototypes and the temperature
//     scale, and the below-chart strip's rows (time, disturbance, cervix,
//     pain, note) form ONE segment below the marks slot.
// The long-range frozen-content test mirrors the windowing section.

// Nine chart days covering one recorded fact per signal (the per-signal rows fixture of the rows
// section):
// temperatures 36.4..37.0 — with the default settings range 36..38 °C every
// half-degree tick between the fixed bounds exists. Unlike the rows
// fixture, day 4 carries NO Mittelschmerz.
DateTime _leftRailDay(int index) => DateTime.utc(2026, 9, 7 + index);

final _leftRailEntries =
    nineDayRowsFixture(day: _leftRailDay, withMittelschmerz: false);

// 5 uniform days at 36.5: the scale is a compact two-tick-plus interval.
List<DailyEntry> _flatEntries() => [
      for (var i = 0; i < 5; i++) DailyEntry(date: _leftRailDay(i), bbtC: 36.5),
    ];

Finder _rail() => find.byKey(const ValueKey('leftRail'));

/// The rail's temperature-scale label texts, in top-down (descending
/// value) order.
List<String> _scaleLabels(WidgetTester tester) {
  final labelFinder = find.descendant(
      of: _rail(),
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('railScaleLabel-')));
  final entries = [
    for (final widget in tester.widgetList<Text>(labelFinder))
      (rect: tester.getRect(find.byWidget(widget)), text: widget.data!),
  ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  return [for (final e in entries) e.text];
}

Widget _leftRailHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
  TemperatureRange? range,
}) =>
    chartHarness(entries: entries, locale: locale, temperatureRange: range);

// Widget tests of the day-note indicator on the cycle chart: a day whose
// entry carries a non-empty notes text shows a small indicator glyph in
// its day column in the row BELOW the chart block — the LAST row of the
// below-chart strip (per the paper sheet, whose remarks block sits at the
// very bottom under the Uhrzeit strip — placement flagged
// TODO(user-review) in the chart code). Days with an
// empty/absent notes field render nothing. Tapping the indicator cell
// opens the day's mark-entry sheet like every other cell.
//

DateTime _noteDay(int index) => DateTime.utc(2026, 9, 7 + index);

// Four chart days:
//  0: plain temperature, no notes                 -> no indicator
//  1: temperature WITH a note                     -> indicator
//  2: notes = empty string                        -> no indicator
//  3: temperature WITHOUT a recorded note field   -> no indicator
final _noteEntries = <DailyEntry>[
  DailyEntry(date: _noteDay(0), bbtC: 36.5),
  DailyEntry(date: _noteDay(1), bbtC: 36.6, notes: 'Impfung heute'),
  DailyEntry(date: _noteDay(2), bbtC: 36.7, notes: ''),
  DailyEntry(date: _noteDay(3), bbtC: 36.4),
];

Widget _noteHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

// Widget tests of the per-signal rows under the cycle chart (the paper's
// recording rows): one always-rendered row per signal — bleeding, mucus
// (with the reserved solid peak-dot slot above the glyph), measurement
// time, cervix, pain. The rows hold ONLY day cells — their sample
// glyphs and localized row names live in the frozen left rail (see
// the left-rail section), keyed `${row}Corner` there. The
// measurement time renders as localized HH:mm text ONLY when the day
// column is wide enough; no per-day clock icon exists anywhere in the
// rows. Tapping a row cell opens the day's mark-entry sheet.
//

DateTime _rowsDay(int index) => DateTime.utc(2026, 9, 7 + index);

// Nine chart days covering one recorded fact per signal — the shared
// per-signal rows fixture from support/fixtures.dart (day 4 WITH the
// Mittelschmerz flag).
final _rowsEntries = nineDayRowsFixture(day: _rowsDay, withMittelschmerz: true);

const _dayCount = 9;

// The chart block's recording rows, top-down in render order: the top
// block inside the temperature grid (bleeding, mucus, Mittelschmerz M,
// sex), then the single below-chart strip in the owner-decided order —
// measurement time first, the disturbance letters, cervix, pain, and at
// the very bottom (the paper sheet's remarks home) the note indicator.
const _signalRows = [
  'bleeding',
  'mucus',
  'mittelschmerz',
  'sex',
  'time',
  'disturbance',
  'cervix',
  'pain',
  'note',
];

/// The bleeding blob (the circle Container) inside the bleeding cell of
/// [index].
Container _bleedingBlob(WidgetTester tester, int index) => tester
    .widgetList<Container>(find.descendant(
        of: chartCell(index, 'bleeding'), matching: find.byType(Container)))
    .firstWhere((container) =>
        (container.decoration! as BoxDecoration).shape == BoxShape.circle);

Widget _rowsHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

// Widget tests of the temperature curve's connectivity and interruption
// rendering: the line connects two temperatures ONLY when their calendar
// days are adjacent; ignored temperatures (a day carrying the
// ignoreTemperature MARK — the rendering is keyed to the mark, NOT to the
// raw disturbance mask, owner decision 2026-09-19) count as measured
// days, keep the line continuous, but render lighter (dot AND touching
// segments). The
// mark makes the state visible on the graph: a marked day without flags
// renders lighter, and a flagged day whose mark was removed renders
// normally again. Widget-level sibling: the weekend-band tests share the harness shape
// (scope inside MaterialApp, dark scheme).

// 2026-09-03 is a Thursday: Thu..Sun as a compact adjacent-day strip.
final _temperatureThu = DateTime.utc(2026, 9, 3);
final _temperatureFri = DateTime.utc(2026, 9, 4);
final _temperatureSat = DateTime.utc(2026, 9, 5);
final _temperatureSun = DateTime.utc(2026, 9, 6);

List<LineChartBarData> _bars(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData;

/// The line bars the chart draws its polyline with, one entry per run of
/// adjacent days (dot-only bars, whose line is invisible, are ignored).
List<LineChartBarData> _segmentBars(WidgetTester tester) => [
      for (final bar in _bars(tester))
        if (bar.color != null && bar.color!.a > 0) bar,
    ];

/// True when some visible polyline bar connects exactly the two day indexes.
bool _connects(WidgetTester tester, int a, int b) =>
    _segmentBars(tester).any((bar) =>
        bar.spots.length == 2 &&
        bar.spots[0].x == a.toDouble() &&
        bar.spots[1].x == b.toDouble());

/// True when any visible polyline bar holds spots whose day indexes are NOT
/// adjacent — i.e. the (single-path) bar paints across a day gap.
bool _spansAGap(WidgetTester tester) => _segmentBars(tester).any((bar) {
      final xs = bar.spots.map((s) => s.x.round()).toList()..sort();
      for (var i = 1; i < xs.length; i++) {
        if (xs[i] != xs[i - 1] + 1) return true;
      }
      return false;
    });

ThemeData _themeOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

Widget _temperatureHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  TemperatureRange? range,
}) =>
    chartHarness(
      entries: entries,
      marks: marks,
      darkTheme: true,
      scopeInsideMaterialApp: true,
      temperatureRange: range,
    );

// Widget tests of the cycle tab's recorded-fact glyphs in the per-signal
// rows under the temperature curve: the measurement time renders as
// localized HH:mm text in its OWN row BELOW the chart block (the first
// row of the below-chart strip) — rotated
// vertically when the day column is narrower than the text (never dropped,
// the old space-constraint bug), horizontal in wide columns (the old
// per-day clock glyph is gone — the clock lives only in the row corner),
// the sex time slots (one X glyph per SET SexTiming bit, drawn at
// that slot's third of the day column — multiple bits render multiple X
// marks), and the letter-coded pain flags B (breast, in the pain row) and
// M (Mittelschmerz, in its own row beneath the mucus row). Days without
// the respective fact render nothing.

DateTime _timeSexPainDay(int index) => DateTime.utc(2026, 9, 7 + index);

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
List<DailyEntry> _timeSexPainEntries() => [
      DailyEntry(
        date: _timeSexPainDay(0),
        bbtC: 36.5,
        measuredAtMinutes: 6 * 60 + 30,
      ),
      DailyEntry(date: _timeSexPainDay(1), bbtC: 36.4),
      DailyEntry(date: _timeSexPainDay(2), sexTimings: SexTiming.start.bit),
      DailyEntry(date: _timeSexPainDay(3), painBreast: true),
      DailyEntry(date: _timeSexPainDay(4), painMittelschmerz: true),
      DailyEntry(
        date: _timeSexPainDay(5),
        sexTimings: SexTiming.start.bit | SexTiming.end.bit,
        painBreast: true,
        painMittelschmerz: true,
      ),
      DailyEntry(date: _timeSexPainDay(6), bbtC: 36.6),
      DailyEntry(
        date: _timeSexPainDay(7),
        cervixFirmness: CervixFirmness.soft,
      ),
    ];

Widget _timeSexPainHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    chartHarness(entries: entries, locale: locale);

// Widget test of the cycle chart's weekend highlighting: weekend days
// (Saturday/Sunday, derived from the real calendar dates) get a subtle
// background band behind their chart column, weekdays get none. The band
// color is theme-derived so it stays readable in light AND dark mode.

// 2026-09-03 is a Thursday: Thu, Fri, Sat, Sun, Mon — a run that starts and
// ends on a weekday with the weekend in the middle (indexes 2 and 3).
final _weekendThu = DateTime.utc(2026, 9, 3);
final _weekendFri = DateTime.utc(2026, 9, 4);
final _weekendSat = DateTime.utc(2026, 9, 5);
final _weekendSun = DateTime.utc(2026, 9, 6);
final _weekendMon = DateTime.utc(2026, 9, 7);

final _weekendEntries = <DailyEntry>[
  DailyEntry(date: _weekendThu, bbtC: 36.5),
  DailyEntry(date: _weekendFri, bbtC: 36.6),
  DailyEntry(date: _weekendSat, bbtC: 36.7),
  DailyEntry(date: _weekendSun, bbtC: 36.8),
  DailyEntry(date: _weekendMon, bbtC: 36.6),
];

/// The weekend background bands currently configured on the chart, in
/// ascending x order.
List<VerticalRangeAnnotation> _weekendBands(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .rangeAnnotations
    .verticalRangeAnnotations;

/// The band color, asserted non-null before use (the chart is configured
/// with an explicit color, never a gradient).
Color _bandColor(VerticalRangeAnnotation band) {
  final color = band.color;
  expect(color, isNotNull,
      reason: 'bands are configured by color, not gradient');
  return color!;
}

Widget _weekendHarness({List<DailyEntry>? entries, DateTime? selected}) =>
    // Same seed scheme wiring as CycleApp (lib/main.dart) so the dark
    // tests below exercise the dark scheme, not a themeless MaterialApp.
    chartHarness(
      entries: entries ?? _weekendEntries,
      selectedDate: selected ?? _weekendThu,
      darkTheme: true,
      scopeInsideMaterialApp: true,
    );

// Widget tests of the cycle tab's viewport-limited day window: for long
// recorded ranges only the days that fit usefully on screen are rendered
// (the window PARKS with an extra screen-width of margin past the visible
// edges and is only rebuilt when the visible edge runs into that margin),
// the whole chart block scrolls horizontally (curve + signal + numbering
// rows together), the FIRST data frame auto-scrolls so the MOST RECENT days
// fill the viewport, a later entries re-emit never re-jumps (the user's
// scrolled position survives), and a jump-to-date affordance moves the
// window onto a picked calendar day. Tapping a day inside the scrolled
// window keeps opening the day's mark-entry sheet.
//

// A many-day range: 2026-01-01 .. 2026-05-30 (150 days, indexes 0..149) —
// long enough that the scroll window and its margin sit strictly inside
// the recorded range, so windowing and margin semantics stay distinguishable.
List<DailyEntry> _manyEntries() => longRangeEntries(150);

List<DailyEntry> _shortEntries() => [
      for (var i = 0; i < 5; i++) DailyEntry(date: longRangeDay(i), bbtC: 36.5),
    ];

Finder _bleedingCell(int index) => find.byKey(ValueKey('bleedingCell-$index'));
Finder _marksCell(int index) => find.byKey(ValueKey('marksCell-$index'));

// The chart's day-column geometry at the test viewport (800 wide, 12 body
// padding on each side): a 60-day range overflows, so columns render at the
// minimum usable width and the content exceeds the viewport.
const _columnWidth = 24.0;

/// The finder for the horizontal scroll view that carries the chart block.
/// The evaluation table below the chart block has its own horizontal
/// scroller (key `cycleSummaryScroll`) — it is not the chart block, so it
/// is excluded by that key here.
Widget _windowingHarness({
  required List<DailyEntry> entries,
  Stream<List<DailyEntry>>? entriesStream,
}) =>
    chartHarness(entries: entries, entriesStream: entriesStream);

// A regression test for the chart's window-rebuild pace: the built day
// window parks with an extra screen-width of margin past the visible
// edges and is only rebuilt when the visible edge would run into that
// margin. Scrolling a long distance must therefore re-window only a
// handful of times — not once per day column. The scroll listener fires
// every scroll tick, but only a window-bound change rebuilds the chart
// block, so the count of rendered-window transitions IS the rebuild
// count the scroll path causes.
//

// A many-day recorded range (2026-01-01 onwards, 600 days; the shared
// long-range fixture with a longer count).
List<DailyEntry> _windowRebuildEntries() => longRangeEntries(600);

/// The day indexes whose signal cells are currently built.
Set<int> _builtCells(WidgetTester tester) {
  const prefix = 'bleedingCell-';
  final indexes = <int>{};
  for (final widget in tester.widgetList(find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith(prefix)))) {
    final suffix =
        (widget.key! as ValueKey<String>).value.substring(prefix.length);
    indexes.add(int.parse(suffix));
  }
  return indexes;
}

void main() {
// ═══════════ alignment ═══════════
// former test/cycle_chart_alignment_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'day i\'s chart dot lands at the center of its label, marks and '
      'symbol cell', (tester) async {
    await tester.pumpWidget(_alignmentHarness(entries: _alignmentEntries(5)));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      final dotX = _dotX(tester, i);
      expect(dotX, closeTo(_cellCenterX(tester, 'bleedingCell-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the bleeding row\'s '
              'cell horizontal center');
      expect(dotX, closeTo(_cellCenterX(tester, 'mucusCell-$i'), 0.5),
          reason: 'day $i: the top-of-block mucus row keeps the shared '
              'column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'mittelschmerzCell-$i'), 0.5),
          reason: 'day $i: the Mittelschmerz row under the mucus row keeps '
              'the shared column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'sexCell-$i'), 0.5),
          reason: 'day $i: the top-of-block sex row keeps the shared '
              'column center');
      expect(dotX, closeTo(_cellCenterX(tester, 'dayLabel-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the day label cell\'s '
              'horizontal center');
      expect(dotX, closeTo(_cellCenterX(tester, 'marksCell-$i'), 0.5),
          reason: 'day $i: the chart dot must sit at the marks cell\'s '
              'horizontal center');
      // The below-chart strip's rows keep the shared center too (their
      // windowed cells sit at the same global column positions).
      for (final row in ['time', 'disturbance', 'cervix', 'pain', 'note']) {
        expect(dotX, closeTo(_cellCenterX(tester, '${row}Cell-$i'), 0.5),
            reason: 'day $i: the below-chart strip\'s $row row keeps the '
                'shared column center');
      }
    }
  });

  testWidgets(
      'a single recorded day keeps a usable domain and maps taps to '
      'that day', (tester) async {
    await tester.pumpWidget(_alignmentHarness(entries: _alignmentEntries(1)));
    await tester.pumpAndSettle();

    // The lone day's dot sits at its column center — the domain is kept at
    // −0.5..0.5 (one full column wide) instead of collapsing.
    expect(
        _dotX(tester, 0), closeTo(_cellCenterX(tester, 'bleedingCell-0'), 0.5),
        reason: 'the single day\'s column center matches its dot');

    // Tapping the plot area opens the one recorded day's sheet.
    final rect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'a tap on the single-day chart opens the day sheet');
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _alignmentDay(0),
        reason: 'the single recorded day owns the whole plot');
  });

// ═══════════ cervix ═══════════
// former test/cycle_chart_cervix_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets('every recorded position renders one glyph under the curve',
      (tester) async {
    await tester.pumpWidget(_cervixHarness(entries: _cervixEntries()));
    await tester.pumpAndSettle();

    // One glyph per position category, checked inside its own cervix cell
    // (ValueKey convention 'cervixCell-$i'): low..unreachable days 0..4, day
    // 5 carries NO Muttermund observation and must render no glyph. The
    // scoping matters: the legend shows a sample glyph too.
    final glyphOf = {
      0: 't', // low (tief)
      1: 'm', // medium
      2: 'h', // high
      3: 'sh', // very high
      4: 'u', // unreachable
    };
    for (final MapEntry(:key, :value) in glyphOf.entries) {
      expect(
        find.descendant(
            of: find.byKey(ValueKey('cervixCell-$key')),
            matching: find.text(value)),
        findsOneWidget,
        reason: 'position category index $key renders its glyph under the '
            'curve inside its own cell',
      );
    }
    // Negative assertion against ALL five glyph letters (not a vacuous
    // find.text('') match): day 5 has no cervix observation, so none of
    // them may appear inside its cervix cell.
    for (final glyph in glyphOf.values) {
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('cervixCell-5')),
            matching: find.text(glyph)),
        findsNothing,
        reason: 'no "$glyph" glyph for a day without an observation',
      );
    }
  });

  testWidgets('the firmness glyph renders beside the position glyph',
      (tester) async {
    await tester.pumpWidget(_cervixHarness(entries: _cervixEntries()));
    await tester.pumpAndSettle();

    // Day 0 additionally carries the firmness observation: its glyph
    // renders BESIDE the position letter in the same cervix line ('w' for
    // soft, distinct from every position letter).
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('cervixCell-0')),
          matching: find.text('w')),
      findsOneWidget,
      reason: 'the firmness glyph renders beside the position glyph in the '
          'same cervix line',
    );
  });

// ═══════════ day labels ═══════════
// former test/cycle_chart_day_labels_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('per-day column labels', () {
    testWidgets(
        'every day column shows day of month and day of cycle; a '
        'cycle start that is not a month first stays a plain number',
        (tester) async {
      // 5 recorded days, no bleeding onset anywhere: one leading cycle
      // group starting on 2026-01-20.
      await tester.pumpWidget(_dayLabelsHarness(entries: _dayLabelsEntries(5)));
      await tester.pumpAndSettle();

      // Column 0 starts the (leading) cycle group on 2026-01-20 — but the
      // month form follows the CALENDAR (day-of-month == 1), not the cycle,
      // so it shows its plain day number; the cycle start is only visible
      // in line 2 counting from 1.
      expect(_label(0, '20.'), findsOneWidget,
          reason: 'the non-month-first cycle start shows a plain day number');
      expect(_label(0, 'Jan'), findsNothing,
          reason: 'no month form on a cycle start that is not a month first');
      expect(_label(0, '1'), findsOneWidget,
          reason: 'day of cycle 1 on the cycle start');
      for (var i = 1; i < 5; i++) {
        expect(_label(i, '${20 + i}.'), findsOneWidget,
            reason: 'day column $i shows its day of month');
        expect(_label(i, '${i + 1}'), findsOneWidget,
            reason: 'day column $i shows its day of cycle (counted from the '
                'cycle start on 2026-01-20)');
      }

      // The label row replaces the old sparse bottom axis titles: no
      // duplicated day-of-month strip anywhere else in the chart.
      expect(find.text('21.'), findsOneWidget);
    });

    testWidgets(
        'the first day of a calendar month shows the localized '
        'short month form instead of the plain day number', (tester) async {
      // 2026-01-29 .. 2026-02-02: day index 3 is February 1st.
      await tester.pumpWidget(_dayLabelsHarness(
          entries: _entriesFrom(DateTime.utc(2026, 1, 29), 5)));
      await tester.pumpAndSettle();

      expect(_label(2, '31.'), findsOneWidget,
          reason: 'ordinary days keep the plain day number');
      expect(_label(3, 'Feb'), findsOneWidget,
          reason: 'February 1st renders the short month form');
      expect(_label(3, '1.'), findsNothing,
          reason: 'the "1." day number is replaced by the short month');
      // Day of cycle line 2 is unchanged: it keeps counting through the
      // month boundary (leading group started 2026-01-29).
      expect(_label(3, '4'), findsOneWidget);
      expect(_label(4, '2.'), findsOneWidget);
    });

    testWidgets('the German short month form is used in the de locale',
        (tester) async {
      // 2025-12-29 .. 2026-01-02: day index 3 is January 1st.
      await tester.pumpWidget(_dayLabelsHarness(
          entries: _entriesFrom(DateTime.utc(2025, 12, 29), 5),
          locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(_label(3, 'Jan.'), findsOneWidget,
          reason: 'the German month abbreviation keeps its trailing period');
      expect(_label(3, 'Jan '), findsNothing,
          reason: 'no en-style "1 Jan"-like composite may leak in');
      expect(_label(4, '2.'), findsOneWidget,
          reason: 'ordinary days show the plain day number');
      expect(_label(3, '4'), findsOneWidget,
          reason: 'day of cycle continues through the month boundary '
              '(leading group started 2025-12-29)');
    });

    testWidgets(
        'a month first that is also a cycle start shows the short '
        'month form, not the day number', (tester) async {
      // The recorded range BEGINS on 2026-02-01 (the leading group's
      // start, no cycleStart mark involved): the first of the month shows
      // the month form, and the leading group's day-of-cycle count also
      // starts at 1 there.
      await tester.pumpWidget(_dayLabelsHarness(
          entries: _entriesFrom(DateTime.utc(2026, 2, 1), 3,
              bleeding: {0: Bleeding.heavy})));
      await tester.pumpAndSettle();

      expect(_label(0, 'Feb'), findsOneWidget,
          reason: 'February 1st is a month first AND the range\'s first '
              'day — the month form shows');
      expect(_label(0, '1.'), findsNothing);
      expect(_label(0, '1'), findsOneWidget,
          reason: 'day of cycle 1 on the cycle start');
      expect(_label(1, '2.'), findsOneWidget);
      expect(_label(1, '2'), findsOneWidget);
    });

    testWidgets(
        'a new cycle starts mid-month with a plain day number and '
        'restarts the day-of-cycle count', (tester) async {
      // 40 days (2026-01-20 .. 2026-02-28); a cycleStart mark on day index
      // 35 (2026-02-24) opens the second cycle there — mid-month, hence a
      // plain day number despite the cycle start.
      final marks = [
        CycleMark(date: _dayLabelsDay(35), type: CycleMarkTypes.cycleStart),
      ];
      await tester.pumpWidget(
          _dayLabelsHarness(entries: _dayLabelsEntries(40), marks: marks));
      await tester.pumpAndSettle();

      // The initial auto-scroll puts the window at the newest days: the 40
      // narrow columns overflow the viewport, so the end of the recorded
      // range — the window around indexes 34–36 — is on screen right away.

      // End of the first cycle: day of cycle 35 on 2026-02-23.
      expect(_label(34, '23.'), findsOneWidget);
      expect(_label(34, '35'), findsOneWidget);

      // Second cycle: the onset day shows a PLAIN day number (month form
      // is only for month firsts) and counts 1.
      expect(_label(35, '24.'), findsOneWidget,
          reason: 'a mid-month cycle start is not a month first');
      expect(_label(35, 'Feb 24'), findsNothing);
      expect(_label(35, '1'), findsOneWidget);
      expect(_label(36, '25.'), findsOneWidget);
      expect(_label(36, '2'), findsOneWidget);
    });

    testWidgets('untracked gap days keep counting from the last cycle start',
        (tester) async {
      // Only day 0 (bleeding onset) and day 5 carry entries; days 1–4 are
      // untracked calendar gaps that still belong to the running cycle.
      final entries = [
        DailyEntry(
            date: _dayLabelsDay(0), bbtC: 36.5, bleeding: Bleeding.heavy),
        DailyEntry(date: _dayLabelsDay(5), bbtC: 36.5),
      ];
      await tester.pumpWidget(_dayLabelsHarness(entries: entries));
      await tester.pumpAndSettle();

      for (var i = 1; i < 5; i++) {
        expect(_label(i, '${20 + i}.'), findsOneWidget,
            reason: 'the untracked gap day $i still shows its day of month');
        expect(_label(i, '${i + 1}'), findsOneWidget,
            reason: 'the gap day keeps counting from the cycle start');
      }
    });

    testWidgets('the labels build windowed at their global x positions',
        (tester) async {
      // 100 recorded days (2026-01-20 .. 2026-04-29): far more than one
      // screen, so only the parked window renders labels — and the
      // initial auto-scroll starts that window at the newest days, where
      // the later labels carry the content of THEIR day, not of a
      // re-indexed window. The parked window carries an extra screen-width
      // of margin past the visible edges (31 columns at this viewport), so
      // the earliest days (index 0..36) stay outside it. The fixture keeps
      // its 100 days for exactly that windowing margin: at ~60 days the
      // parked window would swallow index 0.
      await tester
          .pumpWidget(_dayLabelsHarness(entries: _dayLabelsEntries(100)));
      await tester.pumpAndSettle();

      expect(_dayLabel(0), findsNothing,
          reason: 'the earliest days are outside the initial (newest-days) '
              'parked window');
      expect(_dayLabel(99), findsOneWidget,
          reason: 'the newest day fills the initial window');

      // Day index 40 = 2026-03-01 (20 + 40 days): a month FIRST, so its
      // label is the short month form instead of "1." — and the day-of-
      // cycle line is its own (41, counting from 2026-01-20). The initial
      // parked window covers the range's tail, so index 40 renders without
      // any scrolling.
      expect(_label(40, 'Mar'), findsOneWidget,
          reason: 'March 1st shows the short month form even mid-window');
      expect(_label(40, '1.'), findsNothing);
      expect(_label(40, '41'), findsOneWidget);
    });
  });

  group('three-digit day-of-cycle labels', () {
    testWidgets(
        'a long mark-driven cycle (no cycle start in the recorded range — '
        'e.g. during pregnancy) keeps the three-digit day-of-cycle label '
        'inside its column', (tester) async {
      // 104 recorded days (2026-01-20 .. 2026-05-03) with NO cycleStart
      // marks: the leading cycle group's day-of-cycle counter runs 1..104,
      // so the range's tail renders three-digit day-of-cycle labels. The
      // 104 columns overflow the viewport, so every column renders at the
      // 24 px minimum width — the narrowest layout the chart ever uses.
      await tester
          .pumpWidget(_dayLabelsHarness(entries: _dayLabelsEntries(104)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the three-digit day-of-cycle label must not overflow '
              'its 24 px column');

      // Day index 103 shows day-of-cycle 104 (the leading group counts
      // from 2026-01-20) and sits inside the parked window at the newest
      // days. Its rendered label must not paint past its column bounds.
      final column = tester.getRect(_dayLabel(103));
      final label = tester.getRect(
          find.descendant(of: _dayLabel(103), matching: find.text('104')));
      expect(label.left, greaterThanOrEqualTo(column.left - 0.5),
          reason: 'the rendered label does not paint left of its column');
      expect(label.right, lessThanOrEqualTo(column.right + 0.5),
          reason: 'the rendered label does not paint right of its column');
    });

    testWidgets(
        'short day-of-cycle labels keep their natural size — the label '
        'scales down only, never shrinks 1–2 digit numbers', (tester) async {
      await tester
          .pumpWidget(_dayLabelsHarness(entries: _dayLabelsEntries(104)));
      await tester.pumpAndSettle();

      // Day index 45 shows day-of-cycle 46 (the leading group counts from
      // 2026-01-20) and sits inside the parked window at the newest days.
      // In the test font every glyph is a 1 em square, so the natural
      // (unshrunk) width of the label at fontSize 9 is exactly 2 * 9 = 18.
      final label = tester.getRect(
          find.descendant(of: _dayLabel(45), matching: find.text('46')));
      expect(label.width, closeTo(18.0, 0.5),
          reason: 'a two-digit day-of-cycle label renders at its natural, '
              'unshrunk size (it must never be scaled down to fit)');
    });
  });

  group('header above the chart', () {
    testWidgets(
        'the day header row renders ABOVE the temperature curve '
        '(the paper\'s header line on top of the sheet)', (tester) async {
      await tester.pumpWidget(_dayLabelsHarness(entries: _dayLabelsEntries(5)));
      await tester.pumpAndSettle();

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final headerTop =
          tester.getRect(find.byKey(const ValueKey('dayLabel-2'))).top;
      expect(headerTop, lessThan(chartTop),
          reason: 'the day/cycle header sits above the chart, not below it');
    });

    // The header corner itself (a superset test with localized en tooltips,
    // semantics and the de wording variants) lives beside the rail it slots
    // into: the left-rail section.
  });

// ═══════════ disturbances ═══════════
// former test/cycle_chart_disturbances_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'each set temperature-disturbance flag renders its letter token in '
      'the disturbance row of the below-chart strip, in the day\'s column',
      (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
    for (final entry in {
      1: 'kr',
      2: 'alk',
      3: 'sp',
      4: 'a',
    }.entries) {
      final cellRect = tester.getRect(chartCell(entry.key, 'disturbance'));
      expect(cellRect.top, greaterThan(chartBottom),
          reason: 'the disturbance row is part of the below-chart strip, '
              'below the curve');
      expect(chartCellContent(entry.key, 'disturbance', find.text(entry.value)),
          findsOneWidget,
          reason: 'day ${entry.key} carries its disturbance flag\'s letter '
              'code (${entry.value}) in the day\'s column');
      // The letter sits inside its day column horizontally (same column
      // geometry as every other row).
      final curveCell = tester.getRect(chartCell(entry.key, 'bleeding'));
      expect(cellRect.left, closeTo(curveCell.left, 0.5),
          reason: 'the disturbance cell shares the day column geometry');
    }
  });

  testWidgets('plain days render nothing in the disturbance row',
      (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      expect(
          chartCellContent(0, 'disturbance', find.text(letter)), findsNothing,
          reason: 'a plain day shows no letter code');
    }
  });

  testWidgets('a multi-flag day renders its letters stacked in one cell',
      (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    final cell = tester.getRect(chartCell(5, 'disturbance'));
    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      final rects = chartCellContent(5, 'disturbance', find.text(letter))
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
    final krRect =
        tester.getRect(chartCellContent(5, 'disturbance', find.text('kr')));
    final alkRect =
        tester.getRect(chartCellContent(5, 'disturbance', find.text('alk')));
    expect(alkRect.bottom, lessThanOrEqualTo(krRect.top),
        reason: 'the stacked letters do not overlap');
  });

  testWidgets('tapping a disturbance cell opens the day sheet', (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    await tester.tap(chartCell(1, 'disturbance'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _disturbanceDay(1),
        reason: 'the tapped disturbance cell owns day 1');
  });

  testWidgets(
      'the disturbance row has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    expect(chartCellCorner('disturbance'), findsOneWidget);
    final tooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: chartCellCorner('disturbance'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(tooltips, ['Disturbed measurement'],
        reason: 'the disturbance corner carries the localized row name');

    // Vertical alignment with its row (shared row heights, like every
    // other rail glyph).
    final cornerCenter =
        tester.getRect(chartCellCorner('disturbance')).center.dy;
    final cellCenter = tester.getRect(chartCell(3, 'disturbance')).center.dy;
    expect(cornerCenter, closeTo(cellCenter, 0.5),
        reason: 'the disturbance rail glyph is vertically centered on the '
            'row');

    await tester.pumpWidget(_disturbanceHarness(
        entries: _disturbanceEntries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    final deTooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: chartCellCorner('disturbance'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(deTooltips, ['Messstörung'],
        reason: 'de: the disturbance row carries the German row name');
  });

  testWidgets('the help sheet explains the disturbance letters (en)',
      (tester) async {
    await tester.pumpWidget(_disturbanceHarness(entries: _disturbanceEntries));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text('Interrupted days (sp late to bed, '
                'a frequent night awakening, alk alcohol, kr illness)')),
        findsOneWidget,
        reason: 'the letter codes need a legend entry naming the diary\'s '
            'disturbance vocabulary');
  });

  testWidgets('the German help sheet explains the disturbance letters (de)',
      (tester) async {
    await tester.pumpWidget(_disturbanceHarness(
        entries: _disturbanceEntries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text('Gestörte Messung (sp Spät ins Bett, '
                'a Nachts öfter aufstehen, alk Alkohol, kr Krank)')),
        findsOneWidget,
        reason: 'de: the letter codes carry the German vocabulary');
  });

// ═══════════ evaluation marks ═══════════
// former test/cycle_chart_evaluation_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group(
      'R6 — the peak renders as a solid dot in the mucus row, not on '
      'the curve', () {
    testWidgets(
        'the peak day keeps a plain temperature dot — no ring on '
        'the curve', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/12 (idx 6) carries the mucus-peak mark: the curve dot there is
      // an ORDINARY temperature dot — the ring painter is gone from the
      // peak day (R6).
      final painter = _dotPainter(tester, 6);
      expect(painter, isNot(isA<RingDotPainter>()),
          reason: 'the peak ring was removed from the temperature curve');
      expect(painter, isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets(
        'curve rings exist only for the candidate measurements, '
        'not for the peak', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      // Walk every temperature dot: a ring appears exactly on the three
      // circled candidates (idx 8..10), never on the peak day (idx 6).
      final ringIndexes = <int>{};
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is RingDotPainter) ringIndexes.add(spot.x.round());
        }
      }
      expect(ringIndexes, {8, 9, 10},
          reason: 'rings wrap only the circled candidates (R6/R1)');
      for (final index in ringIndexes) {
        final painter = _dotPainter(tester, index) as RingDotPainter;
        expect(painter.ringColor, chartScheme(tester).primary,
            reason: 'circled candidates are temperature-family');
      }
    });

    testWidgets(
        'the peak renders as a solid dot ABOVE the mucus glyph in '
        'the mucus row (classic NER position)', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/12 (idx 6) carries the peak mark -> solid dot in the mucus row.
      expect(_peakDot(6), findsOneWidget);
      // Neighboring days carry no peak dot.
      expect(_peakDot(5), findsNothing);
      expect(_peakDot(7), findsNothing);

      // The dot sits ABOVE the mucus glyph of the same cell.
      final dotTop = tester.getTopLeft(find.byKey(ValueKey('peakDot-6'))).dy;
      final mucusTop = tester
          .getTopLeft(find
              .descendant(
                of: find.byKey(const ValueKey('mucusCell-6')),
                matching: find.byType(MucusSymbolText),
              )
              .first)
          .dy;
      expect(dotTop, lessThan(mucusTop),
          reason: 'the peak dot renders above the mucus entry (R6)');

      // The dot is SOLID and in the mucus color family (tertiary).
      final dot = tester.widget<Container>(_peakDot(6));
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, chartScheme(tester).tertiary,
          reason: 'the peak belongs to the mucus color family');
    });

    testWidgets(
        'a peak day without an entry keeps rendering no dot and '
        'does not crash', (tester) async {
      // 9/12 has NO entry at all: the mucus cell stays empty (flagged
      // rendering assumption, see cycle.dart).
      final entries =
          _evaluationEntries.where((e) => !_sameDay(e, _sat12)).toList();
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsNothing,
          reason: 'no entry -> the mucus row renders nothing for the day');
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          // The circled candidates (idx 8..10) are unaffected by the
          // missing peak entry; what must be ABSENT is the peak ring —
          // i.e. no ring in the mucus color family (tertiary).
          if (painter is RingDotPainter) {
            expect(painter.ringColor, isNot(chartScheme(tester).tertiary));
          }
        }
      }
    });
  });

  group('R1/R4 — candidate circles and arrows follow the new decision', () {
    testWidgets(
        'circled candidates: every measured day above the baseline '
        'from the rise onward, capped and ended by rule D', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      // The candidates (idx 8..10) render circled ...
      for (final index in [8, 9, 10]) {
        final painter = _dotPainter(tester, index);
        expect(painter, isA<RingDotPainter>(),
            reason: 'circled higher measurement at day index $index');
        expect(
            (painter as RingDotPainter).ringColor, chartScheme(tester).primary,
            reason: 'circled higher measurements are temperature-family');
      }
      // ... the pre-rise rise (idx 0, 36.9 above the baseline 36.4) is NOT
      // a candidate (R3) — an ordinary dot.
      expect(_dotPainter(tester, 0), isNot(isA<RingDotPainter>()));
      expect(_dotPainter(tester, 0), isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets(
        'the four-cap: four arrows carry ordinals; the beyond-cap '
        'arrow STAYS in the sequence — unnumbered, but still an arrow '
        '(R4: a late sequence is not cut off at the cap)', (tester) async {
      // Peak unmarked: every candidate (R4) becomes an arrow. Five
      // above-baseline days exist (9/14..9/18) and all five render — the
      // 5th is beyond its kind's cap, so it carries no ordinal, but it
      // stays part of the connected sequence (R4): the sequence only ends
      // at a SUZ trigger or a break, and arrows never trigger a SUZ.
      final entries = [..._evaluationEntries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 36.5));
      final marks = [
        CycleMark(date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: marks));
      await tester.pumpAndSettle();

      for (final index in [8, 9, 10, 11, 12]) {
        expect(_dotPainter(tester, index), isA<ArrowUpDotPainter>(),
            reason: 'no peak -> arrow at $index (R4; the '
                'beyond-cap candidate renders unnumbered)');
      }
      // Nothing is circled anywhere.
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          expect(painter, isNot(isA<RingDotPainter>()));
        }
      }
    });

    testWidgets(
        'the 4th CIRCLED candidate renders when rule E fires '
        '(the 3rd was below the 0.2 K margin)', (tester) async {
      // 9/14..9/17 all 36.5 (+0.1 above the baseline): the 3rd candidate is
      // below the rule-D margin, so the 4th candidate triggers rule E —
      // and all four render as circles. The 5th (9/18) stays unmarked.
      final entries = [
        ..._evaluationEntries.take(8),
        DailyEntry(date: _mon14, bbtC: 36.5),
        DailyEntry(date: _tue15, bbtC: 36.5),
        DailyEntry(date: _wed16, bbtC: 36.5),
        DailyEntry(date: _thu17, bbtC: 36.5),
        DailyEntry(date: _fri18, bbtC: 36.5),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      for (final index in [8, 9, 10, 11]) {
        expect(_dotPainter(tester, index), isA<RingDotPainter>(),
            reason: 'the 4th circled candidate exists under rule E');
      }
      expect(dotPainterOrNull(tester, 12), isNotNull);
      expect(_dotPainter(tester, 12), isNot(isA<RingDotPainter>()),
          reason: 'the sequence ended at the rule-E trigger');
    });

    testWidgets(
        'a MIXED sequence: the peak-day candidate is an arrow and '
        'circles follow it chronologically (R4 per candidate)', (tester) async {
      // The peak mark sits ON 9/15 (idx 9), between the marked rise (9/14)
      // and the later candidates: 9/14 and the peak day's own candidate are
      // ARROWS; everything strictly after the peak (9/16..9/18) is
      // CIRCLED, with the circle ordinals restarting at 1 (the 3rd circle,
      // 9/18 at 37.0, is >= 0.2 K above the baseline -> rule D fires and
      // ends the sequence there).
      final entries = [..._evaluationEntries];
      entries.add(DailyEntry(date: _thu17, bbtC: 36.5));
      entries.add(DailyEntry(date: _fri18, bbtC: 37.0));
      final marks = [
        CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        CycleMark(date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: marks));
      await tester.pumpAndSettle();

      // Collected kinds across the whole curve, indexed by day.
      final arrows = <int>{};
      final circles = <int>{};
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is ArrowUpDotPainter) arrows.add(spot.x.round());
          if (painter is RingDotPainter) circles.add(spot.x.round());
        }
      }

      // At or before the peak day (9/14, 9/15): arrows.
      expect(arrows, {8, 9},
          reason: 'candidates at or before the peak are arrows (R4) — '
              'the peak day itself included');
      // Strictly after the peak (9/16..9/18): circles.
      expect(circles, {10, 11, 12},
          reason: 'candidates after the peak are circles (R4)');
      // Chronological arrows-then-circles — no interleaving.
      expect(arrows.every((a) => circles.every((c) => a < c)), isTrue,
          reason: 'arrows precede circles (R4)');
    });
  });

  group('numbering', () {
    testWidgets(
        'the six low days carry 1–6, counted back from the first '
        'higher', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      // 9/13..9/8 (idx 7..2) = numbers 1..6.
      expect(_numberUnder(tester, 7), '1');
      expect(_numberUnder(tester, 6), '2');
      expect(_numberUnder(tester, 5), '3');
      expect(_numberUnder(tester, 4), '4');
      expect(_numberUnder(tester, 3), '5');
      expect(_numberUnder(tester, 2), '6');
      // Outside the six-window: no numbers.
      expect(_numberUnder(tester, 0), isNull,
          reason: '9/6: outside the window');
      expect(_numberUnder(tester, 1), isNull, reason: '9/7: 7th prior day');
      expect(_numberUnder(tester, 8), isNull,
          reason: '9/14: the first higher itself is not a low');
    });
  });

  group('baseline — R10 segment', () {
    testWidgets(
        'the baseline draws as a SEGMENT: from the left edge of '
        'low #6\'s column to the last marked candidate (+ half a day), '
        'clamped to the plot bounds', (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      final bars = _baselineBars(tester);
      expect(bars, hasLength(1), reason: 'one evaluated cycle -> one segment');
      final bar = bars.single;
      expect(bar.color, chartScheme(tester).secondary,
          reason: 'the baseline keeps its theme-derived secondary color');
      expect(bar.dashArray, const [6, 4], reason: 'the dashed style stays');
      // START: the left edge of low #6's column — low #6 is 9/8 (idx 2),
      // so the segment begins at x 1.5.
      // END: the last marked candidate (9/16, idx 10 — the rule-D trigger)
      // plus half a day = x 10.5 — the domain extends half a column past
      // the last day, so the clamp no longer bites here.
      final first = bar.spots.first;
      final last = bar.spots.last;
      expect(first.x, closeTo(1.5, 1e-9),
          reason: 'the segment starts under low #6 (left column edge)');
      expect(last.x, closeTo(10.5, 1e-9),
          reason: 'last candidate idx 10 + half a day, inside the domain '
              '(lastX = dayCount − 0.5 = 10.5)');
      expect(first.y, 36.4);
      expect(last.y, 36.4, reason: 'the segment runs at the baseline value');
    });

    testWidgets(
        'the segment ends half a day past the last candidate\'s '
        'column when recorded days continue past it', (tester) async {
      // 9/17 sits AT the baseline (36.4): a gap day, not a candidate — the
      // sequence ended at the rule-D trigger on 9/16, so the R10 segment
      // ends at 9/16's day column + half a day = x 10.5 (no clamp needed).
      final entries = [
        ..._evaluationEntries,
        DailyEntry(date: _thu17, bbtC: 36.4)
      ];
      await tester.pumpWidget(_harness(entries: entries, marks: _marks));
      await tester.pumpAndSettle();

      final spots = _baselineBars(tester).single.spots;
      expect(spots.first.x, closeTo(1.5, 1e-9),
          reason: 'the segment starts under low #6 (left column edge)');
      expect(spots.last.x, closeTo(10.5, 1e-9),
          reason: 'last marked candidate 9/16 (idx 10) + half a day');
    });

    testWidgets('no marked candidate -> no baseline segment', (tester) async {
      // Peak only: no first-higher mark, so no low window and no segment.
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();
      expect(_baselineBars(tester), isEmpty);

      // First higher marked, but every day from the rise on sits AT or
      // below the baseline: no marked candidate exists, so R10 draws no
      // segment at all (not even a partial one through the low window).
      final flat = [
        for (final e in _evaluationEntries)
          e.date.isAfter(_sun13) ? DailyEntry(date: e.date, bbtC: 36.4) : e,
      ];
      await tester.pumpWidget(_harness(entries: flat, marks: _marks));
      await tester.pumpAndSettle();
      expect(_baselineBars(tester), isEmpty,
          reason: 'R10: a cycle with no marked candidate draws no segment');
    });
  });

  group('no marks', () {
    testWidgets('nothing evaluation-related is drawn when no marks exist',
        (tester) async {
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: const []));
      await tester.pumpAndSettle();

      expect(_baselineBars(tester), isEmpty,
          reason: 'no marks -> no baseline segment');
      for (var i = 0; i < 11; i++) {
        expect(_numberUnder(tester, i), isNull,
            reason: 'no marks -> no numbers');
        expect(_peakDot(i), findsNothing, reason: 'no marks -> no peak dot');
      }
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          expect(painter, isNot(isA<RingDotPainter>()));
          expect(painter, isNot(isA<ArrowUpDotPainter>()));
        }
      }
    });
  });

  group('all mucus peaks render (from the marks stream)', () {
    testWidgets(
        'two peak marks in one cycle render two solid dots — even '
        'when no evaluation exists', (tester) async {
      // ONLY peak marks: without a first-higher mark no evaluation can
      // exist, yet every placed peak must render — the dots come from the
      // MARKS STREAM, not from the single domain-anchored peak.
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
          CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsOneWidget, reason: 'the first peak renders');
      expect(_peakDot(9), findsOneWidget,
          reason: 'the second peak renders too, though the evaluation has '
              'nothing to anchor (no rise marked)');
      expect(_peakDot(8), findsNothing,
          reason: 'a day without a peak mark renders no dot');
    });

    testWidgets('two peaks render alongside a full evaluation', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          ..._marks,
          CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_peakDot(6), findsOneWidget);
      expect(_peakDot(9), findsOneWidget);
    });
  });

  group('SUZ marks render (user-placed only)', () {
    // The glyph's top anchoring: the bar hangs DOWN from the chart's top
    // border by a fixed °C drop and the arrow anchors just below that
    // border, so the whole glyph sits below the sex row above the plot.
    // The two pinned values (hang span 0.5 °C, arrow inset 0.25 °C) are
    // owner-eyeball rendering details — update a pin together with its
    // named constant in lib/ui/cycle.dart.
    testWidgets(
        'a suzEvening mark renders a vertical bar hanging from the '
        'chart\'s top border at the column middle, plus a right-pointing '
        'arrow whose base starts at the bar near the top', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          ..._marks,
          CycleMark(date: _wed16, type: CycleMarkTypes.suzEvening),
        ],
      ));
      await tester.pumpAndSettle();

      final data = chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1), reason: 'one user SUZ mark -> one bar');
      final bar = bars.single;
      // suzEvening anchors the bar at the day column's MIDDLE (x = day
      // index); the bar hangs DOWN from the chart's top border by a fixed
      // °C drop instead of spanning the whole plot height.
      expect(bar.spots.first.x, 10.0,
          reason: 'suzEvening anchors at the column middle (9/16, idx 10)');
      expect(bar.spots.last.x, 10.0);
      expect(bar.spots.first.y, data.maxY,
          reason: 'the bar hangs from the chart\'s top border');
      expect(bar.spots.last.y, data.maxY - 0.5,
          reason: 'the bar spans a fixed 0.5 °C drop from the top '
              '(owner-eyeball value, pinned here)');
      expect(bar.color, chartScheme(tester).secondary,
          reason: 'the SUZ bar shares the baseline\'s evaluation-family '
              'color role (secondary)');

      // The right-pointing arrow: base at the bar, anchored inside the
      // hung band, close to the top border (no longer at the cycle's
      // baseline value — the baseline-anchor concept is retired).
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull, reason: 'the SUZ arrow renders with the bar');
      final (spot, painter) = arrow!;
      expect(spot.x, 10.0, reason: 'the arrow base starts at the bar');
      expect(spot.y, data.maxY - 0.25,
          reason: 'the arrow anchors 0.25 °C below the top border, inside '
              'the hung band (owner-eyeball value, pinned here)');
      expect(painter, isA<SuzArrowDotPainter>());
      expect(
          (painter as SuzArrowDotPainter).color, chartScheme(tester).secondary,
          reason: 'the SUZ arrow shares the evaluation-family color role');
    });

    testWidgets(
        'a suzMorning mark anchors the bar at the column START '
        '(x − 0.5)', (tester) async {
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          ..._marks,
          CycleMark(date: _tue15, type: CycleMarkTypes.suzMorning),
        ],
      ));
      await tester.pumpAndSettle();

      final data = chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1));
      final bar = bars.single;
      expect(bar.spots.first.x, 8.5,
          reason: 'suzMorning anchors at the column start (9/15, idx 9 − 0.5)');
      expect(bar.spots.last.x, 8.5);
      // The hang-span/inset values do not depend on the x anchoring.
      expect(bar.spots.first.y, data.maxY,
          reason: 'the bar hangs from the chart\'s top border');
      expect(bar.spots.last.y, data.maxY - 0.5,
          reason: 'the bar spans a fixed 0.5 °C drop from the top '
              '(owner-eyeball value, pinned here)');
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull);
      expect(arrow!.$1.x, 8.5, reason: 'the arrow base starts at the bar');
      expect(arrow.$1.y, data.maxY - 0.25,
          reason: 'the arrow anchors 0.25 °C below the top border, inside '
              'the hung band (owner-eyeball value, pinned here)');
    });

    testWidgets(
        'a suzMorning mark on the FIRST recorded day anchors the bar at '
        'the plot\'s left edge (x − 0.5 = minX, no cut-back)', (tester) async {
      // With the half-column-shifted domain the first day's column starts
      // at −0.5, so its column-START bar sits exactly at the plot's left
      // edge instead of being clamped onto the day index.
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          ..._marks,
          CycleMark(date: _sun6, type: CycleMarkTypes.suzMorning),
        ],
      ));
      await tester.pumpAndSettle();

      final bars = _suzBars(tester);
      expect(bars, hasLength(1));
      final data = chartData(tester);
      final bar = bars.single;
      expect(bar.spots.first.x, -0.5,
          reason: 'day 0\'s column start is the domain\'s minX (−0.5)');
      expect(bar.spots.last.x, -0.5);
      // The clamping affects only x — the top-anchored y values stand.
      expect(bar.spots.first.y, data.maxY,
          reason: 'the bar hangs from the chart\'s top border');
      expect(bar.spots.last.y, data.maxY - 0.5,
          reason: 'the bar spans a fixed 0.5 °C drop from the top '
              '(owner-eyeball value, pinned here)');
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull);
      expect(arrow!.$1.x, -0.5, reason: 'the arrow base starts at the bar');
      expect(arrow.$1.y, data.maxY - 0.25,
          reason: 'the arrow anchors 0.25 °C below the top border, inside '
              'the hung band (owner-eyeball value, pinned here)');
    });

    testWidgets(
        'no SUZ glyph renders without a user mark — the computed '
        'suzBegins suggests only, it never renders', (tester) async {
      // The main scenario's arithmetic fires rule D on 9/16 — but no user
      // SUZ mark exists, so the chart draws no SUZ bar and no arrow.
      await tester
          .pumpWidget(_harness(entries: _evaluationEntries, marks: _marks));
      await tester.pumpAndSettle();

      expect(_suzBars(tester), isEmpty,
          reason: 'the computed SUZ never renders on the chart');
      expect(_suzArrowSpot(tester), isNull);
    });
  });

  group('latest-rise anchor renders in the UI (re-marking supersedes)', () {
    testWidgets(
        'two rise marks: the LATER one drives the evaluation; the earlier '
        'rise day renders no candidate', (tester) async {
      // Two firstHigher marks: 9/14 and 9/15. The LATER mark (9/15) anchors
      // the evaluation — and re-derives the six-low window with it (R9):
      // the lows before 9/15 are 9/9..9/14, so the baseline moves to 9/14's
      // 36.9 (the earlier rise mark's day itself becomes a low!). From the
      // walk start 9/15: 9/15 sits AT the new baseline (gap day, no
      // candidate), 9/16 (37.0) is circle #1 — no SUZ with a single circle.
      // Under the old earliest-anchor semantics the circles would be
      // {8, 9, 10} against the 36.4 baseline; the later mark wins instead.
      await tester.pumpWidget(_harness(
        entries: _evaluationEntries,
        marks: [
          CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
          CycleMark(date: _mon14, type: CycleMarkTypes.firstHigherMeasurement),
          CycleMark(date: _tue15, type: CycleMarkTypes.firstHigherMeasurement),
        ],
      ));
      await tester.pumpAndSettle();

      final rings = <int>{};
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter =
              bar.dotData.getDotPainter(spot, 0, bar, bar.spots.indexOf(spot));
          if (painter is RingDotPainter) rings.add(spot.x.round());
        }
      }
      expect(rings, {10},
          reason: 'the LATEST rise mark anchors the evaluation: the '
              're-derived baseline (36.9 through the earlier rise day, now '
              'low #1) leaves 9/16 as the only candidate');
      // The earlier rise mark's day (9/14, idx 8) renders no candidate —
      // it sits at the new baseline as a low.
      expect(_dotPainter(tester, 8), isNot(isA<RingDotPainter>()),
          reason: 'the earlier rise mark renders no candidate');
      expect(_dotPainter(tester, 8), isNot(isA<ArrowUpDotPainter>()));
      // And the marked rise day itself (9/15) sits at the re-derived
      // baseline: no candidate there either.
      expect(_dotPainter(tester, 9), isNot(isA<RingDotPainter>()));
      expect(_dotPainter(tester, 9), isNot(isA<ArrowUpDotPainter>()));
    });
  });

// ═══════════ grid lines ═══════════
// former test/cycle_chart_grid_lines_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('vertical day lines', () {
    testWidgets(
        'the chart draws hairline vertical grid lines with interval 1 '
        'aligned to the shifted domain\'s column boundaries', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final grid = chartData(tester).gridData;
      expect(grid.drawVerticalLine, isTrue,
          reason: 'the day columns are separated by vertical lines');
      expect(grid.verticalInterval, 1, reason: 'one line per day column');
      // The domain is half a column shifted (minX −0.5); with the baseline
      // at minX the interval-1 lines land on the interior column
      // boundaries 0.5, 1.5, … dayCount − 1.5.
      expect(chartData(tester).baselineX, -0.5,
          reason: 'the grid baseline sits at the domain start so interval-1 '
              'lines land on column boundaries');
      final line = grid.getDrawingVerticalLine(0.5);
      expect(line.strokeWidth, lessThanOrEqualTo(1),
          reason: 'day lines are hairlines');
      expect(line.color, chartScheme(tester).onSurface.withValues(alpha: 0.12),
          reason: 'the hairline is a subtle onSurface tint');
    });

    testWidgets(
        'every signal row\'s day cells carry a matching hairline right '
        'border, and the header row does too', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final onSurface = chartScheme(tester).onSurface;
      for (final row in const [
        'bleeding',
        'mucus',
        'cervix',
        'sex',
        'pain',
        'time',
      ]) {
        final border = _cellRightBorder(tester, 1, row);
        expect(border.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: a hairline right border on the day cell');
        expect(border.right.color, onSurface.withValues(alpha: 0.12),
            reason: 'row $row: the border matches the chart\'s day line '
                'style');
      }

      // The header row's cells carry the same hairline (the day/cycle
      // header belongs to the card).
      final headerBorder = tester
          .widgetList<Container>(find.descendant(
              of: find.byKey(const ValueKey('dayLabel-1')),
              matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere((b) => !b.isUniform,
              orElse: () => fail('no header '
                  'cell border found'));
      expect(headerBorder.right.width, closeTo(0.5, 0.01));
    });

    testWidgets(
        'cycle starts draw thick solid lines: the chart\'s extra line at '
        'nextCycleStart − 0.5 and the thick right border on the cell '
        'before the new cycle in every row', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final onSurface = chartScheme(tester).onSurface;
      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      final boundaryXs = verticalLines.map((l) => l.x).toSet();
      expect(boundaryXs, {4.5, 8.5},
          reason: 'the marked days at indexes 5 and 9 draw their separator '
              'at x = start − 0.5');
      for (final line in verticalLines) {
        expect(line.strokeWidth, closeTo(2, 0.01),
            reason: 'cycle-start lines are thick');
        expect(line.color, onSurface,
            reason: 'cycle-start lines are solid onSurface');
        expect(line.dashArray, isNull, reason: 'the line is solid, not dashed');
      }

      // The thick border sits on the cell BEFORE the new cycle (its right
      // edge is the separator), in every signal row.
      for (final row in const [
        'bleeding',
        'mucus',
        'cervix',
        'sex',
        'pain',
        'time',
      ]) {
        final thick = _cellRightBorder(tester, 4, row);
        expect(thick.right.width, closeTo(2, 0.01),
            reason: 'row $row: the boundary cell carries the thick border');
        expect(thick.right.color, onSurface,
            reason: 'row $row: the boundary border is solid onSurface');
        // The neighboring cells keep the hairline.
        final thinBefore = _cellRightBorder(tester, 3, row);
        expect(thinBefore.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: only the boundary cell is thick');
        final thinAfter = _cellRightBorder(tester, 5, row);
        expect(thinAfter.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: the new cycle\'s first day carries no thick '
                'border (the separator is to its LEFT)');
      }
    });

    testWidgets(
        'no cycle-start line before the first cycleStart mark (the '
        'leading group)', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      expect(verticalLines.map((l) => l.x), isNot(contains(-0.5)),
          reason: 'the leading group\'s start is not a cycle-start line');

      // The first cell of every row keeps the plain hairline.
      final onSurface = chartScheme(tester).onSurface;
      for (final row in const ['bleeding', 'mucus', 'time']) {
        final border = _cellRightBorder(tester, 0, row);
        expect(border.right.width, closeTo(0.5, 0.01),
            reason: 'row $row: no thick border on the leading group\'s last '
                'cell');
        expect(border.right.color, onSurface.withValues(alpha: 0.12));
      }
    });

    testWidgets('a boundary across untracked gap days is still drawn',
        (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _gapEntries, marks: _gapMarks));
      await tester.pumpAndSettle();

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      expect(verticalLines.map((l) => l.x), contains(4.5),
          reason: 'the group opened across the untracked gap days draws '
              'its separator across the gap');
    });
  });

  group('horizontal NER temperature grid', () {
    FlGridData grid(WidgetTester tester) => chartData(tester).gridData;

    Color emphasizedLine(WidgetTester tester) =>
        chartScheme(tester).onSurface.withValues(alpha: 0.45);

    Color plainLine(WidgetTester tester) =>
        chartScheme(tester).onSurface.withValues(alpha: 0.12);

    /// The horizontal-line styling for one temperature value.
    FlLine horizontalLine(WidgetTester tester, double value) =>
        grid(tester).getDrawingHorizontalLine(value);

    testWidgets(
        'the temperature body carries horizontal lines every 0.1 °C over '
        'the fixed display range', (tester) async {
      // The entries keep 36.5 — well inside the default 36–38 °C range; the
      // grid interval is fixed at 0.1 regardless of the data.
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      expect(grid(tester).drawHorizontalLine, isTrue,
          reason: 'the paper grid rules the temperature body horizontally');
      expect(grid(tester).horizontalInterval, 0.1,
          reason: 'one grid line per 0.1 K step (paper convention)');
    });

    testWidgets(
        'full degrees draw SOLID, thick emphasis lines (×10 integer '
        'classification, no float equality)', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      for (final value in const [36.0, 37.0, 38.0]) {
        final line = horizontalLine(tester, value);
        expect(line.strokeWidth, closeTo(1.2, 0.01),
            reason: '$value is a full degree: the grid emphasizes it');
        expect(line.dashArray, isNull,
            reason: '$value: a full-degree line is solid');
        expect(line.color, emphasizedLine(tester),
            reason: '$value: the emphasis tint on the on-surface color');
      }
    });

    testWidgets('the 0.5 midpoints draw DASHED lines at the emphasis weight',
        (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      for (final value in const [36.5, 37.5]) {
        final line = horizontalLine(tester, value);
        expect(line.strokeWidth, closeTo(1.2, 0.01),
            reason: '$value: the half midpoint keeps the emphasis weight');
        expect(line.dashArray, [4, 3], reason: '$value is dashed');
        expect(line.color, emphasizedLine(tester),
            reason: '$value: the emphasis tint on the on-surface color');
      }
    });

    testWidgets('the remaining 0.1 steps draw the plain day-hairline style',
        (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      for (final value in const [36.1, 36.2, 36.3, 36.4, 36.6, 36.9, 37.9]) {
        final line = horizontalLine(tester, value);
        expect(line.strokeWidth, closeTo(0.5, 0.01),
            reason: '$value: an in-between step stays a hairline');
        expect(line.dashArray, isNull, reason: '$value is solid');
        expect(line.color, plainLine(tester),
            reason: '$value: the same subtle tint as the vertical day lines');
      }
    });

    testWidgets(
        'the vertical day lines are unchanged by the horizontal grid: '
        'interval 1, hairline style', (tester) async {
      await tester.pumpWidget(
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks));
      await tester.pumpAndSettle();

      expect(grid(tester).drawVerticalLine, isTrue);
      expect(grid(tester).verticalInterval, 1);
      final vertical = grid(tester).getDrawingVerticalLine(0.5);
      expect(vertical.strokeWidth, lessThanOrEqualTo(1));
      expect(vertical.color, plainLine(tester),
          reason: 'the day hairline style keeps its subtle tint');
    });
  });

// ═══════════ help sheet ═══════════
// former test/cycle_chart_help_sheet_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('help sheet', () {
    testWidgets(
        'the Zyklus AppBar carries an info_outline action with a localized '
        'tooltip, and the glossary is NOT on the screen otherwise',
        (tester) async {
      await tester.pumpWidget(_helpSheetHarness(entries: _helpSheetEntries(5)));
      await tester.pumpAndSettle();

      final action = tester
          .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')));
      expect(action.icon,
          isA<Icon>().having((i) => i.icon, 'icon', Icons.info_outline),
          reason: 'the affordance is the info_outline icon');
      expect(action.tooltip, 'Show symbol glossary',
          reason: 'the action carries its localized tooltip');

      // The legend is gone from the screen: no glossary text renders
      // outside the sheet. The evaluation table below the chart card
      // legitimately renders its own localized row labels (its "Mucus
      // peak" row is a table attribute, not a glossary entry), so the
      // table's subtree is excluded from this absence check.
      for (final entry in _glossaryEn) {
        expect(outsideTable(find.text(entry)), isEmpty,
            reason: '"$entry" no longer sits on the screen');
      }
    });

    testWidgets('tapping the action opens the full symbol glossary (en)',
        (tester) async {
      await tester.pumpWidget(_helpSheetHarness(entries: _helpSheetEntries(5)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the action opens a bottom sheet');
      expect(find.byKey(const ValueKey('cycleHelpSheet')), findsOneWidget,
          reason: 'the sheet carries its test key');
      expect(find.text('Symbol glossary'), findsOneWidget,
          reason: 'the sheet is titled');
      for (final entry in _glossaryEn) {
        // Scoped to the sheet: the evaluation table renders its own row
        // labels behind the sheet (the "Mucus peak" attribute row).
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('cycleHelpSheet')),
                matching: find.text(entry)),
            findsOneWidget,
            reason: 'the glossary explains "$entry"');
      }
      // The sheet also carries the evaluation-arithmetic note (which stays
      // on the screen below the chart card too — scoped to the sheet here).
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text(_arithmeticNoteEn)),
          findsOneWidget);
      // The mucus glossary sample is the plain S glyph (no EW superscript).
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text('EW')),
          findsNothing,
          reason: 'the mucus glossary sample carries no EW superscript');
      // The ignored-temperature entry samples the VISUAL consequence: a
      // lighter temperature dot (primary at the chart's own 0.4 alpha —
      // the same constant the curve draws with), replacing the old
      // day-sheet-toggle icon sample.
      final scheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme;
      final lighterDotSamples = find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color ==
                  scheme.primary.withValues(alpha: 0.4)));
      expect(lighterDotSamples, findsOneWidget,
          reason: 'the glossary samples the lighter temperature dot '
              '(primary at 0.4 alpha — derived from the same constant the '
              'chart uses so they cannot drift)');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.byIcon(Icons.visibility_off_outlined)),
          findsNothing,
          reason: 'the old day-sheet-toggle icon sample is gone — the '
              'legend shows the rendering consequence, not the affordance');
    });

    testWidgets('the glossary uses the German wording in de', (tester) async {
      await tester.pumpWidget(_helpSheetHarness(
          entries: _helpSheetEntries(5), locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')))
              .tooltip,
          'Zeichenerklärung anzeigen');

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.text('Zeichenerklärung'), findsOneWidget);
      for (final entry in _glossaryDe) {
        // Scoped to the sheet: the evaluation table renders its own row
        // labels behind the sheet (the "Schleimhöhepunkt" attribute row).
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('cycleHelpSheet')),
                matching: find.text(entry)),
            findsOneWidget,
            reason: 'de: "$entry"');
      }
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text(_arithmeticNoteDe)),
          findsOneWidget);
    });
  });

// ═══════════ left rail ═══════════
// former test/cycle_chart_left_rail_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('frozen left rail', () {
    testWidgets(
        'the rail renders outside the horizontal scroll and stays frozen '
        'while the day columns move', (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      expect(_rail(), findsOneWidget,
          reason: 'the chart block has a fixed left rail');
      expect(find.descendant(of: chartScrollView(), matching: _rail()),
          findsNothing,
          reason: 'the rail is outside the horizontally scrolling content — '
              'the temperature scale cannot scroll away anymore');

      final railBefore = tester.getRect(_rail());
      final scaleBefore =
          tester.getRect(find.byKey(const ValueKey('railScale')));
      final cellBefore =
          tester.getRect(find.byKey(const ValueKey('bleedingCell-40')));
      // The drag's exact delta depends on the framework's touch slop (see
      // the windowing tests), so the content movement is checked against
      // the settled scroll offset, not the dragged distance.
      final scrollState = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      final offsetBefore = scrollState.position.pixels;

      // Scroll the window toward earlier days (as the windowing tests do):
      // the day columns move, the rail does not.
      await tester.drag(chartScrollView(), const Offset(260, 0));
      await tester.pumpAndSettle();
      final offsetAfter = scrollState.position.pixels;

      expect(tester.getRect(_rail()), railBefore,
          reason: 'the frozen rail keeps its exact rect while scrolling');
      expect(
          tester.getRect(find.byKey(const ValueKey('railScale'))), scaleBefore,
          reason: 'the temperature scale stays put — the defect this rail '
              'fixes: the scale used to scroll away with the content');
      final cellAfter =
          tester.getRect(find.byKey(const ValueKey('bleedingCell-40')));
      expect(cellAfter.center.dx, isNot(cellBefore.center.dx),
          reason: 'precondition: the day columns actually moved');
      expect(cellAfter.center.dx - cellBefore.center.dx,
          closeTo(offsetBefore - offsetAfter, 1),
          reason: 'the day columns move exactly with the scroll offset — '
              'the rail is not part of the scrolling content');
    });

    testWidgets(
        'the scale labels share the chart\'s y mapping: every label sits '
        'exactly at its value\'s plot pixel y', (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: _leftRailEntries));
      await tester.pumpAndSettle();

      // fl_chart's left titles are disabled: the scale cannot be the
      // scrolling chart's own axis strip anymore.
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.titlesData.leftTitles.sideTitles.showTitles, isFalse,
          reason: 'the chart no longer draws its own left scale');
      expect(data.titlesData.leftTitles.sideTitles.reservedSize, 0,
          reason: 'the chart reserves no width for a scale — the plot spans '
              'the full scroll content width');

      // The rail's labels must follow the SAME linear mapping the chart
      // uses: y = plotTop + (maxY − value) / (maxY − minY) * plotHeight.
      final chartRect = tester.getRect(find.byType(LineChart));
      final span = data.maxY - data.minY;
      expect(span, greaterThan(0), reason: 'a usable y domain');
      for (final label in _scaleLabels(tester)) {
        final value = double.parse(label);
        final expectedY =
            chartRect.top + (data.maxY - value) / span * chartRect.height;
        final labelCenter = tester
            .getRect(find.descendant(of: _rail(), matching: find.text(label)))
            .center
            .dy;
        expect(labelCenter, closeTo(expectedY, 0.5),
            reason: 'scale label $label sits at its value\'s pixel y — the '
                'rail and the plot share one mapping');
      }
    });

    testWidgets(
        'the scale keeps the 0.5 °C interval and the two-scale numbering '
        '(integers plain, halves with one decimal)', (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: _leftRailEntries));
      await tester.pumpAndSettle();

      // The fixed settings range 36..38 supplies the bounds (not the
      // data rounding anymore): every half-degree tick between them,
      // top-down 38 .. 36.
      expect(_scaleLabels(tester), ['38', '37.5', '37', '36.5', '36'],
          reason: 'half-degree ticks over the default range, integers '
              'plain and halves one-decimal');
    });

    testWidgets(
        'the six row-name glyphs render IN the rail, each vertically '
        'aligned with its signal row', (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: _leftRailEntries));
      await tester.pumpAndSettle();

      const rows = [
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
      for (final row in rows) {
        final corner = find.byKey(ValueKey('${row}Corner'));
        expect(corner, findsOneWidget,
            reason: 'row $row\'s sample glyph renders (in the rail)');
        expect(find.descendant(of: _rail(), matching: corner), findsOneWidget,
            reason: 'row $row\'s sample glyph lives in the frozen rail, not '
                'in the scrolling rows');

        // Vertical alignment with the row: the glyph's rect center equals
        // one of the row's day cells' center (fixed row heights make this
        // a stable, exact assertion).
        final cornerCenter = tester.getRect(corner).center.dy;
        final cellCenter =
            tester.getRect(find.byKey(ValueKey('${row}Cell-3'))).center.dy;
        expect(cornerCenter, closeTo(cellCenter, 0.5),
            reason: 'row $row\'s rail glyph is vertically centered on the '
                'row');

        // The row name stays attached to the glyph for screen readers and
        // long-press: a tooltip renders in the rail.
        expect(
            tester
                .widgetList<Tooltip>(
                    find.descendant(of: corner, matching: find.byType(Tooltip)))
                .length,
            1,
            reason: 'row $row\'s rail glyph keeps its row-name tooltip');
      }
    });

    testWidgets(
        'the below-chart strip is ONE rail segment: its glyph slots keep '
        'the owner-decided order time, disturbance, cervix, pain, note',
        (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: _leftRailEntries));
      await tester.pumpAndSettle();

      double top(String row) =>
          tester.getRect(find.byKey(ValueKey('${row}Corner'))).top;
      const strip = ['time', 'disturbance', 'cervix', 'pain', 'note'];
      final tops = [for (final row in strip) top(row)];
      expect(tops, equals([...tops]..sort()),
          reason: 'the below-chart strip mirrors the content column\'s '
              'single segment: time first, notes last (owner order)');
      // The strip starts after the marks-row slot, mirroring the content
      // column (the marks slot sits between the temperature scale and the
      // segment).
      expect(
          top('time'),
          greaterThan(
              tester.getRect(find.byKey(const ValueKey('railScale'))).bottom),
          reason: 'the below-chart segment begins below the scale and the '
              'marks slot, as in the content column');
    });

    testWidgets(
        'the header corner (date + cycle-day prototypes) renders in the '
        'rail with its tooltips and semantics', (tester) async {
      await tester.pumpWidget(_leftRailHarness(entries: _leftRailEntries));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      expect(find.descendant(of: _rail(), matching: corner), findsOneWidget,
          reason: 'the header corner slots into the frozen rail');
      expect(find.descendant(of: corner, matching: find.text('14.')),
          findsOneWidget);
      expect(find.descendant(of: corner, matching: find.text('#5')),
          findsOneWidget);

      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Date', 'Cycle day']),
          reason: 'both prototypes keep their localized tooltips');
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Date')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Cycle day')),
        findsOneWidget,
      );
    });

    testWidgets('the corner prototypes use the German wording in de',
        (tester) async {
      await tester.pumpWidget(_leftRailHarness(
          entries: _leftRailEntries, locale: const Locale('de')));
      await tester.pumpAndSettle();

      final corner = find.byKey(const ValueKey('dayHeaderCorner'));
      final tooltips = tester
          .widgetList<Tooltip>(
              find.descendant(of: corner, matching: find.byType(Tooltip)))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Datum', 'Zyklustag']));
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Datum')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: corner,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Zyklustag')),
        findsOneWidget,
      );
    });

    testWidgets(
        'a flat temperature record keeps the scale usable (the fixed '
        'range always has ticks)', (tester) async {
      // All five days at 36.5: the bounds stay the settings range 36..38,
      // so the scale always has ticks and the mapping never divides by
      // zero — no data-dependent degenerate span can appear anymore.
      await tester.pumpWidget(_leftRailHarness(entries: _flatEntries()));
      await tester.pumpAndSettle();

      expect(_scaleLabels(tester), ['38', '37.5', '37', '36.5', '36'],
          reason: 'a single-value record still renders a half-degree scale');
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final chartRect = tester.getRect(find.byType(LineChart));
      final expectedMid = chartRect.top +
          (data.maxY - 36.5) / (data.maxY - data.minY) * chartRect.height;
      final midCenter = tester
          .getRect(find.descendant(of: _rail(), matching: find.text('36.5')))
          .center
          .dy;
      expect(midCenter, closeTo(expectedMid, 0.5),
          reason: 'the flat record\'s value maps mid-scale in both places');
    });

    testWidgets(
        'an overridden settings range moves the bounds AND the rail '
        'labels (one source of truth)', (tester) async {
      await tester.pumpWidget(_leftRailHarness(
        entries: _leftRailEntries,
        range: const TemperatureRange(min: 35.0, max: 39.0),
      ));
      await tester.pumpAndSettle();

      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.minY, 35.0,
          reason: 'the overridden range\'s lower bound is the chart minY');
      expect(data.maxY, 39.0,
          reason: 'the overridden range\'s upper bound is the chart maxY');
      expect(
          _scaleLabels(tester),
          [
            '39',
            '38.5',
            '38',
            '37.5',
            '37',
            '36.5',
            '36',
            '35.5',
            '35',
          ],
          reason: 'every half-degree tick between the overridden bounds '
              'renders in the rail');
    });
  });

// ═══════════ note indicator ═══════════
// former test/cycle_chart_note_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'a day with a non-empty note renders the indicator glyph in its '
      'day column, below the chart block', (tester) async {
    await tester.pumpWidget(_noteHarness(entries: _noteEntries));
    await tester.pumpAndSettle();

    // The glyph rides in the day's column (the LAST row of the
    // below-chart strip, the paper "Bemerkungen" home).
    final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
    final noteRect = tester.getRect(chartCell(1, 'note'));
    expect(noteRect.top, greaterThan(chartBottom),
        reason: 'the note-indicator row sits below the chart block');
    expect(tester.getRect(chartCell(1, 'time')).top, lessThan(noteRect.top),
        reason: 'the note indicator renders below the measurement-time '
            'row, below the chart block');
    for (final row in ['disturbance', 'cervix', 'pain']) {
      expect(noteRect.top, greaterThan(tester.getRect(chartCell(1, row)).top),
          reason: 'the note indicator renders below the $row row — notes '
              'are last in the below-chart strip');
    }
    final cell = tester.getRect(chartCell(1, 'bleeding'));
    expect(noteRect.left, closeTo(cell.left, 0.5),
        reason: 'the note cell shares the day column geometry');

    // The indicator glyphs: the sticky-note icon, one per noted day.
    expect(
        chartCellContent(1, 'note', find.byIcon(Icons.sticky_note_2_outlined)),
        findsOneWidget,
        reason: 'noted day 1 shows the indicator glyph in its column');
  });

  testWidgets('empty/absent notes render nothing', (tester) async {
    await tester.pumpWidget(_noteHarness(entries: _noteEntries));
    await tester.pumpAndSettle();

    for (final i in [0, 2, 3]) {
      expect(
          chartCellContent(
              i, 'note', find.byIcon(Icons.sticky_note_2_outlined)),
          findsNothing,
          reason: 'day $i carries no note text');
    }
  });

  testWidgets('tapping a note-indicator cell opens the day sheet',
      (tester) async {
    await tester.pumpWidget(_noteHarness(entries: _noteEntries));
    await tester.pumpAndSettle();

    await tester.tap(chartCell(1, 'note'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
    expect(sheet.day, _noteDay(1), reason: 'the tapped note cell owns day 1');
  });

  testWidgets(
      'the note row has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    await tester.pumpWidget(_noteHarness(entries: _noteEntries));
    await tester.pumpAndSettle();

    expect(chartCellCorner('note'), findsOneWidget);
    final tooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: chartCellCorner('note'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(tooltips, ['Note'],
        reason: 'the note corner carries the localized row name');

    final cornerCenter = tester.getRect(chartCellCorner('note')).center.dy;
    final cellCenter = tester.getRect(chartCell(1, 'note')).center.dy;
    expect(cornerCenter, closeTo(cellCenter, 0.5),
        reason: 'the note rail glyph is vertically centered on the row');

    await tester.pumpWidget(
        _noteHarness(entries: _noteEntries, locale: const Locale('de')));
    await tester.pumpAndSettle();
    final deTooltips = tester
        .widgetList<Tooltip>(find.descendant(
            of: chartCellCorner('note'), matching: find.byType(Tooltip)))
        .map((t) => t.message)
        .toList();
    expect(deTooltips, ['Notiz'], reason: 'de: the note row is "Notiz"');
  });

  testWidgets('the help sheet explains the note indicator (en and de)',
      (tester) async {
    await tester.pumpWidget(_noteHarness(entries: _noteEntries));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cycleHelpSheet')),
            matching: find.text('Note (this day carries a note in the Diary)')),
        findsOneWidget,
        reason: 'the indicator glyph needs a glossary entry');
  });

  testWidgets('the German help sheet explains the note indicator (de)',
      (tester) async {
    await tester.pumpWidget(
        _noteHarness(entries: _noteEntries, locale: const Locale('de')));
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

// ═══════════ rows ═══════════
// former test/cycle_chart_rows_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group(
      'paper layout: bleeding, mucus, M and sex at the top of the '
      'temperature block', () {
    testWidgets(
        'the top signal rows render INSIDE the chart block above the '
        'curve; cervix, pain and time stay below it', (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      for (final row in ['bleeding', 'mucus', 'mittelschmerz', 'sex']) {
        expect(tester.getRect(chartCell(0, row)).top, lessThan(chartTop),
            reason: 'the $row row renders in the TOP of the temperature '
                'block, above the curve (paper sheet)');
      }
      for (final row in ['time', 'disturbance', 'cervix', 'pain', 'note']) {
        expect(tester.getRect(chartCell(0, row)).top, greaterThan(chartBottom),
            reason: 'the $row row stays below the temperature block');
      }
    });

    testWidgets(
        'the rows render in the paper order — bleeding, mucus, M '
        '(Mittelschmerz directly beneath the mucus row), sex — and the '
        'below-chart strip follows with time first, notes last',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      double top(String row) => tester.getRect(chartCellCorner(row)).top;
      expect(
          ['bleeding', 'mucus', 'mittelschmerz', 'sex'].map(top).toList(),
          [
            ...['bleeding', 'mucus', 'mittelschmerz', 'sex'].map(top)
          ]..sort(),
          reason: 'M sits directly beneath the mucus row (paper sheet), '
              'sex after it, bleeding on top');
      // The below-chart strip keeps the owner-decided order (time first,
      // notes last): time, disturbance, cervix, pain, note after the top
      // segment and the curve.
      expect(top('time'),
          greaterThan(tester.getRect(chartCellCorner('sex')).bottom),
          reason: 'the below-chart strip starts after the top segment '
              'and the curve');
      expect(top('disturbance'), greaterThan(top('time')));
      expect(top('cervix'), greaterThan(top('disturbance')));
      expect(top('pain'), greaterThan(top('cervix')));
      expect(top('note'), greaterThan(top('pain')));
    });

    testWidgets(
        'the Mittelschmerz letter M renders in its own row beneath the '
        'mucus row; the pain row of the below-chart strip carries only B',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      // Day 4 = the fixture's Mittelschmerz day (beside its mucus S): the
      // M letter renders in the mittelschmerz cell, directly beneath the
      // day's mucus glyph.
      expect(
          chartCellContent(4, 'mittelschmerz', find.text('M')), findsOneWidget,
          reason: 'Mittelschmerz renders its M letter in its own row, '
              'directly beneath the mucus row (paper sheet)');
      expect(chartCellContent(4, 'pain', find.text('M')), findsNothing,
          reason: 'the M letter moved out of the strip\'s pain row — '
              'flagged with TODO(user-review) in the chart code');
      expect(chartCellContent(7, 'pain', find.text('B')), findsOneWidget,
          reason: 'breast pain B stays in the strip\'s pain row');
      expect(chartCellContent(7, 'mittelschmerz', find.text('M')), findsNothing,
          reason: 'no M without the Mittelschmerz flag');
    });

    testWidgets('tapping a top-block cell opens the day sheet', (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      await tester.tap(chartCell(4, 'mucus'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, _rowsDay(4),
          reason: 'the moved top-block mucus cell keeps its tap behavior');
    });
  });

  group('per-signal rows', () {
    testWidgets(
        'every signal row renders for every windowed day, in order '
        'bleeding, mucus, mittelschmerz, sex, time, disturbance, cervix, '
        'pain, note', (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      for (var i = 0; i < _dayCount; i++) {
        for (final row in _signalRows) {
          expect(chartCell(i, row), findsOneWidget,
              reason: 'row $row renders a cell for day index $i '
                  '(rows always render, even empty/untracked days)');
        }
      }

      // Row ORDER: the corner slots appear top-down bleeding .. note
      // (paper layout: the first four inside the top of the temperature
      // block, the rest in the below-chart strip, time first).
      final corners =
          _signalRows.map((row) => tester.getRect(chartCellCorner(row)));
      final tops = corners.map((r) => r.top).toList();
      expect(tops, equals([...tops]..sort()),
          reason: 'the signal rows render in the paper\'s order');
    });

    testWidgets(
        'each row\'s corner slot carries a sample glyph with a tooltip '
        'and a semantics label carrying the localized row name (en)',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
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
                of: chartCellCorner(key), matching: find.byType(Tooltip)))
            .map((t) => t.message)
            .toList();
        expect(tooltips, [value],
            reason: 'row $key\'s corner slot carries the localized row name');
        expect(
          find.descendant(
              of: chartCellCorner(key),
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
              of: chartCellCorner('bleeding'),
              matching: find.byType(Container)),
          findsOneWidget,
          reason: 'the bleeding corner shows the blob sample');
      expect(
          find.descendant(
              of: chartCellCorner('mucus'),
              matching: find.byType(MucusSymbolText)),
          findsOneWidget,
          reason: 'the mucus corner shows the glyph sample');
      // Plain S, no quality qualifier: the superscript renders as a
      // Text('EW') WidgetSpan child when one is set — it must be absent.
      final mucusSample = tester.widget<MucusSymbolText>(find.descendant(
          of: chartCellCorner('mucus'),
          matching: find.byType(MucusSymbolText)));
      expect(mucusSample.display.superscript, isNull,
          reason: 'the mucus corner sample is the plain S glyph');
      expect(
          find.descendant(
              of: chartCellCorner('mucus'), matching: find.text('EW')),
          findsNothing,
          reason: 'the mucus corner sample carries no EW superscript');
      expect(
          find.descendant(
              of: chartCellCorner('mittelschmerz'), matching: find.text('M')),
          findsOneWidget,
          reason: 'the mittelschmerz corner shows the M sample');
      expect(
          find.descendant(
              of: chartCellCorner('cervix'), matching: find.text('m')),
          findsOneWidget,
          reason: 'the cervix corner shows a position letter sample');
      expect(
          find.descendant(of: chartCellCorner('sex'), matching: find.text('X')),
          findsOneWidget,
          reason: 'the sex corner shows the X sample');
      expect(
          find.descendant(
              of: chartCellCorner('pain'), matching: find.text('B')),
          findsOneWidget,
          reason: 'the pain corner shows the B sample '
              '(the Mittelschmerz M has its own row/corner)');
      expect(
          find.descendant(
              of: chartCellCorner('pain'), matching: find.text('M')),
          findsNothing);
      expect(
          find.descendant(
              of: chartCellCorner('time'),
              matching: find.byIcon(Icons.schedule)),
          findsOneWidget,
          reason: 'the time corner keeps the clock icon sample');
    });

    testWidgets('the row names use the German wording in de', (tester) async {
      await tester.pumpWidget(
          _rowsHarness(entries: _rowsEntries, locale: const Locale('de')));
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
                of: chartCellCorner(key), matching: find.byType(Tooltip)))
            .map((t) => t.message)
            .toList();
        expect(tooltips, [value], reason: 'de: row $key is $value');
      }
    });

    testWidgets('long-pressing a corner slot shows the row-name tooltip',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
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

    testWidgets(
        'at minimum column width the time renders vertically — never '
        'dropped (wide columns keep the horizontal text, see the wide '
        'HH:mm test above and the measurement-time section)', (tester) async {
      Finder timeCellFinder() => find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('timeCell-'));

      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), below the horizontal threshold. The initial
      // auto-scroll puts the newest days' cells on screen.
      await tester.pumpWidget(_rowsHarness(entries: [
        for (var i = 0; i < 60; i++)
          DailyEntry(
            date: _rowsDay(i),
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
      expect(find.descendant(of: timeCellFinder(), matching: find.byType(Text)),
          findsWidgets);
    });

    testWidgets('no per-day clock icon exists anywhere in the signal rows',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      // The ONLY clock icon in the signal rows is the time row's corner
      // sample; the day cells never carry one (the old per-day clock
      // glyph is gone).
      for (var i = 0; i < _dayCount; i++) {
        expect(
            find.descendant(
                of: chartCell(i, 'time'),
                matching: find.byIcon(Icons.schedule)),
            findsNothing,
            reason: 'day $i: no clock icon in the time cell');
      }
      expect(
          find.descendant(
              of: chartCellCorner('time'),
              matching: find.byIcon(Icons.schedule)),
          findsOneWidget,
          reason: 'only the corner sample keeps a clock icon');
    });

    testWidgets('tapping a signal row cell opens the day\'s sheet',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      await tester.tap(chartCell(3, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, _rowsDay(3),
          reason: 'the tapped bleeding cell owns day 3');
    });

    testWidgets('the bleeding blob keeps the graded-opacity convention',
        (tester) async {
      await tester.pumpWidget(_rowsHarness(entries: _rowsEntries));
      await tester.pumpAndSettle();

      final errorColor =
          Theme.of(tester.element(chartCell(1, 'bleeding'))).colorScheme.error;

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

    // Cross-check at a narrow viewport (the same device class the diary
    // sign-row repro used): the mucus cell renders its glyph inside a
    // 12 px slot below the reserved 10 px peak-dot slot, top-aligned —
    // the fixed-height row rhythm is the design. The two widest glyph
    // shapes (the two-glyph f/S token, and the S glyph with its EW
    // superscript) must lay out without a framework exception at the
    // minimum usable column width (24 px, forced by a range longer than
    // the 320 dp viewport).
    testWidgets(
        'the mucus glyph renders at the minimum column width without a '
        'framework exception', (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final entries = [
        for (var i = 0; i < 12; i++)
          DailyEntry(
            date: _rowsDay(i),
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
        await tester.pumpWidget(_rowsHarness(entries: entries));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = originalOnError;
      }

      // The initial auto-scroll parks the window on the newest days, so
      // both mucus days render.
      expect(find.byKey(const ValueKey('mucusCell-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('mucusCell-11')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('mucusCell-10')),
              matching: find.byType(MucusSymbolText)),
          findsOneWidget,
          reason: 'the f/S day renders its glyph in the mucus row');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('mucusCell-11')),
              matching: find.byType(MucusSymbolText)),
          findsOneWidget,
          reason: 'the S+EW day renders its glyph in the mucus row');
      expect(errors, isEmpty,
          reason: 'the mucus glyphs must lay out without a framework '
              'exception at the minimum column width');
      expect(tester.takeException(), isNull);
    });
  });

// ═══════════ temperature curve ═══════════
// former test/cycle_chart_temperature_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('adjacent-day connectivity', () {
    testWidgets('two readings on adjacent days connect', (tester) async {
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bbtC: 36.6),
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'adjacent calendar days are drawn as one segment');
    });

    testWidgets('a day with no temperature between readings breaks the line',
        (tester) async {
      // Saturday has an entry, but WITHOUT a temperature, and a Sunday with
      // no entry at all behind it: neither gap may be bridged by the curve.
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bleeding: Bleeding.medium),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
        DailyEntry(date: _temperatureSun, bbtC: 36.8),
      ]));
      await tester.pumpAndSettle();

      expect(_spansAGap(tester), isFalse,
          reason: 'a measured day without temperature still breaks the line');
      // The measured days BEHIND the gap stay connected among themselves.
      expect(_connects(tester, 2, 3), isTrue,
          reason: 'adjacent readings after the gap still connect');
    });

    testWidgets('a day with no entry at all breaks the line too',
        (tester) async {
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ]));
      await tester.pumpAndSettle();

      // Both days are lone dots; nothing connects index 0 to index 2.
      expect(_spansAGap(tester), isFalse,
          reason: 'gap between day 0 and day 2: no segment may be drawn');
      expect(_connects(tester, 0, 2), isFalse);
    });
  });

  group('ignored temperatures render lighter (mark-keyed)', () {
    // Thu and Sat: ordinary measurements; Fri: a measured day carrying the
    // ignoreTemperature MARK (no raw flags needed — the mark is the
    // rendering key).
    final ignoredMiddle = <DailyEntry>[
      DailyEntry(date: _temperatureThu, bbtC: 36.5),
      DailyEntry(date: _temperatureFri, bbtC: 36.6),
      DailyEntry(date: _temperatureSat, bbtC: 36.7),
    ];
    final friMark = CycleMark(
        date: _temperatureFri, type: CycleMarkTypes.ignoreTemperature);

    /// The scheme color the chart derives its normal (opaque) color from.
    Color normalColor(WidgetTester tester) =>
        _themeOf(tester).colorScheme.primary;

    testWidgets('line stays continuous through the ignored day',
        (tester) async {
      await tester.pumpWidget(
          _temperatureHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 0, 1), isTrue,
          reason: 'ignored temperature counts as a measured day');
      expect(_connects(tester, 1, 2), isTrue,
          reason: 'the line continues through the ignored day');
    });

    testWidgets('segments touching the ignored day render lighter',
        (tester) async {
      await tester.pumpWidget(
          _temperatureHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        final color = bar.color!;
        expect(color.a, closeTo(0.4, 1e-6),
            reason: 'both segments touch the ignored day -> lighter tint');
        // Lighter = theme color at reduced alpha, not a different hue.
        expect(color.r, normalColor(tester).r);
        expect(color.g, normalColor(tester).g);
        expect(color.b, normalColor(tester).b);
      }
    });

    testWidgets('the ignored dot renders lighter, normal dots stay opaque',
        (tester) async {
      await tester.pumpWidget(
          _temperatureHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      final painterByIndex = <int, Color>{};
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final spot = dotBars.first.spots[i];
        final painter = dotBars.first.dotData
            .getDotPainter(spot, 0, dotBars.first, i) as FlDotCirclePainter;
        painterByIndex[spot.x.round()] = painter.color;
      }
      expect(painterByIndex[0]!.a, 1.0,
          reason: 'an ordinary measurement keeps the full-strength dot');
      final ignored = painterByIndex[1]!;
      expect(ignored.a, closeTo(0.4, 1e-6),
          reason: 'the ignored dot renders lighter');
      expect(ignored.r, normalColor(tester).r);
      expect(ignored.g, normalColor(tester).g);
      expect(ignored.b, normalColor(tester).b);
    });

    testWidgets(
        'a marked day WITHOUT disturbance flags renders lighter '
        '(the mark alone dims the curve)', (tester) async {
      // Headline new behavior (owner decision 2026-09-19): the mark is
      // the visible state, flags are surfaced by other means (diary
      // badge). Fri carries
      // ONLY the mark — no tempDisturbances — and still renders lighter.
      final unflaggedMarked = <DailyEntry>[
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bbtC: 36.6), // mask 0
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ];
      await tester.pumpWidget(
          _temperatureHarness(entries: unflaggedMarked, marks: [friMark]));
      await tester.pumpAndSettle();

      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      final painterByIndex = <int, Color>{};
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final spot = dotBars.single.spots[i];
        final painter = dotBars.single.dotData
            .getDotPainter(spot, 0, dotBars.single, i) as FlDotCirclePainter;
        painterByIndex[spot.x.round()] = painter.color;
      }
      expect(painterByIndex[1]!.a, closeTo(0.4, 1e-6),
          reason: 'a marked day WITHOUT flags renders lighter');
      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, closeTo(0.4, 1e-6),
            reason: 'both segments touch the marked day -> lighter tint');
      }
    });

    testWidgets(
        'a flagged day WITHOUT the mark renders at FULL alpha '
        '(deleting the mark restores normal rendering)', (tester) async {
      // THE FLIP (owner decision 2026-09-19): the mark can be deleted on
      // the day sheet while the raw flags remain — the curve renders
      // normally again (the flags are surfaced by the diary badge, not
      // the curve).
      final flaggedUnmarked = <DailyEntry>[
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(
            date: _temperatureFri,
            bbtC: 36.6,
            tempDisturbances: TempDisturbance.kr.bit),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ];
      await tester.pumpWidget(_temperatureHarness(entries: flaggedUnmarked));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, 1.0,
            reason: 'flags without the mark render at full alpha — the '
                'raw mask is no longer a rendering input');
      }
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final painter = dotBars.single.dotData
                .getDotPainter(dotBars.single.spots[i], 0, dotBars.single, i)
            as FlDotCirclePainter;
        expect(painter.color.a, 1.0,
            reason: 'the flagged-but-unmarked dot keeps the full-strength '
                'color');
      }
    });

    testWidgets(
        'a marked AND flagged day renders lighter (mark-keyed, even with '
        'raw flags)', (tester) async {
      // The typical interrupted day carries both: the raw mask (flags)
      // AND the manually placed ignoreTemperature mark — still lighter
      // (mark-keyed).
      final flaggedMarked = <DailyEntry>[
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(
            date: _temperatureFri,
            bbtC: 36.6,
            tempDisturbances: TempDisturbance.kr.bit),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ];
      await tester.pumpWidget(
          _temperatureHarness(entries: flaggedMarked, marks: [friMark]));
      await tester.pumpAndSettle();

      for (final bar in _segmentBars(tester)) {
        expect(bar.color!.a, closeTo(0.4, 1e-6),
            reason: 'marked + flagged renders lighter (the mark is the '
                'rendering key)');
      }
    });

    testWidgets('two consecutive ignored days connect with a lighter segment',
        (tester) async {
      // Thu and Fri both measured AND both ignored (marks): one segment,
      // but every part of it — line and both dots — renders lighter.
      final marks = [
        CycleMark(
            date: _temperatureThu, type: CycleMarkTypes.ignoreTemperature),
        friMark,
      ];
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bbtC: 36.6),
      ], marks: marks));
      await tester.pumpAndSettle();

      expect(_segmentBars(tester), hasLength(1),
          reason: 'the two adjacent ignored days form exactly one segment');
      final segment = _segmentBars(tester).single;
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment between two ignored days is lighter');
      expect(segment.color!.r, normalColor(tester).r);
      expect(segment.color!.g, normalColor(tester).g);
      expect(segment.color!.b, normalColor(tester).b);

      // Dots come from dot-only bars (invisible line): their per-spot dot
      // painters decide the color, so resolve one painter per spot.
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      expect(dotBars, hasLength(1), reason: 'one continuous measured run');
      for (var i = 0; i < dotBars.first.spots.length; i++) {
        final painter = dotBars.first.dotData.getDotPainter(
            dotBars.first.spots[i], 0, dotBars.first, i) as FlDotCirclePainter;
        expect(painter.color.a, closeTo(0.4, 1e-6),
            reason: 'ignored dot ${dotBars.first.spots[i].x.round()} '
                'renders lighter');
        expect(painter.color.r, normalColor(tester).r);
        expect(painter.color.g, normalColor(tester).g);
        expect(painter.color.b, normalColor(tester).b);
      }
    });

    testWidgets('ignored dot at a run edge connects to the adjacent normal day',
        (tester) async {
      // Fri: ignored; Sat: normal. The ignored edge day is still drawn
      // connected — adjacency, not the mark, decides connectivity.
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bbtC: 36.2),
        DailyEntry(date: _temperatureSat, bbtC: 37.0),
      ], marks: [
        friMark
      ]));
      await tester.pumpAndSettle();

      expect(_connects(tester, 1, 2), isTrue,
          reason: 'ignored run-edge day connects to its adjacent day');
      final segment = _segmentBars(tester)
          .firstWhere((bar) => bar.spots.length == 2 && bar.spots[0].x == 1);
      expect(segment.color!.a, closeTo(0.4, 1e-6),
          reason: 'the segment touching the ignored edge day is lighter');
    });

    testWidgets('ignored-temp segments stay dark in dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpWidget(
          _temperatureHarness(entries: ignoredMiddle, marks: [friMark]));
      await tester.pumpAndSettle();

      final darkScheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme;
      expect(_segmentBars(tester).map((b) => b.color!),
          everyElement(equals(darkScheme.primary.withValues(alpha: 0.4))),
          reason: 'dark scheme: light primary at reduced alpha, still led by '
              'the (bright) scheme color — readable on the dark surface');
      expect(darkScheme.primary.computeLuminance(), greaterThan(0.3),
          reason: 'the lighter segments keep darkness-readable contrast');
    });
  });

  group('adaptive chart height (span of the settings range)', () {
    double chartHeight(WidgetTester tester) =>
        tester.getRect(find.byType(LineChart)).height;

    testWidgets('the default 36–38 °C range keeps the base height of 260',
        (tester) async {
      // The default range spans 2 °C — inside the comfortable ~3 °C span,
      // so no growth regardless of the recorded values.
      await tester.pumpWidget(_temperatureHarness(entries: [
        for (var i = 0; i < 5; i++)
          DailyEntry(date: _temperatureThu.add(Duration(days: i)), bbtC: 36.5),
      ]));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(260, 0.5),
          reason: 'a comfortable ~2 °C range needs the base height');
    });

    testWidgets('the height grows with the range span', (tester) async {
      // The settings range 36.0..40.5 → span 4.5 °C: 260 base plus
      // 1.5 °C beyond the comfortable 3 °C at 80 px per degree.
      await tester.pumpWidget(_temperatureHarness(
        entries: [
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(date: _temperatureFri, bbtC: 40.0),
        ],
        range: const TemperatureRange(min: 36.0, max: 40.5),
      ));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(380, 0.5),
          reason: 'a 4.5 °C span grows the plot: 260 + (4.5 − 3) × 80');
    });

    testWidgets(
        'the height is capped — a wide settings range does not grow '
        'without bounds', (tester) async {
      // The window maximum 34.0..42.0 → span 8 °C, far past the growth
      // range.
      await tester.pumpWidget(_temperatureHarness(
        entries: [
          DailyEntry(date: _temperatureThu, bbtC: 34.5),
          DailyEntry(date: _temperatureFri, bbtC: 41.5),
        ],
        range: const TemperatureRange(min: 34.0, max: 42.0),
      ));
      await tester.pumpAndSettle();

      expect(chartHeight(tester), closeTo(400, 0.5),
          reason: 'the growth is capped at 400');
    });
  });

  group('fixed display range and boundary clipping', () {
    LineChartData data(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart)).data;

    /// The segment bar connecting day indexes [a] and [b].
    LineChartBarData segmentBar(WidgetTester tester, int a, int b) => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .firstWhere((bar) =>
            bar.spots.length == 2 &&
            bar.spots[0].x == a.toDouble() &&
            bar.spots[1].x == b.toDouble() &&
            bar.color != null &&
            bar.color!.a > 0);

    testWidgets(
        'the y bounds are the provider\'s range (default 36.0..38.0), '
        'never the data', (tester) async {
      // The record dips just below the fixed range's lower bound (35.9
      // vs 36.0) — under the old data-adaptive bounds such a low value
      // dragged the lower edge to the half degree below (35.5 here), so
      // this is where the old rounding would have moved the axis; the
      // settings range pins the bounds 36..38 regardless.
      await tester.pumpWidget(_temperatureHarness(entries: [
        DailyEntry(date: _temperatureThu, bbtC: 36.5),
        DailyEntry(date: _temperatureFri, bbtC: 37.0),
        DailyEntry(date: _temperatureSat, bbtC: 35.9),
      ]));
      await tester.pumpAndSettle();

      expect(data(tester).minY, 36.0,
          reason: 'the default range\'s lower bound is the fixed minY');
      expect(data(tester).maxY, 38.0,
          reason: 'the default range\'s upper bound is the fixed maxY');
    });

    testWidgets(
        'a fever above the range renders its curve VALUE clamped to '
        'exactly the upper boundary — the bounds never move', (tester) async {
      await tester.pumpWidget(_temperatureHarness(
        entries: [
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(date: _temperatureFri, bbtC: 39.5),
        ],
      ));
      await tester.pumpAndSettle();

      final segment = segmentBar(tester, 0, 1);
      expect(segment.spots[1].y, 38.0,
          reason: 'the clipped temperature stops AT the boundary 38.0');
      expect(segment.spots[0].y, 36.5,
          reason: 'the in-range neighbor keeps its raw value');

      // Axis bounds and (per the rail tests) the rail labels never move.
      expect(data(tester).minY, 36.0);
      expect(data(tester).maxY, 38.0);
    });

    testWidgets('a below-range value clamps to exactly the lower boundary',
        (tester) async {
      await tester.pumpWidget(_temperatureHarness(
        entries: [
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(date: _temperatureFri, bbtC: 35.0),
        ],
      ));
      await tester.pumpAndSettle();

      final segment = segmentBar(tester, 0, 1);
      expect(segment.spots[1].y, 36.0,
          reason: 'the clipped temperature stops AT the lower boundary 36.0');
      expect(data(tester).minY, 36.0, reason: 'the bounds never move');
    });

    testWidgets(
        'values exactly at the boundaries render unchanged (clamp '
        'passthrough)', (tester) async {
      await tester.pumpWidget(_temperatureHarness(
        entries: [
          DailyEntry(date: _temperatureThu, bbtC: 36.0),
          DailyEntry(date: _temperatureFri, bbtC: 38.0),
        ],
      ));
      await tester.pumpAndSettle();

      final segment = segmentBar(tester, 0, 1);
      expect(segment.spots[0].y, 36.0);
      expect(segment.spots[1].y, 38.0);
    });
  });

// ═══════════ measurement time, sex and pain ═══════════
// former test/cycle_chart_time_sex_pain_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group(
      'measurement time — its own row below the chart block, first in '
      'the below-chart strip', () {
    testWidgets(
        'the time row renders BELOW the chart block, at the strip\'s top '
        '— above the disturbance, cervix and pain rows — for every '
        'day with a recorded measurement time', (tester) async {
      await tester
          .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
      await tester.pumpAndSettle();

      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      // Own row below the block, first in the strip: the time row starts
      // after the chart, but above disturbance/cervix/pain (owner order:
      // time first in the below-chart strip).
      expect(tester.getRect(chartCell(0, 'time')).top, greaterThan(chartBottom),
          reason: 'the time row is not part of the chart block');
      expect(tester.getRect(chartCell(0, 'time')).bottom,
          lessThan(tester.getRect(chartCell(0, 'disturbance')).top),
          reason: 'the time row renders above the disturbance row');
      for (final row in ['cervix', 'pain']) {
        expect(tester.getRect(chartCell(0, 'time')).top,
            lessThan(tester.getRect(chartCell(0, row)).top),
            reason: 'the time row renders above the $row row — time is '
                'the first row of the below-chart strip');
      }
      // Every day with a recorded time renders its HH:mm (the fixture's
      // only recorded time is day 0).
      expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
    });

    testWidgets(
        'at minimum column width the time STILL renders — rotated '
        'vertically in its cell (regression: the time used to be dropped '
        'entirely at the space constraint)', (tester) async {
      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), far below the horizontal text threshold.
      // Give EVERY day a recorded measurement time so the narrow check
      // exercises the row everywhere.
      final entries = [
        for (var i = 0; i < 60; i++)
          DailyEntry(
            date: _timeSexPainDay(i),
            bbtC: 36.5,
            measuredAtMinutes: 6 * 60 + 30,
          ),
      ];
      await tester.pumpWidget(_timeSexPainHarness(entries: entries));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(59, 'time')).width, closeTo(24, 0.5),
          reason: 'precondition: columns at the minimum usable width');

      Finder timeCells() => find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('timeCell-'));

      // The time text survives the space constraint: every rendered time
      // cell carries the rotated HH:mm text (RotatedBox), never empty.
      final rotated = find.descendant(
          of: find
              .byWidgetPredicate((w) => w is RotatedBox && w.quarterTurns != 0),
          matching: find.text('06:30'));
      expect(rotated, findsWidgets,
          reason: 'at the minimum column width the time renders vertically '
              '— it is NEVER dropped');
      expect(
          find.descendant(of: timeCells(), matching: find.byType(RotatedBox)),
          findsWidgets,
          reason: 'the narrow cells rotate the time text');
    });

    testWidgets(
        'between the minimum and the threshold the time renders vertically '
        'too', (tester) async {
      // 25 days fit the viewport but leave only ~29 px per column — below
      // the threshold, so still vertical.
      final entries = [
        for (var i = 0; i < 25; i++)
          DailyEntry(
            date: _timeSexPainDay(i),
            bbtC: 36.5,
            measuredAtMinutes: 6 * 60 + 30,
          ),
      ];
      await tester.pumpWidget(_timeSexPainHarness(entries: entries));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(24, 'time')).width, closeTo(29, 1.5),
          reason: 'precondition: narrow, non-minimum column width');
      expect(
          find.descendant(
              of: chartCell(24, 'time'),
              matching: find.descendant(
                  of: find.byWidgetPredicate(
                      (w) => w is RotatedBox && w.quarterTurns != 0),
                  matching: find.text('06:30'))),
          findsOneWidget,
          reason: 'a ~29 px column also renders the time vertically');
    });

    testWidgets('wide columns render the time horizontally, unrotated',
        (tester) async {
      await tester
          .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
      await tester.pumpAndSettle();

      expect(tester.getRect(chartCell(0, 'time')).width, greaterThan(32),
          reason: 'precondition: a wide column');
      expect(
          find.descendant(
              of: chartCell(0, 'time'), matching: find.byType(RotatedBox)),
          findsNothing,
          reason: 'a wide column keeps the horizontal HH:mm text');
      expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
    });
  });
  testWidgets(
      'the measurement time renders localized HH:mm text on days '
      'with a recorded measurement time — and nothing elsewhere',
      (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    // 8+1 chart days fit the viewport comfortably, so the columns are wide
    // enough for the time text.
    expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget,
        reason: 'the temperature day WITH a recorded time shows the HH:mm '
            'text in its own time cell');
    expect(chartCellContent(1, 'time', find.text('06:30')), findsNothing,
        reason: 'a temperature WITHOUT a recorded time shows no time text');
    expect(chartCellContent(2, 'time', find.byType(Text)), findsNothing,
        reason: 'a temperature-free day can never carry a measurement time '
            '(the domain drops the time without a temperature)');
    expect(chartCellContent(6, 'time', find.byType(Text)), findsNothing,
        reason: 'a plain temperature day without a time shows nothing');
    expect(
        chartCellContent(2, 'time', find.byIcon(Icons.schedule)), findsNothing,
        reason: 'no per-day clock icon — the clock lives only in the row '
            'corner slot');
  });

  testWidgets('the German locale renders the German HH:mm form',
      (tester) async {
    await tester.pumpWidget(_timeSexPainHarness(
        entries: _timeSexPainEntries(), locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: chartCell(0, 'time'), matching: find.text('06:30')),
        findsOneWidget,
        reason: 'the German locale keeps the padded HH:mm form');
  });

  testWidgets('sex renders X marks only on days with recorded time slots',
      (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(2, 'sex', find.text('X')), findsOneWidget,
        reason: 'the sex day shows the X glyph in its own cell');
    expect(chartCellContent(0, 'sex', find.text('X')), findsNothing,
        reason: 'no X on a temperature day without sex');
    expect(chartCellContent(6, 'sex', find.text('X')), findsNothing);
  });

  testWidgets(
      'every set sex time slot renders its own X — multiple slots '
      'render multiple X marks on one day', (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(5, 'sex', find.text('X')), findsNWidgets(2),
        reason: 'two recorded slots (start + end) render two X marks');
    expect(chartCellContent(2, 'sex', find.text('X')), findsOneWidget,
        reason: 'a single recorded slot renders exactly one X');
  });

  testWidgets('each X sits at its slot\'s third of the day column',
      (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    double fractionOf(Rect cell, Rect glyph) =>
        (glyph.center.dx - cell.left) / cell.width;

    final cell2 = tester.getRect(chartCell(2, 'sex'));
    final startX = tester.getRect(chartCellContent(2, 'sex', find.text('X')));
    expect(fractionOf(cell2, startX), closeTo(1 / 6, 0.05),
        reason: 'a start-slot X renders in the START third (center ~1/6) of '
            'the day column');

    final cell5 = tester.getRect(chartCell(5, 'sex'));
    final xRects =
        chartCellContent(5, 'sex', find.text('X')).evaluate().map((element) {
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

  testWidgets(
      'pain renders B in its row; Mittelschmerz renders M in its '
      'own row beneath the mucus row', (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(3, 'pain', find.text('B')), findsOneWidget,
        reason: 'breast pain shows the B letter in the pain row');
    expect(chartCellContent(3, 'pain', find.text('M')), findsNothing,
        reason: 'no Mittelschmerz letter without the flag — and the M '
            'letter home is its own row anyway');
    expect(chartCellContent(4, 'mittelschmerz', find.text('M')), findsOneWidget,
        reason: 'Mittelschmerz shows the M letter in its own row beneath '
            'the mucus row (flagged TODO(user-review) in the chart code)');
    expect(chartCellContent(4, 'pain', find.text('M')), findsNothing,
        reason: 'the M letter no longer renders in the pain row');
    expect(chartCellContent(4, 'pain', find.text('B')), findsNothing,
        reason: 'no breast letter without the flag');
    expect(chartCellContent(5, 'pain', find.text('B')), findsOneWidget);
    expect(
        chartCellContent(5, 'mittelschmerz', find.text('M')), findsOneWidget);
    expect(chartCellContent(6, 'pain', find.text('B')), findsNothing,
        reason: 'a plain day shows no pain letter');
    expect(chartCellContent(6, 'mittelschmerz', find.text('M')), findsNothing);
  });

  testWidgets(
      'a combined day carries the sex X marks alongside both pain '
      'letters (B in the pain row, M beneath the mucus row)', (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(5, 'sex', find.text('X')), findsNWidgets(2),
        reason: 'the sex X marks render in their own row');
    expect(chartCellContent(5, 'pain', find.text('B')), findsOneWidget,
        reason: 'the pain letter renders in its own row beside the sex '
            'row');
    expect(chartCellContent(5, 'mittelschmerz', find.text('M')), findsOneWidget,
        reason: 'the Mittelschmerz letter renders in its own row beneath '
            'the mucus row');
  });

  testWidgets(
      'a firmness-only day renders its glyph with no position '
      'letters', (tester) async {
    await tester
        .pumpWidget(_timeSexPainHarness(entries: _timeSexPainEntries()));
    await tester.pumpAndSettle();

    expect(chartCellContent(7, 'cervix', find.text('w')), findsOneWidget,
        reason: 'the soft-firmness glyph (paper shorthand w) renders in its '
            'own cell');
    for (final glyph in ['t', 'm', 'h', 'sh', 'u']) {
      expect(chartCellContent(7, 'cervix', find.text(glyph)), findsNothing,
          reason: 'no position letter ($glyph) without a position '
              'observation');
    }
  });

// ═══════════ weekend bands ═══════════
// former test/cycle_chart_weekend_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets('weekend columns get background bands, weekday columns none',
      (WidgetTester tester) async {
    await tester.pumpWidget(_weekendHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester).toList()
      ..sort((a, b) => a.x1.compareTo(b.x1));

    // Exactly the two weekend days (Sat & Sun) are band, nothing else.
    expect(bands, hasLength(2));
    // Day i sits at chart x = i with a half-day band width around it.
    expect(bands[0].x1, closeTo(1.5, 1e-9), reason: 'Saturday (day index 2)');
    expect(bands[0].x2, closeTo(2.5, 1e-9));
    expect(bands[1].x1, closeTo(2.5, 1e-9), reason: 'Sunday (day index 3)');
    expect(bands[1].x2, closeTo(3.5, 1e-9));
  });

  // Degenerate case: one recorded day, and it is a weekend day. The chart
  // keeps a one-column-wide domain window (−0.5..0.5), so the lone day's
  // full column (−0.5..0.5) lies inside the plot and the band keeps its
  // full width — no clamp may collapse it to zero.
  testWidgets('single-day weekend chart still renders one band, positive width',
      (WidgetTester tester) async {
    await tester.pumpWidget(_weekendHarness(
      entries: [DailyEntry(date: _weekendSat, bbtC: 36.7)],
      selected: _weekendSat,
    ));
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, hasLength(1), reason: 'the lone Saturday gets its band');
    // fl_chart requires x1 < x2; zero width would paint nothing.
    expect(bands.single.x2, greaterThan(bands.single.x1));
    expect(bands.single.x1, closeTo(-0.5, 1e-9),
        reason: 'the lone column spans −0.5..0.5 in the shifted domain');
    expect(bands.single.x2, closeTo(0.5, 1e-9));
  });

  // Edge clamps: the band annotation clamps to the shifted plot bounds
  // (−0.5 .. dayCount − 0.5). A weekend on the FIRST day extends to the
  // plot's left edge, a weekend on the LAST day to the plot's right edge —
  // both keep their full column width instead of being cut back to the
  // day indexes.
  testWidgets('a weekend on the first day extends to the plot\'s left edge',
      (WidgetTester tester) async {
    // Sat (first day) .. Sun (last day): both bands touch a plot edge.
    await tester.pumpWidget(_weekendHarness(
      entries: [
        DailyEntry(date: _weekendSat, bbtC: 36.7),
        DailyEntry(date: _weekendSun, bbtC: 36.7)
      ],
      selected: _weekendSat,
    ));
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester).toList()
      ..sort((a, b) => a.x1.compareTo(b.x1));
    expect(bands, hasLength(2));
    expect(bands[0].x1, closeTo(-0.5, 1e-9),
        reason: 'the first day\'s band reaches the plot\'s left edge (−0.5)');
    expect(bands[0].x2, closeTo(0.5, 1e-9));
    expect(bands[1].x1, closeTo(0.5, 1e-9),
        reason: 'the last day\'s band reaches the plot\'s right edge '
            '(dayCount − 0.5 = 1.5)');
    expect(bands[1].x2, closeTo(1.5, 1e-9));
  });

  testWidgets('band color is a subtle tint that follows the theme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_weekendHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, isNotEmpty);
    for (final band in bands) {
      // A whisper, not a wallpaper: mostly transparent over the surface.
      final color = _bandColor(band);
      expect(color.a, greaterThan(0.0));
      expect(color.a, lessThan(0.15));
    }
  });

  // Dark mode as its own test: the platform brightness is set BEFORE the
  // first pump (the pump-before-dark trick the theme-mode dark tests use, since a
  // mid-test dispatcher change does not rebuild the theme in the test env).
  testWidgets('dark mode: the band tint is a light overlay on the dark scheme',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_weekendHarness());
    await tester.pumpAndSettle();

    final bands = _weekendBands(tester);
    expect(bands, isNotEmpty);
    for (final band in bands) {
      final color = _bandColor(band);
      expect(color.a, greaterThan(0.0));
      expect(color.a, lessThan(0.15));
      // Dark-mode tint is a light overlay (high relative luminance), so it
      // contrasts against the dark chart surface instead of disappearing.
      expect(
        color.computeLuminance(),
        greaterThan(0.3),
        reason: 'dark-mode weekend tint should lean on the dark scheme',
      );
    }
  });

// ═══════════ windowing ═══════════
// former test/cycle_chart_windowing_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  group('long recorded range', () {
    testWidgets('the first data frame auto-scrolls to the newest days',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      // The newest days sit at the content's right edge, so the initial
      // auto-scroll jumped the viewport to the maximum scroll extent: the
      // last day column fills the window, the earliest days are off-screen.
      expect(_bleedingCell(149), findsOneWidget,
          reason: 'the newest days fill the viewport after the first frame');
      expect(_bleedingCell(0), findsNothing,
          reason: 'the earliest days are outside the initial window');

      // The jump is instant (no animation): the offset sits at the maximum
      // extent already after the settle.
      final state = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, greaterThan(0),
          reason: '150 day columns need more width than the viewport provides');
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the initial auto-scroll jumps straight to the newest days');
    });

    testWidgets('the chart block scrolls horizontally', (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      final scrollView = chartScrollView();
      expect(scrollView, findsOneWidget,
          reason: 'the whole chart block is horizontally scrollable');
      final state = tester.state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, greaterThan(0),
          reason: '60 day columns need more width than the viewport provides');
    });

    testWidgets('dragging scrolls the window; y bounds stay global',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      // The initial window sits at the newest days; drag BACK toward the
      // earliest days and assert the window follows the scroll. The drag
      // exceeds the maximum scroll extent, so it settles at the content's
      // start (the earliest days).
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      expect(_bleedingCell(149), findsNothing,
          reason: 'the newest days scrolled out of the window');
      expect(_bleedingCell(0), findsOneWidget,
          reason: 'the earliest days appear once scrolled to');

      // The temperature scale must NOT rescale per window: the y bounds are
      // the fixed settings-derived range (default 36..38 °C, well above the
      // coldest recorded day here), so the curve keeps its absolute heights
      // while scrolling.
      final chartMinY =
          tester.widget<LineChart>(find.byType(LineChart)).data.minY;
      final recordedValues = _manyEntries().map((e) => e.bbtC!).toList();
      expect(chartMinY,
          lessThanOrEqualTo(recordedValues.reduce((a, b) => a < b ? a : b)),
          reason: 'the y scale still covers the coldest recorded day');
    });

    testWidgets('a later entries re-emit never re-runs the initial auto-scroll',
        (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(_windowingHarness(
          entries: _manyEntries(), entriesStream: controller.stream));
      controller.add(_manyEntries());
      await tester.pumpAndSettle();

      final state = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the first data frame jumped to the newest days');

      // Drag away from the end toward earlier days (deep enough that the
      // wide window margin no longer reaches the range's end). A timed
      // drag has no fling momentum, so the settled offset is
      // deterministic.
      await tester.timedDrag(chartScrollView(), const Offset(900, 0),
          const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final offsetAfterDrag = state.position.pixels;
      expect(offsetAfterDrag, lessThan(state.position.maxScrollExtent));

      // Emit a NEW list instance (one extra day at the end): the user's
      // scrolled position must survive — no re-jump back to the end.
      controller.add(
          [..._manyEntries(), DailyEntry(date: longRangeDay(150), bbtC: 36.5)]);
      await tester.pumpAndSettle();

      expect(state.position.pixels, offsetAfterDrag,
          reason: 'a later re-emit must not re-run the initial auto-scroll');
      expect(_bleedingCell(149), findsNothing,
          reason: 'the view stayed where the user dragged it, not at the end');
      // The dragged-to window still renders: at the dragged offset the
      // visible window starts around floor(offset / columnWidth) — the
      // scroll content leads directly with day column 0 (the y scale lives
      // in the frozen rail outside the scroll), so the offset maps onto
      // the column grid without any leading-strip subtraction.
      final firstVisible = (offsetAfterDrag / _columnWidth).floor();
      expect(_bleedingCell(firstVisible + 2), findsOneWidget,
          reason: 'the dragged-to window cells are still rendered');
    });

    testWidgets(
        'an empty first frame does not jump; the first non-empty '
        'frame mounts the chart and jumps', (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(_windowingHarness(
          entries: _manyEntries(), entriesStream: controller.stream));
      controller.add(const <DailyEntry>[]);
      await tester.pumpAndSettle();

      // No data: the chart block is not built at all, so there is nothing
      // to jump (the screen shows its no-data state instead).
      expect(chartScrollView(), findsNothing);

      controller.add(_manyEntries());
      await tester.pumpAndSettle();

      // The first NON-EMPTY data frame mounts the chart and auto-scrolls
      // to the newest days.
      final state = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      expect(state.position.pixels, state.position.maxScrollExtent,
          reason: 'the first non-empty data frame jumps to the newest days');
      expect(_bleedingCell(149), findsOneWidget);
    });

    testWidgets(
        'a freshly parked window carries one extra screen-width of margin '
        'past the visible edges, not further', (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      final state = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      // The scroll viewport: block width (800 test viewport, 12 body
      // padding on each side) minus the frozen rail left of the scroll.
      const scrollViewport = 800.0 - 2 * 12 - 44; // 732
      final marginDays = (scrollViewport / _columnWidth).ceil(); // 31

      // Fresh park 1: the initial auto-scroll landed at the newest days;
      // the left margin is unclamped and ends exactly one extra
      // screen-width before the leftmost visible edge.
      final maxExtent = state.position.maxScrollExtent;
      final freshVisible = (maxExtent / _columnWidth).floor();
      expect(_bleedingCell(freshVisible - 1 - marginDays), findsOneWidget,
          reason: 'a full extra screen-width of margin renders before the '
              'visible edge of a freshly parked window');
      expect(_bleedingCell(freshVisible - 2 - marginDays), findsNothing,
          reason: 'the fresh park is bounded: the window does not extend '
              'past one extra screen-width');

      // Fresh park 2: a long jump (the jump-to-date landing does the same)
      // re-parks the window around the landed position: both margins
      // extend exactly one extra screen-width past the visible edges.
      // Day cell i spans [i * 24, (i + 1) * 24).
      state.position.jumpTo(1000.0);
      await tester.pumpAndSettle();
      expect(state.position.pixels, 1000.0,
          reason: 'precondition: the jump landed at the exact offset');
      final firstVisible = (1000.0 / _columnWidth).floor();
      final lastVisible = ((1000.0 + scrollViewport) / _columnWidth).ceil() - 1;
      expect(_bleedingCell(firstVisible - 1 - marginDays), findsOneWidget,
          reason: 'the re-parked window carries the screen-width margin '
              'before the visible edge');
      expect(_bleedingCell(firstVisible - 2 - marginDays), findsNothing,
          reason: 'the re-parked window stays bounded at the margin');
      expect(_bleedingCell(lastVisible + 1 + marginDays), findsOneWidget,
          reason: 'the re-parked window carries the screen-width margin '
              'past the visible right edge');
      expect(_bleedingCell(lastVisible + 2 + marginDays), findsNothing,
          reason: 'the re-parked window stays bounded at the margin');
    });

    testWidgets(
        'a small scroll stays inside the parked window — the window is '
        'not rebuilt for travel the margin absorbs', (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      final state = tester.state<ScrollableState>(find.descendant(
          of: chartScrollView(), matching: find.byType(Scrollable)));
      const scrollViewport = 800.0 - 2 * 12 - 44; // 732
      final marginDays = (scrollViewport / _columnWidth).ceil();
      final maxExtent = state.position.maxScrollExtent;
      final freshVisible = (maxExtent / _columnWidth).floor();
      final parkedStart = freshVisible - 1 - marginDays;
      expect(parkedStart, greaterThan(0),
          reason: 'precondition: the parked margin is unclamped here');

      // Travel 240 px (ten columns) — well within one extra screen-width
      // of margin: the visible edge moves, but the parked window around it
      // still covers the viewport with seam margin to spare.
      state.position.jumpTo(maxExtent - 240.0);
      await tester.pumpAndSettle();

      // The parked window keeps sitting at the SAME boundary — it was not
      // re-parked around the new position (that is what keeps the rebuild
      // rare during a fling).
      expect(_bleedingCell(parkedStart), findsOneWidget);
      expect(_bleedingCell(parkedStart - 1), findsNothing,
          reason: 'the parked window did not follow the small scroll — '
              'the margin absorbs the travel');

      // The seam guarantee still holds at the new position: the leftmost
      // visible day and the day before it render.
      final visible = (state.position.pixels / _columnWidth).floor();
      expect(_bleedingCell(visible), findsOneWidget);
    });

    testWidgets(
        'the jump-to-date affordance sits in the AppBar actions, next to '
        'the info action', (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      final jump = find.byKey(const ValueKey('calendarJumpButton'));
      final info = find.byKey(const ValueKey('cycleHelpAction'));
      expect(find.ancestor(of: jump, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the jump affordance moved into the AppBar actions');
      expect(find.ancestor(of: info, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the info action stays in the AppBar beside it');
      expect(tester.getCenter(jump).dx, lessThan(tester.getCenter(info).dx),
          reason: 'the jump affordance renders before the info action');
      expect(find.ancestor(of: jump, matching: find.byType(ListView)),
          findsNothing,
          reason: 'the wasted standalone row above the chart block is gone — '
              'the affordance no longer renders inside the screen body');
    });

    testWidgets('jump-to-date: picking a date moves the window onto it',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      // Drag to the content's start first: the picker opens on the
      // leftmost day of the window (the day the user is looking at), so
      // with the window parked at the earliest days it opens on January —
      // independent of how wide the window margin sits behind the visible
      // edge.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget,
          reason: 'the affordance opens the material date picker');
      // Day index of 2026-01-20 = 19. The material picker confirms a day
      // selection through its OK button.
      await tester.tap(find.text('20').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_bleedingCell(19), findsOneWidget,
          reason: 'the picked day is now inside the rendered window');
      expect(_bleedingCell(149), findsNothing,
          reason: 'the window jumped away from where it was');
    });

    testWidgets('tapping the curve in the scrolled window opens the day sheet',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      // Scroll to the end (content is much wider than the viewport, so a
      // large leftward drag lands at maxScrollExtent).
      await tester.drag(chartScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Content is 60 day columns, no leading strip (the temperature scale
      // lives in the frozen rail left of the scroll view); at max scroll
      // the last day (index 59) sits at the content's right edge. Tap the
      // day column of index 58 (= 2026-02-28) inside the visible area. The
      // chart's x domain is half a column shifted, so day 58's column
      // center maps to tap x = colW * (58 + 0.5).
      const railWidth = 44.0; // the frozen rail left of the scroll view
      const testViewportWidth = 800.0;
      const bodyPadding = 12.0;
      const scrollViewport =
          testViewportWidth - 2 * bodyPadding - railWidth; // 732
      const contentWidth = 60 * 24.0; // 1440
      const maxOffset = contentWidth - scrollViewport; // 708
      final tapContentX = 24.0 * (58 + 0.5);
      final tapScreenX =
          bodyPadding + railWidth + (tapContentX - maxOffset); // 752
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.tapAt(Offset(tapScreenX, chartTop + 100));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'a tap in the scrolled window still opens the day sheet');
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, DateTime.utc(2026, 2, 28),
          reason: 'the tapped chart column maps to day index 58');
    });

    testWidgets('a long press on the curve opens the day sheet too',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: longRangeEntries()));
      await tester.pumpAndSettle();

      await tester.drag(chartScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Same column mapping as the tap above (day 58's column center at
      // colW * (58 + 0.5), content = 60 columns without a strip); the
      // long-press behaves identically to the tap.
      const railWidth = 44.0; // the frozen rail left of the scroll view
      const bodyPadding = 12.0;
      const contentWidth = 60 * 24.0;
      const maxOffset = contentWidth - (800.0 - 2 * bodyPadding - railWidth);
      final tapContentX = 24.0 * (58 + 0.5);
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.longPressAt(Offset(
          bodyPadding + railWidth + (tapContentX - maxOffset), chartTop + 100));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.widget<CycleDaySheet>(find.byType(CycleDaySheet));
      expect(sheet.day, DateTime.utc(2026, 2, 28));
    });
  });

  group('the 1–6 numbering row is windowed like the signal rows', () {
    testWidgets('only the scroll window\'s numbering cells render',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      // The initial auto-scroll parks the window at the newest days: only
      // the window's numbering cells are built — a 150-day range must not
      // keep one cell per calendar day alive off-screen.
      expect(_marksCell(149), findsOneWidget,
          reason: 'the newest days fill the window after the first frame');
      expect(_marksCell(0), findsNothing,
          reason: 'the earliest days are outside the initial window');

      // Drag back to the earliest days: the numbering window follows the
      // scroll, like the signal rows it mirrors.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();
      expect(_marksCell(0), findsOneWidget,
          reason: 'the numbering cells appear once their days scroll in');
      expect(_marksCell(149), findsNothing,
          reason: 'the newest days are outside the window after the drag');
    });

    testWidgets(
        'the windowed numbering cells keep their global column positions',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _manyEntries()));
      await tester.pumpAndSettle();

      // The window spacer (the signal rows' pattern) keeps cell i at its
      // global column position: wherever the window starts, the numbering
      // cell of a day sits exactly at the same column as that day's
      // signal-row cell.
      void expectSharedColumn(int index) {
        final marksX = tester.getTopLeft(_marksCell(index)).dx;
        final bleedingX = tester.getTopLeft(_bleedingCell(index)).dx;
        expect(marksX, closeTo(bleedingX, 0.5),
            reason: 'numbering cell $index keeps its global column position '
                '(window spacer, like the signal rows)');
      }

      // The initial window sits at the newest days ...
      expectSharedColumn(130);
      // ... and the dragged-to window at the earliest days.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();
      expectSharedColumn(10);
    });
  });

  group('short recorded range (5 days)', () {
    testWidgets('every day cell is rendered and nothing is scrollable',
        (tester) async {
      await tester.pumpWidget(_windowingHarness(entries: _shortEntries()));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(_bleedingCell(i), findsOneWidget,
            reason: 'a short range fits usefully on one screen');
      }

      final scrollView = chartScrollView();
      expect(scrollView, findsOneWidget,
          reason: 'the chart is still laid out as one scrollable block');
      final state = tester.state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)));
      expect(state.position.maxScrollExtent, 0,
          reason: '5 comfortable day columns fit the viewport exactly');
    });
  });

// ═══════════ window rebuild pace ═══════════
// former test/cycle_chart_window_rebuild_test.dart (bodies concatenated verbatim; see
// the file header for the merge mechanics)

  testWidgets(
      'scrolling a long distance re-windows the chart only a handful of '
      'times, not once per day column', (tester) async {
    final entries = _windowRebuildEntries();
    // No theme wiring here: the test counts window rebuilds, not looks.
    await tester.pumpWidget(chartHarness(entries: entries, themed: false));
    await tester.pumpAndSettle();

    // Travel 2000 px in 10 px steps (one pump per step): with a parked
    // window carrying an extra screen-width of margin (31 columns at this
    // viewport), the window needs re-parking only every extra screen-width
    // of travel — once per active edge — not once per day column.
    var reWindows = 0;
    var built = _builtCells(tester);
    const steps = 200;
    final gesture =
        await tester.startGesture(tester.getCenter(chartScrollView().first));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(10, 0)); // toward earlier days
      await tester.pump(const Duration(milliseconds: 16));
      final now = _builtCells(tester);
      if (!setEquals(now, built)) {
        reWindows++;
        built = now;
      }
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Measured improvement trail: without windowing/margin this 2000 px
    // scroll caused 200 window rebuilds; with the parked screen-width
    // margin ≤2 were observed — the bound of 6 is headroom for the parked
    // window's two edges and the range's clamped edges.
    expect(reWindows, lessThanOrEqualTo(6),
        reason: 'a 2000 px scroll must re-window only a handful of times '
            '(the parked margin absorbs the travel); observed $reWindows');
  });
}
