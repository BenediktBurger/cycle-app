// Repro tests for the two settings import dialogs (JSON and drip CSV).
//
// Covered: the drip import dialog's content overflowing a small
// Android-class viewport with the keyboard up ("bottom overflowed by N
// pixels"), the file-picker button being hidden on the native (io) compile
// target, and a scrim-dismiss while the import is in flight (the dialogs
// used to tear their controller/notifier down by hand after `await
// showDialog`, letting code in the still-running apply future touch disposed
// state; these tests guard the fix).
//
// Harness notes: the tests pin the German locale and use the in-memory drift
// database override (test/support/database.dart) — nothing platform-channel
// based. The overflow repro pumps the settings screen directly (same
// MaterialApp config as the app shell): the shell keeps every tab mounted
// inside the IndexedStack, so at narrow widths the (separately tracked)
// diary form's overflows would land in the error collector and confound the
// dialog measurement.
import 'dart:async';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:cycle_app/domain/export_import.dart'
    show ExportBlob, buildExportJson, formatIsoDay;
import 'package:cycle_app/domain/models.dart' show DailyEntry;
import 'package:cycle_app/providers.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show acceptExtensions, pickFileTextOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/error_collector.dart';
import 'support/faulty_db.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

/// Simulates the IME opening: a ~300 cp bottom inset applied to the test
/// view (the dialogs below relayout into the reduced area, as on a device).
/// [useSmallAndroidViewport] must have run first; its teardown resets this
/// inset together with the viewport.
Future<void> showKeyboardUp(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding(bottom: 300 * 3);
  await tester.pumpAndSettle();
}

/// Pumps the app shell, opens the settings tab and the drip CSV import
/// dialog.
Future<void> pumpAndOpenDripDialogInShell(WidgetTester tester) async {
  await tester.pumpWidget(appScope(locale: const Locale('de')));
  await tester.pumpAndSettle();
  await openSettingsTab(tester);
  await scrollSettingsCardIntoView(tester, settingsImportDripButton());
  await tester.tap(settingsImportDripButton());
  await tester.pumpAndSettle();
}

/// Pumps the settings screen and opens the JSON import dialog. [seed]
/// loads the device-side data the pasted document interacts with, [builder]
/// swaps in a fault-injectable database (support/faulty_db.dart).
Future<void> pumpAndOpenJsonDialog(
  WidgetTester tester, {
  Future<void> Function(CycleDatabase db)? seed,
  CycleDatabase Function()? builder,
}) async {
  await tester.pumpWidget(settingsHarness(seed: seed, builder: builder));
  await tester.pumpAndSettle();
  await scrollSettingsCardIntoView(tester, settingsImportJsonButton());
  await tester.tap(settingsImportJsonButton());
  await tester.pumpAndSettle();
  expect(
    find.byType(AlertDialog),
    findsOneWidget,
    reason: 'the JSON import dialog must be open',
  );
}

/// Pumps the settings screen and opens the drip CSV import dialog. [seed]
/// provides the device-side data the picked CSV previews against.
Future<void> pumpAndOpenDripDialog(
  WidgetTester tester, {
  Future<void> Function(CycleDatabase db)? seed,
}) async {
  await tester.pumpWidget(settingsHarness(seed: seed));
  await tester.pumpAndSettle();
  await scrollSettingsCardIntoView(tester, settingsImportDripButton());
  await tester.tap(settingsImportDripButton());
  await tester.pumpAndSettle();
  expect(
    find.byType(AlertDialog),
    findsOneWidget,
    reason: 'the drip import dialog must be open',
  );
}

/// The textarea inside the open import dialog (it carries the only
/// TextField of the dialog).
Finder importTextField() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

/// The confirm (apply) button of the open import dialog (JSON dialog label
/// 'Import durchführen', drip dialog label 'Termine-CSV importieren').
Finder applyButton() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);

/// The overwrite-preview line (present only while a conflicting plan is
/// computed).
Finder overwritePreview() =>
    find.byKey(const ValueKey('importOverwritePreview'));

/// An export document carrying only category definitions — the
/// definitions-only import shape.
String categoriesDoc(List<Map<String, Object?>> rows) => buildExportJson(
  ExportBlob(
    exportedAt: DateTime.utc(2026, 9, 20),
    entries: const [],
    marks: const [],
    customCategories: rows,
  ),
);

void main() {
  group('import dialogs', () {
    testWidgets(
      'drip import dialog opens on a small Android viewport (keyboard up) '
      'without any overflow',
      (WidgetTester tester) async {
        useSmallAndroidViewport(tester);
        final errors = await collectFrameworkErrors(tester, () async {
          await tester.pumpWidget(settingsHarness());
          await tester.pumpAndSettle();
          await scrollSettingsCardIntoView(tester, settingsImportDripButton());
          await tester.tap(settingsImportDripButton());
          await tester.pumpAndSettle();
          // The dialog is open; now the keyboard slides in and the dialog
          // relayouts into the reduced area — the reproducing step.
          await showKeyboardUp(tester);
          expect(
            find.byType(AlertDialog),
            findsOneWidget,
            reason: 'the repro needs the import dialog to actually open',
          );
        });

        expect(
          errors,
          isEmpty,
          reason:
              'the drip import dialog (10-line textarea, title, actions) must '
              'fit 360x640 dp with the keyboard up without a RenderFlex '
              'overflow',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the dialogs offer a file picker on the native (io) target '
        '(paste-only before: the button was gated off by canPickFile)', (
      WidgetTester tester,
    ) async {
      await pumpAndOpenDripDialogInShell(tester);
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(OutlinedButton, 'Datei wählen'),
        ),
        findsOneWidget,
        reason:
            'the native build must show the picker button now that a '
            'picker exists on the io target',
      );
    });

    testWidgets(
      'dismissing the drip dialog via the scrim while the import is in '
      'flight does not leak an error into the framework',
      (WidgetTester tester) async {
        await pumpAndOpenDripDialogInShell(tester);

        // Fill the textarea with a valid drip CSV — via the test-only picker
        // override, which also proves the hermetic picker seam injects its
        // result into the dialog's field. Error collection covers the pumps
        // through completion, so an async disposal error has surfaced by the
        // time the assertion runs.
        pickFileTextOverride = (accept) async => sampleDripCsv;
        addTearDown(() => pickFileTextOverride = null);
        final errors = await collectFrameworkErrors(tester, () async {
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(OutlinedButton, 'Datei wählen'),
            ),
          );
          await tester.pumpAndSettle();
          final textField = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          expect(
            tester.widget<TextField>(textField).controller!.text,
            sampleDripCsv,
            reason: 'the picked file content must land in the textarea',
          );
          final apply = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'CSV importieren'),
          );
          await tester.tap(apply);

          // While the import future is in flight, dismiss through the scrim:
          // no pump in between — the barrier tap releases the dialog route.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        });

        expect(tester.takeException(), isNull);
        expect(
          errors,
          isEmpty,
          reason:
              'dismissing the dialog while the import future is running '
              'must not produce a "used after being disposed"-style error from '
              'the dialog state',
        );
      },
    );
  });

  group('import overwrite preview', () {
    /// An export document overwriting [dates] (all already stored on the
    /// device, values changed) — the whole document, paste-ready.
    String conflictDoc(List<DateTime> dates) => buildExportJson(
      ExportBlob(
        exportedAt: DateTime.utc(2026, 9, 20),
        entries: [
          for (final date in dates) {'date': formatIsoDay(date), 'bbt_c': 37.2},
        ],
        marks: const [],
      ),
    );

    /// An export document containing only days the device does not know.
    final foreignDoc = buildExportJson(
      ExportBlob(
        exportedAt: DateTime.utc(2026, 9, 20),
        entries: [
          {'date': '2026-01-01', 'bbt_c': 36.5},
          {'date': '2026-01-02', 'bleeding': 3},
        ],
        marks: const [],
      ),
    );

    testWidgets(
      'the overwrite count for ONE already-stored day previews as the '
      'grammatically correct German singular',
      (WidgetTester tester) async {
        await pumpAndOpenJsonDialog(
          tester,
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        final day = evaluationScenarioEntries().first.date;
        await tester.enterText(importTextField(), conflictDoc([day]));
        await tester.pumpAndSettle();

        expect(overwritePreview(), findsOneWidget);
        expect(
          (tester.widget<Text>(overwritePreview())).data,
          '1 Tag wird überschrieben.',
        );
      },
    );

    testWidgets(
      'a document whose days are all unknown shows no overwrite warning',
      (WidgetTester tester) async {
        await pumpAndOpenJsonDialog(
          tester,
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        await tester.enterText(importTextField(), foreignDoc);
        await tester.pumpAndSettle();

        expect(overwritePreview(), findsNothing);
      },
    );

    testWidgets(
      'replacing the pasted text recomputes the preview (a changed plan '
      'clears the warning line)',
      (WidgetTester tester) async {
        await pumpAndOpenJsonDialog(
          tester,
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        final day = evaluationScenarioEntries().first.date;
        await tester.enterText(importTextField(), conflictDoc([day]));
        await tester.pumpAndSettle();
        expect(overwritePreview(), findsOneWidget);

        await tester.enterText(importTextField(), foreignDoc);
        await tester.pumpAndSettle();
        expect(overwritePreview(), findsNothing);
      },
    );

    testWidgets('TWO already-stored days preview as the grammatically correct '
        'German plural', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(
        tester,
        seed: (db) async {
          for (final entry in evaluationScenarioEntries().take(2)) {
            await db.entriesDao.upsertDaily(entry);
          }
        },
      );
      final days = evaluationScenarioEntries().take(2).map((e) => e.date);
      await tester.enterText(importTextField(), conflictDoc(days.toList()));
      await tester.pumpAndSettle();

      expect(
        (tester.widget<Text>(overwritePreview())).data,
        '2 Tage werden überschrieben.',
      );
    });

    testWidgets(
      'an invalid document shows no warning (and no framework error) and '
      'the apply path reports the invalid-document snackbar with the '
      'dialog still open',
      (WidgetTester tester) async {
        await pumpAndOpenJsonDialog(
          tester,
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        final errors = await collectFrameworkErrors(tester, () async {
          await tester.enterText(importTextField(), '{ not json');
          await tester.pumpAndSettle();
          expect(
            find.byType(AlertDialog),
            findsOneWidget,
            reason: 'the dialog must survive the failed planning',
          );
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'Import durchführen'),
            ),
          );
          await tester.pumpAndSettle();
        });

        expect(overwritePreview(), findsNothing);
        expect(
          find.text('Ungültiges Dokument (kein gültiger cycle-app-Export).'),
          findsOneWidget,
          reason: 'the apply path reports the invalid document',
        );
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'an invalid document keeps the dialog open',
        );
        expect(errors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the drip dialog previews a seeded conflicting day from the picked '
      'CSV',
      (WidgetTester tester) async {
        pickFileTextOverride = (accept) async => sampleDripCsv;
        addTearDown(() => pickFileTextOverride = null);
        await pumpAndOpenDripDialog(
          tester,
          seed: (db) async {
            await db.entriesDao.upsertDaily(
              DailyEntry(date: DateTime.utc(2026, 7, 5), bbtC: 37.0),
            );
          },
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(OutlinedButton, 'Datei wählen'),
          ),
        );
        await tester.pumpAndSettle();

        // The sample CSV re-records 2026-07-05 (temperature 36.2), so the
        // seeded day is overwritten exactly once.
        expect(overwritePreview(), findsOneWidget);
        expect(
          (tester.widget<Text>(overwritePreview())).data,
          '1 Tag wird überschrieben.',
        );
      },
    );

    testWidgets(
      'the apply button stays disabled while the overwrite plan is still '
      'computing, and re-enables once it resolved',
      (WidgetTester tester) async {
        final gate = Completer<void>();
        await pumpAndOpenJsonDialog(
          tester,
          builder: () => FaultyCycleDatabase(entryReadGate: gate),
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        final day = evaluationScenarioEntries().first.date;
        await tester.enterText(importTextField(), conflictDoc([day]));
        await tester.pump();

        expect(
          tester.widget<FilledButton>(applyButton()).onPressed,
          isNull,
          reason: 'apply must wait for the pending overwrite plan',
        );

        gate.complete();
        await tester.pumpAndSettle();
        expect(overwritePreview(), findsOneWidget);
        expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
      },
    );

    testWidgets(
      'a failed planning run also re-enables the apply button, so the '
      'apply path can report the failed import',
      (WidgetTester tester) async {
        final gate = Completer<void>();
        final db = FaultyCycleDatabase(entryReadGate: gate);
        db.failEntryReads = true;
        await pumpAndOpenJsonDialog(
          tester,
          builder: () => db,
          seed: (db) async {
            await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
          },
        );
        final day = evaluationScenarioEntries().first.date;
        await tester.enterText(importTextField(), conflictDoc([day]));
        await tester.pump();
        expect(
          tester.widget<FilledButton>(applyButton()).onPressed,
          isNull,
          reason: 'apply must wait for the pending overwrite plan',
        );

        gate.complete();
        await tester.pumpAndSettle();
        expect(overwritePreview(), findsNothing);
        expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);

        await tester.tap(applyButton());
        await tester.pumpAndSettle();
        expect(
          find.text('Import fehlgeschlagen — die Daten wurden nicht geändert.'),
          findsOneWidget,
        );
      },
    );
  });

  group('import custom category preview', () {
    Finder visibilityPreview() =>
        find.byKey(const ValueKey('importCustomCategoryVisibilityPreview'));
    Finder rowsPreview() =>
        find.byKey(const ValueKey('importCustomCategoryRowsPreview'));

    testWidgets('a visibility flip previews the affected name in the error '
        'style', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(
        tester,
        seed: (db) async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ]);
        },
      );
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Sport',
            'visible': false,
            'items': ['Joggen'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(visibilityPreview(), findsOneWidget);
      final warning = tester.widget<Text>(visibilityPreview());
      expect(warning.data, '1 Kategorie ändert die Sichtbarkeit: Sport');
      expect(
        warning.style?.color,
        Theme.of(tester.element(visibilityPreview())).colorScheme.error,
        reason: 'the visibility flip is the destructive part of the merge',
      );
      expect(rowsPreview(), findsNothing);
    });

    testWidgets('several visibility flips preview in stored order, joined '
        'with the shared separator', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(
        tester,
        seed: (db) async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['Joggen']),
            const CustomCategory(name: 'Medikamente'),
          ]);
        },
      );
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {'name': 'Medikamente', 'visible': false},
          {
            'name': 'Sport',
            'visible': false,
            'items': ['Joggen'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(visibilityPreview()).data,
        '2 Kategorien ändern die Sichtbarkeit: Sport, Medikamente',
        reason: 'the join follows the stored order, not the document order',
      );
    });

    testWidgets('identical definitions preview no warning', (
      WidgetTester tester,
    ) async {
      await pumpAndOpenJsonDialog(
        tester,
        seed: (db) async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['Joggen']),
          ]);
        },
      );
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Sport',
            'visible': true,
            'items': ['Joggen'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(visibilityPreview(), findsNothing);
      expect(rowsPreview(), findsNothing);
    });

    testWidgets('skipped blank-name and duplicate-name rows preview both '
        'counts', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(tester);
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': '   ',
            'items': ['x'],
          },
          {
            'name': 'Neu',
            'items': ['X'],
          },
          {
            'name': 'Neu',
            'items': ['Y'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(rowsPreview(), findsOneWidget);
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 Zeile ohne Namen wurde übersprungen.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 doppelter Kategoriename wurde übersprungen.'),
        ),
        findsOneWidget,
      );
      expect(visibilityPreview(), findsNothing);
    });

    testWidgets('a blank-name row alone previews only the blank-name line', (
      WidgetTester tester,
    ) async {
      await pumpAndOpenJsonDialog(tester);
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {'name': '   '},
        ]),
      );
      await tester.pumpAndSettle();

      expect(rowsPreview(), findsOneWidget);
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 Zeile ohne Namen wurde übersprungen.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 doppelter Kategoriename wurde übersprungen.'),
        ),
        findsNothing,
      );
    });

    testWidgets('an in-document duplicate alone previews only the duplicate '
        'line', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(tester);
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Neu',
            'items': ['X'],
          },
          {
            'name': 'Neu',
            'items': ['Y'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(rowsPreview(), findsOneWidget);
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 doppelter Kategoriename wurde übersprungen.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowsPreview(),
          matching: find.text('1 Zeile ohne Namen wurde übersprungen.'),
        ),
        findsNothing,
      );
    });

    testWidgets('a clean document previews no notice', (
      WidgetTester tester,
    ) async {
      await pumpAndOpenJsonDialog(tester);
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Neu',
            'items': ['X'],
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(visibilityPreview(), findsNothing);
      expect(rowsPreview(), findsNothing);
    });
  });

  group('import summary counts the method snapshots', () {
    testWidgets('a methods-only document is not reported as empty — the '
        'method figures ride the applied summary', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(tester);
      final methodsOnlyDoc = buildExportJson(
        ExportBlob(
          exportedAt: DateTime.utc(2026, 9, 20),
          entries: const [],
          marks: const [],
          methods: [
            {'date': '2026-01-01', 'method': 'vaginal'},
          ],
        ),
      );
      await tester.enterText(importTextField(), methodsOnlyDoc);
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1 Methode neu'),
        findsOneWidget,
        reason: 'the summary reports the written method snapshot',
      );
      expect(
        find.textContaining('nichts zu ändern'),
        findsNothing,
        reason: 'a methods-only document is not an empty import',
      );
    });
  });

  group('import summary of category-only changes', () {
    testWidgets('a categories-only change reports the merged categories '
        'instead of "nothing to change"', (WidgetTester tester) async {
      await pumpAndOpenJsonDialog(tester);
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Neu',
            'items': ['X'],
          },
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Import: 1 eigene Kategorie ergänzt.'),
        findsOneWidget,
        reason: 'a definitions-only change is not an empty import',
      );
      expect(find.textContaining('nichts zu ändern'), findsNothing);
    });

    testWidgets('a merge that adds no category reports the merged wording', (
      WidgetTester tester,
    ) async {
      await pumpAndOpenJsonDialog(
        tester,
        seed: (db) async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Sport', items: ['X']),
          ]);
        },
      );
      await tester.enterText(
        importTextField(),
        categoriesDoc(const [
          {
            'name': 'Sport',
            'visible': true,
            'items': ['X', 'Y'],
          },
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Import: eigene Kategorien zusammengeführt.'),
        findsOneWidget,
        reason: 'a label-only merge adds no category',
      );
      expect(
        find.text('Import: 1 eigene Kategorie ergänzt.'),
        findsNothing,
        reason: 'the =0 form must not claim an added category',
      );
      expect(find.textContaining('nichts zu ändern'), findsNothing);
    });
  });

  group('import updates the custom categories provider in-session', () {
    /// Pumps the REAL app shell (hydration runs there — the bare settings
    /// harness never drives the registrar), opens the settings tab and the
    /// JSON import dialog.
    Future<void> pumpShellAndOpenJsonDialog(
      WidgetTester tester, {
      Future<void> Function(CycleDatabase db)? seed,
    }) async {
      await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
      await tester.pumpAndSettle();
      await openSettingsTab(tester);
      await scrollSettingsCardIntoView(tester, settingsImportJsonButton());
      await tester.tap(settingsImportJsonButton());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    /// The provider value through the shell's scope (the container the
    /// diary form and the settings card read).
    List<CustomCategory> providerCategories(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(EinstellungenScreen)),
        ).read(customDiaryCategoriesProvider);

    /// Pastes [json] into the open dialog and applies the import.
    Future<void> applyImport(WidgetTester tester, String json) async {
      await tester.enterText(importTextField(), json);
      await tester.pumpAndSettle();
      await tester.tap(applyButton());
      await tester.pumpAndSettle();
    }

    testWidgets('a document with definitions applies them without a restart', (
      WidgetTester tester,
    ) async {
      await pumpShellAndOpenJsonDialog(tester);
      await applyImport(
        tester,
        buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 9, 20),
            entries: [
              {'date': '2026-09-01', 'bbt_c': 36.5},
            ],
            marks: const [],
            customCategories: const [
              {
                'name': 'Sport',
                'visible': true,
                'items': ['Joggen'],
              },
            ],
          ),
        ),
      );

      expect(
        providerCategories(tester),
        [
          const CustomCategory(name: 'Sport', items: ['Joggen']),
        ],
        reason:
            'the imported definitions are live in-session — the diary '
            'form and the settings card see them without a restart',
      );
    });

    testWidgets('a colliding definition merges into the provider in place', (
      WidgetTester tester,
    ) async {
      await pumpShellAndOpenJsonDialog(
        tester,
        seed: (db) async {
          await SettingsStore(db.settingsDao).persistCustomCategories([
            const CustomCategory(name: 'Alt', items: ['X']),
          ]);
        },
      );
      await applyImport(
        tester,
        buildExportJson(
          ExportBlob(
            exportedAt: DateTime.utc(2026, 9, 20),
            entries: [
              {'date': '2026-09-01', 'bbt_c': 36.5},
            ],
            marks: const [],
            customCategories: const [
              {
                'name': 'Alt',
                'visible': true,
                'items': ['X', 'Y'],
              },
              {'name': 'Neu', 'visible': true, 'items': <String>[]},
            ],
          ),
        ),
      );

      expect(providerCategories(tester), [
        const CustomCategory(name: 'Alt', items: ['X', 'Y']),
        const CustomCategory(name: 'Neu'),
      ]);
    });

    testWidgets(
      'a document without the key leaves the provider exactly as hydrated',
      (WidgetTester tester) async {
        await pumpShellAndOpenJsonDialog(
          tester,
          seed: (db) async {
            await SettingsStore(db.settingsDao).persistCustomCategories([
              const CustomCategory(name: 'Alt', items: ['X']),
            ]);
          },
        );
        await applyImport(
          tester,
          buildExportJson(
            ExportBlob(
              exportedAt: DateTime.utc(2026, 9, 20),
              entries: [
                {'date': '2026-09-01', 'bbt_c': 36.5},
              ],
              marks: const [],
            ),
          ),
        );

        expect(
          providerCategories(tester),
          [
            const CustomCategory(name: 'Alt', items: ['X']),
          ],
          reason:
              'a definitions-free document must not touch the '
              'in-memory definitions (and not wipe them through a '
              'write-through of an empty list)',
        );
      },
    );
  });

  group('accept-string translation for the native picker', () {
    test('default JSON accept keeps the paired extension filter', () {
      expect(acceptExtensions('application/json,.json'), ['json']);
    });

    test('CSV accept keeps its extension filter', () {
      expect(acceptExtensions('.csv,text/csv'), ['csv']);
    });

    test('extension-only accept keeps its extension filter', () {
      expect(acceptExtensions('.json'), ['json']);
    });

    test('empty accept matches every file', () {
      expect(acceptExtensions(''), isNull);
    });

    test('MIME-only accepts cannot filter, matching every file', () {
      // file_picker cannot filter by MIME, so a bare MIME token degrades
      // to the unfiltered dialog (the import validation catches a wrong
      // pick) — the paired-extension accepts above stay filtered.
      expect(acceptExtensions('application/octet-stream'), isNull);
    });

    test('whitespace-padded tokens are trimmed', () {
      final extensions = acceptExtensions(' .csv , text/csv ');
      expect(extensions, ['csv']);
    });
  });
}
