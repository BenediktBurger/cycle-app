// The DSGVO/privacy notice (German wording): states the app's data-control
// reality — local-only storage, nothing ever sent, GDPR rights exercisable
// directly in the app. Its single surface is the about/onboarding content
// page, reached via the settings pane's AppBar info action.
//
// German device locale mirrors the app's German-first posture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/viewport.dart';

void main() {
  /// German locale + direct settings-screen pump. The pane is a lazy
  /// ListView: callers enlarge the surface and/or drag the target into the
  /// built viewport.
  Future<void> pumpGermanSettingsPane(WidgetTester tester) async {
    useTallSurface(tester, width: 900);

    await tester.pumpWidget(settingsHarness());
    await tester.pumpAndSettle();
  }

  /// Opens the shared content page from the settings pane's app bar info
  /// action.
  Future<void> openAboutPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('aboutAction')));
    await tester.pumpAndSettle();
  }

  group('DSGVO notice', () {
    testWidgets('the about page carries the full privacy notice', (
      WidgetTester tester,
    ) async {
      await pumpGermanSettingsPane(tester);
      await openAboutPage(tester);

      expect(
        find.text('Datenschutz'),
        findsOneWidget,
        reason: 'the notice sits under its heading',
      );
      expect(
        find.textContaining('ausschließlich lokal'),
        findsOneWidget,
        reason: 'the local-only storage statement is the notice\'s core',
      );
      expect(
        find.textContaining('niemals gesendet'),
        findsOneWidget,
        reason:
            'the notice must state that data is never sent — not even '
            'on a crash',
      );
      expect(
        find.textContaining('Rechte aus der DSGVO'),
        findsOneWidget,
        reason:
            'the GDPR rights sentence with its in-app exercise paths '
            'belongs to the notice',
      );
      expect(
        find.textContaining('Auf Android und iOS'),
        findsOneWidget,
        reason:
            'the encrypted-at-rest claim must be qualified to the '
            'native platforms: Android and iOS store the database '
            'encrypted (device-bound key, ADR-0005)',
      );
      expect(
        find.textContaining('unterstütztes Ziel'),
        findsOneWidget,
        reason:
            'the notice names the web app as a supported target, '
            'matching the shipped status',
      );
      expect(
        find.textContaining('nicht verschlüsselt'),
        findsOneWidget,
        reason:
            'the web app\'s browser storage (OPFS/IndexedDB) is '
            'NOT encrypted by the app — the notice must say so',
      );
      expect(
        find.textContaining('Exportiere deshalb regelmäßig'),
        findsOneWidget,
        reason:
            'browser storage is unencrypted, so the notice asks for '
            'regular exports; export/import remains the only backup',
      );
    });
  });

  group('backup / migration / recovery wording', () {
    testWidgets('the export card note names the backup role', (
      WidgetTester tester,
    ) async {
      await pumpGermanSettingsPane(tester);

      // The export card sits below the fold; scroll it into the built
      // viewport range before asserting the note text.
      await tester.dragUntilVisible(
        find.textContaining('einzige Sicherung'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('einzige Sicherung'),
        findsOneWidget,
        reason:
            'the JSON export is the ONLY backup path — the export '
            'card note must say so (and only via export/import: the '
            'database file cannot be copied)',
      );
      expect(
        find.textContaining('nicht kopiert'),
        findsOneWidget,
        reason:
            'the note must rule out copying the encrypted, '
            'device-bound database file (ADR-0005 posture)',
      );
    });

    testWidgets('the about page carries the backup hint', (
      WidgetTester tester,
    ) async {
      await pumpGermanSettingsPane(tester);
      await openAboutPage(tester);

      await tester.dragUntilVisible(
        find.textContaining('nur über Export und Import'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('nur über Export und Import'),
        findsOneWidget,
        reason:
            'the about/onboarding page points to the backed-up role '
            'of the export/import in the settings',
      );
      expect(
        find.textContaining('an dieses Gerät gebunden'),
        findsOneWidget,
        reason:
            'the device-bound encryption key is the REASON copying '
            'the database file is never a backup',
      );
    });
  });

  group('feedback notice', () {
    testWidgets(
      'the about page footer carries the send-nothing feedback note',
      (WidgetTester tester) async {
        await pumpGermanSettingsPane(tester);
        await openAboutPage(tester);

        // The note is the page's footer: bring it into the built viewport.
        await tester.dragUntilVisible(
          find.textContaining('sendet nichts'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('sendet nichts'),
          findsOneWidget,
          reason:
              'the notice must state that the app does not send '
              'anything ever, not even at a crash',
        );
        // The footer's issue-tracker address also appears as the tappable
        // contact row's plain URL text one section above; the parenthesized
        // form here is footer text only (the row text has no closing paren).
        expect(
          find.textContaining('cycle-app/issues)'),
          findsOneWidget,
          reason:
              'the factual GitHub issue-tracker link (the README\'s '
              'project URL) belongs to the note',
        );
        expect(
          find.textContaining('E-Mail'),
          findsOneWidget,
          reason:
              'a mail option is offered per a generic sentence without '
              'inventing an address (none is committed anywhere)',
        );
      },
    );

    testWidgets('the settings pane closes with a compact feedback line', (
      WidgetTester tester,
    ) async {
      await pumpGermanSettingsPane(tester);

      await tester.dragUntilVisible(
        find.textContaining('E-Mail'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('GitHub-Issue'),
        findsOneWidget,
        reason:
            'a compact feedback line ends the settings pane: errors '
            'and suggestions go to the GitHub issue tracker or mail',
      );
    });
  });
}
