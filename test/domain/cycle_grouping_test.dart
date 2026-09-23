// Domain tests: cycle grouping (boundaries between cycles).
// Pure Dart — imports only lib/domain, runs on the host VM.
//
// Boundary rule: cycle groups are MARK-driven. A user-placed cycleStart
// mark (CycleMarkTypes.cycleStart) opens a new cycle group; bleeding only
// SUGGESTS a cycle start (isSuggestedCycleStart — the prompt/derivation
// gate, never a boundary). The old automatic "first bleeding day starts a
// cycle" rule is superseded; bleeding sequences alone form ONE group.
//
// Span rule (owner requirement, app-wide): a cycle runs on UNTIL the next
// cycle-start mark, regardless whether data exists there. Grouping extends
// every cycle's day list with data-less placeholder entries out to
// (a) the day BEFORE the next cycleStart mark (leading + interior cycles)
// and (b) for the LAST cycle to max(last tracked day of the whole data
// set, today) — at least cycle day one can always be printed. A mark with
// no tracked day on/after it (e.g. placed just today) still opens a
// data-less cycle AT the mark day. Untracked days BETWEEN a cycle's own
// tracked days stay out of the list (the gap-day drop-out convention).
// The "today" of the last-cycle rule is injectable (tests pin a date;
// production uses the wall clock / nowProvider at the call sites).
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

/// Matches a data-less span-extension placeholder day: no temperature, no
/// bleeding, no observation of any kind.
final hasNoData = isA<DailyEntry>()
    .having((e) => e.bbtC, 'bbtC', isNull)
    .having((e) => e.bleeding, 'bleeding', Bleeding.none)
    .having((e) => e.mucusSign, 'mucusSign', isNull);

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

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 8),
      );

      expect(cycles, hasLength(2));
      // The leading group (before the first mark) is NOT a menstruation
      // onset; the mark-opened group is.
      expect(cycles[0].startsAtMenstruation, isFalse);
      expect(cycles[0].startDate, DateTime(2026, 3, 1));
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3, 4]);
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 5));
      // The cycle runs on to the pinned today: the tracked Mar 5–6 plus
      // the data-less Mar 7–8 extension days.
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 8)));
      expect(cycles[1].days.map((e) => e.date.day), [5, 6, 7, 8]);
      // The extension days carry NO data.
      expect(cycles[1].days.last.bbtC, isNull);
      expect(cycles[1].days.last.bleeding, Bleeding.none);
    });

    test('an interior cycle extends to the day before the NEXT start mark '
        '(today-independent)', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 3),
        d(2026, 3, 10),
        d(2026, 3, 11),
      ];
      final marks = [start(2026, 3, 1), start(2026, 3, 10)];

      final cycles = groupIntoCycles(entries, marks);

      // The first cycle runs Mar 1..Mar 9 — its tracked days Mar 1–3 plus
      // data-less Mar 4–9, because the next cycle-start mark is Mar 10.
      expect(cycles, hasLength(2));
      expect(cycles[0].startDate, DateTime(2026, 3, 1));
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 9)));
      expect(cycles[0].days.map((e) => e.date.day), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
      for (final entry in cycles[0].days.skip(3)) {
        expect(entry.bbtC, isNull, reason: 'an extension day carries no data');
        expect(entry.bleeding, Bleeding.none);
      }
    });

    test('untracked days BETWEEN a cycle\'s own tracked days stay out of '
        'the day list (the gap-day convention)', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 5),
        d(2026, 3, 10),
      ];
      final marks = [start(2026, 3, 1), start(2026, 3, 10)];

      final cycles = groupIntoCycles(entries, marks);

      // The interior gap Mar 3–4 is NOT backfilled; starting at the cycle's
      // last tracked day (Mar 5), the extension fills Mar 6–9.
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 5, 6, 7, 8, 9]);
    });

    test('the leading group extends to the day before the first mark', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 3),
        d(2026, 3, 7),
      ];
      final marks = [start(2026, 3, 7)];

      final cycles = groupIntoCycles(entries, marks);

      expect(cycles, hasLength(2));
      expect(cycles[0].startsAtMenstruation, isFalse);
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3, 4, 5, 6]);
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 6)));
      expect(cycles[1].startDate, DateTime(2026, 3, 7));
      expect(cycles[1].startsAtMenstruation, isTrue);
    });

    test('without marks the single group runs on to today (the last-cycle '
        'rule applies to the leading group too)', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2), d(2026, 3, 3)];

      final cycles = groupIntoCycles(
        entries,
        const [],
        today: DateTime(2026, 3, 9),
      );

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isFalse);
      expect(cycles.single.endDate, DateOnly.normalize(DateTime(2026, 3, 9)));
      expect(cycles.single.days, hasLength(9));
    });

    test('the LAST cycle extends to the last tracked day of the WHOLE data '
        'set or today — whichever is later (injectable clock)', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 3),
        d(2026, 3, 10),
        d(2026, 3, 11),
      ];
      final marks = [start(2026, 3, 1), start(2026, 3, 10)];

      // Today after the last tracked day: the cycle runs on to today.
      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 15),
      );
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 15)));
      expect(cycles[1].days, hasLength(6));

      // The clock behind the data (raw last tracked wins, no retraction).
      final cyclesPinned = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 9),
      );
      // The raw last tracked day wins — same CYCLE DAY as the expectation;
      // endDate carries the entry's own (non-extended) date object.
      expect(
        DateOnly.sameDay(cyclesPinned[1].endDate, DateTime(2026, 3, 11)),
        isTrue,
      );
      expect(cyclesPinned[1].days, hasLength(2));
    });

    test('a mark with NO tracked day on/after it still opens a data-less '
        'cycle at the mark day ("just created the cycle mark")', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2), d(2026, 3, 3)];
      final marks = [start(2026, 3, 1), start(2026, 3, 20)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 22),
      );

      // The old data set up to Mar 19 (extension), then the fresh,
      // data-less cycle Mar 20..Mar 22 — its cycle day 1 prints.
      expect(cycles, hasLength(2));
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 19)));
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateOnly.normalize(DateTime(2026, 3, 20)));
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 22)));
      expect(cycles[1].days.map((e) => e.date.day), [20, 21, 22]);
      for (final entry in cycles[1].days) {
        expect(entry.bbtC, isNull);
        expect(entry.bleeding, Bleeding.none);
      }
    });

    test('several marks beyond the data open consecutive data-less cycles', () {
      final entries = [d(2026, 3, 1)];
      final marks = [start(2026, 3, 1), start(2026, 3, 20), start(2026, 3, 25)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 30),
      );

      expect(cycles, hasLength(3));
      expect(cycles[1].startDate, DateOnly.normalize(DateTime(2026, 3, 20)));
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 24)));
      expect(cycles[2].startDate, DateOnly.normalize(DateTime(2026, 3, 25)));
      expect(cycles[2].endDate, DateOnly.normalize(DateTime(2026, 3, 30)));
      expect(cycles[1].days, everyElement(hasNoData));
    });

    test('the fresh-mark cycle never retracts below its start (clock behind '
        'the mark)', () {
      final entries = [d(2026, 3, 1)];
      final marks = [start(2026, 3, 1), start(2026, 3, 20)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 15),
      );

      // today (Mar 15) is behind the mark: end clamps to the start itself.
      expect(cycles[1].days, hasLength(1));
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 20)));
    });

    test('back-to-back start marks keep adjacent one-day spans apart', () {
      final entries = [
        d(2026, 3, 1),
        d(2026, 3, 2),
        d(2026, 3, 3),
        d(2026, 3, 4),
      ];
      final marks = [start(2026, 3, 1), start(2026, 3, 2)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 6),
      );

      // Cycle 1 ends the day before the next start mark — here its own
      // tracked day (no extension to add); same CYCLE DAY for sure (the
      // unextended endDate carries the entry's own date object).
      expect(cycles, hasLength(2));
      expect(cycles[0].startDate, DateTime(2026, 3, 1));
      expect(DateOnly.sameDay(cycles[0].endDate, DateTime(2026, 3, 1)), isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 6)));
      expect(cycles[1].days.map((e) => e.date.day), [2, 3, 4, 5, 6]);
    });

    test('start-day marks stay merged: a mark on/before the first tracked '
        'day opens the first group once, then the fresh-mark rule applies', () {
      final entries = [
        d(2026, 3, 5),
        d(2026, 3, 6),
        d(2026, 3, 7),
        d(2026, 3, 8),
      ];
      final marks = [start(2026, 2, 20), start(2026, 3, 1)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 9),
      );

      // Both pre-range marks open the SAME group (no tracked day between
      // them separates two cycles) at the first tracked day; the NEWEST
      // one (Mar 1) is the anchor — its own date is the cycle start, an
      // untracked day before the first tracked day.
      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isTrue);
      expect(cycles.single.startDate, DateTime(2026, 3, 1));
      expect(cycles.single.endDate, DateOnly.normalize(DateTime(2026, 3, 9)));
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

      final cycles = groupIntoCycles(
        entries,
        const [],
        today: DateTime(2026, 5, 1),
      );

      expect(cycles, hasLength(1));
      expect(
        cycles.single.startsAtMenstruation,
        isFalse,
        reason: 'no mark exists — the single group is the leading group',
      );
      expect(cycles.single.startDate, DateTime(2026, 3, 2));
      // The single (last) cycle runs on to the pinned today: the seven
      // tracked days plus Mar.../Apr 29 - May 1 extension days.
      expect(cycles.single.days, hasLength(10));
    });

    test('a mark on an untracked gap day anchors the start on the mark '
        'date itself (gap days belong to the new cycle)', () {
      final entries = [
        d(2026, 3, 1),
        // Mar 2–3: untracked gap days — the mark sits in the gap.
        d(2026, 3, 4),
        d(2026, 3, 5),
      ];
      final marks = [start(2026, 3, 3)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 9),
      );

      expect(cycles, hasLength(2));
      expect(cycles[0].startsAtMenstruation, isFalse);
      // The leading group extends to the day before the mark (Mar 2 as a
      // data-less extension day).
      expect(cycles[0].days.map((e) => e.date.day), [1, 2]);
      expect(
        cycles[1].startsAtMenstruation,
        isTrue,
        reason: 'the group opened for the mark',
      );
      // The start date is the MARK's own date — an untracked day — so the
      // distance between the two marks equals the cycle length.
      expect(cycles[1].startDate, DateTime(2026, 3, 3));
      expect(
        cycles[1].days.map((e) => e.date.day),
        [4, 5, 6, 7, 8, 9],
        reason:
            'tracked days plus the span extension out to the pinned '
            'today — days in the gap are not member days',
      );
      expect(
        cycles[1].days.map((e) => e.date.day),
        isNot(contains(3)),
        reason: 'startDate lies on an untracked gap day — not a member day',
      );
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 3, 9)));
    });

    test('a mark mid-cycle is authoritative wherever placed — including '
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

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 9),
      );

      expect(cycles, hasLength(2));
      // The leading group extends across the untracked Mar 4–5 to the day
      // before the mark.
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3, 4, 5]);
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].startDate, DateTime(2026, 3, 6));
      expect(cycles[1].days.map((e) => e.date.day), [6, 7, 8, 9]);
    });

    test('a mark on the first tracked day opens the first group itself '
        '(no leading group forms)', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2)];
      final marks = [start(2026, 3, 1)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 4),
      );

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isTrue);
      expect(cycles.single.startDate, DateTime(2026, 3, 1));
      expect(cycles.single.endDate, DateOnly.normalize(DateTime(2026, 3, 4)));
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

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 10),
      );

      expect(cycles, hasLength(1));
      expect(
        cycles.single.startsAtMenstruation,
        isTrue,
        reason: 'the first group opens for the earliest mark',
      );
      expect(cycles.single.startDate, DateTime(2026, 3, 5));
      expect(cycles.single.endDate, DateOnly.normalize(DateTime(2026, 3, 10)));
    });

    test('two marks inside one untracked gap open ONE group — the newest '
        'mark anchors the start', () {
      final entries = [
        d(2026, 3, 1),
        // Mar 2–4 untracked; two marks placed inside the gap.
        d(2026, 3, 5),
      ];
      final marks = [start(2026, 3, 3), start(2026, 3, 4)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 8),
      );

      expect(cycles, hasLength(2));
      // The newer (re-marked) start supersedes the older one — the anchor
      // rule of the mark sheet applies to the opening batch as well; the
      // superseded earlier mark hands its day (Mar 3) to the leading group
      // as a data-less span-extension day.
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3]);
      expect(cycles[1].startDate, DateTime(2026, 3, 4));
      expect(cycles[1].startsAtMenstruation, isTrue);
      expect(cycles[1].days.map((e) => e.date.day), [5, 6, 7, 8]);
    });

    test('other mark types do not create boundaries', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 2), d(2026, 3, 3)];
      final marks = [
        CycleMark(
          date: DateTime(2026, 3, 2),
          type: CycleMarkTypes.mucusPeakDay,
        ),
        CycleMark(
          date: DateTime(2026, 3, 3),
          type: CycleMarkTypes.firstHigherMeasurement,
        ),
        CycleMark(date: DateTime(2026, 3, 3), type: CycleMarkTypes.suzEvening),
      ];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 3, 5),
      );

      expect(cycles, hasLength(1));
      expect(cycles.single.startsAtMenstruation, isFalse);
      // The single (last) cycle runs on to the pinned today.
      expect(cycles.single.days, hasLength(5));
    });

    // (The per-profile grouping tests are gone: there is no profile
    // dimension any more — marks key to days only.)

    test('no entries and no marks produce no cycles', () {
      expect(
        groupIntoCycles(const <DailyEntry>[], const <CycleMark>[]),
        isEmpty,
      );
    });

    test('a mark without any tracked data still opens data-less cycles '
        '(entries empty)', () {
      // The "user just created the cycle mark" corner: no data exists at
      // all, but the placed cycleStart mark opens its cycle — at least
      // cycle day 1 can be printed. Two marks: two consecutive cycles.
      final cycles = groupIntoCycles(const <DailyEntry>[], [
        start(2026, 3, 1),
        start(2026, 3, 5),
      ], today: DateTime(2026, 3, 3));

      expect(cycles, hasLength(2));
      expect(cycles[0].startDate, DateOnly.normalize(DateTime(2026, 3, 1)));
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 4)));
      expect(cycles[0].days.map((e) => e.date.day), [1, 2, 3, 4]);
      expect(cycles[0].days, everyElement(hasNoData));
      expect(cycles[1].startDate, DateOnly.normalize(DateTime(2026, 3, 5)));
      // today (Mar 3) is behind the second mark: end clamps to the start.
      expect(cycles[1].days.map((e) => e.date.day), [5]);
      expect(
        cycles.every((c) => c.startsAtMenstruation),
        isTrue,
        reason: 'both cycles opened at a mark',
      );
    });

    test('unsorted input is sorted internally', () {
      final entries = [d(2026, 4, 10), d(2026, 3, 2), d(2026, 3, 5)];
      final cycles = groupIntoCycles(entries, [
        start(2026, 3, 5),
      ], today: DateTime(2026, 3, 7));
      expect(cycles, hasLength(2));
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 4)));
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
      final marks = [start(2026, 3, 2), start(2026, 3, 30), start(2026, 4, 27)];

      final cycles = groupIntoCycles(
        entries,
        marks,
        today: DateTime(2026, 4, 30),
      );

      expect(cycles, hasLength(3));
      expect(cycles.map((c) => c.startsAtMenstruation), everyElement(isTrue));
      expect(cycles[0].startDate, DateTime(2026, 3, 2));
      expect(cycles[1].startDate, DateTime(2026, 3, 30));
      expect(cycles[2].startDate, DateTime(2026, 4, 27));
      // Every interior cycle runs to the day before its next start mark;
      // the last runs to the pinned today.
      expect(cycles[0].endDate, DateOnly.normalize(DateTime(2026, 3, 29)));
      expect(cycles[0].days, hasLength(28));
      expect(cycles[1].endDate, DateOnly.normalize(DateTime(2026, 4, 26)));
      expect(cycles[2].endDate, DateOnly.normalize(DateTime(2026, 4, 30)));
      // The tracked bleeding observations survive inside the extended day
      // lists (extension days carry nothing).
      expect(
        cycles[0].days,
        containsAll(<Matcher>[
          isA<DailyEntry>().having(
            (e) => e.bleeding,
            'bleeding',
            Bleeding.medium,
          ),
        ]),
      );
      final cycle2Bleeding = [
        for (final e in cycles[1].days)
          if (e.bleeding != Bleeding.none) e,
      ];
      expect(cycle2Bleeding.map((e) => (e.bleeding, e.date.day)), [
        (Bleeding.medium, 30),
        (Bleeding.spotting, 10),
      ]);
    });
  });

  group('menstruationOnsetDates — the mark-driven cycle starts', () {
    test('returns the start dates of all mark-opened groups', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 5), d(2026, 3, 30)];
      final marks = [start(2026, 3, 5), start(2026, 3, 30)];

      // Onsets are UTC-normalized (DST-immune day arithmetic), so compare
      // against normalized expectations.
      expect(menstruationOnsetDates(entries, marks), [
        DateOnly.normalize(DateTime(2026, 3, 5)),
        DateOnly.normalize(DateTime(2026, 3, 30)),
      ]);
    });

    test('a mark on an untracked day anchors the onset on the mark date '
        'itself', () {
      final entries = [d(2026, 3, 1), d(2026, 3, 4)];
      final marks = [start(2026, 3, 3)];

      expect(menstruationOnsetDates(entries, marks), [
        DateOnly.normalize(DateTime(2026, 3, 3)),
      ]);
    });

    test('no marks → no onsets (bleeding alone does not count)', () {
      final entries = [d(2026, 3, 2, bleeding: Bleeding.medium), d(2026, 3, 3)];
      expect(menstruationOnsetDates(entries, const []), isEmpty);
      expect(menstruationOnsetDates(const [], const []), isEmpty);
    });
  });

  group('isSuggestedCycleStart — the bleeding suggestion predicate '
      '(characterization: the old automatic rule, demoted to a suggestion '
      'gate)', () {
    test('a menstruation-level day after a non-bleeding day suggests', () {
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 1);

      expect(isSuggestedCycleStart(entry, previous), isTrue);
    });

    test('a first entry with no previous day suggests', () {
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      expect(isSuggestedCycleStart(entry, null), isTrue);
    });

    test('a data gap (previous day untracked) lets the day suggest', () {
      // previous is from an earlier day, not the previous calendar day —
      // an absent previous day cannot be proven non-menstruating.
      final entry = d(2026, 3, 10, bleeding: Bleeding.heavy);
      final previous = d(2026, 3, 1);

      expect(isSuggestedCycleStart(entry, previous), isTrue);
    });

    test('a mid-flow day does not suggest (previous day also bleeding '
        'level >= 2)', () {
      final entry = d(2026, 3, 3, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 2, bleeding: Bleeding.heavy);

      expect(isSuggestedCycleStart(entry, previous), isFalse);
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
      expect(
        isSuggestedCycleStart(entry, null),
        isTrue,
        reason: 'raw flags are rendering input only',
      );
    });

    test('a marked (ignored) day with bleeding >= 2 DOES suggest', () {
      // The ignoreTemperature mark is analysis-scoped (evaluation) and
      // never touches the suggestion: a marked menstruation-level day is
      // as good a cycle-start suggestion as any other.
      final entry = d(2026, 3, 2, bleeding: Bleeding.medium);
      expect(
        isSuggestedCycleStart(entry, null),
        isTrue,
        reason:
            'marks are irrelevant to the predicate — the suppression '
            'is keyed purely on bleeding continuity',
      );
    });

    test('a previous bleeding day suppresses REGARDLESS of its mark', () {
      // Bleeding continuity is the only suppression: a previous calendar
      // day at bleeding level >= 2 proves a continuous menstruation, mark
      // or no mark.
      final entry = d(2026, 3, 3, bleeding: Bleeding.medium);
      final previous = d(2026, 3, 2, bleeding: Bleeding.medium);

      expect(
        isSuggestedCycleStart(entry, previous),
        isFalse,
        reason: 'mid-flow: the previous day bleeds, marks are irrelevant',
      );
    });

    test('light (level 2) suggests like any menstruation level', () {
      expect(
        isSuggestedCycleStart(
          d(2026, 3, 2, bleeding: Bleeding.light),
          d(2026, 3, 1),
        ),
        isTrue,
      );
    });
  });
}
