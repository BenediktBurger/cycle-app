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
import 'package:cycle_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

/// The currently picked value of one of the range pickers (the form field
/// wraps a DropdownButton that carries the value).
double? _pickerValue(WidgetTester tester, ValueKey<String> key) => tester
    .widget<DropdownButton<double>>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(DropdownButton<double>),
      ),
    )
    .value;

void main() {
  group('observed cycles outside the app', () {
    testWidgets('a persisted outside-app count hydrates into the settings '
        'field on start', (WidgetTester tester) async {
      useDeviceLocales(tester, const [Locale('de')]);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistObservedCyclesOutsideApp(5);

      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('observedCyclesOutsideAppField'));
      expect(
        field,
        findsOneWidget,
        reason: 'the outside-app cycles card renders an integer field',
      );
      final textField = tester.widget<TextField>(field);
      expect(
        textField.controller!.text,
        '5',
        reason:
            'the stored count of 5 must appear in the field after the '
            'database opens',
      );
    });

    testWidgets('entering a count writes through as an integer row, an '
        'invalid entry does not (validation 0 <= n)', (
      WidgetTester tester,
    ) async {
      useDeviceLocales(tester, const [Locale('de')]);

      CycleDatabase? db;
      await tester.pumpWidget(
        appScope(
          locale: const Locale('de'),
          onCreated: (created) => db = created,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('observedCyclesOutsideAppField'));
      await tester.enterText(field, '3');
      await tester.pumpAndSettle();

      final store = SettingsStore(db!.settingsDao);
      expect(
        await store.readSetting(SettingKeys.observedCyclesOutsideApp),
        3,
        reason:
            'a valid non-negative integer is written through to '
            'app_settings as a JSON integer',
      );

      // Invalid input: negative and non-integer entries must not write, and
      // the field surfaces the validation error.
      await tester.enterText(field, '-2');
      await tester.pumpAndSettle();
      expect(
        await store.readSetting(SettingKeys.observedCyclesOutsideApp),
        3,
        reason: 'a negative entry is rejected and never written',
      );
      expect(
        find.byKey(const ValueKey('observedCyclesOutsideAppFieldError')),
        findsOneWidget,
        reason: 'the validation error is visible for the rejected entry',
      );

      await tester.enterText(field, '2.5');
      await tester.pumpAndSettle();
      expect(
        await store.readSetting(SettingKeys.observedCyclesOutsideApp),
        3,
        reason: 'a non-integer entry is rejected and never written',
      );

      await tester.enterText(field, '9');
      await tester.pumpAndSettle();
      expect(
        await store.readSetting(SettingKeys.observedCyclesOutsideApp),
        9,
        reason: 'a corrected entry writes through again',
      );
      expect(
        find.byKey(const ValueKey('observedCyclesOutsideAppFieldError')),
        findsNothing,
        reason: 'the error clears once the entry is valid again',
      );
    });

    testWidgets(
      'an external value change resyncs the untouched field and stops '
      'resyncing once the user has typed',
      (WidgetTester tester) async {
        useDeviceLocales(tester, const [Locale('de')]);

        await tester.pumpWidget(appScope(locale: const Locale('de')));
        await tester.pumpAndSettle();

        await tester.tap(navLabel('Einstellungen'));
        await tester.pumpAndSettle();

        final field = find.byKey(
          const ValueKey('observedCyclesOutsideAppField'),
        );
        final container = ProviderScope.containerOf(tester.element(field));
        expect(
          tester.widget<TextField>(field).controller!.text,
          '0',
          reason: 'the field starts at the provider default',
        );

        // A write from outside the field itself changes the provider state
        // while the field has not been touched: the visible text follows.
        container.read(observedCyclesOutsideAppProvider.notifier).state = 7;
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field).controller!.text,
          '7',
          reason: 'an external change must appear in the untouched field',
        );

        // After the user types, the visible text belongs to the user: an
        // external change must not clobber mid-entry.
        await tester.enterText(field, '3');
        await tester.pumpAndSettle();
        container.read(observedCyclesOutsideAppProvider.notifier).state = 11;
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field).controller!.text,
          '3',
          reason: 'an external change must not overwrite an edited field',
        );
      },
    );
  });

  group('hydration', () {
    testWidgets('persisted choices are restored into the UI on start', (
      WidgetTester tester,
    ) async {
      // An English device on purpose: the stored non-default choices must
      // beat the device defaults, not merely repeat them.
      useDeviceLocales(tester, const [Locale('en')]);

      Future<void> seed(CycleDatabase db) async {
        final store = SettingsStore(db.settingsDao);
        await store.persistLocale(const Locale('de'));
        await store.persistThemeMode(ThemeMode.dark);
        await store.persistTemperatureRange(
          const TemperatureRange(min: 35.0, max: 39.0),
        );
      }

      await tester.pumpWidget(appScope(seed: seed));
      await tester.pumpAndSettle();

      expect(
        find.text('Tagebuch'),
        findsWidgets,
        reason:
            'the stored German choice must apply over the English '
            'device locale',
      );
      expect(find.text('Diary'), findsNothing);
      expect(
        materializedBrightness(tester),
        Brightness.dark,
        reason:
            'the stored dark choice must apply over the light test '
            'surface',
      );

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<String>>(settingsLanguageSwitcher())
            .selected,
        const {'de'},
        reason: 'the stored language choice must appear in the switcher',
      );
      expect(
        tester
            .widget<SegmentedButton<ThemeMode>>(settingsThemeSwitcher())
            .selected,
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

    testWidgets('a live explicit choice is not clobbered by hydration', (
      WidgetTester tester,
    ) async {
      useDeviceLocales(tester, const [Locale('de')]);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistLocale(const Locale('de'));

      // The appScope override stands for an (older) live choice: English
      // was applied while the stored snapshot says German — the stored
      // snapshot must not overwrite it.
      await tester.pumpWidget(appScope(locale: const Locale('en'), seed: seed));
      await tester.pumpAndSettle();

      expect(
        find.text('Diary'),
        findsWidgets,
        reason:
            'an already-set choice must never be overwritten by the '
            'hydrated snapshot',
      );
      expect(find.text('Tagebuch'), findsNothing);
    });
  });

  group('write-through', () {
    testWidgets('settings-screen choices land in app_settings as JSON rows', (
      WidgetTester tester,
    ) async {
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
      await tester.tap(settingsLanguageSegment('en'));
      await tester.pumpAndSettle();

      // Theme to Dark.
      await tester.tap(settingsThemeSegment('dark'));
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
      expect(
        await store.readSetting(SettingKeys.locale),
        'en',
        reason:
            'the language choice must persist as a JSON-encoded '
            'language code',
      );
      expect(
        await store.readSetting(SettingKeys.themeMode),
        'dark',
        reason: 'the theme choice must persist as the enum-name token',
      );
      expect(await store.readSetting(SettingKeys.temperatureRange), {
        'min': 35.0,
        'max': 39.0,
      }, reason: 'the range choice must persist as its JSON map');
    });
  });

  group('PDF export identifying values (name & birth date)', () {
    // The settings pane is one scroll list; the PDF-export card sits low
    // (below the outside-app cycle-count card), so both tests render the
    // full pane height in one viewport instead of scrolling into position.
    Future<void> enlargeViewport(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('a persisted name and birth date hydrate into the '
        'PDF-export card on start', (WidgetTester tester) async {
      await enlargeViewport(tester);
      useDeviceLocales(tester, const [Locale('de')]);

      Future<void> seed(CycleDatabase db) async {
        final store = SettingsStore(db.settingsDao);
        await store.persistPdfExportName('Ada Lovelace');
        await store.persistPdfExportBirthDate(DateTime(1990, 1, 2));
      }

      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      final nameField = find.byKey(const ValueKey('pdfExportNameField'));
      expect(
        nameField,
        findsOneWidget,
        reason: 'the PDF-export card renders the name field',
      );
      expect(
        tester.widget<TextField>(nameField).controller!.text,
        'Ada Lovelace',
        reason:
            'the stored name must appear in the field after the '
            'database opens',
      );

      final dateField = find.byKey(const ValueKey('pdfExportBirthDateField'));
      expect(
        tester.widget<TextField>(dateField).controller!.text,
        '1990-01-02',
        reason:
            'the stored birth date appears as the ISO date string the '
            'field exchanges',
      );
    });

    testWidgets('name and birth date write through; an invalid date stays '
        'local (error line, no row write)', (WidgetTester tester) async {
      await enlargeViewport(tester);
      useDeviceLocales(tester, const [Locale('de')]);

      CycleDatabase? db;
      await tester.pumpWidget(appScope(onCreated: (created) => db = created));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('pdfExportNameField')),
        'Ada',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pdfExportBirthDateField')),
        '1990-01-02',
      );
      await tester.pumpAndSettle();

      final store = SettingsStore(db!.settingsDao);
      expect(
        await store.readSetting(SettingKeys.pdfExportName),
        'Ada',
        reason:
            'a valid name writes through to app_settings as a JSON '
            'string',
      );
      expect(
        await store.readSetting(SettingKeys.pdfExportBirthDate),
        '1990-01-02',
        reason: 'a valid birth date writes through as the ISO date string',
      );

      // Invalid: not a real day. The error line shows, the stored value
      // keeps standing.
      await tester.enterText(
        find.byKey(const ValueKey('pdfExportBirthDateField')),
        '1990-02-30',
      );
      await tester.pumpAndSettle();
      expect(
        await store.readSetting(SettingKeys.pdfExportBirthDate),
        '1990-01-02',
        reason: 'an invalid date entry is rejected and never written',
      );
      expect(
        find.byKey(const ValueKey('pdfExportBirthDateFieldError')),
        findsOneWidget,
        reason: 'the validation error is visible for the rejected entry',
      );

      await tester.enterText(
        find.byKey(const ValueKey('pdfExportBirthDateField')),
        '2001-03-15',
      );
      await tester.pumpAndSettle();
      expect(
        await store.readSetting(SettingKeys.pdfExportBirthDate),
        '2001-03-15',
        reason: 'a corrected entry writes through again',
      );
      expect(
        find.byKey(const ValueKey('pdfExportBirthDateFieldError')),
        findsNothing,
        reason: 'the error clears once the entry is valid again',
      );
    });
  });
}
