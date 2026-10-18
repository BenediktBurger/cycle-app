// Pure-Dart unit tests of the 0.05 K step grid over the settings window
// (34.0–42.0 °C): the diary wheel's item source. The grid is integer
// arithmetic on hundredths of a degree, so every pin here is exact —
// any float drift in the conversion fails these tests.
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/domain/temperature_steps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemperatureSteps', () {
    test('the 34–42 °C window holds 161 steps of 0.05 K', () {
      expect(TemperatureSteps.count, 161);
      // Every step spans exactly 5 hundredths of a degree, judged on the
      // integer hundredths (a difference of doubles would drift).
      for (var k = 0; k < TemperatureSteps.count - 1; k++) {
        expect(
          _hundredthsOf(TemperatureSteps.valueAt(k + 1)) -
              _hundredthsOf(TemperatureSteps.valueAt(k)),
          5,
          reason: 'step $k must span exactly 0.05 K',
        );
      }
    });

    test('the endpoints are exactly the window constants', () {
      expect(TemperatureSteps.valueAt(0), TemperatureRange.windowLower);
      expect(
        TemperatureSteps.valueAt(TemperatureSteps.count - 1),
        TemperatureRange.windowUpper,
      );
    });

    test('every value is label-ready: its hundredths are exact', () {
      // Label-ready = a two-decimal formatter never sees a value like
      // 36.04999999999999: the double must round back to its own exact
      // hundredths.
      for (var k = 0; k < TemperatureSteps.count; k++) {
        expect(
          _hundredthsOf(TemperatureSteps.valueAt(k)),
          3400 + 5 * k,
          reason:
              'step $k must be exactly ${(34 + 0.05 * k).toStringAsFixed(2)}',
        );
      }
    });

    test('sampled values equal their two-decimal literals', () {
      expect(TemperatureSteps.valueAt(0), 34.0);
      expect(TemperatureSteps.valueAt(1), 34.05);
      expect(TemperatureSteps.valueAt(41), 36.05);
      expect(TemperatureSteps.valueAt(54), 36.70);
      expect(TemperatureSteps.valueAt(160), 42.0);
    });

    test('the step list runs the whole window in order', () {
      final all = TemperatureSteps.all;
      expect(all, hasLength(TemperatureSteps.count));
      expect(all.first, TemperatureRange.windowLower);
      expect(all.last, TemperatureRange.windowUpper);
      for (var k = 0; k < all.length; k++) {
        expect(all[k], TemperatureSteps.valueAt(k));
      }
    });

    test('index round trip: every grid value maps back to its own index', () {
      for (var k = 0; k < TemperatureSteps.count; k++) {
        expect(
          TemperatureSteps.nearestIndex(TemperatureSteps.valueAt(k)),
          k,
          reason: 'step $k must resolve back to itself',
        );
      }
    });

    test('off-grid values snap to the nearest step', () {
      // The rounding examples of the planned info text: 36.68–36.72 → 36.70,
      // 36.73–36.77 → 36.75.
      expect(TemperatureSteps.nearest(36.68), 36.70);
      expect(TemperatureSteps.nearest(36.72), 36.70);
      expect(TemperatureSteps.nearest(36.73), 36.75);
      expect(TemperatureSteps.nearest(36.77), 36.75);
      // A value already on the grid stays itself.
      expect(TemperatureSteps.nearest(36.70), 36.70);
    });

    test('values outside the window clamp to the ends', () {
      expect(TemperatureSteps.nearest(20.0), TemperatureRange.windowLower);
      expect(TemperatureSteps.nearest(45.0), TemperatureRange.windowUpper);
    });

    test('valueAt rejects indices outside the grid', () {
      expect(() => TemperatureSteps.valueAt(-1), throwsRangeError);
      expect(
        () => TemperatureSteps.valueAt(TemperatureSteps.count),
        throwsRangeError,
      );
    });
  });
}

int _hundredthsOf(double value) => (value * 100).round();
