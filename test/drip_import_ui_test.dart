// Widget test of the drip CSV import card/dialog in the settings screen,
// mirroring the app_shell_test pattern (in-memory drift database override,
// nothing file-based or platform-channel based).
//
// The locale is pinned explicitly so the German-string assertions hold no
// matter what locale the test runner's system reports (the system-follow
// default itself is covered by locale_default_test.dart).
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/providers.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderScope _appScope([Locale? locale]) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith(
          (ref) {
            final db = CycleDatabase(
              DatabaseConnection(
                NativeDatabase.memory(),
                closeStreamsSynchronously: true,
              ),
            );
            ref.onDispose(db.close);
            return db;
          },
        ),
        if (locale != null) localeProvider.overrideWith((ref) => locale),
      ],
      child: const CycleApp(),
    );

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
  testWidgets('drip import card sits below the JSON import card and its '
      'dialog requires CSV text before applying', (WidgetTester tester) async {
    await tester.pumpWidget(_appScope(const Locale('de')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen').first);
    await tester.pumpAndSettle();

    // The settings list is a lazy ListView; drag up (content moves up = we
    // look further down) until the drip card is built.
    for (var i = 0;
        i < 4 && find.text('Drip-Daten importieren').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.text('Drip-Daten importieren'), findsWidgets);

    // … and it comes AFTER the JSON export/import card in the card config.
    final listView = tester.firstWidget<ListView>(find.byType(ListView));
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
