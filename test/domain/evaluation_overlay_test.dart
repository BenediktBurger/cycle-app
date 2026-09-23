// Domain tests of the evaluation overlay (lib/domain/evaluation_overlay.dart):
// the derived per-day artifacts the cycle chart and the PDF export both
// draw — mucus peaks, circled/arrowed higher measurements, the 1–6 low
// numbering, the baseline segment, user SUZ marks — plus the ignored-day
// indexes of the temperature-ignore marks. Pure Dart — imports only
// lib/domain, runs on the host VM.
//
// The fixture carries two mark-opened cycle groups: cycle 1 exercises the
// full artifact family (duplicated peak, arrow/circle split, six lows,
// baseline span, user SUZ from a morning), cycle 2 stays plain so it only
// exercises attribution (an evening SUZ mark inside ITS window while the
// call sees the whole evaluation list) and no half-open window leakage
// across cycle boundaries.
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
import 'package:cycle_app/domain/evaluation_overlay.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';

/// A tracked day; [t] is the measured BBT (null = day without measurement).
DailyEntry d(
  int year,
  int month,
  int day, {
  double? t,
  Bleeding bleeding = Bleeding.none,
}) => DailyEntry(date: DateTime(year, month, day), bbtC: t, bleeding: bleeding);

CycleMark mark(int y, int m, int day, String type) =>
    CycleMark(date: DateTime(y, m, day), type: type);

final cycleOneEntries = <DailyEntry>[
  d(2026, 3, 2, bleeding: Bleeding.medium), // cycle onset, unmeasured
  d(2026, 3, 3, t: 36.1), // #6 … baseline span start (earliest numbered low)
  d(2026, 3, 4, t: 36.2), // #5
  d(2026, 3, 5, t: 36.4), // #4 — highest of the six lows → baseline
  d(2026, 3, 6, t: 36.2), // #3
  d(2026, 3, 7, t: 36.3), // #2
  d(2026, 3, 8, t: 36.1), // #1
  d(2026, 3, 9, t: 36.8), // marked rise — arrow (before the peak day)
  d(2026, 3, 10, t: 36.9), // peak day — at the peak → arrow
  d(2026, 3, 11, t: 37.0), // strictly after the peak → circle
];

final cycleTwoEntries = <DailyEntry>[
  d(2026, 3, 16, bleeding: Bleeding.light), // next cycle onset, unmeasured
  d(2026, 3, 17, t: 36.5),
  d(2026, 3, 18, t: 36.4),
  d(2026, 3, 19, t: 36.5),
  d(2026, 3, 20, t: 36.4),
];

final overlayMarks = <CycleMark>[
  mark(2026, 3, 2, CycleMarkTypes.cycleStart),
  // A duplicated mucus peak: the Mar 4 mark is superseded as the
  // evaluation's anchor (the latest peak drives the arithmetic) but the
  // MARKS STREAM still renders every placed peak.
  mark(2026, 3, 4, CycleMarkTypes.mucusPeakDay),
  mark(2026, 3, 10, CycleMarkTypes.mucusPeakDay),
  mark(2026, 3, 9, CycleMarkTypes.firstHigherMeasurement),
  mark(2026, 3, 12, CycleMarkTypes.suzMorning),
  mark(2026, 3, 16, CycleMarkTypes.cycleStart),
  mark(2026, 3, 20, CycleMarkTypes.suzEvening),
  // Outside the recorded range: never attributed to any day index.
  mark(2026, 5, 1, CycleMarkTypes.mucusPeakDay),
];

/// The two cycle-group evaluations of the fixture.
List<CycleEvaluation> evaluations() =>
    evaluateCycles([...cycleOneEntries, ...cycleTwoEntries], overlayMarks);

/// The chart call: one day space over the whole recorded range, first day
/// at day index 0 (Mar 2, normalized) and one index per calendar day —
/// Mar 20, the last marked day, is index 18.
EvaluationOverlay wholeRangeOverlay() => buildEvaluationOverlay(
  evaluations: evaluations(),
  marks: overlayMarks,
  firstDay: DateOnly.normalize(DateTime(2026, 3, 2)),
  dayCount: 19,
);

void main() {
  group('fixture sanity (arithmetic the overlay only maps)', () {
    test('two mark-opened cycle groups with the expected evaluation', () {
      final evals = evaluations();
      expect(evals.length, 2);
      final first = evals[0];
      expect(first.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(first.numberedLows.map((l) => (l.number, l.date.day)), [
        (1, 8),
        (2, 7),
        (3, 6),
        (4, 5),
        (5, 4),
        (6, 3),
      ]);
      expect(first.baseline!.value, 36.4);
      expect(first.higherMeasurements.map((h) => (h.date.day, h.markKind)), [
        (9, MarkKind.arrow),
        (10, MarkKind.arrow),
        (11, MarkKind.circle),
      ]);
      // R10: the segment runs from low #6 (Mar 3) to the last marked
      // candidate (Mar 11).
      expect(first.baselineSpan!.startDay.day, 3);
      expect(first.baselineSpan!.endDay.day, 11);
      // The second cycle has no first-higher mark: nothing derives there.
      expect(evals[1].higherMeasurements, isEmpty);
      expect(evals[1].baselineSpan, isNull);
    });
  });

  group('buildEvaluationOverlay maps the artifacts onto the day space', () {
    test('every placed peak renders — duplicates included, stream-driven', () {
      final overlay = wholeRangeOverlay();
      // Mar 4 → index 2, Mar 10 → index 8; the out-of-range May 1 peak is
      // dropped. The superseded Mar 4 peak still renders.
      expect(overlay.peakIndexes, {2, 8});
    });

    test('circled vs arrow candidates per MarkKind (per-candidate rule)', () {
      final overlay = wholeRangeOverlay();
      // Mar 9/10 → arrows (rise day and peak day), Mar 11 → circle.
      expect(overlay.arrowIndexes, {7, 8});
      expect(overlay.circledIndexes, {9});
    });

    test('numbered lows map onto their day indexes', () {
      final overlay = wholeRangeOverlay();
      // Mar 8..Mar 3 → indexes 6..1, numbers 1..6.
      expect(overlay.numbersByIndex, {6: 1, 5: 2, 4: 3, 3: 4, 2: 5, 1: 6});
    });

    test('the baseline segment maps the R10 span, null for candidate-free '
        'cycles', () {
      final overlay = wholeRangeOverlay();
      expect(
        overlay.baselineSegments.length,
        1,
        reason: 'only the marked cycle contributes a segment',
      );
      final segment = overlay.baselineSegments.single;
      expect(segment.startIndex, 1, reason: 'low #6 on Mar 3');
      expect(segment.endIndex, 9, reason: 'last marked candidate Mar 11');
      expect(segment.value, 36.4);
    });

    test('SUZ marks anchor morning at the column start, evening at the '
        'middle', () {
      final overlay = wholeRangeOverlay();
      final suz = overlay.suzMarks
          .map((m) => (dayIndex: m.dayIndex, barX: m.barX, morning: m.morning))
          .toSet();
      expect(suz, {
        // Mar 12 → index 10: suzMorning → bar at the column START (− 0.5).
        (dayIndex: 10, barX: 9.5, morning: true),
        // Mar 20 → index 18: suzEvening → bar at the column MIDDLE.
        (dayIndex: 18, barX: 18.0, morning: false),
      });
    });
  });

  group('ignoredDayIndexes', () {
    final ignoreMarks = <CycleMark>[
      mark(2026, 3, 5, CycleMarkTypes.ignoreTemperature), // cycle 1, index 3
      mark(2026, 3, 3, CycleMarkTypes.ignoreTemperature), // cycle 1, index 1
      mark(2026, 3, 19, CycleMarkTypes.ignoreTemperature), // cycle 2, index 3
      // Cycle 1's trailing span-extension day after its last tracked data
      // (the cycle runs to the day before the next start mark): keeps its
      // OWN data-less column index.
      mark(2026, 3, 13, CycleMarkTypes.ignoreTemperature),
      // Before the first tracked day and of a foreign type: ignored.
      mark(2026, 2, 1, CycleMarkTypes.ignoreTemperature),
      mark(2026, 3, 4, CycleMarkTypes.suzMorning),
      // A duplicate of the Mar 3 mark: the set collapses it and
      // time-of-day noise must not duplicate the day either.
      CycleMark(
        date: DateTime(2026, 3, 3, 12, 30),
        type: CycleMarkTypes.ignoreTemperature,
      ),
    ];

    test('indexes into the cycle’s tracked days, normalized per cycle', () {
      final cycles = groupIntoCycles(
        [...cycleOneEntries, ...cycleTwoEntries],
        overlayMarks.where((m) => m.type == CycleMarkTypes.cycleStart).toList(),
      );
      expect(cycles.length, 2);
      expect(
        ignoredDayIndexes(cycle: cycles[0], marks: ignoreMarks),
        {1, 3, 11},
        reason:
            'Mar 3 → index 1, Mar 5 → index 3, Mar 13 → index 11 '
            '(the data-less span extension belongs to the cycle)',
      );
      expect(ignoredDayIndexes(cycle: cycles[1], marks: ignoreMarks), {
        3,
      }, reason: 'Mar 19 → index 3; cycle 1’s marks are not cycle 2’s');
    });

    test('other mark types never contribute', () {
      final cycles = groupIntoCycles(cycleOneEntries, [
        mark(2026, 3, 2, CycleMarkTypes.cycleStart),
        mark(2026, 3, 5, CycleMarkTypes.mucusPeakDay),
      ]);
      expect(ignoredDayIndexes(cycle: cycles.single, marks: const []), isEmpty);
      expect(
        ignoredDayIndexes(
          cycle: cycles.single,
          marks: [mark(2026, 3, 5, CycleMarkTypes.mucusPeakDay)],
        ),
        isEmpty,
      );
    });
  });
}
