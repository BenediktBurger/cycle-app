// Widget test of the drip CSV import card/dialog in the settings screen,
// mirroring the app_shell_test pattern (in-memory drift database override,
// nothing file-based or platform-channel based).
//
// The locale is pinned explicitly so the German-string assertions hold no
// matter what locale the test runner's system reports (the system-follow
// default itself is covered by the locale tests, test/locale_test.dart).
import 'package:cycle_app/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';

ProviderScope _appScope([Locale? locale]) => appScope(locale: locale);

/// Whether the widget [tree] rooted at [w] contains a [Text] with [text]
/// (walks the plain container widgets the settings cards are made of; enough
/// for asserting card config, independent of which cards are currently
/// built in the lazy list).
bool _hasText(Widget w, String text) {
  if (w is Text) return w.data == text;
  if (w is Padding) return w.child != null && _hasText(w.child!, text);
  if (w is Card) return w.child != null && _hasText(w.child!, text);
  if (w is Column) return w.children.any((c) => _hasText(c, text));
  if (w is Row) return w.children.any((c) => _hasText(c, text));
  return false;
}

void main() {
  testWidgets(
      'drip import card sits below the JSON import card and its '
      'dialog requires CSV text before applying', (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();
    // Tap scoped to the navigation bar: all tabs stay mounted (IndexedStack),
    // so the 'Einstellungen' label also matches the offstage screen's AppBar
    // — and in tree order that AppBar precedes the bar, so a bare .first tap
    // would miss.
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Einstellungen')));
    await tester.pumpAndSettle();

    // The settings list is a lazy ListView; scroll down until the drip card
    // is built, then make sure its button is fully on-screen (the list is
    // allowed to grow above the drip card — e.g. the theme-mode switcher —
    // so fixed-amount drag loops would be brittle; the card ORDER assertion
    // below does not depend on how much content sits above). Both finders
    // are scoped to the settings screen: with the shell keeping every tab
    // mounted, the diary and statistics screens bring their own scrollables
    // and ListViews into the tree.
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
    expect(find.text('Drip-Daten importieren'), findsWidgets);

    // … and it comes AFTER the JSON export/import card in the card config.
    final listView = tester.firstWidget<ListView>(find.descendant(
        of: find.byType(EinstellungenScreen), matching: find.byType(ListView)));
    final children =
        (listView.childrenDelegate as SliverChildListDelegate).children;
    int cardIndex(String text) =>
        children.indexWhere((w) => w is Card && _hasText(w, text));
    expect(cardIndex('JSON-Import'), greaterThanOrEqualTo(0));
    expect(cardIndex('Drip-Daten importieren'), greaterThan(0));
    expect(cardIndex('Drip-Daten importieren'),
        greaterThan(cardIndex('JSON-Import')),
        reason: 'The drip card must sit below the JSON import card');

    // Opening the drip dialog: the launch button is pinned by its dedicated
    // label (dripImportButton, "CSV importieren"), distinct from the card
    // heading ("Drip-Daten importieren") AND from the dialog's Apply action
    // (checked after the dialog opens below).
    final dripButton =
        find.widgetWithText(FilledButton, 'CSV importieren').first;
    await tester.ensureVisible(dripButton);
    await tester.pumpAndSettle();
    await tester.tap(dripButton);
    await tester.pumpAndSettle();

    // The dialog carries a CSV textarea.
    final dialogTextFields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(dialogTextFields, findsOneWidget);

    // Apply is disabled until CSV text is present …
    // (The card's own launch button shares the "CSV importieren" label —
    // scoping to the dialog isolates the dialog's Apply action.)
    Finder applyButton() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'CSV importieren'));
    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);

    // … and enabled once the textarea holds text.
    await tester.enterText(dialogTextFields, 'date\n');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
  });
}
