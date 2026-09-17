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
      d(2026, 3, 13, t: 37.0), // 3rd circled → SUZ begins this evening
      d(2026, 3, 14, t: 36.95), // higher, but beyond the 3rd circle
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
      // Mar 3 stays unnumbered: it is the 7th usable day before the rise.
    });

    test('draws the baseline through the HIGHEST of the six lows', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 5)));
    });

    test('circles the first three higher measurements after the peak', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [
          (11, HigherPosition.afterPeak, 1),
          (12, HigherPosition.afterPeak, 2),
          (13, HigherPosition.afterPeak, 3),
          (14, HigherPosition.afterPeak, null), // higher, not circled
        ],
      );
    });

    test('SUZ begins the evening of the 3rd circled higher measurement', () {
      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.suzBeginsEvening, DateOnly.normalize(DateTime(2026, 3, 13)));
    });
  });

  group('edge matrix', () {
    test('a rise BEFORE the peak is exposed as before-peak (arrow-up only), '
        'never circled and never a 1–6 low', () {
      // The pre-peak Zacke sits far enough before the (late-marked) first
      // higher that it falls outside the six-low window — otherwise the
      // locked "low = any usable day before the 1st higher" definition
      // would make the Zacke itself the baseline (see the matching
      // TODO(user-review) in lib/domain/evaluation.dart).
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 7, t: 36.8), // the pre-peak rise (Zacke)
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
        d(2026, 3, 20, t: 36.7), // first higher (marked)
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
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [
          (7, HigherPosition.beforePeak, null), // arrow-up territory
          (20, HigherPosition.afterPeak, 1),
        ],
      );
      expect(e.suzBeginsEvening, isNull);
    });

    test('missing peak: numbering + baseline still work, but nothing can be '
        'judged pre-peak vs post-peak (position unknown, no circles, no SUZ)',
        () {
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
      // Without a peak the relative position is unknowable — exposed as
      // null so the UI can decide to draw nothing.
      expect(
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [(10, null, null)],
      );
      expect(e.suzBeginsEvening, isNull);
    });

    test('missing first-higher mark: only the peak is known, nothing else '
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
      expect(e.suzBeginsEvening, isNull);
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
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [(10, HigherPosition.afterPeak, 1)],
      );
      expect(e.suzBeginsEvening, isNull);
    });

    test('excluded days consume no low slot and are never circled higher '
        'measurements', () {
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
        d(2026, 3, 14, t: 37.2, excluded: true), // alcohol spike — no circle
        d(2026, 3, 15, t: 36.9),
      ];
      final marks = [peak(2026, 3, 9), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      // The fever day (Mar 4, 37.0) shifted nothing: the six lows are the
      // six closest usable days before the rise.
      expect(e.numberedLows.map((l) => (l.number, l.date.day)),
          [(1, 11), (2, 10), (3, 9), (4, 8), (5, 7), (6, 6)]);
      expect(e.baseline!.value, 36.4);
      expect(e.baseline!.date, DateOnly.normalize(DateTime(2026, 3, 6)));
      // The alcohol spike (Mar 14, 37.2) is NOT a circled higher — if it
      // were counted, it would be the 2nd circle and Mar 15 the 3rd, and
      // SUZ would wrongly begin on Mar 15.
      expect(
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [(12, HigherPosition.afterPeak, 1), (15, HigherPosition.afterPeak, 2)],
      );
      expect(e.suzBeginsEvening, isNull);
    });

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

    test('multiple cycles are evaluated independently; marks do not leak '
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
      expect(a.suzBeginsEvening, DateOnly.normalize(DateTime(2026, 3, 13)));

      final b = evalFor(entries, marks, DateTime(2026, 4, 6));
      expect(b.mucusPeakDay, DateOnly.normalize(DateTime(2026, 4, 13)));
      expect(b.firstHigherDay, DateOnly.normalize(DateTime(2026, 4, 14)));
      expect(b.baseline!.value, 36.4);
      expect(b.baseline!.date, DateOnly.normalize(DateTime(2026, 4, 9)));
      expect(b.suzBeginsEvening, DateOnly.normalize(DateTime(2026, 4, 16)));
    });

    test('entries and marks of other profiles are ignored when profileId is '
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
      expect(e.suzBeginsEvening, isNull);
    });

    test('empty input yields no evaluations', () {
      expect(evaluateCycles(const [], const []), isEmpty);
    });
  });

  group('higher-measurement boundary (locked working definition)', () {
    test('a day exactly AT the baseline is not higher; exactly 0.2 K above '
        'it is (floating-point tolerance)', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, t: 36.2),
        d(2026, 3, 4, t: 36.1),
        d(2026, 3, 5, t: 36.3),
        d(2026, 3, 6, t: 36.4), // baseline (highest inside the six window)
        d(2026, 3, 7, t: 36.2),
        d(2026, 3, 8, t: 36.3),
        d(2026, 3, 9, t: 36.2),
        d(2026, 3, 10, t: 36.3), // peak day — 7th usable, outside the window
        d(2026, 3, 11, t: 36.4), // exactly at the baseline → NOT higher
        d(2026, 3, 12, t: 36.6), // exactly +0.2 K → higher (1st circled)
      ];
      final marks = [peak(2026, 3, 10), rise(2026, 3, 12)];

      final e = evalFor(entries, marks, DateTime(2026, 3, 2));

      expect(e.baseline!.value, 36.4);
      // 36.4 + 0.2 is binary-floating-point-imprecise; the arithmetic must
      // still recognize 36.6 as exactly +0.2 K (see the epsilon comment in
      // lib/domain/evaluation.dart). The exactly-at-baseline day (Mar 11)
      // must NOT appear.
      expect(
        e.higherMeasurements
            .map((h) => (h.date.day, h.position, h.circleOrd)),
        [(12, HigherPosition.afterPeak, 1)],
      );
      expect(e.suzBeginsEvening, isNull);
    });
  });
}
