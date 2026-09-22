// Widget tests of the shared bleeding symbol: a square box whose bleed
// fill is a bottom-anchored fraction of the box height — levels 2–5 fill
// (level − 1)/4 of it (1/4, 2/4, 3/4, 4/4), level 1 (spotting) renders a
// dotted, interrupted fill within the bottom quarter band, and level 0
// renders nothing (the surfaces keep their own none appearance: the
// chart's empty cell, the diary's faint outlineVariant dot; see the
// symbol's header comment).
//
// The cycle chart's cells hand the symbol bounded constraints — the cell
// box serves as the fill boundary (the widget deliberately shrinks when
// given unbounded ones) — the diary tiles wrap it in a fixed 18 px
// square — these tests pin the geometry at a fixed square size, measured
// with getRect, so the convention cannot drift between the surfaces.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/bleeding_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const boxSide = 20.0;

  /// Pumps [bleeding] into a 20 px square box and returns the box rect.
  Future<Rect> pumpSymbol(WidgetTester tester, Bleeding bleeding) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: const ValueKey('box'),
              width: boxSide,
              height: boxSide,
              child: BleedingSymbol(bleeding: bleeding),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(const ValueKey('box')));
  }

  Iterable<Rect> fillRects(WidgetTester tester) => [
    for (var i = 0; i < find.byType(BleedingFill).evaluate().length; i++)
      tester.getRect(find.byType(BleedingFill).at(i)),
  ];

  testWidgets('level none renders no fill (the surfaces keep their own '
      'none appearance)', (tester) async {
    await pumpSymbol(tester, Bleeding.none);
    expect(
      find.byType(BleedingFill),
      findsNothing,
      reason: 'an untracked-looking empty box, nothing painted',
    );
  });

  testWidgets('levels 2–5 fill (level-1)/4 of the box height, '
      'bottom-anchored across the full width', (tester) async {
    final expectations = {
      Bleeding.light: 1 / 4,
      Bleeding.medium: 2 / 4,
      Bleeding.heavy: 3 / 4,
      Bleeding.maximum: 4 / 4,
    };
    for (final MapEntry(key: level, value: fraction) in expectations.entries) {
      final box = await pumpSymbol(tester, level);
      final rects = fillRects(tester);
      expect(
        rects,
        hasLength(1),
        reason: '$level draws exactly one solid fill region',
      );
      final rect = rects.single;
      expect(
        rect.height,
        closeTo(boxSide * fraction, 0.01),
        reason: '$level fills $fraction of the box height',
      );
      expect(
        rect.bottom,
        closeTo(box.bottom, 0.01),
        reason: '$level: the fill is anchored at the box\'s bottom',
      );
      expect(
        rect.width,
        closeTo(boxSide, 0.01),
        reason: '$level: the fill spans the full box width',
      );
    }
  });

  testWidgets('the fill carries the theme error color', (tester) async {
    await pumpSymbol(tester, Bleeding.heavy);
    final scheme = Theme.of(tester.element(find.byType(BleedingFill)));
    expect(
      tester.widget<BleedingFill>(find.byType(BleedingFill)).color,
      scheme.colorScheme.error,
    );
  });

  testWidgets('spotting renders dots — three or more disjoint fill regions '
      'inside the bottom quarter band, never a solid 1/4 fill', (tester) async {
    final box = await pumpSymbol(tester, Bleeding.spotting);
    final rects = fillRects(tester);
    expect(
      rects.length,
      greaterThanOrEqualTo(3),
      reason: 'spotting interrupts the 1/4 band into several dots',
    );

    final bandTop = box.top + boxSide * 3 / 4;
    for (final rect in rects) {
      expect(
        rect.top,
        greaterThanOrEqualTo(bandTop - 0.01),
        reason: 'the dots stay inside the bottom quarter band',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(box.bottom + 0.01),
        reason: 'the dots stay inside the bottom quarter band',
      );
    }
    final sorted = [...rects]..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < sorted.length; i++) {
      expect(
        sorted[i].left,
        greaterThanOrEqualTo(sorted[i - 1].right),
        reason: 'the dots are disjoint regions, not one merged bar',
      );
    }
    expect(
      sorted.last.right - sorted.first.left,
      lessThan(boxSide),
      reason: 'the dotted fill never reads as a solid quarter bar',
    );
  });
}
