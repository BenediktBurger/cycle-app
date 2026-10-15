// Tests of the pure paper-form geometry helper (lib/pdf/pdf_axis.dart): the
// y geometry of the temperature scale. No pdf-package or Flutter import
// needed here: plain doubles only.
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/pdf/pdf_axis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('temperature axis (y geometry of the curve plot)', () {
    final axis = PdfCurveAxis(
      range: const TemperatureRange(min: 36.0, max: 38.0),
      plotHeight: 200,
    );

    test("yFor gives the distance down from the plot's top edge", () {
      expect(axis.yFor(36.0), closeTo(200, 1e-9));
      expect(axis.yFor(37.0), closeTo(100, 1e-9));
      expect(axis.yFor(38.0), closeTo(0, 1e-9));
    });

    test('yFor clamps out-of-window values to the edges for drawing calls', () {
      expect(axis.yFor(35.0), closeTo(200, 1e-9));
      expect(axis.yFor(39.5), closeTo(0, 1e-9));
    });

    test('the 0.1 °C grid lines run through the whole window inclusive of '
        'both bounds', () {
      final lines = axis.gridLines();
      expect(lines.length, 21, reason: '36,0 … 38,0 in 0,1 °C steps');
      expect(lines.first.value, closeTo(36.0, 1e-9));
      expect(lines.last.value, closeTo(38.0, 1e-9));
      expect(
        lines.map((l) => l.value),
        containsAllInOrder([36.4, 36.5, 37.0, 37.9]),
      );
      for (final line in lines) {
        expect(
          line.y,
          closeTo(axis.yFor(line.value), 1e-9),
          reason: 'the grid line sits on its value, never off-scale',
        );
      }
    });

    test('the scale labels mark every 0.5 °C plus the range\'s own bounds, '
        'with the German decimal comma and the °C unit on EVERY label', () {
      final labels = axis.axisLabels();
      expect(
        labels.map((l) => l.text).toList(),
        ['38 °C', '37,5 °C', '37 °C', '36,5 °C', '36 °C'],
        reason:
            'the paper form labels half degrees with a decimal comma; '
            'whole degrees stay plain; the unit is part of every label '
            '(no separate caption row — see the axis-label rail decision)',
      );
      expect(labels.map((l) => l.value).toList(), [
        38.0,
        37.5,
        37.0,
        36.5,
        36.0,
      ]);
      for (final label in labels) {
        expect(
          label.y,
          closeTo(axis.yFor(label.value), 1e-9),
          reason: 'the label rides on its grid position in the rail',
        );
      }
    });

    test('every axis label carries the °C suffix (unit per label)', () {
      final labels = axis.axisLabels();
      expect(
        labels.map((l) => l.text).toList(),
        everyElement(endsWith(' °C')),
        reason:
            'each rail label carries its own unit — no standalone '
            '"°C" caption row renders',
      );
    });

    test('a range whose bounds fall between the 0.5 °C steps still labels '
        'the bounds themselves', () {
      final axis = PdfCurveAxis(
        range: const TemperatureRange(min: 36.2, max: 37.6),
        plotHeight: 100,
      );
      expect(axis.axisLabels().map((l) => l.text).toList(), [
        '37,6 °C',
        '37,5 °C',
        '37 °C',
        '36,5 °C',
        '36,2 °C',
      ]);
      expect(
        axis.gridLines().length,
        15,
        reason: '36,2 … 37,6 in 0,1 °C steps',
      );
    });
  });
}
