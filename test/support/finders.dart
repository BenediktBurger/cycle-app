// Shared finders and chart-view-state helpers for the widget tests — the
// interaction helpers the chart and shell tests kept copy-pasting.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The navigation shell carries each tab's label exactly once per surface;
/// scoping the taps here keeps them unambiguous even though every screen
/// (and its AppBar) is mounted at once — the shell keeps all tabs mounted in
/// an IndexedStack, so a bare find.text(label) matches the bar's/rail's
/// destination AND the mounted screen's AppBar title (tree order puts the
/// AppBar first, so a bare .first tap would miss). Both adaptive surfaces
/// match: the bottom NavigationBar (phone portrait) and the NavigationRail
/// (wide/landscape shell, width >= 720) — the shell test pins which one
/// renders at which size, this finder only needs to tap through either.
Finder navLabel(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail),
  matching: find.text(label),
);

/// The non-modal day options panel on the cycle screen (the converted
/// former modal bottom sheet): keyed wrapper the Zyklus screen renders
/// below the chart while a tapped day's options are showing.
Finder cycleDayPanel() => find.byKey(const ValueKey('cycleDayPanel'));

/// The day options panel's "edit day" icon button (the form-jump affordance
/// in the panel header next to the day label and the close button).
Finder cycleDayPanelEditButton() =>
    find.byKey(const ValueKey('cycleDayPanelEdit'));

/// The Zyklus screen's vertical list scroller (the horizontal chart
/// scroller is excluded by direction). Offstage tabs are skipped
/// by default, so in the full-app scope this still matches once — if a
/// tree carries more than one vertical scroller in view, scope the finder
/// to the screen's descendant.
Finder cycleListScroller() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// The horizontal scroll view that carries the chart block. Callers that
/// share the tree with other screens (the tab shell keeps every tab
/// mounted) wrap this in a ZyklusScreen-scoped descendant finder.
Finder chartScrollView() => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

/// A chart-block recording-row cell: [row] = signal key (e.g. `bleeding`,
/// `cervix`, `disturbance`), [index] = the day column.
Finder chartCell(int index, String row) =>
    find.byKey(ValueKey('${row}Cell-$index'));

/// The row's header-corner prototype cell outside the day columns.
Finder chartCellCorner(String row) => find.byKey(ValueKey('${row}Corner'));

/// A finder scoped inside a chart-block cell.
Finder chartCellContent(int index, String row, Finder inner) =>
    find.descendant(of: chartCell(index, row), matching: inner);

/// A diary entry-form chip: [group] is the chip row's key group (`bleeding`,
/// `disturbance`, `mucusSign`, `mucusQuality`, `cervixPosition`,
/// `cervixOpening`, `cervixFirmness`, `sexTiming`, `pain`) and [value] the
/// option token — the domain enum's `.name` (e.g. bleeding `none`…`maximum`,
/// sex timing `start`/`middle`/`end`, pain `breast`/`mittelschmerz`, whose
/// row has no enum of its own), or `unset` for the mucus sign row's
/// "no sign" chip. The cervix rows' leading unset chips ("—") carry no key
/// (the mucus sign row's does, via the `unset` value above), and the
/// mucusQuality chips only exist while the S sign is selected (the row
/// wrapper is keyed `mucusQualityRow`).
///
/// The Tagebuch screen mounts exactly once (the shell's IndexedStack keeps
/// every tab built, but offstage tabs are skipped by default finders), so a
/// bare key matches once whenever the diary tab is in view; tests that
/// reach the form from a shell-level scope keep their existing
/// TagebuchScreen-descendant wrapper around this finder.
Finder diaryChip(String group, String value) =>
    find.byKey(ValueKey('${group}Chip-$value'));

/// The entry form's temperature input (the BBT field, the form's first
/// field).
Finder diaryTemperatureField() =>
    find.byKey(const ValueKey('diaryTemperatureField'));

/// The entry form's measured-time button: visible only while a plausible
/// temperature is entered, showing the stored or prefilled time.
Finder measuredTimeField() => find.byKey(const ValueKey('measuredTimeField'));

/// The entry form's bottom save button — NOT the AppBar's save action,
/// which carries its own `diarySaveAction` key.
Finder diarySaveButton() => find.byKey(const ValueKey('diarySaveButton'));

/// A mark chip in the day options panel: [markType] is the mark-type token
/// (`cycleStart`, `mucusPeakDay`, `firstHigherMeasurement`, `suzEvening`,
/// `suzMorning`, `ignoreTemperature`) — the panel keys every chip
/// `cycleSheetChip-<token>`, so the finder argument follows the domain's
/// mark vocabulary instead of the chip's static label. The
/// temperature-exclusion chip carries its chip key too, inside the keyed
/// `cycleSheetExcludeGroup` cell of the shared grid; the group key stays
/// available for tests that scope at the whole group.
///
/// The chip keys are unique in the tree (mark chips render only in the
/// panel, whose presence a test already ensures before a tap), so a bare
/// key matches once; a test sharing the tree with a retargeted open
/// panel must gate the tap behind the day tap that opens it, as everywhere
/// else in the cycle-list harnesses.
Finder cycleSheetChip(String markType) =>
    find.byKey(ValueKey('cycleSheetChip-$markType'));

/// The rise-consistency dialog's Keep choice (keeps the just-placed,
/// inconsistent first-higher mark standing — same effect as dismissing).
Finder cycleSheetRiseKeepButton() =>
    find.byKey(const ValueKey('cycleSheetRiseKeepButton'));

/// The rise-consistency dialog's Remove choice (removes the just-placed
/// first-higher mark through the toggle path).
Finder cycleSheetRiseRemoveButton() =>
    find.byKey(const ValueKey('cycleSheetRiseRemoveButton'));

// --- settings screen -------------------------------------------------------

/// The settings screen's language switcher (the `SegmentedButton<String>`
/// heading the language card).
///
/// The screen mounts once, and default finders skip the IndexedStack's
/// offstage tabs, so a bare key matches once whenever the settings tab is
/// in view — but it stays resolvable UNDER a pushed route (the about page,
/// an import dialog), since those leave the settings screen on stage; a
/// test sharing the tree with such an overlay scopes through it.
Finder settingsLanguageSwitcher() =>
    find.byKey(const ValueKey('languageSwitcher'));

/// One segment of the language switcher: [value] is the switcher's model
/// token (`'system'`/`'de'`/`'en'` — the segment model strings, not the
/// label wording). The key lives on the segment's label Text (a
/// ButtonSegment cannot carry a key, and the rendered segment is an
/// unkeyed TextButton — see settings.dart); it is sought as the
/// switcher-scoped descendant so the tap cannot land anywhere else.
Finder settingsLanguageSegment(String value) => find.descendant(
  of: settingsLanguageSwitcher(),
  matching: find.byKey(ValueKey('languageSegment-$value')),
);

/// The settings screen's theme-mode switcher (the
/// `SegmentedButton<ThemeMode>` heading the theme card) — same
/// mounting/offstage story as settingsLanguageSwitcher above.
Finder settingsThemeSwitcher() => find.byKey(const ValueKey('themeSwitcher'));

/// One segment of the theme-mode switcher: [value] is the ThemeMode enum
/// name (`'system'`/`'light'`/`'dark'`), not the label wording. Key rides on
/// the segment label Text, scoped inside the switcher (mirrors
/// settingsLanguageSegment above).
Finder settingsThemeSegment(String value) => find.descendant(
  of: settingsThemeSwitcher(),
  matching: find.byKey(ValueKey('themeSegment-$value')),
);

/// The settings pane's JSON export launch button (the download action of
/// the export card).
Finder settingsExportButton() =>
    find.byKey(const ValueKey('settingsExportButton'));

/// The settings pane's JSON import launch button (opens the JSON import
/// dialog).
Finder settingsImportJsonButton() =>
    find.byKey(const ValueKey('settingsImportJsonButton'));

/// The drip CSV import card's launch button — distinct from the dialog's
/// apply action, which shares the l10n label and is scoped through the
/// AlertDialog where needed.
Finder settingsImportDripButton() =>
    find.byKey(const ValueKey('settingsImportDripButton'));

/// The PDF export card's save button (generates the document and hands it
/// to the save-as dialog; the card carries the summary line, the anonymize
/// switch and the save+share action row — see [pdfExportShareButton]).
Finder pdfExportButton() => find.byKey(const ValueKey('pdfExportButton'));

/// The PDF export card's share button (the second hand-off next to the
/// save button: same generated document, system share sheet instead of the
/// save-as dialog).
Finder pdfExportShareButton() =>
    find.byKey(const ValueKey('pdfExportShareButton'));

/// The PDF export card's anonymize switch (card-local state; it never
/// writes a provider or settings row).
Finder pdfExportAnonymizeSwitch() =>
    find.byKey(const ValueKey('pdfExportAnonymizeSwitch'));

/// The cycle-selection sub-page's confirm button: applies the toggled
/// selection back onto the card — distinct from the All/None shortcuts
/// that only change the page's rows.
Finder pdfExportSelectionConfirmButton() =>
    find.byKey(const ValueKey('pdfExportSelectionConfirmButton'));

/// The color-scheme brightness actually materialized by the running app,
/// taken from the shell's Scaffold (below the MaterialApp theme wiring).
Brightness materializedBrightness(WidgetTester tester) {
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  return Theme.of(scaffoldContext).colorScheme.brightness;
}

/// The full LineChartData of the (single) chart on screen.
LineChartData chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

/// The Material scheme the chart renders with (the app's ThemeData from
/// the harness MaterialApp).
ColorScheme chartScheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme;

/// The dot-only bars (invisible line) whose per-spot dot painters decide
/// how each temperature renders.
List<LineChartBarData> dotBars(WidgetTester tester) =>
    chartData(tester).lineBarsData.where((bar) {
      final color = bar.color;
      return color == null || color.a == 0;
    }).toList();

/// The dot painter for a day index, or null when the day has no temperature
/// point on the chart.
FlDotPainter? dotPainterOrNull(WidgetTester tester, int dayIndex) {
  for (final bar in dotBars(tester)) {
    for (var i = 0; i < bar.spots.length; i++) {
      final spot = bar.spots[i];
      if (spot.x.round() == dayIndex) {
        return bar.dotData.getDotPainter(spot, 0, bar, i);
      }
    }
  }
  return null;
}

/// The dot painter the chart would use for the temperature dot of [dayIndex]
/// (fails when that day has no temperature point on the chart).
FlDotPainter dotPainter(WidgetTester tester, int dayIndex) {
  final painter = dotPainterOrNull(tester, dayIndex);
  if (painter == null) fail('no temperature dot at day index $dayIndex');
  return painter;
}
