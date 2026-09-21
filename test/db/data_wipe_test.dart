// The delete-all wipe behind the settings pane's "Daten löschen" card.
//
// The wipe clears the TRACKED data — cycle_entries and user_marks, both
// tables inside ONE transaction. The app_settings table deliberately
// SURVIVES: its rows are user choices (language, theme, temperature
// range…), and the onboarding flag must stay so the completed welcome page
// does not replay after a data wipe.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CycleDatabase db;

  setUp(() {
    db = CycleDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<void> seedTrackedData() async {
    await db.entriesDao.upsertDaily(DailyEntry(
        date: DateTime.utc(2026, 9, 6), bbtC: 36.4, bleeding: Bleeding.light));
    await db.entriesDao
        .upsertDaily(DailyEntry(date: DateTime.utc(2026, 9, 7), bbtC: 36.5));
    await db.marksDao
        .addMark(DateTime.utc(2026, 9, 6), CycleMarkTypes.cycleStart);
    await db.marksDao
        .addMark(DateTime.utc(2026, 9, 12), CycleMarkTypes.mucusPeakDay);
  }

  group('deleteAllTrackedData (entries + marks tables, settings survive)', () {
    test('empties the entries and marks tables and reports the counts',
        () async {
      await seedTrackedData();
      expect(await db.entriesDao.allEntries(), hasLength(2));
      expect(await db.marksDao.allMarks(), hasLength(2));

      final counts = await db.deleteAllTrackedData();
      expect(counts.entries, 2,
          reason: 'the reported count is the number '
              'of REMOVED entry rows');
      expect(counts.marks, 2);
      expect(await db.entriesDao.allEntries(), isEmpty,
          reason: 'after the wipe the entries table is empty');
      expect(await db.marksDao.allMarks(), isEmpty,
          reason: 'after the wipe the marks table is empty');
    });

    test('app_settings rows survive the wipe (onboarding flag included)',
        () async {
      await seedTrackedData();
      await db.settingsDao.writeValue(SettingKeys.onboardingCompleted, 'true');
      await db.settingsDao.writeValue('locale', '"de"');

      await db.deleteAllTrackedData();

      expect(await db.settingsDao.readValue(SettingKeys.onboardingCompleted),
          'true',
          reason: 'the onboarding flag is a settings row, NOT tracked data: '
              'it must stay so the welcome page does not replay after a '
              'data wipe');
      expect(await db.settingsDao.readValue('locale'), '"de"',
          reason: 'settings are user choices — the data wipe only resets '
              'the diary of observations, never the preferences');
    });

    test('an empty database wipes without error and reports empty counts',
        () async {
      final counts = await db.deleteAllTrackedData();
      expect(counts.entries, 0);
      expect(counts.marks, 0);
      expect(await db.entriesDao.allEntries(), isEmpty);
      expect(await db.marksDao.allMarks(), isEmpty);
    });
  });
}
