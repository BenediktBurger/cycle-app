// The "Eigene Kategorien" settings card: end-to-end (the REAL CycleApp
// against the in-memory drift database override, same shape as
// what_to_track_setting_test.dart) — every edit goes through
// customDiaryCategoriesProvider and writes through to the app_settings
// row, a seeded row hydrates into the card, and the label guards (trim,
// caps, duplicates) reject without altering stored data.
import 'package:cycle_app/db/cycle_database.dart';
import 'package:cycle_app/db/settings_store.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';
import 'support/viewport.dart';

// The card keys its rows by position AND category name: names are unique
// among UI-created rows (duplicates are rejected), and the position keeps
// the keys distinct even for hand-edited rows that carry duplicate names
// (the JSON decoders stay lenient).
Finder categoryRow(int index, String name) =>
    find.byKey(ValueKey('customCategoryRow-$index-$name'));
Finder nameField(int index, String name) =>
    find.byKey(ValueKey('customCategoryNameField-$index-$name'));
Finder nameError(int index, String name) =>
    find.byKey(ValueKey('customCategoryNameError-$index-$name'));
Finder visibleSwitch(int index, String name) =>
    find.byKey(ValueKey('customCategoryVisibleSwitch-$index-$name'));
Finder moveUpButton(int index, String name) =>
    find.byKey(ValueKey('customCategoryMoveUp-$index-$name'));
Finder moveDownButton(int index, String name) =>
    find.byKey(ValueKey('customCategoryMoveDown-$index-$name'));
Finder deleteButton(int index, String name) =>
    find.byKey(ValueKey('customCategoryDelete-$index-$name'));
Finder entryText(int index, String name, int entryIndex, String entry) =>
    find.byKey(ValueKey('customCategoryEntry-$index-$name-$entryIndex-$entry'));
Finder entryRemoveButton(
  int index,
  String name,
  int entryIndex,
  String entry,
) => find.byKey(
  ValueKey('customCategoryEntryRemove-$index-$name-$entryIndex-$entry'),
);
Finder entryField(int index, String name) =>
    find.byKey(ValueKey('customCategoryEntryField-$index-$name'));
Finder entryError(int index, String name) =>
    find.byKey(ValueKey('customCategoryEntryError-$index-$name'));
Finder entryAddButton(int index, String name) =>
    find.byKey(ValueKey('customCategoryEntryAdd-$index-$name'));
Finder addCategoryField() =>
    find.byKey(const ValueKey('customCategoryAddField'));
Finder addCategoryButton() =>
    find.byKey(const ValueKey('customCategoryAddButton'));
Finder addCategoryError() =>
    find.byKey(const ValueKey('customCategoryAddError'));

/// Pumps the real app, opens the settings tab and scrolls the custom
/// categories card into view. Returns the created in-memory database for
/// stored-row assertions.
Future<CycleDatabase> openCard(
  WidgetTester tester, {
  Future<void> Function(CycleDatabase db)? seed,
}) async {
  useTallSurface(tester);
  CycleDatabase? db;
  await tester.pumpWidget(
    appScope(
      locale: const Locale('de'),
      seed: seed,
      onCreated: (created) => db = created,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(navLabel('Einstellungen'));
  await tester.pumpAndSettle();
  await scrollSettingsCardIntoView(
    tester,
    find.byKey(const ValueKey('customCategoriesCard')),
  );
  return db!;
}

/// Types [text] into [field] and commits with the keyboard's done action —
/// the rename flow.
Future<void> submitText(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// The raw JSON list stored under the customDiaryCategories key (null when
/// the row is absent, i.e. no categories ever stored).
Future<Object?> storedRaw(CycleDatabase db) => SettingsStore(
  db.settingsDao,
).readSetting(SettingKeys.customDiaryCategories);

void main() {
  group('Custom categories card (add)', () {
    testWidgets('adding a category writes through and renders a row', (
      WidgetTester tester,
    ) async {
      final db = await openCard(tester);

      await tester.enterText(addCategoryField(), 'Sport');
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();

      expect(categoryRow(0, 'Sport'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': true, 'items': <Object?>[]},
      ], reason: 'the added category persists as the one definitions row');
    });

    testWidgets('a category name is trimmed before storing', (
      WidgetTester tester,
    ) async {
      final db = await openCard(tester);

      await tester.enterText(addCategoryField(), '  Sport  ');
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();

      expect(categoryRow(0, 'Sport'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': true, 'items': <Object?>[]},
      ], reason: 'the stored label is the trimmed name');
    });
  });

  group('Custom categories card (rename)', () {
    testWidgets('renaming trims and writes through without touching items', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) =>
            SettingsStore(db.settingsDao).persistCustomCategories(const [
              CustomCategory(name: 'Sport', items: ['Joggen']),
            ]),
      );

      await submitText(tester, nameField(0, 'Sport'), '  Bewegung  ');

      expect(categoryRow(0, 'Bewegung'), findsOneWidget);
      expect(categoryRow(0, 'Sport'), findsNothing);
      expect(
        await storedRaw(db),
        [
          {
            'name': 'Bewegung',
            'visible': true,
            'items': ['Joggen'],
          },
        ],
        reason: 'the rename replaces only the name — items and visibility stay',
      );
    });

    testWidgets('a valid rename after a rejected one clears the error', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(db.settingsDao).persistCustomCategories(
          const [CustomCategory(name: 'Sport'), CustomCategory(name: 'Ruhe')],
        ),
      );

      await submitText(tester, nameField(0, 'Sport'), 'Ruhe');
      expect(nameError(0, 'Sport'), findsOneWidget);

      await submitText(tester, nameField(0, 'Sport'), 'Bewegung');

      expect(nameError(0, 'Sport'), findsNothing);
      expect(
        nameError(0, 'Bewegung'),
        findsNothing,
        reason:
            'the rejected submission\'s error must not outlive a '
            'successful rename in the same row',
      );
      expect(categoryRow(0, 'Bewegung'), findsOneWidget);
      expect(categoryRow(1, 'Ruhe'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'Bewegung', 'visible': true, 'items': <Object?>[]},
        {'name': 'Ruhe', 'visible': true, 'items': <Object?>[]},
      ]);
    });
  });

  group('Custom categories card (visibility)', () {
    testWidgets('the visibility switch flips the stored visible flag', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(
          db.settingsDao,
        ).persistCustomCategories(const [CustomCategory(name: 'Sport')]),
      );

      await tester.tap(visibleSwitch(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': false, 'items': <Object?>[]},
      ]);

      await tester.tap(visibleSwitch(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': true, 'items': <Object?>[]},
      ]);
    });
  });

  group('Custom categories card (entries)', () {
    testWidgets('adding and removing entries writes through in order', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(
          db.settingsDao,
        ).persistCustomCategories(const [CustomCategory(name: 'Sport')]),
      );

      await tester.enterText(entryField(0, 'Sport'), 'Joggen');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {
          'name': 'Sport',
          'visible': true,
          'items': ['Joggen'],
        },
      ]);

      await tester.enterText(entryField(0, 'Sport'), 'Kraft');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {
          'name': 'Sport',
          'visible': true,
          'items': ['Joggen', 'Kraft'],
        },
      ], reason: 'entries keep their addition order');

      await tester.tap(entryRemoveButton(0, 'Sport', 0, 'Joggen'));
      await tester.pumpAndSettle();
      expect(entryText(0, 'Sport', 0, 'Kraft'), findsOneWidget);
      expect(await storedRaw(db), [
        {
          'name': 'Sport',
          'visible': true,
          'items': ['Kraft'],
        },
      ], reason: 'removing an entry leaves the other entries untouched');
    });

    testWidgets('a valid add after a rejected one clears the error', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) =>
            SettingsStore(db.settingsDao).persistCustomCategories(const [
              CustomCategory(name: 'Sport', items: ['Joggen']),
            ]),
      );

      await tester.enterText(entryField(0, 'Sport'), 'Joggen');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(entryError(0, 'Sport'), findsOneWidget);

      await tester.enterText(entryField(0, 'Sport'), 'Kraft');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();

      expect(
        entryError(0, 'Sport'),
        findsNothing,
        reason:
            'the rejected submission\'s error must not outlive a '
            'successful add in the same row',
      );
      expect(entryText(0, 'Sport', 1, 'Kraft'), findsOneWidget);
      expect(await storedRaw(db), [
        {
          'name': 'Sport',
          'visible': true,
          'items': ['Joggen', 'Kraft'],
        },
      ]);
    });
  });

  group('Custom categories card (reorder)', () {
    testWidgets('moving a category keeps the stored and rendered order', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) =>
            SettingsStore(db.settingsDao).persistCustomCategories(const [
              CustomCategory(name: 'A'),
              CustomCategory(name: 'B'),
              CustomCategory(name: 'C'),
            ]),
      );

      await tester.tap(moveDownButton(0, 'A'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {'name': 'B', 'visible': true, 'items': <Object?>[]},
        {'name': 'A', 'visible': true, 'items': <Object?>[]},
        {'name': 'C', 'visible': true, 'items': <Object?>[]},
      ], reason: 'moving A down swaps it with B');
      expect(
        tester.getTopLeft(categoryRow(0, 'B')).dy,
        lessThan(tester.getTopLeft(categoryRow(1, 'A')).dy),
      );

      await tester.tap(moveUpButton(1, 'A'));
      await tester.pumpAndSettle();
      expect(await storedRaw(db), [
        {'name': 'A', 'visible': true, 'items': <Object?>[]},
        {'name': 'B', 'visible': true, 'items': <Object?>[]},
        {'name': 'C', 'visible': true, 'items': <Object?>[]},
      ], reason: 'moving A up restores the original order');
    });
  });

  group('Custom categories card (delete)', () {
    testWidgets('deleting a category removes only that category', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(db.settingsDao).persistCustomCategories(
          const [CustomCategory(name: 'A'), CustomCategory(name: 'B')],
        ),
      );

      await tester.tap(deleteButton(0, 'A'));
      await tester.pumpAndSettle();

      expect(categoryRow(0, 'A'), findsNothing);
      expect(categoryRow(0, 'B'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'B', 'visible': true, 'items': <Object?>[]},
      ]);
    });
  });

  group('Custom categories card (guards)', () {
    testWidgets('a duplicate category name is rejected', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(
          db.settingsDao,
        ).persistCustomCategories(const [CustomCategory(name: 'Sport')]),
      );

      await tester.enterText(addCategoryField(), ' Sport ');
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();

      expect(addCategoryError(), findsOneWidget);
      expect(categoryRow(0, 'Sport'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': true, 'items': <Object?>[]},
      ], reason: 'the duplicate is rejected after trimming — nothing stored');
    });

    testWidgets('a duplicate entry name within a category is rejected', (
      WidgetTester tester,
    ) async {
      final db = await openCard(
        tester,
        seed: (db) =>
            SettingsStore(db.settingsDao).persistCustomCategories(const [
              CustomCategory(name: 'Sport', items: ['Joggen']),
            ]),
      );

      await tester.enterText(entryField(0, 'Sport'), 'Joggen');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();

      expect(entryError(0, 'Sport'), findsOneWidget);
      expect(await storedRaw(db), [
        {
          'name': 'Sport',
          'visible': true,
          'items': ['Joggen'],
        },
      ], reason: 'the duplicate entry is rejected — the list stays unchanged');
    });

    testWidgets('a label over the length cap is rejected', (
      WidgetTester tester,
    ) async {
      final db = await openCard(tester);
      final tooLong = 'x' * (customLabelMaxLength + 1);

      await tester.enterText(addCategoryField(), tooLong);
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();
      expect(addCategoryError(), findsOneWidget);
      expect(await storedRaw(db), isNull, reason: 'no category row written');

      await tester.enterText(addCategoryField(), 'Sport');
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();

      await tester.enterText(entryField(0, 'Sport'), tooLong);
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();
      expect(entryError(0, 'Sport'), findsOneWidget);
      expect(await storedRaw(db), [
        {'name': 'Sport', 'visible': true, 'items': <Object?>[]},
      ], reason: 'the over-cap entry is rejected — the items stay empty');
    });

    testWidgets('the 11th category is rejected', (WidgetTester tester) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(db.settingsDao).persistCustomCategories([
          for (var i = 1; i <= maxCustomCategories; i++)
            CustomCategory(name: 'K$i'),
        ]),
      );

      await tester.enterText(addCategoryField(), 'X');
      await tester.tap(addCategoryButton());
      await tester.pumpAndSettle();

      expect(addCategoryError(), findsOneWidget);
      expect(categoryRow(10, 'X'), findsNothing);
      final stored = await storedRaw(db) as List<Object?>;
      expect(stored, hasLength(maxCustomCategories));
    });

    testWidgets('the 16th entry is rejected', (WidgetTester tester) async {
      final db = await openCard(
        tester,
        seed: (db) => SettingsStore(db.settingsDao).persistCustomCategories([
          CustomCategory(
            name: 'Sport',
            items: [for (var i = 1; i <= maxCustomCategoryEntries; i++) 'E$i'],
          ),
        ]),
      );

      await scrollSettingsCardIntoView(tester, entryField(0, 'Sport'));
      await tester.enterText(entryField(0, 'Sport'), 'X');
      await tester.tap(entryAddButton(0, 'Sport'));
      await tester.pumpAndSettle();

      expect(entryError(0, 'Sport'), findsOneWidget);
      expect(entryText(0, 'Sport', 15, 'X'), findsNothing);
      final stored = await storedRaw(db) as List<Object?>;
      expect(
        (stored.single as Map<Object?, Object?>)['items'],
        hasLength(maxCustomCategoryEntries),
      );
    });
  });
}
