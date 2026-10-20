// Widget tests of the Settings export card's backup controls: the four
// reminder presets (Off / Monthly / Quarterly / Half-yearly, quarterly by
// default, no free-form and no weekly option), the last-export line in the
// device's LOCAL calendar day, and the unchanged export/import actions.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/domain/backup_reminder.dart';
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/database.dart';
import '../support/finders.dart';
import '../support/fixtures.dart';
import '../support/viewport.dart';

final Finder _dropdown = find.byKey(
  const ValueKey('backupReminderIntervalDropdown'),
);

/// Pumps the settings pane with the export card's reminder state pinned and
/// scrolls the card into the built viewport.
Future<ProviderContainer> pumpExportCard(
  WidgetTester tester, {
  DateTime? lastExportAt,
  BackupReminderInterval? interval,
  Future<void> Function(CycleDatabase db)? seed,
}) async {
  useTallSurface(tester, width: 900, height: 2600);
  await tester.pumpWidget(
    settingsHarness(
      lastExportAt: lastExportAt,
      backupReminderInterval: interval,
      seed: seed,
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EinstellungenScreen)),
  );
  await scrollSettingsCardIntoView(tester, _dropdown);
  return container;
}

DropdownButton<BackupReminderInterval> dropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<BackupReminderInterval>>(_dropdown);

String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

void main() {
  group('reminder presets', () {
    testWidgets('offers exactly the four fixed presets', (tester) async {
      await pumpExportCard(tester);

      expect(
        dropdown(tester).items!.map((item) => item.value).toList(),
        BackupReminderInterval.values,
        reason:
            'the four presets are the whole vocabulary — a weekly option or '
            'a free-form step has no representation',
      );
      expect(
        dropdown(
          tester,
        ).items!.map((item) => (item.child as Text).data).toList(),
        const ['Aus', 'Monatlich', 'Vierteljährlich', 'Halbjährlich'],
      );
    });

    testWidgets('defaults to quarterly', (tester) async {
      await pumpExportCard(tester);

      expect(dropdown(tester).value, BackupReminderInterval.quarterly);
      expect(find.text('Vierteljährlich'), findsOneWidget);
    });

    testWidgets('selecting a preset updates the provider', (tester) async {
      final container = await pumpExportCard(tester);

      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monatlich'));
      await tester.pumpAndSettle();

      expect(
        container.read(backupReminderIntervalProvider),
        BackupReminderInterval.monthly,
      );
      expect(dropdown(tester).value, BackupReminderInterval.monthly);
    });
  });

  group('last export line', () {
    testWidgets('reads never without a recorded export', (tester) async {
      await pumpExportCard(tester);

      expect(find.text('Letzter Export: nie'), findsOneWidget);
    });

    // Local-time boundaries: the displayed day is the user's local day, not
    // the UTC day. 00:30 catches a formatter that converts local to UTC in
    // positive-offset zones, 23:30 in negative-offset zones.
    for (final localInstant in [
      DateTime(2026, 4, 26, 0, 30),
      DateTime(2026, 4, 26, 23, 30),
    ]) {
      testWidgets('reads ${localInstant.hour}:${localInstant.minute} local as '
          '26 April', (tester) async {
        await pumpExportCard(tester, lastExportAt: localInstant);
        expect(find.text('Letzter Export: 2026-04-26'), findsOneWidget);
      });
    }

    testWidgets('reads a stored UTC instant as its local calendar day', (
      tester,
    ) async {
      final storedInstant = DateTime.utc(2026, 4, 26, 23, 30);
      await pumpExportCard(tester, lastExportAt: storedInstant);
      expect(
        find.text('Letzter Export: ${isoDay(storedInstant.toLocal())}'),
        findsOneWidget,
      );
    });
  });

  group('existing actions', () {
    testWidgets('export still opens the shared JSON preview', (tester) async {
      await pumpExportCard(
        tester,
        seed: (db) async {
          await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
        },
      );
      await scrollSettingsCardIntoView(tester, settingsExportButton());

      await tester.tap(settingsExportButton());
      await tester.pumpAndSettle();

      expect(find.text('JSON-Vorschau'), findsOneWidget);
    });

    testWidgets('import still opens its dialog', (tester) async {
      await pumpExportCard(tester);
      await scrollSettingsCardIntoView(tester, settingsImportJsonButton());

      await tester.tap(settingsImportJsonButton());
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
