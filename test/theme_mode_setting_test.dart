// Theme-mode setting: the app's color-scheme mode (light / dark / system)
// is selectable in the settings screen. Mirrors the language switcher
// pattern: the choice is written through to the local app_settings table on
// change and hydrated back on the next start (the persistence round trip
// itself is pinned in settings_persistence_test.dart); the default "System"
// follows the device brightness setting.
//
// The platform brightness is simulated through the test binding's platform
// dispatcher; the app itself is unchanged: in-memory drift database
// override, no platform channels (same pattern as the locale tests,
// in this directory). The first test pins the light OS surface (formerly
// its own file, theme_brightness_test.dart — merged here, its "dark OS
// setting" duplicate having been removed in the earlier dedupe); the rest
// cover the dark surface and the explicit light/dark choices.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

import 'support/database.dart';
import 'support/viewport.dart';

/// App scope for the theme-mode tests. A null [themeMode] means: leave the
/// provider at its real default (the "System" option); anything else is an
/// explicit settings choice.
ProviderScope _appScope({ThemeMode? themeMode}) =>
    appScope(themeMode: themeMode);

void main() {
  // Light OS surface: the dispatcher defaults to light (no test value is
  // set), and the light look is today's baseline. The whole family shares
  // the _appScope above, so the former file's identical wrapper dropped
  // away with the merge.
  testWidgets('light OS setting keeps the app light (today\'s look)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(materializedBrightness(tester), Brightness.light);
  });

  testWidgets('system default follows the device brightness (dark device)', (
    WidgetTester tester,
  ) async {
    useDarkDeviceBrightness(tester);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(
      materializedBrightness(tester),
      Brightness.dark,
      reason: 'The default must be System: follow the device brightness',
    );
  });

  testWidgets('explicit dark choice wins over a light device', (
    WidgetTester tester,
  ) async {
    // No test value to set: the dispatcher defaults to light.
    await tester.pumpWidget(_appScope(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(
      materializedBrightness(tester),
      Brightness.dark,
      reason: 'An explicit dark choice must beat the device brightness',
    );
  });

  testWidgets('explicit light choice wins over a dark device', (
    WidgetTester tester,
  ) async {
    useDarkDeviceBrightness(tester);

    await tester.pumpWidget(_appScope(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(
      materializedBrightness(tester),
      Brightness.light,
      reason: 'An explicit light choice must beat the device brightness',
    );
  });

  testWidgets(
    'settings switcher renders System/Light/Dark and switches between them',
    (WidgetTester tester) async {
      // No test value to set: the dispatcher defaults to light.
      await tester.pumpWidget(_appScope());
      await tester.pumpAndSettle();
      // Tap through the shared navigation finder (nav surface, both adaptive
      // surfaces match — see finders.dart): all tabs stay mounted
      // (IndexedStack), so the 'Settings' label also matches the offstage
      // screen's AppBar — and in tree order that AppBar precedes the shell's
      // navigation surface, so a bare .first tap would miss.
      await tester.tap(navLabel('Settings'));
      await tester.pumpAndSettle();

      // The keyed switcher (the language switcher also renders in the
      // settings pane; scoping by key keeps this one unambiguous).
      final themeSwitcher = settingsThemeSwitcher();
      expect(
        themeSwitcher,
        findsOneWidget,
        reason: 'The theme-mode switcher must be on the settings screen',
      );
      final switcher = tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher);
      expect(switcher.segments.map((segment) => segment.value), [
        ThemeMode.system,
        ThemeMode.light,
        ThemeMode.dark,
      ], reason: 'The switcher must offer System, Light and Dark');
      expect(switcher.selected, {
        ThemeMode.system,
      }, reason: 'The default selection must be "System"');

      // Switching to dark applies it immediately, overriding the light device.
      await tester.tap(settingsThemeSegment('dark'));
      await tester.pumpAndSettle();
      expect(
        materializedBrightness(tester),
        Brightness.dark,
        reason: 'Selecting Dark must switch the app to dark immediately',
      );
      final switcher2 = tester.widget<SegmentedButton<ThemeMode>>(
        themeSwitcher,
      );
      expect(switcher2.selected, {ThemeMode.dark});

      // Back to light explicitly.
      await tester.tap(settingsThemeSegment('light'));
      await tester.pumpAndSettle();
      expect(
        materializedBrightness(tester),
        Brightness.light,
        reason: 'Selecting Light must switch the app to light immediately',
      );
      final switcher3 = tester.widget<SegmentedButton<ThemeMode>>(
        themeSwitcher,
      );
      expect(switcher3.selected, {ThemeMode.light});

      // Back to the system default: the light device brightness returns.
      await tester.tap(settingsThemeSegment('system'));
      await tester.pumpAndSettle();
      expect(
        materializedBrightness(tester),
        Brightness.light,
        reason: 'Selecting System must follow the device brightness again',
      );
      final switcher4 = tester.widget<SegmentedButton<ThemeMode>>(
        themeSwitcher,
      );
      expect(switcher4.selected, {ThemeMode.system});
    },
  );
}
