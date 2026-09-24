// Unit tests of the PDF export model (lib/domain/pdf_export_model.dart):
// the export-ready record produced from entries + marks + the settings
// values. Pure arithmetic, mirroring the cycle page's numbering rule
// (the leading pre-mark group is excluded from counting and numbering,
// like everywhere the "Zyklus N" ordinals appear).
import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/pdf_export_model.dart';
import 'package:cycle_app/domain/statistics.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int month, int day) => DateTime.utc(2026, month, day);

/// Data shot: three mark-opened cycles (starts Mar 1, Mar 29, Apr 26) plus
/// one leading pre-mark entry (Feb 20, no mark before it).
///
/// Cycle 1 is tracked DAILY through Mar 15 (gap days in a tracked-day
/// list would keep the raw-data fields below unchanged but are NOT
/// index-space neutral: they change the overlay's per-day index space —
/// a calendar offset is not its tracked position — and the drawing layer
/// (lib/pdf/pdf_curve.dart) maps calendar-offset indexes through
/// tracked-day positions, with gap-day marks dropping out; a daily run
/// keeps the derived per-day indexes readable) and
/// carries the full observation surface the PDF's per-cycle overlay maps
/// from: mucus (with a quality on the S day), a measurement time, a raw
/// disturbance flag, a temperature-ignore mark, the mucus-peak and
/// first-higher marks, and one SUZ mark of each variant (the cycle's plain
/// record rows the export renders verbatim; cycles 2 and 3 stay almost
/// plain so a mark-free cycle's empty overlay is asserted too).
List<DailyEntry> modelEntries() => [
  DailyEntry(date: d(2, 20), bbtC: 36.5),
  DailyEntry(date: d(3, 1), bbtC: 36.4, bleeding: Bleeding.medium),
  DailyEntry(date: d(3, 2), bbtC: 36.4),
  DailyEntry(date: d(3, 3), bbtC: 36.2),
  DailyEntry(date: d(3, 4), bbtC: 36.1),
  DailyEntry(date: d(3, 5), bbtC: 36.2),
  // The raw data surface the PDF renders verbatim: mucus sign with its
  // quality, recorded times, one raw disturbance flag and sex timings —
  // this mask never excludes anything (the temperature-ignore mark is
  // the exclusion signal). Raw observation fields never touch the
  // evaluation arithmetic, so the other groups' expectations stay put.
  DailyEntry(
    date: d(3, 6),
    bbtC: 36.3,
    measuredAtMinutes: 7 * 60 + 20,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.w,
  ),
  DailyEntry(date: d(3, 7), bbtC: 36.2),
  DailyEntry(date: d(3, 8), bbtC: 36.2, sexTimings: 3),
  // The ignoreTemperature-marked day: excluded from the evaluation
  // (number #5 is skipped, "6 5 _ 4 …"), still a full observation row.
  DailyEntry(
    date: d(3, 9),
    bbtC: 36.3,
    tempDisturbances: 1,
    mucusSign: MucusSign.t,
  ),
  DailyEntry(date: d(3, 10), bbtC: 36.1, mucusSign: MucusSign.fs),
  DailyEntry(
    date: d(3, 11),
    bbtC: 36.2,
    measuredAtMinutes: 8 * 60,
    mucusSign: MucusSign.s,
    mucusQuality: MucusQuality.g,
  ),
  DailyEntry(
    date: d(3, 12),
    bbtC: 36.2,
    painBreast: true,
    painMittelschmerz: true,
  ),
  DailyEntry(date: d(3, 13), bbtC: 36.3, mucusSign: MucusSign.s),
  DailyEntry(date: d(3, 14), bbtC: 36.7, mucusSign: MucusSign.s),
  DailyEntry(date: d(3, 15), bbtC: 36.8, sexTimings: 7),
  DailyEntry(date: d(3, 29), bbtC: 36.4, bleeding: Bleeding.medium),
  DailyEntry(date: d(4, 26), bbtC: 36.4, bleeding: Bleeding.light),
];

/// Cycle 1's analysis marks (peak Mar 12, rise Mar 14), one SUZ mark per
/// variant inside its window and one temperature-ignore mark; cycles 2 and
/// 3 stay mark-free.
List<CycleMark> modelMarks() => [
  CycleMark(date: d(3, 1), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(3, 12), type: CycleMarkTypes.mucusPeakDay),
  CycleMark(date: d(3, 14), type: CycleMarkTypes.firstHigherMeasurement),
  CycleMark(date: d(3, 15), type: CycleMarkTypes.suzMorning),
  CycleMark(date: d(3, 10), type: CycleMarkTypes.suzEvening),
  CycleMark(date: d(3, 9), type: CycleMarkTypes.ignoreTemperature),
  CycleMark(date: d(3, 29), type: CycleMarkTypes.cycleStart),
  CycleMark(date: d(4, 26), type: CycleMarkTypes.cycleStart),
];

void main() {
  group('building the export model', () {
    test('no entries and no marks: the empty model', () {
      final model = buildPdfExportModel(
        entries: const [],
        marks: const [],
        observedCyclesOutsideApp: 3,
        name: 'Ada',
        birthDate: DateTime.utc(1990, 1, 2),
      );
      expect(model.cycles, isEmpty);
      expect(
        model.shortestCycleLengths,
        isEmpty,
        reason: 'the per-cycle stats lists stay parallel to the cycles',
      );
      expect(model.earliestFirstHigherCycleDays, isEmpty);
      expect(model.name, 'Ada');
      expect(model.birthDate, DateTime.utc(1990, 1, 2));
    });
  });

  group('per-cycle list & count arithmetic', () {
    test('without prior cycles, every mark-opened cycle is exported and '
        'numbered 1..n via the shared ordinal rule', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(
        model.cycles.length,
        3,
        reason: 'the three mark-opened cycles, none filtered out',
      );
      // The page's observed-cycle count IS its ordinal (the shared
      // numbering rule behind "Zyklus N") — the paper form counts up
      // until the count reaches the cycle's own number.
      final counts = [
        for (var i = 0; i < model.cycles.length; i++) model.ordinalOf(i),
      ];
      expect(
        counts,
        [1, 2, 3],
        reason:
            'each page counts itself up: "Beobachtete Zyklen" is the '
            'same number as the "Zyklus N" line (one shared rule), so '
            'the two cannot drift apart',
      );
      final ordinals = [
        for (var i = 0; i < model.cycles.length; i++)
          cycleOrdinalNumber(i, model.observedCyclesOutsideApp),
      ];
      expect(ordinals, [
        1,
        2,
        3,
      ], reason: 'the cycle page numbering: the shared rule, 0-based');
    });

    test('outside-app cycles shift the numbering and the count — '
        'for every exported cycle', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 4,
      );
      final counts = [
        for (var i = 0; i < model.cycles.length; i++) model.ordinalOf(i),
      ];
      expect(
        counts,
        [5, 6, 7],
        reason:
            'each page counts ITSELF up through the outside-app shift '
            '(the count IS its ordinal); no page carries a number '
            'counted beyond its own cycle',
      );
      final ordinals = [
        for (var i = 0; i < model.cycles.length; i++)
          cycleOrdinalNumber(i, model.observedCyclesOutsideApp),
      ];
      expect(ordinals, [5, 6, 7]);
    });

    test('the leading pre-mark group is excluded from counting and '
        'numbering (same rule as the cycle page)', () {
      // modelEntries already carries the Feb 20 pre-mark entry: assert it
      // does not shift anything.
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 4,
      );
      expect(model.cycles.length, 3, reason: 'three MARK-OPENED cycles');
      final counts = [
        for (var i = 0; i < model.cycles.length; i++) model.ordinalOf(i),
      ];
      expect(
        counts,
        [5, 6, 7],
        reason:
            'the pre-mark group shifts nothing; the page count is '
            'its ordinal',
      );
      final ordinals = [
        for (var i = 0; i < model.cycles.length; i++)
          cycleOrdinalNumber(i, model.observedCyclesOutsideApp),
      ];
      expect(ordinals, [
        5,
        6,
        7,
      ], reason: 'the unnumbered leading group shifts nothing');
      expect(model.cycles.every((c) => c.cycle.startsAtMenstruation), isTrue);
    });

    test('exporting up to a chosen cycle: only the mark-opened cycles up '
        'to that start are exported (default: all)', () {
      final upToSecond = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 4,
        exportStartsUpTo: d(3, 29),
      );
      expect(upToSecond.cycles.length, 2);
      final counts = [
        for (var i = 0; i < upToSecond.cycles.length; i++)
          upToSecond.ordinalOf(i),
      ];
      expect(
        counts,
        [5, 6],
        reason:
            'per-cycle count-up: a page\'s "Beobachtete Zyklen" is its '
            'own ordinal — even inside a "up to" export where the pair '
            'of numbers coincide, the paper form never counts ahead of '
            'the printed cycle',
      );
      final ordinals = [
        for (var i = 0; i < upToSecond.cycles.length; i++)
          upToSecond.ordinalOf(i),
      ];
      expect(ordinals, [
        5,
        6,
      ], reason: '"Zyklus 6" is the exported one — the latest of the list');
      // The start date is the opening mark's OWN date — the raw local
      // midnight shape (like the entries), not the UTC-normalized one.
      expect(upToSecond.cycles.last.cycle.startDate, DateTime(2026, 3, 29));

      // The default (null) exports everything mark-opened.
      final all = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(all.cycles.length, 3);
    });

    test('a cycle starting exactly ON the "up to" limit day is exported: '
        'the start date is normalized before the instant comparison', () {
      // Cycle 2's startDate since the mark-anchoring change is the placed
      // mark's local-midnight datetime, while the limit is the normalized
      // UTC-midnight day. In a UTC-negative locale the raw local-midnight
      // INSTANT lies after the limit instant even though both name the
      // same calendar day — a raw `isAfter` comparison there wrongly
      // drops the cycle (run this file with TZ=Etc/GMT+5 against the raw
      // comparison to reproduce it on a UTC-positive host). The filter
      // must compare calendar days: normalize the start date like every
      // other identity comparison (the limit is normalized by the
      // builder itself).
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        exportStartsUpTo: d(3, 29),
      );
      expect(model.cycles.length, 2);
      expect(
        model.cycles.last.cycle.startDate,
        DateTime(2026, 3, 29),
        reason:
            'cycle 2 starts exactly ON the limit day — the local-midnight '
            'instant is normalized to the same calendar day as the limit, '
            'so "up to" stays inclusive of it',
      );
    });

    test('a SELECTED subset exports exactly the chosen cycles, in bucket '
        'order, with parallel overlays (the checkbox list\'s constraint)', () {
      // Cycles 1 and 3 of 3 (the checkbox fixture's shape).
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 4,
        selectedStartDates: {d(3, 1), d(4, 26)},
      );
      // The listed cycles carry the Cycle's own startDate — the mark's
      // local-midnight date shape (see lib/domain/cycle_grouping.dart);
      // the SELECTION identity above is normalized before matching.
      expect(
        model.cycles.map((e) => e.cycle.startDate).toList(),
        [DateTime(2026, 3, 1), DateTime(2026, 4, 26)],
        reason:
            'the chosen cycles in observation order — the middle one '
            'stays out even though a later cycle is in',
      );
      expect(model.overlays, hasLength(model.cycles.length));
      // Cycle 1's artifacts are still derived from the WHOLE evaluation list
      // (its marks/overlay are unaffected by the other cycles' export fate).
      expect(model.overlays[0].suzMarks, isNotEmpty);

      final ordinals = [
        for (var i = 0; i < model.cycles.length; i++) model.ordinalOf(i),
      ];
      expect(
        ordinals,
        [5, 7],
        reason:
            'the exported cycles carry their REAL numbers from the whole '
            'record (cycle 1 -> 5, cycle 3 -> 7) — a subset export never '
            're-indexes the selected set',
      );
    });

    test('a SINGLE selected cycle is numbered with its REAL number, the '
        'header count reads the whole record', () {
      // Only the last of the three mark-opened cycles: the bug report's
      // shape — before the fix the page header printed "Zyklus 1".
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 4,
        selectedStartDates: {d(4, 26)},
      );
      expect(model.cycles.length, 1);
      expect(
        model.ordinalOf(0),
        7,
        reason:
            'the record\'s third mark-opened cycle, shifted by the 4 '
            'outside-app cycles — never the subset\'s re-indexed "1"; '
            'the page\'s "Beobachtete Zyklen" reads the SAME 7 (the '
            'count is the ordinal, both routes through the shared rule) '
            '— here, where the paper cycles 4–6 were never exported '
            'either, the count-up still reaches 7 because the observed '
            'history the user counts on paper includes them',
      );

      // The report's scenario with a larger paper history: 10 observed
      // on paper, the 15th app cycle exported -> "Zyklus 13"-shaped truth.
      final tenPaper = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        observedCyclesOutsideApp: 10,
        selectedStartDates: {d(4, 26)},
      );
      expect(tenPaper.ordinalOf(0), 13);
    });

    test('the selection is the normalized cycle-START identity: time-of-day '
        'noise and unknown dates do not break the match', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        // May 1 with a stray time-of-day, plus a nonsense date.
        selectedStartDates: {
          DateTime(2026, 4, 26, 14, 30), // time-of-day noise on cycle 3
          DateTime(2026, 5, 1, 9), // matches no cycle start: dropped
          DateTime(2026, 3, 29, 23, 59), // matches cycle 2 exactly
        },
      );
      expect(
        model.cycles.map((e) => e.cycle.startDate).toList(),
        [DateTime(2026, 3, 29), DateTime(2026, 4, 26)],
        reason:
            'the start-day identity is the normalized UTC-midnight date; '
            'the unselected date is dropped silently',
      );
    });

    test('an EMPTY explicit selection exports nothing (the card\'s '
        '"Keine" state keeps the empty-document guard in charge)', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        selectedStartDates: const {},
      );
      expect(model.cycles, isEmpty);
      expect(model.overlays, isEmpty);
    });

    test('the selection list mirrors the exported cycles: ordinal + start '
        'per mark-opened cycle, pre-mark group omitted', () {
      final choices = exportableCycles(
        modelEntries(),
        modelMarks(),
        observedCyclesOutsideApp: 4,
      );
      expect(choices.length, 3);
      expect(choices.map((c) => c.ordinal), [5, 6, 7]);
      expect(choices.map((c) => c.startDate), [d(3, 1), d(3, 29), d(4, 26)]);
    });
  });

  group('print idempotency (the paper-form point of view)', () {
    test('appending later cycles to the record changes NO earlier exported '
        'cycle\'s page values', () {
      // Split the fixture at cycle 2's start mark: the pre-mark entry plus
      // cycle 1 (with its marks) vs cycles 2 and 3 from Mar 29 on.
      final cut = d(3, 29);
      bool earlier(DateTime date) =>
          DateOnly.normalize(date).isBefore(DateOnly.normalize(cut));
      final earlyEntries = [
        for (final e in modelEntries())
          if (earlier(e.date)) e,
      ];
      final laterEntries = [
        for (final e in modelEntries())
          if (!earlier(e.date)) e,
      ];
      final earlyMarks = [
        for (final m in modelMarks())
          if (earlier(m.date)) m,
      ];
      final laterMarks = [
        for (final m in modelMarks())
          if (!earlier(m.date)) m,
      ];
      final selection = {d(3, 1)};

      // First print: the record ends with cycle 1 and it is exported
      // alone — exactly the shape of printing it while it was the latest
      // observed cycle.
      final before = buildPdfExportModel(
        entries: earlyEntries,
        marks: earlyMarks,
        observedCyclesOutsideApp: 4,
        selectedStartDates: selection,
      );
      expect(before.cycles.length, 1);
      final beforeOrdinal = before.ordinalOf(0);
      final beforeShortest = before.shortestCycleLengths.single;
      final beforeEarliest = before.earliestFirstHigherCycleDays.single;
      expect(
        beforeOrdinal,
        5,
        reason: '4 paper cycles + this record\'s first cycle',
      );
      expect(
        beforeShortest,
        isNull,
        reason: 'no completed cycle exists before it yet',
      );
      expect(beforeEarliest, (
        any: 14,
        afterMucusPeak: 14,
      ), reason: 'its own rise is part of its own observation');

      // Later print: cycles 2 and 3 exist in the record now; the SAME
      // cycle 1 is exported with the SAME selection. Its page must print
      // the identical numbers and stats — nothing may be recomputed from
      // data that did not exist when the page was first printed.
      final after = buildPdfExportModel(
        entries: [...earlyEntries, ...laterEntries],
        marks: [...earlyMarks, ...laterMarks],
        observedCyclesOutsideApp: 4,
        selectedStartDates: selection,
      );
      expect(after.cycles.length, 1);
      expect(
        after.ordinalOf(0),
        beforeOrdinal,
        reason: 'an exported subset never re-indexes the selected set',
      );
      expect(
        after.shortestCycleLengths.single,
        beforeShortest,
        reason:
            'cycle 1 has a completed 28-day length only once a later '
            'cycle exists — the page keeps the "—" it printed then',
      );
      expect(
        after.earliestFirstHigherCycleDays.single,
        beforeEarliest,
        reason:
            'later cycles carry no earlier rise here, and even if one '
            'did, the truncation at cycle 1 would keep them out',
      );
    });
  });

  group('per-cycle shortest cycle length (the prefix truncation)', () {
    test('the shortest COMPLETED length counts up per cycle: none for the '
        'first, later cycles excluded (print idempotency)', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      // Starts: Mar 1 -> Mar 29 (28) -> Apr 26 (28). Cycle 1 has no
      // completed EARLIER cycle; cycles 2 and 3 each see cycle 1's
      // finished 28 — every page's own (not-yet-completed) length stays
      // out, so printing an early cycle after later ones exist cannot
      // change its number.
      expect(model.shortestCycleLengths, [null, 28, 28]);

      final truncated = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        exportStartsUpTo: d(4, 26),
      );
      expect(truncated.shortestCycleLengths, [
        null,
        28,
        28,
      ], reason: 'the facts read the record prefix, not the exported subset');
    });

    test('a NON-CONTIGUOUS subset counts the unexported cycles too: the '
        'prefix runs over the WHOLE record up to the printed cycle', () {
      // Cycles 1 and 3 of 3: cycle 3's page sees cycle 1's completed
      // length (to the successor Mar 29) AND the unexported cycle 2's
      // completed length (Mar 29 -> Apr 26, 28) — the paper form would
      // have counted both. The consecutive-EXPORTED distance (Mar 1 ->
      // Apr 26 = 56) is a between-cycles distance and must never appear.
      final subset = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        selectedStartDates: {d(3, 1), d(4, 26)},
      );
      expect(subset.cycles.length, 2);
      expect(subset.shortestCycleLengths, [null, 28]);
    });

    test('a CONSECUTIVE selection keeps the same per-cycle values as the '
        'export-all case', () {
      final subset = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        selectedStartDates: {d(3, 1), d(3, 29)},
      );
      expect(subset.shortestCycleLengths, [null, 28]);
    });

    test('a single exported cycle (the first): no completed earlier cycle, '
        'so the page falls back to the "—" convention', () {
      final single = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        exportStartsUpTo: d(3, 1),
      );
      expect(single.cycles.length, 1);
      expect(single.shortestCycleLengths, [null]);
    });

    test('a single exported cycle (the LAST): its own completed length is '
        'known only once later cycles exist, so it is excluded and the '
        'earlier ones still count', () {
      final last = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        selectedStartDates: {d(4, 26)},
      );
      expect(
        last.shortestCycleLengths,
        [28],
        reason:
            'cycle 1\'s completed 28, not cycle 3\'s own open-ended '
            'span (which would make the page non-idempotent)',
      );
    });
  });

  group('earliest first higher cycle day', () {
    /// Marks variant: cycle 2 (start Mar 29) carries a peak AND a
    /// first-higher mark on the SAME day — a rise not strictly after the
    /// peak (cycle day 1). The "real" variant must ignore it.
    List<CycleMark> divergentMarks() => [
      ...modelMarks(),
      CycleMark(date: d(3, 29), type: CycleMarkTypes.mucusPeakDay),
      CycleMark(date: d(3, 29), type: CycleMarkTypes.firstHigherMeasurement),
    ];

    test('computed per cycle over the record prefix truncated AT the '
        'printed cycle (its own rise included), both variants', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        exportStartsUpTo: d(3, 29),
      );
      // Cycle 1: rise marked Mar 14, start Mar 1 -> cycle day 14, strictly
      // after the peak (Mar 12). Cycle 2: rise on the start day itself ->
      // cycle day 1, NOT strictly after the same-day peak.
      expect(model.earliestFirstHigherCycleDays.length, 2);
      expect(model.earliestFirstHigherCycleDays[0], (
        any: 14,
        afterMucusPeak: 14,
      ));
      expect(
        model.earliestFirstHigherCycleDays[1],
        (any: 1, afterMucusPeak: 14),
        reason:
            'cycle 2\'s page sees its own day-1 rise in the "any" '
            'variant while the "real" variant stays cycle 1\'s late rise',
      );
    });

    test('a later cycle can never rewrite an earlier page: cycle 1\'s '
        'earliest stays its own 14 with the divergent cycles 2 and 3 '
        'present in the record', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
      );
      expect(
        model.earliestFirstHigherCycleDays,
        [
          (any: 14, afterMucusPeak: 14),
          (any: 1, afterMucusPeak: 14),
          (any: 1, afterMucusPeak: 14),
        ],
        reason:
            'the statistic is truncated at the printed cycle, so '
            'later data never leaks into earlier pages',
      );
    });

    test('delegates to the documented two-variant helper — per cycle over '
        'the record prefix, so the statistics screen and the PDF header '
        'cannot drift', () {
      final evaluations = evaluateCycles(
        modelEntries(),
        divergentMarks(),
      ).where((e) => e.cycle.startsAtMenstruation).toList();
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        exportStartsUpTo: d(3, 29),
      );
      for (var i = 0; i < model.cycles.length; i++) {
        final prefix = evaluations.sublist(0, model.markOpenedIndexes[i] + 1);
        expect(
          model.earliestFirstHigherCycleDays[i],
          earliestFirstHigherCycleDay(prefix),
          reason:
              'page ${i + 1}: the shared helper over the record up to '
              'that cycle, never over more',
        );
      }
    });
  });

  group('the paper-history constants fold into every exported page', () {
    /// Marks variant: cycle 2's rise sits on its own start day, on the
    /// SAME day as its peak (not the "real" variant) — same shape as the
    /// earliest-first-higher group's fixture.
    List<CycleMark> divergentMarks() => [
      ...modelMarks(),
      CycleMark(date: d(3, 29), type: CycleMarkTypes.mucusPeakDay),
      CycleMark(date: d(3, 29), type: CycleMarkTypes.firstHigherMeasurement),
    ];

    test('the paper shortest is the every-page minimum against the prefix '
        'minimum (first page: it replaces the "—")', () {
      // Paper 21 beats the in-app 28-day minimum on every page, including
      // the first one whose in-app-only value is null.
      final winningPaper = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        shortestCycleLengthOutsideApp: 21,
      );
      expect(
        winningPaper.shortestCycleLengths,
        [21, 21, 21],
        reason:
            'the paper figure predates every in-app cycle, so it '
            'belongs in every cycle\'s point of view — the first page '
            'prints the paper figure instead of "—" and the later pages '
            'keep the smaller paper minimum over their in-app 28',
      );
      // Paper 30 loses against the recorded in-app minimum of 28: a paper
      // value never flips a surfaced minimum upward.
      final losingPaper = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        shortestCycleLengthOutsideApp: 30,
      );
      expect(losingPaper.shortestCycleLengths, [30, 28, 28]);
    });

    test('the paper earliest first higher min-combines into BOTH variants '
        'of every page', () {
      // divergentMarks: cycle 2's rise on its own start day (cycle day 1,
      // NOT strictly after its same-day peak). Paper 10 undercuts cycle 1's
      // in-app 14 in both variants; page 2/3's "any" keeps the smaller
      // in-app 1 while the real variant folds to the paper 10.
      final paper10 = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        earliestFirstHigherCycleDayOutsideApp: 10,
      );
      expect(paper10.earliestFirstHigherCycleDays, [
        (any: 10, afterMucusPeak: 10),
        (any: 1, afterMucusPeak: 10),
        (any: 1, afterMucusPeak: 10),
      ]);

      // Paper 16 is beaten everywhere by in-app values (14 in the real
      // variant from page 1 on): the paper constant never inflates a page.
      final paper16 = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        earliestFirstHigherCycleDayOutsideApp: 16,
      );
      expect(paper16.earliestFirstHigherCycleDays, [
        (any: 14, afterMucusPeak: 14),
        (any: 1, afterMucusPeak: 14),
        (any: 1, afterMucusPeak: 14),
      ]);
    });

    test('the paper constants add no later-cycle dependence: printing an '
        'early cycle alone (paper figure in) is idempotent across the '
        'record growing', () {
      // The print-idempotency test's split, now WITH paper constants:
      // whatever the record does later, the paper figure is constant, so
      // the page's paper-derived values may not move either.
      final cut = d(3, 29);
      bool earlier(DateTime date) =>
          DateOnly.normalize(date).isBefore(DateOnly.normalize(cut));
      final earlyEntries = [
        for (final e in modelEntries())
          if (earlier(e.date)) e,
      ];
      final earlyMarks = [
        for (final m in modelMarks())
          if (earlier(m.date)) m,
      ];
      final laterEntries = [
        for (final e in modelEntries())
          if (!earlier(e.date)) e,
      ];
      final laterMarks = [
        for (final m in modelMarks())
          if (!earlier(m.date)) m,
      ];
      final selection = {d(3, 1)};

      final before = buildPdfExportModel(
        entries: earlyEntries,
        marks: earlyMarks,
        observedCyclesOutsideApp: 4,
        shortestCycleLengthOutsideApp: 21,
        earliestFirstHigherCycleDayOutsideApp: 10,
        selectedStartDates: selection,
      );
      expect(before.cycles.length, 1);
      expect(
        before.shortestCycleLengths,
        [21],
        reason:
            'no completed in-app cycle exists yet — the paper figure '
            'stands alone instead of the "—" the paperless build prints',
      );
      expect(before.earliestFirstHigherCycleDays, [
        (any: 10, afterMucusPeak: 10),
      ], reason: 'the paper rise on cycle day 10 beats cycle 1\'s own 14');

      final after = buildPdfExportModel(
        entries: [...earlyEntries, ...laterEntries],
        marks: [...earlyMarks, ...laterMarks],
        observedCyclesOutsideApp: 4,
        shortestCycleLengthOutsideApp: 21,
        earliestFirstHigherCycleDayOutsideApp: 10,
        selectedStartDates: selection,
      );
      expect(
        after.shortestCycleLengths.single,
        21,
        reason:
            'later cycles changed nothing: the paper part of the '
            'value is constant — the page prints identically however '
            'late it is reprinted',
      );
      expect(after.earliestFirstHigherCycleDays.single, (
        any: 10,
        afterMucusPeak: 10,
      ));
      // Cross-check against the paperless builds of the same shapes: the
      // first-cycle page difference is exactly the paper figure.
      final paperlessBefore = buildPdfExportModel(
        entries: earlyEntries,
        marks: earlyMarks,
        selectedStartDates: selection,
      );
      expect(paperlessBefore.shortestCycleLengths, [null]);
    });
  });

  group('per-cycle overlays for the PDF', () {
    test('the evaluated cycle exposes its derived display artifacts', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(
        model.overlays.length,
        model.cycles.length,
        reason: 'one overlay per exported cycle, parallel to the list',
      );
      final first = model.overlays[0];
      // Cycle 1 = tracked Mar 1–15 → day index = calendar offset from
      // Mar 1 (Mar 12 → 11, Mar 14 → 13, Mar 15 → 14, Mar 8 → 7, …).
      expect(first.peakIndexes, {11}, reason: 'the mucus-peak mark on Mar 12');
      expect(
        first.circledIndexes,
        {13, 14},
        reason:
            'the candidates Mar 14/15 — strictly after the peak → '
            'circles (R4)',
      );
      expect(first.arrowIndexes, isEmpty);
      expect(
        first.numbersByIndex,
        {12: 1, 11: 2, 10: 3, 9: 4, 7: 6},
        reason:
            'low numbering counting back from the rise, #5 skipped '
            'on the ignored Mar 9',
      );
      expect(
        first.baselineSegments.map((s) => (s.startIndex, s.endIndex, s.value)),
        [(7, 14, 36.3)],
        reason:
            'R10: from low #6 (Mar 8) to the last marked candidate '
            '(Mar 15), through the highest low',
      );
      final suz = first.suzMarks
          .map((m) => (m.dayIndex, m.morning, m.barX))
          .toSet();
      expect(suz, {
        // Mar 15 → index 14: suzMorning at the column start (−0.5).
        (14, true, 13.5),
        // Mar 10 → index 9: suzEvening at the column middle.
        (9, false, 9.0),
      });
      expect(first.ignoredIndexes, {
        8,
      }, reason: 'the ignoreTemperature mark on Mar 9');
    });

    test('mark-free cycles carry an empty overlay', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      for (final overlay in model.overlays.skip(1)) {
        expect(overlay.peakIndexes, isEmpty);
        expect(overlay.circledIndexes, isEmpty);
        expect(overlay.arrowIndexes, isEmpty);
        expect(overlay.numbersByIndex, isEmpty);
        expect(overlay.baselineSegments, isEmpty);
        expect(overlay.suzMarks, isEmpty);
        expect(
          overlay.ignoredIndexes,
          isEmpty,
          reason: 'other cycles’ ignore marks are not this cycle’s',
        );
      }
    });

    test('the empty model carries no overlays either', () {
      final model = buildPdfExportModel(entries: const [], marks: const []);
      expect(model.overlays, isEmpty);
    });

    test('the temperature range echoes the caller and defaults to the '
        'settings default', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(model.temperatureRange, TemperatureRange.defaults);

      final custom = TemperatureRange(min: 35.5, max: 37.5);
      expect(
        buildPdfExportModel(
          entries: modelEntries(),
          marks: modelMarks(),
          temperatureRange: custom,
        ).temperatureRange,
        same(custom),
        reason: 'echoed, not recounted (the settings owns the range)',
      );
    });
  });

  group('the data-span extension (a cycle runs to the next mark / today)', () {
    test('an interior cycle extends to the day before the next start mark; '
        'the last cycle extends to the caller-pinned today', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        today: d(5, 20),
      );
      // Cycle 1: Mar 1 -> next start Mar 29 (end Mar 28); cycle 2:
      // Mar 29 -> next start Apr 26 (end Apr 25); cycle 3 (last): Apr 26
      // -> today (May 20). The cycles were tracked far shorter.
      expect(model.cycles.map((e) => e.cycle.days.length).toList(), [
        28,
        28,
        25,
      ]);
      expect(model.cycles.last.cycle.endDate, DateOnly.normalize(d(5, 20)));
      // Overlays stay parallel to the exported cycles.
      expect(model.overlays, hasLength(model.cycles.length));
      // The extension days carry no derived artifacts (mark-free cycles).
      for (final overlay in model.overlays.skip(1)) {
        expect(overlay.circledIndexes, isEmpty);
        expect(overlay.arrowIndexes, isEmpty);
      }
    });

    test('a mark placed on a data-less extension day keeps its OWN column '
        '(no drop-out, no slide onto a neighboring day)', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: [
          ...modelMarks(),
          CycleMark(date: d(4, 10), type: CycleMarkTypes.mucusPeakDay),
        ],
        today: d(5, 20),
      );
      // Apr 10 sits on cycle 2's extension (Mar 29..Apr 25, tracked only
      // on Mar 29): index 12 = Apr 10's own calendar offset — the mark
      // renders in its own (empty) column of the PDF page.
      expect(model.overlays[1].peakIndexes, {12});
      expect(model.overlays[0].peakIndexes, {11});
    });

    test('an analysis mark inside a data-less trailing cycle derives no '
        'artifacts (no baseline/candidates from empty days)', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: [
          ...modelMarks(),
          CycleMark(
            // Far enough into the trailing extension that the six-low
            // window (rise−1 … rise−6) reaches no tracked day at all —
            // the window day May 4–9 days are all data-less.
            date: d(5, 10),
            type: CycleMarkTypes.firstHigherMeasurement,
          ),
        ],
        today: d(5, 20),
      );
      final last = model.cycles.last;
      expect(last.firstHigherDay, DateOnly.normalize(d(5, 10)));
      expect(last.baseline, isNull);
      expect(last.higherMeasurements, isEmpty);
      expect(last.numberedLows, isEmpty);
      expect(last.evaluationStopped, isFalse);
    });
  });

  group('identifying values', () {
    test('an unpadded name and the birth date pass through for the header', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        name: 'Maria Muster',
        birthDate: DateTime.utc(1980, 12, 24),
      );
      expect(model.name, 'Maria Muster');
      expect(model.birthDate, DateTime.utc(1980, 12, 24));
    });

    test('absent identifiers stay absent (nullable header facts)', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(model.name, isNull);
      expect(model.birthDate, isNull);
    });

    test('a whitespace-padded name carries the TRIMMED value in the model', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        name: '  Ada  ',
      );
      expect(
        model.name,
        'Ada',
        reason:
            'the model aligns with the trimmed persisted name '
            '(persistPdfExportName and the settings UI both trim)',
      );
    });

    test('a blank (whitespace-only) name stays null', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        name: '   ',
      );
      expect(model.name, isNull);
    });
  });
}
