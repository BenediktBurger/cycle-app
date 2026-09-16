// Unit tests of the pure curve-structure helpers (lib/ui/cycle_curve.dart):
// adjacent-day connectivity runs and lighter-rendering of interrupted
// (excluded) temperatures — the rule set the temperature chart draws by.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// Entry for chart day index [i] (2026-09-03 = index 0); the helpers are
/// day-index driven, so dates only provide the calendar offset.
DailyEntry _entry(int i, {double? bbt, bool excluded = false}) => DailyEntry(
      date: DateTime.utc(2026, 9, 3).add(Duration(days: i)),
      bbtC: bbt,
      excludeIllness: excluded,
    );

void main() {
  group('curveRuns — adjacent-day connectivity', () {
    test('adjacent measured days join into one run', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        1: _entry(1, bbt: 36.6),
        2: _entry(2, bbt: 36.7),
      });
      expect(runs, hasLength(1));
      expect([for (final p in runs.single.points) p.dayIndex], [0, 1, 2]);
    });

    test('a temperatureless day (entry without bbtC) breaks the run', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        // day 1: entry exists, but no temperature measured
        1: DailyEntry(
            date: DateTime.utc(2026, 9, 4), bleeding: Bleeding.medium),
        2: _entry(2, bbt: 36.7),
        3: _entry(3, bbt: 36.8),
      });
      expect(runs, hasLength(2));
      expect(runs[0].points.single.dayIndex, 0);
      expect([for (final p in runs[1].points) p.dayIndex], [2, 3]);
    });

    test('a fully missing day breaks the run the same way', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        2: _entry(2, bbt: 36.7),
      });
      expect(runs, hasLength(2));
      for (final run in runs) {
        expect(run.points, hasLength(1));
      }
    });

    test('excluded temperatures count as measured days for connectivity', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        1: _entry(1, bbt: 36.4, excluded: true),
        2: _entry(2, bbt: 36.7),
      });
      expect(runs, hasLength(1));
      expect(runs.single.points[1].excluded, isTrue);
      expect(runs.single.points[0].excluded, isFalse);
    });

    test('unordered day indexes still produce the sorted run', () {
      final runs = curveRuns({
        2: _entry(2, bbt: 36.7),
        0: _entry(0, bbt: 36.5),
        1: _entry(1, bbt: 36.6),
      });
      expect(runs, hasLength(1));
      expect([for (final p in runs.single.points) p.dayIndex], [0, 1, 2]);
    });

    test('empty input yields no runs', () {
      expect(curveRuns(const {}), isEmpty);
    });
  });

  group('curveSegments — lighter rendering of interrupted segments', () {
    test('segments only exist between adjacent run points', () {
      final segments = curveSegments([
        const CurveRun([
          CurvePoint(dayIndex: 0, bbtC: 36.5, excluded: false),
          CurvePoint(dayIndex: 1, bbtC: 36.6, excluded: false),
          CurvePoint(dayIndex: 2, bbtC: 36.7, excluded: false),
        ]),
      ]);
      expect(segments.map((s) => s.a.dayIndex), [0, 1]);
      expect(segments.map((s) => s.b.dayIndex), [1, 2]);
    });

    test('a segment touching an interrupted day is lighter', () {
      final segments = curveSegments([
        const CurveRun([
          CurvePoint(dayIndex: 0, bbtC: 36.5, excluded: false),
          CurvePoint(dayIndex: 1, bbtC: 36.4, excluded: true),
          CurvePoint(dayIndex: 2, bbtC: 36.7, excluded: false),
        ]),
      ]);
      // Both segments touch the interrupted day 1.
      expect(segments.map((s) => s.lighter), everyElement(isTrue));
    });
  });

  group('interrupted semantics at the boundary', () {
    test('interrupted day WITHOUT temperature just breaks the run', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        1: _entry(1, excluded: true), // interrupted, but no measurement
        2: _entry(2, bbt: 36.7),
      });
      expect(runs, hasLength(2));
      expect(runs.map((r) => r.points.single.dayIndex), [0, 2]);
    });
  });
}
