// Widget test of the Muttermund (cervix) display on the Zyklus chart: the
// recorded position renders as a glyph in the symbol row under the
// temperature curve, the firmness glyph renders BESIDE the position glyph
// (one cervix line, two observations), days without an observation stay
// empty, and the legend names the position symbol. Same harness pattern as
// test/cycle_chart_temperature_test.dart (localized en).
import 'package:cycle_app/domain/cervix.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedColor = const Color(0xFF6750A4);

List<DailyEntry> _entries() => [
      for (var i = 0; i < CervixPosition.values.length; i++)
        DailyEntry(
          date: DateTime.utc(2026, 9, 7 + i),
          bbtC: 36.5 + i * 0.1,
          cervixPosition: CervixPosition.values[i],
          // Opening must NOT be displayed on the chart: it only exists in
          // the entry form.
          cervixOpening: CervixOpening.open,
          // Day 0 additionally records a FIRMNESS, to pin that both cervix
          // observations render side by side in the same line (the 'w' for
          // soft stays letter-distinct from every position glyph).
          cervixFirmness:
              i == 0 ? CervixFirmness.soft : null,
        ),
      DailyEntry(date: DateTime.utc(2026, 9, 12), bbtC: 37.0),
    ];

Widget _chartHarness({required List<DailyEntry> entries}) => MaterialApp(
      themeMode: ThemeMode.system,
      theme:
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor, brightness: Brightness.dark),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ProviderScope(
        overrides: [
          dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          selectedDateProvider.overrideWith((ref) => entries.first.date),
        ],
        child: Scaffold(body: ZyklusScreen()),
      ),
    );

void main() {
  testWidgets('every recorded position renders one glyph under the curve',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    // One glyph per position category, checked inside its own symbol cell
    // (ValueKey convention 'symbolCell-$i'): low..unreachable days 0..4, day
    // 5 carries NO Muttermund observation and must render no glyph. The
    // scoping matters: the legend shows a sample glyph too.
    final glyphOf = {
      0: 't', // low (tief)
      1: 'm', // medium
      2: 'h', // high
      3: 'sh', // very high
      4: 'u', // unreachable
    };
    for (final MapEntry(:key, :value) in glyphOf.entries) {
      expect(
        find.descendant(
            of: find.byKey(ValueKey('symbolCell-$key')),
            matching: find.text(value)),
        findsOneWidget,
        reason: 'position category index $key renders its glyph under the '
            'curve inside its own cell',
      );
    }
    // Negative assertion against ALL five glyph letters (not a vacuous
    // find.text('') match): day 5 has no cervix observation, so none of
    // them may appear inside its symbol cell.
    for (final glyph in glyphOf.values) {
      expect(
        find.descendant(
            of: find.byKey(const ValueKey('symbolCell-5')),
            matching: find.text(glyph)),
        findsNothing,
        reason: 'no "$glyph" glyph for a day without an observation',
      );
    }
  });

  testWidgets('the firmness glyph renders beside the position glyph',
      (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    // Day 0 additionally carries the firmness observation: its glyph
    // renders BESIDE the position letter in the same cervix line ('w' for
    // soft, distinct from every position letter).
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('symbolCell-0')),
          matching: find.text('w')),
      findsOneWidget,
      reason: 'the firmness glyph renders beside the position glyph in the '
          'same cervix line',
    );
  });

  testWidgets('the legend names the Muttermund symbol', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(find.text('Cervix position'), findsOneWidget,
        reason: 'the glyph row needs a legend entry');
  });
}
