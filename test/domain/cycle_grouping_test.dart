// Domain tests: cycle grouping (boundaries between cycles).
// Pure Dart — imports only lib/domain, runs on the host VM.

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/models.dart';

DailyEntry d(
  int year,
  int month,
  int day, {
  Bleeding bleeding = Bleeding.none,
  bool interrupted = false,
}) {
  return DailyEntry(
    date: DateTime(year, month, day),
    bleeding: bleeding,
    excludeIllness: interrupted && bleeding == Bleeding.period,
    excludeTravel: interrupted && bleeding != Bleeding.period,
  );
}

void main() {
  group('groupIntoCycles', () {
    test('splits three menstrual cycles at their period onsets', () {
      final entries = <DailyEntry>[
        // cycle 1: onset Mar 2, bleeding 3 days, then a few tracked days
        d(2026, 3, 2, bleeding: Bleeding.period),
        d(2026, 3, 3, bleeding: Bleeding.period),
        d(2026, 3, 4),
        // cycle 2: onset Mar 30 (28-day cycle); tracked only partially,
        // plus one spotting-only day mid-cycle that must NOT be a boundary
        d(2026, 3, 30, bleeding: Bleeding.period),
        d(2026, 4, 10, bleeding: Bleeding.spotting),
        // cycle 3: onset Apr 27
        d(2026, 4, 27, bleeding: Bleeding.period),
        d(2026, 4, 28),
      ];

      final cycles = groupIntoCycles(entries);

      expect(cycles, hasLength(3));
      expect(cycles.map((c) => c.startsAtMenstruation), everyElement(isTrue));
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].startDate, DateTime(2026, 3, 30));
      expect(cycles[2].startDate, DateTime(2026, 4, 27));

      // cycle membership: cycle 1 owns Mar 2..4, cycle 2 owns Mar 30 + the
      // spotting day, cycle 3 owns Apr 27..28.
      expect(
        cycles[0].days.map((e) => e.date.day).toList(),
        [2, 3, 4],
      );
      expect(
        cycles[1].days.map((e) => (e.bleeding, e.date.day)).toList(),
        const [(Bleeding.period, 30), (Bleeding.spotting, 10)],
      );
      expect(cycles[2].days, hasLength(2));

      // Menstruation onset dates are exposed for the stats layer.
      // Onsets are UTC-normalized (DST-immune day arithmetic), so compare
      // against normalized expectations.
      expect(
        menstruationOnsetDates(entries),
        [
          DateOnly.normalize(DateTime(2026, 3, 2)),
          DateOnly.normalize(DateTime(2026, 3, 30)),
          DateOnly.normalize(DateTime(2026, 4, 27)),
        ],
      );
    });

    test('entries before the first onset form an unbounded leading group', () {
      final entries = [
        d(2026, 2, 20), // mid-cycle data, no known period yet
        d(2026, 2, 21),
        d(2026, 3, 2, bleeding: Bleeding.period), // first known onset
        d(2026, 3, 3),
      ];
      final cycles = groupIntoCycles(entries);
      expect(cycles, hasLength(2));
      expect(cycles[0].startsAtMenstruation, isFalse);
      expect(cycles[0].startDate, DateTime(2026, 2, 20));
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 2));
    });

    test('interrupted (excluded) bleeding days do NOT start cycles', () {
      final entries = [
        d(2026, 4, 1, bleeding: Bleeding.period), // onset of cycle
        d(2026, 4, 2),
        // A period day flagged as interrupted (illness) is not a boundary —
        // the next NORMAL period day becomes the true onset:
        d(2026, 4, 29, bleeding: Bleeding.period, interrupted: true),
        d(2026, 4, 30, bleeding: Bleeding.period),
        d(2026, 5, 1),
      ];
      final cycles = groupIntoCycles(entries);
      expect(
        menstruationOnsetDates(entries),
        [
          DateOnly.normalize(DateTime(2026, 4, 1)),
          DateOnly.normalize(DateTime(2026, 4, 30)),
        ],
      );
      expect(cycles, hasLength(2));
      expect(cycles[1].startDate, DateTime(2026, 4, 30));
    });

    test('consecutive period days are ONE menstruation, not many cycles', () {
      final entries = [
        d(2026, 6, 1, bleeding: Bleeding.period),
        d(2026, 6, 2, bleeding: Bleeding.period),
        d(2026, 6, 3, bleeding: Bleeding.period),
      ];
      final cycles = groupIntoCycles(entries);
      expect(cycles, hasLength(1));
      expect(menstruationOnsetDates(entries), [DateTime(2026, 6, 1)]);
    });

    test('empty input produces no cycles', () {
      final cycles = groupIntoCycles(const <DailyEntry>[]);
      expect(cycles, isEmpty);
      expect(menstruationOnsetDates(const <DailyEntry>[]), isEmpty);
    });

    test('unsorted input is sorted internally', () {
      final entries = [
        d(2026, 4, 27, bleeding: Bleeding.period),
        d(2026, 3, 2, bleeding: Bleeding.period),
      ];
      final cycles = groupIntoCycles(entries);
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].startDate, DateTime(2026, 4, 27));
    });
  });
}
