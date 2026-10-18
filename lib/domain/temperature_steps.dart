// Pure-Dart 0.05 K step grid over the settings window constants — the
// diary temperature wheel's item source. Integer hundredths arithmetic so
// every step is exactly its two-decimal value (same anti-drift pattern as
// temperatureRangeSteps in lib/ui/settings/temperature_range_card.dart).
import 'temperature_range.dart';

/// The 0.05 K grid across the [TemperatureRange.windowLower]–
/// [TemperatureRange.windowUpper] °C window (161 items at 0.05 K).
abstract final class TemperatureSteps {
  /// Grid pitch in hundredths of a degree.
  static const int _hundredthsPerStep = 5;

  /// The window's lower end in hundredths (34.0 °C).
  static const int _hundredthsLower = 3400;

  /// Number of grid items, endpoints included: (42.0 − 34.0) / 0.05 + 1.
  static const int count = 161;

  static final List<double> _all = List.unmodifiable(<double>[
    for (var k = 0; k < count; k++) valueAt(k),
  ]);

  /// Every grid value in ascending order, [windowLower] first.
  static List<double> get all => _all;

  /// The temperature of grid item [index]; [index] must be within
  /// `0..count-1`.
  static double valueAt(int index) {
    if (index < 0 || index >= count) {
      throw RangeError.range(index, 0, count - 1, 'index');
    }
    return (_hundredthsLower + index * _hundredthsPerStep) / 100;
  }

  /// The grid item closest to [temperature]; values outside the window
  /// clamp to the nearer end. Off-grid stored values (imports, old typed
  /// entries like 36.68) resolve here for DISPLAY only — the stored value
  /// itself is never rewritten by the caller.
  static double nearest(double temperature) =>
      valueAt(nearestIndex(temperature));

  /// The index of the grid item closest to [temperature], clamped into
  /// `0..count-1`.
  static int nearestIndex(double temperature) {
    final hundredths = (temperature * 100).round();
    final index = ((hundredths - _hundredthsLower) / _hundredthsPerStep)
        .round();
    return index.clamp(0, count - 1);
  }
}
