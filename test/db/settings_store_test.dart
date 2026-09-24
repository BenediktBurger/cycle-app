// Settings-store tests: the typed layer over the raw key-value DAO —
// JSON-encoded values, the named SettingKeys, typed decode with default
// fallbacks for corrupt/unknown data and the schema-less generic path that
// future settings (no new code, no schema change) rely on.
//
// Pure Dart against NativeDatabase.memory() — no platform channels, no web,
// no widgets (dart:ui's Locale and material's ThemeMode work headless under
// flutter test). Same Linux sqlite note as cycle_database_test.dart:
// package:sqlite3 needs the system sqlite library on Linux.

import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/temperature_range.dart';

void main() {
  // Fresh in-memory database + store for every test (closed in tearDown).
  late CycleDatabase db;
  late SettingsStore store;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    store = SettingsStore(db.settingsDao);
  });

  /// Writes a raw text value under [key], as if an older app version (or a
  /// corrupted write) had stored it: [value] is what ends up in the value
  /// column verbatim — no JSON layer is applied.
  Future<void> seedRaw(String key, String value) =>
      db.settingsDao.writeValue(key, value);

  group('snapshot load', () {
    test('an empty table loads to the pure defaults', () async {
      final snapshot = await store.load();
      expect(snapshot.locale, isNull);
      expect(snapshot.themeMode, ThemeMode.system);
      expect(snapshot.temperatureRange, TemperatureRange.defaults);
    });

    test(
      'unknown keys are ignored on load (no error, no default change)',
      () async {
        await seedRaw('pdfExport.anonymize', 'true');
        await seedRaw('future.thing', '"whatever"');

        final snapshot = await store.load();
        expect(snapshot, isA<PersistedSettings>());
        expect(snapshot, PersistedSettings.defaults());
      },
    );

    test('round-trips all three typed settings in one snapshot', () async {
      await store.persistLocale(const Locale('de'));
      await store.persistThemeMode(ThemeMode.dark);
      await store.persistTemperatureRange(
        const TemperatureRange(min: 35.5, max: 39.0),
      );

      final snapshot = await store.load();
      expect(snapshot.locale, const Locale('de'));
      expect(snapshot.themeMode, ThemeMode.dark);
      expect(
        snapshot.temperatureRange,
        const TemperatureRange(min: 35.5, max: 39.0),
      );

      // Switching everything again must fully replace the snapshot content.
      await store.persistLocale(
        null,
      ); // back to system (row is gone, see below)
      await store.persistThemeMode(ThemeMode.light);
      final reloaded = await store.load();
      expect(
        reloaded.locale,
        isNull,
        reason: 'null locale means "follow the system"',
      );
      expect(reloaded.themeMode, ThemeMode.light);
    });
  });

  group('locale', () {
    test(
      'null/system stores nothing — absent row and default read the same',
      () async {
        await store.persistLocale(null);
        expect(await store.readSetting(SettingKeys.locale), isNull);
        expect(
          await db.select(db.appSettings).get(),
          isEmpty,
          reason: 'the system default is not persisted as a row',
        );
        final snapshot = await store.load();
        expect(snapshot.locale, isNull);
      },
    );

    test('explicit de/en round-trip as Locale objects', () async {
      await store.persistLocale(const Locale('de'));
      final snapshot = await store.load();
      expect(snapshot.locale, const Locale('de'));

      await store.persistLocale(const Locale('en'));
      expect((await store.load()).locale, const Locale('en'));

      // One row per key: switching did not leave a second row behind.
      expect(await db.select(db.appSettings).get(), hasLength(1));
    });

    test('a language code outside {de,en} is stored anyway (ADR-0007 '
        'resolution falls back later)', () async {
      await store.persistLocale(const Locale('fr'));
      final snapshot = await store.load();
      expect(snapshot.locale, const Locale('fr'));
    });
  });

  group('theme mode', () {
    test('each named token round-trips, system included', () async {
      for (final mode in ThemeMode.values) {
        await store.persistThemeMode(mode);
        expect(
          await store.readSetting(SettingKeys.themeMode),
          mode.name,
          reason: '${mode.name} is stored as its JSON string token',
        );
        expect((await store.load()).themeMode, mode);
      }
    });

    test('an unknown stored token falls back to the system default', () async {
      await seedRaw(SettingKeys.themeMode, '"tomato"');
      expect((await store.load()).themeMode, ThemeMode.system);
    });
  });

  group('temperature range', () {
    test('JSON round-trip keeps the chosen 35.5–39.0 window', () async {
      const range = TemperatureRange(min: 35.5, max: 39.0);
      await store.persistTemperatureRange(range);

      final raw = await db.settingsDao.readValue(SettingKeys.temperatureRange);
      expect(
        raw,
        '{"min":35.5,"max":39.0}',
        reason: 'the value column stores the JSON map, exactly',
      );

      final snapshot = await store.load();
      expect(snapshot.temperatureRange, isA<TemperatureRange>());
      expect(snapshot.temperatureRange, range);
    });

    test(
      'TemperatureRange.toJson/fromJson agree with the stored shape',
      () async {
        const range = TemperatureRange(min: 34.0, max: 42.0);
        final restored = TemperatureRange.fromJson(range.toJson());
        expect(restored, range);
      },
    );

    test('wrongly ordered bounds are a store-side ArgumentError', () {
      expect(
        () => TemperatureRange.fromJson(const {'min': 39.0, 'max': 35.5}),
        throwsArgumentError,
      );
    });

    test('bounds outside the 34–42 °C window are rejected as a range', () {
      expect(
        () => TemperatureRange.fromJson(const {'min': 30.0, 'max': 45.0}),
        throwsArgumentError,
      );
      // Mixed: min below the window, max inside — any bound outside the
      // window is invalid, not just a fully out-of-window pair.
      expect(
        () => TemperatureRange.fromJson(const {'min': 30.0, 'max': 39.0}),
        throwsArgumentError,
      );
      // Mirror case: min inside, max above the window.
      expect(
        () => TemperatureRange.fromJson(const {'min': 36.0, 'max': 45.0}),
        throwsArgumentError,
      );
    });

    test('bad range shapes fall back to the default range on load', () async {
      for (final raw in [
        '"opaque string"', // JSON string, not a map
        'garbage{', // not JSON at all
        '{"max":39.0}', // missing min
        '{"min":"35","max":"39"}', // bounds are strings
        '{"min":39.0,"max":35.5}', // wrongly ordered
        '{"min":30.0,"max":45.0}', // both bounds outside the allowed window
        '{"min":30.0,"max":39.0}', // min below the window, max inside
        '[35.5,39.0]', // top-level list instead of an object
      ]) {
        await seedRaw(SettingKeys.temperatureRange, raw);
        expect(
          (await store.load()).temperatureRange,
          TemperatureRange.defaults,
          reason: 'corrupt stored value "$raw" must not surface an error',
        );
      }
    });
  });

  group('observed cycles outside the app (int >= 0)', () {
    test('an empty table loads to 0', () async {
      final snapshot = await store.load();
      expect(snapshot.observedCyclesOutsideApp, 0);
    });

    test(
      'non-negative integers round-trip; an explicit 0 row is fine',
      () async {
        await store.persistObservedCyclesOutsideApp(7);
        expect(
          await store.readSetting(SettingKeys.observedCyclesOutsideApp),
          7,
          reason: 'the value column stores the plain JSON integer',
        );
        expect((await store.load()).observedCyclesOutsideApp, 7);

        await store.persistObservedCyclesOutsideApp(0);
        expect(
          (await store.load()).observedCyclesOutsideApp,
          0,
          reason:
              'an explicit default row is fine — it reads back as the '
              'default (same stance as the system theme row)',
        );
      },
    );

    test('non-integer, negative and corrupt rows fall back to 0', () async {
      for (final raw in [
        '"3"', // JSON string, not an integer
        '2.5', // JSON double
        '-1', // outside the allowed range (int >= 0)
        'true', // JSON bool
        'garbage{', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.observedCyclesOutsideApp, raw);
        expect(
          (await store.load()).observedCyclesOutsideApp,
          0,
          reason:
              'corrupt/negative stored value "$raw" must not surface an '
              'error and must not poison the count',
        );
      }
    });
  });

  group('paper history outside the app (shortest cycle & earliest first '
      'higher, int >= 1)', () {
    test('an empty table loads to no paper values', () async {
      final snapshot = await store.load();
      expect(
        snapshot.shortestCycleLengthOutsideApp,
        isNull,
        reason:
            'an absent row means "not given" — the paper history is '
            'optional',
      );
      expect(snapshot.earliestFirstHigherCycleDayOutsideApp, isNull);
    });

    test(
      'valid integer values round-trip under their dot-family keys',
      () async {
        await store.persistShortestCycleLengthOutsideApp(21);
        expect(
          await store.readSetting(SettingKeys.shortestCycleLengthOutsideApp),
          21,
          reason: 'the value column stores the plain JSON integer',
        );
        await store.persistEarliestFirstHigherCycleDayOutsideApp(14);
        expect(
          await store.readSetting(
            SettingKeys.earliestFirstHigherCycleDayOutsideApp,
          ),
          14,
        );

        final snapshot = await store.load();
        expect(snapshot.shortestCycleLengthOutsideApp, 21);
        expect(snapshot.earliestFirstHigherCycleDayOutsideApp, 14);
        expect(
          await db.select(db.appSettings).get(),
          hasLength(2),
          reason: 'one row per key, no leftovers',
        );
      },
    );

    test('persisting null or a value < 1 deletes the row (cleared reads '
        'the same as absent)', () async {
      // An explicit 0/negative is never a paper fact (the field validates
      // >= 1), so it must not linger as a row that "reads back 0".
      for (final shortest in [null, 0, -3]) {
        await store.persistShortestCycleLengthOutsideApp(21);
        await store.persistShortestCycleLengthOutsideApp(shortest);
        expect(
          await store.readSetting(SettingKeys.shortestCycleLengthOutsideApp),
          isNull,
          reason: 'a cleared/rejected shortest value deletes its row',
        );
      }
      for (final earliest in [null, 0, -1]) {
        await store.persistEarliestFirstHigherCycleDayOutsideApp(14);
        await store.persistEarliestFirstHigherCycleDayOutsideApp(earliest);
        expect(
          await store.readSetting(
            SettingKeys.earliestFirstHigherCycleDayOutsideApp,
          ),
          isNull,
          reason: 'a cleared/rejected cycle-day value deletes its row',
        );
      }
      // Round-trip again after the deletes: a fresh valid value is stored,
      // not blocked by the cleared state.
      await store.persistShortestCycleLengthOutsideApp(26);
      expect((await store.load()).shortestCycleLengthOutsideApp, 26);
    });

    test(
      'out-of-range, non-integer and corrupt rows fall back to null',
      () async {
        for (final raw in [
          '0', // outside the allowed range (int >= 1)
          '-1', // negative
          '"21"', // JSON string, not an integer
          '21.5', // JSON double
          'true', // JSON bool
          'garbage{', // not JSON at all
        ]) {
          await seedRaw(SettingKeys.shortestCycleLengthOutsideApp, raw);
          await seedRaw(SettingKeys.earliestFirstHigherCycleDayOutsideApp, raw);
          final snapshot = await store.load();
          expect(
            snapshot.shortestCycleLengthOutsideApp,
            isNull,
            reason: 'corrupt stored value "$raw" must not surface an error',
          );
          expect(
            snapshot.earliestFirstHigherCycleDayOutsideApp,
            isNull,
            reason: 'corrupt stored value "$raw" must not surface an error',
          );
        }
      },
    );

    test('the snapshot equality covers the paper values', () {
      expect(
        PersistedSettings(shortestCycleLengthOutsideApp: 21),
        isNot(PersistedSettings.defaults()),
      );
      expect(
        PersistedSettings(earliestFirstHigherCycleDayOutsideApp: 14),
        isNot(PersistedSettings.defaults()),
      );
      expect(
        PersistedSettings(shortestCycleLengthOutsideApp: 21),
        PersistedSettings(shortestCycleLengthOutsideApp: 21),
      );
    });
  });

  group('onboarding completion flag (first-start gate)', () {
    test('an empty table loads to not completed', () async {
      final snapshot = await store.load();
      expect(
        snapshot.onboardingCompleted,
        false,
        reason:
            'an absent row means the welcome page has not been seen '
            'yet — it must be shown once',
      );
    });

    test('true round-trips; an explicit false row is kept', () async {
      await store.persistOnboardingCompleted(true);
      expect(
        await store.readSetting(SettingKeys.onboardingCompleted),
        true,
        reason: 'the value column stores the plain JSON boolean',
      );
      expect((await store.load()).onboardingCompleted, true);

      // An explicit false row is only written by a deliberate store user;
      // it must read back the same as the absence of a row.
      await store.persistOnboardingCompleted(false);
      expect((await store.load()).onboardingCompleted, false);
      expect(
        await db.select(db.appSettings).get(),
        hasLength(1),
        reason: 'the persisted row is stored, one row per key',
      );
    });

    test('corrupt rows fall back to not completed', () async {
      for (final raw in [
        '"true"', // JSON string, not a boolean
        '1', // JSON number
        'garbage{', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.onboardingCompleted, raw);
        expect(
          (await store.load()).onboardingCompleted,
          false,
          reason:
              'corrupt stored value "$raw" must not surface an error '
              'and must replay the welcome page rather than skip it',
        );
      }
    });
  });

  group('generic JSON path (future settings without any code change)', () {
    test(
      'a bool setting round-trips with no typed helper and no schema edit',
      () async {
        await store.writeSetting('pdfExport.anonymize', true);
        expect(await store.readSetting('pdfExport.anonymize'), true);
        // With the typed layer: writeSetting writes the JSON-encoded text.
        expect(await db.settingsDao.readValue('pdfExport.anonymize'), 'true');
      },
    );

    test('every JSON-native type can ride the generic path', () async {
      await store.writeSetting('pdfExport.name', 'B. Beispiel');
      await store.writeSetting('pdfExport.count', 12);
      await store.writeSetting('pdfExport.parts', {
        'name': 'x',
        'cycles': [1, 2],
      });

      expect(await store.readSetting('pdfExport.name'), 'B. Beispiel');
      expect(await store.readSetting('pdfExport.count'), 12);
      expect(await store.readSetting('pdfExport.parts'), {
        'name': 'x',
        'cycles': [1, 2],
      });
    });

    test('writing null deletes the row (delete-verb semantics)', () async {
      await store.writeSetting('pdfExport.anonymize', true);
      await store.writeSetting('pdfExport.anonymize', null);
      expect(await store.readSetting('pdfExport.anonymize'), isNull);
      expect(await db.select(db.appSettings).get(), isEmpty);
    });

    test('reading an absent key returns null without error', () async {
      expect(await store.readSetting('neverWritten.key'), isNull);
    });
  });

  group('PDF export identifying values (name & birth date)', () {
    test('an empty table loads to no name and no birth date', () async {
      final snapshot = await store.load();
      expect(snapshot.pdfExportName, isNull);
      expect(snapshot.pdfExportBirthDate, isNull);
    });

    test(
      'a name round-trips as a JSON string under the dot-family key',
      () async {
        await store.persistPdfExportName('Ada Lovelace');
        expect(
          await store.readSetting(SettingKeys.pdfExportName),
          'Ada Lovelace',
          reason: 'the name column stores the plain JSON string',
        );
        expect((await store.load()).pdfExportName, 'Ada Lovelace');
      },
    );

    test('persisting null or blank deletes the name row', () async {
      await store.persistPdfExportName('Ada');
      await store.persistPdfExportName('   ');
      expect(
        await store.readSetting(SettingKeys.pdfExportName),
        isNull,
        reason:
            'a whitespace-only name is NOT stored as identifying '
            'value — the settings row is deleted',
      );
      expect(await db.select(db.appSettings).get(), isEmpty);
    });

    test('non-string and corrupt name rows fall back to no name', () async {
      for (final raw in [
        '3', // JSON number
        '"   "', // whitespace-only string
        'true', // JSON bool
        '"[" + "broken', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.pdfExportName, raw);
        expect(
          (await store.load()).pdfExportName,
          isNull,
          reason: 'corrupt stored value "$raw" must not surface an error',
        );
      }
    });

    test('a birth date round-trips as the ISO date string and loads as a '
        'DateOnly-normalized day', () async {
      await store.persistPdfExportBirthDate(DateTime(1990, 1, 2));
      expect(
        await store.readSetting(SettingKeys.pdfExportBirthDate),
        '1990-01-02',
        reason: 'the birth date stores as the plain ISO date string',
      );
      final loaded = (await store.load()).pdfExportBirthDate;
      expect(
        loaded,
        DateTime.utc(1990, 1, 2),
        reason:
            'the decoded value is the calendar day, UTC-midnight '
            'normalized (DateOnly convention)',
      );
    });

    test('non-date and corrupt birth-date rows fall back to no date', () async {
      for (final raw in [
        '"1990-02-30"', // a JSON date string that is not a real day
        '"not-a-date"', // JSON string, not a date
        '19900102', // JSON number
        'garbage{', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.pdfExportBirthDate, raw);
        expect(
          (await store.load()).pdfExportBirthDate,
          isNull,
          reason: 'corrupt stored value "$raw" must not surface an error',
        );
      }
    });

    test('both identifying values load in one snapshot', () async {
      await store.persistPdfExportName('Ada');
      await store.persistPdfExportBirthDate(DateTime(1990, 1, 2));
      final snapshot = await store.load();
      expect(snapshot.pdfExportName, 'Ada');
      expect(snapshot.pdfExportBirthDate, DateTime.utc(1990, 1, 2));
    });
  });
}
