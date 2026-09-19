// Roundtrip state preservation across tab switches: leaving the Zyklus tab
// and coming back must show the same chart view — the same scroll offset
// and the same rendered day window (the shell keeps all tabs mounted, so
// the chart state survives; the diary form reloads via selectedDateProvider
// instead of a remount).
//
// Harness pattern of test/app_shell_test.dart (in-memory drift database
// override, closeStreamsSynchronously: true, German locale pin) plus a
// stream-controller override for the entries so the chart has a long
// recorded range without touching the database.
import 'dart:async';

import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/cycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

import 'support/finders.dart';

import 'support/database.dart';

/// The horizontal scroll view that carries the cycle chart block, scoped to
/// the Zyklus screen (other tabs have their own scrollables).
Finder _chartScrollView() => find.descendant(
    of: find.byType(ZyklusScreen),
    matching: chartScrollView());

Widget _appScope(StreamController<List<DailyEntry>> entries) =>
    // Broadcast so the diary and the cycle chart (both watch this provider)
    // can listen at the same time.
    appScope(
      entriesStream: entries.stream,
      locale: const Locale('de'),
    );

void main() {
  testWidgets('cycle chart keeps its window across a tab switch away and back',
      (WidgetTester tester) async {
    final entries = StreamController<List<DailyEntry>>.broadcast();
    addTearDown(entries.close);

    await tester.pumpWidget(_appScope(entries));
    // A single pump here: the entries provider is still loading until the
    // controller below emits, and the loading spinner would never settle
    // under pumpAndSettle. After the emit, pumpAndSettle is safe again.
    await tester.pump();
    // The provider subscribes during the build above; an emit before that
    // would be dropped by the broadcast stream, so seed now and let the
    // shell settle with data.
    entries.add(longRangeEntries());
    await tester.pumpAndSettle();

    // Switch to the Zyklus tab.
    await tester.tap(navLabel('Zyklus'));
    await tester.pumpAndSettle();

    // Drag the window away from its initial position. A timed drag carries
    // no fling momentum, so the settle is deterministic — but the exact
    // settled offset depends on where the drag starts and how it clamps
    // against the scroll extent, so it is recorded below rather than
    // asserted. What matters for the preservation check is that the window
    // ends up somewhere ELSE than where it started (and, as of the initial
    // auto-scroll, that "else" is never the newest-days end: a remount
    // would jump straight back there, so a roundtrip mismatch is caught
    // wherever the drag settled).
    // The drag direction depends on where the window starts: from the
    // day-0 window (offset 0) it drags toward the later days, from the
    // newest-days window (at max scroll extent) it drags back toward the
    // earlier days — either way the window ends up away from the end it
    // started at, so the preservation check below is meaningful in both
    // shell/chart regimes.
    ScrollableState chartScrollState() => tester.state<ScrollableState>(find
        .descendant(of: _chartScrollView(), matching: find.byType(Scrollable)));
    final positionBeforeDrag = chartScrollState().position;
    final startOffset = positionBeforeDrag.pixels;
    final dragFromEnd = startOffset >= positionBeforeDrag.maxScrollExtent;
    await tester.timedDrag(
      _chartScrollView(),
      Offset(dragFromEnd ? 300 : -300, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();

    final offsetBefore = chartScrollState().position.pixels;
    expect(offsetBefore, isNot(startOffset),
        reason: 'the drag must have moved the window off its start position');

    List<int> renderedCells() => [
          for (var i = 0; i < 60; i++)
            if (find.byKey(ValueKey('bleedingCell-$i')).evaluate().isNotEmpty)
              i,
        ];
    final cellsBefore = renderedCells();
    expect(cellsBefore, isNotEmpty,
        reason: 'the scrolled window must render day cells');

    // Roundtrip: to the diary tab and back.
    await tester.tap(navLabel('Tagebuch'));
    await tester.pumpAndSettle();
    await tester.tap(navLabel('Zyklus'));
    await tester.pumpAndSettle();

    expect(chartScrollState().position.pixels, offsetBefore,
        reason: 'the scroll offset must survive the tab switch');
    expect(renderedCells(), cellsBefore,
        reason:
            'the same day window must still be rendered after the roundtrip');
  });
}
