// Widget tests of the shared MucusSymbolText renderer: the compact mucus
// glyphs (Tagebuch day chip, chart mucus cell, help-sheet legend) must
// long-press into the same cheat-sheet explanation the entry-form picker
// chips carry — plain S shows the sign explanation, Sᴱᵂ shows the sign and
// quality explanations together.
//
// Low-level harness: the renderer is pumped directly, German labels are
// pinned (locale de).

import 'package:cycle_app/domain/mucus.dart' show MucusQuality, MucusSign;
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/mucus_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
