import 'package:flutter_test/flutter_test.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/domain/mucus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'support/chart_pump.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/provider_fixtures.dart';

// Widget tests of the cycle screen's data states: a failing entries or marks
// stream swaps the chart block for the retry surface whose tap re-invokes the
// stream factory; signal-less tracked days still render the chart; and the
// chart's tracked range follows the shared derived pass's today-span rule
// (the chart renders up to the pinned `today`, never past it).

// The tracked day the signal-less scenarios carry, also pinned as
// `today` for the clock-inside-the-tracked-range case.
final _trackedDay = DateTime.utc(2026, 9, 10);

void main() {
  testWidgets('a marks stream error replaces the chart with the retry '
      'surface, and retry re-renders the chart', (tester) async {
    final marksRetry = StreamRetryFixture<CycleMark>(evaluationScenarioMarks());
    await pumpChart(
      tester,
      chartHarness(
        entries: evaluationScenarioEntries(),
        marksStreamFactory: marksRetry.stream,
      ),
    );

    expect(
      find.byType(LineChart),
      findsNothing,
      reason:
          'the chart must not render marks-driven content from the '
          'silently-empty marks list',
    );
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('marksStreamRetryButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('marksStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
    expect(
      marksRetry.attempts,
      2,
      reason: 'the retry re-invoked the stream factory',
    );
  });

  testWidgets('a marks stream error also replaces the no-data text with the '
      'retry surface when there is nothing to chart', (tester) async {
    final failingMarks = StreamRetryFixture<CycleMark>(const []);
    await pumpChart(
      tester,
      chartHarness(
        entries: const [],
        selectedDate: DateTime(2024, 5, 2),
        marksStreamFactory: failingMarks.stream,
      ),
    );

    expect(
      find.text('Enter observations or measurements to see the cycle.'),
      findsNothing,
    );
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('marksStreamRetryButton')),
      findsOneWidget,
    );
  });

  testWidgets('an entries stream error gains the retry affordance, and '
      'retry restores the chart', (tester) async {
    final entriesRetry = StreamRetryFixture<DailyEntry>(
      evaluationScenarioEntries(),
    );
    await pumpChart(
      tester,
      chartHarness(
        entries: evaluationScenarioEntries(),
        marks: evaluationScenarioMarks(),
        entriesStreamFactory: entriesRetry.stream,
      ),
    );

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Loading failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('entriesStreamRetryButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('entriesStreamRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
    expect(entriesRetry.attempts, 2);
  });

  // The screen merges the raw entries with the shared derived pass's
  // span-extended cycle day lists (lib/ui/cycle.dart), so the chart's range
  // follows the SHARED span rule: it reaches the pinned `today` and renders
  // whenever any tracked day exists — however signal-less the temperature
  // data is. The harness pins `now` to the last seeded day by default; the
  // span tests here pass the explicit pin.
  testWidgets('a bleeding-only tracked day renders the chart, not the '
      'no-data message', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: [DailyEntry(date: _trackedDay, bleeding: Bleeding.heavy)],
      ),
    );

    expect(
      dayLabel(0),
      findsOneWidget,
      reason: 'the tracked day renders its day column',
    );
    expect(
      bleedingFills(0),
      findsOneWidget,
      reason: 'the bleeding glyph renders in the bleeding row',
    );
    expect(
      find.textContaining('Enter observations or measurements'),
      findsNothing,
      reason: 'bleeding data is data: the no-data placeholder must not show',
    );
  });

  testWidgets('a mucus-only tracked day renders the chart', (tester) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: [DailyEntry(date: _trackedDay, mucusSign: MucusSign.s)],
      ),
    );

    expect(dayLabel(0), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inPlotMucus-0')),
      findsOneWidget,
      reason: 'the mucus glyph renders inside the temperature plot',
    );
    expect(
      find.textContaining('Enter observations or measurements'),
      findsNothing,
    );
  });

  testWidgets('the chart renders up to today, not up to the last tracked day', (
    tester,
  ) async {
    // The scenario's tracked range ends 9/16 (index 10); five placeholder
    // days extend the span to the pinned today (indexes 11..15).
    await pumpChart(
      tester,
      chartHarness(
        entries: evaluationScenarioEntries(),
        now: () => DateTime.utc(2026, 9, 21),
      ),
    );

    expect(
      dayLabelText(15, '21.'),
      findsOneWidget,
      reason: "today's column renders, with its day-of-month label",
    );
    expect(
      find.byKey(const ValueKey('bleedingCell-19')),
      findsNothing,
      reason: 'the span ends at today, not past it',
    );
    expect(
      find.byKey(const ValueKey('bleedingCell-15')),
      findsOneWidget,
      reason:
          'the placeholder days render tap targets, so the extended '
          'range stays editable through today',
    );
    final renderedLabels = tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('dayLabel-'),
          ),
        )
        .length;
    expect(
      renderedLabels,
      16,
      reason: '11 tracked days + 5 placeholder days render',
    );
  });

  testWidgets('a pinned clock behind the data never retracts the chart', (
    tester,
  ) async {
    // Today (9/10) lies inside the tracked range (ends 9/16): the span
    // rule's max keeps the tracked end — the clock never shortens a longer
    // dataset.
    await pumpChart(
      tester,
      chartHarness(
        entries: evaluationScenarioEntries(),
        now: () => _trackedDay,
      ),
    );

    expect(
      dayLabelText(10, '16.'),
      findsOneWidget,
      reason: 'the last tracked day stays the chart\'s right edge',
    );
    expect(find.byKey(const ValueKey('dayLabel-11')), findsNothing);
  });

  testWidgets('genuinely nothing tracked keeps the no-data message', (
    tester,
  ) async {
    await pumpChart(
      tester,
      chartHarness(
        entries: const [],
        marks: const [],
        selectedDate: _trackedDay,
      ),
    );

    expect(
      find.textContaining('Enter observations or measurements'),
      findsOneWidget,
      reason: 'no entries and no marks render the centered no-data text',
    );
    expect(find.byType(LineChart), findsNothing);
  });
}
