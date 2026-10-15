import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:cycle_app/ui/cycle_mark_sheet.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';

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
    date: septSevenDay(0),
    bbtC: 36.5,
    cervixPosition: CervixPosition.low,
    cervixOpening: CervixOpening.closed,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(
    date: septSevenDay(1),
    bbtC: 36.6,
    cervixPosition: CervixPosition.medium,
    cervixOpening: CervixOpening.middle,
  ),
  DailyEntry(
    date: septSevenDay(2),
    bbtC: 36.7,
    cervixPosition: CervixPosition.high,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: septSevenDay(3),
    bbtC: 36.8,
    cervixPosition: CervixPosition.veryHigh,
    cervixOpening: CervixOpening.open,
    cervixFirmness: CervixFirmness.halfSoft,
  ),
  DailyEntry(
    date: septSevenDay(4),
    bbtC: 36.9,
    cervixPosition: CervixPosition.unreachable,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: septSevenDay(5),
    bbtC: 37.0,
    cervixOpening: CervixOpening.open,
  ),
  DailyEntry(
    date: septSevenDay(6),
    bbtC: 36.4,
    cervixPosition: CervixPosition.medium,
  ),
  DailyEntry(
    date: septSevenDay(7),
    bbtC: 36.5,
    cervixFirmness: CervixFirmness.soft,
  ),
  DailyEntry(
    date: septSevenDay(8),
    bbtC: 36.6,
    painBreast: true,
    notes:
        'Impfung nachgekauft (Rückfrage bei Dr. Wild) '
        '\nArztbesuche nachtragen',
  ),
  DailyEntry(
    date: septSevenDay(9),
    bbtC: 36.7,
    cervixPosition: CervixPosition.medium,
    cervixFirmness: CervixFirmness.soft,
    notes: 'Nachkontrolle beim Frauenarzt',
  ),
  DailyEntry(
    date: septSevenDay(10),
    bbtC: 36.8,
    cervixPosition: CervixPosition.medium,
    cervixFirmness: CervixFirmness.soft,
    notes: ' \n ',
  ),
  DailyEntry(
    date: septSevenDay(11),
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
// Widget tests of the notes band on the cycle chart: a day whose entry
// carries a non-empty notes text shows the joined note text in its day
// column — rotated to read bottom→top and anchored at the band bottom.
// The band is the LAST segment of the below-chart strip (per the paper
// sheet, whose remarks block sits at the very bottom). Days with an
// empty/absent notes field render no text. Tapping any band cell opens
// the day options panel like every other cell.

// Four chart days:
//  0: plain temperature, no notes                 -> no note text
//  1: temperature WITH a note                     -> rotated note text
//  2: notes = empty string                        -> no note text
//  3: temperature WITHOUT a recorded note field   -> no note text
final _noteEntries = <DailyEntry>[
  DailyEntry(date: septSevenDay(0), bbtC: 36.5),
  DailyEntry(date: septSevenDay(1), bbtC: 36.6, notes: 'Impfung heute'),
  DailyEntry(date: septSevenDay(2), bbtC: 36.7, notes: ''),
  DailyEntry(date: septSevenDay(3), bbtC: 36.4),
];

void main() {
  testWidgets('the band cells match the band-height constant and every '
      'windowed day renders one', (tester) async {
    await pumpChart(tester, _cervixHarness(entries: _cervixEntries()));

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
      CervixOpening.closed: cervixClosedDotSize,
      CervixOpening.middle: cervixMiddleCircleSize,
      CervixOpening.open: cervixOpenCircleSize,
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
        closeTo(diameterOf[value]!, 0.01),
        reason: "day $key: the circle's diameter communicates the opening",
      );
      expect(
        rect.height,
        closeTo(diameterOf[value]!, 0.01),
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
          cervixCircleStrokeWidth,
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
      closeTo(cell4.top + cervixSlotCenterY(0), 0.5),
      reason: 'the topmost slot anchors at its slot center below the band top',
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

  testWidgets('a day with a non-empty note renders its text in the notes '
      'band, below the chart block', (tester) async {
    await pumpChart(tester, chartHarness(entries: _noteEntries));

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
    await pumpChart(tester, chartHarness(entries: _noteEntries));

    for (final i in [0, 2, 3]) {
      expect(
        find.byKey(ValueKey('notesText-$i')),
        findsNothing,
        reason: 'day $i carries no note text',
      );
    }
  });

  testWidgets('tapping a notes-band cell opens the day sheet', (tester) async {
    await pumpChart(tester, chartHarness(entries: _noteEntries));

    await tester.tap(chartCell(1, 'notesBand'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cycleDayPanel(), findsOneWidget);
    final sheet = tester.widget<CycleDayPanel>(cycleDayPanel());
    expect(
      sheet.day,
      septSevenDay(1),
      reason: 'the tapped band cell owns day 1',
    );
  });

  testWidgets('the notes band has a rail corner slot with the localized row '
      'name (en and de)', (tester) async {
    final wording = {const Locale('en'): 'Note', const Locale('de'): 'Notiz'};
    for (final MapEntry(:key, :value) in wording.entries) {
      await pumpFreshChart(
        tester,
        () => chartHarness(entries: _noteEntries, locale: key),
      );

      expect(chartCellCorner('notesBand'), findsOneWidget);
      expect(tooltipMessages(tester, chartCellCorner('notesBand')), [
        value,
      ], reason: '$key: the band corner carries the localized row name');

      final cornerCenter = tester
          .getRect(chartCellCorner('notesBand'))
          .center
          .dy;
      final cellCenter = tester.getRect(chartCell(1, 'notesBand')).center.dy;
      expect(
        cornerCenter,
        closeTo(cellCenter, 0.5),
        reason: 'the band rail glyph is vertically centered on the row',
      );
    }
  });
}
