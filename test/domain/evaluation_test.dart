// Domain tests: evaluation arithmetic over (entries, marks) — the
// compute-only NER rules of docs/cheatsheet.md §Auswertung. Pure Dart —
// imports only lib/domain, runs on the host VM.
//
// Numbering (settled, owner-confirmed 2026-09-17): the six-low window is
// the SIX PREVIOUS CALENDAR DAYS before the user-marked first higher
// measurement (rise−1 … rise−6); numbers belong to CALENDAR POSITIONS —
// the measured, not-excluded day at rise−i carries number i. An
// unmeasured/untracked day inside the window gets NO number: numbers are
// skipped, e.g. "6 5 _ 3 _ 1" (day rise−4 and rise−2 unmeasured). The
// baseline is the MAX of the not-excluded measured temperatures within
// those six calendar days — no stretch-back to older measured days.
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

/// A tracked day; [t] is the measured BBT (null = day without measurement).
///
/// NOTE on exclusion: raw disturbance flags (tempDisturbances) do NOT
/// exclude a day from the analysis any more — the exclusion is the
/// ignoreTemperature MARK (see [excludedDay]), supplied alongside the
/// entries in the marks list.
DailyEntry d(
  int year,
  int month,
  int day, {
  double? t,
  Bleeding bleeding = Bleeding.none,
}) {
  return DailyEntry(
    date: DateTime(year, month, day),
    bbtC: t,
    bleeding: bleeding,
  );
}

/// A user-placed mucus peak mark on (year, month, day).
CycleMark peak(int year, int month, int day) => CycleMark(
      date: DateTime(year, month, day),
      type: CycleMarkTypes.mucusPeakDay,
    );

/// A user-placed first-higher-measurement mark on (year, month, day).
CycleMark rise(int year, int month, int day) => CycleMark(
      date: DateTime(year, month, day),
      type: CycleMarkTypes.firstHigherMeasurement,
    );

/// A user-placed cycleStart mark on (year, month, day) — the authoritative
/// cycle boundary (see lib/domain/cycle_grouping.dart: grouping is
/// mark-driven; bleeding only suggests).
CycleMark start(int year, int month, int day) => CycleMark(
      date: DateTime(year, month, day),
      type: CycleMarkTypes.cycleStart,
    );

/// The analysis-exclusion mark on (year, month, day): the ONLY exclusion
/// signal the evaluation consumes. Raw disturbance flags never exclude.
CycleMark excludedDay(int year, int month, int day) => CycleMark(
      date: DateTime(year, month, day),
      type: CycleMarkTypes.ignoreTemperature,
    );

/// The evaluation of the cycle group whose first tracked day is [start].
CycleEvaluation evalFor(
  List<DailyEntry> entries,
  List<CycleMark> marks,
  DateTime start,
) {
  return evaluateCycles(entries, marks).firstWhere(
    (e) => DateOnly.sameDay(e.cycle.startDate, start),
  );
}

/// The shared base of the standard scenarios: cycle onset (unmeasured)
/// plus the six-low run with the baseline on Mar 6 and the peak day on
/// Mar 9 — the entry lists of most tests append their marked rise day and
/// tail via the spread below.
final _baseLowRun = <DailyEntry>[
  d(2026, 3, 2, bleeding: Bleeding.medium), // cycle onset, unmeasured
  d(2026, 3, 3, t: 36.2),
  d(2026, 3, 4, t: 36.1),
  d(2026, 3, 5, t: 36.3),
  d(2026, 3, 6, t: 36.4), // baseline — the highest of the six lows
  d(2026, 3, 7, t: 36.2),
  d(2026, 3, 8, t: 36.3),
  d(2026, 3, 9, t: 36.2), // peak day (most scenarios set it here)
];

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
      // Number 1 is the low immediately before the first higher: numbers
      // are calendar offsets (rise−1 carries #1). The peak day itself is
      // measured, so it carries #1 — its mucus role does not matter here.
      expect(
        e.numberedLows.map((l) => (l.number, l.date.day)),
        [(1, 10), (2, 9), (3, 8), (4, 7), (5, 6), (6, 5)],
      );
      expect(e.numberedLows.map((l) => l.value),
          [36.1, 36.0, 36.1, 36.3, 36.2, 36.4]);
      // Mar 3 stays unnumbered: it is the 8th calendar day before the rise
      // (Mar 4 is the 7th; both fall outside the 1–6 window).
    });

    test('draws the baseline through the HIGHEST of the six lows', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 5)));
    });

    test('baseline segment: starts at low #6, ends at the last candidate', () {
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
      ..._baseLowRun,
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
      // only, and without circles there is nothing to count (the settled
      // rule in lib/domain/evaluation.dart cites the cheat sheet's
      // "umrandete" wording).
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

    test(
        'peak ON the rise day → the rise-day candidate is an ARROW, '
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
        ..._baseLowRun,
        d(2026, 3, 10, t: 36.8), // marked rise (between the peaks) → arrow 1
        d(2026, 3, 11, t: 36.9), // arrow 2
        d(2026, 3, 12, t: 37.0), // peak 2 (late) → arrow 3 (peak-day candidate)
        d(2026, 3, 13,
            t: 37.0), // circle 1 — first candidate after the LAST peak
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        'baseline and the walk; the earlier rise day renders no candidate', () {
      final entries = [
        ..._baseLowRun,
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
      // The six-low window re-anchors to the LATER mark: the six calendar
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        'trigger — the SUZ fires on the 3rd CIRCLE, not the 3rd candidate', () {
      final entries = [
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        ..._baseLowRun,
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
        'an ignoreTemperature MARK without any raw flags excludes: ONE '
        'marked day between candidates consumes the tolerated gap; its '
        'above-baseline value is never a candidate', () {
      final entries = [
        ..._baseLowRun,
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 37.2), // alcohol spike — a GAP via the MARK,
        // not a candidate, despite being far above the baseline (the entry
        // carries no raw exclusion flags at all)
        d(2026, 3, 12, t: 36.9), // candidate 2
        d(2026, 3, 13, t: 37.0), // candidate 3 → SUZ (rule D)
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        excludedDay(2026, 3, 11)
      ];

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

    test(
        'raw disturbance flags alone do NOT exclude: a flagged spike '
        'stays a candidate and the day is not a gap', () {
      // The mask (spät ins Bett, Krank, …) is RAW data for the interrupted
      // rendering — the analysis exclusion comes from the mark only. A
      // flagged 37.2 must therefore remain a candidate like any other
      // above-baseline measurement.
      final entries = [
        ..._baseLowRun,
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        DailyEntry(
          date: DateTime(2026, 3, 11),
          bbtC: 37.2,
          tempDisturbances:
              TempDisturbance.alk.bit | TempDisturbance.kr.bit, // flags only
        ), // candidate 2 — the flags alone do NOT exclude it
        d(2026, 3, 12, t: 36.9), // candidate 3 → SUZ (rule D)
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
        reason: 'raw flags no longer exclude from the analysis — the '
            'flagged day is an ordinary candidate',
      );
      expect(e.suzBegins, DateOnly.normalize(DateTime(2026, 3, 12)));
      expect(e.evaluationStopped, isFalse);
    });

    test('TWO marked (excluded) days in a row break the sequence', () {
      final entries = [
        ..._baseLowRun,
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
        d(2026, 3, 11, t: 37.2), // marked excluded — gap 1
        d(2026, 3, 12, t: 37.0), // marked excluded — gap 2 → break
        d(2026, 3, 13, t: 36.9), // would-be candidate — NOT marked
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        excludedDay(2026, 3, 11),
        excludedDay(2026, 3, 12),
      ];

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
        d(2026, 3, 3, t: 36.3), // BEFORE rise−6 — outside the window
        d(2026, 3, 5, t: 36.1), // rise−5 → #5
        d(2026, 3, 6, t: 36.4), // rise−4 → #4 — highest of the three → baseline
        d(2026, 3, 7, t: 36.3), // rise−3 → #3 (the peak day)
        d(2026, 3, 10, t: 36.8), // marked rise → candidate 1
      ];
      final marks = [peak(2026, 3, 7), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Only three measured days sit inside the six-calendar-day window
      // rise−1 … rise−6 = Mar 9 … Mar 4 (Mar 9, 8, 4 are untracked): the
      // numbers 3, 4, 5 belong to the calendar positions, the unmeasured
      // positions get no number. Untracked days do NOT stretch the window
      // back — the old arithmetic would have numbered Mar 3 as low #4.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(3, 7), (4, 6), (5, 5)]);
      // The segment starts at the earliest numbered low day (the #5 day,
      // Mar 5) — the old stretch-back arithmetic reached Mar 3 instead.
      expect(
          e.baselineSpan!.startDay, DateOnly.normalize(DateTime(2026, 3, 5)));
      expect(e.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 3, 10)));
    });

    test('a cycle with tracked days after the last candidate ends at it', () {
      final entries = [
        ..._baseLowRun,
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
      expect(e.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 3, 11)));
    });

    test(
        'the end never crosses the next menstruation start (R10 clamp — '
        'vacuous by construction, pinned defensively)', () {
      final entries = [
        // Cycle A: last candidate on its last tracked day (Mar 13)…
        ..._baseLowRun,
        d(2026, 3, 10, t: 36.5), // marked rise → circle 1
        d(2026, 3, 11, t: 36.5), // circle 2
        d(2026, 3, 12, t: 36.5), // circle 3 — below the margin
        d(2026, 3, 13, t: 36.5), // circle 4 — rule E fires here
        // …and cycle B starts the very next day (cycleStart mark).
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
        start(2026, 3, 2),
        peak(2026, 3, 9),
        rise(2026, 3, 10),
        start(2026, 3, 14),
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
      expect(
          a.baselineSpan!.startDay, DateOnly.normalize(DateTime(2026, 3, 4)));
      expect(a.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 3, 13)));
      // B has its own, independent segment.
      expect(
          b.baselineSpan!.startDay, DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(b.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 3, 23)));
    });

    test('multi-cycle evaluations carry independent baseline segments', () {
      final entries = [
        // Cycle A: starts at the Mar 2 cycleStart mark
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
        // Cycle B: starts at the Apr 6 cycleStart mark (after a data gap)
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
        start(2026, 3, 2),
        peak(2026, 3, 10),
        rise(2026, 3, 11),
        start(2026, 4, 6),
        peak(2026, 4, 13),
        rise(2026, 4, 14),
      ];

      final a = evalFor(entries, marks, DateTime(2026, 3, 2));
      final b = evalFor(entries, marks, DateTime(2026, 4, 6));

      // A: low #6 is Mar 5 (the window reaches back over the 7-day gap);
      // the segment ends at A's last circle and does NOT reach into B.
      expect(
          a.baselineSpan!.startDay, DateOnly.normalize(DateTime(2026, 3, 5)));
      expect(a.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 3, 13)));
      // B: low #6 is Apr 8 (the window covers Apr 8–13).
      expect(
          b.baselineSpan!.startDay, DateOnly.normalize(DateTime(2026, 4, 8)));
      expect(b.baselineSpan!.endDay, DateOnly.normalize(DateTime(2026, 4, 16)));
    });

    test('no marked candidates → no segment (null span)', () {
      // The rise mark sits exactly at the baseline: no candidate ever
      // appears, so R10 draws no baseline segment.
      final entries = [
        ..._baseLowRun,
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

  group(
      'six-low window and baseline (calendar positions, owner ruling '
      '2026-09-17)', () {
    test('untracked days inside the window get no number — numbers skip', () {
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

      // The window is rise−1 … rise−6 = Mar 11 … Mar 6. Mar 7 (rise−5) is
      // untracked — it gets no number and its number 5 is SKIPPED; the
      // numbers belong to calendar positions, so only five lows carry
      // numbers (the old dense arithmetic would have numbered Mar 3 as #6).
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (6, 6)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test(
        'an unmeasured window day gets no number — numbers skip, no '
        'stretch-back', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4), // tracked but NOT measured
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4),
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.1), // peak day
        d(2026, 3, 12, t: 36.8), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The window is rise−1 … rise−6 = Mar 11 … Mar 6. Mar 11 and Mar 10
      // are untracked (numbers 1 and 2 skipped), Mar 4 lies BEFORE the
      // window end — under the calendar rule only four lows are numbered:
      // 3, 4, 5, 6. The old dense arithmetic numbered six lows 1–6,
      // stretching back to Mar 3.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(3, 9), (4, 8), (5, 7), (6, 6)]);
      expect(e.numberedLows.map((l) => l.number), [3, 4, 5, 6]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test('a marked (excluded) day before the window changes nothing', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 37.0), // fever day — before the window, and
        // excluded via the MARK: contributes no temperature, hence no low.
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.1), // peak day
        d(2026, 3, 10, t: 36.3),
        d(2026, 3, 11, t: 36.2),
        d(2026, 3, 12, t: 36.8), // first higher (marked)
      ];
      final marks = [
        peak(2026, 3, 9),
        rise(2026, 3, 12),
        excludedDay(2026, 3, 4)
      ];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The fever day (Mar 4, 37.0) lies before the window (rise−1 …
      // rise−6 = Mar 11 … Mar 6) and shifted nothing: the window's six
      // positions are all measured, so all six numbers are used.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (5, 7), (6, 6)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });

    test(
        'fewer than six measured days inside the window: number only '
        'what exists', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.3), // BEFORE rise−6 — outside the window
        d(2026, 3, 5, t: 36.1), // rise−5 → #5
        d(2026, 3, 6, t: 36.4), // rise−4 → #4 — highest → baseline
        d(2026, 3, 7, t: 36.3), // rise−3 → #3 (the peak day)
        d(2026, 3, 10, t: 36.8), // first higher (marked)
      ];
      final marks = [peak(2026, 3, 7), rise(2026, 3, 10)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The window rise−1 … rise−6 = Mar 9 … Mar 4 contains exactly three
      // measured days (Mar 9, 8, 4 are untracked): numbers 3, 4, 5. The
      // old dense arithmetic would have numbered Mar 3 as #4.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(3, 7), (4, 6), (5, 5)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
      expect(
        e.higherMeasurements.map((h) => (h.date.day, h.markKind, h.ordinal)),
        [(10, MarkKind.circle, 1)],
      );
      expect(e.suzBegins, isNull);
    });
  });

  group('six-low window: calendar positions (owner ruling 2026-09-17)', () {
    test(
        'numbering is the calendar offset — unmeasured and untracked days '
        'inside the window get no number, numbers skip ("6 5 _ 3 _ 1")', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 5, t: 36.1), // rise−6 → #6
        d(2026, 3, 6, t: 36.2), // rise−5 → #5
        d(2026, 3, 7), // rise−4: tracked but unmeasured — NO number
        d(2026, 3, 8, t: 36.2), // rise−3 → #3
        // Mar 9: untracked — rise−2 carries NO number either
        d(2026, 3, 10, t: 36.3), // rise−1 → #1
        d(2026, 3, 11, t: 36.8), // marked rise
      ];
      final marks = [rise(2026, 3, 11)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The owner example "6 5 _ 3 _ 1": the numbers belong to the
      // CALENDAR POSITIONS rise−1 … rise−6 — an omitted day gets no
      // number and its number is skipped. The old dense arithmetic would
      // have produced 1, 2, 3, 4 over the same four measured days.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 10), (3, 8), (5, 6), (6, 5)]);
    });

    // Shared fixture: only THREE measured days sit inside the
    // six-calendar-day window rise−1 … rise−6 = Mar 9 … Mar 4 (Mar 8, 6, 4
    // are untracked). Mar 3 is measured too, but OLDER than rise−6 — the
    // old stretch-back arithmetic pulled it into the window (numbering it
    // #4) and let its 36.6 set the baseline.
    final stretchEntries = [
      d(2026, 3, 2, bleeding: Bleeding.medium),
      d(2026, 3, 3, t: 36.6), // before rise−6 — OUTSIDE the window
      d(2026, 3, 5, t: 36.1), // rise−5 → #5
      d(2026, 3, 7, t: 36.2), // rise−3 → #3
      d(2026, 3, 9, t: 36.3), // rise−1 → #1
      d(2026, 3, 10, t: 36.8), // marked rise
    ];
    final stretchMarks = [rise(2026, 3, 10)];

    test('unmeasured days do NOT stretch the window back', () {
      final e = evalFor(stretchEntries, stretchMarks, DateTime(2026, 3, 2));

      // Exactly the measured days of rise−1 … rise−6 are numbered — the
      // old arithmetic would have numbered Mar 3 as low #4 (four lows).
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 9), (3, 7), (5, 5)]);
    });

    test(
        'baseline = max over the six-calendar-day window — old-vs-new '
        'disagreement: no stretch-back to an older higher day', () {
      final e = evalFor(stretchEntries, stretchMarks, DateTime(2026, 3, 2));

      // The old stretch-back arithmetic found the 36.6 on Mar 3 and set
      // the baseline there; the calendar window ignores it — the baseline
      // is the highest measured day INSIDE the window.
      expect(e.baseline!.value, 36.3);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 9)));
    });

    test(
        'a marked (excluded) day occupies its calendar day and contributes '
        'no temperature (number skipped, no baseline contribution) — with '
        'no raw flags at all', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 6, t: 36.4), // rise−6 → #6 — highest inside the window
        d(2026, 3, 7, t: 37.5), // rise−5: the day EXISTS and is measured,
        // but the ignoreTemperature MARK makes its 37.5 get no number
        // and raise no baseline (the entry carries no raw flags)
        d(2026, 3, 8, t: 36.3), // rise−4 → #4
        d(2026, 3, 9, t: 36.1), // rise−3 → #3
        d(2026, 3, 10, t: 36.3), // rise−2 → #2
        d(2026, 3, 11, t: 36.2), // rise−1 → #1
        d(2026, 3, 12, t: 36.8), // marked rise
      ];
      final marks = [rise(2026, 3, 12), excludedDay(2026, 3, 7)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // Five numbered lows: number 5 is skipped (the excluded rise−5 day
      // occupies it but carries no temperature). The old dense arithmetic
      // would have numbered Mar 6 as #5.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (6, 6)]);
      // The excluded 37.5 (which would have raised the baseline) counts
      // as nothing — the baseline is the max of the not-excluded measured
      // temperatures within the window.
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
    });
  });

  group('rise-mark consistency (owner decision 2026-09-17)', () {
    // Shared fixture: the six-calendar-day window before the Mar 11 mark
    // is Mar 5..Mar 10 (36.2, 36.4, 36.1, unmeasured, 36.3, 36.2), so the
    // baseline is the 36.4 on Mar 6 — the highest not-excluded measured
    // temperature inside the window. The marked day itself varies per test.
    final baseEntries = [
      d(2026, 3, 2, bleeding: Bleeding.medium),
      d(2026, 3, 5, t: 36.2), // rise−6
      d(2026, 3, 6, t: 36.4), // rise−5 — highest in the window → baseline
      d(2026, 3, 7, t: 36.1),
      d(2026, 3, 8), // rise−4: tracked but unmeasured
      d(2026, 3, 9, t: 36.3),
      d(2026, 3, 10, t: 36.2),
      d(2026, 3, 11, t: 36.9), // the marked rise day
    ];
    final riseMark = [rise(2026, 3, 11)];

    test('true when the marked day lies strictly above the baseline', () {
      final e = evalFor(baseEntries, riseMark, DateTime(2026, 3, 2));

      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 11)));
      expect(e.baseline!.value, 36.4);
      expect(e.riseMarkConsistent, isTrue);
    });

    test(
        'false when the marked value is NOT strictly above the baseline '
        '(equal or below)', () {
      // 36.4 equals the baseline; the check demands STRICTLY above.
      final equal = [
        ...baseEntries.take(7),
        d(2026, 3, 11, t: 36.4),
      ];
      final eEqual = evalFor(equal, riseMark, DateTime(2026, 3, 2));
      expect(eEqual.riseMarkConsistent, isFalse,
          reason: '36.4 is not STRICTLY above the baseline 36.4');

      // 36.3 lies below the baseline 36.4.
      final below = [
        ...baseEntries.take(7),
        d(2026, 3, 11, t: 36.3),
      ];
      final eBelow = evalFor(below, riseMark, DateTime(2026, 3, 2));
      expect(eBelow.riseMarkConsistent, isFalse);
    });

    test('false when the marked day is tracked but unmeasured', () {
      final entries = [
        ...baseEntries.take(7),
        d(2026, 3, 11), // no temperature recorded
      ];
      final e = evalFor(entries, riseMark, DateTime(2026, 3, 2));

      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 11)));
      expect(e.baseline!.value, 36.4);
      expect(e.riseMarkConsistent, isFalse);
    });

    test(
        'false when the marked day is excluded (ignoreTemperature mark, '
        'no raw flags needed)', () {
      final entries = [
        ...baseEntries.take(7),
        d(2026, 3, 11, t: 37.0), // fever day — measured, but excluded via
        // the MARK (raw flags do not exclude)
      ];
      final marks = [rise(2026, 3, 11), excludedDay(2026, 3, 11)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.riseMarkConsistent, isFalse,
          reason: 'an excluded temperature is not usable for the check');
    });

    test('null when no first-higher mark exists', () {
      final e = evalFor(baseEntries, [peak(2026, 3, 9)], DateTime(2026, 3, 2));

      expect(e.firstHigherDay, isNull);
      expect(e.riseMarkConsistent, isNull);
    });

    test('null when no baseline exists (no usable low in the window)', () {
      // The window Mar 5..Mar 10 of the Mar 11 mark carries no measured,
      // not-excluded temperature — without a baseline the check is
      // undefined (null), even though the marked day is measured.
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 11, t: 36.9), // marked rise; Mar 3..10 untracked
      ];
      final e = evalFor(entries, riseMark, DateTime(2026, 3, 2));

      expect(e.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 11)));
      expect(e.baseline, isNull);
      expect(e.riseMarkConsistent, isNull);
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
      // Mar 9 is untracked — its calendar position (rise−1) carries no
      // number, so the numbering starts at #2 and NO number stretches the
      // window back to Mar 3 (the old arithmetic numbered Mar 3 as #6).
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(2, 8), (3, 7), (4, 6), (5, 5), (6, 4)]);
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
        // Cycle A: starts at the Mar 2 cycleStart mark
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
        // Cycle B: starts at the Apr 6 cycleStart mark (after a data gap)
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
        start(2026, 3, 2),
        peak(2026, 3, 10),
        rise(2026, 3, 11),
        start(2026, 4, 6),
        peak(2026, 4, 13),
        rise(2026, 4, 14),
      ];

      final evaluations = evaluateCycles(entries, marks);
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

    test('empty input yields no evaluations', () {
      expect(evaluateCycles(const [], const []), isEmpty);
    });
  });

  group('mark-driven cycle windows flow into the evaluation', () {
    test(
        'a cycleStart mark splits the tracked days into independent '
        'evaluation windows — the peak/rise anchors bind per window', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2, t: 36.2),
        d(2026, 3, 3, t: 36.1),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.4), // highest of window 1's six lows → baseline
        d(2026, 3, 6, t: 36.2),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.8), // marked rise of window 1
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10), // the cycleStart-mark day (unmeasured — irrelevant)
        d(2026, 3, 11, t: 36.2),
        d(2026, 3, 12, t: 36.1),
        d(2026, 3, 13, t: 36.3),
        d(2026, 3, 14, t: 36.4), // highest of window 2's six lows → baseline
        d(2026, 3, 15, t: 36.2),
        d(2026, 3, 16, t: 36.3),
        d(2026, 3, 17, t: 36.8), // marked rise of window 2
        d(2026, 3, 18, t: 36.9),
      ];
      final marks = [
        peak(2026, 3, 5),
        rise(2026, 3, 8),
        start(2026, 3, 10),
        peak(2026, 3, 15),
        rise(2026, 3, 17),
      ];

      final a = evalFor(entries, marks, DateTime(2026, 3, 1));
      expect(a.cycle.startsAtMenstruation, isFalse,
          reason: 'the leading group predates the first cycleStart mark');
      expect(a.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 8)));
      expect(a.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 5)));
      expect(a.baseline!.value, 36.4);
      expect(a.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 5)));

      final b = evalFor(entries, marks, DateTime(2026, 3, 10));
      expect(b.cycle.startsAtMenstruation, isTrue,
          reason: 'the mark-driven group opens at the marked day');
      expect(b.firstHigherDay, DateOnly.normalize(DateTime(2026, 3, 17)),
          reason: 'the window 1 rise (Mar 8) lies before window 2 and does '
              'not anchor it');
      expect(b.mucusPeakDay, DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(b.baseline!.value, 36.4);
      expect(b.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 14)));
    });

    test(
        'without a cycleStart mark the same data is ONE window — the '
        'latest rise anchors the whole run', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2, t: 36.2),
        d(2026, 3, 3, t: 36.1),
        d(2026, 3, 4, t: 36.3),
        d(2026, 3, 5, t: 36.4),
        d(2026, 3, 6, t: 36.2),
        d(2026, 3, 7, t: 36.3),
        d(2026, 3, 8, t: 36.8), // marked rise of window 1
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10),
        d(2026, 3, 11, t: 36.2),
        d(2026, 3, 12, t: 36.1),
        d(2026, 3, 13, t: 36.3),
        d(2026, 3, 14, t: 36.4),
        d(2026, 3, 15, t: 36.2),
        d(2026, 3, 16, t: 36.3),
        d(2026, 3, 17, t: 36.8), // marked rise of window 2 — the LATEST
        d(2026, 3, 18, t: 36.9),
      ];
      final marks = [
        peak(2026, 3, 5),
        rise(2026, 3, 8),
        peak(2026, 3, 15),
        rise(2026, 3, 17),
      ];

      final evaluations = evaluateCycles(entries, marks);
      expect(evaluations, hasLength(1));
      expect(evaluations.single.firstHigherDay,
          DateOnly.normalize(DateTime(2026, 3, 17)),
          reason: 'the most-recent rise mark anchors the single group');
    });
  });
}
