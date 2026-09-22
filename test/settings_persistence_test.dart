// Settings persistence end-to-end: the three general settings (language,
// theme mode, temperature range) survive an app restart. The tests pump the
// REAL CycleApp against the in-memory drift database override (appScope): a
// seeded app_settings table must be hydrated into the UI after the database
// opens, a live choice must never be clobbered by hydration, and
// settings-screen choices must be written back through to that table.
//
// The platform locale is simulated through the test binding's dispatcher
// (same pattern as locale_test.dart), so hydration and write-through both
// act on deliberate choices rather than on the system default. The
// provider-level unit behavior of the store itself is pinned in
// test/db/settings_store_test.dart.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

/// The currently picked value of one of the range pickers (the form field
/// wraps a DropdownButton that carries the value).
double? _pickerValue(WidgetTester tester, ValueKey<String> key) => tester
    .widget<DropdownButton<double>>(find.descendant(
        of: find.byKey(key), matching: find.byType(DropdownButton<double>)))
    .value;

void main() {
  group('hydration', () {
    testWidgets('persisted choices are restored into the UI on start',
        (WidgetTester tester) async {
      // An English device on purpose: the stored non-default choices must
      // beat the device defaults, not merely repeat them.
      useDeviceLocales(tester, const [Locale('en')]);

      Future<void> seed(CycleDatabase db) async {
        final store = SettingsStore(db.settingsDao);
        await store.persistLocale(const Locale('de'));
        await store.persistThemeMode(ThemeMode.dark);
        await store.persistTemperatureRange(
            const TemperatureRange(min: 35.0, max: 39.0));
      }

      await tester.pumpWidget(appScope(seed: seed));
      await tester.pumpAndSettle();

      expect(find.text('Tagebuch'), findsWidgets,
          reason: 'the stored German choice must apply over the English '
              'device locale');
      expect(find.text('Diary'), findsNothing);
      expect(materializedBrightness(tester), Brightness.dark,
          reason: 'the stored dark choice must apply over the light test '
              'surface');

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      final languageSwitcher = find.byType(SegmentedButton<String>);
      expect(
        tester.widget<SegmentedButton<String>>(languageSwitcher).selected,
        const {'de'},
        reason: 'the stored language choice must appear in the switcher',
      );
      final themeSwitcher = find.byType(SegmentedButton<ThemeMode>);
      expect(
        tester.widget<SegmentedButton<ThemeMode>>(themeSwitcher).selected,
        {ThemeMode.dark},
        reason: 'the stored theme choice must appear in the switcher',
      );
      expect(
        _pickerValue(tester, const ValueKey('temperatureRangeMin')),
        35.0,
        reason: 'the stored range must show in the lower picker',
      );
      expect(
        _pickerValue(tester, const ValueKey('temperatureRangeMax')),
        39.0,
        reason: 'the stored range must show in the upper picker',
      );
    });

    testWidgets('a live explicit choice is not clobbered by hydration',
        (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistLocale(const Locale('de'));

      // The appScope override stands for an (older) live choice: English
      // was applied while the stored snapshot says German — the stored
      // snapshot must not overwrite it.
      await tester.pumpWidget(appScope(locale: const Locale('en'), seed: seed));
      await tester.pumpAndSettle();

      expect(find.text('Diary'), findsWidgets,
          reason: 'an already-set choice must never be overwritten by the '
              'hydrated snapshot');
      expect(find.text('Tagebuch'), findsNothing);
    });
  });

  group('write-through', () {
    testWidgets('settings-screen choices land in app_settings as JSON rows',
        (WidgetTester tester) async {
      // A German device on purpose: switching to English is then a real
      // change away from the system default (and the starting UI is
      // German, which decides the labels used below).
      useDeviceLocales(tester, const [Locale('de')]);

      CycleDatabase? db;
      await tester.pumpWidget(appScope(onCreated: (created) => db = created));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      // Switch language to English (the UI rebuilds under our fingers —
      // the subsequent lookups use the English labels).
      await tester.tap(find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('English')));
      await tester.pumpAndSettle();

      // Theme to Dark.
      await tester.tap(find.descendant(
          of: find.byType(SegmentedButton<ThemeMode>),
          matching: find.text('Dark')));
      await tester.pumpAndSettle();

      // Range to 35–39 °C: lower picker first, then the upper one (the
      // DropdownButtonFormField value proves the write-through read the
      // same way the provider write does in
      // temperature_range_setting_test.dart).
      await tester.tap(find.byKey(const ValueKey('temperatureRangeMin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('35.0 °C').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('temperatureRangeMax')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('39.0 °C').last);
      await tester.pumpAndSettle();

      // The moment the rows get written is not the UI's business: read
      // back through the typed store on the very handle the app opened.
      final store = SettingsStore(db!.settingsDao);
      expect(await store.readSetting(SettingKeys.locale), 'en',
          reason: 'the language choice must persist as a JSON-encoded '
              'language code');
      expect(await store.readSetting(SettingKeys.themeMode), 'dark',
          reason: 'the theme choice must persist as the enum-name token');
      expect(await store.readSetting(SettingKeys.temperatureRange),
          {'min': 35.0, 'max': 39.0},
          reason: 'the range choice must persist as its JSON map');
    });
  });
}
