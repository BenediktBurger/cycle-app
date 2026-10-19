import 'package:cycle_app/domain/decimal_display.dart';
import 'package:cycle_app/domain/temperature_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finders.dart';

/// One wheel item's pixel height, derived from the rendered labels of the
/// two grid steps adjacent to [centered] — hardcoding the wheel's item
/// extent would drift silently when its layout changes.
double _itemExtent(WidgetTester tester, double centered) {
  final wheel = diaryTemperatureWheel();
  String label(double value) => formatDecimal(
    value,
    locale: Localizations.localeOf(tester.element(wheel)).toString(),
    decimalDigits: 2,
  );
  final index = TemperatureSteps.nearestIndex(centered);
  // The wheel renders its higher values on top: the step above the
  // centred one is the next HIGHER grid value.
  final above = tester.getCenter(
    find.descendant(
      of: wheel,
      matching: find.text(label(TemperatureSteps.valueAt(index + 1))),
    ),
  );
  final below = tester.getCenter(
    find.descendant(
      of: wheel,
      matching: find.text(label(TemperatureSteps.valueAt(index - 1))),
    ),
  );
  return (below.dy - above.dy) / 2;
}

/// Scrolls the diary temperature wheel from the grid value [from] it
/// currently centers to [to], one 0.05 K step per drag (a slow drag has no
/// fling momentum, so each step settles exactly one item).
Future<void> scrollTemperatureWheel(
  WidgetTester tester, {
  required double from,
  required double to,
}) async {
  final step = TemperatureSteps.valueAt(1) - TemperatureSteps.valueAt(0);
  var remaining = ((to - from) / step).round();
  if (remaining == 0) return;
  final extent = _itemExtent(tester, from);
  // tester.drag splits the move at kDragSlopDefault and the wheel's
  // DragStartBehavior.start discards that first segment — add the slop
  // back to move exactly one item per drag.
  final perDrag = extent + kDragSlopDefault;
  // Dragging the content DOWN (positive dy) selects higher values —
  // higher temperatures sit at the wheel's top.
  final toSmaller = remaining < 0;
  while (remaining != 0) {
    await tester.drag(
      diaryTemperatureWheel(),
      Offset(0, toSmaller ? -perDrag : perDrag),
    );
    await tester.pumpAndSettle();
    remaining += toSmaller ? 1 : -1;
  }
}
