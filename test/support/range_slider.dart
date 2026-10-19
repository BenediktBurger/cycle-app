// Shared driver for the temperature-range card's RangeSlider: a RangeSlider
// has no per-handle widget to tap, so the tests drive it at its thumb
// geometry. The track maps the allowed window linearly onto the track rect
// (see _trackRect), and the divisions mechanism snaps every landed position
// onto the half-degree grid.
import 'dart:math' as math;

import 'package:cycle_app/domain/temperature_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _slider() => find.byKey(const ValueKey('temperatureRangeSlider'));

/// The slider's track rect, derived the way the framework paints it: the
/// widget rect minus half the larger of the thumb and overlay shape on
/// each side. The app's theme sets no slider shapes, so the Material 2
/// defaults apply.
Rect _trackRect(WidgetTester tester) {
  final sliderTheme = SliderTheme.of(tester.element(_slider()));
  final thumbWidth =
      (sliderTheme.rangeThumbShape ?? const RoundRangeSliderThumbShape())
          .getPreferredSize(true, false)
          .width;
  final overlayWidth =
      (sliderTheme.overlayShape ?? const RoundSliderOverlayShape())
          .getPreferredSize(true, false)
          .width;
  final inset = math.max(overlayWidth, thumbWidth) / 2;
  final rect = tester.getRect(_slider());
  return Rect.fromLTWH(
    rect.left + inset,
    rect.top,
    rect.width - 2 * inset,
    rect.height,
  );
}

double _xForValue(WidgetTester tester, double value) {
  final track = _trackRect(tester);
  final span = TemperatureRange.windowUpper - TemperatureRange.windowLower;
  return track.left +
      (value - TemperatureRange.windowLower) / span * track.width;
}

/// Drags the lower or upper thumb onto [value] (a half-degree step inside
/// the allowed window). The first movement — the one that wins the drag
/// arena — must sit on the grabbed thumb's own side of the track midpoint:
/// the framework selects the dragged thumb by midpoint at drag start, and
/// the one-degree minimum gap guarantees each thumb's outer side is clear
/// of it. The gesture therefore starts beside the thumb, latches it with a
/// step away from the other thumb, and only then travels to the target.
Future<void> dragRangeThumbToValue(
  WidgetTester tester, {
  required bool lower,
  required double value,
}) async {
  final track = _trackRect(tester);
  final values = tester.widget<RangeSlider>(_slider()).values;
  final from = lower ? values.start : values.end;
  final thumbX = _xForValue(tester, from);
  final grabOffset = lower ? -20.0 : 20.0;
  final latchStep = lower ? -30.0 : 30.0;
  final latchedX = thumbX + grabOffset + latchStep;

  final gesture = await tester.startGesture(
    Offset(thumbX + grabOffset, track.center.dy),
  );
  await tester.pump();
  await gesture.moveBy(Offset(latchStep, 0));
  await tester.pump();
  await gesture.moveBy(Offset(_xForValue(tester, value) - latchedX, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
