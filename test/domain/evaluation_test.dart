// Domain tests: evaluation arithmetic over (entries, marks) — the
// compute-only NER rules of docs/cheatsheet.md §Auswertung. Pure Dart —
// imports only lib/domain, runs on the host VM.
//
// Numbering direction: the cheat sheet says the six low measurements before
// the first higher are "zurücknummeriert" without saying which day is 1.
// These tests pin the arithmetic's choice — number 1 is the low measurement
// immediately BEFORE the first higher, counting backwards — and the
// implementation carries the matching TODO(user-review). If an INER expert
// rules otherwise, flip the direction here and in lib/domain/evaluation.dart.
//
// Mark kinds and ordinals (per-candidate rules): every above-baseline
// candidate from the marked rise onward is an ARROW while the mucus peak is
// unset or the day is at or before the peak day, and a CIRCLE after the peak
// day. Ordinals count WITHIN each kind (arrows 1–4, circles 1–4); the circle
// ordinal drives the SUZ rules D/E — rule D begins the SUZ the EVENING of
// the 3rd circle (≥ +0.2 K above the baseline), rule E the MORNING of the
// 4th circle (any margin) — the arrow ordinal expresses the arrow cap.
// Candidates beyond their kind's cap stay in the sequence unnumbered.
//
// Anchors (owner-confirmed): the MOST RECENT mark of each type inside a
// cycle drives the evaluation — the latest mucus-peak mark ("Höhepunkt =
// letzter Tag mit der besten Qualität"; multiple peaks arise from delayed
// ovulation) and the latest first-higher-measurement mark (re-marking
// supersedes). Earlier duplicate marks stay stored and render no candidate
// (see the "multiple marks" group below).

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/evaluation.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';

/// A tracked day; [t] is the measured BBT (null = day without measurement),
/// [excluded] sets one exclusion flag (illness) — any flag behaves the same
/// for the arithmetic (an interrupted day is an interrupted day).
DailyEntry d(
  int year,
  int month,
  int day, {
  double? t,
  bool excluded = false,
  Bleeding bleeding = Bleeding.none,
}) {
  return DailyEntry(
    date: DateTime(year, month, day),
    bbtC: t,
    bleeding: bleeding,
    excludeIllness: excluded,
  );
}

/// A user-placed mucus peak mark on (year, month, day).
CycleMark peak(int year, int month, int day) => CycleMark(
      profileId: 1,
      date: DateTime(year, month, day),
      type: CycleMarkTypes.mucusPeakDay,
    );

/// A user-placed first-higher-measurement mark on (year, month, day).
CycleMark rise(int year, int month, int day) => CycleMark(
      profileId: 1,
      date: DateTime(year, month, day),
      type: CycleMarkTypes.firstHigherMeasurement,
    );

/// The evaluation of the cycle group whose first tracked day is [start].
CycleEvaluation evalFor(
  List<DailyEntry> entries,
  List<CycleMark> marks,
  DateTime start,
) {
  return evaluateCycles(entries, marks, profileId: 1).firstWhere(
    (e) => DateOnly.sameDay(e.cycle.startDate, start),
  );
}

void main() {
  group('textbook pattern (happy path)', () {
    final entries = [
      d(2026, 3, 2, bleeding: Bleeding.medium), // cycle onset, unmeasured
      d(2026, 3, 3, t: 36.1),
      d(2026, 3, 4, t: 36.2),
      d(2026, 3, 5, t: 36.4), // highest of the six lows → baseline
      d(2026, 3, 6, t: 36.2),
      d(2026, 3, 7, t: 36.3),
      d(2026, 3, 8, t: 36.1),
      d(2026, 3, 9, t: 36.0), // a 7th low — OUTSIDE the 1–6 window
      d(2026, 3, 10, t: 36.1), // mucus peak day
      d(2026, 3, 11, t: 36.8), // first higher (marked) → circled
      d(2026, 3, 12, t: 36.9), // 2nd circled
      d(2026, 3, 13, t: 37.0), // 3rd circled, ≥ +0.2 K → SUZ (rule D)
      d(2026, 3, 14, t: 36.95), // higher, but the SUZ already began
    ];
    final marks = [peak(2026, 3, 10), rise(2026, 3, 11)];

    test('numbers the six low measurements counting back from the 1st higher',
        () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 11)));
      // Number 1 is the low immediately before the first higher (see the
      // file header note on numbering direction). The peak day itself is a
      // usable measured day before the first higher, so it consumes the
      // #1 slot (matching the locked working definition).
      expect(
        e.numberedLows.map((l) => (l.number, l.date.day)),
        [(1, 10), (2, 9), (3, 8), (4, 7), (5, 6), (6, 5)],
      );
      expect(e.numberedLows.map((l) => l.value),
          [36.1, 36.0, 36.1, 36.3, 36.2, 36.4]);
      // Mar 3 stays unnumbered: it is the 8th usable day before the rise
      // (Mar 4 is the 7th; both fall outside the 1–6 window).
    });

    test('draws the baseline through the HIGHEST of the six lows', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 5)));
    });

    test('baseline segment: starts at low #6, ends at the last candidate',
        () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // R10: the segment starts at the earliest numbered low day (low #6 —
      // Mar 5, the highest of the six) and ends at the last marked
      // candidate day (Mar 13, the rule-D trigger day). The Mar 14
      // measurement is beyond the completed sequence and does not extend
      // the segment.
      expect(
        e.baselineSpan!.startDay,
        DateOnly.normalize(DateTime(2026, 3, 5)),
      );
      expect(
        e.baselineSpan!.endDay,
        DateOnly.normalize(DateTime(2026, 3, 13)),
      );
    });

    test('circles the marked candidates; the SUZ day ends the sequence', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Rule D fires at the 3rd CIRCLE (37.0 ≥ 36.4 + 0.2), so the
      // sequence is complete after three circles; the Mar 14 measurement
      // (36.95, still above the baseline) is NOT marked — the evaluation
      // is finished, not stopped.
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (11, MarkKind.circle, 1),
          (12, MarkKind.circle, 2),
          (13, MarkKind.circle, 3),
        ],
      );
      // Difference-to-baseline per candidate (rendering input, rule R7).
      expect(e.higherMeasurements[0].differenceK, closeTo(0.4, 1e-9));
      expect(e.higherMeasurements[1].differenceK, closeTo(0.5, 1e-9));
      expect(e.higherMeasurements[2].differenceK, closeTo(0.6, 1e-9));
    });

    test('SUZ begins the evening of the 3rd circle via rule D', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)));
      expect(e.suzRule, SuzRule.d);
      expect(e.evaluationStopped, isFalse);
    });
  });

  group('rule R1 — candidacy is strictly above the baseline, any margin', () {
    test('a day exactly AT the baseline is not a candidate', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline (highest of the six)
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.4), // marked rise, but exactly AT the baseline
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      expect(e.higherMeasurements, isEmpty);
      // R10: no marked candidate → no baseline segment.
      expect(e.baselineSpan, isNull);
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test('a day ANY amount above the baseline is a candidate (+0.01 K)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.41), // marked rise, +0.01 K — still circled
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.higherMeasurements.single.differenceK, closeTo(0.01, 1e-9));
      expect(e.suzBegins, isNull);
    });
  });

  group('rule R2 — connectedness: one gap tolerated, two stop the run', () {
    test('ONE missing day between candidates keeps the sequence going', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        // Mar 11: untracked — the single tolerated gap day
        d(2026, 3, 12, t: 36.9), // candidate 2
        d(2026, 3, 13, t: 37.0), // candidate 3, ≥ +0.2 K → SUZ (rule D)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (12, MarkKind.circle, 2),
          (13, MarkKind.circle, 3),
        ],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)));
      expect(e.suzRule, SuzRule.d);
      expect(e.evaluationStopped, isFalse);
    });

    test('ONE day at/below the baseline between candidates keeps it going', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 36.3), // BELOW the baseline — the tolerated gap
        d(2026, 3, 12, t: 36.9), // candidate 2
        d(2026, 3, 13, t: 37.0), // candidate 3 → SUZ (rule D)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.ordinal)),
        [(10, 1), (12, 2), (13, 3)],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)));
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'ONE missing day between the last ARROW and the first CIRCLE keeps '
        'the sequence going (R2 spans the kind transition)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10, t: 36.8), // marked rise → arrow 1
        d(2026, 3, 11, t: 36.9), // peak day → arrow 2
        // Mar 12: untracked — the single tolerated gap day at the
        // arrow→circle transition
        d(2026, 3, 13, t: 37.0), // circle 1
        d(2026, 3, 14, t: 37.0), // circle 2
      ];
      final marks = [peak(2026, 3, 11), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (13, MarkKind.circle, 1),
          (14, MarkKind.circle, 2),
        ],
      );
      expect(e.evaluationStopped, isFalse);
      expect(e.suzBegins, isNull);
    });

    test(
        'TWO missing days at the arrow→circle transition break the sequence '
        'too', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10, t: 36.8), // marked rise → arrow 1
        d(2026, 3, 11, t: 36.9), // peak day → arrow 2
        // Mar 12–13: two untracked days across the transition → break
        d(2026, 3, 14, t: 37.0), // would-be circle — NOT marked
      ];
      final marks = [peak(2026, 3, 11), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isTrue);
    });

    test(
        'TWO missing days between candidates STOP the evaluation: no SUZ, '
        'no automatic re-search (later higher days stay unmarked)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        // Mar 11–12: two untracked days — more than one gap → break
        d(2026, 3, 13, t: 36.9), // would-be candidate — NOT marked
        d(2026, 3, 14, t: 37.0), // NOT marked either
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isTrue);
    });

    test('TWO days at/below the baseline between candidates break it too', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 36.3), // below baseline (gap 1)
        d(2026, 3, 12, t: 36.4), // exactly at baseline (gap 2)
        d(2026, 3, 13, t: 36.9), // would-be candidate — NOT marked
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isTrue);
    });

    test(
        'a gap run at the END of the data is not a break (nothing '
        'followed, so no two candidates are disconnected)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11), // tracked but unmeasured (gap 1)
        d(2026, 3, 12), // tracked but unmeasured (gap 2) — data ends here
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });
  });

  group('rule R3 — candidates exist only from the marked rise onward', () {
    test(
        'a pre-rise above-baseline day (Zacke) is no candidate and does '
        'not disturb the sequence', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 7, t: 36.8), // the pre-rise Zacke — NOT a candidate
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.2),
        d(2026, 3, 11, t: 36.3),
        d(2026, 3, 12, t: 36.2),
        d(2026, 3, 13, t: 36.3),
        d(2026, 3, 14, t: 36.2),
        d(2026, 3, 15, t: 36.4), // baseline (highest of the six)
        d(2026, 3, 16, t: 36.3),
        d(2026, 3, 17, t: 36.1),
        d(2026, 3, 18, t: 36.2),
        d(2026, 3, 19, t: 36.3),
        d(2026, 3, 20, t: 36.7), // marked rise → the ONLY candidate
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 20)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 9)));
      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 20)));
      expect(
        e.numberedLows.map((l) => (l.number, l.date.day)),
        [(1, 19), (2, 18), (3, 17), (4, 16), (5, 15), (6, 14)],
      );
      // The Zacke (36.8 on Mar 7) does NOT define the baseline — the six
      // lows closest to the marked first higher do.
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(20, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'the rise mark is taken verbatim: when the marked day is not above '
        'the baseline, the sequence starts at the next above-baseline day', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.4), // marked rise, but AT the baseline
        d(2026, 3, 11, t: 36.9), // first day above the baseline → candidate 1
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(11, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });
  });

  group('rule R4 — arrow vs circle, PER CANDIDATE', () {
    // Shared fixture: baseline 36.4 (Mar 6), rise on Mar 10.
    final entries = [
      d(2026, 3, 2, bleeding: Bleeding.medium),
      d(2026, 3, 3, t: 36.2),
      d(2026, 3, 4, t: 36.1),
      d(2026, 3, 5, t: 36.3),
      d(2026, 3, 6, t: 36.4), // baseline
      d(2026, 3, 7, t: 36.2),
      d(2026, 3, 8, t: 36.3),
      d(2026, 3, 9, t: 36.2),
      d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
      d(2026, 3, 11, t: 36.9), // candidate 2
      d(2026, 3, 12, t: 37.0), // candidate 3
    ];

    test('peak set BEFORE the rise → every candidate is CIRCLED', () {
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (11, MarkKind.circle, 2),
          (12, MarkKind.circle, 3),
        ],
      );
    });

    test('peak NOT set → every candidate is an ARROW (and no SUZ)', () {
      final marks = [rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, isNull);
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3),
        ],
      );
      // Even though the 3rd candidate is ≥ +0.2 K above the baseline, the
      // SUZ cannot be declared: rules D and E count CIRCLED measurements
      // only, and without circles there is nothing to count (the
      // TODO(user-review) in lib/domain/evaluation.dart cites the cheat
      // sheet's "umrandete" wording).
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'MIXED: peak between the marked rise and later candidates — arrows '
        'up to and including the peak day, circles afterwards', () {
      final mixed = [
        ...entries,
        d(2026, 3, 13, t: 37.0), // candidate 4 — first after the peak
      ];
      // The peak sits on candidate 2 (Mar 11, 36.9 > 36.4): the peak day's
      // own above-baseline temperature is an ARROW (R4).
      final marks = [peak(2026, 3, 11), rise(2026, 3, 10)];

      final e = evalFor(mixed, marks, DateTime(2026, 3, 2));

      // Ordinals are per kind: the arrows count among themselves, the
      // circles RESTART at 1 after the peak.
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2), // the peak-day candidate is an arrow
          (12, MarkKind.circle, 1),
          (13, MarkKind.circle, 2),
        ],
      );
      // Chronologically arrows precede circles — no interleaving.
      final firstCircle =
          e.higherMeasurements.indexWhere((h) => h.markKind == MarkKind.circle);
      expect(
        e.higherMeasurements.indexWhere(
          (h) => h.markKind == MarkKind.arrow,
          firstCircle,
        ),
        -1,
        reason: 'chronologically arrows precede circles — no interleaving',
      );
      // Only two circles so far: neither rule D (needs a 3rd circle) nor
      // rule E (needs a 4th) has triggered.
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test('peak ON the rise day → the rise-day candidate is an ARROW, '
        'later candidates are circles', () {
      final marks = [peak(2026, 3, 10), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.circle, 1),
          (12, MarkKind.circle, 2),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test('peak AFTER the rise → arrows until the peak day, circles after', () {
      final mixed = [
        ...entries,
        d(2026, 3, 13, t: 37.0), // first candidate after the peak
      ];
      // The peak mark sits on candidate 3 (Mar 12, 37.0 > 36.4).
      final marks = [peak(2026, 3, 12), rise(2026, 3, 10)];

      final e = evalFor(mixed, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3), // the peak-day candidate is an arrow
          (13, MarkKind.circle, 1),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'caps: four arrows with ordinals, then the circles continue to '
        'four (rule E fires at the 4th circle)', () {
      final long = [
        ...entries,
        d(2026, 3, 13, t: 36.5), // arrow 4
        d(2026, 3, 14, t: 36.5), // peak day — 5th arrow, beyond the cap
        d(2026, 3, 15, t: 36.5), // circle 1
        d(2026, 3, 16, t: 36.5), // circle 2
        d(2026, 3, 17, t: 36.5), // circle 3 — below the +0.2 margin
        d(2026, 3, 18, t: 36.5), // circle 4 — rule E fires here
      ];
      // The peak sits on the 5th candidate (Mar 14, 36.5 > 36.4): that
      // candidate is still an ARROW (at or before the peak day), but the
      // arrow cap is already exhausted — it stays in the sequence
      // UNNUMBERED while the circles after it get their own ordinals.
      final marks = [peak(2026, 3, 14), rise(2026, 3, 10)];

      final e = evalFor(long, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3),
          (13, MarkKind.arrow, 4),
          (14, MarkKind.arrow, null), // beyond the arrow cap — unnumbered
          (15, MarkKind.circle, 1),
          (16, MarkKind.circle, 2),
          (17, MarkKind.circle, 3),
          (18, MarkKind.circle, 4), // rule E fires here (any margin)
        ],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 18)));
      expect(e.suzRule, SuzRule.e);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'an arrows-only sequence keeps listing connected candidates beyond '
        'the arrow cap, unnumbered (no SUZ is possible anyway)', () {
      final long = [
        ...entries,
        d(2026, 3, 13, t: 36.5), // arrow 4
        d(2026, 3, 14, t: 36.5), // arrow 5 — beyond the cap, unnumbered
      ];
      final marks = [rise(2026, 3, 10)]; // peak NOT set

      final e = evalFor(long, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3),
          (13, MarkKind.arrow, 4),
          (14, MarkKind.arrow, null),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });
  });

  group(
      'multiple marks in one cycle — the MOST RECENT mark of each type '
      'anchors the evaluation (owner-confirmed)', () {
    // NOTE: rendering ALL mucus-peak marks of a cycle is chart/UI scope
    // (see the all-peaks rendering in lib/ui/cycle_marks.dart). The
    // domain only picks the ANCHORS: the latest mucus-peak mark and the
    // latest first-higher-measurement mark drive the evaluation; earlier
    // duplicates stay STORED (their removal is the sheet toggle's concern)
    // and simply stop anchoring.

    test(
        'two peaks: candidates up to and including the LAST peak are '
        'arrows, circles start at 1 after it; rule D fires on the 3rd '
        'circle under the late peak', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline (highest of the six lows)
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak 1 (early) — also low #1
        d(2026, 3, 10, t: 36.8), // marked rise (between the peaks) → arrow 1
        d(2026, 3, 11, t: 36.9), // arrow 2
        d(2026, 3, 12, t: 37.0), // peak 2 (late) → arrow 3 (peak-day candidate)
        d(2026, 3, 13, t: 37.0), // circle 1 — first candidate after the LAST peak
        d(2026, 3, 14, t: 37.0), // circle 2
        d(2026, 3, 15, t: 36.7), // circle 3, ≥ +0.2 K → rule D fires HERE
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        peak(2026, 3, 12),
      ];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The MOST RECENT peak (Mar 12) anchors the per-candidate decision —
      // "Höhepunkt = letzter Tag mit der besten Qualität": multiple peaks
      // arise from delayed ovulation (a peak subsides and a later one
      // appears), so the latest peak is the ovulation that counts for R4.
      expect(e.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 12)));
      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3), // the peak-day candidate is an arrow
          (13, MarkKind.circle, 1), // circle ordinals start at 1 AFTER the
          (14, MarkKind.circle, 2), // …last peak
          (15, MarkKind.circle, 3),
        ],
      );
      // Rules D/E count circles only; under the late peak the 3rd circle
      // (36.7 ≥ 36.4 + 0.2) triggers rule D on Mar 15 — NOT on Mar 12
      // (which would be the 3rd circle under an early-peak anchor).
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(e.suzRule, SuzRule.d);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'adding a later peak flips earlier circles back to arrows — '
        'compute-only re-evaluation, no mark changes', () {
      // The SAME data as the two-peak test above, but at the moment BEFORE
      // the second peak was placed: only peak 1 (Mar 9) exists, so every
      // candidate is a circle. The test pins both states to document the
      // flip: adding the later peak re-evaluates the SAME marks and the
      // candidates up to and including the new peak day become arrows.
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak 1
        d(2026, 3, 10, t: 36.8),
        d(2026, 3, 11, t: 36.9),
        d(2026, 3, 12, t: 37.0),
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final before = evalFor(entries, marks, DateTime(2026, 3, 2));
      expect(
        before.higherMeasurements
            .map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (11, MarkKind.circle, 2),
          (12, MarkKind.circle, 3),
        ],
      );

      final after = evalFor(
        entries,
        [...marks, peak(2026, 3, 12)],
        DateTime(2026, 3, 2),
      );
      expect(
        after.higherMeasurements
            .map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3),
        ],
      );
    });

    test(
        'a peak marked AFTER all candidates: every candidate stays an '
        'arrow → no SUZ (rules D/E count circles only)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak 1 (early, before the rise)
        d(2026, 3, 10, t: 36.8), // marked rise → arrow 1
        d(2026, 3, 11, t: 36.9), // arrow 2
        d(2026, 3, 12, t: 37.0), // arrow 3 — last candidate; data ends here
      ];
      // Peak 2 is marked on Mar 14 — AFTER every candidate (Mar 10–12).
      // Under the most-recent-peak anchor every candidate day is ≤ the
      // peak → arrows; arrows never trigger rules D/E → no SUZ.
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        peak(2026, 3, 14),
      ];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 14)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.arrow, 3),
        ],
      );
      expect(e.suzBegins, isNull,
          reason: 'an all-arrow sequence yields no circles, so rules D and '
              'E cannot fire — even though the 3rd candidate is ≥ +0.2 K');
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'two rise marks: the LATER one anchors the six-low window, the '
        'baseline and the walk; the earlier rise day renders no candidate',
        () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4),
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // EARLIER rise mark (premature Hochlage)
        d(2026, 3, 11, t: 36.3), // values fall back — the earlier rise broke
        d(2026, 3, 12, t: 36.4),
        d(2026, 3, 13, t: 36.9), // the REAL rise — re-marked here (later mark)
        d(2026, 3, 14, t: 37.0), // candidate 2
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        rise(2026, 3, 13),
      ];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The later mark supersedes: re-marking the rise (after a broken
      // Hochlage or a delayed second peak) moves the whole evaluation.
      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 13)));
      // The six-low window re-anchors to the LATER mark: the six usable
      // days before Mar 13.
      expect(
        e.numberedLows.map((l) => (l.number, l.date.day)),
        [(1, 12), (2, 11), (3, 10), (4, 9), (5, 8), (6, 7)],
      );
      // The earlier rise day's value (36.8 on Mar 10) is the highest of
      // the re-anchored window — it sets the baseline. (The earlier MARK
      // itself stops anchoring; its day is just a low of the new window.)
      expect(e.baseline!.value, 36.8);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 10)));
      // The earlier rise day renders NO candidate: the walk starts at the
      // later mark (R3), so Mar 10 lies before the walk region (it is also
      // AT the new baseline — doubly excluded).
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (13, MarkKind.circle, 1),
          (14, MarkKind.circle, 2),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse,
          reason: 'the re-anchored sequence is simply short — no break');
    });
  });

  group('rule R5 — SUZ rules D and E count circles only', () {
    test(
        'rule D regression: the 3rd CIRCLE exactly +0.2 K above the '
        'baseline triggers the SUZ (floating-point tolerance)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline (highest inside the six window)
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10, t: 36.3), // peak day — low #1 (Mar 11 is low #2)
        d(2026, 3, 12, t: 36.5), // marked rise → circle 1 (+0.1)
        d(2026, 3, 13, t: 36.5), // circle 2 (+0.1)
        d(2026, 3, 14, t: 36.6), // circle 3, exactly +0.2 K → rule D
      ];
      final marks = [peak(2026, 3, 10), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      // 36.4 + 0.2 is binary-floating-point-imprecise; the arithmetic must
      // still recognize 36.6 as exactly +0.2 K (epsilon in
      // lib/domain/evaluation.dart).
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 14)));
      expect(e.suzRule, SuzRule.d);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'rule E: 3rd circle below the margin, 4th circle at ANY margin → '
        'SUZ begins the MORNING of the 4th circle', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1 (+0.1)
        d(2026, 3, 11, t: 36.5), // circle 2 (+0.1)
        d(2026, 3, 12, t: 36.5), // circle 3 (+0.1 — below the +0.2 margin)
        d(2026, 3, 13, t: 36.41), // circle 4, only +0.01 K → rule E
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (11, MarkKind.circle, 2),
          (12, MarkKind.circle, 3),
          (13, MarkKind.circle, 4),
        ],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)),
          reason: 'rule E: the SUZ begins the MORNING of the 4th circled '
              'measurement day — the D→evening / E→morning mapping IS the '
              'time-of-day semantics: the domain reports the day plus the '
              'rule, the sheet renders the matching phrasing');
      expect(e.suzRule, SuzRule.e);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'exactly 3 circles, the 3rd below the +0.2 margin, data ends → '
        'NO SUZ, NOT stopped (rule E needs the 4th circle)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1 (+0.1)
        d(2026, 3, 11, t: 36.5), // circle 2 (+0.1)
        d(2026, 3, 12, t: 36.5), // circle 3 (+0.1 — below the margin); END
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (11, MarkKind.circle, 2),
          (12, MarkKind.circle, 3),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isFalse,
          reason: 'the data simply ran out — not a connectedness break');
    });

    test(
        'D/E count circles only: arrows before the peak do not advance the '
        'trigger — the SUZ fires on the 3rd CIRCLE, not the 3rd candidate',
        () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10, t: 36.5), // marked rise → arrow 1 (+0.1)
        d(2026, 3, 11, t: 36.5), // peak day → arrow 2 (+0.1)
        d(2026, 3, 12, t: 36.6), // circle 1 (+0.2 — 3rd CANDIDATE, but only
        // the 1st circle: NO trigger here)
        d(2026, 3, 13, t: 36.6), // circle 2 (+0.2)
        d(2026, 3, 14, t: 36.7), // circle 3 (+0.3 ≥ +0.2) → rule D HERE
      ];
      final marks = [peak(2026, 3, 11), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.arrow, 1),
          (11, MarkKind.arrow, 2),
          (12, MarkKind.circle, 1),
          (13, MarkKind.circle, 2),
          (14, MarkKind.circle, 3),
        ],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 14)),
          reason: 'the 3rd circle (Mar 14) triggers rule D — not the 3rd '
              'candidate (Mar 12), which was only the 1st circle');
      expect(e.suzRule, SuzRule.d);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'a break between the 3rd (below the margin) and the 4th circle '
        'prevents rule E: no SUZ, evaluation stopped', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1
        d(2026, 3, 11, t: 36.5), // circle 2
        d(2026, 3, 12, t: 36.5), // circle 3 — below the +0.2 margin
        // Mar 13–14: two untracked days → break before the 4th circle
        d(2026, 3, 15, t: 36.6), // would-be circle — NOT marked
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (11, MarkKind.circle, 2),
          (12, MarkKind.circle, 3),
        ],
      );
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isTrue);
    });

    test('only two circles and the data ends: no SUZ, not stopped', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1
        d(2026, 3, 11, t: 36.5), // circle 2 — data ends
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.higherMeasurements, hasLength(2));
      expect(e.suzBegins, isNull);
      expect(e.suzRule, isNull);
      expect(e.evaluationStopped, isFalse);
    });
  });

  group(
      'rule R8 — excluded days in the candidate sequence (excluded like '
      'missing)', () {
    test(
        'ONE excluded day between candidates consumes the tolerated gap; '
        'an above-baseline excluded value is never a candidate', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 37.2, excluded: true), // alcohol spike — a GAP,
        // not a candidate, despite being far above the baseline
        d(2026, 3, 12, t: 36.9), // candidate 2
        d(2026, 3, 13, t: 37.0), // candidate 3 → SUZ (rule D)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (10, MarkKind.circle, 1),
          (12, MarkKind.circle, 2),
          (13, MarkKind.circle, 3),
        ],
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)));
      expect(e.evaluationStopped, isFalse);
    });

    test('TWO excluded days in a row break the sequence', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 37.2, excluded: true), // gap 1
        d(2026, 3, 12, t: 37.0, excluded: true), // gap 2 → break
        d(2026, 3, 13, t: 36.9), // would-be candidate — NOT marked
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isTrue);
    });
  });

  group('baseline span (R10)', () {
    test('fewer than six lows: the segment starts at the oldest numbered low',
        () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.3), // low #4 — the OLDEST numbered low
        d(2026, 3, 5, t: 36.1), // low #3
        d(2026, 3, 6, t: 36.4), // low #2 — highest of the four → baseline
        d(2026, 3, 7, t: 36.3), // peak day (low #1)
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
      ];
      final marks = [peak(2026, 3, 7), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.numberedLows, hasLength(4));
      expect(e.baselineSpan!.startDay,
          DateOnly.normalize(DateTime(2026, 3, 3)));
      expect(e.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 3, 10)));
    });

    test('a cycle with tracked days after the last candidate ends at it', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1
        d(2026, 3, 11, t: 36.5), // circle 2 — data continues…
        d(2026, 3, 12, bleeding: Bleeding.light), // …but stays low
        d(2026, 3, 13, t: 36.2),
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Only two circles (the later days are at/below the baseline); the
      // segment ends at the LAST MARKED CANDIDATE, not at the cycle end.
      expect(e.higherMeasurements, hasLength(2));
      expect(e.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 3, 11)));
    });

    test(
        'the end never crosses the next menstruation start (R10 clamp — '
        'vacuous by construction, pinned defensively)', () {
      final entries = [
        // Cycle A: last candidate on its last tracked day (Mar 13)…
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1
        d(2026, 3, 11, t: 36.5), // circle 2
        d(2026, 3, 12, t: 36.5), // circle 3 — below the margin
        d(2026, 3, 13, t: 36.5), // circle 4 — rule E fires here
        // …and cycle B starts the very next day.
        d(2026, 3, 14, bleeding: Bleeding.medium),
        d(2026, 3, 15, t: 36.2),
        d(2026, 3, 16, t: 36.1),
        d(2026, 3, 17, t: 36.4),
        d(2026, 3, 18, t: 36.2),
        d(2026, 3, 19, t: 36.3),
        d(2026, 3, 20, t: 36.1),
        d(2026, 3, 21, t: 36.8), // first higher B (marked) → circle 1
        d(2026, 3, 22, t: 36.9), // circle 2
        d(2026, 3, 23, t: 37.0), // circle 3, ≥ +0.2 K → rule D
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        peak(2026, 3, 20),
        rise(2026, 3, 21),
      ];

      final a = evalFor(entries, marks, DateTime(2026, 3, 2));
      final b = evalFor(entries, marks, DateTime(2026, 3, 14));

      // A's end stays on its own last candidate day (Mar 13) even though
      // the next menstruation starts on Mar 14 and B's six-low window
      // begins on Mar 15 — the R10 min() clamps cannot pull the end
      // earlier by construction (the next cycle always starts after this
      // cycle's days).
      expect(a.baselineSpan!.startDay,
          DateOnly.normalize(DateTime(2026, 3, 4)));
      expect(a.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 3, 13)));
      // B has its own, independent segment.
      expect(b.baselineSpan!.startDay,
          DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(b.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 3, 23)));
    });

    test('multi-cycle evaluations carry independent baseline segments', () {
      final entries = [
        // Cycle A: onset Mar 2
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.4),
        d(2026, 3, 6, t: 36.2),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.1),
        d(2026, 3, 9, t: 36.0),
        d(2026, 3, 10, t: 36.1), // peak A
        d(2026, 3, 11, t: 36.8), // first higher A
        d(2026, 3, 12, t: 36.9),
        d(2026, 3, 13, t: 37.0),
        // Cycle B: onset Apr 6 (after a data gap)
        d(2026, 4, 6, bleeding: Bleeding.medium),
        d(2026, 4, 7, t: 36.2),
        d(2026, 4, 8, t: 36.1),
        d(2026, 4, 9, t: 36.4),
        d(2026, 4, 10, t: 36.3),
        d(2026, 4, 11, t: 36.2),
        d(2026, 4, 12, t: 36.0),
        d(2026, 4, 13, t: 36.1), // peak B
        d(2026, 4, 14, t: 36.8), // first higher B
        d(2026, 4, 15, t: 36.9),
        d(2026, 4, 16, t: 37.0),
      ];
      final marks = [
        peak(2026, 3, 10),
        rise(2026, 3, 11),
        peak(2026, 4, 13),
        rise(2026, 4, 14),
      ];

      final a = evalFor(entries, marks, DateTime(2026, 3, 2));
      final b = evalFor(entries, marks, DateTime(2026, 4, 6));

      // A: low #6 is Mar 5 (the window reaches back over the 7-day gap);
      // the segment ends at A's last circle and does NOT reach into B.
      expect(a.baselineSpan!.startDay,
          DateOnly.normalize(DateTime(2026, 3, 5)));
      expect(a.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 3, 13)));
      // B: low #6 is Apr 8 (the window covers Apr 8–13).
      expect(b.baselineSpan!.startDay,
          DateOnly.normalize(DateTime(2026, 4, 8)));
      expect(b.baselineSpan!.endDay,
          DateOnly.normalize(DateTime(2026, 4, 16)));
    });

    test('no marked candidates → no segment (null span)', () {
      // The rise mark sits exactly at the baseline: no candidate ever
      // appears, so R10 draws no baseline segment.
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2), // peak day
        d(2026, 3, 10, t: 36.4), // marked rise, but AT the baseline
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline, isNotNull);
      expect(e.higherMeasurements, isEmpty);
      expect(e.baselineSpan, isNull);
    });

    test('no first-higher mark → no segment (null span)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.2),
        d(2026, 3, 6, t: 36.4),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.2),
        d(2026, 3, 9, t: 36.4), // mucus peak day (marked)
        d(2026, 3, 11, t: 36.8), // a rise exists but is NOT marked
      ];
      final marks = [peak(2026, 3, 9)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline, isNull);
      expect(e.higherMeasurements, isEmpty);
      expect(e.baselineSpan, isNull);
    });
  });

  group('six-low numbering and baseline (unchanged logic)', () {
    test('calendar gaps in the data consume no low slot', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2), // untracked Mar 4–5
        d(2026, 3, 6, t: 36.4), // untracked Mar 7
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.1), // peak day
        d(2026, 3, 10, t: 36.2),
        d(2026, 3, 11, t: 36.3),
        d(2026, 3, 12, t: 36.7), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Exactly six usable days exist before the rise — the gap days
      // (Mar 4, 5, 7) consumed no slots, so nothing is left unnumbered.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (5, 6), (6, 3)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test('a tracked day missing its temperature consumes no low slot', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4), // tracked but NOT measured — no low slot
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4),
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.1), // peak day
        d(2026, 3, 12, t: 36.8), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Six measured lows exist (Mar 4 skipped) — the unmeasured day
      // consumed no slot, so six numbers still fit.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 9), (2, 8), (3, 7), (4, 6), (5, 5), (6, 3)]);
      expect(e.numberedLows.map((l) => l.date.day), isNot(contains(4)));
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test('excluded days consume no low slot', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 37.0, excluded: true), // fever — no low slot
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.1), // peak day
        d(2026, 3, 10, t: 36.3),
        d(2026, 3, 11, t: 36.2),
        d(2026, 3, 12, t: 36.8), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The fever day (Mar 4, 37.0) shifted nothing: the six lows are the
      // six closest usable days before the rise.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (5, 7), (6, 6)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test('fewer than six usable prior measurements: number only what exists',
        () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.3), // low #3
        d(2026, 3, 5, t: 36.1), // low #2
        d(2026, 3, 6, t: 36.4), // low #1 — highest of the three → baseline
        d(2026, 3, 7, t: 36.3), // peak day
        d(2026, 3, 10, t: 36.8), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 7), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The peak day (Mar 7, measured) is itself a usable day before the
      // first higher, so it takes the #1 slot (locked working definition).
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 7), (2, 6), (3, 5), (4, 3)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
    });
  });

  group('edge matrix', () {
    test(
        'missing peak: numbering + baseline still work; the candidates '
        'become arrows and no SUZ can be declared', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.4),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.2),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.1),
        d(2026, 3, 10, t: 36.7), // first higher (marked); peak NOT marked
      ];
      final marks = [rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, isNull);
      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 8), (2, 7), (3, 6), (4, 5), (5, 4), (6, 3)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 4)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.arrow, 1)],
      );
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'missing first-higher mark: only the peak is known, nothing else '
        'can be derived', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.2),
        d(2026, 3, 6, t: 36.4),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.2),
        d(2026, 3, 9, t: 36.4), // mucus peak day (marked)
        d(2026, 3, 11, t: 36.8), // a rise exists but is NOT marked
      ];
      final marks = [peak(2026, 3, 9)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 9)));
      expect(e.firstHigherDay, isNull);
      expect(e.numberedLows, isEmpty);
      expect(e.baseline, isNull);
      expect(e.higherMeasurements, isEmpty);
      expect(e.baselineSpan, isNull);
      expect(e.suzBegins, isNull);
      expect(e.evaluationStopped, isFalse);
    });

    test(
        'multiple cycles are evaluated independently; marks do not leak '
        'across cycle boundaries', () {
      final entries = [
        // Cycle A: onset Mar 2
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.4),
        d(2026, 3, 6, t: 36.2),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.1),
        d(2026, 3, 9, t: 36.0),
        d(2026, 3, 10, t: 36.1), // peak A
        d(2026, 3, 11, t: 36.8), // first higher A
        d(2026, 3, 12, t: 36.9),
        d(2026, 3, 13, t: 37.0),
        // Cycle B: onset Apr 6 (after a data gap)
        d(2026, 4, 6, bleeding: Bleeding.medium),
        d(2026, 4, 7, t: 36.2),
        d(2026, 4, 8, t: 36.1),
        d(2026, 4, 9, t: 36.4),
        d(2026, 4, 10, t: 36.3),
        d(2026, 4, 11, t: 36.2),
        d(2026, 4, 12, t: 36.0),
        d(2026, 4, 13, t: 36.1), // peak B
        d(2026, 4, 14, t: 36.8), // first higher B
        d(2026, 4, 15, t: 36.9),
        d(2026, 4, 16, t: 37.0),
      ];
      final marks = [
        peak(2026, 3, 10),
        rise(2026, 3, 11),
        peak(2026, 4, 13),
        rise(2026, 4, 14),
      ];

      final evaluations = evaluateCycles(entries, marks, profileId: 1);
      expect(evaluations, hasLength(2));

      final a = evalFor(entries, marks, DateTime(2026, 3, 2));
      expect(a.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 10)));
      expect(a.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 11)));
      expect(a.baseline!.value, 36.4);
      expect(a.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 5)));
      expect(
        a.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [
          (11, MarkKind.circle, 1),
          (12, MarkKind.circle, 2),
          (13, MarkKind.circle, 3),
        ],
      );
      expect(a.suzBegins, DateOnly.normalize(DateTime(2026, 3, 13)));
      expect(a.suzRule, SuzRule.d);
      expect(a.evaluationStopped, isFalse);

      final b = evalFor(entries, marks, DateTime(2026, 4, 6));
      expect(b.mucusPeakDay, DateOnly.normalize(DateTime(2026, 4, 13)));
      expect(b.firstHigherDay, DateOnly.normalize(DateTime(2026, 4, 14)));
      expect(b.baseline!.value, 36.4);
      expect(b.baseline!.date, DateOnly.normalize(DateTime(2026, 4, 9)));
      expect(b.suzBegins, DateOnly.normalize(DateTime(2026, 4, 16)));
      expect(b.suzRule, SuzRule.d);
      expect(b.evaluationStopped, isFalse);
    });

    test(
        'entries and marks of other profiles are ignored when profileId is '
        'given', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.3),
        DailyEntry(date: DateTime(2026, 3, 5), profileId: 2, bbtC: 37.5),
      ];
      final marks = [
        CycleMark(
          profileId: 2,
          date: DateTime(2026, 3, 5),
          type: CycleMarkTypes.mucusPeakDay,
        ),
      ];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.mucusPeakDay, isNull);
      expect(e.firstHigherDay, isNull);
      expect(e.numberedLows, isEmpty);
      expect(e.higherMeasurements, isEmpty);
      expect(e.suzBegins, isNull);
    });

    test('empty input yields no evaluations', () {
      expect(evaluateCycles(const [], const []), isEmpty);
    });
  });
}
