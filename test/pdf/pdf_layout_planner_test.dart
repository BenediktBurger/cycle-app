// Unit tests of the PDF layout planner (lib/pdf/pdf_layout.dart): the pure
// (cycle -> pages) split behind the "at most 1 cycle per page" rule — a
// page-break mid-cycle is allowed (long cycles like a pregnancy span more
// than one page), but two cycles NEVER share a page.
import 'package:cycle_app/pdf/pdf_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('one cycle per page (small cycles)', () {
    test('a short cycle takes exactly one page', () {
      final plan = planCyclePages([10]);
      expect(plan.length, 1);
      expect(plan.single.cycleIndex, 0);
      expect(plan.single.pageIndexInCycle, 0);
      expect(plan.single.firstDayIndex, 0);
      expect(plan.single.dayCount, 10);
    });

    test('every cycle opens its own page — no page carries days of two '
        'cycles', () {
      // One, two and one page: 10-day, 40-day, 5-day cycles -> 4 pages,
      // in cycle order.
      final plan = planCyclePages([10, 40, 5], maxDaysPerPage: 30);
      expect(plan.length, 4);
      expect([for (final p in plan) p.cycleIndex], [0, 1, 1, 2]);
    });
  });

  group('long cycles span several pages', () {
    test('a pregnancy-style 120-day cycle breaks into four pages', () {
      final plan = planCyclePages([120], maxDaysPerPage: 30);
      expect(plan.length, 4);
      expect(plan.every((p) => p.cycleIndex == 0), isTrue);
      expect(plan.map((p) => p.dayCount).toList(), [30, 30, 30, 30]);
      expect(plan.map((p) => p.firstDayIndex).toList(), [0, 30, 60, 90]);
      expect(plan.map((p) => p.pageIndexInCycle).toList(), [0, 1, 2, 3]);
    });

    test('a remainder page takes only the trailing days', () {
      final plan = planCyclePages([45], maxDaysPerPage: 30);
      expect(plan.map((p) => p.dayCount).toList(), [30, 15]);
    });
  });

  group('windows cover every day exactly once, in order', () {
    test('coverage over mixed cycles', () {
      const counts = [12, 30, 90, 3];
      final plan = planCyclePages(counts, maxDaysPerPage: 25);
      // Total windows: 1 + 2 + 4 + 1 = 8.
      expect(plan.length, 8);
      // Coverage: each cycle's windows partition its days.
      var covered = 0;
      for (final p in plan) {
        expect(p.dayCount, greaterThan(0));
        expect(p.dayCount, lessThanOrEqualTo(25));
        covered += p.dayCount;
      }
      expect(covered, counts.reduce((a, b) => a + b));
      // Pages are ordered (cycle order, then page order within a cycle).
      for (var i = 1; i < plan.length; i++) {
        final previous = plan[i - 1];
        final current = plan[i];
        expect(previous.cycleIndex, lessThanOrEqualTo(current.cycleIndex));
        expect(
          previous.cycleIndex == current.cycleIndex,
          previous.pageIndexInCycle < current.pageIndexInCycle,
          reason: 'inside a cycle the page numbers grow strictly',
        );
      }
    });

    test('concatenated windows per cycle equal the day count', () {
      const counts = [28, 31];
      final plan = planCyclePages(counts, maxDaysPerPage: 30);
      for (var cycle = 0; cycle < counts.length; cycle++) {
        final days = plan
            .where((p) => p.cycleIndex == cycle)
            .fold(0, (sum, p) => sum + p.dayCount);
        expect(days, counts[cycle]);
      }
    });
  });

  group('defaults & guards', () {
    test('the default column budget is the paper sheet’s 40 day columns: a '
        '31-day cycle fits on ONE page', () {
      final plan = planCyclePages([31]);
      expect(
        plan.length,
        1,
        reason: 'defaultMaxDaysPerPage = 40: no continuation page needed',
      );
      expect(plan.single.dayCount, 31);
    });

    test('a 45-day cycle under the default budget: full page + remainder', () {
      final plan = planCyclePages([45]);
      expect(plan.map((p) => p.dayCount).toList(), [40, 5]);
      expect(plan.map((p) => p.firstDayIndex).toList(), [0, 40]);
      expect(plan.map((p) => p.pageIndexInCycle).toList(), [0, 1]);
    });

    test('a pregnancy-style 120-day cycle under the default budget '
        '(uniform continuation pages)', () {
      final plan = planCyclePages([120]);
      expect(plan.map((p) => p.dayCount).toList(), [40, 40, 40]);
      expect(plan.map((p) => p.firstDayIndex).toList(), [0, 40, 80]);
    });

    test('an empty cycle list yields no pages', () {
      expect(planCyclePages(const []), isEmpty);
    });

    test('a non-positive column budget is rejected', () {
      expect(
        () => planCyclePages([10], maxDaysPerPage: 0),
        throwsArgumentError,
      );
      expect(
        () => planCyclePages([10], maxDaysPerPage: -1),
        throwsArgumentError,
      );
    });
  });
}
