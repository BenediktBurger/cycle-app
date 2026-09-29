// Unit tests of the pure in-chart glyph layer (lib/ui/chart_marks.dart):
// the per-day placement records (sex timing slots, mucus letters, mucus
// peak flag) and the narrow-range visibility predicate that the cycle
// chart and the PDF export both consume. The letter vocabulary stays
// mucusDisplay's — the tests pin that the mapper adds no second mapping.
import 'package:cycle_app/domain/mucus.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/ui/chart_marks.dart';
import 'package:flutter_test/flutter_test.dart';

DailyEntry _entry(
  int i, {
  MucusSign? sign,
  MucusQuality? quality,
  int sexTimings = 0,
}) => DailyEntry(
  date: DateTime.utc(2026, 9, 3).add(Duration(days: i)),
  mucusSign: sign,
  mucusQuality: quality,
  sexTimings: sexTimings,
);

void main() {
  group('chartDayMarks — sex timing slots', () {
    test('no recorded timing → no slot', () {
      final marks = chartDayMarks({0: _entry(0)});
      expect(marks[0]!.sexSlots, isEmpty);
    });

    test('start / middle / end each map to their column fraction', () {
      final start = chartDayMarks({
        0: _entry(0, sexTimings: SexTiming.start.bit),
      });
      expect(start[0]!.sexSlots.single.timing, SexTiming.start);
      expect(start[0]!.sexSlots.single.columnFraction, closeTo(1 / 6, 1e-9));

      final middle = chartDayMarks({
        0: _entry(0, sexTimings: SexTiming.middle.bit),
      });
      expect(middle[0]!.sexSlots.single.timing, SexTiming.middle);
      expect(middle[0]!.sexSlots.single.columnFraction, closeTo(0.5, 1e-9));

      final end = chartDayMarks({0: _entry(0, sexTimings: SexTiming.end.bit)});
      expect(end[0]!.sexSlots.single.timing, SexTiming.end);
      expect(end[0]!.sexSlots.single.columnFraction, closeTo(5 / 6, 1e-9));
    });

    test('two bits list both slots in SexTiming.values order', () {
      final marks = chartDayMarks({
        0: _entry(0, sexTimings: SexTiming.end.bit | SexTiming.start.bit),
      });
      expect(
        [for (final slot in marks[0]!.sexSlots) slot.timing],
        [SexTiming.start, SexTiming.end],
      );
      expect(marks[0]!.sexSlots[0].columnFraction, closeTo(1 / 6, 1e-9));
      expect(marks[0]!.sexSlots[1].columnFraction, closeTo(5 / 6, 1e-9));
    });

    test('all three bits list all three slots in SexTiming.values order', () {
      final marks = chartDayMarks({
        0: _entry(
          0,
          sexTimings:
              SexTiming.start.bit | SexTiming.middle.bit | SexTiming.end.bit,
        ),
      });
      expect([
        for (final slot in marks[0]!.sexSlots) slot.timing,
      ], SexTiming.values);
      expect(marks[0]!.sexSlots[0].columnFraction, closeTo(1 / 6, 1e-9));
      expect(marks[0]!.sexSlots[1].columnFraction, closeTo(0.5, 1e-9));
      expect(marks[0]!.sexSlots[2].columnFraction, closeTo(5 / 6, 1e-9));
    });

    test('a day absent from the entries has no placement record at all', () {
      final marks = chartDayMarks({0: _entry(0, sexTimings: 7)});
      expect(marks[1], isNull);
    });
  });

  group('chartDayMarks — mucus letters (mucusDisplay vocabulary)', () {
    test('every sign maps through mucusDisplay unchanged', () {
      for (final sign in MucusSign.values) {
        final marks = chartDayMarks({0: _entry(0, sign: sign)});
        expect(marks[0]!.mucus, mucusDisplay(sign: sign), reason: '$sign');
      }
      final fs = chartDayMarks({0: _entry(0, sign: MucusSign.fs)});
      expect(fs[0]!.mucus!.symbol, 'f/S');
      final nothing = chartDayMarks({0: _entry(0, sign: MucusSign.nothing)});
      expect(nothing[0]!.mucus!.symbol, 'Ø');
    });

    test('quality renders only as an S superscript token', () {
      final marks = chartDayMarks({
        0: _entry(0, sign: MucusSign.s, quality: MucusQuality.ew),
      });
      expect(marks[0]!.mucus, (symbol: 'S', superscript: 'EW'));

      final bare = chartDayMarks({0: _entry(0, sign: MucusSign.s)});
      expect(bare[0]!.mucus, (symbol: 'S', superscript: null));

      final noQualitySign = chartDayMarks({
        0: _entry(0, sign: MucusSign.fs, quality: null),
      });
      expect(noQualitySign[0]!.mucus!.superscript, isNull);
    });

    test('a sign-free day maps to no mucus glyph', () {
      final marks = chartDayMarks({0: _entry(0)});
      expect(marks[0]!.mucus, isNull);
    });
  });

  group('chartDayMarks — mucus peak flag', () {
    test('a peak-flagged day with an entry gets the dot', () {
      final marks = chartDayMarks(
        {0: _entry(0, sign: MucusSign.s), 1: _entry(1, sign: MucusSign.f)},
        peakIndexes: {0},
      );
      expect(marks[0]!.mucusPeak, isTrue);
      expect(marks[1]!.mucusPeak, isFalse);
    });

    test('a peak flag without an entry renders no dot', () {
      final marks = chartDayMarks(
        {0: _entry(0, sign: MucusSign.s)},
        peakIndexes: {1},
      );
      expect(marks[1], isNull);
    });

    test('mirrors the rows: the dot needs the entry, not the letter', () {
      final marks = chartDayMarks({0: _entry(0)}, peakIndexes: {0});
      expect(marks[0]!.mucusPeak, isTrue);
    });
  });

  group('chartMarkRowVisible — narrow-range hiding', () {
    test('the default range keeps both rows (and the peak dot) visible', () {
      final range = TemperatureRange.defaults;
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isTrue);
    });

    test('a span below 0.2 hides both rows', () {
      final range = TemperatureRange(min: 37.85, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
    });

    test('a span of exactly 0.2 keeps sex, hides mucus', () {
      final range = TemperatureRange(min: 37.8, max: 38.0);
      // The sex row center (37.85) sits exactly on the min + 0.05 margin:
      // boundary values are visible, not dropped.
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
    });

    test('a span of 0.3 still shows sex, hides mucus and the peak dot', () {
      final range = TemperatureRange(min: 37.7, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
    });

    test('rows hide independently — a hand-built mixed case', () {
      // Same 0.3 span as above but at the window floor: hiding is
      // min-anchored, not a rule pinned to one absolute scale position.
      final range = TemperatureRange(min: 34.0, max: 34.3);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
    });
  });
}
