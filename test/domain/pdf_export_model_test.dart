// Unit tests of the PDF export model (lib/domain/pdf_export_model.dart):
// the export-ready record produced from entries + marks + the settings
// values. Pure arithmetic, mirroring the cycle page's numbering rule
// (the leading pre-mark group is excluded from counting and numbering,
// like everywhere the "Zyklus N" ordinals appear).
import 'package:cycle_app/domain/cycle_grouping.dart';
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
        model.observedCycleCount,
        3,
        reason: 'the outside-app count stands on its own',
      );
      expect(model.shortestCycleLength, isNull);
      expect(model.earliestFirstHigherCycleDay.any, isNull);
      expect(model.earliestFirstHigherCycleDay.afterMucusPeak, isNull);
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
      expect(model.observedCycleCount, 3);
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
      expect(
        model.observedCycleCount,
        7,
        reason: '4 paper cycles before the app + 3 recorded here',
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
      expect(
        model.observedCycleCount,
        7,
        reason: 'the pre-mark group is not one of them',
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
      expect(
        upToSecond.observedCycleCount,
        6,
        reason: '4 outside + the first two in-app cycles',
      );
      final ordinals = [
        for (var i = 0; i < upToSecond.cycles.length; i++)
          cycleOrdinalNumber(i, upToSecond.observedCyclesOutsideApp),
      ];
      expect(ordinals, [
        5,
        6,
      ], reason: '"Zyklus 6" is the exported one — the latest of the list');
      expect(upToSecond.cycles.last.cycle.startDate, d(3, 29));

      // The default (null) exports everything mark-opened.
      final all = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      expect(all.cycles.length, 3);
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

  group('shortest cycle length', () {
    test('minimum of the gaps between consecutive exported starts; the '
        'open last cycle contributes none', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
      );
      // Starts: Mar 1 -> Mar 29 (28), Mar 29 -> Apr 26 (28).
      expect(model.shortestCycleLength, 28);

      final truncated = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        exportStartsUpTo: d(4, 26),
      );
      expect(
        truncated.shortestCycleLength,
        28,
        reason: 'the last start has no known follow-up length',
      );
    });

    test('fewer than two exported starts: no length at all', () {
      final single = buildPdfExportModel(
        entries: modelEntries(),
        marks: modelMarks(),
        exportStartsUpTo: d(3, 1),
      );
      expect(single.cycles.length, 1);
      expect(single.shortestCycleLength, isNull);
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

    test('minimum over the exported mark-opened cycles, both variants', () {
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        exportStartsUpTo: d(3, 29),
      );
      // Cycle 1: rise marked Mar 14, start Mar 1 -> cycle day 14, strictly
      // after the peak (Mar 12). Cycle 2: rise on the start day itself ->
      // cycle day 1, NOT strictly after the same-day peak.
      expect(model.earliestFirstHigherCycleDay.any, 1);
      expect(
        model.earliestFirstHigherCycleDay.afterMucusPeak,
        14,
        reason: 'the "real" first higher stays cycle 1\'s late rise',
      );
    });

    test('delegates to the documented two-variant helper — the statistics '
        'screen and the PDF header cannot drift', () {
      final evaluations = evaluateCycles(
        modelEntries(),
        divergentMarks(),
      ).where((e) => e.cycle.startsAtMenstruation).toList();
      final model = buildPdfExportModel(
        entries: modelEntries(),
        marks: divergentMarks(),
        exportStartsUpTo: d(3, 29),
      );
      expect(
        model.earliestFirstHigherCycleDay,
        earliestFirstHigherCycleDay(evaluations),
      );
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
