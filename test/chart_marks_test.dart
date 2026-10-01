// Unit tests of the pure in-chart glyph layer (lib/ui/chart_marks.dart):
// the per-day observations records (sex timing slots, mucus letters,
// Mittelschmerz M flag) and the narrow-range visibility predicates for
// the top-anchored rows and the bottom-anchored numbers row — consumed
// by the cycle chart and the PDF export, who render the peak dot and
// the day numbers from the overlay artifacts themselves. The letter
// vocabulary stays mucusDisplay's — the tests pin that the mapper adds
// no second mapping.
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
  bool mittelschmerz = false,
}) => DailyEntry(
  date: DateTime.utc(2026, 9, 3).add(Duration(days: i)),
  mucusSign: sign,
  mucusQuality: quality,
  sexTimings: sexTimings,
  painMittelschmerz: mittelschmerz,
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

  group('chartDayMarks — a pure observations map (entries.keys only)', () {
    test('records exist exactly for the entries.keys', () {
      final marks = chartDayMarks({0: _entry(0), 2: _entry(2)});
      expect(marks.keys.toSet(), {0, 2});
    });

    test('a day absent from the entries stays record-less', () {
      final marks = chartDayMarks({0: _entry(0)});
      expect(marks[1], isNull);
    });
  });

  group('chartDayMarks — Mittelschmerz M flag', () {
    test('an entry with painMittelschmerz recorded carries the M', () {
      final marks = chartDayMarks({0: _entry(0, mittelschmerz: true)});
      expect(marks[0]!.mittelschmerz, isTrue);
    });

    test('an entry without the flag carries no M', () {
      final marks = chartDayMarks({0: _entry(0)});
      expect(marks[0]!.mittelschmerz, isFalse);
    });

    test('a day absent from the entries renders no M', () {
      final marks = chartDayMarks({0: _entry(0, mittelschmerz: true)});
      expect(marks[1], isNull);
    });
  });

  group('chartMarkRowVisible — narrow-range hiding, new pitch', () {
    test('the default range keeps every row (and the numbers) visible', () {
      final range = TemperatureRange.defaults;
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isTrue);
      expect(dayNumbersRowVisible(range), isTrue);
    });

    test('span 0.10 — sex AND the numbers sit on the boundary: visible', () {
      final range = TemperatureRange(min: 37.9, max: 38.0);
      // Boundary equality stays VISIBLE for both anchored kinds.
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(dayNumbersRowVisible(range), isTrue);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isFalse);
    });

    test('span 0.20 — sex AND the peak dot, mucus and M hidden', () {
      final range = TemperatureRange(min: 37.8, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      // The peak dot hides with ITS OWN row (0.15), decoupled from the
      // letters band: on this boundary it stays visible.
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isFalse);
      expect(dayNumbersRowVisible(range), isTrue);
    });

    test('span 0.30 — mucus joins on the boundary, M still hidden', () {
      final range = TemperatureRange(min: 37.7, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isFalse);
      expect(dayNumbersRowVisible(range), isTrue);
    });

    test('span 0.40 — M joins on the boundary: every row visible', () {
      final range = TemperatureRange(min: 37.6, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isTrue);
      expect(dayNumbersRowVisible(range), isTrue);
    });

    test('just below a span of 0.10 everything top-anchored hides', () {
      final range = TemperatureRange(min: 37.91, max: 38.0);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isFalse);
    });

    test('the peak dot hides just below span 0.20 — its own row, alone', () {
      final range = TemperatureRange(min: 37.81, max: 38.0);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isFalse);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isFalse);
    });

    test('rows hide independently — a hand-built mixed case at the floor', () {
      // Same 0.4 span as above but at the window floor: hiding is
      // min-anchored, not a rule pinned to one absolute scale position.
      final range = TemperatureRange(min: 34.0, max: 34.4);
      expect(chartMarkRowVisible(sexRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(peakDotCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mucusRowCenterOffsetK, range), isTrue);
      expect(chartMarkRowVisible(mRowCenterOffsetK, range), isTrue);
      expect(dayNumbersRowVisible(range), isTrue);
    });
  });

  group('dayNumbersRowVisible — bottom-anchored numbers rule', () {
    test('a span below 0.10 hides the numbers row', () {
      expect(
        dayNumbersRowVisible(TemperatureRange(min: 37.91, max: 38.0)),
        isFalse,
      );
      // Not pinned to one absolute position.
      expect(
        dayNumbersRowVisible(TemperatureRange(min: 36.0, max: 36.09)),
        isFalse,
      );
    });

    test(
      'a span of exactly 0.10 keeps the row (boundary equality visible)',
      () {
        expect(
          dayNumbersRowVisible(TemperatureRange(min: 37.9, max: 38.0)),
          isTrue,
        );
        expect(
          dayNumbersRowVisible(TemperatureRange(min: 34.0, max: 34.1)),
          isTrue,
        );
      },
    );

    test('every wider span keeps the row visible', () {
      expect(dayNumbersRowVisible(TemperatureRange.defaults), isTrue);
      expect(
        dayNumbersRowVisible(
          TemperatureRange(
            min: TemperatureRange.windowLower,
            max: TemperatureRange.windowUpper,
          ),
        ),
        isTrue,
      );
    });
  });
}
