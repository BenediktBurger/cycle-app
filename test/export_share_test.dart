// Widget tests for the JSON export's file actions on the preview page:
// the share action that hands a real, export-named file to the system
// share sheet (the Android/iOS route — free-form file paths and
// home-directory writes do not exist there, and the native hint long
// promised a share sheet), its success and failure snackbars, and the
// desktop save button the share work must not regress.
//
// Harness notes: the tests pin the German locale and use the in-memory
// drift database override (test/support/database.dart) with a seeded
// entry so the export is non-empty — nothing platform-channel based.
// The share path goes through the test-only seam in file_transfer_io.dart
// (shareFileOverride, the same pattern as the picker's
// pickFileTextOverride): the real share plugin is never invoked, the
// suite stays hermetic. Navigation mimics the user path — Settings ›
// JSON-Export › preview page. The German literals below (button,
// snackbars) must stay in step with the localization entries
// (exportShare / exportShared / exportShareFailed) they exercise.
import 'dart:io';

import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show canSaveFile, shareFileOverride;
import 'package:cycle_app/ui/settings.dart'
    show EinstellungenScreen, exportFileName;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/fixtures.dart';

/// The l10n strings the tests drive through (German is authoritative):
/// the share button and the confirm/failure snackbars next to the
/// existing save strings.
const shareButtonLabel = 'Teilen';
const sharedSnackbarLabel = 'Datei geteilt.';
const shareFailedSnackbarLabel = 'Teilen fehlgeschlagen.';
const saveFileButtonLabel = 'Als Datei speichern';
const previewTitleLabel = 'JSON-Vorschau';
const exportButtonLabel = 'JSON-Export';

/// The settings screen with the exact MaterialApp configuration of the app
/// shell (sans the shell itself) over the in-memory database.
Widget settingsHarness() => ProviderScope(
  overrides: [
    inMemoryDatabase(
      seed: (db) async {
        await db.entriesDao.upsertDaily(evaluationScenarioEntries().first);
      },
    ),
  ],
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

/// Pumps the settings screen and navigates through JSON-Export onto the
/// export preview page (the seeded entry keeps the export from being
/// rejected as empty). The preview page is on top when this returns.
Future<void> pumpToExportPreview(WidgetTester tester) async {
  await tester.pumpWidget(settingsHarness());
  await tester.pumpAndSettle();
  // Scroll the lazy settings list until the export button is built; the
  // scroller is scoped to the settings screen.
  await tester.scrollUntilVisible(
    find.widgetWithText(FilledButton, exportButtonLabel),
    200,
    scrollable: find
        .descendant(
          of: find.byType(EinstellungenScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, exportButtonLabel));
  await tester.pumpAndSettle();
  expect(
    find.text(previewTitleLabel),
    findsOneWidget,
    reason: 'the user path must reach the export preview page',
  );
}

void main() {
  group('export preview: share action', () {
    testWidgets('the preview page offers the share button', (
      WidgetTester tester,
    ) async {
      await pumpToExportPreview(tester);
      expect(
        find.text(shareButtonLabel),
        findsOneWidget,
        reason:
            'the export preview must offer a share action on the '
            'native (io) target — the clipboard-only route is not enough '
            'for an Android user, as the shipped native hint promised',
      );
    });

    testWidgets('tapping share hands the export file to the system share sheet '
        '(seam call-through with filename and JSON content) and confirms '
        'with a snackbar', (WidgetTester tester) async {
      final shared = <(String, String)>[];
      shareFileOverride = (filename, content) async {
        shared.add((filename, content));
        return true;
      };
      addTearDown(() => shareFileOverride = null);

      await pumpToExportPreview(tester);
      await tester.tap(find.text(shareButtonLabel));
      await tester.pumpAndSettle();

      expect(
        shared,
        hasLength(1),
        reason:
            'the share tap must reach the share implementation '
            '(here: the hermetic test seam)',
      );
      final (filename, content) = shared.single;
      expect(filename, exportFileName);
      expect(
        content,
        contains('schema_version'),
        reason:
            'the shared file content must be the self-describing '
            'export JSON',
      );
      expect(
        find.text(sharedSnackbarLabel),
        findsOneWidget,
        reason:
            'a successful share reports itself, like the save path '
            'does',
      );
    });

    testWidgets('a failed share reports the failure snackbar', (
      WidgetTester tester,
    ) async {
      shareFileOverride = (filename, content) async => false;
      addTearDown(() => shareFileOverride = null);

      await pumpToExportPreview(tester);
      await tester.tap(find.text(shareButtonLabel));
      await tester.pumpAndSettle();

      expect(
        find.text(shareFailedSnackbarLabel),
        findsOneWidget,
        reason:
            'a share failure must be reported, mirroring the save '
            'failure snackbar',
      );
      expect(find.text(sharedSnackbarLabel), findsNothing);
    });
  });

  group('export preview: desktop save regression', () {
    testWidgets('the preview keeps offering the home-directory save button', (
      WidgetTester tester,
    ) async {
      // The desktop save path keys off HOME/USERPROFILE; the widget-test
      // environment cannot rewrite those variables for the running
      // process, so the runner's own environment is the fixture: it must
      // carry a home directory for this target class.
      expect(
        Platform.environment['HOME'],
        isNotEmpty,
        reason:
            'the test environment is expected to carry HOME — '
            'without it the desktop save button legitimately stays '
            'hidden and this goal is undriveable',
      );
      expect(canSaveFile, isTrue);

      await pumpToExportPreview(tester);
      expect(
        find.text(saveFileButtonLabel),
        findsOneWidget,
        reason:
            'desktop keeps the existing save-as-file path even '
            'after the share action arrives',
      );
    });
  });
}
