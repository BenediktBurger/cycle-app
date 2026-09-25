// Widget tests for the JSON export's file actions on the preview page:
// the share action that hands a real, export-named file to the system
// share sheet, its success and failure snackbars, and the save-as-dialog
// path (file_picker's save dialog on every native target now, Android SAF
// included) the share work must not regress, and the export-BUILD failure
// path (fault-injected database, the delete-data test's pattern) whose
// failure must surface as a localized snackbar instead of a silent abort.
//
// Harness notes: the tests pin the German locale and use the in-memory
// drift database override (test/support/database.dart) with a seeded
// entry so the export is non-empty — nothing platform-channel based.
// The share and save paths go through the test-only seams in
// file_transfer_io.dart (shareFileOverride / saveFileOverride, the same
// pattern as the picker's pickFileTextOverride): the real plugins are
// never invoked, the suite stays hermetic. Navigation mimics the user
// path — Settings › JSON-Export › preview page. The German literals below
// (button, snackbars) must stay in step with the localization entries
// (exportShare / exportShared / exportShareFailed / exportSaved /
// exportSaveFailed / exportFailed) they exercise.
import 'dart:io';

import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show
        canSaveFile,
        saveFileOverride,
        shareFile,
        shareFileBytes,
        shareFileOverride;
import 'package:cycle_app/ui/settings.dart'
    show EinstellungenScreen, exportFileName;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';

import 'support/database.dart';
import 'support/fixtures.dart';

/// The l10n strings the tests drive through (German is authoritative):
/// the share button and the confirm/failure snackbars next to the
/// existing save strings.
const shareButtonLabel = 'Teilen';
const sharedSnackbarLabel = 'Datei geteilt.';
const shareFailedSnackbarLabel = 'Teilen fehlgeschlagen.';
const saveFileButtonLabel = 'Als Datei speichern';
const savedSnackbarLabel = 'Datei gespeichert.';
const saveFailedSnackbarLabel = 'Speichern fehlgeschlagen.';
const exportFailedSnackbarLabel = 'Export fehlgeschlagen.';
const previewTitleLabel = 'JSON-Vorschau';
const exportButtonLabel = 'JSON-Export';

/// Fault injection for the export build: the real in-memory database whose
/// data reads can be armed to fail AFTER the harness was pumped — the test
/// flips the flag at exactly the point the fault should occur. The export
/// reads through the DAOs, so arming the entries read covers the build.
class _FaultyDatabase extends CycleDatabase {
  _FaultyDatabase(super.executor);

  bool failReads = false;

  late final _FaultyEntriesDao _faultyEntriesDao = _FaultyEntriesDao(this);

  @override
  EntriesDao get entriesDao => _faultyEntriesDao;
}

class _FaultyEntriesDao extends EntriesDao {
  _FaultyEntriesDao(this._faulty) : super(_faulty);

  final _FaultyDatabase _faulty;

  @override
  Future<List<CycleEntry>> allEntries() {
    if (_faulty.failReads) {
      throw StateError('injected read failure');
    }
    return super.allEntries();
  }
}

_FaultyDatabase _faultyDatabase() {
  return _FaultyDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}

/// The settings screen with the exact MaterialApp configuration of the app
/// shell (sans the shell itself) over the in-memory database. [builder]
/// swaps the database subclass for fault injection, like the delete-data
/// tests build theirs.
Widget settingsHarness({CycleDatabase Function()? builder}) => ProviderScope(
  overrides: [
    inMemoryDatabase(
      builder: builder,
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

/// The path_provider channel whose getTemporaryDirectory answer decides
/// where [shareFile]/[shareFileBytes] stage their files; and the
/// share_plus channel the staged hand-off goes through.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _sharePlusChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  group('export open: failure surfacing', () {
    testWidgets('a failing export build reports the failure snackbar and '
        'keeps the settings screen (no preview page, no unhandled error)', (
      WidgetTester tester,
    ) async {
      final faulty = _faultyDatabase();
      await tester.pumpWidget(settingsHarness(builder: () => faulty));
      await tester.pumpAndSettle();
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

      faulty.failReads = true;
      await tester.tap(find.widgetWithText(FilledButton, exportButtonLabel));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the export flow must catch its own failures — nothing may '
            'leak into the zone as an unhandled error',
      );
      expect(
        find.text(exportFailedSnackbarLabel),
        findsOneWidget,
        reason:
            'a failure building the export (the database reads the JSON '
            'is assembled from) is reported via the localized failure '
            'snackbar, mirroring the other settings flows',
      );
      expect(
        find.text(previewTitleLabel),
        findsNothing,
        reason: 'the preview page does not open when the export failed',
      );
    });
  });

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

  group('export preview: save-as-dialog path', () {
    testWidgets('the preview page offers the save button', (
      WidgetTester tester,
    ) async {
      // Platform-independent: every native io target (desktop and
      // Android SAF alike) offers the save-as dialog, so `canSaveFile`
      // is just `true`.
      expect(canSaveFile, isTrue);

      await pumpToExportPreview(tester);
      expect(
        find.text(saveFileButtonLabel),
        findsOneWidget,
        reason:
            'the save-as-file path survives next to the share action '
            '(save dialog on the native targets, browser download on web)',
      );
    });

    testWidgets('tapping save drives the save implementation through the seam '
        '(filename and JSON content) and confirms with a snackbar', (
      WidgetTester tester,
    ) async {
      final saves = <(String, String)>[];
      saveFileOverride = (filename, content) async {
        saves.add((filename, content));
        return true;
      };
      addTearDown(() => saveFileOverride = null);

      await pumpToExportPreview(tester);
      await tester.tap(find.text(saveFileButtonLabel));
      await tester.pumpAndSettle();

      expect(
        saves,
        hasLength(1),
        reason:
            'the save tap must reach the save implementation '
            '(here: the hermetic test seam standing in for the real '
            'save-as dialog)',
      );
      final (filename, content) = saves.single;
      expect(filename, exportFileName);
      expect(
        content,
        contains('schema_version'),
        reason:
            'the saved file content must be the self-describing '
            'export JSON',
      );
      expect(find.text(savedSnackbarLabel), findsOneWidget);
    });

    testWidgets('a failed save reports the failure snackbar', (
      WidgetTester tester,
    ) async {
      saveFileOverride = (filename, content) async => false;
      addTearDown(() => saveFileOverride = null);

      await pumpToExportPreview(tester);
      await tester.tap(find.text(saveFileButtonLabel));
      await tester.pumpAndSettle();

      expect(
        find.text(saveFailedSnackbarLabel),
        findsOneWidget,
        reason:
            'a save failure must be reported, mirroring the share '
            'failure snackbar (a cancelled dialog also lands here — the '
            'bool contract cannot tell cancel from failure)',
      );
      expect(find.text(savedSnackbarLabel), findsNothing);
    });
  });

  // These tests drive the real share implementation (not the widget-test
  // override seams) over mocked platform channels, so the filesystem side
  // effect — the staged plaintext export / PDF under the platform temp
  // directory and its removal after the share sheet resolves — is
  // observable hermetically.
  group('share staging: temp file cleanup', () {
    late Directory stagingDir;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      stagingDir = Directory.systemTemp.createTempSync('share_stage_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
            return switch (call.method) {
              'getTemporaryDirectory' => stagingDir.path,
              _ => null,
            };
          });
    });

    /// Asserts [filename]'s staged copy under the temp dir is gone; every
    /// share outcome (sheet resolved, user dismissed, channel failure) is
    /// expected to end with the file removed.
    void expectStagedFileGone(String filename) {
      final staged = File(
        '${stagingDir.path}${Platform.pathSeparator}$filename',
      );
      expect(
        staged.existsSync(),
        isFalse,
        reason:
            'the staged share file $filename must be deleted once the '
            'share call resolves — it stays behind otherwise '
            '(platform temp dir: ${stagingDir.path})',
      );
    }

    void registerShareHandler({
      bool throwPlatformException = false,
      void Function(String stagedPath)? onHandoff,
    }) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sharePlusChannel, (call) async {
            expect(call.method, 'share');
            final paths = List<String>.from(call.arguments['paths'] as List);
            expect(paths, hasLength(1), reason: 'share action stages one file');
            onHandoff?.call(paths.single);
            if (throwPlatformException) {
              throw PlatformException(code: 'test', message: 'share failed');
            }
            return 'test-action';
          });
    }

    test(
      'shareFile stages the JSON under the temp dir, hands the staged '
      'path to the share sheet, and deletes it after the sheet resolves',
      () async {
        String? stagedPath;
        registerShareHandler(
          onHandoff: (path) {
            stagedPath = path;
            // While the share sheet reads the file, it is still there.
            final staged = File(path);
            expect(
              staged.existsSync(),
              isTrue,
              reason:
                  'the share target must be able to read the staged '
                  'file at hand-off time',
            );
            expect(
              staged.readAsStringSync(),
              '{"schema_version":1}',
              reason: 'the staged file carries the export content',
            );
          },
        );

        final shared = await shareFile(
          'cycle_export_test.json',
          '{"schema_version":1}',
        );

        expect(shared, isTrue, reason: 'a resolved sheet is a hand-off');
        expect(
          stagedPath,
          '${stagingDir.path}${Platform.pathSeparator}cycle_export_test.json',
          reason: 'the staged file lands in the platform temp directory',
        );
        expectStagedFileGone('cycle_export_test.json');
      },
    );

    test(
      'shareFile also deletes the staged file when the share fails',
      () async {
        registerShareHandler(throwPlatformException: true);

        final shared = await shareFile(
          'cycle_export_test.json',
          '{"schema_version":1}',
        );

        expect(shared, isFalse, reason: 'a channel failure is not a hand-off');
        expectStagedFileGone('cycle_export_test.json');
      },
    );

    test('shareFileBytes stages the PDF bytes and deletes the file after '
        'the sheet resolves', () async {
      final bytes = <int>[0x25, 0x50, 0x44, 0x46]; // "%PDF"
      String? stagedPath;
      registerShareHandler(
        onHandoff: (path) {
          stagedPath = path;
          final staged = File(path);
          expect(
            staged.readAsBytesSync(),
            bytes,
            reason: 'the staged file carries the PDF content',
          );
        },
      );

      final shared = await shareFileBytes('cycle_pdf_test.pdf', bytes);

      expect(shared, isTrue, reason: 'a resolved sheet is a hand-off');
      expect(
        stagedPath,
        '${stagingDir.path}${Platform.pathSeparator}cycle_pdf_test.pdf',
        reason: 'the staged file lands in the platform temp directory',
      );
      expectStagedFileGone('cycle_pdf_test.pdf');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(_pathProviderChannel, null)
        ..setMockMethodCallHandler(_sharePlusChannel, null);
      stagingDir.deleteSync(recursive: true);
    });
  });
}
