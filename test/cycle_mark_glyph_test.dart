// Unit tests of the evaluation-glyph geometry in lib/ui/cycle_marks.dart:
// the arrow-up glyph of a marked higher measurement (its placement relative
// to the temperature dot) and the SUZ arrow glyph's size (chart painter and
// legend sample together, no database).
import 'package:cycle_app/ui/cycle_marks.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('arrow-up glyph placement (higher measurement before the peak)', () {
    test('the arrow candidate glyph paints BELOW the temperature dot', () {
      // The paper sheet writes the upward arrow under the column's dot:
      // position-below, not orientation change — the head keeps pointing
      // up at the dot it marks.
      const center = Offset(100, 200);
      final tip = arrowUpTipFor(center, radius: 3);

      expect(
        tip.dy,
        greaterThan(center.dy),
        reason: 'the glyph tip sits below the dot center',
      );
      expect(
        tip.dx,
        center.dx,
        reason: 'the glyph stays centered on the day column',
      );
    });
  });

  group('SUZ arrow glyph size', () {
    testWidgets('the legend sample scales with the chart glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SuzArrowGlyph(color: const Color(0xFF000000))),
        ),
      );

      final sample = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(SuzArrowGlyph),
          matching: find.byType(CustomPaint),
        ),
      );
      // The sample box must carry the chart glyph's footprint — the very
      // Size the chart painter reports — next to its companion bar: the
      // 2 px bar sits at the 0.5 px left inset (see _SuzArrowGlyphPainter),
      // so the box is at least bar + inset + glyph wide, and at least the
      // glyph tall. Stated as proportions of the chart glyph's size, not
      // as bare absolutes.
      final glyphSize = SuzArrowDotPainter(
        color: const Color(0xFF000000),
      ).getSize(const FlSpot(0, 0));
      expect(
        sample.size.width,
        greaterThanOrEqualTo(glyphSize.width + 2.5),
        reason:
            'the bar (2 px) plus its 0.5 px inset precede the glyph '
            'in the sample box',
      );
      expect(
        sample.size.height,
        greaterThanOrEqualTo(glyphSize.height),
        reason:
            'the sample is at least as tall as the glyph '
            '(the bar spans the box\'s full height)',
      );
    });
  });
}
