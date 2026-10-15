// Pure-Dart unit tests of the temperature display range's value-type
// semantics: TemperatureRange.fromJson is the validation seam every reader
// of persisted material goes through; readers catch its ArgumentError and
// keep the default.
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemperatureRange.fromJson', () {
    test('wrongly ordered bounds are rejected', () {
      expect(
        () => TemperatureRange.fromJson(const {'min': 39.0, 'max': 35.5}),
        throwsArgumentError,
      );
    });

    test('bounds outside the 34–42 °C window are rejected as a range', () {
      expect(
        () => TemperatureRange.fromJson(const {'min': 30.0, 'max': 45.0}),
        throwsArgumentError,
      );
      // Mixed: min below the window, max inside — any bound outside the
      // window is invalid, not just a fully out-of-window pair.
      expect(
        () => TemperatureRange.fromJson(const {'min': 30.0, 'max': 39.0}),
        throwsArgumentError,
      );
      // Mirror case: min inside, max above the window.
      expect(
        () => TemperatureRange.fromJson(const {'min': 36.0, 'max': 45.0}),
        throwsArgumentError,
      );
    });

    test('fromJson restores what toJson wrote', () {
      const range = TemperatureRange(min: 34.0, max: 42.0);
      expect(TemperatureRange.fromJson(range.toJson()), range);
    });
  });
}
