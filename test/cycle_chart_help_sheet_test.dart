// Widget tests of the cycle tab's symbol glossary (help sheet): the
// legend left the screen — the Zyklus AppBar carries an info_outline
// action whose long-press-friendly tooltip opens a bottom sheet with the
// full symbol glossary (every entry the on-screen legend carried) plus
// the evaluation-arithmetic note. Localized in en and de.
//
// Same harness pattern as test/cycle_chart_rows_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:cycle_app/ui/cycle_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

List<DailyEntry> _entries(int count) => [
      for (var i = 0; i < count; i++)
        DailyEntry(date: DateTime.utc(2026, 9, 7 + i), bbtC: 36.5),
    ];

Widget _chartHarness({
  required List<DailyEntry> entries,
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(const <CycleMark>[])),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const ZyklusScreen(),
      ),
    );

/// The glossary entries (en wording); each is asserted inside the help
/// sheet. The "Ignored temperature" entry presents the VISUAL consequence
/// (the lighter temperature on the curve — the mark is the rendering key,
/// owner decision 2026-09-19) while naming where the mark is set.
const _glossaryEn = [
  'BBT (temperature)',
  'Bleeding',
  'Fertility sign (mucus)',
  'Mucus peak',
  'Ignored temperature (lighter; set in the day sheet)',
  'Circled higher measurements',
  'Premature temperature rise',
  'Baseline',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Cervix position',
  'Cervix firmness',
  'Measurement time',
  'Sex (X per time of day)',
  'Pain (B breast, M Mittelschmerz)',
];

const _glossaryDe = [
  'BBT (Temperatur)',
  'Blutung',
  'Zeichen der Fruchtbarkeit (Schleim)',
  'Schleimhöhepunkt',
  'Temperatur ignoriert (heller gezeichnet; im Tagesblatt gesetzt)',
  'Umrandete höhere Messungen',
  'vorzeitiger Temperaturanstieg',
  'Basislinie',
  'Sicher unfruchtbare Zeit (SUZ)',
  'Muttermund-Position',
  'Muttermund-Festigkeit',
  'Messzeitpunkt',
  'Sex (X je Zeitpunkt)',
  'Schmerz (B Brust, M Mittelschmerz)',
];

const _arithmeticNoteEn =
    'Evaluation marks: you place the mucus peak and the first higher '
    'measurement; numbering, baseline and circles are computed for display '
    'only — no fertility statement.';

const _arithmeticNoteDe =
    'Auswertungsmarkierungen: Schleimhöhepunkt und erste höhere Messung '
    'setzt du selbst; Nummerierung, Basislinie und Umrandungen werden nur '
    'für die Anzeige berechnet — keine Fruchtbarkeitsangabe.';

void main() {
  group('help sheet', () {
    testWidgets(
        'the Zyklus AppBar carries an info_outline action with a localized '
        'tooltip, and the glossary is NOT on the screen otherwise',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      final action = tester
          .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')));
      expect(action.icon,
          isA<Icon>().having((i) => i.icon, 'icon', Icons.info_outline),
          reason: 'the affordance is the info_outline icon');
      expect(action.tooltip, 'Show symbol glossary',
          reason: 'the action carries its localized tooltip');

      // The legend is gone from the screen: no glossary text renders
      // outside the sheet. The evaluation table below the chart card
      // legitimately renders its own localized row labels (its "Mucus
      // peak" row is a table attribute, not a glossary entry), so the
      // table's subtree is excluded from this absence check.
      for (final entry in _glossaryEn) {
        expect(outsideTable(find.text(entry)), isEmpty,
            reason: '"$entry" no longer sits on the screen');
      }
    });

    testWidgets('tapping the action opens the full symbol glossary (en)',
        (tester) async {
      await tester.pumpWidget(_chartHarness(entries: _entries(5)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the action opens a bottom sheet');
      expect(find.byKey(const ValueKey('cycleHelpSheet')), findsOneWidget,
          reason: 'the sheet carries its test key');
      expect(find.text('Symbol glossary'), findsOneWidget,
          reason: 'the sheet is titled');
      for (final entry in _glossaryEn) {
        // Scoped to the sheet: the evaluation table renders its own row
        // labels behind the sheet (the "Mucus peak" attribute row).
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('cycleHelpSheet')),
                matching: find.text(entry)),
            findsOneWidget,
            reason: 'the glossary explains "$entry"');
      }
      // The sheet also carries the evaluation-arithmetic note (which stays
      // on the screen below the chart card too — scoped to the sheet here).
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text(_arithmeticNoteEn)),
          findsOneWidget);
      // The mucus glossary sample is the plain S glyph (no EW superscript).
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text('EW')),
          findsNothing,
          reason: 'the mucus glossary sample carries no EW superscript');
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
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              (widget.decoration as BoxDecoration?)?.color ==
                  scheme.primary.withValues(alpha: 0.4)));
      expect(lighterDotSamples, findsOneWidget,
          reason: 'the glossary samples the lighter temperature dot '
              '(primary at 0.4 alpha — derived from the same constant the '
              'chart uses so they cannot drift)');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.byIcon(Icons.visibility_off_outlined)),
          findsNothing,
          reason: 'the old day-sheet-toggle icon sample is gone — the '
              'legend shows the rendering consequence, not the affordance');
    });

    testWidgets('the glossary uses the German wording in de', (tester) async {
      await tester.pumpWidget(
          _chartHarness(entries: _entries(5), locale: const Locale('de')));
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('cycleHelpAction')))
              .tooltip,
          'Zeichenerklärung anzeigen');

      await tester.tap(find.byKey(const ValueKey('cycleHelpAction')));
      await tester.pumpAndSettle();

      expect(find.text('Zeichenerklärung'), findsOneWidget);
      for (final entry in _glossaryDe) {
        // Scoped to the sheet: the evaluation table renders its own row
        // labels behind the sheet (the "Schleimhöhepunkt" attribute row).
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('cycleHelpSheet')),
                matching: find.text(entry)),
            findsOneWidget,
            reason: 'de: "$entry"');
      }
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cycleHelpSheet')),
              matching: find.text(_arithmeticNoteDe)),
          findsOneWidget);
    });
  });
}

/// The glossary [finder]'s matches that do NOT sit inside the evaluation
/// table: the table legitimately renders its own localized row labels (its
/// "Mucus peak" row is a table attribute, not a glossary entry), so the
/// glossary-absence check filters those matches out.
Iterable<Element> outsideTable(Finder finder) =>
    finder.evaluate().where((element) {
      var insideTable = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is CycleSummaryTable) insideTable = true;
        return !insideTable;
      });
      return !insideTable;
    });
