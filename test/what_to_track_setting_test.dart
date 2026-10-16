// The "What to track" diary-settings card: end-to-end (the REAL CycleApp
// against the in-memory drift database override, same shape as
// settings_persistence_test.dart) — defaults on a fresh start, a switch
// flip writing through to the app_settings table, and a persisted row
// hydrating into the card on restart. That a live explicit choice is
// never clobbered by hydration is the shared rule pinned in
// settings_persistence_test.dart's hydration group.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/diary_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

/// The [SwitchListTile] state of one tracked item's settings switch.
bool switchState(WidgetTester tester, DiaryItem item) => tester
    .widget<SwitchListTile>(find.byKey(ValueKey('trackSwitch-${item.name}')))
    .value;

void main() {
  group('What to track card (defaults)', () {
    testWidgets('a fresh start shows the default tracking configuration', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester, width: 900);

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
      expect(
        switchState(tester, DiaryItem.pain),
        isTrue,
        reason: 'pain defaults to tracked',
      );
      const temperatureSwitch = ValueKey('trackSwitch-temperature');
      expect(
        find.byKey(temperatureSwitch),
        findsOneWidget,
        reason: 'the card renders the temperature switch',
      );
      expect(
        switchState(tester, DiaryItem.temperature),
        isTrue,
        reason: 'temperature defaults to tracked',
      );
      expect(
        tester.getTopLeft(find.byKey(temperatureSwitch)).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('trackSwitch-mucus'))).dy,
        ),
        reason:
            'temperature is the first switch on the card, matching the '
            'diary form section order',
      );
    });
  });

  group('What to track card (write-through)', () {
    testWidgets('flipping switches writes through as the JSON map', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester, width: 900);

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
        'temperature': true,
        'mucus': false,
        'cervix': true,
        'sex': true,
        'pain': true,
      }, reason: 'all flips must land in the one diaryTrack JSON row');
    });
  });

  group('What to track card (hydration)', () {
    testWidgets('a persisted diaryTrack row hydrates into the card on start', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester, width: 900);

      Future<void> seed(CycleDatabase db) =>
          SettingsStore(db.settingsDao).persistDiaryTrack(
            const DiaryTrack(
              temperature: false,
              mucus: false,
              cervix: true,
              sex: false,
              pain: false,
            ),
          );

      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();

      await tester.tap(navLabel('Einstellungen'));
      await tester.pumpAndSettle();

      expect(switchState(tester, DiaryItem.temperature), isFalse);
      expect(switchState(tester, DiaryItem.mucus), isFalse);
      expect(switchState(tester, DiaryItem.cervix), isTrue);
      expect(switchState(tester, DiaryItem.sex), isFalse);
      expect(switchState(tester, DiaryItem.pain), isFalse);
    });
  });
}
