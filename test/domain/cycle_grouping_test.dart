// Domain tests: cycle grouping (boundaries between cycles).
// Pure Dart — imports only lib/domain, runs on the host VM.
//
// Boundary rule: cycle groups are MARK-driven. A user-placed cycleStart
// mark (CycleMarkTypes.cycleStart) opens a new cycle group; bleeding only
// SUGGESTS a cycle start (isSuggestedCycleStart — the prompt/derivation
// gate, never a boundary). The old automatic "first bleeding day starts a
// cycle" rule is superseded; bleeding sequences alone form ONE group.
//
// Suggestion semantics (owner decision 2026-09-18, temperature-only): the
// suppression is keyed PURELY on bleeding continuity — a day suggests iff
// bleeding >= 2 and the previous calendar day is not also bleeding >= 2.
// The ignoreTemperature mark is IRRELEVANT to the predicate (a marked day
// with menstruation-level bleeding suggests; a marked previous bleeding
// day suppresses like any other bleeding day). The predicate takes NO
// excluded-state parameters.

import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/domain/cycle_grouping.dart';
import 'package:cycle_app/domain/date_only.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';

import 'mark_fixtures.dart';

DailyEntry d(
  int year,
  int month,
  int day, {
  Bleeding bleeding = Bleeding.none,
  int tempDisturbances = 0,
}) {
  return DailyEntry(
    date: DateTime(year, month, day),
    bleeding: bleeding,
    tempDisturbances: tempDisturbances,
  );
}

// start: the shared domain mark fixture (mark_fixtures.dart).

/// A temperature-ignore mark on (year, month, day) — the ONLY analysis
/// signal the temperature evaluation consumes (raw disturbance flags are
/// rendering input; the mark does not affect cycle-start suggestions).
CycleMark ignoredDay(int year, int month, int day) => CycleMark(
      date: DateTime(year, month, day),
      type: CycleMarkTypes.ignoreTemperature,
    );

void main() {
  group('groupIntoCycles — cycleStart marks open the groups', () {
    test('a cycleStart mark opens a new group wherever it sits', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 3),
        d(2026, 3, 4),
        d(2026, 3, 5),
        d(2026, 3, 6),
      ];
      final marks = [start(2026, 3, 5)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(2));
      // The leading group (before the first mark) is NOT a menstruation
      // onset; the mark-opened group is.
      expect(cycles[0].startsAtMenstruation, isFalse);
      expect(cycles[0].startDate, DateTime(2026, 3, 1));
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3, 4]);
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 5));
      expect(cycles[1].days.map((e) => e.date.day), [5, 6]);
    });

    test('bleeding alone never opens a group — one group without marks', () {
      final entries = <DailyEntry>[
        // The old rule split at every menstruation-level onset (Mar 2,
        // Mar 30, Apr 27); under the mark-driven rule all of this is ONE
        // group unless the user places cycleStart marks.
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, bleeding: Bleeding.medium),
        d(2026, 3, 4),
        d(2026, 3, 30, bleeding: Bleeding.medium),
        d(2026, 4, 10, bleeding: Bleeding.spotting),
        d(2026, 4, 27, bleeding: Bleeding.medium),
        d(2026, 4, 28),
      ];

      final cycles = groupIntoCycles(entries, const []);

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isFalse,
          reason: 'no mark exists — the single group is the leading group');
      expect(cycles.single.startDate, DateTime(2026, 3, 2));
      expect(cycles.single.days, hasLength(7));
    });

    test(
        'a mark on an untracked gap day opens the group at the next '
        'tracked day (startsAtMenstruation == true)', () {
      final entries = [
        d(2026, 3, 1),
        // Mar 2–3: untracked gap days — the mark sits in the gap.
        d(2026, 3, 4),
        d(2026, 3, 5),
      ];
      final marks = [start(2026, 3, 3)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(2));
      expect(cycles[0].startsAtMenstruation, isFalse);
      expect(cycles[0].days.map((e) => e.date.day), [1]);
      expect(cycles[1].startsAtMenstruation, isTrue,
          reason: 'the group opened for the mark, at the next tracked day');
      expect(cycles[1].startDate, DateTime(2026, 3, 4));
      expect(cycles[1].days.map((e) => e.date.day), [4, 5]);
    });

    test(
        'a mark mid-cycle is authoritative wherever placed — including '
        'an excluded (interrupted) day', () {
      final entries = [
        d(2026, 3, 1, bleeding: Bleeding.medium),
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, bleeding: Bleeding.medium),
        // The mark sits on a TEMPERATURE-IGNORED day: the
        // ignoreTemperature mark is analysis input only (evaluation) and
        // never blocks the cycle-start mark (no interplay with grouping).
        d(2026, 3, 6, bleeding: Bleeding.medium),
        d(2026, 3, 7),
      ];
      final marks = [start(2026, 3, 6), ignoredDay(2026, 3, 6)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(2));
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3]);
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 6));
      expect(cycles[1].days.map((e) => e.date.day), [6, 7]);
    });

    test(
        'a mark on the first tracked day opens the first group itself '
        '(no leading group forms)', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2)];
      final marks = [start(2026, 3, 1)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isTrue);
      expect(cycles.single.startDate, DateTime(2026, 3, 1));
    });

    test('marks on or before the first tracked day open only ONE group', () {
      final entries = [
        d(2026, 3, 5),
        d(2026, 3, 6),
        d(2026, 3, 7),
        d(2026, 3, 8),
      ];
      final marks = [
        // Placed on untracked days before the recorded range — and
        // duplicates on the first tracked day itself: all of them open the
        // very first group, no group can start before it.
        start(2026, 2, 20),
        start(2026, 3, 1),
        start(2026, 3, 5),
        start(2026, 3, 5),
      ];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isTrue,
          reason: 'the first group opens for the earliest mark');
      expect(cycles.single.startDate, DateTime(2026, 3, 5));
    });

    test('two marks inside one untracked gap open ONE group', () {
      final entries = [
        d(2026, 3, 1),
        // Mar 2–4 untracked; two marks placed inside the gap.
        d(2026, 3, 5),
      ];
      final marks = [start(2026, 3, 3), start(2026, 3, 4)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(2));
      expect(cycles[1].startDate, DateTime(2026, 3, 5));
      expect(cycles[1].startsAtMenstruation, isTrue);
    });

    test('other mark types do not create boundaries', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2), d(2026, 3, 3)];
      final marks = [
        CycleMark(
            date: DateTime(2026, 3, 2), type: CycleMarkTypes.mucusPeakDay),
        CycleMark(
            date: DateTime(2026, 3, 3),
            type: CycleMarkTypes.firstHigherMeasurement),
        CycleMark(date: DateTime(2026, 3, 3), type: CycleMarkTypes.suzEvening),
      ];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isFalse);
    });

    // (The per-profile grouping tests are gone: there is no profile
    // dimension any more — marks key to days only.)

    test('empty entries produce no cycles, even with marks', () {
      expect(
          groupIntoCycles(const <DailyEntry>[], [start(2026, 3, 1)]), isEmpty);
      expect(
          groupIntoCycles(const <DailyEntry>[], const <CycleMark>[]), isEmpty);
    });

    test('unsorted input is sorted internally', () {
      final entries = [
        d(2026, 4, 10),
        d(2026, 3, 2),
        d(2026, 3, 5),
      ];
      final cycles = groupIntoCycles(entries, [start(2026, 3, 5)]);
      expect(cycles, hasLength(2));
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].startDate, DateTime(2026, 3, 5));
    });

    test('three mark-driven cycles split at their marks', () {
      final entries = [
        d(2026, 3, 2, bleeding: Bleeding.medium),
        d(2026, 3, 3, bleeding: Bleeding.medium),
        d(2026, 3, 4),
        d(2026, 3, 30, bleeding: Bleeding.medium),
        d(2026, 4, 10, bleeding: Bleeding.spotting),
        d(2026, 4, 27, bleeding: Bleeding.medium),
        d(2026, 4, 28),
      ];
      final marks = [
        start(2026, 3, 2),
        start(2026, 3, 30),
        start(2026, 4, 27),
      ];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(3));
      expect(cycles.map((c) => c.startsAtMenstruation), everyElement(isTrue));
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].startDate, DateTime(2026, 3, 30));
      expect(cycles[2].startDate, DateTime(2026, 4, 27));
      expect(
        cycles[0].days.map((e) => e.date.day).toList(),
        [2, 3, 4],
      );
      expect(
        cycles[1].days.map((e) => (e.bleeding, e.date.day)).toList(),
        const [(Bleeding.medium, 30), (Bleeding.spotting, 10)],
      );
      expect(cycles[2].days, hasLength(2));
    });
  });

  group('menstruationOnsetDates — the mark-driven cycle starts', () {
    test('returns the start dates of all mark-opened groups', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 5),
        d(2026, 3, 30),
      ];
      final marks = [start(2026, 3, 5), start(2026, 3, 30)];

      // Onsets are UTC-normalized (DST-immune day arithmetic), so compare
      // against normalized expectations.
      expect(
        menstruationOnsetDates(entries, marks),
        [
          DateOnly.normalize(DateTime(2026, 3, 5)),
          DateOnly.normalize(DateTime(2026, 3, 30)),
        ],
      );
    });

    test('a mark on an untracked day contributes the next tracked day', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 4)];
      final marks = [start(2026, 3, 3)];

      expect(
        menstruationOnsetDates(entries, marks),
        [DateOnly.normalize(DateTime(2026, 3, 4))],
      );
    });

    test('no marks → no onsets (bleeding alone does not count)', () {
      final entries = [d(2026, 3, 2, bleeding: Bleeding.medium), d(2026, 3, 3)];
      expect(menstruationOnsetDates(entries, const []), isEmpty);
      expect(menstruationOnsetDates(const [], const []), isEmpty);
    });
  });

  group(
      'isSuggestedCycleStart — the bleeding suggestion predicate '
      '(characterization: the old automatic rule, demoted to a suggestion '
      'gate)', () {
    test('a menstruation-level day after a non-bleeding day suggests', () {
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 1);

      expect(
        isSuggestedCycleStart(entry, previous),
        isTrue,
      );
    });

    test('a first entry with no previous day suggests', () {
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      expect(
        isSuggestedCycleStart(entry, null),
        isTrue,
      );
    });

    test('a data gap (previous day untracked) lets the day suggest', () {
      // previous is from an earlier day, not the previous calendar day —
      // an absent previous day cannot be proven non-menstruating.
      final entry = d(2026, 3, 10, bleeding: Bleeding.heavy);
      final previous = d(2026, 3, 1);

      expect(
        isSuggestedCycleStart(entry, previous),
        isTrue,
      );
    });

    test(
        'a mid-flow day does not suggest (previous day also bleeding '
        'level >= 2)', () {
      final entry = d(2026, 3, 3, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 2, bleeding: Bleeding.heavy);

      expect(
        isSuggestedCycleStart(entry, previous),
        isFalse,
      );
    });

    test('spotting (level 1) never suggests', () {
      final entry = d(2026, 3, 2, bleeding: Bleeding.spotting);
      expect(isSuggestedCycleStart(entry, null), isFalse);
    });

    test('raw disturbance flags never reach the suggestion predicate', () {
      // The predicate reads bleeding continuity only: raw disturbance
      // flags (isInterrupted) and the ignoreTemperature mark are both
      // invisible to it — a flagged, menstruation-level day suggests.
      final entry = d(
        2026,
        3,
        2,
        bleeding: Bleeding.medium,
        tempDisturbances: TempDisturbance.kr.bit | TempDisturbance.sp.bit,
      );
      expect(isSuggestedCycleStart(entry, null), isTrue,
          reason: 'raw flags are rendering input only');
    });

    test('a marked (ignored) day with bleeding >= 2 DOES suggest', () {
      // The ignoreTemperature mark is analysis-scoped (evaluation) and
      // never touches the suggestion: a marked menstruation-level day is
      // as good a cycle-start suggestion as any other.
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      expect(
        isSuggestedCycleStart(entry, null),
        isTrue,
        reason: 'marks are irrelevant to the predicate — the suppression '
            'is keyed purely on bleeding continuity',
      );
    });

    test('a previous bleeding day suppresses REGARDLESS of its mark', () {
      // Bleeding continuity is the only suppression: a previous calendar
      // day at bleeding level >= 2 proves a continuous menstruation, mark
      // or no mark.
      final entry = d(2026, 3, 3, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 2, bleeding: Bleeding.medium);

      expect(isSuggestedCycleStart(entry, previous), isFalse,
          reason: 'mid-flow: the previous day bleeds, marks are irrelevant');
    });

    test('light (level 2) suggests like any menstruation level', () {
      expect(
        isSuggestedCycleStart(
            d(2026, 3, 2, bleeding: Bleeding.light), d(2026, 3, 1)),
        isTrue,
      );
    });
  });
}
