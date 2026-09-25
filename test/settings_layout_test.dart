// Widget test of the settings pane's LAYOUT after the reorganization:
// the card ORDER (general information -> paper history -> the remaining
// settings -> the export action card), the field grouping (name + birth
// date live in the general card, not under a "PDF-Export" title), the
// anonymization note's home (inside the export card, at its switch) and
// the absence of the standalone privacy card (the about page owns that
// text — see notices_test.dart for the copy pins).
//
// German device locale + full-app pump mirror the other settings tests;
// the pane is a lazy ListView, so the tests enlarge the surface (the
// setSurfaceSize pattern of settings_persistence_test.dart) and assert
// the built children directly — never on compact-view assumptions.
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

  /// The pane's card widgets in tree order. Called only when the enlarged
  /// surface has built the whole list (see the per-test enlargeViewport).
  Iterable<Card> cards(WidgetTester tester) =>
      tester.widgetList<Card>(find.byType(Card));

  /// The settings pane's cards sit flat (no nested Cards), so a keyed
  /// descendant resolves each card unambiguously.
  Finder cardOf(Finder inner) =>
      find.ancestor(of: inner, matching: find.byType(Card));

  int indexOfCard(WidgetTester tester, Finder cardFinder) {
    final target = cardFinder.evaluate().single;
    final list = find.byType(Card).evaluate().toList();
    return list.indexOf(target);
  }

  group('card order', () {
    testWidgets('general information first, paper history next to it, language '
        'card after them, delete data stays the last card', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpGermanSettingsPane(tester);

      final generalCard = find.byKey(const ValueKey('generalInfoCard'));
      final paperCard = find.byKey(const ValueKey('paperHistoryCard'));
      expect(
        generalCard,
        findsOneWidget,
        reason: 'the general-information card carries a test key',
      );
      expect(
        paperCard,
        findsOneWidget,
        reason: 'the paper-history card carries a test key',
      );
      final languageCard = cardOf(
        find.byKey(const ValueKey('languageSwitcher')),
      );
      final deleteCard = cardOf(
        find.byKey(const ValueKey('settingsDeleteDataButton')),
      );

      final positionGeneral = indexOfCard(tester, generalCard);
      final positionPaper = indexOfCard(tester, paperCard);
      final positionLanguage = indexOfCard(tester, languageCard);
      final positionDelete = indexOfCard(tester, deleteCard);

      expect(
        positionGeneral < positionPaper && positionPaper < positionLanguage,
        isTrue,
        reason:
            'the general-information card is followed directly by the '
            'paper-history card (the owner-ordered top of the pane), and '
            'the language card comes only after them (got general @$positionGeneral, '
            'paper @$positionPaper, language @$positionLanguage of '
            '${cards(tester).length} cards)',
      );
      expect(
        positionDelete,
        cards(tester).length - 1,
        reason: 'the delete-data (danger) card stays the pane\'s last card',
      );
    });
  });

  group('general information card', () {
    testWidgets(
      'carries the name and birth-date fields plus the optional/usage '
      'caption, and no PDF-titled identifying card remains',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpGermanSettingsPane(tester);

        final generalCard = find.byKey(const ValueKey('generalInfoCard'));
        expect(
          find.descendant(
            of: generalCard,
            matching: find.byKey(const ValueKey('pdfExportNameField')),
          ),
          findsOneWidget,
          reason: 'the name field moved into the general-information card',
        );
        expect(
          find.descendant(
            of: generalCard,
            matching: find.byKey(const ValueKey('pdfExportBirthDateField')),
          ),
          findsOneWidget,
          reason: 'the birth-date field moved into the card too',
        );
        expect(
          find.descendant(
            of: generalCard,
            matching: find.text(
              'Optional. Die Angaben werden für die Exportfunktion und die '
              'Statistik verwendet.',
            ),
          ),
          findsOneWidget,
          reason:
              'the card says right under its title that the entries are '
              'optional and what they are used for',
        );

        expect(
          find.text('PDF-Export'),
          findsOneWidget,
          reason:
              'the PDF export title now belongs to the ACTION card only — '
              'the identifying-values card (formerly also titled '
              '"PDF-Export") is gone',
        );
      },
    );
  });

  group('anonymization note', () {
    testWidgets(
      'the note sits inside the export card, together with the anonymize '
      'switch (not at the data entry)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpGermanSettingsPane(tester);

        final note = find.text(
          'Blendet eingeschaltet Name und Geburtsdatum aus dem Kopfbereich '
          'des jeweiligen Exports aus, ohne die Speicherung zu ändern.',
        );
        expect(
          find.descendant(
            of: cardOf(pdfExportAnonymizeSwitch().first),
            matching: note,
          ),
          findsOneWidget,
          reason:
              'the anonymization explanation lives at the control it '
              'explains — the anonymize switch inside the export card',
        );
      },
    );
  });

  group('privacy notice', () {
    testWidgets(
      'the settings pane carries no Datenschutzhinweis card (the about '
      'page owns the text; see notices_test.dart)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpGermanSettingsPane(tester);

        expect(
          find.text('Datenschutz'),
          findsNothing,
          reason:
              'the standalone privacy card is removed from the settings '
              'pane — the notice stays reachable via the AppBar info '
              'action (about page)',
        );
      },
    );
  });
}
