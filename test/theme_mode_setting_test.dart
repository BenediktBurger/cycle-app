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
// in this directory). The remaining tests cover the dark surface and the
// explicit light/dark choices.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/settings_switcher.dart';
import 'support/viewport.dart';

/// App scope for the theme-mode tests. A null [themeMode] means: leave the
/// provider at its real default (the "System" option); anything else is an
/// explicit settings choice.
ProviderScope _appScope({ThemeMode? themeMode}) =>
    appScope(themeMode: themeMode);

void main() {
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
      // No test value to set: the dispatcher defaults to light — the System
      // segment follows it, Dark and Light override it.
      await pumpSettingsPane(tester, 'Settings');

      final themeSwitcher = settingsThemeSwitcher();
      expect(
        tester
            .widget<SegmentedButton<ThemeMode>>(themeSwitcher)
            .segments
            .map((segment) => segment.value),
        [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
        reason: 'The switcher must offer System, Light and Dark',
      );

      // Switching applies the choice immediately, overriding the light
      // device; the System step returns to the device brightness.
      await exerciseSwitcher<ThemeMode>(
        tester,
        switcher: themeSwitcher,
        defaultSelected: const {ThemeMode.system},
        steps: [
          SwitcherStep(
            segment: settingsThemeSegment('dark'),
            selected: const {ThemeMode.dark},
            outcome: (tester) async {
              expect(
                materializedBrightness(tester),
                Brightness.dark,
                reason:
                    'Selecting Dark must switch the app to dark immediately',
              );
            },
          ),
          SwitcherStep(
            segment: settingsThemeSegment('light'),
            selected: const {ThemeMode.light},
            outcome: (tester) async {
              expect(
                materializedBrightness(tester),
                Brightness.light,
                reason:
                    'Selecting Light must switch the app to light immediately',
              );
            },
          ),
          SwitcherStep(
            segment: settingsThemeSegment('system'),
            selected: const {ThemeMode.system},
            outcome: (tester) async {
              expect(
                materializedBrightness(tester),
                Brightness.light,
                reason:
                    'Selecting System must follow the device brightness again',
              );
            },
          ),
        ],
      );
    },
  );
}
