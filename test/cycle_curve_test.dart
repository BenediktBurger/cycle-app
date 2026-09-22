// Unit tests of the pure curve-structure helpers (lib/ui/cycle_curve.dart):
// adjacent-day connectivity runs and lighter-rendering of ignored
// temperatures — the rule set the temperature chart draws by. The
// interruption flag comes from the IGNORED-DAY-INDEX set passed to
// curveRuns: the set is computed by the chart from the ignoreTemperature
// marks (owner decision 2026-09-19 — the MARK is the rendering key, not
// the raw tempDisturbances mask). A flagged day whose mark was removed
// renders normally; a marked day without flags renders lighter.
//
// The visible-range groups pin the new split of responsibilities: curveRuns
// keeps every point's RAW measured value (an out-of-range reading is NOT
// rewritten at the data layer), while visibleCurveSegments derives the
// drawable clipped spans the chart actually draws — a straight segment is
// reduced to what lies inside the settings range (default 36–38 °C),
// dropping everything outside. A measurement exactly AT a boundary counts
// as in range.
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
          date: DateTime.utc(2026, 9, 4),
          bleeding: Bleeding.medium,
        ),
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

    test('ignored (marked) temperatures count as measured days '
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
      expect(
        runs.single.points[1].excluded,
        isTrue,
        reason: 'the day index in the ignored set drives the flag',
      );
      expect(runs.single.points[0].excluded, isFalse);
    });

    test('the ignored-day-index set decides the flag — the raw mask does '
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
      expect(
        markedUnflagged.single.points[1].excluded,
        isTrue,
        reason:
            'the mark (via the ignored-day-index set) is the '
            'rendering key — flags are not needed',
      );

      // THE FLIP: a flagged day NOT in the ignored set renders normally
      // (the user removed the mark — the curve shows the owned state).
      final flaggedUnmarked = curveRuns({
        0: _entry(0, bbt: 36.5),
        1: _entry(1, bbt: 36.4, flagged: true), // flags WITHOUT the mark
        2: _entry(2, bbt: 36.7),
      });
      expect(
        flaggedUnmarked.single.points[1].excluded,
        isFalse,
        reason: 'raw flags are no longer a rendering input',
      );

      // Marked AND flagged (the typical manually excluded day): lighter.
      final markedAndFlagged = curveRuns(
        {
          0: _entry(0, bbt: 36.5),
          1: _entry(1, bbt: 36.4, flagged: true),
          2: _entry(2, bbt: 36.7),
        },
        ignoredDayIndexes: {1},
      );
      expect(
        markedAndFlagged.single.points[1].excluded,
        isTrue,
        reason: 'the mark keying makes the flagged+marked day lighter',
      );
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
    test('an ignored day WITHOUT temperature just breaks the run '
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

  group('curveRuns — raw values', () {
    CurvePoint probe(Map<int, double?> temps, {Set<int>? ignored}) {
      final entries = {
        for (final MapEntry(:key, :value) in temps.entries)
          key: _entry(key, bbt: value),
      };
      final runs = curveRuns(entries, ignoredDayIndexes: ignored ?? const {});
      return [
        for (final run in runs)
          for (final point in run.points) point,
      ].single;
    }

    test('an in-range value passes through untouched', () {
      final point = probe({0: 36.5});
      expect(point.bbtC, 36.5, reason: 'runs carry the measured value');
    });

    test('a value above the range stays raw', () {
      final point = probe({0: 39.5});
      expect(
        point.bbtC,
        39.5,
        reason:
            'curveRuns never rewrites values — visibility is '
            ' decided later, by the clip helper',
      );
    });

    test('a value below the range stays raw', () {
      final point = probe({0: 35.2});
      expect(
        point.bbtC,
        35.2,
        reason:
            'curveRuns never rewrites values — visibility is '
            ' decided later, by the clip helper',
      );
    });

    test('a value exactly at a boundary passes through unchanged', () {
      expect(probe({0: 38.0}).bbtC, 38.0);
      expect(probe({0: 36.0}).bbtC, 36.0);
    });

    test('a run with an out-of-range day stays connected and keeps the raw '
        'value', () {
      final runs = curveRuns({
        0: _entry(0, bbt: 36.5),
        1: _entry(1, bbt: 40.1),
        2: _entry(2, bbt: 36.7),
      });
      expect(
        runs,
        hasLength(1),
        reason: 'connectivity is decided before any range knowledge',
      );
      expect(
        [for (final p in runs.single.points) p.bbtC],
        [36.5, 40.1, 36.7],
        reason: 'the out-of-range day keeps its raw value in the run',
      );
    });

    test('an isolated out-of-range day still forms a single-point run '
        'with its raw value', () {
      // No adjacent measured days — a segment-less run; the chart skips
      // it entirely when every measurement is out of range.
      final runs = curveRuns({5: _entry(5, bbt: 39.5)});
      expect(
        runs,
        hasLength(1),
        reason:
            'curveRuns is range-blind: the run survives even though '
            'nothing can be drawn from it',
      );
      final point = runs.single.points.single;
      expect(point.dayIndex, 5);
      expect(
        point.bbtC,
        39.5,
        reason: 'the out-of-range value is kept raw, not rewritten',
      );
    });

    test('an ignored out-of-range day is flagged anyway (raw value kept)', () {
      final point = probe({0: 40.1}, ignored: {0});
      expect(point.excluded, isTrue);
      expect(point.bbtC, 40.1);
    });
  });

  group('visibleCurveSegments — clipping to the visible value range', () {
    const defaultRange = TemperatureRange(min: 36.0, max: 38.0);

    CurveSegment segment(
      double ax,
      double ay,
      double bx,
      double by, {
      bool excludedA = false,
      bool excludedB = false,
    }) => CurveSegment(
      CurvePoint(dayIndex: ax.toInt(), bbtC: ay, excluded: excludedA),
      CurvePoint(dayIndex: bx.toInt(), bbtC: by, excluded: excludedB),
    );

    test('both endpoints in range: one span identical to the segment', () {
      final spans = visibleCurveSegments([
        segment(0, 37.0, 1, 37.5),
      ], defaultRange);
      expect(spans, hasLength(1));
      expect(spans.single.startX, 0);
      expect(spans.single.startY, 37.0);
      expect(spans.single.endX, 1);
      expect(
        spans.single.endY,
        37.5,
        reason: 'integer day endpoints, raw y values',
      );
    });

    test('in-range to above-range: the span ends at the boundary crossing', () {
      final spans = visibleCurveSegments([
        segment(0, 37.0, 1, 39.0),
      ], defaultRange);
      expect(spans, hasLength(1));
      expect(spans.single.startX, 0);
      expect(spans.single.startY, 37.0);
      expect(
        spans.single.endX,
        0.5,
        reason: 'the line crosses 38.0 halfway between the days',
      );
      expect(spans.single.endY, 38.0);
    });

    test('in-range to below-range: the span ends at the boundary crossing', () {
      final spans = visibleCurveSegments([
        segment(0, 37.0, 1, 35.0),
      ], defaultRange);
      expect(spans, hasLength(1));
      expect(spans.single.startX, 0);
      expect(spans.single.startY, 37.0);
      expect(spans.single.endX, 0.5);
      expect(spans.single.endY, 36.0);
    });

    test(
      'above-range to in-range: the span starts at the boundary crossing',
      () {
        final spans = visibleCurveSegments([
          segment(0, 39.0, 1, 37.0),
        ], defaultRange);
        expect(spans, hasLength(1));
        expect(spans.single.startX, 0.5);
        expect(spans.single.startY, 38.0);
        expect(spans.single.endX, 1);
        expect(spans.single.endY, 37.0);
      },
    );

    test(
      'below-range to in-range: the span starts at the boundary crossing',
      () {
        final spans = visibleCurveSegments([
          segment(0, 35.0, 1, 37.0),
        ], defaultRange);
        expect(spans, hasLength(1));
        expect(spans.single.startX, 0.5);
        expect(spans.single.startY, 36.0);
        expect(spans.single.endX, 1);
        expect(spans.single.endY, 37.0);
      },
    );

    test('both endpoints above the range: no span at all', () {
      final spans = visibleCurveSegments([
        segment(0, 39.0, 1, 40.0),
      ], defaultRange);
      expect(spans, isEmpty);
    });

    test('both endpoints below the range: no span at all', () {
      final spans = visibleCurveSegments([
        segment(0, 35.0, 1, 34.0),
      ], defaultRange);
      expect(spans, isEmpty);
    });

    test('below-range to above-range across the window: ONE span riding '
        'both boundary crossings', () {
      final spans = visibleCurveSegments([
        segment(0, 35.0, 1, 39.0),
      ], defaultRange);
      expect(spans, hasLength(1));
      // 35→39 crosses 36.0 at x = 0.25 and 38.0 at x = 0.75.
      expect(spans.single.startX, 0.25);
      expect(spans.single.startY, 36.0);
      expect(spans.single.endX, 0.75);
      expect(spans.single.endY, 38.0);
    });

    test('a segment starting exactly at the upper boundary and leaving '
        'upward: no drawable span (only the degenerate boundary point is '
        'in range) — but the boundary value itself classifies as in range', () {
      final spans = visibleCurveSegments([
        segment(0, 38.0, 1, 39.0),
      ], defaultRange);
      expect(
        spans,
        isEmpty,
        reason:
            't=0 is the only in-range point — a zero-length span '
            'is dropped',
      );
      expect(
        isBbtCInRange(38.0, defaultRange),
        isTrue,
        reason:
            'the boundary dot itself renders (the dot filter uses the '
            'same predicate)',
      );
      expect(
        isBbtCInRange(36.0, defaultRange),
        isTrue,
        reason: 'the lower boundary is inclusive as well',
      );
      expect(isBbtCInRange(38.5, defaultRange), isFalse);
      expect(isBbtCInRange(35.5, defaultRange), isFalse);
    });

    test('a crossing that lands exactly on an integer day: the single-point '
        'span is dropped', () {
      // 40→38 over two days touches the upper boundary exactly at day 2.
      final spans = visibleCurveSegments([
        segment(0, 40.0, 2, 38.0),
      ], defaultRange);
      expect(spans, isEmpty);
    });

    test(
      'a span whose source segment touches an interrupted day is lighter',
      () {
        final spans = visibleCurveSegments([
          segment(0, 37.0, 1, 39.0, excludedA: true),
          segment(0, 37.0, 1, 39.0, excludedB: true),
          segment(0, 37.0, 1, 39.0),
        ], defaultRange);
        expect(spans, hasLength(3));
        expect(
          spans[0].lighter,
          isTrue,
          reason: 'the interrupted endpoint carries the lighter bit',
        );
        expect(
          spans[1].lighter,
          isTrue,
          reason: 'either endpoint being interrupted makes the span lighter',
        );
        expect(spans[2].lighter, isFalse);
      },
    );
  });
}
