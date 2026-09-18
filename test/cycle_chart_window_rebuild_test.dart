// A regression test for the chart's window-rebuild pace: the built day
// window parks with an extra screen-width of margin past the visible
// edges and is only rebuilt when the visible edge would run into that
// margin. Scrolling a long distance must therefore re-window only a
// handful of times — not once per day column. The scroll listener fires
// every scroll tick, but only a window-bound change rebuilds the chart
// block, so the count of rendered-window transitions IS the rebuild
// count the scroll path causes.
//
// Same harness pattern as test/cycle_chart_windowing_test.dart.
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A many-day recorded range (2026-01-01 onwards); the cycle-start marks
// keep the header's day-of-cycle labels in the two-digit range a real
// recording stays in (same fixture pattern as the windowing tests).
DateTime _day(int index) => DateTime.utc(2026, 1, 1).add(Duration(days: index));

List<DailyEntry> _entries() => [
      for (var i = 0; i < 600; i++)
        DailyEntry(date: _day(i), bbtC: 36.4 + (i % 10) * 0.05),
    ];

List<CycleMark> _cycleStartMarks() => [
      for (var i = 24; i <= 599; i += 25)
        CycleMark(
            profileId: 1, date: _day(i), type: CycleMarkTypes.cycleStart),
    ];

Finder _hScrollView() => find.byWidgetPredicate((w) =>
    w is SingleChildScrollView &&
    w.scrollDirection == Axis.horizontal &&
    w.key != const ValueKey('cycleSummaryScroll'));

/// The day indexes whose signal cells are currently built.
Set<int> _builtCells(WidgetTester tester) {
  const prefix = 'bleedingCell-';
  final indexes = <int>{};
  for (final widget in tester.widgetList(find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>)
          .value.startsWith(prefix)))) {
    final suffix = (widget.key! as ValueKey<String>).value
        .substring(prefix.length);
    indexes.add(int.parse(suffix));
  }
  return indexes;
}

void main() {
  testWidgets(
      'scrolling a long distance re-windows the chart only a handful of '
      'times, not once per day column', (tester) async {
    final entries = _entries();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dailyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        marksProvider.overrideWith((ref) => Stream.value(_cycleStartMarks())),
        selectedDateProvider.overrideWith((ref) => entries.first.date),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: ZyklusScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Travel 2000 px in 10 px steps (one pump per step): with a parked
    // window carrying an extra screen-width of margin (31 columns at this
    // viewport), the window needs re-parking only every extra screen-width
    // of travel — once per active edge — not once per day column.
    var reWindows = 0;
    var built = _builtCells(tester);
    const steps = 200;
    final gesture = await tester
        .startGesture(tester.getCenter(_hScrollView().first));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(10, 0)); // toward earlier days
      await tester.pump(const Duration(milliseconds: 16));
      final now = _builtCells(tester);
      if (!setEquals(now, built)) {
        reWindows++;
        built = now;
      }
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Measured improvement trail: without windowing/margin this 2000 px
    // scroll caused 200 window rebuilds; with the parked screen-width
    // margin ≤2 were observed — the bound of 6 is headroom for the parked
    // window's two edges and the range's clamped edges.
    expect(reWindows, lessThanOrEqualTo(6),
        reason: 'a 2000 px scroll must re-window only a handful of times '
            '(the parked margin absorbs the travel); observed $reWindows');
  });
}
