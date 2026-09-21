// The settings pane's "Daten löschen" card and its confirmation dialog:
// danger-tinted, shows the counts of what will go, an explicit danger
// confirm with CANCEL as the default action, a SnackBar report afterwards,
// and a strong "export first" recommendation. Settings (and the onboarding
// flag) deliberately survive the wipe — see test/db/data_wipe_test.dart.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/marks.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

void main() {
  /// German device, already onboarded, seeded with two tracked days, two
  /// marks and a locale settings row (the locale row proves settings
  /// survive the wipe).
  Future<CycleDatabase> pumpSeededSettingsPane(WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    CycleDatabase? db;
    Future<void> seed(CycleDatabase database) async {
      db = database;
      await database.entriesDao.upsertDaily(DailyEntry(
          date: DateTime.utc(2026, 9, 6),
          bbtC: 36.4,
          bleeding: Bleeding.light));
      await database.entriesDao
          .upsertDaily(DailyEntry(date: DateTime.utc(2026, 9, 7), bbtC: 36.5));
      await database.marksDao
          .addMark(DateTime.utc(2026, 9, 6), CycleMarkTypes.cycleStart);
      await database.marksDao
          .addMark(DateTime.utc(2026, 9, 12), CycleMarkTypes.mucusPeakDay);
      await SettingsStore(database.settingsDao)
          .persistLocale(const Locale('de'));
    }

    await tester.pumpWidget(appScope(
      locale: const Locale('de'),
      onboardingCompleted: true,
      seed: seed,
    ));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();

    // The danger card sits below the fold — scroll it into view.
    await tester.dragUntilVisible(
        find.byKey(const ValueKey('settingsDeleteDataButton')),
        find.byType(ListView),
        const Offset(0, -200));
    await tester.pumpAndSettle();
    return db!;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settingsDeleteDataButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel (the default action) keeps all data',
      (WidgetTester tester) async {
    final db = await pumpSeededSettingsPane(tester);
    await openDialog(tester);

    // The dialog states what will go (the counts of BOTH tables).
    expect(find.textContaining('2 Tagebucheinträge'), findsOneWidget,
        reason: 'the confirmation dialog shows the count of diary entries '
            'to be wiped');
    expect(find.textContaining('2 Markierungen'), findsOneWidget,
        reason: 'the confirmation dialog shows the count of marks to be '
            'wiped');

    // CANCEL is the default: tapping it closes the dialog without any
    // deletion.
    await tester.tap(find.byKey(const ValueKey('deleteDataCancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('deleteDataConfirm')), findsNothing,
        reason: 'cancelling closes the dialog');
    expect(await db.entriesDao.allEntries(), hasLength(2),
        reason: 'cancel must touch nothing');
    expect(await db.marksDao.allMarks(), hasLength(2),
        reason: 'cancel must touch nothing');
  });

  testWidgets(
      'explicit confirm wipes the tracked data, reports via '
      'SnackBar, keeps the settings, and providers re-emit',
      (WidgetTester tester) async {
    final db = await pumpSeededSettingsPane(tester);
    await openDialog(tester);

    await tester.tap(find.byKey(const ValueKey('deleteDataConfirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('gelöscht'), findsOneWidget,
        reason: 'the wipe reports what it did via a SnackBar');
    expect(await db.entriesDao.allEntries(), isEmpty,
        reason: 'the confirm button performs the wipe — the entries table '
            'is empty afterwards');
    expect(await db.marksDao.allMarks(), isEmpty,
        reason: 'the wipe also clears the marks table');
    expect(await db.settingsDao.readValue(SettingKeys.locale), '"de"',
        reason: 'settings survive the wipe (user choices, onboarding flag '
            'included — see the wipe unit tests)');

    // Providers re-emit: the Tagebuch (which watches the entries stream)
    // now shows the empty state instead of the seeded days.
    await tester.tap(navLabel('Tagebuch'));
    await tester.pumpAndSettle();
    // The empty-state line lives in the screen's scrollable below the
    // entry form — bring it into the built viewport range.
    await tester.dragUntilVisible(find.textContaining('Noch keine Einträge'),
        find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch keine Einträge'), findsOneWidget,
        reason: 'the diary screen re-renders the post-wipe state through '
            'the re-emitting entries stream');
  });
}
