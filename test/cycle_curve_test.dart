// Unit tests of the pure curve-structure helpers (lib/ui/cycle_curve.dart):
// adjacent-day connectivity runs and lighter-rendering of ignored
// temperatures — the rule set the temperature chart draws by. The
// interruption flag comes from the IGNORED-DAY-INDEX set passed to
// curveRuns: the set is computed by the chart from the ignoreTemperature
// marks (owner decision 2026-09-19 — the MARK is the rendering key, not
// the raw tempDisturbances mask). A flagged day whose mark was removed
// renders normally; a marked day without flags renders lighter.
//
// The display-range group pins the owner-decided CLIP rule: curve values
// outside the chart's fixed settings range (default 36–38 °C) are clamped
// to exactly the boundary at the data layer — the scale never stretches
// to fit an outlier.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/ui/cycle_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// Entry for chart day index [i] (2026-09-03 = index 0); the helpers are
/// day-index driven, so dates only provide the calendar offset.
/// [flagged] sets the raw disturbance mask (rendering-irrelevant since the
/// mark keying — kept here to prove the mask no longer drives the flag).
DailyEntry _entry(int i, {double? bbt, bool flagged = false}) => DailyEntry(
      date: DateTime.utc(2026, 9, 3).add(Duration(days: i)),
      bbtC: bbt,
      tempDisturbances: flagged ? TempDisturbance.kr.bit : 0,
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

    test(
        'ignored (marked) temperatures count as measured days '
        'for connectivity', () {
      final runs = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 36.4),
          2: _entry(2, bbt: 36.7),
        },
        ignoredDayIndexes: {1},
      );
      expect(runs, hasLength(1));
      expect(runs.single.points[1].excluded, isTrue,
          reason: 'the day index in the ignored set drives the flag');
      expect(runs.single.points[0].excluded, isFalse);
    });

    test(
        'the ignored-day-index set decides the flag — the raw mask does '
        'not', () {
      // HEADLINE new behavior: a marked day WITHOUT flags renders lighter.
      final markedUnflagged = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 36.4), // no tempDisturbances at all
          2: _entry(2, bbt: 36.7),
        },
        ignoredDayIndexes: {1},
      );
      expect(markedUnflagged.single.points[1].excluded, isTrue,
          reason: 'the mark (via the ignored-day-index set) is the '
              'rendering key — flags are not needed');

      // THE FLIP: a flagged day NOT in the ignored set renders normally
      // (the user removed the mark — the curve shows the owned state).
      final flaggedUnmarked = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 36.4, flagged: true), // flags WITHOUT the mark
          2: _entry(2, bbt: 36.7),
        },
      );
      expect(flaggedUnmarked.single.points[1].excluded, isFalse,
          reason: 'raw flags are no longer a rendering input');

      // Marked AND flagged (the typical manually excluded day): lighter.
      final markedAndFlagged = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 36.4, flagged: true),
          2: _entry(2, bbt: 36.7),
        },
        ignoredDayIndexes: {1},
      );
      expect(markedAndFlagged.single.points[1].excluded, isTrue,
          reason: 'the mark keying makes the flagged+marked day lighter');
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
    test(
        'an ignored day WITHOUT temperature just breaks the run '
        '(marks cannot bridge a measurement gap)', () {
      final runs = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1), // day index in the ignored set, but no measurement
          2: _entry(2, bbt: 36.7),
        },
        ignoredDayIndexes: {1},
      );
      expect(runs, hasLength(2));
      expect(runs.map((r) => r.points.single.dayIndex), [0, 2]);
    });
  });

  group('display-range clipping (clip, never rescale)', () {
    const defaultRange = TemperatureRange(min: 36.0, max: 38.0);

    CurvePoint pointIn(Map<int, double> temps,
        {TemperatureRange? displayRange}) {
      final entries = {
        for (final MapEntry(:key, :value) in temps.entries)
          key: _entry(key, bbt: value),
      };
      final runs = curveRuns(entries, displayRange: displayRange);
      return [
        for (final run in runs)
          for (final point in run.points) point,
      ].single;
    }

    test('a temperature above the range clips to exactly the upper boundary',
        () {
      final point = pointIn({0: 39.5}, displayRange: defaultRange);
      expect(point.bbtC, 38.0,
          reason: 'a fever value renders AT maxY, not beyond the plot');
    });

    test('a temperature below the range clips to exactly the lower boundary',
        () {
      final point = pointIn({0: 35.2}, displayRange: defaultRange);
      expect(point.bbtC, 36.0, reason: 'a low value renders AT minY');
    });

    test('a value exactly at a boundary passes through unchanged', () {
      expect(pointIn({0: 38.0}, displayRange: defaultRange).bbtC, 38.0,
          reason: 'clamp at the boundary must return the value itself');
      expect(pointIn({0: 36.0}, displayRange: defaultRange).bbtC, 36.0,
          reason: 'clamp at the lower boundary must return the value itself');
    });

    test('in-range values pass through unchanged', () {
      expect(pointIn({0: 36.5}, displayRange: defaultRange).bbtC, 36.5);
      expect(pointIn({0: 37.85}, displayRange: defaultRange).bbtC, 37.85);
    });

    test(
        'a run with an out-of-range day stays connected (clipping does '
        'not break adjacency)', () {
      final runs = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 40.1),
          2: _entry(2, bbt: 36.7),
        },
        displayRange: defaultRange,
      );
      expect(runs, hasLength(1), reason: 'adjacency is untouched by the clip');
      expect([for (final p in runs.single.points) p.bbtC], [36.5, 38.0, 36.7]);
    });

    test('the pure helper clamps independently of runs', () {
      expect(clampBbtC(39.5, defaultRange), 38.0);
      expect(clampBbtC(35.4, defaultRange), 36.0);
      expect(clampBbtC(36.8, defaultRange), 36.8);
    });

    test(
        'without a display range the raw values pass through (the chart '
        'always passes one — the default keeps historical callers honest)', () {
      expect(pointIn({0: 39.5}).bbtC, 39.5);
    });
  });
}
