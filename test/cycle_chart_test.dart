// Widget tests of the cycle chart on the Zyklus screen — the whole
// chart family in one file: grid alignment, the merged below-chart
// notes band, per-day column labels, the temperature-disturbance
// letters, the computed evaluation marks (mucus-peak/first-higher-based
// candidates, numbering, baseline segment, SUZ), the grid lines
// (vertical day lines plus the 0.1 K horizontal temperature grid over
// the fixed settings range), the symbol help sheet, the frozen left
// rail, the per-signal rows, the temperature curve's connectivity and
// ignore rendering (the unit-level curve runs stay
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

import 'dart:async';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/bleeding_symbol.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';
import 'support/provider_fixtures.dart';

// Widget tests of the cycle chart's grid alignment invariant: day i's
// temperature dot lands exactly at the horizontal CENTER of its day column
// — the same center the day-label row and the signal rows use. The chart
// block's scroll content holds ONLY the day
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

// Widget tests of the Muttermund (cervix) display in the Zyklus chart's
// notes band: on every cervix day the band reserves the same top block —
// the glyph zone with 5 fixed position slots (low lowest … veryHigh
// highest, unreachable beyond) and the fixed letter row beneath it — so
// the position evolution stays comparable at a glance whatever the note.
// The glyph zone's ink is the OPENING circle, painted circle geometry
// sized by its value (the painted diameter communicates the opening, like
// the course notation). A position value without an opening paints
// nothing — the position only picks the slot.
// The firmness letter renders iff a value exists and never moves the
// slot ink; the breast-pain B sits in its own plain-letter row directly
// above the note zone (at the band top on cervix-free days, not
// reserved on pain-free days); the note zone takes the band's rest,
// spanning the full band on cervix-free pain-free days.

DateTime _cervixDay(int index) => DateTime.utc(2026, 9, 7 + index);

// One cervix-observation shape per day (0..10):
//  0: low + closed + soft        → filled dot in the lowest slot, letter row
//  1: medium + middle            → middle circle one slot higher
//  2: high + open                → open circle higher still
//  3: veryHigh + open + halfSoft → open circle in the topmost reachable slot
//  4: unreachable + open         → open circle in the unreachable (topmost) slot
//  5: opening open only          → open circle at the medium slot
//  6: position medium only       → nothing paints (position has no glyph)
//  7: firmness soft only         → only the letter-row 'w', no slot ink
//  8: breast pain + a long multi-line note, no cervix → the B pain row at
//    the band top, the note zone below it
//  9: medium + soft + a long note → the note zone renders below the fixed
//    letter row, the slot ink never moves
// 10: medium + soft + a whitespace-only note → the note folds to no text
//    and the day renders exactly like its cervix observations alone
// 11: medium + soft + breast pain + a note → the B pain row sits between
//    the letter row and the note zone, nothing in the cervix stack moves
List<DailyEntry> _cervixEntries() => [
  DailyEntry(
    date: _cervixDay(0),
    bbtC: 36.5,
    cervixPosition: CervixPosition.low,
    cervixOpening: CervixOpening.closed,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(
    date: _cervixDay(1),
    bbtC: 36.6,
    cervixPosition: CervixPosition.medium,
    cervixOpening: CervixOpening.middle,
  ),
  DailyEntry(
    date: _cervixDay(2),
    bbtC: 36.7,
    cervixPosition: CervixPosition.high,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: _cervixDay(3),
    bbtC: 36.8,
    cervixPosition: CervixPosition.veryHigh,
    cervixOpening: CervixOpening.open,
    cervixFirmness: CervixFirmness.halfSoft,
  ),
  DailyEntry(
    date: _cervixDay(4),
    bbtC: 36.9,
    cervixPosition: CervixPosition.unreachable,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: _cervixDay(5),
    bbtC: 37.0,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: _cervixDay(6),
    bbtC: 36.4,
    cervixPosition: CervixPosition.medium,
  ),
  DailyEntry(
    date: _cervixDay(7),
    bbtC: 36.5,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(
    date: _cervixDay(8),
    bbtC: 36.6,
    painBreast: true,
    notes:
        'Impfung nachgekauft (Rückfrage bei Dr. Wild) '
        '\nArztbesuche nachtragen',
  ),
  DailyEntry(
    date: _cervixDay(9),
    bbtC: 36.7,
    cervixPosition: CervixPosition.medium,
    cervixFirmness: CervixFirmness.soft,
    notes: 'Nachkontrolle beim Frauenarzt',
  ),
  DailyEntry(
    date: _cervixDay(10),
    bbtC: 36.8,
    cervixPosition: CervixPosition.medium,
    cervixFirmness: CervixFirmness.soft,
    notes: ' \n ',
  ),
  DailyEntry(
    date: _cervixDay(11),
    bbtC: 36.9,
    cervixPosition: CervixPosition.medium,
    cervixFirmness: CervixFirmness.soft,
    painBreast: true,
    notes: 'Beim Sport gezogen',
  ),
];

Widget _cervixHarness({required List<DailyEntry> entries}) => chartHarness(
  entries: entries,
  darkTheme: true,
  scopeInsideMaterialApp: true,
);

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

List<DailyEntry> _dayLabelsEntries(
  int count, {
  Map<int, Bleeding> bleeding = const {},
}) => [
  for (var i = 0; i < count; i++)
    DailyEntry(
      date: _dayLabelsDay(i),
      bbtC: 36.5,
      bleeding: bleeding[i] ?? Bleeding.none,
    ),
];

// A recorded range starting `start` (unlike _dayLabelsDay above, so month-first
// scenarios can begin on other calendar days).
DateTime _dayFrom(DateTime start, int index) =>
    start.add(Duration(days: index));

List<DailyEntry> _entriesFrom(
  DateTime start,
  int count, {
  Map<int, Bleeding> bleeding = const {},
}) => [
  for (var i = 0; i < count; i++)
    DailyEntry(
      date: _dayFrom(start, i),
      bbtC: 36.5,
      bleeding: bleeding[i] ?? Bleeding.none,
    ),
];

Finder _dayLabel(int index) => find.byKey(ValueKey('dayLabel-$index'));

Finder _label(int index, String text) => find.descendant(
  of: find.byKey(ValueKey('dayLabel-$index')),
  matching: find.text(text),
);

Widget _dayLabelsHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  Locale locale = const Locale('en'),
}) => chartHarness(entries: entries, marks: marks, locale: locale);

// Widget tests of the temperature-disturbance letters in the cycle
// chart's below-chart strip: a day carrying one of the NER disturbance
// flags (late to bed, night awakening, alcohol, illness) renders its
// letter code in the disturbance row — in the day's column, keyed like the
// other rows — while plain days render nothing. The letters are the raw
// TempDisturbance tokens of the day's tempDisturbances mask, read
// through a single letter-mapping seam (see the comment on
// disturbanceLetters in lib/domain/disturbances.dart). The interrupted curve
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
    tempDisturbances: TempDisturbance.kr.bit,
  ),
  DailyEntry(
    date: _disturbanceDay(2),
    bbtC: 36.7,
    tempDisturbances: TempDisturbance.alk.bit,
  ),
  DailyEntry(
    date: _disturbanceDay(3),
    bbtC: 36.4,
    tempDisturbances: TempDisturbance.sp.bit,
  ),
  DailyEntry(
    date: _disturbanceDay(4),
    bbtC: 36.5,
    tempDisturbances: TempDisturbance.a.bit,
  ),
  DailyEntry(
    date: _disturbanceDay(5),
    bbtC: 36.8,
    tempDisturbances: TempDisturbance.values.fold(0, (mask, d) => mask | d.bit),
  ),
];

Widget _disturbanceHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) => chartHarness(entries: entries, locale: locale);

// Widget tests of the computed evaluation marks on the cycle chart (Mode M,
// ADR-0001): the user places the mucus-peak and first-higher marks; the UI
// derives and renders the candidate circles/arrows (kind decided PER
// CANDIDATE: arrows at or before the peak day, circles strictly after — R4),
// the solid peak dot in its own in-plot row, the 1–6 low numbering inside
// the plot's bottom edge and the baseline SEGMENT (low #6 to the last
// marked candidate — R10). Derived
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

Widget _harness({
  required List<DailyEntry> entries,
  required List<CycleMark> marks,
  TemperatureRange? range,
}) => MaterialApp(
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
      selectedDatePin(entries.first.date),
      if (range != null) temperatureRangePin(range),
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
    .where(
      (bar) =>
          bar.color == chartScheme(tester).secondary &&
          bar.spots.first.y == bar.spots.last.y,
    )
    .toList();

/// The SUZ bars: vertical two-spot bars in the secondary color (one per
/// user-placed SUZ mark) — the same evaluation-family color as the baseline
/// segment, distinguished by orientation.
List<LineChartBarData> _suzBars(WidgetTester tester) => chartData(tester)
    .lineBarsData
    .where(
      (bar) =>
          bar.color == chartScheme(tester).secondary &&
          bar.spots.first.x == bar.spots.last.x,
    )
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

/// The in-plot day-number glyph under [dayIndex] carrying [number].
Finder _dayNumberGlyph(int dayIndex, int number) =>
    find.byKey(ValueKey('inPlotDayNumber-$dayIndex-$number'));

/// The number rendered in-plot at [dayIndex], or null when none: the
/// glyphs key their value (`inPlotDayNumber-$index-$n`), so absence is a
/// prefix sweep.
String? _numberUnder(WidgetTester tester, int dayIndex) {
  final prefix = 'inPlotDayNumber-$dayIndex-';
  final numbers = [
    for (final widget in tester.widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      ),
    ))
      (widget.key! as ValueKey<String>).value.substring(prefix.length),
  ];
  return numbers.isEmpty ? null : numbers.single;
}

/// The in-plot mucus-peak dot of [dayIndex].
Finder _peakDot(int dayIndex) =>
    find.byKey(ValueKey('inPlotPeakDot-$dayIndex'));

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
      bleeding: i == 5 || i == 9 ? Bleeding.heavy : Bleeding.none,
    ),
];

/// The cycleStart marks of the two-cycle scenario (at the marked days 5
/// and 9 — the same days that used to be bleeding onsets).
final _twoCycleMarks = <CycleMark>[
  CycleMark(date: _gridLineDay(5), type: CycleMarkTypes.cycleStart),
  CycleMark(date: _gridLineDay(9), type: CycleMarkTypes.cycleStart),
];

/// A gap scenario: day 0 tracked, days 1..4 untracked, a cycleStart mark
/// on the untracked gap day 3 — the mark date itself is the new cycle's
/// start (the untracked gap days belong to it), so the separator is drawn
/// at day 3's column, between the mark and the next tracked day 5.
final _gapEntries = <DailyEntry>[
  DailyEntry(date: _gridLineDay(0), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: _gridLineDay(5), bbtC: 36.5, bleeding: Bleeding.heavy),
];

final _gapMarks = <CycleMark>[
  CycleMark(date: _gridLineDay(3), type: CycleMarkTypes.cycleStart),
];

// The FIRST tracked day itself carries the cycleStart mark: tracking began
// right on a cycle start (e.g. continued from the paper sheet), so there
// is NO leading pre-mark group and the recorded range's LEFT edge is the
// first cycle boundary.
final _firstDayBoundaryEntries = longRangeEntries(12);

final _firstDayBoundaryMarks = <CycleMark>[
  CycleMark(date: longRangeDay(0), type: CycleMarkTypes.cycleStart),
];

/// The card-row border container inside the cell of [index]/[row]: the
/// cell's decoration border is a non-uniform Border (right side only),
/// unlike every glyph's own decoration (uniform Border.all or none). The
/// recording-row cells key the whole cell (the border Container is a
/// descendant of the key), but the in-plot glyphs carry no cell borders.
/// Both search directions stay.
Border _cellBorder(WidgetTester tester, int index, String row) {
  final cell = chartCell(index, row);
  final containers = [
    ...tester.widgetList<Container>(
      find.descendant(of: cell, matching: find.byType(Container)),
    ),
    ...tester.widgetList<Container>(
      find.ancestor(of: cell, matching: find.byType(Container)),
    ),
  ];
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<Border>()
      .firstWhere(
        (b) => !b.isUniform,
        orElse: () => fail('no cell border found in cell $index of $row'),
      );
}

Widget _gridLinesHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
}) => chartHarness(entries: entries, marks: marks);

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

/// The glossary entries (en wording), each asserted inside the help sheet
/// and — in the appearance-order test — expected as the sheet's rendered
/// label sequence: the order mirrors the cycle tab's top-down render
/// order (the signal rows above the curve, then the temperature-curve
/// group, then the below-chart strip). The "Ignored temperature" entry
/// presents the VISUAL consequence (the lighter temperature on the curve
/// — the mark is the rendering key, owner decision 2026-09-19) while
/// naming where the mark is set.
const _glossaryEn = [
  'Bleeding',
  'Fertility sign (mucus)',
  'Mucus peak',
  'Mittelschmerz (M)',
  'Sex (X per time of day)',
  'BBT (temperature) in °C',
  'Ignored temperature (lighter; set in the day sheet)',
  'Circled higher measurements',
  'Premature temperature rise',
  'Baseline',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Measurement time',
  'Disturbed measurement (sp late to bed, a frequent night awakening, '
      'alk alcohol, kr illness)',
  'Cervix position',
  'Cervix firmness',
  'Breast pain (B)',
  'Note (diary text, shown vertically per day)',
];

/// The German glossary wording (authoritative draft per the language
/// policy), in the same top-down appearance order as `_glossaryEn`.
const _glossaryDe = [
  'Blutung',
  'Fruchtbarkeitszeichen (Zervixschleim)',
  'Schleimhöhepunkt',
  'Mittelschmerz (M)',
  'Sex (X je Zeitpunkt)',
  'Aufwachtemperatur in °C',
  'Temperatur ignoriert (heller gezeichnet)',
  'Umrandete höhere Messungen',
  'Vorzeitiger Temperaturanstieg',
  'Basislinie',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Messzeitpunkt',
  'Messstörung (sp Spät ins Bett, a Nachts öfter aufstehen, '
      'alk Alkohol, kr Krank)',
  'Muttermund-Position',
  'Muttermund-Festigkeit',
  'Brustschmerz (B)',
  'Notiz (Tagebuchtext, am Tag senkrecht dargestellt)',
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
}) => chartHarness(entries: entries, locale: locale, withScaffold: false);

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
//  3. the per-signal-row corner sample glyphs (bleeding box, clock,
//     sticky-note band sample), each vertically aligned with its signal
//     row's fixed-height slot; the rows' segments mirror the scroll
//     content: the top-of-block rows (bleeding, M) stack between the
//     header prototypes and the temperature scale, and the below-chart
//     strip's rows (time, disturbance, notes band) form ONE
//     segment below the marks slot. The mucus letters, the sex X marks
//     and the peak dot render INSIDE the plot (chart_marks.dart), so they
//     have no row and no rail slot.
// The long-range frozen-content test mirrors the windowing section.

// Nine chart days covering one recorded fact per signal (the per-signal rows fixture of the rows
// section):
// temperatures 36.4..37.0 — with the default settings range 36..38 °C every
// half-degree tick between the fixed bounds exists. Unlike the rows
// fixture, day 4 carries NO Mittelschmerz.
DateTime _leftRailDay(int index) => DateTime.utc(2026, 9, 7 + index);

final _leftRailEntries = nineDayRowsFixture(
  day: _leftRailDay,
  withMittelschmerz: false,
);

// 5 uniform days at 36.5: the scale is a compact two-tick-plus interval.
List<DailyEntry> _flatEntries() => [
  for (var i = 0; i < 5; i++) DailyEntry(date: _leftRailDay(i), bbtC: 36.5),
];

Finder _rail() => find.byKey(const ValueKey('leftRail'));

/// The rail's temperature-scale label texts, in top-down (descending
/// value) order — with the rendered °C unit suffix.
List<String> _scaleLabels(WidgetTester tester) {
  final labelFinder = find.descendant(
    of: _rail(),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('railScaleLabel-'),
    ),
  );
  final entries = [
    for (final widget in tester.widgetList<Text>(labelFinder))
      (rect: tester.getRect(find.byWidget(widget)), text: widget.data!),
  ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  return [for (final e in entries) e.text];
}

/// The scale labels' numeric part (the labels carry a " °C" unit suffix
/// whose formatting is asserted separately).
double _scaleLabelValue(String label) =>
    double.parse(label.replaceFirst(RegExp(r' ?°C$'), ''));

Widget _leftRailHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
  TemperatureRange? range,
}) => chartHarness(entries: entries, locale: locale, temperatureRange: range);

// Widget tests of the notes band on the cycle chart: a day whose entry
// carries a non-empty notes text shows the joined note text in its day
// column — rotated to read bottom→top and anchored at the band bottom.
// The band is the LAST segment of the below-chart strip (per the paper
// sheet, whose remarks block sits at the very bottom). Days with an
// empty/absent notes field render no text. Tapping any band cell opens
// the day options panel like every other cell.

DateTime _noteDay(int index) => DateTime.utc(2026, 9, 7 + index);

// Four chart days:
//  0: plain temperature, no notes                 -> no note text
//  1: temperature WITH a note                     -> rotated note text
//  2: notes = empty string                        -> no note text
//  3: temperature WITHOUT a recorded note field   -> no note text
final _noteEntries = <DailyEntry>[
  DailyEntry(date: _noteDay(0), bbtC: 36.5),
  DailyEntry(date: _noteDay(1), bbtC: 36.6, notes: 'Impfung heute'),
  DailyEntry(date: _noteDay(2), bbtC: 36.7, notes: ''),
  DailyEntry(date: _noteDay(3), bbtC: 36.4),
];

Widget _noteHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) => chartHarness(entries: entries, locale: locale);

// Widget tests of the per-signal rows under the cycle chart (the paper's
// recording rows): one always-rendered row per signal — bleeding, mucus
// (with the reserved solid peak-dot slot above the glyph), measurement
// time, disturbance, and the merged notes band. The rows hold ONLY day
// cells — their sample glyphs and localized row names live in the frozen
// left rail (see the left-rail section), keyed `${row}Corner` there. The
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

// The chart block's recording rows, top-down in render order: the single
// top strip row (bleeding), then the single below-chart strip in the
// owner-decided order — measurement time first, the disturbance letters,
// then the merged notes band at the very bottom (the paper sheet's
// remarks home). The mucus letters, sex Xs, Mittelschmerz M and
// evaluation numbers render inside the plot (the in-plot glyph section).
const _signalRows = ['bleeding', 'time', 'disturbance', 'notesBand'];

// The bleeding row's dedicated level fixture: every level recorded once,
// on consecutive days — day 0 none(0), day 1 light, day 2 spotting,
// day 3 medium, day 4 heavy, day 5 maximum. Every day carries a
// temperature: with no measurement recorded anywhere the chart renders
// only its "no temperature" placeholder instead of the signal rows, so
// the bleeding cells would never exist to assert on.
final _bleedingRowEntries = [
  DailyEntry(date: _rowsDay(0), bbtC: 36.5),
  DailyEntry(date: _rowsDay(1), bbtC: 36.5, bleeding: Bleeding.light),
  DailyEntry(date: _rowsDay(2), bbtC: 36.5, bleeding: Bleeding.spotting),
  DailyEntry(date: _rowsDay(3), bbtC: 36.5, bleeding: Bleeding.medium),
  DailyEntry(date: _rowsDay(4), bbtC: 36.5, bleeding: Bleeding.heavy),
  DailyEntry(date: _rowsDay(5), bbtC: 36.5, bleeding: Bleeding.maximum),
];

/// All bleed-fill regions (the shared symbol's fill widgets) inside the
/// bleeding cell of [index]: the solid bottom bar of a menstruation-level
/// day, or the dots of a spotting day.
Finder _bleedingFills(int index) => find.descendant(
  of: chartCell(index, 'bleeding'),
  matching: find.byType(BleedingFill),
);

Widget _rowsHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
  TemperatureRange? range,
}) => chartHarness(entries: entries, locale: locale, temperatureRange: range);

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
bool _connects(WidgetTester tester, int a, int b) => _segmentBars(tester).any(
  (bar) =>
      bar.spots.length == 2 &&
      bar.spots[0].x == a.toDouble() &&
      bar.spots[1].x == b.toDouble(),
);

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
}) => chartHarness(
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
// marks), the letter-coded pain flag B (breast, in the notes band's pain
// row) and M (Mittelschmerz, inside the plot below the mucus
// letters). Days without
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
  DailyEntry(date: _timeSexPainDay(2), sexTimings: SexTiming.morning.bit),
  DailyEntry(date: _timeSexPainDay(3), painBreast: true),
  DailyEntry(date: _timeSexPainDay(4), painMittelschmerz: true),
  DailyEntry(
    date: _timeSexPainDay(5),
    sexTimings: SexTiming.morning.bit | SexTiming.evening.bit,
    painBreast: true,
    painMittelschmerz: true,
  ),
  DailyEntry(date: _timeSexPainDay(6), bbtC: 36.6),
  DailyEntry(date: _timeSexPainDay(7), cervixFirmness: CervixFirmness.soft),
];

Widget _timeSexPainHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) => chartHarness(entries: entries, locale: locale);

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
  expect(
    color,
    isNotNull,
    reason: 'bands are configured by color, not gradient',
  );
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
// the whole chart block scrolls horizontally (curve and signal
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

/// A 149-day range whose TAIL evaluates: days 142..147 sit 0.3 °C under
/// day 148's marked rise, so the six days before the rise carry the 1–6
/// numbering while the visible front of the range stays number-free.
List<DailyEntry> _numberedTailEntries() => [
  ...longRangeEntries(142),
  for (var i = 0; i < 6; i++)
    DailyEntry(date: longRangeDay(142 + i), bbtC: 36.2),
  DailyEntry(date: longRangeDay(148), bbtC: 36.5),
];

/// The first-higher mark that anchors _numberedTailEntries's low window.
final _numberedTailMarks = <CycleMark>[
  CycleMark(
    date: longRangeDay(148),
    type: CycleMarkTypes.firstHigherMeasurement,
  ),
];

Finder _bleedingCell(int index) => find.byKey(ValueKey('bleedingCell-$index'));

// The chart's day-column geometry at the test viewport (800 wide, 12 body
// padding on each side): a 60-day range overflows, so columns render at the
// minimum usable width and the content exceeds the viewport.
const _columnWidth = 24.0;

/// The finder for the horizontal scroll view that carries the chart block.
Widget _windowingHarness({
  required List<DailyEntry> entries,
  List<CycleMark> marks = const [],
  Stream<List<DailyEntry>>? entriesStream,
  bool emptyHome = false,
}) => chartHarness(
  entries: entries,
  marks: marks,
  entriesStream: entriesStream,
  emptyHome: emptyHome,
);

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
  for (final widget in tester.widgetList(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith(prefix),
    ),
  )) {
    final suffix = (widget.key! as ValueKey<String>).value.substring(
      prefix.length,
    );
    indexes.add(int.parse(suffix));
  }
  return indexes;
}

void main() {
  // ═══════════ alignment ═══════════
  // former test/cycle_chart_alignment_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('day i\'s chart dot lands at the center of its label and '
      'signal cells', (tester) async {
    await pumpChart(tester, _alignmentHarness(entries: _alignmentEntries(5)));

    for (var i = 0; i < 5; i++) {
      final dotX = _dotX(tester, i);
      expect(
        dotX,
        closeTo(_cellCenterX(tester, 'bleedingCell-$i'), 0.5),
        reason:
            'day $i: the chart dot must sit at the bleeding row\'s '
            'cell horizontal center',
      );
      expect(
        dotX,
        closeTo(_cellCenterX(tester, 'dayLabel-$i'), 0.5),
        reason:
            'day $i: the chart dot must sit at the day label cell\'s '
            'horizontal center',
      );
      // The below-chart strip's rows keep the shared center too (their
      // windowed cells sit at the same global column positions).
      for (final row in ['time', 'disturbance', 'notesBand']) {
        expect(
          dotX,
          closeTo(_cellCenterX(tester, '${row}Cell-$i'), 0.5),
          reason:
              'day $i: the below-chart strip\'s $row row keeps the '
              'shared column center',
        );
      }
    }
  });

  testWidgets('a single recorded day keeps a usable domain and maps taps to '
      'that day', (tester) async {
    await pumpChart(tester, _alignmentHarness(entries: _alignmentEntries(1)));

    // The lone day's dot sits at its column center — the domain is kept at
    // −0.5..0.5 (one full column wide) instead of collapsing.
    expect(
      _dotX(tester, 0),
      closeTo(_cellCenterX(tester, 'bleedingCell-0'), 0.5),
      reason: 'the single day\'s column center matches its dot',
    );

    // Tapping the plot area opens the one recorded day's sheet.
    final rect = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(rect.center.dx, rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      cycleDayPanel(),
      findsOneWidget,
      reason: 'a tap on the single-day chart opens the day options panel',
    );
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(
      sheet.day,
      _alignmentDay(0),
      reason: 'the single recorded day owns the whole plot',
    );
  });

  // ═══════════ cervix ═══════════
  // former test/cycle_chart_cervix_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('the band cells match the band-height constant and every '
      'windowed day renders one', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    expect(
      notesBandHeight,
      64,
      reason:
          'the band stacks the cervix glyph zone, the letter row, the '
          'breast-pain row and the note zone',
    );
    for (var i = 0; i < _cervixEntries().length; i++) {
      final cell = tester.getRect(chartCell(i, 'notesBand'));
      expect(
        cell.height,
        closeTo(notesBandHeight, 0.01),
        reason: 'day $i: the band cell is one notesBandHeight band',
      );
    }
  });

  testWidgets('the opening paints a circle sized by its value in its '
      'position slot; a position without an opening paints nothing', (
    tester,
  ) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    final circleOf = {
      0: CervixOpening.closed, // low slot
      1: CervixOpening.middle, // medium slot
      2: CervixOpening.open, // high slot
      3: CervixOpening.open, // veryHigh slot
      4: CervixOpening.open, // unreachable slot — topmost, past veryHigh
      5: CervixOpening.open, // opening-only day: medium slot
    };
    final diameterOf = {
      CervixOpening.closed: 4.0,
      CervixOpening.middle: 6.0,
      CervixOpening.open: 8.0,
    };
    for (final MapEntry(:key, :value) in circleOf.entries) {
      final keyFinder = find.byKey(ValueKey('cervixSlotGlyph-$key'));
      final circle = tester.widget<Container>(keyFinder);
      final decoration = circle.decoration! as BoxDecoration;
      final rect = tester.getRect(keyFinder);
      expect(
        decoration.shape,
        BoxShape.circle,
        reason: 'day $key renders its opening as circle geometry',
      );
      expect(
        rect.width,
        diameterOf[value],
        reason: "day $key: the circle's diameter communicates the opening",
      );
      expect(
        rect.height,
        diameterOf[value],
        reason: "day $key: the circle's diameter communicates the opening",
      );
      if (value == CervixOpening.closed) {
        expect(
          decoration.color,
          isNotNull,
          reason: 'day $key: the closed opening is the filled dot',
        );
        expect(
          decoration.border,
          isNull,
          reason: 'day $key: the filled dot carries no stroke',
        );
      } else {
        expect(
          decoration.color,
          isNull,
          reason: "day $key: the opening's ring is an outline circle",
        );
        expect(
          (decoration.border! as Border).top.width,
          1.3,
          reason: "day $key: the ring stroke is the shared circle stroke",
        );
      }
    }

    // A position value is only the slot anchor: without an opening
    // nothing paints in the glyph zone (day 6 records a position only,
    // days 9–11 record other observations without an opening).
    for (final index in [6, 9, 10, 11]) {
      expect(
        find.byKey(ValueKey('cervixSlotGlyph-$index')),
        findsNothing,
        reason:
            'day $index: a position without an opening renders no '
            'slot ink',
      );
      expect(
        find.descendant(
          of: chartCell(index, 'notesBand'),
          matching: find.byWidgetPredicate((w) => w is Text && w.data == 'm'),
        ),
        findsNothing,
        reason: 'day $index: positions paint no letter ink',
      );
    }

    // The slots encode the position anchored at the band top: the ink
    // centers step DOWNWARD (larger y) with lower positions — unreachable
    // topmost, then veryHigh, high, medium, low.
    double inkCenterY(int index) => tester
        .getRect(find.byKey(ValueKey('cervixSlotGlyph-$index')))
        .center
        .dy;
    final centers = [
      for (final i in [4, 3, 2, 1, 0]) inkCenterY(i),
    ];
    expect(
      centers,
      [...centers]..sort(),
      reason:
          'the slot inks step downward with falling position '
          '(unreachable topmost … low lowest)',
    );
    final cell4 = tester.getRect(chartCell(4, 'notesBand'));
    expect(
      centers.first,
      closeTo(cell4.top + 5, 0.5),
      reason: 'the topmost slot anchors 5 px below the band top',
    );

    // Every day whose observations still paint the medium slot shares ONE
    // slot: the opening-only circle keeps the same ink center as the
    // position+opening day (the letter row and its note never shift the
    // glyph).
    final mediumCenter = inkCenterY(1);
    for (final i in [5]) {
      expect(
        inkCenterY(i),
        closeTo(mediumCenter, 0.5),
        reason:
            'day $i: the medium slot center is fixed — the letter row '
            'and the note never shift the glyph',
      );
    }
  });

  testWidgets('the firmness letter renders iff a firmness value exists, in '
      'the fixed letter row below the glyph zone', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    final expectedLetter = {0: 'w', 3: 'h-w', 7: 'w', 9: 'w', 10: 'w', 11: 'w'};
    for (final MapEntry(:key, :value) in expectedLetter.entries) {
      final ink = find.byKey(ValueKey('cervixFirmnessGlyph-$key'));
      expect(ink, findsOneWidget, reason: 'day $key renders its firmness ink');
      expect(
        tester.widget<Text>(ink).data,
        value,
        reason: 'day $key shows the firmness shorthand "$value"',
      );
      final rect = tester.getRect(ink);
      final cell = tester.getRect(chartCell(key, 'notesBand'));
      expect(
        rect.top,
        closeTo(cell.top + cervixGlyphZoneHeight, 0.5),
        reason:
            'day $key: the letter row starts where the glyph zone ends — '
            'the same height on every cervix day, position and note '
            'regardless',
      );
    }
    for (final key in [2, 8]) {
      expect(
        find.byKey(ValueKey('cervixFirmnessGlyph-$key')),
        findsNothing,
        reason: 'day $key records no firmness and shows no letter',
      );
    }

    // The letter still renders below the slot ink — the circle's
    // distance to the row communicates the position.
    for (final key in [0, 3]) {
      expect(
        tester
            .getRect(find.byKey(ValueKey('cervixFirmnessGlyph-$key')))
            .center
            .dy,
        greaterThan(
          tester
              .getRect(find.byKey(ValueKey('cervixSlotGlyph-$key')))
              .center
              .dy,
        ),
        reason: 'day $key: the firmness letter renders below the slot ink',
      );
    }
  });

  testWidgets('the note zone top follows the band stack: below letter row '
      'and pain row on cervix days, below the pain row alone on '
      'cervix-free days, full band on cervix-free pain-free days', (
    tester,
  ) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    // Day 9's note zone starts below the FULL reserved top block — the
    // same height every cervix day carries.
    final cell9 = tester.getRect(chartCell(9, 'notesBand'));
    final day9Note = tester.getRect(find.byKey(const ValueKey('notesText-9')));
    expect(
      day9Note.top,
      closeTo(cell9.top + cervixGlyphZoneHeight + cervixLetterRowHeight, 0.5),
      reason:
          "a cervix day's note zone starts below the fixed glyph zone and "
          'letter row',
    );
    // Day 11 adds the breast-pain row between the letter row and the note
    // zone; the reserved cervix block itself stays untouched.
    final cell11 = tester.getRect(chartCell(11, 'notesBand'));
    final day11Note = tester.getRect(
      find.byKey(const ValueKey('notesText-11')),
    );
    expect(
      day11Note.top,
      closeTo(
        cell11.top +
            cervixGlyphZoneHeight +
            cervixLetterRowHeight +
            painRowHeight,
        0.5,
      ),
      reason:
          "a cervix pain day's note zone starts below the pain row that "
          'follows the letter row',
    );
    // Day 8 is cervix-free: the pain row takes the band top and the note
    // zone starts below it.
    final cell8 = tester.getRect(chartCell(8, 'notesBand'));
    final day8Note = tester.getRect(find.byKey(const ValueKey('notesText-8')));
    expect(
      day8Note.top,
      closeTo(cell8.top + painRowHeight, 0.5),
      reason:
          'on a cervix-free pain day the note zone starts below the '
          'topmost pain row',
    );
    expect(
      day8Note.height,
      closeTo(notesBandHeight - painRowHeight, 1),
      reason: 'the cervix-free pain day notes the band minus the pain row',
    );
  });

  testWidgets('a whitespace-only note folds to nothing: no note text '
      'renders and the cervix zones keep their fixed geometry', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    expect(
      find.byKey(const ValueKey('notesText-10')),
      findsNothing,
      reason:
          "day 10's whitespace-only note folds to no text — no "
          'invisible glyph renders',
    );
    final cell10 = tester.getRect(chartCell(10, 'notesBand'));
    final letter = tester.getRect(
      find.byKey(const ValueKey('cervixFirmnessGlyph-10')),
    );
    expect(
      letter.top,
      closeTo(cell10.top + cervixGlyphZoneHeight, 0.5),
      reason: "day 10's letter row keeps its fixed place without a note",
    );
  });

  testWidgets('the notes teaser reads top→bottom anchored at the note zone '
      "top, joined, single line and ellipsized; the note text keeps the "
      'column edge on pain and pain-free days alike', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    final note = tester.widget<Text>(find.byKey(const ValueKey('notesText-8')));
    expect(
      note.data,
      'Impfung nachgekauft (Rückfrage bei Dr. Wild) Arztbesuche nachtragen',
      reason: 'the notes teaser folds newlines to a space like the PDF',
    );
    expect(note.maxLines, 1, reason: 'the teaser is a single line');
    expect(
      note.overflow,
      TextOverflow.ellipsis,
      reason: 'the teaser ellipsizes instead of wrapping',
    );
    final rotated = find
        .ancestor(
          of: find.byKey(const ValueKey('notesText-8')),
          matching: find.byType(RotatedBox),
        )
        .first;
    expect(
      tester.widget<RotatedBox>(rotated).quarterTurns,
      1,
      reason: 'the rotated box reads top→bottom',
    );
    final noteRect = tester.getRect(find.byKey(const ValueKey('notesText-8')));
    final cell8 = tester.getRect(chartCell(8, 'notesBand'));
    expect(
      noteRect.top,
      closeTo(cell8.top + painRowHeight, 1),
      reason: 'the note text anchors at the note zone top, below the pain row',
    );
    expect(
      noteRect.left,
      closeTo(cell8.left, 1),
      reason:
          'the pain letter lives in its own row — the note text keeps the '
          'column edge, no left clearance',
    );

    final cell9 = tester.getRect(chartCell(9, 'notesBand'));
    expect(
      tester.getRect(find.byKey(const ValueKey('notesText-9'))).left,
      closeTo(cell9.left, 1),
      reason: "a pain-free day's note text sits at the column edge",
    );

    for (final i in [0, 1, 2, 3, 4, 5, 6, 7, 9, 10]) {
      expect(
        find.byKey(ValueKey('painBreastGlyph-$i')),
        findsNothing,
        reason: 'day $i records no breast pain and shows no B',
      );
      expect(
        find.descendant(
          of: chartCell(i, 'notesBand'),
          matching: find.byWidgetPredicate((w) => w is Text && w.data == 'B'),
        ),
        findsNothing,
        reason: 'no breast-pain letter in day $i\'s band',
      );
    }
  });

  testWidgets('the breast-pain letter renders as a plain letter centered in '
      'its dedicated row — below the letter row on cervix days, at the band '
      'top on cervix-free days', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    Finder inkOf(int index) => find.byKey(ValueKey('painBreastGlyph-$index'));

    final plain = tester.widget<Text>(inkOf(8));
    expect(plain.data, 'B', reason: 'the pain ink is the plain B letter');

    for (final index in [8, 11]) {
      final rowTop = index == 8
          ? tester.getRect(chartCell(index, 'notesBand')).top
          : tester.getRect(chartCell(index, 'notesBand')).top +
                cervixGlyphZoneHeight +
                cervixLetterRowHeight;
      final ink = tester.getRect(inkOf(index));
      expect(
        ink.center.dy,
        closeTo(rowTop + painRowHeight / 2, 0.5),
        reason:
            'day $index: the B letter centers vertically in its '
            '$painRowHeight-px pain row',
      );
      expect(
        ink.center.dx,
        closeTo(tester.getRect(chartCell(index, 'notesBand')).center.dx, 0.5),
        reason:
            'day $index: the B letter centers horizontally like the '
            'firmness letters, no fixed left pin',
      );
      expect(
        ink.bottom,
        lessThanOrEqualTo(rowTop + painRowHeight + 0.5),
        reason: "day $index: the B letter stays inside its pain row",
      );
    }

    expect(
      find.byKey(const ValueKey('painBreastGlyph-9')),
      findsNothing,
      reason: 'day 9 records no breast pain — no pain row is reserved',
    );
  });

  testWidgets('a cervix-free day renders no cervix ink in its band', (
    tester,
  ) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

    expect(find.byKey(const ValueKey('cervixSlotGlyph-8')), findsNothing);
    expect(find.byKey(const ValueKey('cervixFirmnessGlyph-8')), findsNothing);
  });

  // ═══════════ day labels ═══════════
  // former test/cycle_chart_day_labels_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('per-day column labels', () {
    testWidgets('every day column shows day of month and day of cycle; a '
        'cycle start that is not a month first stays a plain number', (
      tester,
    ) async {
      // 5 recorded days, no bleeding onset anywhere: one leading cycle
      // group starting on 2026-01-20.
      await pumpChart(tester, _dayLabelsHarness(entries: _dayLabelsEntries(5)));

      // Column 0 starts the (leading) cycle group on 2026-01-20 — but the
      // month form follows the CALENDAR (day-of-month == 1), not the cycle,
      // so it shows its plain day number; the cycle start is only visible
      // in line 2 counting from 1.
      expect(
        _label(0, '20.'),
        findsOneWidget,
        reason: 'the non-month-first cycle start shows a plain day number',
      );
      expect(
        _label(0, 'Jan'),
        findsNothing,
        reason: 'no month form on a cycle start that is not a month first',
      );
      expect(
        _label(0, '1'),
        findsOneWidget,
        reason: 'day of cycle 1 on the cycle start',
      );
      for (var i = 1; i < 5; i++) {
        expect(
          _label(i, '${20 + i}.'),
          findsOneWidget,
          reason: 'day column $i shows its day of month',
        );
        expect(
          _label(i, '${i + 1}'),
          findsOneWidget,
          reason:
              'day column $i shows its day of cycle (counted from the '
              'cycle start on 2026-01-20)',
        );
      }

      // The label row replaces the old sparse bottom axis titles: no
      // duplicated day-of-month strip anywhere else in the chart.
      expect(find.text('21.'), findsOneWidget);
    });

    testWidgets('the first day of a calendar month shows the localized '
        'short month form instead of the plain day number', (tester) async {
      // 2026-01-29 .. 2026-02-02: day index 3 is February 1st.
      await pumpChart(
        tester,
        _dayLabelsHarness(entries: _entriesFrom(DateTime.utc(2026, 1, 29), 5)),
      );

      expect(
        _label(2, '31.'),
        findsOneWidget,
        reason: 'ordinary days keep the plain day number',
      );
      expect(
        _label(3, 'Feb'),
        findsOneWidget,
        reason: 'February 1st renders the short month form',
      );
      expect(
        _label(3, '1.'),
        findsNothing,
        reason: 'the "1." day number is replaced by the short month',
      );
      // Day of cycle line 2 is unchanged: it keeps counting through the
      // month boundary (leading group started 2026-01-29).
      expect(_label(3, '4'), findsOneWidget);
      expect(_label(4, '2.'), findsOneWidget);
    });

    testWidgets('the German short month form is used in the de locale', (
      tester,
    ) async {
      // 2025-12-29 .. 2026-01-02: day index 3 is January 1st.
      await pumpChart(
        tester,
        _dayLabelsHarness(
          entries: _entriesFrom(DateTime.utc(2025, 12, 29), 5),
          locale: const Locale('de'),
        ),
      );

      expect(
        _label(3, 'Jan.'),
        findsOneWidget,
        reason: 'the German month abbreviation keeps its trailing period',
      );
      expect(
        _label(3, 'Jan '),
        findsNothing,
        reason: 'no en-style "1 Jan"-like composite may leak in',
      );
      expect(
        _label(4, '2.'),
        findsOneWidget,
        reason: 'ordinary days show the plain day number',
      );
      expect(
        _label(3, '4'),
        findsOneWidget,
        reason:
            'day of cycle continues through the month boundary '
            '(leading group started 2025-12-29)',
      );
    });

    testWidgets('a month first that is also a cycle start shows the short '
        'month form, not the day number', (tester) async {
      // The recorded range BEGINS on 2026-02-01 (the leading group's
      // start, no cycleStart mark involved): the first of the month shows
      // the month form, and the leading group's day-of-cycle count also
      // starts at 1 there.
      await pumpChart(
        tester,
        _dayLabelsHarness(
          entries: _entriesFrom(
            DateTime.utc(2026, 2, 1),
            3,
            bleeding: {0: Bleeding.heavy},
          ),
        ),
      );

      expect(
        _label(0, 'Feb'),
        findsOneWidget,
        reason:
            'February 1st is a month first AND the range\'s first '
            'day — the month form shows',
      );
      expect(_label(0, '1.'), findsNothing);
      expect(
        _label(0, '1'),
        findsOneWidget,
        reason: 'day of cycle 1 on the cycle start',
      );
      expect(_label(1, '2.'), findsOneWidget);
      expect(_label(1, '2'), findsOneWidget);
    });

    testWidgets('a new cycle starts mid-month with a plain day number and '
        'restarts the day-of-cycle count', (tester) async {
      // 40 days (2026-01-20 .. 2026-02-28); a cycleStart mark on day index
      // 35 (2026-02-24) opens the second cycle there — mid-month, hence a
      // plain day number despite the cycle start.
      final marks = [
        CycleMark(date: _dayLabelsDay(35), type: CycleMarkTypes.cycleStart),
      ];
      await pumpChart(
        tester,
        _dayLabelsHarness(entries: _dayLabelsEntries(40), marks: marks),
      );

      // The initial auto-scroll puts the window at the newest days: the 40
      // narrow columns overflow the viewport, so the end of the recorded
      // range — the window around indexes 34–36 — is on screen right away.

      // End of the first cycle: day of cycle 35 on 2026-02-23.
      expect(_label(34, '23.'), findsOneWidget);
      expect(_label(34, '35'), findsOneWidget);

      // Second cycle: the onset day shows a PLAIN day number (month form
      // is only for month firsts) and counts 1.
      expect(
        _label(35, '24.'),
        findsOneWidget,
        reason: 'a mid-month cycle start is not a month first',
      );
      expect(_label(35, 'Feb 24'), findsNothing);
      expect(_label(35, '1'), findsOneWidget);
      expect(_label(36, '25.'), findsOneWidget);
      expect(_label(36, '2'), findsOneWidget);
    });

    testWidgets('untracked gap days keep counting from the last cycle start', (
      tester,
    ) async {
      // Only day 0 (bleeding onset) and day 5 carry entries; days 1–4 are
      // untracked calendar gaps that still belong to the running cycle.
      final entries = [
        DailyEntry(
          date: _dayLabelsDay(0),
          bbtC: 36.5,
          bleeding: Bleeding.heavy,
        ),
        DailyEntry(date: _dayLabelsDay(5), bbtC: 36.5),
      ];
      await pumpChart(tester, _dayLabelsHarness(entries: entries));

      for (var i = 1; i < 5; i++) {
        expect(
          _label(i, '${20 + i}.'),
          findsOneWidget,
          reason: 'the untracked gap day $i still shows its day of month',
        );
        expect(
          _label(i, '${i + 1}'),
          findsOneWidget,
          reason: 'the gap day keeps counting from the cycle start',
        );
      }
    });

    testWidgets('the labels build windowed at their global x positions', (
      tester,
    ) async {
      // 100 recorded days (2026-01-20 .. 2026-04-29): far more than one
      // screen, so only the parked window renders labels — and the
      // initial auto-scroll starts that window at the newest days, where
      // the later labels carry the content of THEIR day, not of a
      // re-indexed window. The parked window carries an extra screen-width
      // of margin past the visible edges (31 columns at this viewport), so
      // the earliest days (index 0..36) stay outside it. The fixture keeps
      // its 100 days for exactly that windowing margin: at ~60 days the
      // parked window would swallow index 0.
      await pumpChart(
        tester,
        _dayLabelsHarness(entries: _dayLabelsEntries(100)),
      );

      expect(
        _dayLabel(0),
        findsNothing,
        reason:
            'the earliest days are outside the initial (newest-days) '
            'parked window',
      );
      expect(
        _dayLabel(99),
        findsOneWidget,
        reason: 'the newest day fills the initial window',
      );

      // Day index 40 = 2026-03-01 (20 + 40 days): a month FIRST, so its
      // label is the short month form instead of "1." — and the day-of-
      // cycle line is its own (41, counting from 2026-01-20). The initial
      // parked window covers the range's tail, so index 40 renders without
      // any scrolling.
      expect(
        _label(40, 'Mar'),
        findsOneWidget,
        reason: 'March 1st shows the short month form even mid-window',
      );
      expect(_label(40, '1.'), findsNothing);
      expect(_label(40, '41'), findsOneWidget);
    });
  });

  group('three-digit day-of-cycle labels', () {
    testWidgets(
      'a long mark-driven cycle (no cycle start in the recorded range — '
      'e.g. during pregnancy) keeps the three-digit day-of-cycle label '
      'inside its column',
      (tester) async {
        // 104 recorded days (2026-01-20 .. 2026-05-03) with NO cycleStart
        // marks: the leading cycle group's day-of-cycle counter runs 1..104,
        // so the range's tail renders three-digit day-of-cycle labels. The
        // 104 columns overflow the viewport, so every column renders at the
        // 24 px minimum width — the narrowest layout the chart ever uses.
        await pumpChart(
          tester,
          _dayLabelsHarness(entries: _dayLabelsEntries(104)),
        );

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the three-digit day-of-cycle label must not overflow '
              'its 24 px column',
        );

        // Day index 103 shows day-of-cycle 104 (the leading group counts
        // from 2026-01-20) and sits inside the parked window at the newest
        // days. Its rendered label must not paint past its column bounds.
        final column = tester.getRect(_dayLabel(103));
        final label = tester.getRect(
          find.descendant(of: _dayLabel(103), matching: find.text('104')),
        );
        expect(
          label.left,
          greaterThanOrEqualTo(column.left - 0.5),
          reason: 'the rendered label does not paint left of its column',
        );
        expect(
          label.right,
          lessThanOrEqualTo(column.right + 0.5),
          reason: 'the rendered label does not paint right of its column',
        );
      },
    );

    testWidgets('short day-of-cycle labels keep their natural size — the label '
        'scales down only, never shrinks 1–2 digit numbers', (tester) async {
      await pumpChart(
        tester,
        _dayLabelsHarness(entries: _dayLabelsEntries(104)),
      );

      // Day index 45 shows day-of-cycle 46 (the leading group counts from
      // 2026-01-20) and sits inside the parked window at the newest days.
      // In the test font every glyph is a 1 em square, so the natural
      // (unshrunk) width of the label at fontSize 9 is exactly 2 * 9 = 18.
      final label = tester.getRect(
        find.descendant(of: _dayLabel(45), matching: find.text('46')),
      );
      expect(
        label.width,
        closeTo(18.0, 0.5),
        reason:
            'a two-digit day-of-cycle label renders at its natural, '
            'unshrunk size (it must never be scaled down to fit)',
      );
    });
  });

  group('long-running cycles (day-of-cycle beyond three digits, '
      'pregnancy-like)', () {
    // ~130 consecutive tracked days with NO cycleStart mark (the leading
    // group runs pregnancy-like 1..130). The columns overflow the
    // viewport, so every column renders at the minimum usable width while
    // the initial auto-scroll parks the window on the newest days.
    List<DailyEntry> longRun() => _dayLabelsEntries(130);

    testWidgets('a ~130-day run without any cycle start renders without '
        'exceptions or overflow and the three-digit day-of-cycle header '
        'label actually renders', (tester) async {
      await pumpChart(tester, _dayLabelsHarness(entries: longRun()));

      expect(
        tester.takeException(),
        isNull,
        reason: 'the long run builds without layout exceptions',
      );

      // Day index 119 shows day-of-cycle 120 (the leading group counts
      // from 2026-01-20) and sits inside the parked window at the newest
      // days: the three-digit header label renders and stays inside its
      // column.
      final column = tester.getRect(_dayLabel(119));
      final label = tester.getRect(
        find.descendant(of: _dayLabel(119), matching: find.text('120')),
      );
      expect(
        label.left,
        greaterThanOrEqualTo(column.left - 0.5),
        reason: 'day-of-cycle 120 renders, not left of its column',
      );
      expect(
        label.right,
        lessThanOrEqualTo(column.right + 0.5),
        reason: 'day-of-cycle 120 renders, not right of its column',
      );
    });

    testWidgets('the same run with one mid-range cycle start renders the '
        'day columns and the ordinal chip scaled within its span, without '
        'exceptions', (tester) async {
      // A mid-range cycle start at day index 80 (2026-04-10): it sits
      // inside the initial parked window (the window covers the newest
      // ~60 columns), so its chip renders right away.
      final marks = [
        CycleMark(date: _dayLabelsDay(80), type: CycleMarkTypes.cycleStart),
      ];
      await pumpChart(
        tester,
        _dayLabelsHarness(entries: longRun(), marks: marks),
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the long run with a mid-range boundary builds without '
            'layout exceptions',
      );

      // The restart is visible: the boundary day counts 1 again and the
      // beyond-three-digit column continues the count.
      expect(
        find.descendant(of: _dayLabel(80), matching: find.text('1')),
        findsOneWidget,
        reason:
            'the mid-range cycle start restarts the day-of-cycle '
            'count at 1',
      );
      expect(
        find.descendant(of: _dayLabel(119), matching: find.text('40')),
        findsOneWidget,
        reason: 'the columns after the cycle start count on',
      );

      // The ordinal chip hugs its label and stays INSIDE the cycle's own
      // column span (boundary day through the range's end, clamped to the
      // built window): the FittedBox scales the label within the span —
      // the chip is bounded by it, never wider, and never overflows the
      // plot.
      final chip = find.byKey(const ValueKey('cycleOrdinalChip-80'));
      expect(
        chip,
        findsOneWidget,
        reason: 'the mid-range boundary renders its ordinal chip',
      );
      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / 130;
      final chipRect = tester.getRect(chip);
      expect(
        chipRect.left,
        closeTo(plot.left + 80 * colW, 2.5),
        reason: 'the chip pins to the boundary day\'s column start',
      );
      // The built window's right edge is the range's end (column 129), so
      // the chip's available span is 80..130 columns wide; the chip's
      // background must stop at it.
      expect(
        chipRect.right,
        lessThanOrEqualTo(plot.left + 130 * colW + 0.5),
        reason: 'the chip stays inside its cycle\'s span',
      );
      expect(
        chipRect.right,
        lessThanOrEqualTo(plot.right),
        reason: 'the chip never overflows the plot',
      );
      // The FittedBox kept the label within the chip's hugging background.
      final textRect = tester.getRect(
        find.descendant(of: chip, matching: find.text('Cycle 1')),
      );
      expect(
        textRect.left,
        greaterThanOrEqualTo(chipRect.left),
        reason: 'the label starts inside the chip',
      );
      expect(
        textRect.right,
        lessThanOrEqualTo(chipRect.right),
        reason: 'the label ends inside the chip',
      );
    });
  });

  group('header above the chart', () {
    testWidgets('the day header row renders ABOVE the temperature curve '
        '(the paper\'s header line on top of the sheet)', (tester) async {
      await pumpChart(tester, _dayLabelsHarness(entries: _dayLabelsEntries(5)));

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final headerTop = tester
          .getRect(find.byKey(const ValueKey('dayLabel-2')))
          .top;
      expect(
        headerTop,
        lessThan(chartTop),
        reason: 'the day/cycle header sits above the chart, not below it',
      );
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
      await pumpChart(
        tester,
        _disturbanceHarness(entries: _disturbanceEntries),
      );

      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      for (final entry in {1: 'kr', 2: 'alk', 3: 'sp', 4: 'a'}.entries) {
        final cellRect = tester.getRect(chartCell(entry.key, 'disturbance'));
        expect(
          cellRect.top,
          greaterThan(chartBottom),
          reason:
              'the disturbance row is part of the below-chart strip, '
              'below the curve',
        );
        expect(
          chartCellContent(entry.key, 'disturbance', find.text(entry.value)),
          findsOneWidget,
          reason:
              'day ${entry.key} carries its disturbance flag\'s letter '
              'code (${entry.value}) in the day\'s column',
        );
        // The letter sits inside its day column horizontally (same column
        // geometry as every other row).
        final curveCell = tester.getRect(chartCell(entry.key, 'bleeding'));
        expect(
          cellRect.left,
          closeTo(curveCell.left, 0.5),
          reason: 'the disturbance cell shares the day column geometry',
        );
      }
    },
  );

  testWidgets('plain days render nothing in the disturbance row', (
    tester,
  ) async {
    await pumpChart(tester, _disturbanceHarness(entries: _disturbanceEntries));

    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      expect(
        chartCellContent(0, 'disturbance', find.text(letter)),
        findsNothing,
        reason: 'a plain day shows no letter code',
      );
    }
  });

  testWidgets('a multi-flag day renders its letters stacked in one cell', (
    tester,
  ) async {
    await pumpChart(tester, _disturbanceHarness(entries: _disturbanceEntries));

    final cell = tester.getRect(chartCell(5, 'disturbance'));
    for (final letter in ['kr', 'alk', 'sp', 'a']) {
      final rects = chartCellContent(5, 'disturbance', find.text(letter))
          .evaluate()
          .map((element) {
            final box = element.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) & box.size;
          })
          .toList();
      expect(
        rects,
        hasLength(1),
        reason: 'the $letter code renders exactly once',
      );
      final rect = rects.single;
      expect(rect.left, greaterThanOrEqualTo(cell.left - 0.5));
      expect(
        rect.right,
        lessThanOrEqualTo(cell.right + 0.5),
        reason: 'the stacked letters stay inside the day column',
      );
    }
    // Stacked: the letters render at DIFFERENT vertical positions (the
    // paper sheet writes disturbance codes one under the other). Render
    // order follows the mask's token order — alk (bit 4) stacks above
    // kr (bit 8).
    final krRect = tester.getRect(
      chartCellContent(5, 'disturbance', find.text('kr')),
    );
    final alkRect = tester.getRect(
      chartCellContent(5, 'disturbance', find.text('alk')),
    );
    expect(
      alkRect.bottom,
      lessThanOrEqualTo(krRect.top),
      reason: 'the stacked letters do not overlap',
    );
  });

  testWidgets('tapping a disturbance cell opens the day sheet', (tester) async {
    await pumpChart(tester, _disturbanceHarness(entries: _disturbanceEntries));

    await tester.tap(chartCell(1, 'disturbance'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cycleDayPanel(), findsOneWidget);
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(
      sheet.day,
      _disturbanceDay(1),
      reason: 'the tapped disturbance cell owns day 1',
    );
  });

  testWidgets(
    'the disturbance row has a rail corner slot with the localized row '
    'name (en and de)',
    (tester) async {
      await pumpChart(
        tester,
        _disturbanceHarness(entries: _disturbanceEntries),
      );

      expect(chartCellCorner('disturbance'), findsOneWidget);
      final tooltips = tester
          .widgetList<Tooltip>(
            find.descendant(
              of: chartCellCorner('disturbance'),
              matching: find.byType(Tooltip),
            ),
          )
          .map((t) => t.message)
          .toList();
      expect(tooltips, [
        'Disturbed measurement',
      ], reason: 'the disturbance corner carries the localized row name');

      // Vertical alignment with its row (shared row heights, like every
      // other rail glyph).
      final cornerCenter = tester
          .getRect(chartCellCorner('disturbance'))
          .center
          .dy;
      final cellCenter = tester.getRect(chartCell(3, 'disturbance')).center.dy;
      expect(
        cornerCenter,
        closeTo(cellCenter, 0.5),
        reason:
            'the disturbance rail glyph is vertically centered on the '
            'row',
      );

      await pumpChart(
        tester,
        _disturbanceHarness(
          entries: _disturbanceEntries,
          locale: const Locale('de'),
        ),
      );
      final deTooltips = tester
          .widgetList<Tooltip>(
            find.descendant(
              of: chartCellCorner('disturbance'),
              matching: find.byType(Tooltip),
            ),
          )
          .map((t) => t.message)
          .toList();
      expect(deTooltips, [
        'Messstörung',
      ], reason: 'de: the disturbance row carries the German row name');
    },
  );

  testWidgets('the help sheet explains the disturbance letters (en and de)', (
    tester,
  ) async {
    final wording = {
      const Locale('de'):
          'Messstörung (sp Spät ins Bett, '
          'a Nachts öfter aufstehen, alk Alkohol, kr Krank)',
      const Locale('en'):
          'Disturbed measurement (sp late to bed, '
          'a frequent night awakening, alk alcohol, kr illness)',
    };
    for (final MapEntry(:key, :value) in wording.entries) {
      await pumpChart(
        tester,
        // Remount the app per iteration: a same-shaped re-pump would only
        // update the existing tree in place, and the previous locale's open
        // help-sheet route (its scrim) would then absorb the next tap.
        KeyedSubtree(
          key: UniqueKey(),
          child: _disturbanceHarness(entries: _disturbanceEntries, locale: key),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(value),
        ),
        findsOneWidget,
        reason:
            '$key: the letter codes need a legend entry naming the '
            'diary\'s disturbance vocabulary',
      );
    }
  });

  // ═══════════ evaluation marks ═══════════
  // former test/cycle_chart_evaluation_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('R6 — the peak renders as a solid dot inside the plot, not on '
      'the curve', () {
    testWidgets('the peak day keeps a plain temperature dot — no ring on '
        'the curve', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/12 (idx 6) carries the mucus-peak mark: the curve dot there is
      // an ORDINARY temperature dot — the ring painter is gone from the
      // peak day (R6).
      final painter = dotPainter(tester, 6);
      expect(
        painter,
        isNot(isA<RingDotPainter>()),
        reason: 'the peak ring was removed from the temperature curve',
      );
      expect(painter, isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets('curve rings exist only for the candidate measurements, '
        'not for the peak', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      // Walk every temperature dot: a ring appears exactly on the three
      // circled candidates (idx 8..10), never on the peak day (idx 6).
      final ringIndexes = <int>{};
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter = bar.dotData.getDotPainter(
            spot,
            0,
            bar,
            bar.spots.indexOf(spot),
          );
          if (painter is RingDotPainter) ringIndexes.add(spot.x.round());
        }
      }
      expect(ringIndexes, {
        8,
        9,
        10,
      }, reason: 'rings wrap only the circled candidates (R6/R1)');
      for (final index in ringIndexes) {
        final painter = dotPainter(tester, index) as RingDotPainter;
        expect(
          painter.ringColor,
          chartScheme(tester).primary,
          reason: 'circled candidates are temperature-family',
        );
      }
    });

    testWidgets('the peak renders as a solid dot INSIDE the plot, at the '
        'peak row\'s own $peakDotCenterOffsetK K pitch', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/12 (idx 6) carries the peak mark -> solid in-plot dot.
      expect(_peakDot(6), findsOneWidget);
      // Neighboring days carry no peak dot.
      expect(_peakDot(5), findsNothing);
      expect(_peakDot(7), findsNothing);

      // The dot is SOLID and in the mucus color family (tertiary), at the
      // shared glyph alpha.
      final dot = tester.widget<Container>(_peakDot(6));
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        chartScheme(tester).tertiary.withValues(alpha: chartMarkAlpha),
        reason: 'the peak belongs to the mucus color family',
      );

      // The dot sits at the peak-dot row's OWN pitch below the scale max —
      // decoupled from the letters row — pixel-y via the shared linear
      // value->pixel mapping.
      final plot = tester.getRect(find.byType(LineChart));
      final data = chartData(tester);
      final span = data.maxY - data.minY;
      final expectedY = plot.top + peakDotCenterOffsetK / span * plot.height;
      expect(
        tester.getRect(_peakDot(6)).center.dy,
        closeTo(expectedY, 0.5),
        reason:
            'the peak dot pins at the peak row\'s own pitch, '
            'above the letters row',
      );
    });

    testWidgets('a peak day without an entry still renders the dot and '
        'does not crash', (tester) async {
      // 9/12 has NO entry at all: the dot hangs on the peak mark itself,
      // so it renders alone in the day's column.
      final entries = _evaluationEntries
          .where((e) => !_sameDay(e, _sat12))
          .toList();
      await pumpChart(tester, _harness(entries: entries, marks: _marks));

      expect(
        _peakDot(6),
        findsOneWidget,
        reason: 'the dot rides the mark, entry or not',
      );
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter = bar.dotData.getDotPainter(
            spot,
            0,
            bar,
            bar.spots.indexOf(spot),
          );
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
    testWidgets('circled candidates: every measured day above the baseline '
        'from the rise onward, capped and ended by rule D', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      // The candidates (idx 8..10) render circled ...
      for (final index in [8, 9, 10]) {
        final painter = dotPainter(tester, index);
        expect(
          painter,
          isA<RingDotPainter>(),
          reason: 'circled higher measurement at day index $index',
        );
        expect(
          (painter as RingDotPainter).ringColor,
          chartScheme(tester).primary,
          reason: 'circled higher measurements are temperature-family',
        );
      }
      // ... the pre-rise rise (idx 0, 36.9 above the baseline 36.4) is NOT
      // a candidate (R3) — an ordinary dot.
      expect(dotPainter(tester, 0), isNot(isA<RingDotPainter>()));
      expect(dotPainter(tester, 0), isNot(isA<ArrowUpDotPainter>()));
    });

    testWidgets('the four-cap: four arrows carry ordinals; the beyond-cap '
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
      await pumpChart(tester, _harness(entries: entries, marks: marks));

      for (final index in [8, 9, 10, 11, 12]) {
        expect(
          dotPainter(tester, index),
          isA<ArrowUpDotPainter>(),
          reason:
              'no peak -> arrow at $index (R4; the '
              'beyond-cap candidate renders unnumbered)',
        );
      }
      // Nothing is circled anywhere.
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter = bar.dotData.getDotPainter(
            spot,
            0,
            bar,
            bar.spots.indexOf(spot),
          );
          expect(painter, isNot(isA<RingDotPainter>()));
        }
      }
    });

    testWidgets('the 4th CIRCLED candidate renders when rule E fires '
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
      await pumpChart(tester, _harness(entries: entries, marks: _marks));

      for (final index in [8, 9, 10, 11]) {
        expect(
          dotPainter(tester, index),
          isA<RingDotPainter>(),
          reason: 'the 4th circled candidate exists under rule E',
        );
      }
      expect(dotPainterOrNull(tester, 12), isNotNull);
      expect(
        dotPainter(tester, 12),
        isNot(isA<RingDotPainter>()),
        reason: 'the sequence ended at the rule-E trigger',
      );
    });

    testWidgets('a MIXED sequence: the peak-day candidate is an arrow and '
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
      await pumpChart(tester, _harness(entries: entries, marks: marks));

      // Collected kinds across the whole curve, indexed by day.
      final arrows = <int>{};
      final circles = <int>{};
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter = bar.dotData.getDotPainter(
            spot,
            0,
            bar,
            bar.spots.indexOf(spot),
          );
          if (painter is ArrowUpDotPainter) arrows.add(spot.x.round());
          if (painter is RingDotPainter) circles.add(spot.x.round());
        }
      }

      // At or before the peak day (9/14, 9/15): arrows.
      expect(
        arrows,
        {8, 9},
        reason:
            'candidates at or before the peak are arrows (R4) — '
            'the peak day itself included',
      );
      // Strictly after the peak (9/16..9/18): circles.
      expect(circles, {
        10,
        11,
        12,
      }, reason: 'candidates after the peak are circles (R4)');
      // Chronological arrows-then-circles — no interleaving.
      expect(
        arrows.every((a) => circles.every((c) => a < c)),
        isTrue,
        reason: 'arrows precede circles (R4)',
      );
    });
  });

  group('numbering', () {
    testWidgets('the six low days carry 1–6 inside the plot, counted back '
        'from the first higher', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      // 9/13..9/8 (idx 7..2) = numbers 1..6.
      expect(_numberUnder(tester, 7), '1');
      expect(_numberUnder(tester, 6), '2');
      expect(_numberUnder(tester, 5), '3');
      expect(_numberUnder(tester, 4), '4');
      expect(_numberUnder(tester, 3), '5');
      expect(_numberUnder(tester, 2), '6');
      // Outside the six-window: no numbers.
      expect(
        _numberUnder(tester, 0),
        isNull,
        reason: '9/6: outside the window',
      );
      expect(_numberUnder(tester, 1), isNull, reason: '9/7: 7th prior day');
      expect(
        _numberUnder(tester, 8),
        isNull,
        reason: '9/14: the first higher itself is not a low',
      );
    });

    testWidgets('the numbers render in the primary color, bold and small', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      final ink = tester.widget<Text>(_dayNumberGlyph(7, 1)).style!;
      expect(ink.color, chartScheme(tester).primary);
      expect(ink.fontWeight, FontWeight.bold);
      expect(ink.fontSize, 9);
    });

    testWidgets('a surface-colored halo layer renders behind the number '
        'ink at the same spot', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      final halo = find.byKey(const ValueKey('inPlotHaloDayNumber-7-1'));
      expect(halo, findsOneWidget, reason: 'one halo layer behind the ink');
      expect(
        tester.getRect(halo).center,
        tester.getRect(_dayNumberGlyph(7, 1)).center,
        reason: 'the halo is centered exactly behind its ink glyph',
      );
    });

    testWidgets('the numbers sit at the plot\'s bottom edge (min + 0.05) '
        'and center under their day column', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      final plot = tester.getRect(find.byType(LineChart));
      final data = chartData(tester);
      final span = data.maxY - data.minY;
      final expectedY =
          plot.top +
          (data.maxY - (data.minY + dayNumbersRowCenterOffsetK)) /
              span *
              plot.height;
      for (var i = 2; i <= 7; i++) {
        final glyph = tester.getRect(
          find.byKey(ValueKey('inPlotDayNumber-$i-${8 - i}')),
        );
        expect(
          glyph.center.dy,
          closeTo(expectedY, 0.5),
          reason: 'day $i: the number pins at the bottom edge margin',
        );
        expect(
          glyph.center.dx,
          closeTo(_dotX(tester, i), 1),
          reason: 'day $i: the number centers under its day column',
        );
      }
    });
  });

  group('baseline — R10 segment', () {
    testWidgets('the baseline draws as a SEGMENT: from the left edge of '
        'low #6\'s column to the last marked candidate (+ half a day), '
        'clamped to the plot bounds', (tester) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      final bars = _baselineBars(tester);
      expect(bars, hasLength(1), reason: 'one evaluated cycle -> one segment');
      final bar = bars.single;
      expect(
        bar.color,
        chartScheme(tester).secondary,
        reason: 'the baseline keeps its theme-derived secondary color',
      );
      expect(bar.dashArray, const [6, 4], reason: 'the dashed style stays');
      // START: the left edge of low #6's column — low #6 is 9/8 (idx 2),
      // so the segment begins at x 1.5.
      // END: the last marked candidate (9/16, idx 10 — the rule-D trigger)
      // plus half a day = x 10.5 — the domain extends half a column past
      // the last day, so the clamp no longer bites here.
      final first = bar.spots.first;
      final last = bar.spots.last;
      expect(
        first.x,
        closeTo(1.5, 1e-9),
        reason: 'the segment starts under low #6 (left column edge)',
      );
      expect(
        last.x,
        closeTo(10.5, 1e-9),
        reason:
            'last candidate idx 10 + half a day, inside the domain '
            '(lastX = dayCount − 0.5 = 10.5)',
      );
      expect(first.y, 36.4);
      expect(last.y, 36.4, reason: 'the segment runs at the baseline value');
    });

    testWidgets('the segment ends half a day past the last candidate\'s '
        'column when recorded days continue past it', (tester) async {
      // 9/17 sits AT the baseline (36.4): a gap day, not a candidate — the
      // sequence ended at the rule-D trigger on 9/16, so the R10 segment
      // ends at 9/16's day column + half a day = x 10.5 (no clamp needed).
      final entries = [
        ..._evaluationEntries,
        DailyEntry(date: _thu17, bbtC: 36.4),
      ];
      await pumpChart(tester, _harness(entries: entries, marks: _marks));

      final spots = _baselineBars(tester).single.spots;
      expect(
        spots.first.x,
        closeTo(1.5, 1e-9),
        reason: 'the segment starts under low #6 (left column edge)',
      );
      expect(
        spots.last.x,
        closeTo(10.5, 1e-9),
        reason: 'last marked candidate 9/16 (idx 10) + half a day',
      );
    });

    testWidgets('no marked candidate -> no baseline segment', (tester) async {
      // Peak only: no first-higher mark, so no low window and no segment.
      await pumpChart(
        tester,
        _harness(
          entries: _evaluationEntries,
          marks: [CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay)],
        ),
      );
      expect(_baselineBars(tester), isEmpty);

      // First higher marked, but every day from the rise on sits AT or
      // below the baseline: no marked candidate exists, so R10 draws no
      // segment at all (not even a partial one through the low window).
      final flat = [
        for (final e in _evaluationEntries)
          e.date.isAfter(_sun13) ? DailyEntry(date: e.date, bbtC: 36.4) : e,
      ];
      await pumpChart(tester, _harness(entries: flat, marks: _marks));
      expect(
        _baselineBars(tester),
        isEmpty,
        reason: 'R10: a cycle with no marked candidate draws no segment',
      );
    });
  });

  group('no marks', () {
    testWidgets('nothing evaluation-related is drawn when no marks exist', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: const []),
      );

      expect(
        _baselineBars(tester),
        isEmpty,
        reason: 'no marks -> no baseline segment',
      );
      for (var i = 0; i < 11; i++) {
        expect(
          _numberUnder(tester, i),
          isNull,
          reason: 'no marks -> no numbers',
        );
        expect(_peakDot(i), findsNothing, reason: 'no marks -> no peak dot');
      }
      for (final bar in dotBars(tester)) {
        for (final spot in bar.spots) {
          final painter = bar.dotData.getDotPainter(
            spot,
            0,
            bar,
            bar.spots.indexOf(spot),
          );
          expect(painter, isNot(isA<RingDotPainter>()));
          expect(painter, isNot(isA<ArrowUpDotPainter>()));
        }
      }
    });
  });

  group('all mucus peaks render (from the marks stream)', () {
    testWidgets('two peak marks in one cycle render two solid dots — even '
        'when no evaluation exists', (tester) async {
      // ONLY peak marks: without a first-higher mark no evaluation can
      // exist, yet every placed peak must render — the dots come from the
      // MARKS STREAM, not from the single domain-anchored peak.
      await pumpChart(
        tester,
        _harness(
          entries: _evaluationEntries,
          marks: [
            CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
            CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
          ],
        ),
      );

      expect(_peakDot(6), findsOneWidget, reason: 'the first peak renders');
      expect(
        _peakDot(9),
        findsOneWidget,
        reason:
            'the second peak renders too, though the evaluation has '
            'nothing to anchor (no rise marked)',
      );
      expect(
        _peakDot(8),
        findsNothing,
        reason: 'a day without a peak mark renders no dot',
      );
    });

    testWidgets('two peaks render alongside a full evaluation', (tester) async {
      await pumpChart(
        tester,
        _harness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _tue15, type: CycleMarkTypes.mucusPeakDay),
          ],
        ),
      );

      expect(_peakDot(6), findsOneWidget);
      expect(_peakDot(9), findsOneWidget);
    });
  });

  group('SUZ marks render (user-placed only)', () {
    // The glyph's top anchoring: the bar hangs DOWN from the chart's top
    // border by a fixed °C drop and the arrow anchors just below that
    // border, so the whole glyph sits inside the top rows of the plot.
    // The two pinned values (suzBarHangSpanDegrees /
    // suzArrowTopInsetDegrees from suz_glyph.dart, shared with the PDF
    // export) are owner-eyeball rendering details — the tests pin them
    // through the named constants so bar/glyph/PDF stay in lockstep.
    testWidgets('a suzEvening mark renders a vertical bar hanging from the '
        'chart\'s top border at the column middle, plus a right-pointing '
        'arrow whose base starts at the bar near the top', (tester) async {
      await pumpChart(
        tester,
        _harness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _wed16, type: CycleMarkTypes.suzEvening),
          ],
        ),
      );

      final data = chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1), reason: 'one user SUZ mark -> one bar');
      final bar = bars.single;
      // suzEvening anchors the bar at the day column's MIDDLE (x = day
      // index); the bar hangs DOWN from the chart's top border by a fixed
      // °C drop instead of spanning the whole plot height.
      expect(
        bar.spots.first.x,
        10.0,
        reason: 'suzEvening anchors at the column middle (9/16, idx 10)',
      );
      expect(bar.spots.last.x, 10.0);
      expect(
        bar.spots.first.y,
        data.maxY,
        reason: 'the bar hangs from the chart\'s top border',
      );
      expect(
        bar.spots.last.y,
        data.maxY - suzBarHangSpanDegrees,
        reason:
            'the bar spans a fixed $suzBarHangSpanDegrees °C drop from '
            'the top (owner-eyeball value, pinned here)',
      );
      expect(
        bar.color,
        chartScheme(tester).secondary,
        reason:
            'the SUZ bar shares the baseline\'s evaluation-family '
            'color role (secondary)',
      );

      // The right-pointing arrow: base at the bar, anchored inside the
      // hung band, close to the top border (no longer at the cycle's
      // baseline value — the baseline-anchor concept is retired).
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull, reason: 'the SUZ arrow renders with the bar');
      final (spot, painter) = arrow!;
      expect(spot.x, 10.0, reason: 'the arrow base starts at the bar');
      expect(
        spot.y,
        data.maxY - suzArrowTopInsetDegrees,
        reason:
            'the arrow anchors $suzArrowTopInsetDegrees °C below the '
            'top border, inside the hung band (owner-eyeball value, '
            'pinned here)',
      );
      expect(painter, isA<SuzArrowDotPainter>());
      expect(
        (painter as SuzArrowDotPainter).color,
        chartScheme(tester).secondary,
        reason: 'the SUZ arrow shares the evaluation-family color role',
      );
    });

    testWidgets('a suzMorning mark anchors the bar at the column START '
        '(x − 0.5)', (tester) async {
      await pumpChart(
        tester,
        _harness(
          entries: _evaluationEntries,
          marks: [
            ..._marks,
            CycleMark(date: _tue15, type: CycleMarkTypes.suzMorning),
          ],
        ),
      );

      final data = chartData(tester);
      final bars = _suzBars(tester);
      expect(bars, hasLength(1));
      final bar = bars.single;
      expect(
        bar.spots.first.x,
        8.5,
        reason: 'suzMorning anchors at the column start (9/15, idx 9 − 0.5)',
      );
      expect(bar.spots.last.x, 8.5);
      // The hang-span/inset values do not depend on the x anchoring.
      expect(
        bar.spots.first.y,
        data.maxY,
        reason: 'the bar hangs from the chart\'s top border',
      );
      expect(
        bar.spots.last.y,
        data.maxY - suzBarHangSpanDegrees,
        reason:
            'the bar spans a fixed $suzBarHangSpanDegrees °C drop from '
            'the top (owner-eyeball value, pinned here)',
      );
      final arrow = _suzArrowSpot(tester);
      expect(arrow, isNotNull);
      expect(arrow!.$1.x, 8.5, reason: 'the arrow base starts at the bar');
      expect(
        arrow.$1.y,
        data.maxY - suzArrowTopInsetDegrees,
        reason:
            'the arrow anchors $suzArrowTopInsetDegrees °C below the '
            'top border, inside the hung band (owner-eyeball value, '
            'pinned here)',
      );
    });

    testWidgets(
      'a suzMorning mark on the FIRST recorded day anchors the bar at '
      'the plot\'s left edge (x − 0.5 = minX, no cut-back)',
      (tester) async {
        // With the half-column-shifted domain the first day's column starts
        // at −0.5, so its column-START bar sits exactly at the plot's left
        // edge instead of being clamped onto the day index.
        await pumpChart(
          tester,
          _harness(
            entries: _evaluationEntries,
            marks: [
              ..._marks,
              CycleMark(date: _sun6, type: CycleMarkTypes.suzMorning),
            ],
          ),
        );

        final bars = _suzBars(tester);
        expect(bars, hasLength(1));
        final data = chartData(tester);
        final bar = bars.single;
        expect(
          bar.spots.first.x,
          -0.5,
          reason: 'day 0\'s column start is the domain\'s minX (−0.5)',
        );
        expect(bar.spots.last.x, -0.5);
        // The clamping affects only x — the top-anchored y values stand.
        expect(
          bar.spots.first.y,
          data.maxY,
          reason: 'the bar hangs from the chart\'s top border',
        );
        expect(
          bar.spots.last.y,
          data.maxY - suzBarHangSpanDegrees,
          reason:
              'the bar spans a fixed $suzBarHangSpanDegrees °C drop from '
              'the top (owner-eyeball value, pinned here)',
        );
        final arrow = _suzArrowSpot(tester);
        expect(arrow, isNotNull);
        expect(arrow!.$1.x, -0.5, reason: 'the arrow base starts at the bar');
        expect(
          arrow.$1.y,
          data.maxY - suzArrowTopInsetDegrees,
          reason:
              'the arrow anchors $suzArrowTopInsetDegrees °C below the '
              'top border, inside the hung band (owner-eyeball value, '
              'pinned here)',
        );
      },
    );

    testWidgets('no SUZ glyph renders without a user mark — the computed '
        'suzBegins suggests only, it never renders', (tester) async {
      // The main scenario's arithmetic fires rule D on 9/16 — but no user
      // SUZ mark exists, so the chart draws no SUZ bar and no arrow.
      await pumpChart(
        tester,
        _harness(entries: _evaluationEntries, marks: _marks),
      );

      expect(
        _suzBars(tester),
        isEmpty,
        reason: 'the computed SUZ never renders on the chart',
      );
      expect(_suzArrowSpot(tester), isNull);
    });
  });

  group('latest-rise anchor renders in the UI (re-marking supersedes)', () {
    testWidgets(
      'two rise marks: the LATER one drives the evaluation; the earlier '
      'rise day renders no candidate',
      (tester) async {
        // Two firstHigher marks: 9/14 and 9/15. The LATER mark (9/15) anchors
        // the evaluation — and re-derives the six-low window with it (R9):
        // the lows before 9/15 are 9/9..9/14, so the baseline moves to 9/14's
        // 36.9 (the earlier rise mark's day itself becomes a low!). From the
        // walk start 9/15: 9/15 sits AT the new baseline (gap day, no
        // candidate), 9/16 (37.0) is circle #1 — no SUZ with a single circle.
        // Under the old earliest-anchor semantics the circles would be
        // {8, 9, 10} against the 36.4 baseline; the later mark wins instead.
        await pumpChart(
          tester,
          _harness(
            entries: _evaluationEntries,
            marks: [
              CycleMark(date: _sat12, type: CycleMarkTypes.mucusPeakDay),
              CycleMark(
                date: _mon14,
                type: CycleMarkTypes.firstHigherMeasurement,
              ),
              CycleMark(
                date: _tue15,
                type: CycleMarkTypes.firstHigherMeasurement,
              ),
            ],
          ),
        );

        final rings = <int>{};
        for (final bar in dotBars(tester)) {
          for (final spot in bar.spots) {
            final painter = bar.dotData.getDotPainter(
              spot,
              0,
              bar,
              bar.spots.indexOf(spot),
            );
            if (painter is RingDotPainter) rings.add(spot.x.round());
          }
        }
        expect(
          rings,
          {10},
          reason:
              'the LATEST rise mark anchors the evaluation: the '
              're-derived baseline (36.9 through the earlier rise day, now '
              'low #1) leaves 9/16 as the only candidate',
        );
        // The earlier rise mark's day (9/14, idx 8) renders no candidate —
        // it sits at the new baseline as a low.
        expect(
          dotPainter(tester, 8),
          isNot(isA<RingDotPainter>()),
          reason: 'the earlier rise mark renders no candidate',
        );
        expect(dotPainter(tester, 8), isNot(isA<ArrowUpDotPainter>()));
        // And the marked rise day itself (9/15) sits at the re-derived
        // baseline: no candidate there either.
        expect(dotPainter(tester, 9), isNot(isA<RingDotPainter>()));
        expect(dotPainter(tester, 9), isNot(isA<ArrowUpDotPainter>()));
      },
    );
  });

  // ═══════════ summary table absence ═══════════
  // new screen-level test from the summary-table removal (no former file;
  // see the file header note on the other sections' merge mechanics)

  // The cycle tab renders NO evaluation summary table anymore: the chart
  // block (with its evaluation overlay) is the only evaluation surface on
  // the screen — the numbers live on the separate statistics tab. The
  // absence is keyed on the `cycleSummary*` keys the table's scroller,
  // cells and headers rendered with, so a re-introduction under a new
  // class name is caught too.
  testWidgets('the Zyklus screen renders no evaluation summary table', (
    tester,
  ) async {
    // A tall surface: the table would sit below the default test
    // viewport's fold, and the Zyklus list is lazy — below the fold it is
    // not even built, so a short surface could miss it and pass vacuously.
    useTallSurface(tester);
    await pumpChart(tester, chartHarness(entries: _alignmentEntries(5)));

    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            (key.value == 'cycleSummaryScroll' ||
                key.value.startsWith('cycleSummaryCell-') ||
                key.value.startsWith('cycleSummaryHeader-'));
      }),
      findsNothing,
      reason: 'no cycleSummary* scroller/cell/header keys render anymore',
    );
  });

  // ═══════════ grid lines ═══════════
  // former test/cycle_chart_grid_lines_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('vertical day lines', () {
    testWidgets('the chart draws hairline vertical grid lines with interval 1 '
        'aligned to the shifted domain\'s column boundaries', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final grid = chartData(tester).gridData;
      expect(
        grid.drawVerticalLine,
        isTrue,
        reason: 'the day columns are separated by vertical lines',
      );
      expect(grid.verticalInterval, 1, reason: 'one line per day column');
      // The domain is half a column shifted (minX −0.5); with the baseline
      // at minX the interval-1 lines land on the interior column
      // boundaries 0.5, 1.5, … dayCount − 1.5.
      expect(
        chartData(tester).baselineX,
        -0.5,
        reason:
            'the grid baseline sits at the domain start so interval-1 '
            'lines land on column boundaries',
      );
      final line = grid.getDrawingVerticalLine(0.5);
      expect(
        line.strokeWidth,
        lessThanOrEqualTo(1),
        reason: 'day lines are hairlines',
      );
      expect(
        line.color,
        chartScheme(tester).onSurface.withValues(alpha: 0.12),
        reason: 'the hairline is a subtle onSurface tint',
      );
    });

    testWidgets('every signal row\'s day cells carry a matching hairline right '
        'border, and the header row does too', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final onSurface = chartScheme(tester).onSurface;
      for (final row in const ['bleeding', 'time', 'notesBand']) {
        final border = _cellBorder(tester, 1, row);
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason: 'row $row: a hairline right border on the day cell',
        );
        expect(
          border.right.color,
          onSurface.withValues(alpha: 0.12),
          reason:
              'row $row: the border matches the chart\'s day line '
              'style',
        );
      }

      // The header row's cells carry the same hairline (the day/cycle
      // header belongs to the card).
      final headerBorder = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('dayLabel-1')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere(
            (b) => !b.isUniform,
            orElse: () => fail(
              'no header '
              'cell border found',
            ),
          );
      expect(headerBorder.right.width, closeTo(0.5, 0.01));
    });

    testWidgets(
      'cycle starts draw thick solid lines: the chart\'s extra line at '
      'nextCycleStart − 0.5 and the thick right border on the cell '
      'before the new cycle in every row',
      (tester) async {
        await pumpChart(
          tester,
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
        );

        final onSurface = chartScheme(tester).onSurface;
        final verticalLines = chartData(tester).extraLinesData.verticalLines;
        final boundaryXs = verticalLines.map((l) => l.x).toSet();
        expect(
          boundaryXs,
          {4.5, 8.5},
          reason:
              'the marked days at indexes 5 and 9 draw their separator '
              'at x = start − 0.5',
        );
        for (final line in verticalLines) {
          expect(
            line.strokeWidth,
            closeTo(2, 0.01),
            reason: 'cycle-start lines are thick',
          );
          expect(
            line.color,
            onSurface,
            reason: 'cycle-start lines are solid onSurface',
          );
          expect(
            line.dashArray,
            isNull,
            reason: 'the line is solid, not dashed',
          );
        }

        // The thick border sits on the cell BEFORE the new cycle (its right
        // edge is the separator), in every signal row.
        for (final row in const ['bleeding', 'time', 'notesBand']) {
          final thick = _cellBorder(tester, 4, row);
          expect(
            thick.right.width,
            closeTo(2, 0.01),
            reason: 'row $row: the boundary cell carries the thick border',
          );
          expect(
            thick.right.color,
            onSurface,
            reason: 'row $row: the boundary border is solid onSurface',
          );
          // The neighboring cells keep the hairline.
          final thinBefore = _cellBorder(tester, 3, row);
          expect(
            thinBefore.right.width,
            closeTo(0.5, 0.01),
            reason: 'row $row: only the boundary cell is thick',
          );
          final thinAfter = _cellBorder(tester, 5, row);
          expect(
            thinAfter.right.width,
            closeTo(0.5, 0.01),
            reason:
                'row $row: the new cycle\'s first day carries no thick '
                'border (the separator is to its LEFT)',
          );
        }
      },
    );

    testWidgets('no cycle-start line before the first cycleStart mark (the '
        'leading group)', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      expect(
        verticalLines.map((l) => l.x),
        isNot(contains(-0.5)),
        reason: 'the leading group\'s start is not a cycle-start line',
      );

      // The first cell of every row keeps the plain hairline.
      final onSurface = chartScheme(tester).onSurface;
      for (final row in const ['bleeding', 'time']) {
        final border = _cellBorder(tester, 0, row);
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason:
              'row $row: no thick border on the leading group\'s last '
              'cell',
        );
        expect(border.right.color, onSurface.withValues(alpha: 0.12));
      }
    });

    testWidgets('a cycle start on the FIRST tracked day is a boundary at the '
        'range\'s left edge: the ordinal chip renders at index 0 and the '
        'first day cells thicken their LEFT border (the mirror of the '
        'right-edge separator rule)', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(
          entries: _firstDayBoundaryEntries,
          marks: _firstDayBoundaryMarks,
        ),
      );

      final onSurface = chartScheme(tester).onSurface;

      // The ordinal chip renders at index 0, pinned to the plot's left
      // edge (the boundary column's start).
      final chip = find.byKey(const ValueKey('cycleOrdinalChip-0'));
      expect(
        chip,
        findsOneWidget,
        reason:
            'the first tracked day opens the first cycle in the recorded '
            'range — its ordinal badge renders inside the plot',
      );
      final plot = tester.getRect(find.byType(LineChart));
      expect(
        tester.getRect(chip).left,
        closeTo(plot.left + 2, 2.5),
        reason:
            'day-index 0: the chip pins to the boundary column\'s start, '
            'the recorded range\'s left edge',
      );

      // The domain-edge boundary paints through the first day cells' thick
      // LEFT border — the mirror of every interior boundary's thick RIGHT
      // border on the cell before the new cycle. (The chart's extra
      // separator line would sit exactly at the domain's left edge x =
      // −0.5, where its 2 px stroke clamps outside the plot.)
      const edgeThickRows = ['bleeding', 'time', 'notesBand'];
      for (final row in edgeThickRows) {
        final border = _cellBorder(tester, 0, row);
        expect(
          border.left.width,
          closeTo(2, 0.01),
          reason:
              'row $row: the range\'s first cell carries the thick '
              'left boundary border',
        );
        expect(
          border.left.color,
          onSurface,
          reason: 'row $row: the boundary border is solid onSurface',
        );
        // The separator goes to the LEFT of the boundary column, so the
        // first cell's right edge keeps the plain hairline.
        expect(
          border.right.width,
          closeTo(0.5, 0.01),
          reason: 'row $row: the first day keeps the hairline right edge',
        );
      }
      // The header row's first cell carries the same thick left border.
      final headerBorder = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('dayLabel-0')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .firstWhere(
            (b) => !b.isUniform,
            orElse: () => fail('no header cell border found'),
          );
      expect(headerBorder.left.width, closeTo(2, 0.01));
      expect(headerBorder.left.color, onSurface);

      // The extra-line list carries no edge line: the boundary at the
      // recorded range's left edge is painted by the cells' borders, not
      // by a chart line that would clamp at the plot edge (and the chip
      // hangs from that border).
      expect(
        chartData(tester).extraLinesData.verticalLines.map((l) => l.x),
        isNot(contains(-0.5)),
        reason:
            'the left-edge boundary does not draw an extra line at the '
            'domain edge — the cells\' left borders carry it',
      );
    });

    testWidgets('a boundary mark inside untracked gap days draws its '
        'separator at the mark\'s own day column', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _gapEntries, marks: _gapMarks),
      );

      final verticalLines = chartData(tester).extraLinesData.verticalLines;
      // The mark sits on the untracked day index 3; the separator runs
      // through the gap at the mark's own column (not at the next tracked
      // day) — the boundary anchor is the mark date, and the line is
      // drawn at the boundary day's column START (x = i − 0.5).
      expect(
        verticalLines.map((l) => l.x),
        contains(2.5),
        reason:
            'the mark inside the untracked gap draws its separator at '
            'the mark\'s own day column',
      );
      expect(
        verticalLines.map((l) => l.x),
        isNot(contains(4.5)),
        reason:
            'the new cycle\'s first tracked day is no separator line: '
            'the boundary anchored on the mark date',
      );
    });

    testWidgets('the in-plot ordinal badge pins its left edge to the boundary '
        'column (the pixel the separator is drawn through)', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      // The badge chip renders inside the temperature plot, and its LEFT
      // edge pins to the boundary day's column start — pixel i · cellWidth
      // measured from the plot's left edge (a small inset tolerated), the
      // same pixel the thick separator's chart-domain x = i − 0.5 maps to.
      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / _twoCycleEntries.length;
      for (final i in [5, 9]) {
        final chipRect = tester.getRect(
          find.byKey(ValueKey('cycleOrdinalChip-$i')),
        );
        expect(
          chipRect.left,
          closeTo(plot.left + i * colW, 2.5),
          reason:
              'day-index $i: the badge\'s left edge pins to its '
              'cycle\'s first column inside the plot',
        );
      }
    });

    testWidgets('the in-plot ordinal badge shrink-wraps its background to the '
        'label: no full band across the cycle\'s own columns', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / _twoCycleEntries.length;
      // The first boundary (day 5) opens a cycle running columns 5..8 — a
      // 4-column span the chip must NOT paint across: its background hugs
      // the localized wording instead (text + a small horizontal padding).
      final firstTextNatural = tester
          .getSize(find.byKey(const ValueKey('cycleOrdinal-5')))
          .width;
      final first = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-5')),
      );
      final firstSpan = (9 - 5) * colW;
      expect(
        first.width,
        lessThan(firstSpan / 2),
        reason:
            'day-index 5: the chip\'s background hugs the label '
            'instead of spanning the cycle\'s own columns',
      );
      expect(
        first.width,
        greaterThan(firstTextNatural),
        reason:
            'day-index 5: the shrink-wrapped background still '
            'includes its horizontal padding around the text',
      );

      // The text sits inside the hugging background.
      final firstText = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinal-5')),
      );
      expect(
        firstText.left,
        greaterThanOrEqualTo(first.left),
        reason: 'the label starts inside the hugging background',
      );
      expect(
        firstText.right,
        lessThanOrEqualTo(first.right),
        reason: 'the label ends inside the hugging background',
      );

      // The last cycle ran columns 9..11 before: with the shrink-wrap the
      // chip no longer runs to the plot's right edge either.
      final last = tester.getRect(
        find.byKey(const ValueKey('cycleOrdinalChip-9')),
      );
      expect(
        last.right,
        lessThan(plot.right),
        reason:
            'day-index 9: the last cycle\'s chip hugs its label, it '
            'no longer runs to the plot\'s right edge',
      );
    });

    testWidgets('the in-plot ordinal badge clamps at the built window\'s right '
        'edge: a boundary whose cycle runs past the window squeezes the '
        'label into the windowed span instead of overflowing the plot', (
      tester,
    ) async {
      // A 150-day range with a sole cycleStart mark at day index 62: the
      // mark's cycle's own columns would run all the way to the range's
      // end — far past the built window once the block scrolled away from
      // the newest days. After dragging to the content's start the parked
      // window's last built index is 62 (observed below), so the clamp
      // leaves the chip a SINGLE day column — narrower than the natural
      // label, i.e. the clamp really bites.
      const boundaryIndex = 62;
      final entries = longRangeEntries(150);
      final marks = [
        CycleMark(
          date: longRangeDay(boundaryIndex),
          type: CycleMarkTypes.cycleStart,
        ),
      ];
      await pumpChart(
        tester,
        _gridLinesHarness(entries: entries, marks: marks),
      );
      // Drag back to the earliest days (the drag exceeds the range's whole
      // scroll extent, so it settles at the content's start) and let the
      // window re-park well inside the range.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      // The built window's right edge, observed like every windowed row:
      // the day-label cells render exactly for the window's indexes. The
      // fixture above depends on the boundary sitting AT that edge.
      var windowEnd = -1;
      for (var i = 0; i < entries.length; i++) {
        if (tester.any(_dayLabel(i))) windowEnd = i;
      }
      expect(
        windowEnd,
        boundaryIndex,
        reason:
            'the fixture pins the boundary to the parked window\'s '
            'last built index, so the windowed clamp is what limits '
            'the chip',
      );

      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / entries.length;
      // The windowed clamp: the cycle's available span is clamped to the
      // window's right edge (one past the last built index), minus the two
      // column insets. The natural label is WIDER than that span, so the
      // clamp genuinely bites instead of the chip merely hugging the text.
      final maxWidth = (windowEnd + 1 - boundaryIndex) * colW - 4;
      final chip = tester.getRect(
        find.byKey(ValueKey('cycleOrdinalChip-$boundaryIndex')),
      );
      final natural = tester
          .getSize(find.byKey(ValueKey('cycleOrdinal-$boundaryIndex')))
          .width;
      expect(
        natural,
        greaterThan(maxWidth),
        reason:
            'the localized wording is wider than the single-column '
            'clamped span, so the window clamp — not the shrink-wrap — '
            'limits this chip',
      );

      // The chip fills the clamped span exactly: its right edge stops at
      // the window's right boundary instead of running toward the cycle's
      // natural end (the range's end), never overflowing the plot.
      expect(
        chip.width,
        closeTo(maxWidth, 0.5),
        reason:
            'day-index $boundaryIndex: the clamped span is the '
            'chip\'s effective width',
      );
      expect(
        chip.right,
        closeTo(plot.left + (windowEnd + 1) * colW, 2.5),
        reason:
            'day-index $boundaryIndex: the chip clamps at the built '
            'window\'s right edge',
      );
      expect(
        chip.right,
        lessThan(plot.right),
        reason: 'the clamped chip never overflows the plot',
      );
    });

    testWidgets('a perversely short cycle renders its chip and the FittedBox '
        'scales the label down instead of overflowing', (tester) async {
      // Cycle starts on directly adjacent days at the range's tail: two
      // degenerate one-day cycles, so each chip is bounded by a single
      // minimum-width column minus the two column insets.
      final entries = longRangeEntries(60);
      final marks = [
        for (final i in [58, 59])
          CycleMark(date: longRangeDay(i), type: CycleMarkTypes.cycleStart),
      ];
      await pumpChart(
        tester,
        _gridLinesHarness(entries: entries, marks: marks),
      );

      final chipFinder = find.byKey(const ValueKey('cycleOrdinalChip-59'));
      expect(
        chipFinder,
        findsOneWidget,
        reason: 'the one-day cycle renders its chip',
      );
      final chip = tester.getRect(chipFinder);

      // The one-cycle column minus the two column insets is the chip's
      // available width — and the natural label is wider, so the chip is
      // clamped to that span (this is what forces the scale-down case).
      final plot = tester.getRect(find.byType(LineChart));
      final colW = plot.width / entries.length;
      final natural = tester
          .getSize(find.descendant(of: chipFinder, matching: find.byType(Text)))
          .width;
      expect(
        natural,
        greaterThan(colW - 4),
        reason:
            'the localized wording is wider than the one-column '
            'span at its natural size, so only a FittedBox scale-down '
            'fits it',
      );
      expect(
        chip.width,
        closeTo(colW - 4, 0.5),
        reason:
            'the one-day cycle pins the chip to its single column '
            '(the natural text is squeezed, not widened beyond it)',
      );

      final textFinder = find.byKey(const ValueKey('cycleOrdinal-59'));
      final fitted = tester.widget<FittedBox>(
        find.descendant(of: chipFinder, matching: find.byType(FittedBox)),
      );
      expect(
        fitted.fit,
        BoxFit.scaleDown,
        reason: 'the chip scales the label down, never up',
      );
      // The VISUAL (fitted) text bounds stay inside the chip: scaled down
      // to the chip's width, not overflowing it.
      final visual = tester.getRect(textFinder);
      expect(
        visual.right,
        lessThanOrEqualTo(chip.right),
        reason: 'the scaled-down label fits inside the chip\'s width',
      );
      expect(
        visual.left,
        greaterThanOrEqualTo(chip.left),
        reason: 'the scaled-down label starts inside the chip',
      );
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
      'the fixed display range',
      (tester) async {
        // The entries keep 36.5 — well inside the default 36–38 °C range; the
        // grid interval is fixed at 0.1 regardless of the data.
        await pumpChart(
          tester,
          _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
        );

        expect(
          grid(tester).drawHorizontalLine,
          isTrue,
          reason: 'the paper grid rules the temperature body horizontally',
        );
        expect(
          grid(tester).horizontalInterval,
          0.1,
          reason: 'one grid line per 0.1 K step (paper convention)',
        );
      },
    );

    testWidgets('full degrees draw SOLID, thick emphasis lines (×10 integer '
        'classification, no float equality)', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.0, 37.0, 38.0]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(1.2, 0.01),
          reason: '$value is a full degree: the grid emphasizes it',
        );
        expect(
          line.dashArray,
          isNull,
          reason: '$value: a full-degree line is solid',
        );
        expect(
          line.color,
          emphasizedLine(tester),
          reason: '$value: the emphasis tint on the on-surface color',
        );
      }
    });

    testWidgets('the 0.5 midpoints draw DASHED lines at the emphasis weight', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.5, 37.5]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(1.2, 0.01),
          reason: '$value: the half midpoint keeps the emphasis weight',
        );
        expect(line.dashArray, [4, 3], reason: '$value is dashed');
        expect(
          line.color,
          emphasizedLine(tester),
          reason: '$value: the emphasis tint on the on-surface color',
        );
      }
    });

    testWidgets('the remaining 0.1 steps draw the plain day-hairline style', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      for (final value in const [36.1, 36.2, 36.3, 36.4, 36.6, 36.9, 37.9]) {
        final line = horizontalLine(tester, value);
        expect(
          line.strokeWidth,
          closeTo(0.5, 0.01),
          reason: '$value: an in-between step stays a hairline',
        );
        expect(line.dashArray, isNull, reason: '$value is solid');
        expect(
          line.color,
          plainLine(tester),
          reason: '$value: the same subtle tint as the vertical day lines',
        );
      }
    });

    testWidgets('the vertical day lines are unchanged by the horizontal grid: '
        'interval 1, hairline style', (tester) async {
      await pumpChart(
        tester,
        _gridLinesHarness(entries: _twoCycleEntries, marks: _twoCycleMarks),
      );

      expect(grid(tester).drawVerticalLine, isTrue);
      expect(grid(tester).verticalInterval, 1);
      final vertical = grid(tester).getDrawingVerticalLine(0.5);
      expect(vertical.strokeWidth, lessThanOrEqualTo(1));
      expect(
        vertical.color,
        plainLine(tester),
        reason: 'the day hairline style keeps its subtle tint',
      );
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
        await pumpChart(
          tester,
          _helpSheetHarness(entries: _helpSheetEntries(5)),
        );

        final action = tester.widget<IconButton>(
          find.byKey(const ValueKey('cycleHelpAction')),
        );
        expect(
          action.icon,
          isA<Icon>().having((i) => i.icon, 'icon', Icons.info_outline),
          reason: 'the affordance is the info_outline icon',
        );
        expect(
          action.tooltip,
          'Show symbol glossary',
          reason: 'the action carries its localized tooltip',
        );

        // The legend is gone from the screen: no glossary text renders
        // outside the sheet anywhere on the cycle tab.
        for (final entry in _glossaryEn) {
          expect(
            find.text(entry),
            findsNothing,
            reason: '"$entry" no longer sits on the screen',
          );
        }
      },
    );

    testWidgets('tapping the action opens the full symbol glossary (en)', (
      tester,
    ) async {
      await pumpChart(tester, _helpSheetHarness(entries: _helpSheetEntries(5)));

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'the action opens a bottom sheet',
      );
      expect(
        find.byKey(const ValueKey('cycleHelpSheet')),
        findsOneWidget,
        reason: 'the sheet carries its test key',
      );
      expect(
        find.text('Symbol glossary'),
        findsOneWidget,
        reason: 'the sheet is titled',
      );
      for (final entry in _glossaryEn) {
        expect(
          find.text(entry),
          findsOneWidget,
          reason: 'the glossary explains "$entry"',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(_arithmeticNoteEn),
        ),
        findsOneWidget,
      );
      // The mucus glossary sample is the plain S glyph (no EW superscript).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text('EW'),
        ),
        findsNothing,
        reason: 'the mucus glossary sample carries no EW superscript',
      );
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
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color ==
                  scheme.primary.withValues(alpha: 0.4),
        ),
      );
      expect(
        lighterDotSamples,
        findsOneWidget,
        reason:
            'the glossary samples the lighter temperature dot '
            '(primary at 0.4 alpha — derived from the same constant the '
            'chart uses so they cannot drift)',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsNothing,
        reason:
            'the old day-sheet-toggle icon sample is gone — the '
            'legend shows the rendering consequence, not the affordance',
      );
    });

    testWidgets('the glossary uses the German wording in de', (tester) async {
      await pumpChart(
        tester,
        _helpSheetHarness(
          entries: _helpSheetEntries(5),
          locale: const Locale('de'),
        ),
      );

      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')))
            .tooltip,
        'Zeichenerklärung anzeigen',
      );

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.text('Zeichenerklärung'), findsOneWidget);
      for (final entry in _glossaryDe) {
        expect(find.text(entry), findsOneWidget, reason: 'de: "$entry"');
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(_arithmeticNoteDe),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'the glossary entries render in the cycle tab\'s top-down appearance '
      'order (en and de)',
      (tester) async {
        final orders = [
          (
            const Locale('en'),
            _glossaryEn,
            'the glossary mirrors the cycle tab\'s top-down render order: '
                'the signal rows above the curve (bleeding, mucus, mucus '
                'peak, Mittelschmerz, sex), then the temperature-curve '
                'group (temperature, ignored temperature, circled higher, '
                'premature rise, baseline, SUZ), then the below-chart strip '
                '(measurement time, disturbance, cervix position, cervix '
                'firmness, breast pain, note)',
          ),
          (
            const Locale('de'),
            _glossaryDe,
            'the German sheet mirrors the en appearance order in the '
                'German documentation wording: signal rows, '
                'temperature-curve group, below-chart strip (en/de '
                'appearance order stays in parity — en/de parallel draft '
                'policy)',
          ),
        ];
        for (final (locale, glossary, orderReason) in orders) {
          await pumpChart(
            tester,
            // Remount the app per iteration: a same-shaped re-pump would
            // only update the existing tree in place, and the previous
            // locale's open help-sheet route (its scrim) would then absorb
            // the next tap.
            KeyedSubtree(
              key: UniqueKey(),
              child: _helpSheetHarness(
                entries: _helpSheetEntries(5),
                locale: locale,
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
          await tester.pumpAndSettle();

          // Walk the sheet's label texts in tree order (a Column renders
          // its children top-down, which the descendant finder preserves)
          // and compare the glossary members' sequence against the expected
          // appearance order — the sheet title and the arithmetic note are
          // not glossary members and are filtered out.
          final labels = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(const ValueKey('cycleHelpSheet')),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data)
              .whereType<String>()
              .where(glossary.toSet().contains)
              .toList();
          expect(labels, glossary, reason: '$locale: $orderReason');
        }
      },
    );

    testWidgets('the baseline entry samples the chart\'s dashed style', (
      tester,
    ) async {
      await pumpChart(tester, _helpSheetHarness(entries: _helpSheetEntries(5)));
      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      final glyph = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.byKey(const ValueKey('legendBaselineGlyph')),
        ),
      );
      expect(
        (glyph.painter as dynamic).dashPattern,
        const [6, 4],
        reason:
            'the legend paints the baseline dashed with the chart\'s own '
            'dash pattern — the chart\'s baseline bar is an fl_chart '
            'segment (dashArray [6, 4]) that cannot be reused outside '
            'the chart, so the glyph repaints the same dashes',
      );
    });
  });

  // ═══════════ left rail ═══════════
  // former test/cycle_chart_left_rail_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('frozen left rail', () {
    testWidgets(
      'the rail renders outside the horizontal scroll and stays frozen '
      'while the day columns move',
      (tester) async {
        await pumpChart(tester, _leftRailHarness(entries: longRangeEntries()));

        expect(
          _rail(),
          findsOneWidget,
          reason: 'the chart block has a fixed left rail',
        );
        expect(
          find.descendant(of: chartScrollView(), matching: _rail()),
          findsNothing,
          reason:
              'the rail is outside the horizontally scrolling content — '
              'the temperature scale cannot scroll away anymore',
        );

        final railBefore = tester.getRect(_rail());
        final scaleBefore = tester.getRect(
          find.byKey(const ValueKey('railScale')),
        );
        final cellBefore = tester.getRect(
          find.byKey(const ValueKey('bleedingCell-40')),
        );
        // The drag's exact delta depends on the framework's touch slop (see
        // the windowing tests), so the content movement is checked against
        // the settled scroll offset, not the dragged distance.
        final scrollState = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        final offsetBefore = scrollState.position.pixels;

        // Scroll the window toward earlier days (as the windowing tests do):
        // the day columns move, the rail does not.
        await tester.drag(chartScrollView(), const Offset(260, 0));
        await tester.pumpAndSettle();
        final offsetAfter = scrollState.position.pixels;

        expect(
          tester.getRect(_rail()),
          railBefore,
          reason: 'the frozen rail keeps its exact rect while scrolling',
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('railScale'))),
          scaleBefore,
          reason:
              'the temperature scale stays put — the defect this rail '
              'fixes: the scale used to scroll away with the content',
        );
        final cellAfter = tester.getRect(
          find.byKey(const ValueKey('bleedingCell-40')),
        );
        expect(
          cellAfter.center.dx,
          isNot(cellBefore.center.dx),
          reason: 'precondition: the day columns actually moved',
        );
        expect(
          cellAfter.center.dx - cellBefore.center.dx,
          closeTo(offsetBefore - offsetAfter, 1),
          reason:
              'the day columns move exactly with the scroll offset — '
              'the rail is not part of the scrolling content',
        );
      },
    );

    testWidgets(
      'the scale labels share the chart\'s y mapping: every label sits '
      'exactly at its value\'s plot pixel y',
      (tester) async {
        await pumpChart(tester, _leftRailHarness(entries: _leftRailEntries));

        // fl_chart's left titles are disabled: the scale cannot be the
        // scrolling chart's own axis strip anymore.
        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        expect(
          data.titlesData.leftTitles.sideTitles.showTitles,
          isFalse,
          reason: 'the chart no longer draws its own left scale',
        );
        expect(
          data.titlesData.leftTitles.sideTitles.reservedSize,
          0,
          reason:
              'the chart reserves no width for a scale — the plot spans '
              'the full scroll content width',
        );

        // The rail's labels must follow the SAME linear mapping the chart
        // uses: y = plotTop + (maxY − value) / (maxY − minY) * plotHeight.
        final chartRect = tester.getRect(find.byType(LineChart));
        final span = data.maxY - data.minY;
        expect(span, greaterThan(0), reason: 'a usable y domain');
        for (final label in _scaleLabels(tester)) {
          final value = _scaleLabelValue(label);
          final expectedY =
              chartRect.top + (data.maxY - value) / span * chartRect.height;
          final labelCenter = tester
              .getRect(find.descendant(of: _rail(), matching: find.text(label)))
              .center
              .dy;
          expect(
            labelCenter,
            closeTo(expectedY, 0.5),
            reason:
                'scale label $label sits at its value\'s pixel y — the '
                'rail and the plot share one mapping',
          );
        }
      },
    );

    testWidgets(
      'the scale keeps the 0.5 °C interval and the two-scale numbering '
      '(integers plain, halves with one decimal), with the °C unit on '
      'EVERY label (mirrors the PDF rail), and an overridden range moves '
      'the bounds AND the labels (one source of truth)',
      (tester) async {
        final cases =
            <
              ({
                TemperatureRange? range,
                double expectedMinY,
                double expectedMaxY,
                List<String> labels,
                String labelsReason,
              })
            >[
              (
                // The fixed settings range 36..38 supplies the bounds (not
                // the data rounding anymore): every half-degree tick between
                // them, top-down 38 .. 36 — each carrying the unit suffix.
                range: null,
                expectedMinY: 36.0,
                expectedMaxY: 38.0,
                labels: ['38 °C', '37.5 °C', '37 °C', '36.5 °C', '36 °C'],
                labelsReason:
                    'half-degree ticks over the default range, integers '
                    'plain and halves one-decimal, unit suffix on every '
                    'label (the standalone "°C" caption row is removed '
                    'accordingly)',
              ),
              (
                range: const TemperatureRange(min: 35.0, max: 39.0),
                expectedMinY: 35.0,
                expectedMaxY: 39.0,
                labels: [
                  '39 °C',
                  '38.5 °C',
                  '38 °C',
                  '37.5 °C',
                  '37 °C',
                  '36.5 °C',
                  '36 °C',
                  '35.5 °C',
                  '35 °C',
                ],
                labelsReason:
                    'every half-degree tick between the overridden bounds '
                    'renders in the rail (each carrying the unit suffix)',
              ),
            ];
        for (final (
              :range,
              :expectedMinY,
              :expectedMaxY,
              :labels,
              :labelsReason,
            )
            in cases) {
          await pumpChart(
            tester,
            // Remount per case so no previous case's chart state can leak
            // into the next pump.
            KeyedSubtree(
              key: UniqueKey(),
              child: _leftRailHarness(entries: _leftRailEntries, range: range),
            ),
          );

          final data = tester.widget<LineChart>(find.byType(LineChart)).data;
          expect(
            data.minY,
            expectedMinY,
            reason:
                'the settings range\'s lower bound is the chart\'s minY — '
                'one source of truth',
          );
          expect(
            data.maxY,
            expectedMaxY,
            reason:
                'the settings range\'s upper bound is the chart\'s maxY — '
                'one source of truth',
          );
          expect(_scaleLabels(tester), labels, reason: labelsReason);
        }
      },
    );

    testWidgets(
      'the scale labels follow the device locale: de renders the German '
      'comma, the en default keeps the dot (same ticks, separator only)',
      (tester) async {
        await pumpChart(
          tester,
          KeyedSubtree(
            key: UniqueKey(),
            child: _leftRailHarness(
              entries: _leftRailEntries,
              locale: const Locale('de'),
            ),
          ),
        );

        expect(
          _scaleLabels(tester),
          ['38 °C', '37,5 °C', '37 °C', '36,5 °C', '36 °C'],
          reason:
              'the rail\'s decimal display follows the effective '
              'locale — integers stay plain, halves comma-formatted in de',
        );
      },
    );

    testWidgets('the row-name glyphs render IN the rail, each vertically '
        'aligned with its signal row', (tester) async {
      await pumpChart(tester, _leftRailHarness(entries: _leftRailEntries));

      const rows = ['bleeding', 'time', 'disturbance', 'notesBand'];
      for (final row in rows) {
        final corner = find.byKey(ValueKey('${row}Corner'));
        expect(
          corner,
          findsOneWidget,
          reason: 'row $row\'s sample glyph renders (in the rail)',
        );
        expect(
          find.descendant(of: _rail(), matching: corner),
          findsOneWidget,
          reason:
              'row $row\'s sample glyph lives in the frozen rail, not '
              'in the scrolling rows',
        );

        // Vertical alignment with the row: the glyph's rect center equals
        // one of the row's day cells' center (fixed row heights make this
        // a stable, exact assertion).
        final cornerCenter = tester.getRect(corner).center.dy;
        final cellCenter = tester
            .getRect(find.byKey(ValueKey('${row}Cell-3')))
            .center
            .dy;
        expect(
          cornerCenter,
          closeTo(cellCenter, 0.5),
          reason:
              'row $row\'s rail glyph is vertically centered on the '
              'row',
        );

        // The row name stays attached to the glyph for screen readers and
        // long-press: a tooltip renders in the rail.
        expect(
          tester
              .widgetList<Tooltip>(
                find.descendant(of: corner, matching: find.byType(Tooltip)),
              )
              .length,
          1,
          reason: 'row $row\'s rail glyph keeps its row-name tooltip',
        );
      }
    });

    testWidgets(
      'the below-chart strip is ONE rail segment: its glyph slots keep '
      'the owner-decided order time, disturbance, notes band',
      (tester) async {
        await pumpChart(tester, _leftRailHarness(entries: _leftRailEntries));

        double top(String row) =>
            tester.getRect(find.byKey(ValueKey('${row}Corner'))).top;
        const strip = ['time', 'disturbance', 'notesBand'];
        final tops = [for (final row in strip) top(row)];
        expect(
          tops,
          equals([...tops]..sort()),
          reason:
              'the below-chart strip mirrors the content column\'s '
              'single segment: time first, notes last (owner order)',
        );
        // The strip starts after the marks-row slot, mirroring the content
        // column (the marks slot sits between the temperature scale and the
        // segment).
        expect(
          top('time'),
          greaterThan(
            tester.getRect(find.byKey(const ValueKey('railScale'))).bottom,
          ),
          reason:
              'the below-chart segment begins below the scale and the '
              'marks slot, as in the content column',
        );
      },
    );

    testWidgets(
      'the header corner (date + cycle-day prototypes) renders in the '
      'rail with its tooltips and semantics (en and de)',
      (tester) async {
        final wording = {
          const Locale('en'): ['Date', 'Cycle day'],
          const Locale('de'): ['Datum', 'Zyklustag'],
        };
        for (final MapEntry(:key, :value) in wording.entries) {
          await pumpChart(
            tester,
            _leftRailHarness(entries: _leftRailEntries, locale: key),
          );

          final corner = find.byKey(const ValueKey('dayHeaderCorner'));
          expect(
            find.descendant(of: _rail(), matching: corner),
            findsOneWidget,
            reason: 'the header corner slots into the frozen rail',
          );
          // The prototypes are locale-independent literals ('14.' day
          // number, '#5' cycle day).
          expect(
            find.descendant(of: corner, matching: find.text('14.')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: corner, matching: find.text('#5')),
            findsOneWidget,
          );

          final tooltips = tester
              .widgetList<Tooltip>(
                find.descendant(of: corner, matching: find.byType(Tooltip)),
              )
              .map((t) => t.message)
              .toList();
          expect(
            tooltips,
            containsAll(value),
            reason: 'both prototypes keep their localized tooltips ($key)',
          );
          expect(
            find.descendant(
              of: corner,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == value[0],
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: corner,
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == value[1],
              ),
            ),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'the rail is only as wide as its widest label: every scale label '
      'stays inside the rail without clipping (en and de)',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('de')]) {
          await pumpChart(
            tester,
            KeyedSubtree(
              key: UniqueKey(),
              child: _leftRailHarness(
                entries: _leftRailEntries,
                locale: locale,
              ),
            ),
          );

          final rail = tester.getRect(_rail());
          expect(
            rail.width,
            37,
            reason:
                'the frozen rail stays as wide as its widest '
                'scale label plus inset — wider wastes row room',
          );

          final scale = tester.getRect(find.byKey(const ValueKey('railScale')));
          final labels = find.descendant(
            of: _rail(),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'railScaleLabel-',
                  ),
            ),
          );
          for (final widget in tester.widgetList<Text>(labels)) {
            final what = '$locale "${widget.data!}"';
            final rect = tester.getRect(find.byWidget(widget));
            expect(
              rect.left,
              greaterThanOrEqualTo(rail.left),
              reason: '$what stays inside the rail\'s left edge',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(rail.right),
              reason: '$what is not clipped at the rail\'s right edge',
            );
            // The labels sit centered on their tick's plot pixel, so the
            // edge ticks' boxes straddle the scale's edges by half a
            // label height; the CENTER must stay within the scale.
            expect(
              rect.center.dy,
              inInclusiveRange(scale.top, scale.bottom),
              reason: '$what centers on its tick within the scale',
            );
          }
        }
      },
    );

    testWidgets('a flat temperature record keeps the scale usable (the fixed '
        'range always has ticks)', (tester) async {
      // All five days at 36.5: the bounds stay the settings range 36..38,
      // so the scale always has ticks and the mapping never divides by
      // zero — no data-dependent degenerate span can appear anymore.
      await pumpChart(tester, _leftRailHarness(entries: _flatEntries()));

      expect(_scaleLabels(tester), [
        '38 °C',
        '37.5 °C',
        '37 °C',
        '36.5 °C',
        '36 °C',
      ], reason: 'a single-value record still renders a half-degree scale');
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final chartRect = tester.getRect(find.byType(LineChart));
      final expectedMid =
          chartRect.top +
          (data.maxY - 36.5) / (data.maxY - data.minY) * chartRect.height;
      final midCenter = tester
          .getRect(find.descendant(of: _rail(), matching: find.text('36.5 °C')))
          .center
          .dy;
      expect(
        midCenter,
        closeTo(expectedMid, 0.5),
        reason: 'the flat record\'s value maps mid-scale in both places',
      );
    });
  });

  // ═══════════ notes band ═══════════
  // former test/cycle_chart_note_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets('a day with a non-empty note renders its text in the notes '
      'band, below the chart block', (tester) async {
    await pumpChart(tester, _noteHarness(entries: _noteEntries));

    // The note text rides in the day's column (the LAST segment of the
    // below-chart strip, the paper "Bemerkungen" home).
    final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
    final noteRect = tester.getRect(chartCell(1, 'notesBand'));
    expect(
      noteRect.top,
      greaterThan(chartBottom),
      reason: 'the notes band sits below the chart block',
    );
    expect(
      tester.getRect(chartCell(1, 'time')).top,
      lessThan(noteRect.top),
      reason: 'the notes band renders below the measurement-time row',
    );
    for (final row in ['disturbance']) {
      expect(
        noteRect.top,
        greaterThan(tester.getRect(chartCell(1, row)).top),
        reason:
            'the notes band renders below the $row row — notes '
            'are last in the below-chart strip',
      );
    }
    final cell = tester.getRect(chartCell(1, 'bleeding'));
    expect(
      noteRect.left,
      closeTo(cell.left, 0.5),
      reason: 'the band cell shares the day column geometry',
    );

    // The noted day 1 shows the note text ink in its column; a cervix-free,
    // pain-free day anchors it at the full band top.
    expect(
      find.byKey(const ValueKey('notesText-1')),
      findsOneWidget,
      reason: 'noted day 1 shows its note text in the band',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('notesText-1'))).top,
      closeTo(noteRect.top, 0.5),
      reason:
          'without cervix or pain rows the note text anchors at the band top',
    );
  });

  testWidgets('empty/absent notes render no note text', (tester) async {
    await pumpChart(tester, _noteHarness(entries: _noteEntries));

    for (final i in [0, 2, 3]) {
      expect(
        find.byKey(ValueKey('notesText-$i')),
        findsNothing,
        reason: 'day $i carries no note text',
      );
    }
  });

  testWidgets('tapping a notes-band cell opens the day sheet', (tester) async {
    await pumpChart(tester, _noteHarness(entries: _noteEntries));

    await tester.tap(chartCell(1, 'notesBand'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cycleDayPanel(), findsOneWidget);
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(sheet.day, _noteDay(1), reason: 'the tapped band cell owns day 1');
  });

  testWidgets('the notes band has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    await pumpChart(tester, _noteHarness(entries: _noteEntries));

    expect(chartCellCorner('notesBand'), findsOneWidget);
    final tooltips = tester
        .widgetList<Tooltip>(
          find.descendant(
            of: chartCellCorner('notesBand'),
            matching: find.byType(Tooltip),
          ),
        )
        .map((t) => t.message)
        .toList();
    expect(tooltips, [
      'Note',
    ], reason: 'the band corner carries the localized row name');

    final cornerCenter = tester.getRect(chartCellCorner('notesBand')).center.dy;
    final cellCenter = tester.getRect(chartCell(1, 'notesBand')).center.dy;
    expect(
      cornerCenter,
      closeTo(cellCenter, 0.5),
      reason: 'the band rail glyph is vertically centered on the row',
    );

    await pumpChart(
      tester,
      _noteHarness(entries: _noteEntries, locale: const Locale('de')),
    );
    final deTooltips = tester
        .widgetList<Tooltip>(
          find.descendant(
            of: chartCellCorner('notesBand'),
            matching: find.byType(Tooltip),
          ),
        )
        .map((t) => t.message)
        .toList();
    expect(deTooltips, ['Notiz'], reason: 'de: the band row is "Notiz"');
  });

  testWidgets('the help sheet keeps the note entry (en and de)', (
    tester,
  ) async {
    final wording = {
      const Locale('en'): 'Note (diary text, shown vertically per day)',
      const Locale('de'): 'Notiz (Tagebuchtext, am Tag senkrecht dargestellt)',
    };
    for (final MapEntry(:key, :value) in wording.entries) {
      await pumpChart(
        tester,
        // Remount the app per iteration: a same-shaped re-pump would only
        // update the existing tree in place, and the previous locale's open
        // help-sheet route (its scrim) would then absorb the next tap.
        KeyedSubtree(
          key: UniqueKey(),
          child: _noteHarness(entries: _noteEntries, locale: key),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(value),
        ),
        findsOneWidget,
        reason:
            '$key: the indicator glyph needs a legend entry the diary '
            'note vocabulary resolves against',
      );
    }
  });

  // ═══════════ rows ═══════════
  // former test/cycle_chart_rows_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('paper layout: bleeding is the one top strip row', () {
    testWidgets('bleeding is the ONLY top strip row, above the curve; '
        'disturbance and the notes band stay below the block', (tester) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      final chartTop = tester.getRect(find.byType(LineChart)).top;
      final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
      expect(
        tester.getRect(chartCell(0, 'bleeding')).top,
        lessThan(chartTop),
        reason:
            'the bleeding row renders in the TOP of the temperature '
            'block, above the curve (paper sheet)',
      );
      for (final row in ['time', 'disturbance', 'notesBand']) {
        expect(
          tester.getRect(chartCell(0, row)).top,
          greaterThan(chartBottom),
          reason: 'the $row row stays below the temperature block',
        );
      }
    });

    testWidgets('no Mittelschmerz row and no numbering row remain on the '
        'card: no cells, no corners', (tester) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      for (var i = 0; i < _dayCount; i++) {
        expect(
          find.byKey(ValueKey('mittelschmerzCell-$i')),
          findsNothing,
          reason: 'the M renders inside the plot (inPlotM), not as a cell',
        );
        expect(
          find.byKey(ValueKey('marksCell-$i')),
          findsNothing,
          reason:
              'the 1–6 numbering renders inside the plot '
              '(inPlotDayNumber), not as a cell',
        );
      }
      expect(chartCellCorner('mittelschmerz'), findsNothing);
    });

    testWidgets('the rows render in the paper order — bleeding alone on '
        'top — and the below-chart strip follows with time first, notes '
        'last', (tester) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      double top(String row) => tester.getRect(chartCellCorner(row)).top;
      // The below-chart strip keeps the owner-decided order (time first,
      // notes last): time, disturbance, notes band after the top
      // segment and the curve.
      expect(
        top('time'),
        greaterThan(tester.getRect(chartCellCorner('bleeding')).bottom),
        reason:
            'the below-chart strip starts after the top segment '
            'and the curve',
      );
      expect(top('disturbance'), greaterThan(top('time')));
      expect(top('notesBand'), greaterThan(top('disturbance')));
    });

    testWidgets('the Mittelschmerz M renders INSIDE the plot below the '
        'mucus letters, column-centered; the band keeps only B', (
      tester,
    ) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      final plot = tester.getRect(find.byType(LineChart));
      final data = chartData(tester);
      final span = data.maxY - data.minY;
      final colW = plot.width / _dayCount;
      final mRect = tester.getRect(find.byKey(const ValueKey('inPlotM-4')));
      // Day 4 = the fixture's Mittelschmerz day (beside its mucus S).
      expect(
        mRect.center.dy,
        closeTo(plot.top + mRowCenterOffsetK / span * plot.height, 0.5),
        reason: 'the M pins at the $mRowCenterOffsetK K pitch',
      );
      expect(
        mRect.center.dx,
        closeTo(plot.left + (4 + 0.5) * colW, 1),
        reason: 'the M centers in its day column',
      );
      expect(
        mRect.center.dy,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('inPlotMucus-4'))).bottom,
        ),
        reason: 'the M renders below the day\'s mucus letters',
      );
      expect(
        find.byKey(const ValueKey('inPlotHaloM-4')),
        findsOneWidget,
        reason: 'the M ink carries its halo layer',
      );
      // The other days carry no M; the band keeps only B.
      expect(find.byKey(const ValueKey('inPlotM-7')), findsNothing);
      expect(
        chartCellContent(4, 'notesBand', find.text('M')),
        findsNothing,
        reason: 'the band never carries the M letter',
      );
      expect(
        find.byKey(const ValueKey('painBreastGlyph-7')),
        findsOneWidget,
        reason: 'breast pain B renders in the band\'s pain row',
      );
    });

    testWidgets('tapping a top-strip cell opens the day sheet', (tester) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      await tester.tap(chartCell(4, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(
        sheet.day,
        _rowsDay(4),
        reason: 'the top-strip bleeding cell keeps its tap behavior',
      );
    });
  });

  group('per-signal rows', () {
    testWidgets('every signal row renders for every windowed day, in order '
        'bleeding, time, disturbance, notes band', (tester) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      for (var i = 0; i < _dayCount; i++) {
        for (final row in _signalRows) {
          expect(
            chartCell(i, row),
            findsOneWidget,
            reason:
                'row $row renders a cell for day index $i '
                '(rows always render, even empty/untracked days)',
          );
        }
      }

      // Row ORDER: the corner slots appear top-down bleeding .. notes band
      // (paper layout: bleeding alone inside the top of the temperature
      // block, the rest in the below-chart strip, time first).
      final corners = _signalRows.map(
        (row) => tester.getRect(chartCellCorner(row)),
      );
      final tops = corners.map((r) => r.top).toList();
      expect(
        tops,
        equals([...tops]..sort()),
        reason: 'the signal rows render in the paper\'s order',
      );
    });

    testWidgets('each row\'s corner slot carries a sample glyph with a tooltip '
        'and a semantics label carrying the localized row name (en)', (
      tester,
    ) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      final rowNames = {
        'bleeding': 'Bleeding',
        'disturbance': 'Disturbed measurement',
        'time': 'Measurement time',
        'notesBand': 'Note',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        expect(find.byKey(ValueKey('${key}Corner')), findsOneWidget);
        final tooltips = tester
            .widgetList<Tooltip>(
              find.descendant(
                of: chartCellCorner(key),
                matching: find.byType(Tooltip),
              ),
            )
            .map((t) => t.message)
            .toList();
        expect(tooltips, [
          value,
        ], reason: 'row $key\'s corner slot carries the localized row name');
        expect(
          find.descendant(
            of: chartCellCorner(key),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == value,
            ),
          ),
          findsOneWidget,
          reason:
              'row $key\'s corner slot announces the row name to '
              'screen readers',
        );
      }

      // The corner sample glyphs: a bleeding box and the sticky-note band
      // sample.
      expect(
        find.descendant(
          of: chartCellCorner('bleeding'),
          matching: find.byType(BleedingSymbol),
        ),
        findsOneWidget,
        reason:
            'the bleeding corner shows the box sample (dotted '
            'spotting, like the row\'s cells render it)',
      );
      expect(
        find.descendant(
          of: chartCellCorner('notesBand'),
          matching: find.byIcon(Icons.sticky_note_2_outlined),
        ),
        findsOneWidget,
        reason:
            'the band corner shows the sticky-note sample (the cervix '
            'and breast-pain vocabulary has no extra rail corner: it '
            'lives in the band itself)',
      );
      expect(
        find.descendant(
          of: chartCellCorner('time'),
          matching: find.byIcon(Icons.schedule),
        ),
        findsOneWidget,
        reason: 'the time corner keeps the clock icon sample',
      );
    });

    testWidgets('the row names use the German wording in de', (tester) async {
      await pumpChart(
        tester,
        _rowsHarness(entries: _rowsEntries, locale: const Locale('de')),
      );

      final rowNames = {
        'bleeding': 'Blutung',
        'disturbance': 'Messstörung',
        'time': 'Messzeitpunkt',
        'notesBand': 'Notiz',
      };
      for (final MapEntry(:key, :value) in rowNames.entries) {
        final tooltips = tester
            .widgetList<Tooltip>(
              find.descendant(
                of: chartCellCorner(key),
                matching: find.byType(Tooltip),
              ),
            )
            .map((t) => t.message)
            .toList();
        expect(tooltips, [value], reason: 'de: row $key is $value');
      }
    });

    testWidgets('long-pressing a corner slot shows the row-name tooltip', (
      tester,
    ) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      // The tooltip overlay shows the localized row name. The bare text
      // can pre-exist elsewhere (the legend's "Bleeding" entry), so pin
      // the OVERLAY as one additional occurrence of the word.
      final before = tester.widgetList<Text>(find.text('Bleeding')).length;
      await tester.longPress(find.byKey(const ValueKey('bleedingCorner')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Bleeding'),
        findsNWidgets(before + 1),
        reason: 'long-press shows the row-name tooltip overlay',
      );
    });

    testWidgets('at minimum column width the time renders vertically — never '
        'dropped (wide columns keep the horizontal text, see the wide '
        'HH:mm test above and the measurement-time section)', (tester) async {
      Finder timeCellFinder() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('timeCell-'),
      );

      // 60 days overflow the viewport: columns render at the minimum
      // usable width (24 px), below the horizontal threshold. The initial
      // auto-scroll puts the newest days' cells on screen.
      await pumpChart(
        tester,
        _rowsHarness(
          entries: [
            for (var i = 0; i < 60; i++)
              DailyEntry(
                date: _rowsDay(i),
                bbtC: 36.5,
                measuredAtMinutes: 6 * 60 + 30,
              ),
          ],
        ),
      );

      expect(
        timeCellFinder(),
        findsWidgets,
        reason: 'the initial window renders time cells',
      );
      expect(
        find.descendant(of: timeCellFinder(), matching: find.text('06:30')),
        findsWidgets,
        reason:
            'the recorded time renders at the minimum column width — '
            'vertically (the old behavior dropped it)',
      );
      expect(
        find.descendant(of: timeCellFinder(), matching: find.byType(Text)),
        findsWidgets,
      );
    });

    testWidgets('no per-day clock icon exists anywhere in the signal rows', (
      tester,
    ) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      // The ONLY clock icon in the signal rows is the time row's corner
      // sample; the day cells never carry one (the old per-day clock
      // glyph is gone).
      for (var i = 0; i < _dayCount; i++) {
        expect(
          find.descendant(
            of: chartCell(i, 'time'),
            matching: find.byIcon(Icons.schedule),
          ),
          findsNothing,
          reason: 'day $i: no clock icon in the time cell',
        );
      }
      expect(
        find.descendant(
          of: chartCellCorner('time'),
          matching: find.byIcon(Icons.schedule),
        ),
        findsOneWidget,
        reason: 'only the corner sample keeps a clock icon',
      );
    });

    testWidgets('tapping a signal row cell opens the day\'s sheet', (
      tester,
    ) async {
      await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

      await tester.tap(chartCell(3, 'bleeding'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(
        sheet.day,
        _rowsDay(3),
        reason: 'the tapped bleeding cell owns day 3',
      );
    });

    // The bleeding row renders the shared square-box convention (see
    // lib/ui/bleeding_symbol.dart): the cell box is the fill boundary, the
    // fill is a bottom-anchored fraction of the box height, and the
    // spotting level interrupts its quarter band into dots. The geometry
    // is measured with getRect so the convention cannot drift between the
    // chart cells, the diary tiles and the glossary sample.
    testWidgets(
      'bleeding cells fill a bottom-anchored fraction of the cell box',
      (tester) async {
        await pumpChart(tester, _rowsHarness(entries: _bleedingRowEntries));

        final errorColor = chartScheme(tester).error;

        // The menstruation levels: cell index → (level, fill fraction of the
        // box height).
        final expectations = {
          1: (Bleeding.light, 1 / 4),
          3: (Bleeding.medium, 2 / 4),
          4: (Bleeding.heavy, 3 / 4),
          5: (Bleeding.maximum, 4 / 4),
        };
        for (final MapEntry(:key, :value) in expectations.entries) {
          final (level, fraction) = value;
          final cell = tester.getRect(chartCell(key, 'bleeding'));
          expect(
            _bleedingFills(key),
            findsOneWidget,
            reason: '$level draws exactly one solid fill region',
          );
          final fill = tester.widget<BleedingFill>(_bleedingFills(key));
          expect(
            fill.color,
            errorColor,
            reason: '$level fills with the bleeding color',
          );
          final rect = tester.getRect(_bleedingFills(key));
          expect(
            rect.height,
            closeTo(cell.height * fraction, 0.01),
            reason: '$level fills $fraction of the box height',
          );
          expect(
            rect.bottom,
            closeTo(cell.bottom, 0.01),
            reason: '$level: the fill is anchored at the box\'s bottom',
          );
          expect(
            rect.left,
            closeTo(cell.left, 0.01),
            reason:
                '$level: the fill spans the full cell width — the '
                'table cell box serves as the fill boundary',
          );
        }

        // Day 0 records bleeding "none": the cell stays empty.
        expect(
          _bleedingFills(0),
          findsNothing,
          reason: 'bleeding none keeps the empty cell',
        );
      },
    );

    testWidgets(
      'spotting renders an interrupted dotted fill in the bottom quarter '
      'band, not a solid quarter bar',
      (tester) async {
        await pumpChart(tester, _rowsHarness(entries: _bleedingRowEntries));

        final cell = tester.getRect(chartCell(2, 'bleeding'));
        final bandTop = cell.top + cell.height * 3 / 4;
        final dots = _bleedingFills(2).evaluate();
        expect(
          dots.length,
          greaterThanOrEqualTo(3),
          reason: 'spotting interrupts the 1/4 band into several dots',
        );

        final rects = [
          for (var i = 0; i < dots.length; i++)
            tester.getRect(_bleedingFills(2).at(i)),
        ];
        for (final rect in rects) {
          expect(
            rect.top,
            greaterThanOrEqualTo(bandTop - 0.01),
            reason: 'the dots stay inside the bottom quarter band',
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(cell.bottom + 0.01),
            reason: 'the dots stay inside the bottom quarter band',
          );
        }
        final sorted = [...rects]..sort((a, b) => a.left.compareTo(b.left));
        for (var i = 1; i < sorted.length; i++) {
          expect(
            sorted[i].left,
            greaterThanOrEqualTo(sorted[i - 1].right),
            reason: 'the dots are disjoint regions, not one merged bar',
          );
        }
        expect(
          sorted.last.right - sorted.first.left,
          lessThan(cell.width),
          reason: 'the dotted fill never reads as a solid quarter bar',
        );
      },
    );

    // Cross-check at a narrow viewport (the same device class the diary
    // sign-row repro used): the in-plot mucus letters render at the
    // minimum usable column width (24 px, forced by a range longer than
    // the 320 dp viewport). The two widest glyph shapes (the two-glyph
    // f/S token, and the S glyph with its EW superscript) must lay out
    // without a framework exception in their 24 px columns.
    testWidgets('the in-plot mucus letters render at the minimum column width '
        'without a framework exception', (tester) async {
      useNarrowPhoneViewport(tester);

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
        await pumpChart(tester, _rowsHarness(entries: entries));
      } finally {
        FlutterError.onError = originalOnError;
      }

      // The initial auto-scroll parks the window on the newest days, so
      // both mucus days render — the letters are keyed glyphs themselves.
      final fDay = tester.widget<MucusSymbolText>(
        find.byKey(const ValueKey('inPlotMucus-10')),
      );
      expect(fDay.display!.symbol, 'f/S');
      final sDay = tester.widget<MucusSymbolText>(
        find.byKey(const ValueKey('inPlotMucus-11')),
      );
      expect(sDay.display!.superscript, 'EW');
      expect(
        errors,
        isEmpty,
        reason:
            'the mucus glyphs must lay out without a framework '
            'exception at the minimum column width',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════ in-plot signal glyphs ═══════════
  // The raw sex/mucus observations, the mucus peak and the Mittelschmerz M
  // render INSIDE the temperature plot (mapped by the pure layer in
  // lib/ui/chart_marks.dart) — in the day's column, at the row pitches
  // −0.05 K (sex X), −0.15 K (peak dot), −0.25 K (mucus letter) and −0.35 K
  // (M) below the scale max, keyed `inPlot*` per day; every ink glyph
  // carries a `inPlotHalo*` stroke pass behind it. The top strip carries
  // only bleeding (see the rows section).

  DateTime inPlotDay(int index) => DateTime.utc(2026, 9, 7 + index);

  // Five chart days:
  //  0: mucus S with EW quality AND the peak mark on it -> letter + dot
  //  1: sex at all three timings            -> three X marks in one column
  //  2: sex at the START slot only          -> one X at the start fraction
  //  3: mucus f (plain, no peak mark)       -> bare letter, no dot
  //  4: plain temperature day               -> no in-plot glyphs
  List<DailyEntry> inPlotEntries() => [
    DailyEntry(
      date: inPlotDay(0),
      bbtC: 36.5,
      mucusSign: MucusSign.s,
      mucusQuality: MucusQuality.ew,
    ),
    DailyEntry(
      date: inPlotDay(1),
      bbtC: 36.6,
      sexTimings:
          SexTiming.morning.bit | SexTiming.midday.bit | SexTiming.evening.bit,
    ),
    DailyEntry(
      date: inPlotDay(2),
      bbtC: 36.7,
      sexTimings: SexTiming.morning.bit,
    ),
    DailyEntry(date: inPlotDay(3), bbtC: 36.4, mucusSign: MucusSign.f),
    DailyEntry(date: inPlotDay(4), bbtC: 36.5),
  ];

  final inPlotMarks = [
    CycleMark(date: inPlotDay(0), type: CycleMarkTypes.mucusPeakDay),
  ];

  Widget inPlotHarness({TemperatureRange? range}) => chartHarness(
    entries: inPlotEntries(),
    marks: inPlotMarks,
    temperatureRange: range,
  );

  testWidgets('the in-plot glyph rows render per day: sex X marks by timing, '
      'mucus letters, and the peak dot on every peak-marked day — with its '
      'entry or alone', (tester) async {
    await pumpChart(tester, inPlotHarness());

    expect(find.byKey(const ValueKey('inPlotMucus-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotPeakDot-0')), findsOneWidget);
    for (final timing in SexTiming.values) {
      expect(
        find.byKey(ValueKey('inPlotSex-1-${timing.name}')),
        findsOneWidget,
        reason: 'the all-three-timings day renders the $timing X',
      );
    }
    expect(find.byKey(const ValueKey('inPlotSex-2-morning')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotSex-2-midday')),
      findsNothing,
      reason: 'no X for an unrecorded timing',
    );
    expect(find.byKey(const ValueKey('inPlotMucus-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotPeakDot-3')),
      findsNothing,
      reason: 'no dot without the peak mark',
    );
    expect(
      find.byKey(const ValueKey('inPlotMucus-4')),
      findsNothing,
      reason: 'a sign-free day renders no letter',
    );
    expect(find.byKey(const ValueKey('inPlotSex-4-morning')), findsNothing);
  });

  testWidgets('a peak-marked interior GAP day renders the dot alone: the dot '
      'hangs on the day, no letter X M or number joins it there, and an '
      'unflagged gap day draws no dot', (tester) async {
    final gapEntries = [
      DailyEntry(date: inPlotDay(0), bbtC: 36.5, mucusSign: MucusSign.s),
      DailyEntry(
        date: inPlotDay(2),
        bbtC: 36.7,
        sexTimings: SexTiming.morning.bit,
      ),
      DailyEntry(date: inPlotDay(4), bbtC: 36.5),
    ];
    final gapMarks = [
      CycleMark(date: inPlotDay(1), type: CycleMarkTypes.mucusPeakDay),
    ];
    await pumpChart(tester, chartHarness(entries: gapEntries, marks: gapMarks));

    expect(find.byKey(const ValueKey('inPlotPeakDot-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotHaloPeakDot-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotMucus-1')),
      findsNothing,
      reason: 'a day without an entry renders no letter',
    );
    for (final timing in SexTiming.values) {
      expect(find.byKey(ValueKey('inPlotSex-1-${timing.name}')), findsNothing);
    }
    expect(find.byKey(const ValueKey('inPlotM-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('inPlotPeakDot-3')),
      findsNothing,
      reason: 'the unflagged gap day 3 carries no dot',
    );
  });

  testWidgets('each in-plot glyph sits at its column center (multi-timing '
      'Xs at their timing fraction) and at its row pitch under the top '
      'edge', (tester) async {
    await pumpChart(tester, inPlotHarness());

    final plot = tester.getRect(find.byType(LineChart));
    final data = chartData(tester);
    final span = data.maxY - data.minY;
    final colW = plot.width / inPlotEntries().length;
    double expectedCenterY(double offsetK) =>
        plot.top + offsetK / span * plot.height;

    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotMucus-0'))).center.dx,
      closeTo(plot.left + 0.5 * colW, 1),
      reason: 'the mucus letter centers in its day column',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotPeakDot-0'))).center.dx,
      closeTo(plot.left + 0.5 * colW, 1),
      reason: 'the peak dot centers in its day column',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotPeakDot-0'))).center.dy,
      closeTo(expectedCenterY(peakDotCenterOffsetK), 0.5),
      reason: 'the peak dot pins at its own row pitch, above the letter',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotMucus-0'))).center.dy,
      closeTo(expectedCenterY(mucusRowCenterOffsetK), 0.5),
      reason: 'the mucus letter pins at the letters row pitch',
    );

    final fractions = {'morning': 1 / 6, 'midday': 0.5, 'evening': 5 / 6};
    for (final MapEntry(:key, :value) in fractions.entries) {
      expect(
        tester.getRect(find.byKey(ValueKey('inPlotSex-1-$key'))).center.dx,
        closeTo(plot.left + (1 + value) * colW, 1),
        reason: 'the $key-timing X sits at its fraction in ONE column',
      );
      expect(
        tester.getRect(find.byKey(ValueKey('inPlotSex-1-$key'))).center.dy,
        closeTo(expectedCenterY(sexRowCenterOffsetK), 0.5),
        reason: 'the sex X pins at the topmost glyph row pitch',
      );
    }
    expect(
      tester
          .getRect(find.byKey(const ValueKey('inPlotSex-2-morning')))
          .center
          .dx,
      closeTo(plot.left + (2 + 1 / 6) * colW, 1),
    );
  });

  testWidgets('a surface-colored halo layer renders behind the sex, mucus '
      'and peak-dot glyphs, exactly centered', (tester) async {
    await pumpChart(tester, inPlotHarness());

    for (final haloKey in const [
      'inPlotHaloSex-2-morning',
      'inPlotHaloMucus-0',
      'inPlotHaloPeakDot-0',
    ]) {
      final halo = find.byKey(ValueKey(haloKey));
      expect(halo, findsOneWidget, reason: '$haloKey renders behind its ink');
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('inPlotHaloPeakDot-0'))).center,
      tester.getRect(_peakDot(0)).center,
      reason: 'the dot\'s halo backing sits exactly behind the dot',
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('inPlotHaloSex-2-morning')))
          .center,
      tester.getRect(find.byKey(const ValueKey('inPlotSex-2-morning'))).center,
      reason: 'the X halo sits exactly behind the ink',
    );
  });

  testWidgets('the in-plot glyphs keep the rows\' color roles at the shared '
      'mark alpha: X onSurface, letter and dot tertiary', (tester) async {
    await pumpChart(tester, inPlotHarness());

    final scheme = chartScheme(tester);
    // MucusSymbolText's outer RichText carries the DEFAULT text style; the
    // tertiary ink is the wrapped base span inside it.
    final letterSpan =
        tester
                .widgetList<RichText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('inPlotMucus-0')),
                    matching: find.byType(RichText),
                  ),
                )
                .map((rich) => rich.text)
                .whereType<TextSpan>()
                .where((span) => span.children != null)
                .single
                .children!
                .single
            as TextSpan;
    expect(
      letterSpan.style!.color,
      scheme.tertiary.withValues(alpha: chartMarkAlpha),
      reason: 'the mucus letter keeps the tertiary ink at 0.85 alpha',
    );
    expect(
      (tester.widget<Container>(_peakDot(0)).decoration as BoxDecoration).color,
      scheme.tertiary.withValues(alpha: chartMarkAlpha),
      reason: 'the peak dot shares the letter\'s tertiary ink',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('inPlotSex-2-morning')))
          .style!
          .color,
      scheme.onSurface.withValues(alpha: chartMarkAlpha),
      reason: 'the sex X keeps the neutral onSurface ink at 0.85 alpha',
    );
  });

  testWidgets('a span-0.20 range keeps the sex row AND the peak dot '
      '(decoupled rows) and hides the mucus letters', (tester) async {
    await pumpChart(
      tester,
      inPlotHarness(range: const TemperatureRange(min: 37.8, max: 38.0)),
    );

    expect(
      find.byKey(const ValueKey('inPlotMucus-0')),
      findsNothing,
      reason: 'the 0.2 K span leaves no room for the letter row',
    );
    expect(find.byKey(const ValueKey('inPlotMucus-3')), findsNothing);
    expect(
      _peakDot(0),
      findsOneWidget,
      reason:
          'the peak dot is its own row: at span 0.20 its center lands '
          'exactly on the bottom margin — visible',
    );
    for (final timing in SexTiming.values) {
      expect(
        find.byKey(ValueKey('inPlotSex-1-${timing.name}')),
        findsOneWidget,
        reason: 'the $timing X stays — the sex row hides independently',
      );
    }
  });

  testWidgets('at the 0.10 boundary only the sex row (top margin) stays '
      'visible; below it every top row hides', (tester) async {
    // min + 0.05 = 37.95, max − 0.05 = 37.95 at the span-0.10 boundary:
    // the sex row's center lands exactly on the margin (visible), the
    // peak dot one 0.1-gap below it does not.
    await pumpChart(
      tester,
      inPlotHarness(range: const TemperatureRange(min: 37.9, max: 38.0)),
    );

    for (final timing in SexTiming.values) {
      expect(
        find.byKey(ValueKey('inPlotSex-1-${timing.name}')),
        findsOneWidget,
        reason: 'the $timing X stays at the boundary equality',
      );
    }
    expect(_peakDot(0), findsNothing);
    expect(find.byKey(const ValueKey('inPlotMucus-0')), findsNothing);
    expect(find.byKey(const ValueKey('inPlotMucus-3')), findsNothing);
  });

  testWidgets('a span-0.30 range shows the mucus letters at their boundary '
      'but still hides the M row below', (tester) async {
    await pumpChart(
      tester,
      _rowsHarness(
        entries: _rowsEntries,
        range: const TemperatureRange(min: 37.7, max: 38.0),
      ),
    );

    expect(
      find.byKey(const ValueKey('inPlotMucus-4')),
      findsOneWidget,
      reason: 'the letters row lands exactly on the bottom margin — visible',
    );
    expect(
      find.byKey(const ValueKey('inPlotM-4')),
      findsNothing,
      reason: 'the 0.3 K span leaves no room for the M row',
    );
  });

  testWidgets('at the 0.40 boundary the M row appears', (tester) async {
    await pumpChart(
      tester,
      _rowsHarness(
        entries: _rowsEntries,
        range: const TemperatureRange(min: 37.6, max: 38.0),
      ),
    );

    expect(
      find.byKey(const ValueKey('inPlotM-4')),
      findsOneWidget,
      reason: 'the M row lands exactly on the bottom margin — visible',
    );
  });

  testWidgets('the bottom-anchored day numbers hide when the span drops '
      'below 0.10 and stay visible at the boundary', (tester) async {
    // Numbers hidden: the center at min + 0.05 = 36.05 exceeds max − 0.05
    // = 36.03 when the span is 0.08.
    await pumpChart(
      tester,
      _harness(
        entries: _evaluationEntries,
        marks: _marks,
        range: const TemperatureRange(min: 36.0, max: 36.08),
      ),
    );
    for (var i = 0; i < _evaluationEntries.length; i++) {
      expect(
        _numberUnder(tester, i),
        isNull,
        reason: 'day $i: the 0.08 K span hides the numbers row',
      );
    }

    // Boundary span 0.10: the center at min + 0.05 = max − 0.05 — visible.
    // Remount the app per iteration: a same-shaped re-pump would only
    // update the const-canonicalized subtree in place and keep the old
    // provider range.
    await pumpChart(
      tester,
      KeyedSubtree(
        key: UniqueKey(),
        child: _harness(
          entries: _evaluationEntries,
          marks: _marks,
          range: const TemperatureRange(min: 36.0, max: 36.1),
        ),
      ),
    );
    expect(
      _numberUnder(tester, 7),
      '1',
      reason: 'the numbers row reads the boundary equality as visible',
    );
  });

  testWidgets('the mucus and sex signal rows are gone: no day cells, no '
      'corner slots, no row peak dots — and only the two observation '
      'kinds render in the plot', (tester) async {
    await pumpChart(tester, _rowsHarness(entries: _rowsEntries));

    for (var i = 0; i < _dayCount; i++) {
      expect(
        find.byKey(ValueKey('mucusCell-$i')),
        findsNothing,
        reason: 'mucus letters render in the plot, not as row cells',
      );
      expect(
        find.byKey(ValueKey('sexCell-$i')),
        findsNothing,
        reason: 'the X marks render in the plot, not as row cells',
      );
    }
    expect(find.byKey(const ValueKey('mucusCorner')), findsNothing);
    expect(find.byKey(const ValueKey('sexCorner')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('peakDot-'),
      ),
      findsNothing,
      reason:
          'no row-rendered peak dot key remains — the dot renders '
          'in-plot as inPlotPeakDot-*',
    );

    // The complete set of in-plot keys: the fixture's recorded
    // observations are day 4's S+EW mucus plus its Mittelschmerz M and
    // day 6's start-slot sex — no exclusion marks render in the plot.
    final inPlotKeys = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('inPlot'),
          ),
        )
        .map((w) => (w.key! as ValueKey<String>).value)
        .toSet();
    expect(
      inPlotKeys,
      {
        'inPlotMucus-4',
        'inPlotHaloMucus-4',
        'inPlotM-4',
        'inPlotHaloM-4',
        'inPlotSex-6-morning',
        'inPlotHaloSex-6-morning',
      },
      reason:
          'only the mucus letters, the M, the X marks and their halos '
          'render in the plot',
    );
  });

  // ═══════════ temperature curve ═══════════
  // former test/cycle_chart_temperature_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('adjacent-day connectivity', () {
    testWidgets('two readings on adjacent days connect', (tester) async {
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 36.6),
          ],
        ),
      );

      expect(
        _connects(tester, 0, 1),
        isTrue,
        reason: 'adjacent calendar days are drawn as one segment',
      );
    });

    testWidgets('a day with no temperature between readings breaks the line', (
      tester,
    ) async {
      // Saturday has an entry, but WITHOUT a temperature, and a Sunday with
      // no entry at all behind it: neither gap may be bridged by the curve.
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bleeding: Bleeding.medium),
            DailyEntry(date: _temperatureSat, bbtC: 36.7),
            DailyEntry(date: _temperatureSun, bbtC: 36.8),
          ],
        ),
      );

      expect(
        _spansAGap(tester),
        isFalse,
        reason: 'a measured day without temperature still breaks the line',
      );
      // The measured days BEHIND the gap stay connected among themselves.
      expect(
        _connects(tester, 2, 3),
        isTrue,
        reason: 'adjacent readings after the gap still connect',
      );
    });

    testWidgets('a day with no entry at all breaks the line too', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureSat, bbtC: 36.7),
          ],
        ),
      );

      // Both days are lone dots; nothing connects index 0 to index 2.
      expect(
        _spansAGap(tester),
        isFalse,
        reason: 'gap between day 0 and day 2: no segment may be drawn',
      );
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
      date: _temperatureFri,
      type: CycleMarkTypes.ignoreTemperature,
    );

    /// The scheme color the chart derives its normal (opaque) color from.
    Color normalColor(WidgetTester tester) =>
        _themeOf(tester).colorScheme.primary;

    testWidgets('the line stays continuous through the ignored day — and both '
        'segments touching it render lighter', (tester) async {
      await pumpChart(
        tester,
        _temperatureHarness(entries: ignoredMiddle, marks: [friMark]),
      );

      expect(
        _connects(tester, 0, 1),
        isTrue,
        reason: 'ignored temperature counts as a measured day',
      );
      expect(
        _connects(tester, 1, 2),
        isTrue,
        reason: 'the line continues through the ignored day',
      );
      for (final bar in _segmentBars(tester)) {
        final color = bar.color!;
        expect(
          color.a,
          closeTo(0.4, 1e-6),
          reason: 'both segments touch the ignored day -> lighter tint',
        );
        // Lighter = theme color at reduced alpha, not a different hue.
        expect(color.r, normalColor(tester).r);
        expect(color.g, normalColor(tester).g);
        expect(color.b, normalColor(tester).b);
      }
    });

    testWidgets(
      'the ignored dot renders lighter, normal dots stay opaque — the '
      'mark alone dims the curve, no disturbance flags needed',
      (tester) async {
        // Headline new behavior (owner decision 2026-09-19): the mark is
        // the visible state, flags are surfaced by other means (diary
        // badge). Fri carries ONLY the mark — no tempDisturbances — and
        // still renders lighter.
        final unflaggedMarked = <DailyEntry>[
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(date: _temperatureFri, bbtC: 36.6), // mask 0
          DailyEntry(date: _temperatureSat, bbtC: 36.7),
        ];
        await pumpChart(
          tester,
          _temperatureHarness(entries: unflaggedMarked, marks: [friMark]),
        );

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
          final painter =
              dotBars.first.dotData.getDotPainter(spot, 0, dotBars.first, i)
                  as FlDotCirclePainter;
          painterByIndex[spot.x.round()] = painter.color;
        }
        expect(
          painterByIndex[0]!.a,
          1.0,
          reason: 'an ordinary measurement keeps the full-strength dot',
        );
        expect(
          painterByIndex[1]!.a,
          closeTo(0.4, 1e-6),
          reason:
              'the ignored dot renders lighter — a marked day WITHOUT '
              'flags renders lighter (the mark alone dims the curve)',
        );
        expect(painterByIndex[1]!.r, normalColor(tester).r);
        expect(painterByIndex[1]!.g, normalColor(tester).g);
        expect(painterByIndex[1]!.b, normalColor(tester).b);
        for (final bar in _segmentBars(tester)) {
          expect(
            bar.color!.a,
            closeTo(0.4, 1e-6),
            reason: 'both segments touch the marked day -> lighter tint',
          );
        }
      },
    );

    testWidgets('a flagged day WITHOUT the mark renders at FULL alpha '
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
          tempDisturbances: TempDisturbance.kr.bit,
        ),
        DailyEntry(date: _temperatureSat, bbtC: 36.7),
      ];
      await pumpChart(tester, _temperatureHarness(entries: flaggedUnmarked));

      for (final bar in _segmentBars(tester)) {
        expect(
          bar.color!.a,
          1.0,
          reason:
              'flags without the mark render at full alpha — the '
              'raw mask is no longer a rendering input',
        );
      }
      final dotBars = [
        for (final bar in _bars(tester))
          if (bar.color == null || bar.color!.a == 0) bar,
      ];
      for (var i = 0; i < dotBars.single.spots.length; i++) {
        final painter =
            dotBars.single.dotData.getDotPainter(
                  dotBars.single.spots[i],
                  0,
                  dotBars.single,
                  i,
                )
                as FlDotCirclePainter;
        expect(
          painter.color.a,
          1.0,
          reason:
              'the flagged-but-unmarked dot keeps the full-strength '
              'color',
        );
      }
    });

    testWidgets(
      'a marked AND flagged day renders lighter (mark-keyed, even with '
      'raw flags)',
      (tester) async {
        // The typical interrupted day carries both: the raw mask (flags)
        // AND the manually placed ignoreTemperature mark — still lighter
        // (mark-keyed).
        final flaggedMarked = <DailyEntry>[
          DailyEntry(date: _temperatureThu, bbtC: 36.5),
          DailyEntry(
            date: _temperatureFri,
            bbtC: 36.6,
            tempDisturbances: TempDisturbance.kr.bit,
          ),
          DailyEntry(date: _temperatureSat, bbtC: 36.7),
        ];
        await pumpChart(
          tester,
          _temperatureHarness(entries: flaggedMarked, marks: [friMark]),
        );

        for (final bar in _segmentBars(tester)) {
          expect(
            bar.color!.a,
            closeTo(0.4, 1e-6),
            reason:
                'marked + flagged renders lighter (the mark is the '
                'rendering key)',
          );
        }
      },
    );

    testWidgets('two consecutive ignored days connect with a lighter segment', (
      tester,
    ) async {
      // Thu and Fri both measured AND both ignored (marks): one segment,
      // but every part of it — line and both dots — renders lighter.
      final marks = [
        CycleMark(
          date: _temperatureThu,
          type: CycleMarkTypes.ignoreTemperature,
        ),
        friMark,
      ];
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 36.6),
          ],
          marks: marks,
        ),
      );

      expect(
        _segmentBars(tester),
        hasLength(1),
        reason: 'the two adjacent ignored days form exactly one segment',
      );
      final segment = _segmentBars(tester).single;
      expect(
        segment.color!.a,
        closeTo(0.4, 1e-6),
        reason: 'the segment between two ignored days is lighter',
      );
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
        final painter =
            dotBars.first.dotData.getDotPainter(
                  dotBars.first.spots[i],
                  0,
                  dotBars.first,
                  i,
                )
                as FlDotCirclePainter;
        expect(
          painter.color.a,
          closeTo(0.4, 1e-6),
          reason:
              'ignored dot ${dotBars.first.spots[i].x.round()} '
              'renders lighter',
        );
        expect(painter.color.r, normalColor(tester).r);
        expect(painter.color.g, normalColor(tester).g);
        expect(painter.color.b, normalColor(tester).b);
      }
    });

    testWidgets(
      'ignored dot at a run edge connects to the adjacent normal day',
      (tester) async {
        // Fri: ignored; Sat: normal. The ignored edge day is still drawn
        // connected — adjacency, not the mark, decides connectivity.
        await pumpChart(
          tester,
          _temperatureHarness(
            entries: [
              DailyEntry(date: _temperatureThu, bbtC: 36.5),
              DailyEntry(date: _temperatureFri, bbtC: 36.2),
              DailyEntry(date: _temperatureSat, bbtC: 37.0),
            ],
            marks: [friMark],
          ),
        );

        expect(
          _connects(tester, 1, 2),
          isTrue,
          reason: 'ignored run-edge day connects to its adjacent day',
        );
        final segment = _segmentBars(
          tester,
        ).firstWhere((bar) => bar.spots.length == 2 && bar.spots[0].x == 1);
        expect(
          segment.color!.a,
          closeTo(0.4, 1e-6),
          reason: 'the segment touching the ignored edge day is lighter',
        );
      },
    );

    testWidgets('ignored-temp segments stay dark in dark mode', (tester) async {
      useDarkDeviceBrightness(tester);

      await pumpChart(
        tester,
        _temperatureHarness(entries: ignoredMiddle, marks: [friMark]),
      );

      final darkScheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .darkTheme!
          .colorScheme;
      expect(
        _segmentBars(tester).map((b) => b.color!),
        everyElement(equals(darkScheme.primary.withValues(alpha: 0.4))),
        reason:
            'dark scheme: light primary at reduced alpha, still led by '
            'the (bright) scheme color — readable on the dark surface',
      );
      expect(
        darkScheme.primary.computeLuminance(),
        greaterThan(0.3),
        reason: 'the lighter segments keep darkness-readable contrast',
      );
    });
  });

  group('adaptive chart height (span of the settings range)', () {
    double chartHeight(WidgetTester tester) =>
        tester.getRect(find.byType(LineChart)).height;

    testWidgets(
      'the plot height follows the settings range\'s span: base height '
      'inside the comfortable ~3 °C, growth beyond it, capped at 400',
      (tester) async {
        // One case per settings-range shape: the default 36–38 °C range
        // spans 2 °C (inside the comfortable ~3 °C span, so no growth
        // regardless of the recorded values), the 36.0..40.5 range spans
        // 4.5 °C: 260 base plus 1.5 °C beyond the comfortable 3 °C at
        // 80 px per degree, and the window maximum 34.0..42.0 spans 8 °C,
        // far past the growth range.
        final cases =
            <
              ({
                TemperatureRange? range,
                List<DailyEntry> entries,
                double expectedHeight,
                String heightReason,
              })
            >[
              (
                range: null,
                entries: [
                  for (var i = 0; i < 5; i++)
                    DailyEntry(
                      date: _temperatureThu.add(Duration(days: i)),
                      bbtC: 36.5,
                    ),
                ],
                expectedHeight: 260.0,
                heightReason: 'a comfortable ~2 °C range needs the base height',
              ),
              (
                range: const TemperatureRange(min: 36.0, max: 40.5),
                entries: [
                  DailyEntry(date: _temperatureThu, bbtC: 36.5),
                  DailyEntry(date: _temperatureFri, bbtC: 40.0),
                ],
                expectedHeight: 380.0,
                heightReason:
                    'a 4.5 °C span grows the plot: 260 + (4.5 − 3) × 80',
              ),
              (
                range: const TemperatureRange(min: 34.0, max: 42.0),
                entries: [
                  DailyEntry(date: _temperatureThu, bbtC: 34.5),
                  DailyEntry(date: _temperatureFri, bbtC: 41.5),
                ],
                expectedHeight: 400.0,
                heightReason: 'the growth is capped at 400',
              ),
            ];
        for (final (:range, :entries, :expectedHeight, :heightReason)
            in cases) {
          await pumpChart(
            tester,
            // Remount per case so no previous case's chart state can leak
            // into the next pump.
            KeyedSubtree(
              key: UniqueKey(),
              child: _temperatureHarness(entries: entries, range: range),
            ),
          );

          expect(
            chartHeight(tester),
            closeTo(expectedHeight, 0.5),
            reason: heightReason,
          );
        }
      },
    );
  });

  group('fixed display-range bounds', () {
    LineChartData data(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart)).data;

    testWidgets('the y bounds are the provider\'s range (default 36.0..38.0), '
        'never the data', (tester) async {
      // The record dips just below the fixed range's lower bound (35.9
      // vs 36.0) — under the old data-adaptive bounds such a low value
      // dragged the lower edge to the half degree below (35.5 here), so
      // this is where the old rounding would have moved the axis; the
      // settings range pins the bounds 36..38 regardless. Out-of-range
      // readings are simply not rendered (see the next section) — they
      // never move the bounds either way.
      await pumpChart(
        tester,
        _temperatureHarness(
          entries: [
            DailyEntry(date: _temperatureThu, bbtC: 36.5),
            DailyEntry(date: _temperatureFri, bbtC: 37.0),
            DailyEntry(date: _temperatureSat, bbtC: 35.9),
          ],
        ),
      );

      expect(
        data(tester).minY,
        36.0,
        reason: 'the default range\'s lower bound is the fixed minY',
      );
      expect(
        data(tester).maxY,
        38.0,
        reason: 'the default range\'s upper bound is the fixed maxY',
      );
    });
  });

  // ═══════════ temperature visible range ═══════════
  // Widget tests of temperatures OUTSIDE the chart's visible value range
  // (the settings-selected display range, default 36–38 °C): such a
  // measurement is NOT rendered at all — its whole per-day dot painter
  // (dot, circled-higher ring, arrow-up glyph) is skipped with its spot.
  // The polyline still connects the adjacent days but is CLIPPED to the
  // value range: the drawable piece runs to the boundary crossing (at a
  // possibly fractional day index BETWEEN the days), so a line running to
  // or along the plot's top/bottom edge tells the reader data lie beyond
  // the visible range. In-range rendering is pixel-for-pixel unchanged, a
  // value exactly AT a boundary counts as in range (its dot renders and its
  // segments pass through raw), and when EVERY measurement is out of range
  // the paper grid renders with no curve (the "no temperature" placeholder
  // still does NOT show — the days carry measurements). Fixture shape and
  // helpers are shared with the temperature-connectivity section above.

  /// A measured-day strip on the temperature section's Thu..Sat calendar
  /// block: day index = list position, temperatures = the given values.
  List<DailyEntry> rangeEntries(List<double> temps) => [
    for (var i = 0; i < temps.length; i++)
      DailyEntry(
        date: _temperatureThu.add(Duration(days: i)),
        bbtC: temps[i],
      ),
  ];

  /// The visible polyline's drawable spans as (start, end) spot pairs —
  /// one pair per visible two-spot line bar (the curve draws one bar per
  /// clipped span).
  List<(FlSpot, FlSpot)> visibleSpans(WidgetTester tester) => [
    for (final bar in _segmentBars(tester))
      if (bar.spots.length == 2) (bar.spots.first, bar.spots.last),
  ];

  /// The (x, y) pair list of [visibleSpans], for exact endpoint comparison.
  List<(double, double, double, double)> spanEndpoints(WidgetTester tester) => [
    for (final (start, end) in visibleSpans(tester))
      (start.x, start.y, end.x, end.y),
  ];

  /// True when some dot-only bar carries a spot at [dayIndex] (day indexes
  /// sit at integral x positions).
  bool hasDotSpot(WidgetTester tester, int dayIndex) => dotBars(
    tester,
  ).any((bar) => bar.spots.any((spot) => spot.x.round() == dayIndex));

  group('out-of-range temperatures against the fixed display-range bounds '
      '(37 / 39 / 37 above, 37 / 38 / 37 at, 37 / 35 / 37 below, '
      '39 / 39.2 / 39 all out)', () {
    testWidgets(
      'a temperature out of range renders no dot and clips the polyline '
      'at the boundary crossing; exactly at the boundary the dot and '
      'raw endpoints render unchanged; an all-out record leaves only '
      'the mounted paper grid',
      (tester) async {
        final boundaryCases =
            <
              (
                String label,
                List<double> values,
                bool boundaryDotRenders,
                List<(double, double, double, double)> endpoints,
                String reason,
                void Function(WidgetTester)? extras,
              )
            >[
              (
                'above the range (37 / 39 / 37)',
                [37.0, 39.0, 37.0],
                false,
                [(0.0, 37.0, 0.5, 38.0), (1.5, 38.0, 2.0, 37.0)],
                'the line to and from the above-range day is clipped at '
                    'the upper boundary 38.0, crossing midway between the days',
                (tester) {
                  expect(
                    dotPainterOrNull(tester, 0),
                    isNotNull,
                    reason: 'the in-range left day keeps its dot painter',
                  );
                  expect(
                    dotPainterOrNull(tester, 2),
                    isNotNull,
                    reason: 'the in-range right day keeps its dot painter',
                  );
                  final spans = visibleSpans(tester);
                  expect(
                    spans,
                    hasLength(2),
                    reason: 'the only visible bars are the two clipped spans',
                  );
                  expect(
                    (spans[0].$1.x, spans[0].$1.y),
                    (0.0, 37.0),
                    reason:
                        'the left bar starts at day 0\'s raw in-range value',
                  );
                  expect(
                    (spans[1].$2.x, spans[1].$2.y),
                    (2.0, 37.0),
                    reason: 'the right bar ends at day 2\'s raw in-range value',
                  );
                  expect(
                    hasDotSpot(tester, 1),
                    isFalse,
                    reason:
                        'the dot bars carry in-range spots only — no spot '
                        'maps to the out-of-range day',
                  );
                },
              ),
              (
                'exactly at the boundary (37 / 38 / 37)',
                [37.0, 38.0, 37.0],
                true,
                [(0.0, 37.0, 1.0, 38.0), (1.0, 38.0, 2.0, 37.0)],
                'the boundary value lies inside the window, so the segments '
                    'keep their raw endpoints (no clipping)',
                null,
              ),
              (
                'below the range (37 / 35 / 37)',
                [37.0, 35.0, 37.0],
                false,
                [(0.0, 37.0, 0.5, 36.0), (1.5, 36.0, 2.0, 37.0)],
                'the line to and from the below-range day is clipped at '
                    'the lower boundary 36.0, crossing midway between the days',
                null,
              ),
            ];

        for (final (
              label,
              values,
              boundaryDotRenders,
              endpoints,
              endpointReason,
              extras,
            )
            in boundaryCases) {
          await pumpChart(
            tester,
            // Remount the app per fixture: a same-shaped re-pump would
            // only update the existing tree in place and carry the
            // previous fixture's clip shape into the next one.
            KeyedSubtree(
              key: UniqueKey(),
              child: _temperatureHarness(entries: rangeEntries(values)),
            ),
          );

          if (boundaryDotRenders) {
            expect(
              dotPainterOrNull(tester, 1),
              isNotNull,
              reason:
                  '$label: the boundary value counts as in range — its '
                  'dot renders unchanged',
            );
          } else {
            expect(
              dotPainterOrNull(tester, 1),
              isNull,
              reason:
                  '$label: the middle day\'s dot is skipped with its '
                  'spot (no ring or arrow anchored to it either)',
            );
          }
          if (extras != null) extras(tester);
          expect(spanEndpoints(tester), endpoints, reason: endpointReason);
        }

        // Every measurement out of range: the curve vanishes but the
        // chart still mounts (the paper grid with no curve; the
        // "no temperature" placeholder must NOT show — the days carry
        // measurements).
        await pumpChart(
          tester,
          _temperatureHarness(entries: rangeEntries([39.0, 39.2, 39.0])),
        );
        for (var i = 0; i < 3; i++) {
          expect(
            dotPainterOrNull(tester, i),
            isNull,
            reason: 'day $i is out of range — its dot does not render',
          );
        }
        expect(
          _segmentBars(tester),
          isEmpty,
          reason:
              'no piece of the polyline passes through the visible '
              'range — nothing drawable at all',
        );
        expect(
          find.byType(LineChart),
          findsOneWidget,
          reason: 'the chart still mounts with its paper grid',
        );
        expect(
          find.textContaining('Enter observations or measurements'),
          findsNothing,
          reason:
              'the "no temperature" placeholder does not show — the '
              'days carry measurements',
        );
      },
    );
  });

  // ═══════════ measurement time, sex and pain ═══════════
  // former test/cycle_chart_time_sex_pain_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('measurement time — its own row below the chart block, first in '
      'the below-chart strip', () {
    testWidgets(
      'the time row renders BELOW the chart block, at the strip\'s top '
      '— above the disturbance row and the notes band — for every '
      'day with a recorded measurement time',
      (tester) async {
        await pumpChart(
          tester,
          _timeSexPainHarness(entries: _timeSexPainEntries()),
        );

        final chartBottom = tester.getRect(find.byType(LineChart)).bottom;
        // Own row below the block, first in the strip: the time row starts
        // after the chart, but above disturbance and the band (owner order:
        // time first in the below-chart strip).
        expect(
          tester.getRect(chartCell(0, 'time')).top,
          greaterThan(chartBottom),
          reason: 'the time row is not part of the chart block',
        );
        expect(
          tester.getRect(chartCell(0, 'time')).bottom,
          lessThan(tester.getRect(chartCell(0, 'disturbance')).top),
          reason: 'the time row renders above the disturbance row',
        );
        expect(
          tester.getRect(chartCell(0, 'time')).top,
          lessThan(tester.getRect(chartCell(0, 'notesBand')).top),
          reason:
              'the time row renders above the notes band — time is '
              'the first row of the below-chart strip',
        );
        // Every day with a recorded time renders its HH:mm (the fixture's
        // only recorded time is day 0).
        expect(chartCellContent(0, 'time', find.text('06:30')), findsOneWidget);
      },
    );

    testWidgets(
      'the time STILL renders at every column width — rotated vertically '
      '(RotatedBox) under the width threshold, horizontal above it '
      '(regression: the time used to be dropped entirely at the space '
      'constraint)',
      (tester) async {
        List<DailyEntry> timedEntries(int count) => [
          // Give EVERY day a recorded measurement time so the narrow checks
          // exercise the row everywhere.
          for (var i = 0; i < count; i++)
            DailyEntry(
              date: _timeSexPainDay(i),
              bbtC: 36.5,
              measuredAtMinutes: 6 * 60 + 30,
            ),
        ];
        Finder timeCells() => find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('timeCell-'),
        );

        final orientationCases =
            <
              (
                String label,
                List<DailyEntry> entries,
                int checkedDay,
                Matcher columnWidth,
                bool vertical,
                bool everyCellRotates,
              )
            >[
              (
                // 60 days overflow the viewport: columns render at the
                // minimum usable width (24 px), far below the horizontal
                // text threshold.
                '60 days, columns at the minimum usable width',
                timedEntries(60),
                59,
                closeTo(24, 0.5),
                true,
                true,
              ),
              (
                // 25 days fit the viewport but leave only ~29 px per column —
                // below the threshold, so still vertical.
                '25 days, a narrow non-minimum ~29 px column',
                timedEntries(25),
                24,
                closeTo(29, 1.5),
                true,
                false,
              ),
              (
                'wide columns',
                _timeSexPainEntries(),
                0,
                greaterThan(32),
                false,
                false,
              ),
            ];

        for (final (
              label,
              entries,
              checkedDay,
              columnWidth,
              vertical,
              everyCellRotates,
            )
            in orientationCases) {
          await pumpChart(
            tester,
            // Remount the app per iteration: a same-shaped re-pump would only
            // update the existing tree in place and carry the previous
            // column width (and its scroll offset) into the next fixture.
            KeyedSubtree(
              key: UniqueKey(),
              child: _timeSexPainHarness(entries: entries),
            ),
          );

          expect(
            tester.getRect(chartCell(checkedDay, 'time')).width,
            columnWidth,
            reason: 'precondition: $label',
          );
          if (vertical) {
            // The time text survives the space constraint: the rendered
            // time cells carry the rotated HH:mm text (RotatedBox), never
            // empty — it is NEVER dropped.
            final rotatedTime = find.descendant(
              of: chartCell(checkedDay, 'time'),
              matching: find.text('06:30'),
            );
            expect(
              rotatedTime,
              findsOneWidget,
              reason:
                  '$label: the time renders vertically — it is NEVER '
                  'dropped',
            );
            final rotatedBox = find
                .ancestor(of: rotatedTime, matching: find.byType(RotatedBox))
                .first;
            expect(
              tester.widget<RotatedBox>(rotatedBox).quarterTurns,
              1,
              reason:
                  '$label: the vertical time reads top→bottom, like the '
                  "band's note teaser",
            );
            // The time text scales to fill the row's full 30 px height, so
            // geometry can't tell a top anchor from a centered one — pin the
            // anchor itself instead.
            final anchor = find
                .ancestor(of: rotatedBox, matching: find.byType(Align))
                .first;
            expect(
              tester.widget<Align>(anchor).alignment,
              Alignment.topCenter,
              reason:
                  '$label: the vertical time anchors its reading start '
                  'at the row top',
            );
            if (everyCellRotates) {
              expect(
                find.descendant(
                  of: timeCells(),
                  matching: find.byType(RotatedBox),
                ),
                findsWidgets,
                reason: '$label: the narrow cells rotate the time text',
              );
            } else {
              expect(
                find.descendant(
                  of: chartCell(checkedDay, 'time'),
                  matching: find.byType(RotatedBox),
                ),
                findsOneWidget,
              );
            }
          } else {
            expect(
              find.descendant(
                of: chartCell(checkedDay, 'time'),
                matching: find.byType(RotatedBox),
              ),
              findsNothing,
              reason: '$label: keeps the horizontal HH:mm text',
            );
            expect(
              chartCellContent(checkedDay, 'time', find.text('06:30')),
              findsOneWidget,
            );
          }
        }
      },
    );
  });
  testWidgets(
    'the measurement time renders localized HH:mm text on days with a '
    'recorded measurement time — and nothing elsewhere (en and de)',
    (tester) async {
      for (final locale in [const Locale('en'), const Locale('de')]) {
        // 8+1 chart days fit the viewport comfortably, so the columns are
        // wide enough for the time text.
        await pumpChart(
          tester,
          _timeSexPainHarness(entries: _timeSexPainEntries(), locale: locale),
        );

        expect(
          chartCellContent(0, 'time', find.text('06:30')),
          findsOneWidget,
          reason:
              '$locale: the temperature day WITH a recorded time shows the '
              'padded HH:mm text in its own time cell',
        );
        expect(
          chartCellContent(1, 'time', find.text('06:30')),
          findsNothing,
          reason:
              '$locale: a temperature WITHOUT a recorded time shows no '
              'time text',
        );
        expect(
          chartCellContent(2, 'time', find.byType(Text)),
          findsNothing,
          reason:
              '$locale: a temperature-free day can never carry a '
              'measurement time (the domain drops the time without a '
              'temperature)',
        );
        expect(
          chartCellContent(6, 'time', find.byType(Text)),
          findsNothing,
          reason:
              '$locale: a plain temperature day without a time shows nothing',
        );
        expect(
          chartCellContent(2, 'time', find.byIcon(Icons.schedule)),
          findsNothing,
          reason:
              '$locale: no per-day clock icon — the clock lives only in '
              'the row corner slot',
        );
      }
    },
  );

  testWidgets('sex renders X marks only on days with recorded time slots', (
    tester,
  ) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    expect(
      find.byKey(const ValueKey('inPlotSex-2-morning')),
      findsOneWidget,
      reason: 'the sex day shows its X glyph inside the plot',
    );
    expect(
      find.byKey(const ValueKey('inPlotSex-0-morning')),
      findsNothing,
      reason: 'no X on a temperature day without sex',
    );
    expect(find.byKey(const ValueKey('inPlotSex-6-morning')), findsNothing);
  });

  testWidgets('every set sex time slot renders its own X — multiple slots '
      'render multiple X marks on one day', (tester) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    // day 5 recorded start + end: middle is the only absent timing.
    expect(
      find.byKey(const ValueKey('inPlotSex-5-midday')),
      findsNothing,
      reason: 'no X for an unrecorded timing',
    );
    expect(
      find.byKey(const ValueKey('inPlotSex-5-morning')),
      findsOneWidget,
      reason: 'two recorded slots (start + end) render their X marks',
    );
    expect(find.byKey(const ValueKey('inPlotSex-5-evening')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotSex-2-morning')),
      findsOneWidget,
      reason: 'a single recorded slot renders exactly one X',
    );
  });

  testWidgets('each X sits at its slot\'s fraction of the day column', (
    tester,
  ) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    final plot = tester.getRect(find.byType(LineChart));
    final colW = plot.width / 8;

    double xFraction(int dayIndex, String timing) {
      final glyph = tester.getRect(
        find.byKey(ValueKey('inPlotSex-$dayIndex-$timing')),
      );
      return (glyph.center.dx - plot.left) / colW - dayIndex;
    }

    final startF = xFraction(2, 'morning');
    expect(
      startF,
      closeTo(1 / 6, 0.05),
      reason:
          'a start-slot X renders at the column\'s start fraction '
          '(~1/6)',
    );

    expect(
      xFraction(5, 'morning'),
      closeTo(1 / 6, 0.05),
      reason: 'the first X belongs to the start slot (left)',
    );
    expect(
      xFraction(5, 'evening'),
      closeTo(5 / 6, 0.05),
      reason: 'the second X belongs to the end slot (right)',
    );
  });

  testWidgets('pain renders B in its band row; Mittelschmerz renders M '
      'inside the plot', (tester) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    expect(
      find.byKey(const ValueKey('painBreastGlyph-3')),
      findsOneWidget,
      reason: 'breast pain shows the B letter in its band row',
    );
    expect(
      chartCellContent(3, 'notesBand', find.text('M')),
      findsNothing,
      reason: 'no Mittelschmerz letter without the flag',
    );
    expect(
      find.byKey(const ValueKey('inPlotM-4')),
      findsOneWidget,
      reason: 'Mittelschmerz shows the M letter inside the plot',
    );
    expect(
      find.byKey(const ValueKey('painBreastGlyph-4')),
      findsNothing,
      reason: 'no breast letter without the flag',
    );
    expect(find.byKey(const ValueKey('painBreastGlyph-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('inPlotM-5')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('painBreastGlyph-6')),
      findsNothing,
      reason: 'a plain day shows no pain letter',
    );
    expect(find.byKey(const ValueKey('inPlotM-6')), findsNothing);
  });

  testWidgets('a combined day carries the sex X marks alongside the band '
      'pain row and the Mittelschmerz M inside the plot', (tester) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    expect(
      find.byKey(const ValueKey('inPlotSex-5-evening')),
      findsOneWidget,
      reason: 'the sex X marks render inside the plot',
    );
    expect(
      find.byKey(const ValueKey('painBreastGlyph-5')),
      findsOneWidget,
      reason:
          'the B letter renders in the day\'s pain row beside the in-plot '
          'sex marks',
    );
    expect(
      find.byKey(const ValueKey('inPlotM-5')),
      findsOneWidget,
      reason: 'the Mittelschmerz letter renders inside the plot',
    );
  });

  testWidgets('a firmness-only day renders its glyph with no position '
      'ink at all', (tester) async {
    await pumpChart(
      tester,
      _timeSexPainHarness(entries: _timeSexPainEntries()),
    );

    expect(
      find.byKey(const ValueKey('cervixFirmnessGlyph-7')),
      findsOneWidget,
      reason:
          'the soft-firmness glyph (paper shorthand w) renders pinned '
          'in the band\'s cervix zone',
    );
    for (final glyph in ['t', 'm', 'h', 'sh', 'u']) {
      expect(
        chartCellContent(7, 'notesBand', find.text(glyph)),
        findsNothing,
        reason: 'positions paint circles, never letters — ($glyph incl.)',
      );
    }
    expect(
      find.byKey(const ValueKey('cervixSlotGlyph-7')),
      findsNothing,
      reason: 'no slot glyph on a day whose opening was never recorded',
    );
  });

  // ═══════════ weekend bands ═══════════
  // former test/cycle_chart_weekend_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets(
    'weekend columns get background bands — exactly the weekend days at '
    'full column width, weekday columns none, clamped to the plot edges',
    (WidgetTester tester) async {
      // One case per fixture shape, all with the same band geometry model
      // (day i sits at chart x = i with a half-day band width around it):
      // the default week strip with the weekend in the middle, the
      // degenerate lone-Saturday day and a Sat..Sun run where both bands
      // touch a plot edge.
      final cases =
          <
            ({
              List<DailyEntry>? entries,
              DateTime? selected,
              String? lengthReason,
              List<(double x1, double x2, String x1Reason)> bands,
            })
          >[
            (
              // Exactly the two weekend days (Sat & Sun) are band, nothing else.
              entries: null,
              selected: null,
              lengthReason: null,
              bands: [
                (1.5, 2.5, 'Saturday (day index 2)'),
                (2.5, 3.5, 'Sunday (day index 3)'),
              ],
            ),
            (
              // Degenerate case: one recorded day, and it is a weekend day. The
              // chart keeps a one-column-wide domain window (−0.5..0.5), so the
              // lone day's full column (−0.5..0.5) lies inside the plot and the
              // band keeps its full width — no clamp may collapse it to zero.
              entries: [DailyEntry(date: _weekendSat, bbtC: 36.7)],
              selected: _weekendSat,
              lengthReason: 'the lone Saturday gets its band',
              bands: [
                (
                  -0.5,
                  0.5,
                  'the lone column spans −0.5..0.5 in the shifted domain',
                ),
              ],
            ),
            (
              // Edge clamps: the band annotation clamps to the shifted plot
              // bounds (−0.5 .. dayCount − 0.5). A weekend on the FIRST day
              // extends to the plot's left edge, a weekend on the LAST day to
              // the plot's right edge — both keep their full column width
              // instead of being cut back to the day indexes.
              entries: [
                DailyEntry(date: _weekendSat, bbtC: 36.7),
                DailyEntry(date: _weekendSun, bbtC: 36.7),
              ],
              selected: _weekendSat,
              lengthReason: null,
              bands: [
                (
                  -0.5,
                  0.5,
                  'the first day\'s band reaches the plot\'s left edge (−0.5)',
                ),
                (
                  0.5,
                  1.5,
                  'the last day\'s band reaches the plot\'s right edge '
                      '(dayCount − 0.5 = 1.5)',
                ),
              ],
            ),
          ];
      for (final (:entries, :selected, :lengthReason, :bands) in cases) {
        await pumpChart(
          tester,
          // Remount per case so no previous case's fixture can leak into
          // the next pump.
          KeyedSubtree(
            key: UniqueKey(),
            child: _weekendHarness(entries: entries, selected: selected),
          ),
        );

        final actualBands = _weekendBands(tester).toList()
          ..sort((a, b) => a.x1.compareTo(b.x1));
        expect(
          actualBands,
          hasLength(bands.length),
          reason: lengthReason ?? 'exactly one band per weekend day',
        );
        for (var i = 0; i < bands.length; i++) {
          expect(
            actualBands[i].x1,
            closeTo(bands[i].$1, 1e-9),
            reason: bands[i].$3,
          );
          expect(actualBands[i].x2, closeTo(bands[i].$2, 1e-9));
        }
        // fl_chart requires x1 < x2; a zero-width band would paint nothing.
        for (final band in actualBands) {
          expect(band.x2, greaterThan(band.x1));
        }
      }
    },
  );

  testWidgets('the band tint renders in both brightnesses — mostly transparent '
      'over the light surface, a light overlay on the dark scheme', (
    WidgetTester tester,
  ) async {
    for (final dark in [false, true]) {
      // Dark-mode variant: the platform brightness must be set BEFORE
      // that variant's pump (the pump-before-dark trick the theme-mode
      // dark tests use, since a mid-test dispatcher change does not
      // rebuild the theme in the test env).
      if (dark) useDarkDeviceBrightness(tester);

      await pumpChart(
        tester,
        // Remount per variant so no previous variant's scheme can leak
        // into the next pump.
        KeyedSubtree(key: UniqueKey(), child: _weekendHarness()),
      );

      final bands = _weekendBands(tester);
      expect(bands, isNotEmpty);
      for (final band in bands) {
        // A whisper, not a wallpaper: mostly transparent over the surface.
        final color = _bandColor(band);
        expect(color.a, greaterThan(0.0));
        expect(color.a, lessThan(0.15));
      }
      if (dark) {
        for (final band in bands) {
          // Dark-mode tint is a light overlay (high relative luminance),
          // so it contrasts against the dark chart surface instead of
          // disappearing.
          expect(
            _bandColor(band).computeLuminance(),
            greaterThan(0.3),
            reason: 'dark-mode weekend tint should lean on the dark scheme',
          );
        }
      }
    }
  });

  // ═══════════ windowing ═══════════
  // former test/cycle_chart_windowing_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  group('long recorded range', () {
    testWidgets('the first data frame auto-scrolls to the newest days', (
      tester,
    ) async {
      await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

      // The newest days sit at the content's right edge, so the initial
      // auto-scroll jumped the viewport to the maximum scroll extent: the
      // last day column fills the window, the earliest days are off-screen.
      expect(
        _bleedingCell(149),
        findsOneWidget,
        reason: 'the newest days fill the viewport after the first frame',
      );
      expect(
        _bleedingCell(0),
        findsNothing,
        reason: 'the earliest days are outside the initial window',
      );

      // The jump is instant (no animation): the offset sits at the maximum
      // extent already after the settle.
      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: '150 day columns need more width than the viewport provides',
      );
      expect(
        state.position.pixels,
        state.position.maxScrollExtent,
        reason: 'the initial auto-scroll jumps straight to the newest days',
      );
    });

    testWidgets('the chart block scrolls horizontally', (tester) async {
      await pumpChart(tester, _windowingHarness(entries: longRangeEntries()));

      final scrollView = chartScrollView();
      expect(
        scrollView,
        findsOneWidget,
        reason: 'the whole chart block is horizontally scrollable',
      );
      final state = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: '60 day columns need more width than the viewport provides',
      );
    });

    testWidgets('dragging scrolls the window; y bounds stay global', (
      tester,
    ) async {
      await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

      // The initial window sits at the newest days; drag BACK toward the
      // earliest days and assert the window follows the scroll. The drag
      // exceeds the maximum scroll extent, so it settles at the content's
      // start (the earliest days).
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      expect(
        _bleedingCell(149),
        findsNothing,
        reason: 'the newest days scrolled out of the window',
      );
      expect(
        _bleedingCell(0),
        findsOneWidget,
        reason: 'the earliest days appear once scrolled to',
      );

      // The temperature scale must NOT rescale per window: the y bounds are
      // the fixed settings-derived range (default 36..38 °C, well above the
      // coldest recorded day here), so the curve keeps its absolute heights
      // while scrolling.
      final chartMinY = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .minY;
      final recordedValues = _manyEntries().map((e) => e.bbtC!).toList();
      expect(
        chartMinY,
        lessThanOrEqualTo(recordedValues.reduce((a, b) => a < b ? a : b)),
        reason: 'the y scale still covers the coldest recorded day',
      );
    });

    testWidgets(
      'a later entries re-emit never re-runs the initial auto-scroll',
      (tester) async {
        final controller = StreamController<List<DailyEntry>>();
        addTearDown(controller.close);
        await tester.pumpWidget(
          _windowingHarness(
            entries: _manyEntries(),
            entriesStream: controller.stream,
          ),
        );
        controller.add(_manyEntries());
        await tester.pumpAndSettle();

        final state = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          state.position.pixels,
          state.position.maxScrollExtent,
          reason: 'the first data frame jumped to the newest days',
        );

        // Drag away from the end toward earlier days (deep enough that the
        // wide window margin no longer reaches the range's end). A timed
        // drag has no fling momentum, so the settled offset is
        // deterministic.
        await tester.timedDrag(
          chartScrollView(),
          const Offset(900, 0),
          const Duration(milliseconds: 200),
        );
        await tester.pumpAndSettle();
        final offsetAfterDrag = state.position.pixels;
        expect(offsetAfterDrag, lessThan(state.position.maxScrollExtent));

        // Emit a NEW list instance (one extra day at the end): the user's
        // scrolled position must survive — no re-jump back to the end.
        controller.add([
          ..._manyEntries(),
          DailyEntry(date: longRangeDay(150), bbtC: 36.5),
        ]);
        await tester.pumpAndSettle();

        expect(
          state.position.pixels,
          offsetAfterDrag,
          reason: 'a later re-emit must not re-run the initial auto-scroll',
        );
        expect(
          _bleedingCell(149),
          findsNothing,
          reason: 'the view stayed where the user dragged it, not at the end',
        );
        // The dragged-to window still renders: at the dragged offset the
        // visible window starts around floor(offset / columnWidth) — the
        // scroll content leads directly with day column 0 (the y scale lives
        // in the frozen rail outside the scroll), so the offset maps onto
        // the column grid without any leading-strip subtraction.
        final firstVisible = (offsetAfterDrag / _columnWidth).floor();
        expect(
          _bleedingCell(firstVisible + 2),
          findsOneWidget,
          reason: 'the dragged-to window cells are still rendered',
        );
      },
    );

    testWidgets('an empty first frame does not jump; the first non-empty '
        'frame mounts the chart and jumps', (tester) async {
      final controller = StreamController<List<DailyEntry>>();
      addTearDown(controller.close);
      await tester.pumpWidget(
        _windowingHarness(
          entries: _manyEntries(),
          entriesStream: controller.stream,
        ),
      );
      controller.add(const <DailyEntry>[]);
      await tester.pumpAndSettle();

      // No data: the chart block is not built at all, so there is nothing
      // to jump (the screen shows its no-data state instead).
      expect(chartScrollView(), findsNothing);

      controller.add(_manyEntries());
      await tester.pumpAndSettle();

      // The first NON-EMPTY data frame mounts the chart and auto-scrolls
      // to the newest days.
      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        state.position.pixels,
        state.position.maxScrollExtent,
        reason: 'the first non-empty data frame jumps to the newest days',
      );
      expect(_bleedingCell(149), findsOneWidget);
    });

    testWidgets(
      'a freshly parked window carries one extra screen-width of margin '
      'past the visible edges, not further',
      (tester) async {
        await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

        final state = tester.state<ScrollableState>(
          find.descendant(
            of: chartScrollView(),
            matching: find.byType(Scrollable),
          ),
        );
        // The scroll viewport: block width (800 test viewport, 12 body
        // padding on each side) minus the frozen rail left of the scroll.
        const scrollViewport = 800.0 - 2 * 12 - 37; // 739
        final marginDays = (scrollViewport / _columnWidth).ceil(); // 31

        // Fresh park 1: the initial auto-scroll landed at the newest days;
        // the left margin is unclamped and ends exactly one extra
        // screen-width before the leftmost visible edge.
        final maxExtent = state.position.maxScrollExtent;
        final freshVisible = (maxExtent / _columnWidth).floor();
        expect(
          _bleedingCell(freshVisible - 1 - marginDays),
          findsOneWidget,
          reason:
              'a full extra screen-width of margin renders before the '
              'visible edge of a freshly parked window',
        );
        expect(
          _bleedingCell(freshVisible - 2 - marginDays),
          findsNothing,
          reason:
              'the fresh park is bounded: the window does not extend '
              'past one extra screen-width',
        );

        // Fresh park 2: a long jump (the jump-to-date landing does the same)
        // re-parks the window around the landed position: both margins
        // extend exactly one extra screen-width past the visible edges.
        // Day cell i spans [i * 24, (i + 1) * 24).
        state.position.jumpTo(1000.0);
        await tester.pumpAndSettle();
        expect(
          state.position.pixels,
          1000.0,
          reason: 'precondition: the jump landed at the exact offset',
        );
        final firstVisible = (1000.0 / _columnWidth).floor();
        final lastVisible =
            ((1000.0 + scrollViewport) / _columnWidth).ceil() - 1;
        expect(
          _bleedingCell(firstVisible - 1 - marginDays),
          findsOneWidget,
          reason:
              'the re-parked window carries the screen-width margin '
              'before the visible edge',
        );
        expect(
          _bleedingCell(firstVisible - 2 - marginDays),
          findsNothing,
          reason: 'the re-parked window stays bounded at the margin',
        );
        expect(
          _bleedingCell(lastVisible + 1 + marginDays),
          findsOneWidget,
          reason:
              'the re-parked window carries the screen-width margin '
              'past the visible right edge',
        );
        expect(
          _bleedingCell(lastVisible + 2 + marginDays),
          findsNothing,
          reason: 'the re-parked window stays bounded at the margin',
        );
      },
    );

    testWidgets('a small scroll stays inside the parked window — the window is '
        'not rebuilt for travel the margin absorbs', (tester) async {
      await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

      final state = tester.state<ScrollableState>(
        find.descendant(
          of: chartScrollView(),
          matching: find.byType(Scrollable),
        ),
      );
      const scrollViewport = 800.0 - 2 * 12 - 37; // 739
      final marginDays = (scrollViewport / _columnWidth).ceil();
      final maxExtent = state.position.maxScrollExtent;
      final freshVisible = (maxExtent / _columnWidth).floor();
      final parkedStart = freshVisible - 1 - marginDays;
      expect(
        parkedStart,
        greaterThan(0),
        reason: 'precondition: the parked margin is unclamped here',
      );

      // Travel 240 px (ten columns) — well within one extra screen-width
      // of margin: the visible edge moves, but the parked window around it
      // still covers the viewport with seam margin to spare.
      state.position.jumpTo(maxExtent - 240.0);
      await tester.pumpAndSettle();

      // The parked window keeps sitting at the SAME boundary — it was not
      // re-parked around the new position (that is what keeps the rebuild
      // rare during a fling).
      expect(_bleedingCell(parkedStart), findsOneWidget);
      expect(
        _bleedingCell(parkedStart - 1),
        findsNothing,
        reason:
            'the parked window did not follow the small scroll — '
            'the margin absorbs the travel',
      );

      // The seam guarantee still holds at the new position: the leftmost
      // visible day and the day before it render.
      final visible = (state.position.pixels / _columnWidth).floor();
      expect(_bleedingCell(visible), findsOneWidget);
    });

    testWidgets(
      'the jump-to-date affordance sits in the AppBar actions, next to '
      'the info action',
      (tester) async {
        await pumpChart(tester, _windowingHarness(entries: longRangeEntries()));

        final jump = find.byKey(const ValueKey('calendarJumpButton'));
        final info = find.byKey(const ValueKey('cycleHelpAction'));
        expect(
          find.ancestor(of: jump, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the jump affordance moved into the AppBar actions',
        );
        expect(
          find.ancestor(of: info, matching: find.byType(AppBar)),
          findsOneWidget,
          reason: 'the info action stays in the AppBar beside it',
        );
        expect(
          tester.getCenter(jump).dx,
          lessThan(tester.getCenter(info).dx),
          reason: 'the jump affordance renders before the info action',
        );
        expect(
          find.ancestor(of: jump, matching: find.byType(ListView)),
          findsNothing,
          reason:
              'the wasted standalone row above the chart block is gone — '
              'the affordance no longer renders inside the screen body',
        );
      },
    );

    testWidgets('jump-to-date: picking a date moves the window onto it', (
      tester,
    ) async {
      await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

      // Drag to the content's start first: the picker opens on the
      // leftmost day of the window (the day the user is looking at), so
      // with the window parked at the earliest days it opens on January —
      // independent of how wide the window margin sits behind the visible
      // edge.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
      await tester.pumpAndSettle();

      expect(
        find.byType(DatePickerDialog),
        findsOneWidget,
        reason: 'the affordance opens the material date picker',
      );
      // Day index of 2026-01-20 = 19. The material picker confirms a day
      // selection through its OK button.
      await tester.tap(find.text('20').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        _bleedingCell(19),
        findsOneWidget,
        reason: 'the picked day is now inside the rendered window',
      );
      expect(
        _bleedingCell(149),
        findsNothing,
        reason: 'the window jumped away from where it was',
      );
    });

    testWidgets(
      'jump-to-date: picking a date after the chart unmounted disposes '
      'quietly, with no reach into the disposed state',
      (tester) async {
        await pumpChart(tester, _windowingHarness(entries: _manyEntries()));

        // The picker opens on the leftmost visible day, so the January
        // date grid is on screen (day cells of other months stay off it —
        // see the picking test above).
        await tester.drag(chartScrollView(), const Offset(3000, 0));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('calendarJumpButton')));
        await tester.pumpAndSettle();
        expect(
          find.byType(DatePickerDialog),
          findsOneWidget,
          reason: 'the affordance opens the material date picker',
        );

        // Unmount the screen body while the picker stays open (a real tab
        // change does the same): the chart state and its scroll hooks are
        // disposed under the still-open dialog.
        await tester.pumpWidget(
          _windowingHarness(entries: _manyEntries(), emptyHome: true),
        );
        await tester.pump();
        expect(
          find.byType(DatePickerDialog),
          findsOneWidget,
          reason:
              'the picker rides the root navigator and survives the '
              'body swap',
        );

        // Confirming the pick resolves the picker future inside the
        // disposed chart's continuation — which must return without
        // touching the disposed state (no unhandled error, no crash).
        await tester.tap(find.text('20').last, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping the curve in the scrolled window opens the day sheet',
      (tester) async {
        await pumpChart(tester, _windowingHarness(entries: longRangeEntries()));

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
        const railWidth = 37.0; // the frozen rail left of the scroll view
        const testViewportWidth = 800.0;
        const bodyPadding = 12.0;
        const scrollViewport =
            testViewportWidth - 2 * bodyPadding - railWidth; // 739
        const contentWidth = 60 * 24.0; // 1440
        const maxOffset = contentWidth - scrollViewport; // 701
        final tapContentX = 24.0 * (58 + 0.5);
        final tapScreenX =
            bodyPadding + railWidth + (tapContentX - maxOffset); // 752
        final chartTop = tester.getRect(find.byType(LineChart)).top;

        await tester.tapAt(Offset(tapScreenX, chartTop + 100));
        await tester.pumpAndSettle();

        expect(
          cycleDayPanel(),
          findsOneWidget,
          reason: 'a tap in the scrolled window still opens the day sheet',
        );
        final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
        expect(
          sheet.day,
          DateTime.utc(2026, 2, 28),
          reason: 'the tapped chart column maps to day index 58',
        );
      },
    );

    testWidgets('a long press on the curve opens the day sheet too', (
      tester,
    ) async {
      await pumpChart(tester, _windowingHarness(entries: longRangeEntries()));

      await tester.drag(chartScrollView(), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      // Same column mapping as the tap above (day 58's column center at
      // colW * (58 + 0.5), content = 60 columns without a strip); the
      // long-press behaves identically to the tap.
      const railWidth = 37.0; // the frozen rail left of the scroll view
      const bodyPadding = 12.0;
      const contentWidth = 60 * 24.0;
      const maxOffset = contentWidth - (800.0 - 2 * bodyPadding - railWidth);
      final tapContentX = 24.0 * (58 + 0.5);
      final chartTop = tester.getRect(find.byType(LineChart)).top;

      await tester.longPressAt(
        Offset(
          bodyPadding + railWidth + (tapContentX - maxOffset),
          chartTop + 100,
        ),
      );
      await tester.pumpAndSettle();

      expect(cycleDayPanel(), findsOneWidget);
      final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
      expect(sheet.day, DateTime.utc(2026, 2, 28));
    });
  });

  group('the in-plot day numbers are windowed like the in-plot glyphs', () {
    testWidgets('only the scroll window\'s number glyphs render', (
      tester,
    ) async {
      await pumpChart(
        tester,
        _windowingHarness(
          entries: _numberedTailEntries(),
          marks: _numberedTailMarks,
        ),
      );

      // The initial auto-scroll parks the window at the newest days: the
      // tail's low days (indexes 142..147) sit inside the parked window
      // and the earliest days are outside it.
      expect(
        _dayNumberGlyph(142, 6),
        findsOneWidget,
        reason: 'the newest days fill the window after the first frame',
      );
      expect(
        _numberUnder(tester, 0),
        isNull,
        reason: 'the earliest days carry no number',
      );

      // Drag back to the earliest days: the number glyphs follow the
      // built window, like every other in-plot glyph.
      await tester.drag(chartScrollView(), const Offset(3000, 0));
      await tester.pumpAndSettle();
      expect(
        _numberUnder(tester, 142),
        isNull,
        reason: 'the numbered tail leaves the built window after the drag',
      );
    });

    testWidgets(
      'the windowed number glyphs keep their global column positions',
      (tester) async {
        await pumpChart(
          tester,
          _windowingHarness(
            entries: _numberedTailEntries(),
            marks: _numberedTailMarks,
          ),
        );

        // The window spacer keeps glyph i at its global column position:
        // wherever the window starts, a day's number centers exactly at
        // that day's signal-row cell center.
        void expectSharedColumn(int index, int number) {
          final numberX = tester
              .getRect(_dayNumberGlyph(index, number))
              .center
              .dx;
          final bleedingX = tester.getRect(_bleedingCell(index)).center.dx;
          expect(
            numberX,
            closeTo(bleedingX, 0.5),
            reason:
                'number glyph $index keeps its global column position '
                '(window spacer, like the in-plot glyphs)',
          );
        }

        // The initial window sits at the newest days ...
        expectSharedColumn(142, 6);
        // ... and the dragged-to window at the earliest days carries no
        // number glyphs to align.
        await tester.drag(chartScrollView(), const Offset(3000, 0));
        await tester.pumpAndSettle();
        expect(_numberUnder(tester, 142), isNull);
      },
    );
  });

  group('short recorded range (5 days)', () {
    testWidgets('every day cell is rendered and nothing is scrollable', (
      tester,
    ) async {
      await pumpChart(tester, _windowingHarness(entries: _shortEntries()));

      for (var i = 0; i < 5; i++) {
        expect(
          _bleedingCell(i),
          findsOneWidget,
          reason: 'a short range fits usefully on one screen',
        );
      }

      final scrollView = chartScrollView();
      expect(
        scrollView,
        findsOneWidget,
        reason: 'the chart is still laid out as one scrollable block',
      );
      final state = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(
        state.position.maxScrollExtent,
        0,
        reason: '5 comfortable day columns fit the viewport exactly',
      );
    });
  });

  // ═══════════ window rebuild pace ═══════════
  // former test/cycle_chart_window_rebuild_test.dart (bodies concatenated verbatim; see
  // the file header for the merge mechanics)

  testWidgets(
    'scrolling a long distance re-windows the chart only a handful of '
    'times, not once per day column',
    (tester) async {
      final entries = _windowRebuildEntries();
      // No theme wiring here: the test counts window rebuilds, not looks.
      await pumpChart(tester, chartHarness(entries: entries, themed: false));

      // Travel 2000 px in 10 px steps (one pump per step): with a parked
      // window carrying an extra screen-width of margin (31 columns at this
      // viewport), the window needs re-parking only every extra screen-width
      // of travel — once per active edge — not once per day column.
      var reWindows = 0;
      var built = _builtCells(tester);
      const steps = 200;
      final gesture = await tester.startGesture(
        tester.getCenter(chartScrollView().first),
      );
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
      expect(
        reWindows,
        lessThanOrEqualTo(6),
        reason:
            'a 2000 px scroll must re-window only a handful of times '
            '(the parked margin absorbs the travel); observed $reWindows',
      );
    },
  );

  // ═══════════ stream error retry surfaces ═══════════

  testWidgets('a marks stream error replaces the chart with the retry '
      'surface, and retry re-renders the chart', (tester) async {
    var attempt = 0;
    await pumpChart(
      tester,
      chartHarness(
        entries: _evaluationEntries,
        marks: _marks,
        marksStreamFactory: () {
          attempt++;
          return attempt == 1
              ? Stream<List<CycleMark>>.error(StateError('injected error'))
              : Stream.value(_marks);
        },
      ),
    );

    expect(
      find.byType(LineChart),
      findsNothing,
      reason:
          'the chart must not render marks-driven content from the '
          'silently-empty marks list',
    );
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('marksStreamRetryButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('marksStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
    expect(attempt, 2, reason: 'the retry re-invoked the stream factory');
  });

  testWidgets('a marks stream error also replaces the no-data text with the '
      'retry surface when there is nothing to chart', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: const [],
        selectedDate: DateTime(2024, 5, 2),
        marksStreamFactory: () =>
            Stream<List<CycleMark>>.error(StateError('injected error')),
      ),
    );

    expect(
      find.text('Enter observations or measurements to see the cycle.'),
      findsNothing,
    );
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('marksStreamRetryButton')),
      findsOneWidget,
    );
  });

  testWidgets('an entries stream error gains the retry affordance, and '
      'retry restores the chart', (tester) async {
    var attempt = 0;
    await pumpChart(
      tester,
      chartHarness(
        entries: _evaluationEntries,
        marks: _marks,
        entriesStreamFactory: () {
          attempt++;
          return attempt == 1
              ? Stream<List<DailyEntry>>.error(StateError('injected error'))
              : Stream.value(_evaluationEntries);
        },
      ),
    );

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entriesStreamRetryButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('entriesStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
    expect(attempt, 2);
  });

  // ═══════════ data-less rendering and the today-span ═══════════
  // The screen merges the raw entries with the shared derived pass's
  // span-extended cycle day lists (lib/ui/cycle.dart), so the chart's range
  // follows the SHARED span rule: it reaches the pinned `today` and renders
  // whenever any tracked day exists — however signal-less the temperature
  // data is. The harness pins `now` to the last seeded day by default; the
  // span tests here pass the explicit pin.
  testWidgets('a bleeding-only tracked day renders the chart, not the '
      'no-data message', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: [
          DailyEntry(date: DateTime.utc(2026, 9, 10), bleeding: Bleeding.heavy),
        ],
      ),
    );

    expect(
      _dayLabel(0),
      findsOneWidget,
      reason: 'the tracked day renders its day column',
    );
    expect(
      _bleedingFills(0),
      findsOneWidget,
      reason: 'the bleeding glyph renders in the bleeding row',
    );
    expect(
      find.textContaining('Enter observations or measurements'),
      findsNothing,
      reason: 'bleeding data is data: the no-data placeholder must not show',
    );
  });

  testWidgets('a mucus-only tracked day renders the chart', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: [
          DailyEntry(date: DateTime.utc(2026, 9, 10), mucusSign: MucusSign.s),
        ],
      ),
    );

    expect(_dayLabel(0), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotMucus-0')),
      findsOneWidget,
      reason: 'the mucus glyph renders inside the temperature plot',
    );
    expect(
      find.textContaining('Enter observations or measurements'),
      findsNothing,
    );
  });

  testWidgets('the chart renders up to today, not up to the last tracked day', (
    tester,
  ) async {
    // The scenario's tracked range ends 9/16 (index 10); five placeholder
    // days extend the span to the pinned today (indexes 11..15).
    await pumpChart(
      tester,
      chartHarness(
        entries: _evaluationEntries,
        now: () => DateTime.utc(2026, 9, 21),
      ),
    );

    expect(
      _label(15, '21.'),
      findsOneWidget,
      reason: "today's column renders, with its day-of-month label",
    );
    expect(
      find.byKey(const ValueKey('bleedingCell-19')),
      findsNothing,
      reason: 'the span ends at today, not past it',
    );
    expect(
      find.byKey(const ValueKey('bleedingCell-15')),
      findsOneWidget,
      reason:
          'the placeholder days render tap targets, so the extended '
          'range stays editable through today',
    );
    final renderedLabels = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('dayLabel-'),
          ),
        )
        .length;
    expect(
      renderedLabels,
      16,
      reason: '11 tracked days + 5 placeholder days render',
    );
  });

  testWidgets('a pinned clock behind the data never retracts the chart', (
    tester,
  ) async {
    // Today (9/10) lies inside the tracked range (ends 9/16): the span
    // rule's max keeps the tracked end — the clock never shortens a longer
    // dataset.
    await pumpChart(
      tester,
      chartHarness(
        entries: _evaluationEntries,
        now: () => DateTime.utc(2026, 9, 10),
      ),
    );

    expect(
      _label(10, '16.'),
      findsOneWidget,
      reason: 'the last tracked day stays the chart\'s right edge',
    );
    expect(find.byKey(const ValueKey('dayLabel-11')), findsNothing);
  });

  testWidgets('genuinely nothing tracked keeps the no-data message', (
    tester,
  ) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: const [],
        marks: const [],
        selectedDate: DateTime.utc(2026, 9, 10),
      ),
    );

    expect(
      find.textContaining('Enter observations or measurements'),
      findsOneWidget,
      reason: 'no entries and no marks render the centered no-data text',
    );
    expect(find.byType(LineChart), findsNothing);
  });
}
