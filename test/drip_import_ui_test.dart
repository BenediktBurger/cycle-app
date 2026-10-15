// Widget test of the drip CSV import card/dialog in the settings screen,
// mirroring the app_shell_test pattern (in-memory drift database override,
// nothing file-based or platform-channel based).
//
// The locale is pinned explicitly so the German-string assertions hold no
// matter what locale the test runner's system reports (the system-follow
// default itself is covered by the locale tests, test/locale_test.dart).
import 'package:cycle_app/ui/settings.dart';
import 'package:cycle_app/ui/settings/drip_import_card.dart';
import 'package:cycle_app/ui/settings/export_import_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';

void main() {
  testWidgets('drip import card sits below the JSON import card and its '
      'dialog requires CSV text before applying', (WidgetTester tester) async {
    await tester.pumpWidget(appScope(locale: const Locale('de')));
    await tester.pumpAndSettle();
    await openSettingsTab(tester);
    await scrollSettingsCardIntoView(tester, settingsImportDripButton());
    expect(find.text('Drip-Daten importieren'), findsWidgets);

    // … and it comes AFTER the JSON export/import card in the card config.
    final listView = tester.firstWidget<ListView>(
      find.descendant(
        of: find.byType(EinstellungenScreen),
        matching: find.byType(ListView),
      ),
    );
    final children =
        (listView.childrenDelegate as SliverChildListDelegate).children;
    final jsonImportIndex = children.indexWhere((w) => w is ExportImportCard);
    final dripImportIndex = children.indexWhere((w) => w is DripImportCard);
    expect(jsonImportIndex, greaterThanOrEqualTo(0));
    expect(dripImportIndex, greaterThanOrEqualTo(0));
    expect(
      dripImportIndex,
      greaterThan(jsonImportIndex),
      reason: 'The drip card must sit below the JSON import card',
    );

    // Opening the drip dialog: the launch button is keyed
    // (settingsImportDripButton), distinct from the card heading
    // ('Drip-Daten importieren') AND from the dialog's Apply action
    // (shares the button's l10n label; scoped to the dialog below).
    final dripButton = settingsImportDripButton();
    await tester.ensureVisible(dripButton);
    await tester.pumpAndSettle();
    await tester.tap(dripButton);
    await tester.pumpAndSettle();

    // The dialog carries a CSV textarea.
    final dialogTextFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogTextFields, findsOneWidget);

    // Apply is disabled until CSV text is present …
    // (The card's own launch button shares the "CSV importieren" label —
    // scoping to the dialog isolates the dialog's Apply action.)
    Finder applyButton() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'CSV importieren'),
    );
    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);

    // … and enabled once the textarea holds text.
    await tester.enterText(dialogTextFields, 'date\n');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
  });
}
