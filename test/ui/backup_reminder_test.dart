// Widget tests of the backup reminder banner in the real app shell: due
// rendering, both actions, the empty-database and in-memory suppressions, and
// that the settings tab stays reachable. The clock is pinned through
// appScope's nowProvider.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/main.dart' show CycleApp;
import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/database.dart';

final fixedNow = DateTime.utc(2026, 10, 20, 10);

final Finder _banner = find.byKey(const ValueKey('backupReminderBanner'));
final Finder _exportNow = find.byKey(const ValueKey('backupReminderExportNow'));
final Finder _later = find.byKey(const ValueKey('backupReminderLater'));

WebStorageStatus _inMemoryReport() => const WebStorageStatus(
  backend: WebStorageBackend.inMemory,
  installedPwa: false,
  persistent: false,
  usageBytes: null,
  quotaBytes: null,
  userAgent: 'test-agent',
  missingFeatures: <String>{},
);

/// A tracked entry created three months and a few days before [fixedNow],
/// i.e. past the default quarterly interval.
Future<void> _seedTrackedData(CycleDatabase db) async {
  final createdAt = fixedNow.subtract(const Duration(days: 120));
  await db
      .into(db.cycleEntries)
      .insert(
        CycleEntriesCompanion.insert(
          date: createdAt,
          createdAt: Value(createdAt),
          updatedAt: Value(createdAt),
        ),
      );
}

Future<CycleDatabase> _pumpApp(
  WidgetTester tester, {
  Future<void> Function(CycleDatabase db)? seed,
  WebStorageStatus? storageReport,
}) async {
  CycleDatabase? db;
  await tester.pumpWidget(
    appScope(
      locale: const Locale('de'),
      now: () => fixedNow,
      seed: seed,
      onCreated: (created) => db = created,
      storageReport: storageReport,
    ),
  );
  await tester.pumpAndSettle();
  return db!;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CycleApp)));

void main() {
  testWidgets('due data shows the banner with both actions', (tester) async {
    await _pumpApp(tester, seed: _seedTrackedData);

    expect(_banner, findsOneWidget);
    expect(_exportNow, findsOneWidget);
    expect(_later, findsOneWidget);
  });

  testWidgets('no tracked data shows no banner', (tester) async {
    await _pumpApp(tester);

    expect(_banner, findsNothing);
    expect(
      find.byType(IndexedStack),
      findsOneWidget,
      reason: 'the shell layout is unchanged when not due',
    );
  });

  testWidgets('an in-memory storage report suppresses the banner', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      seed: _seedTrackedData,
      storageReport: _inMemoryReport(),
    );

    expect(_banner, findsNothing);
  });

  testWidgets('"Export now" opens the shared JSON export preview', (
    tester,
  ) async {
    await _pumpApp(tester, seed: _seedTrackedData);

    await tester.tap(_exportNow);
    await tester.pumpAndSettle();

    expect(
      find.text('JSON-Vorschau'),
      findsOneWidget,
      reason: '"Export now" must use the single shared export flow',
    );
  });

  testWidgets('"Later" snoozes for seven days in the provider and row and '
      'hides the banner', (tester) async {
    final db = await _pumpApp(tester, seed: _seedTrackedData);
    final container = _container(tester);

    await tester.tap(_later);
    await tester.pumpAndSettle();

    final snoozedUntil = fixedNow.add(const Duration(days: 7));
    expect(_banner, findsNothing);
    expect(
      container.read(backupReminderSnoozedUntilProvider),
      snoozedUntil,
      reason: 'the snooze is seven days from the pinned now',
    );
    expect(
      await SettingsStore(
        db.settingsDao,
      ).readSetting(SettingKeys.backupReminderSnoozedUntil),
      snoozedUntil.toIso8601String(),
      reason: 'the write-through stores the snooze row',
    );
  });

  testWidgets('the settings tab stays reachable while the banner shows', (
    tester,
  ) async {
    await _pumpApp(tester, seed: _seedTrackedData);
    expect(_banner, findsOneWidget);

    await openSettingsTab(tester);

    expect(find.widgetWithText(AppBar, 'Einstellungen'), findsOneWidget);
    expect(_banner, findsOneWidget);
  });
}
