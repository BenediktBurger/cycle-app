// The DSGVO/privacy notice (the drafted German paragraph from the roadmap's
// "add necessary DSGVO notice" item): states the app's data-control reality —
// local-only storage, nothing ever sent, GDPR rights exercisable directly in
// the app. Two surfaces share one string source: the settings pane's
// "Datenschutz" card and the about/onboarding content page.
//
// German device locale mirrors the app's German-first posture.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

void main() {
  /// German device + seeded onboarding flag: the shell is reachable and the
  /// settings pane is the navigation surface both groups start from.
  Future<void> pumpGermanSettingsPane(WidgetTester tester) async {
    useDeviceLocales(tester, const [Locale('de')]);

    Future<void> seed(CycleDatabase db) =>
        SettingsStore(db.settingsDao).persistOnboardingCompleted(true);

    await tester.pumpWidget(appScope(locale: const Locale('de'), seed: seed));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('Einstellungen'));
    await tester.pumpAndSettle();
  }

  /// Opens the shared content page from the settings pane's app bar info
  /// action.
  Future<void> openAboutPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('aboutAction')));
    await tester.pumpAndSettle();
  }

  group('DSGVO notice', () {
    testWidgets('the settings pane shows the Datenschutz card with the notice',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);

      // The card sits below the fold together with the later cards.
      await tester.dragUntilVisible(find.text('Datenschutz'),
          find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.text('Datenschutz'), findsOneWidget,
          reason: 'the settings pane carries the privacy notice as its own '
              '"Datenschutz" card');
      expect(find.textContaining('ausschließlich lokal'), findsOneWidget,
          reason: 'the local-only storage statement is the notice\'s core');
      expect(find.textContaining('niemals gesendet'), findsOneWidget,
          reason: 'the notice must state that data is never sent — not even '
              'on a crash');
      expect(find.textContaining('Rechte aus der DSGVO'), findsOneWidget,
          reason: 'the GDPR rights sentence with its in-app exercise paths '
              'belongs to the notice');
    });

    testWidgets('the about page carries the same privacy text',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);
      await openAboutPage(tester);

      expect(find.text('Datenschutz'), findsOneWidget,
          reason: 'the about page is the onboarding content — it must show '
              'the same notice, heading included');
      expect(find.textContaining('ausschließlich lokal'), findsOneWidget,
          reason: 'the settings card and the about page share ONE string '
              'source, the same sentence both times');
      expect(find.textContaining('niemals gesendet'), findsOneWidget);
    });
  });

  group('backup / migration / recovery wording', () {
    testWidgets('the export card note names the backup role',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);

      // The export card sits below the fold; scroll it into the built
      // viewport range before asserting the note text.
      await tester.dragUntilVisible(find.textContaining('einzige Sicherung'),
          find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.textContaining('einzige Sicherung'), findsOneWidget,
          reason: 'the JSON export is the ONLY backup path — the export '
              'card note must say so (and only via export/import: the '
              'database file cannot be copied)');
      expect(find.textContaining('nicht kopiert'), findsOneWidget,
          reason: 'the note must rule out copying the encrypted, '
              'device-bound database file (ADR-0005 posture)');
    });

    testWidgets('the about page carries the backup hint',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);
      await openAboutPage(tester);

      await tester.dragUntilVisible(
          find.textContaining('nur über den JSON-Export/-Import'),
          find.byType(ListView),
          const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.textContaining('nur über den JSON-Export/-Import'),
          findsOneWidget,
          reason: 'the about/onboarding page points to the backed-up role '
              'of the export/import in the settings');
      expect(find.textContaining('an dieses Gerät gebunden'), findsOneWidget,
          reason: 'the device-bound encryption key is the REASON copying '
              'the database file is never a backup');
    });
  });

  group('feedback notice', () {
    testWidgets('the about page footer carries the send-nothing feedback note',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);
      await openAboutPage(tester);

      // The note is the page's footer: bring it into the built viewport.
      await tester.dragUntilVisible(find.textContaining('sendet nichts'),
          find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.textContaining('sendet nichts'), findsOneWidget,
          reason: 'the notice must state that the app does not send '
              'anything ever, not even at a crash');
      expect(find.textContaining('cycle-app/issues'), findsOneWidget,
          reason: 'the factual GitHub issue-tracker link (the README\'s '
              'project URL) belongs to the note');
      expect(find.textContaining('E-Mail'), findsOneWidget,
          reason: 'a mail option is offered per a generic sentence without '
              'inventing an address (none is committed anywhere)');
    });

    testWidgets('the settings pane closes with a compact feedback line',
        (WidgetTester tester) async {
      await pumpGermanSettingsPane(tester);

      await tester.dragUntilVisible(find.textContaining('E-Mail'),
          find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.textContaining('GitHub-Issue'), findsOneWidget,
          reason: 'a compact feedback line ends the settings pane: errors '
              'and suggestions go to the GitHub issue tracker or mail');
    });
  });
}
