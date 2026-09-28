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
import 'package:cycle_app/domain/export_import.dart'
    show ExportBlob, buildExportJson, formatIsoDay;
import 'package:cycle_app/domain/models.dart' show DailyEntry;
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show acceptExtensions, pickFileTextOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/fixtures.dart';
import 'support/viewport.dart';

/// Runs [pump] with a collector installed in place of
/// [FlutterError.onError]; returns everything the framework reported so the
/// caller can assert none of it happened (assertions happen after this
/// returns, so the handler is restored by then).
Future<List<FlutterErrorDetails>> collectFrameworkErrors(
  WidgetTester tester,
  Future<void> Function() pump,
) async {
  final errors = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details);
  try {
    await pump();
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

/// Simulates the IME opening: a ~300 cp bottom inset applied to the test
/// view (the dialogs below relayout into the reduced area, as on a device).
/// [useSmallAndroidViewport] must have run first; its teardown resets this
/// inset together with the viewport.
Future<void> showKeyboardUp(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding(bottom: 300 * 3);
  await tester.pumpAndSettle();
}

/// The settings screen with the exact MaterialApp configuration of the app
/// shell (sans the shell itself, see the file header). [seed] provides the
/// device-side data the pasted document previews against.
Widget settingsHarness({
  Future<void> Function(CycleDatabase db)? seed,
  CycleDatabase Function()? builder,
}) => ProviderScope(
  overrides: [inMemoryDatabase(seed: seed, builder: builder)],
  child: MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
    ),
    locale: const Locale('de'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('de')],
    home: const EinstellungenScreen(),
  ),
);

/// Pumps the app shell, opens the settings tab and the drip CSV import
/// dialog.
///
/// The tab goes through the shared navigation finder (nav surface, both
/// adaptive surfaces match — see finders.dart): all tabs stay mounted
/// (IndexedStack), so the 'Einstellungen' label also matches the offstage
/// screen's AppBar.
Future<void> pumpAndOpenDripDialogInShell(WidgetTester tester) async {
  await tester.pumpWidget(appScope(locale: const Locale('de')));
  await tester.pumpAndSettle();
  await tester.tap(navLabel('Einstellungen'));
  await tester.pumpAndSettle();

  // Scroll the lazy settings list until the drip button is built; the
  // scrollable is scoped to the settings screen (the shell keeps the other
  // tabs' scrollables in the tree).
  await tester.scrollUntilVisible(
    settingsImportDripButton(),
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(settingsImportDripButton());
  await tester.pumpAndSettle();
}

/// Pumps the settings screen and opens the JSON import dialog. [seed]
/// loads the device-side data the pasted document interacts with, [builder]
/// swaps in a database subclass (fault/plan-timing injection, same seam as
/// the delete-data tests).
Future<void> pumpAndOpenJsonDialog(
  WidgetTester tester, {
  Future<void> Function(CycleDatabase db)? seed,
  CycleDatabase Function()? builder,
}) async {
  await tester.pumpWidget(settingsHarness(seed: seed, builder: builder));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    settingsImportJsonButton(),
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
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
  await tester.scrollUntilVisible(
    settingsImportDripButton(),
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
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

/// Database with a controllable planning read: every entries read waits
/// for [entryReadGate] (the read a plan blocks on) and turns into the
/// read failure planning can hit when [failEntryReads] is set.
final class _GatedPlanDatabase extends CycleDatabase {
  _GatedPlanDatabase(super.executor, {required this.entryReadGate});

  final Completer<void> entryReadGate;
  bool failEntryReads = false;

  late final _GatedPlanEntriesDao _gatedEntriesDao = _GatedPlanEntriesDao(this);

  @override
  EntriesDao get entriesDao => _gatedEntriesDao;
}

final class _GatedPlanEntriesDao extends EntriesDao {
  _GatedPlanEntriesDao(this._db) : super(_db);

  final _GatedPlanDatabase _db;

  @override
  Future<List<CycleEntry>> allEntries() {
    final gate = _db.entryReadGate.future;
    if (_db.failEntryReads) {
      return gate.then((_) => throw StateError('injected plan read failure'));
    }
    return gate.then((_) => super.allEntries());
  }
}

/// Builds the [_GatedPlanDatabase] the same way the harness builds its
/// in-memory database (no files, no platform channels).
_GatedPlanDatabase _gatedPlanDatabase(Completer<void> gate) {
  return _GatedPlanDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
    entryReadGate: gate,
  );
}

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
          await tester.scrollUntilVisible(
            settingsImportDripButton(),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(EinstellungenScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
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
          builder: () => _gatedPlanDatabase(gate),
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
        final db = _gatedPlanDatabase(gate);
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
