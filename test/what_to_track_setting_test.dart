// The "What to track" diary-settings card: end-to-end (the REAL CycleApp
// against the in-memory drift database override, same shape as
// settings_persistence_test.dart) — defaults on a fresh start, a switch
// flip writing through to the app_settings table, a persisted row
// hydrating into the card on restart, and a live choice never clobbered
// by hydration.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/diary_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';

/// The settings pane is one scroll list (a lazy ListView); the cards far
/// down the pane render only when the surface is large enough. Same
/// reasoning as settings_persistence_test.dart's copy.
Future<void> enlargeViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// The [SwitchListTile] state of one tracked item's settings switch.
bool switchState(WidgetTester tester, DiaryItem item) => tester
    .widget<SwitchListTile>(find.byKey(ValueKey('trackSwitch-${item.name}')))
    .value;

void main() {
  group('What to track card (defaults)', () {
    testWidgets('a fresh start shows the default tracking configuration', (
      WidgetTester tester,
    ) async {
      await enlargeViewport(tester);

      await tester.pumpWidget(appScope(locale: const Locale('de')));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('trackSwitch-mucus')),
        findsOneWidget,
        reason: 'the card renders the mucus switch',
      );
      expect(switchState(tester, DiaryItem.mucus), isTrue);
      expect(
        switchState(tester, DiaryItem.cervix),
        isFalse,
        reason: 'cervix defaults to NOT tracked',
      );
      expect(switchState(tester, DiaryItem.sex), isTrue);
    });
  });

  group('What to track card (write-through)', () {
    testWidgets('flipping switches writes through as the JSON map', (
      WidgetTester tester,
    ) async {
      await enlargeViewport(tester);

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

      // Track the cervix, stop tracking mucus.
      await tester.tap(find.byKey(const ValueKey('trackSwitch-cervix')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('trackSwitch-mucus')));
      await tester.pumpAndSettle();

      final store = SettingsStore(db!.settingsDao);
      expect(await store.readSetting(SettingKeys.diaryTrack), {
        'mucus': false,
        'cervix': true,
        'sex': true,
      }, reason: 'both flips must land in the one diaryTrack JSON row');
    });
  });

  group('What to track card (hydration)', () {
    testWidgets('a persisted diaryTrack row hydrates into the card on start', (
      WidgetTester tester,
    ) async {
      await enlargeViewport(tester);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistDiaryTrack(
            const DiaryTrack(mucus: false, cervix: true, sex: false),
          );

      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      expect(switchState(tester, DiaryItem.mucus), isFalse);
      expect(switchState(tester, DiaryItem.cervix), isTrue);
      expect(switchState(tester, DiaryItem.sex), isFalse);
    });

    testWidgets('hydration cannot clobber a live switch choice', (
      WidgetTester tester,
    ) async {
      await enlargeViewport(tester);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistDiaryTrack(
            const DiaryTrack(mucus: true, cervix: true, sex: true),
          );

      // The pin stands for an older live choice (mucus untracked): the
      // seeded snapshot (cervix tracked) must not overwrite it.
      await tester.pumpWidget(
        appScope(
          locale: const Locale('de'),
          seed: seed,
          diaryTrack: const DiaryTrack(mucus: false, cervix: false, sex: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      expect(
        switchState(tester, DiaryItem.mucus),
        isFalse,
        reason: 'the live choice (mucus untracked) wins over the row',
      );
      expect(
        switchState(tester, DiaryItem.cervix),
        isFalse,
        reason: 'the seeded row must not overwrite the live choice',
      );
    });
  });
}
