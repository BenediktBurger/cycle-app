// Theme-mode setting: the app's color-scheme mode (light / dark / system)
// is selectable in the settings screen. Mirrors the language switcher
// pattern: an in-memory provider (resets on reload by design — documented
// limitation), default "System" follows the device brightness setting.
//
// The platform brightness is simulated through the test binding's platform
// dispatcher; the app itself is unchanged: in-memory drift database
// override, no platform channels (same pattern as theme_brightness_test.dart
// and locale_default_test.dart).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// App scope for the theme-mode tests. A null [themeMode] means: leave the
/// provider at its real default (the "System" option); anything else is an
/// explicit settings choice.
ProviderScope _appScope({ThemeMode? themeMode}) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          final db = CycleDatabase(
            DatabaseConnection(
              NativeDatabase.memory(),
              closeStreamsSynchronously: true,
            ),
          );
          ref.onDispose(db.close);
          return db;
        }),
        if (themeMode != null) themeModeProvider.overrideWith((ref) => themeMode),
      ],
      child: const CycleApp(),
    );

/// The color-scheme brightness actually materialized by the running app,
/// taken from the shell's Scaffold (below the MaterialApp theme wiring).
Brightness _materializedBrightness(WidgetTester tester) {
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  return Theme.of(scaffoldContext).colorScheme.brightness;
}

void main() {
  testWidgets(
      'system default follows the device brightness (dark device)',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    expect(_materializedBrightness(tester), Brightness.dark,
        reason: 'The default must be System: follow the device brightness');
  });

  testWidgets(
      'explicit dark choice wins over a light device',
      (WidgetTester tester) async {
    // No test value to set: the dispatcher defaults to light.
    await tester.pumpWidget(_appScope(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(_materializedBrightness(tester), Brightness.dark,
        reason: 'An explicit dark choice must beat the device brightness');
  });

  testWidgets(
      'explicit light choice wins over a dark device',
      (WidgetTester tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(_appScope(themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(_materializedBrightness(tester), Brightness.light,
        reason: 'An explicit light choice must beat the device brightness');
  });

  testWidgets(
      'settings switcher renders System/Light/Dark and switches between them',
      (WidgetTester tester) async {
    // No test value to set: the dispatcher defaults to light.
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    // All three options are offered (the language switcher also shows a
    // "System" segment, hence the type-scoped lookup).
    final themeSwitcher =
        find.byType(SegmentedButton<ThemeMode>);
    expect(themeSwitcher, findsOneWidget,
        reason: 'The theme-mode switcher must be on the settings screen');
    expect(
      find.descendant(of: themeSwitcher, matching: find.text('System')),
      findsOneWidget,
      reason: 'Theme option "System" must be offered',
    );
    expect(
      find.descendant(of: themeSwitcher, matching: find.text('Light')),
      findsOneWidget,
      reason: 'Theme option "Light" must be offered',
    );
    expect(
      find.descendant(of: themeSwitcher, matching: find.text('Dark')),
      findsOneWidget,
      reason: 'Theme option "Dark" must be offered',
    );
    final switcher = tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher);
    expect(switcher.selected, {ThemeMode.system},
        reason: 'The default selection must be "System"');

    // Switching to dark applies it immediately, overriding the light device.
    await tester.tap(find.descendant(of: themeSwitcher, matching: find.text('Dark')));
    await tester.pumpAndSettle();
    expect(_materializedBrightness(tester), Brightness.dark,
        reason: 'Selecting Dark must switch the app to dark immediately');
    final switcher2 = tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher);
    expect(switcher2.selected, {ThemeMode.dark});

    // Back to light explicitly.
    await tester.tap(find.descendant(of: themeSwitcher, matching: find.text('Light')));
    await tester.pumpAndSettle();
    expect(_materializedBrightness(tester), Brightness.light,
        reason: 'Selecting Light must switch the app to light immediately');
    final switcher3 = tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher);
    expect(switcher3.selected, {ThemeMode.light});

    // Back to the system default: the light device brightness returns.
    await tester.tap(
        find.descendant(of: themeSwitcher, matching: find.text('System')));
    await tester.pumpAndSettle();
    expect(_materializedBrightness(tester), Brightness.light,
        reason: 'Selecting System must follow the device brightness again');
    final switcher4 = tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher);
    expect(switcher4.selected, {ThemeMode.system});
  });
}
