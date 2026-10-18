import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/fixtures.dart';

// Widget tests of the cycle tab's symbol glossary (help sheet): the
// legend left the screen — the Zyklus AppBar carries an info_outline
// action whose long-press-friendly tooltip opens a bottom sheet with the
// full symbol glossary (every entry the on-screen legend carried) plus
// the evaluation-arithmetic note. Localized in en and de.
//

List<DailyEntry> _helpSheetEntries(int count) => [
  for (var i = 0; i < count; i++) DailyEntry(date: septSevenDay(i), bbtC: 36.5),
];

/// The glossary entries (en wording), each asserted inside the help sheet
/// and — in the appearance-order test — expected as the sheet's rendered
/// label sequence: the order mirrors the cycle tab's top-down render
/// order (the signal rows above the curve, then the temperature-curve
/// group, then the below-chart strip). The "Ignored temperature" entry
/// presents the VISUAL consequence (the lighter temperature on the curve
/// — the mark is the rendering key, owner decision 2026-09-19) while
/// naming where the mark is set.
const _glossaryEn = [
  'Bleeding',
  'Fertility sign (mucus)',
  'Mucus peak',
  'Mittelschmerz (M)',
  'Sex (X per time of day)',
  'BBT (temperature) in °C',
  'Ignored temperature (lighter; set in the day sheet)',
  'Circled higher measurements',
  'Premature temperature rise',
  'Baseline',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Measurement time',
  'Disturbed measurement (sp late to bed, a frequent night awakening, '
      'alk alcohol, kr illness)',
  'Cervix position',
  'Cervix firmness',
  'Breast pain (B)',
  'Note (diary text, shown vertically per day)',
];

/// The German glossary wording (authoritative draft per the language
/// policy), in the same top-down appearance order as `_glossaryEn`.
const _glossaryDe = [
  'Blutung',
  'Fruchtbarkeitszeichen (Zervixschleim)',
  'Schleimhöhepunkt',
  'Mittelschmerz (M)',
  'Geschlechtsverkehr (X je Zeitpunkt)',
  'Aufwachtemperatur in °C',
  'Temperatur ignoriert (heller gezeichnet)',
  'Umrandete höhere Messungen',
  'Vorzeitiger Temperaturanstieg',
  'Basislinie',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Messzeitpunkt',
  'Messstörung (sp Spät ins Bett, a Nachts öfter aufstehen, '
      'alk Alkohol, kr Krank)',
  'Muttermund-Position',
  'Muttermund-Festigkeit',
  'Brustschmerz (B)',
  'Notiz (Tagebuchtext, am Tag senkrecht dargestellt)',
];

const _arithmeticNoteEn =
    'Evaluation marks: you place the mucus peak and the first higher '
    'measurement; numbering, baseline and circles are computed for display '
    'only — no fertility statement.';

const _arithmeticNoteDe =
    'Auswertungsmarkierungen: Schleimhöhepunkt und erste höhere Messung '
    'setzt du selbst; Nummerierung, Basislinie und Umrandungen werden nur '
    'für die Anzeige berechnet — keine Fruchtbarkeitsangabe.';

Widget _helpSheetHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) => chartHarness(entries: entries, locale: locale, withScaffold: false);

void main() {
  group('help sheet', () {
    testWidgets(
      'the Zyklus AppBar carries an info_outline action with a localized '
      'tooltip, and the glossary is NOT on the screen otherwise',
      (tester) async {
        await pumpChart(
          tester,
          _helpSheetHarness(entries: _helpSheetEntries(5)),
        );

        final action = tester.widget<IconButton>(
          find.byKey(const ValueKey('cycleHelpAction')),
        );
        expect(
          action.icon,
          isA<Icon>().having((i) => i.icon, 'icon', Icons.info_outline),
          reason: 'the affordance is the info_outline icon',
        );
        expect(
          action.tooltip,
          'Show symbol glossary',
          reason: 'the action carries its localized tooltip',
        );

        // The legend is gone from the screen: no glossary text renders
        // outside the sheet anywhere on the cycle tab.
        for (final entry in _glossaryEn) {
          expect(
            find.text(entry),
            findsNothing,
            reason: '"$entry" no longer sits on the screen',
          );
        }
      },
    );

    testWidgets('tapping the action opens the full symbol glossary (en)', (
      tester,
    ) async {
      await pumpChart(tester, _helpSheetHarness(entries: _helpSheetEntries(5)));

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'the action opens a bottom sheet',
      );
      expect(
        find.byKey(const ValueKey('cycleHelpSheet')),
        findsOneWidget,
        reason: 'the sheet carries its test key',
      );
      expect(
        find.text('Symbol glossary'),
        findsOneWidget,
        reason: 'the sheet is titled',
      );
      for (final entry in _glossaryEn) {
        expect(
          find.text(entry),
          findsOneWidget,
          reason: 'the glossary explains "$entry"',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(_arithmeticNoteEn),
        ),
        findsOneWidget,
      );
      // The mucus glossary sample is the plain S glyph (no EW superscript).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text('EW'),
        ),
        findsNothing,
        reason: 'the mucus glossary sample carries no EW superscript',
      );
      // The ignored-temperature entry samples the VISUAL consequence: a
      // lighter temperature dot (primary at the chart's own 0.4 alpha —
      // the same constant the curve draws with), replacing the old
      // day-sheet-toggle icon sample.
      final scheme = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme;
      final lighterDotSamples = find.descendant(
        of: find.byKey(const ValueKey('cycleHelpSheet')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color ==
                  scheme.primary.withValues(alpha: 0.4),
        ),
      );
      expect(
        lighterDotSamples,
        findsOneWidget,
        reason:
            'the glossary samples the lighter temperature dot '
            '(primary at 0.4 alpha — derived from the same constant the '
            'chart uses so they cannot drift)',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsNothing,
        reason:
            'the old day-sheet-toggle icon sample is gone — the '
            'legend shows the rendering consequence, not the affordance',
      );
    });

    testWidgets('the glossary uses the German wording in de', (tester) async {
      await pumpChart(
        tester,
        _helpSheetHarness(
          entries: _helpSheetEntries(5),
          locale: const Locale('de'),
        ),
      );

      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')))
            .tooltip,
        'Zeichenerklärung anzeigen',
      );

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.text('Zeichenerklärung'), findsOneWidget);
      for (final entry in _glossaryDe) {
        expect(find.text(entry), findsOneWidget, reason: 'de: "$entry"');
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.text(_arithmeticNoteDe),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'the glossary entries render in the cycle tab\'s top-down appearance '
      'order (en and de)',
      (tester) async {
        final orders = [
          (
            const Locale('en'),
            _glossaryEn,
            'the glossary mirrors the cycle tab\'s top-down render order: '
                'the signal rows above the curve (bleeding, mucus, mucus '
                'peak, Mittelschmerz, sex), then the temperature-curve '
                'group (temperature, ignored temperature, circled higher, '
                'premature rise, baseline, SUZ), then the below-chart strip '
                '(measurement time, disturbance, cervix position, cervix '
                'firmness, breast pain, note)',
          ),
          (
            const Locale('de'),
            _glossaryDe,
            'the German sheet mirrors the en appearance order in the '
                'German documentation wording: signal rows, '
                'temperature-curve group, below-chart strip (en/de '
                'appearance order stays in parity — en/de parallel draft '
                'policy)',
          ),
        ];
        for (final (locale, glossary, orderReason) in orders) {
          await pumpFreshChart(
            tester,
            // The previous locale's open help-sheet route (its scrim) would
            // absorb the next tap without a remount.
            () => _helpSheetHarness(
              entries: _helpSheetEntries(5),
              locale: locale,
            ),
          );
          await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
          await tester.pumpAndSettle();

          // Walk the sheet's label texts in tree order (a Column renders
          // its children top-down, which the descendant finder preserves)
          // and compare the glossary members' sequence against the expected
          // appearance order — the sheet title and the arithmetic note are
          // not glossary members and are filtered out.
          final labels = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(const ValueKey('cycleHelpSheet')),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data)
              .whereType<String>()
              .where(glossary.toSet().contains)
              .toList();
          expect(labels, glossary, reason: '$locale: $orderReason');
        }
      },
    );

    testWidgets('the baseline entry samples the chart\'s dashed style', (
      tester,
    ) async {
      await pumpChart(tester, _helpSheetHarness(entries: _helpSheetEntries(5)));
      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      final glyph = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('cycleHelpSheet')),
          matching: find.byKey(const ValueKey('legendBaselineGlyph')),
        ),
      );
      expect(
        (glyph.painter as dynamic).dashPattern,
        baselineDashPattern,
        reason:
            'the legend paints the baseline dashed with the chart\'s own '
            'dash pattern — the chart\'s baseline bar is an fl_chart '
            'segment that cannot be reused outside the chart, so the '
            'glyph repaints the same dashes',
      );
    });
  });
}
