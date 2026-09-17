// Widget test of the Muttermund (cervix) position display on the Zyklus
// chart: the recorded position renders as a glyph in the symbol row under
// the temperature curve, days without an observation stay empty, and the
// legend names the symbol. Same harness pattern as
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
    Finder cell(int i) => find.descendant(
        of: find.byKey(ValueKey('symbolCell-$i')), matching: find.text(''));
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
    expect(cell(5), findsNothing,
        reason: 'no glyph for a day without an observation');
  });

  testWidgets('the legend names the Muttermund symbol', (tester) async {
    await tester.pumpWidget(_chartHarness(entries: _entries()));
    await tester.pumpAndSettle();

    expect(find.text('Cervix position'), findsOneWidget,
        reason: 'the glyph row needs a legend entry');
  });
}
