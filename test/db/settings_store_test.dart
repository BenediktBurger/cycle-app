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
import 'package:cycle_app/domain/backup_reminder.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:cycle_app/domain/diary_track.dart';
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

  group('what to track (diary section visibility family)', () {
    test('an empty table loads to the diary-track defaults', () async {
      final snapshot = await store.load();
      expect(snapshot.diaryTrack, DiaryTrack.defaults);
    });

    test('the track map round-trips under its key', () async {
      const tracked = DiaryTrack(mucus: false, cervix: true, sex: false);
      await store.persistDiaryTrack(tracked);
      expect(
        await db.settingsDao.readValue(SettingKeys.diaryTrack),
        '{"temperature":true,"mucus":false,"cervix":true,"sex":false,"pain":true}',
        reason: 'the value column stores the JSON map, exactly',
      );
      final snapshot = await store.load();
      expect(snapshot.diaryTrack, tracked);
      expect(await db.select(db.appSettings).get(), hasLength(1));
    });

    test(
      'a corrupt or mistyped row degrades item-by-item to the defaults',
      () async {
        final expectations = <(String, DiaryTrack)>[
          ('"opaque string"', DiaryTrack.defaults), // string, not a map
          ('garbage{', DiaryTrack.defaults), // not JSON at all
          ('[true,false,true]', DiaryTrack.defaults), // list, not an object
          // Only the mistyped item degrades; the valid ones stand.
          ('{"mucus":"yes","cervix":true}', const DiaryTrack(cervix: true)),
          ('{"mucus":true,"cervix":2}', const DiaryTrack(mucus: true)),
          (
            '{"mucus":true,"cervix":true,"sex":"x"}',
            const DiaryTrack(mucus: true, cervix: true),
          ),
        ];
        for (final (raw, expected) in expectations) {
          await seedRaw(SettingKeys.diaryTrack, raw);
          expect(
            (await store.load()).diaryTrack,
            expected,
            reason: 'corrupt stored value "$raw" must not surface an error',
          );
        }
      },
    );
  });

  group('custom diary categories (definitions family)', () {
    test('an empty table loads to no categories', () async {
      final snapshot = await store.load();
      expect(snapshot.customDiaryCategories, isEmpty);
    });

    test(
      'the definitions round-trip as the JSON list under their key',
      () async {
        const definitions = [
          CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']),
          CustomCategory(name: 'Medikamente', visible: false),
        ];
        await store.persistCustomCategories(definitions);
        expect(
          await db.settingsDao.readValue(SettingKeys.customDiaryCategories),
          '[{"name":"Sport","visible":true,"items":["Joggen","Kraft"]},'
          '{"name":"Medikamente","visible":false,"items":[]}]',
          reason: 'the value column stores the JSON list, exactly',
        );
        final snapshot = await store.load();
        expect(snapshot.customDiaryCategories, definitions);
        expect(await db.select(db.appSettings).get(), hasLength(1));
      },
    );

    test(
      'persisting an empty list deletes the row (absent == cleared)',
      () async {
        await store.persistCustomCategories(const [
          CustomCategory(name: 'Sport'),
        ]);
        await store.persistCustomCategories(const []);
        expect(
          await store.readSetting(SettingKeys.customDiaryCategories),
          isNull,
          reason: 'an empty definitions list must not linger as a row',
        );
        expect(await db.select(db.appSettings).get(), isEmpty);
      },
    );

    test(
      'a corrupt row keeps the default while other keys stay unaffected',
      () async {
        await store.persistDiaryTrack(const DiaryTrack(mucus: false));
        for (final raw in [
          '"opaque string"', // JSON string, not a list
          'garbage{', // not JSON at all
          '5', // JSON number, not a list
          '[true, 42, "Sport"]', // a list without any map member
        ]) {
          await seedRaw(SettingKeys.customDiaryCategories, raw);
          final snapshot = await store.load();
          expect(
            snapshot.customDiaryCategories,
            isEmpty,
            reason: 'corrupt stored value "$raw" must not surface an error',
          );
          expect(
            snapshot.diaryTrack,
            const DiaryTrack(mucus: false),
            reason: 'a corrupt row degrades only its own key',
          );
        }
      },
    );

    test('junk list members are skipped; valid members still decode', () async {
      await seedRaw(
        SettingKeys.customDiaryCategories,
        '[{"name":"Sport","items":["Joggen"]}, "junk", 42]',
      );
      expect((await store.load()).customDiaryCategories, const [
        CustomCategory(name: 'Sport', items: ['Joggen']),
      ]);
    });

    test('mistyped fields inside a stored map fall back per field', () async {
      await seedRaw(
        SettingKeys.customDiaryCategories,
        '[{"name":"Sport","visible":"yes","items":"Joggen"}]',
      );
      expect(
        (await store.load()).customDiaryCategories,
        const [CustomCategory(name: 'Sport')],
        reason:
            'the per-field leniency of CustomCategory.fromJson applies '
            'to stored rows too',
      );
    });
  });

  group('backup reminder and export tracking', () {
    test('an empty table loads the documented defaults', () async {
      final snapshot = await store.load();
      expect(snapshot.lastExportAt, isNull);
      expect(
        snapshot.backupReminderInterval,
        BackupReminderInterval.quarterly,
        reason: 'quarterly is the default without an explicit row',
      );
      expect(snapshot.backupReminderSnoozedUntil, isNull);
    });

    test('every interval token round-trips', () async {
      for (final interval in BackupReminderInterval.values) {
        await store.persistBackupReminderInterval(interval);
        expect(
          await store.readSetting(SettingKeys.backupReminderInterval),
          interval.name,
          reason: '${interval.name} is stored as its enum-name token',
        );
        expect((await store.load()).backupReminderInterval, interval);
      }
    });

    test('unknown, non-string and corrupt interval rows decode to '
        'quarterly', () async {
      for (final raw in [
        '"weekly"', // a token that is not one of the four presets
        '"Off"', // wrong case is not a token
        '3', // JSON number, not a string token
        'true', // JSON bool
        'garbage{', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.backupReminderInterval, raw);
        expect(
          (await store.load()).backupReminderInterval,
          BackupReminderInterval.quarterly,
          reason: 'corrupt stored value "$raw" must keep the default',
        );
      }
    });

    test('timestamps round-trip as ISO strings normalized to UTC', () async {
      final exportedAt = DateTime.utc(2026, 1, 15, 10, 30);
      await store.persistLastExportAt(exportedAt);
      expect(
        await store.readSetting(SettingKeys.lastExportAt),
        exportedAt.toIso8601String(),
        reason: 'the value column stores the plain ISO timestamp string',
      );
      final loadedExport = (await store.load()).lastExportAt;
      expect(loadedExport, exportedAt);
      expect(loadedExport!.isUtc, isTrue);

      final snoozedUntil = DateTime.utc(2026, 2, 1);
      await store.persistBackupReminderSnoozedUntil(snoozedUntil);
      expect(
        await store.readSetting(SettingKeys.backupReminderSnoozedUntil),
        snoozedUntil.toIso8601String(),
      );
      final loadedSnooze = (await store.load()).backupReminderSnoozedUntil;
      expect(loadedSnooze, snoozedUntil);
      expect(loadedSnooze!.isUtc, isTrue);
    });

    test(
      'a stored timestamp with an offset loads as the same UTC instant',
      () async {
        await seedRaw(SettingKeys.lastExportAt, '"2026-01-15T10:30:00+02:00"');
        final loaded = (await store.load()).lastExportAt;
        expect(loaded, DateTime.utc(2026, 1, 15, 8, 30));
        expect(loaded!.isUtc, isTrue);
      },
    );

    test('non-string and unparsable timestamp rows decode to null', () async {
      for (final raw in [
        '123', // JSON number
        'true', // JSON bool
        '"not-a-date"', // JSON string, not an instant
        '"2026-13-45T00:00:00Z"', // ISO-shaped but not a real instant
        'null', // JSON null
        'garbage{', // not JSON at all
      ]) {
        await seedRaw(SettingKeys.lastExportAt, raw);
        await seedRaw(SettingKeys.backupReminderSnoozedUntil, raw);
        final snapshot = await store.load();
        expect(
          snapshot.lastExportAt,
          isNull,
          reason: 'corrupt stored value "$raw" must not surface an error',
        );
        expect(
          snapshot.backupReminderSnoozedUntil,
          isNull,
          reason: 'corrupt stored value "$raw" must not surface an error',
        );
      }
    });

    test(
      'one corrupt reminder row leaves the other settings untouched',
      () async {
        final exportedAt = DateTime.utc(2026, 1, 15, 10, 30);
        final snoozedUntil = DateTime.utc(2026, 2, 1);
        await store.persistLastExportAt(exportedAt);
        await store.persistBackupReminderSnoozedUntil(snoozedUntil);
        await seedRaw(SettingKeys.backupReminderInterval, '"weekly"');

        final snapshot = await store.load();
        expect(
          snapshot.backupReminderInterval,
          BackupReminderInterval.quarterly,
        );
        expect(
          snapshot.lastExportAt,
          exportedAt,
          reason: 'a corrupt row degrades only its own key',
        );
        expect(snapshot.backupReminderSnoozedUntil, snoozedUntil);
      },
    );

    test('snapshots differing only in a reminder field are unequal', () async {
      const defaults = PersistedSettings.defaults();
      final otherExport = PersistedSettings(
        lastExportAt: DateTime.utc(2026, 1, 15),
      );
      final otherInterval = PersistedSettings(
        backupReminderInterval: BackupReminderInterval.off,
      );
      final otherSnooze = PersistedSettings(
        backupReminderSnoozedUntil: DateTime.utc(2026, 2, 1),
      );

      expect(otherExport == defaults, isFalse);
      expect(otherInterval == defaults, isFalse);
      expect(otherSnooze == defaults, isFalse);
      expect(
        otherExport ==
            PersistedSettings(lastExportAt: DateTime.utc(2026, 1, 15)),
        isTrue,
      );
      expect(
        otherExport.hashCode,
        PersistedSettings(lastExportAt: DateTime.utc(2026, 1, 15)).hashCode,
      );
    });

    test(
      'a null write deletes its row and an explicit off row persists',
      () async {
        await store.persistLastExportAt(DateTime.utc(2026, 1, 15));
        await store.persistLastExportAt(null);
        expect(
          await store.readSetting(SettingKeys.lastExportAt),
          isNull,
          reason: 'a cleared export instant must not linger as a row',
        );

        await store.persistBackupReminderSnoozedUntil(DateTime.utc(2026, 2, 1));
        await store.persistBackupReminderSnoozedUntil(null);
        expect(
          await store.readSetting(SettingKeys.backupReminderSnoozedUntil),
          isNull,
        );

        await store.persistBackupReminderInterval(BackupReminderInterval.off);
        expect(
          await store.readSetting(SettingKeys.backupReminderInterval),
          'off',
          reason: 'an explicit off choice is a real row, not an absent one',
        );
        expect(
          (await store.load()).backupReminderInterval,
          BackupReminderInterval.off,
        );
        expect(
          await db.select(db.appSettings).get(),
          hasLength(1),
          reason: 'only the explicit off row remains',
        );
      },
    );
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
        '"[broken', // unterminated JSON string
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
