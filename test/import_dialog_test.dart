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
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/file_transfer_io.dart'
    show acceptTypeGroup, pickFileTextOverride;
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
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
/// shell (sans the shell itself, see the file header).
Widget settingsHarness() => ProviderScope(
      overrides: [inMemoryDatabase()],
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
/// All taps go through the navigation bar / dedicated card labels: all tabs
/// stay mounted (IndexedStack), so the 'Einstellungen' label also matches the
/// offstage screen's AppBar.
Future<void> pumpAndOpenDripDialogInShell(WidgetTester tester) async {
  await tester.pumpWidget(appScope(locale: const Locale('de')));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text('Einstellungen')));
  await tester.pumpAndSettle();

  // Scroll the lazy settings list until the drip card is built; the finders
  // are scoped to the settings screen (the shell keeps the other tabs'
  // scrollables in the tree).
  await tester.scrollUntilVisible(
    find.text('Drip-Daten importieren'),
    200,
    scrollable: find
        .descendant(
            of: find.byType(EinstellungenScreen),
            matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'CSV importieren').first);
  await tester.pumpAndSettle();
}

void main() {
  group('import dialogs', () {
    testWidgets(
        'drip import dialog opens on a small Android viewport (keyboard up) '
        'without any overflow', (WidgetTester tester) async {
      useSmallAndroidViewport(tester);
      final errors = await collectFrameworkErrors(tester, () async {
        await tester.pumpWidget(settingsHarness());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Drip-Daten importieren'),
          200,
          scrollable: find
              .descendant(
                  of: find.byType(EinstellungenScreen),
                  matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        await tester
            .tap(find.widgetWithText(FilledButton, 'CSV importieren').first);
        await tester.pumpAndSettle();
        // The dialog is open; now the keyboard slides in and the dialog
        // relayouts into the reduced area — the reproducing step.
        await showKeyboardUp(tester);
        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'the repro needs the import dialog to actually open');
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
    });

    testWidgets(
        'the dialogs offer a file picker on the native (io) target '
        '(paste-only before: the button was gated off by canPickFile)',
        (WidgetTester tester) async {
      await pumpAndOpenDripDialogInShell(tester);
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
            of: dialog,
            matching: find.widgetWithText(OutlinedButton, 'Datei wählen')),
        findsOneWidget,
        reason: 'the native build must show the picker button now that a '
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
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(OutlinedButton, 'Datei wählen')));
        await tester.pumpAndSettle();
        final textField = find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField));
        expect(
          tester.widget<TextField>(textField).controller!.text,
          sampleDripCsv,
          reason: 'the picked file content must land in the textarea',
        );
        final apply = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'CSV importieren'));
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
        reason: 'dismissing the dialog while the import future is running '
            'must not produce a "used after being disposed"-style error from '
            'the dialog state',
      );
    });
  });

  group('accept-string translation for the native picker', () {
    test('default JSON accept produces the JSON type group', () {
      final group = acceptTypeGroup('application/json,.json');
      expect(group.label, 'JSON');
      expect(group.extensions, ['json']);
      expect(group.mimeTypes, ['application/json']);
    });

    test('CSV accept produces the CSV type group', () {
      final group = acceptTypeGroup('.csv,text/csv');
      expect(group.label, 'CSV');
      expect(group.extensions, ['csv']);
      expect(group.mimeTypes, ['text/csv']);
    });

    test('extension-only accept keeps only extensions', () {
      final group = acceptTypeGroup('.json');
      expect(group.label, 'JSON');
      expect(group.extensions, ['json']);
      expect(group.mimeTypes, isNull);
    });

    test('empty accept matches every file', () {
      final group = acceptTypeGroup('');
      expect(group.extensions, isNull);
      expect(group.mimeTypes, isNull);
    });

    test('unknown types fall back to the generic group', () {
      final group = acceptTypeGroup('application/octet-stream');
      expect(group.extensions, isNull);
      expect(group.mimeTypes, ['application/octet-stream']);
      expect(group.label, isNot(isIn(['JSON', 'CSV'])));
    });

    test('whitespace-padded and duplicate tokens stay stable', () {
      final group = acceptTypeGroup(' .csv , text/csv ');
      expect(group.label, 'CSV');
      expect(group.extensions, ['csv']);
      expect(group.mimeTypes, ['text/csv']);
    });
  });
}
