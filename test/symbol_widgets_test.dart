// Widget tests of the shared symbol renderers: the bleeding square-box fill
// geometry and the mucus glyph long-press explanations.
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart' show MucusQuality, MucusSign;
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/bleeding_symbol.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  Widget harness(Widget child) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('de')],
    home: Scaffold(body: Center(child: child)),
  );

  Widget symbol(MucusSign? sign, [MucusQuality? quality]) =>
      MucusSymbolText(sign: sign, quality: quality, color: Colors.black);

  testWidgets('plain S long-presses into the S explanation', (
    WidgetTester tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(harness(symbol(MucusSign.s)));

    await tester.longPress(find.byType(MucusSymbolText));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.mucusSignTooltipS),
      findsOneWidget,
      reason:
          'the plain-S glyph shows the Schleim explanation from '
          'the cheat sheet',
    );
  });

  testWidgets('Sᴱᵂ long-presses into the sign and quality explanation', (
    WidgetTester tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(harness(symbol(MucusSign.s, MucusQuality.ew)));
    final combined = find.textContaining(
      '${l10n.mucusSignTooltipS} – ${l10n.mucusQualityTooltipEw}',
    );

    await tester.longPress(find.byType(MucusSymbolText));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10n.mucusSignTooltipS),
      findsOneWidget,
      reason: 'the long-press tooltip carries the Schleim explanation',
    );
    expect(
      combined,
      findsOneWidget,
      reason:
          'the S+EW glyph shows the Schleim explanation AND the '
          'EW-quality explanation together',
    );
  });

  testWidgets('no sign recorded renders no tooltip surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(symbol(null)));

    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: 'a blank day contributes no long-pressable glyph',
    );
  });

  testWidgets('A glyph ignores a stray quality in its tooltip', (
    WidgetTester tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('de'));
    await tester.pumpWidget(harness(symbol(MucusSign.a, MucusQuality.ew)));

    await tester.longPress(find.byType(MucusSymbolText));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.mucusSignTooltipA),
      findsOneWidget,
      reason: 'the A glyph explains Ausfluss',
    );
    expect(
      find.textContaining(l10n.mucusQualityTooltipEw),
      findsNothing,
      reason:
          'qualities render only with S, so the tooltip ignores '
          'one recorded on another sign',
    );
  });
}
