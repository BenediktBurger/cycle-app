/// The cycle chart's temperature display range in °C: the FIXED y bounds
/// the plot and the frozen rail's scale share — settings-selectable
/// ("Temperaturbereich" card), default 36–38 °C, allowed window 34.0–42.0 °C.
///
/// Plain Dart value type (no Flutter) so the curve helpers
/// (lib/ui/cycle_curve.dart) and their tests can consume it headless.
/// Out-of-range temperatures CLIP at the boundary (owner decision: clip,
/// never rescale — the scale never stretches to fit an outlier).
///
/// Fahrenheit stays out of scope: the value, its bounds and every seam
/// built on it (label formatter, settings step units) live in °C domain
/// units, ready for a later conversion to hook into.
final class TemperatureRange {
  /// Both bounds must be ordered — the settings UI enforces this by
  /// construction (each picker only offers values strictly on its side of
  /// the other bound); the assertion keeps hand-built values honest.
  const TemperatureRange({required this.min, required this.max})
      : assert(min < max, 'temperature range needs min < max');

  /// The lower end of the settings UI's selectable window. A chosen range
  /// cannot go below it.
  static const double windowLower = 34.0;

  /// The upper end of the settings UI's selectable window.
  static const double windowUpper = 42.0;

  /// The default range the provider starts with (the owner-requested
  /// 36–38 °C window).
  static const TemperatureRange defaults =
      TemperatureRange(min: 36.0, max: 38.0);

  /// The chart's lower y bound, in °C.
  final double min;

  /// The chart's upper y bound, in °C.
  final double max;

  /// The display span in °C (drives the plot-height heuristic).
  double get span => max - min;

  /// JSON-map form for the generic key-value settings store
  /// ({"min":..,"max":..} — the exact shape the app_settings column holds).
  Map<String, Object?> toJson() => {'min': min, 'max': max};

  /// Restores a range from a [toJson] map. Missing or mistyped bounds, a
  /// wrongly ordered window, and bounds outside the [windowLower]–
  /// [windowUpper] °C window all throw [ArgumentError] — readers of
  /// persisted material (the settings store) catch that and keep their
  /// default. Any single bound outside the window is enough to reject: the
  /// mixed cases (one bound below the window, one inside) are invalid too.
  static TemperatureRange fromJson(Map<String, Object?> json) {
    final min = json['min'];
    final max = json['max'];
    if (min is! num || max is! num) {
      throw ArgumentError.value(
          json, 'json', 'needs numeric "min" and "max" bounds');
    }
    if (min >= max) {
      throw ArgumentError.value(json, 'json', 'needs min < max');
    }
    if (min < windowLower || max > windowUpper) {
      throw ArgumentError.value(
        json,
        'json',
        'needs both bounds inside the '
            '$windowLower–$windowUpper °C window',
      );
    }
    return TemperatureRange(min: min.toDouble(), max: max.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is TemperatureRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}
