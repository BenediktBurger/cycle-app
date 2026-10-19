// Widget tests of the Tagebuch entry form's custom-category sections
// ("eigene Kategorien"): one chip section per VISIBLE category in
// definitions order, FilterChip multi-select per entry, the single toggle
// chip for an entry-less category, tick seeding from the loaded day's
// stored map, and the save-time merge rule (categories outside the current
// definitions keep their stored items verbatim; known categories are fully
// controlled by their chips).
//
// Harness: the pinned-clock DiaryHarness over the in-memory database with
// customDiaryCategoriesProvider pinned to the test's definitions; German
// locale (labels are user data, the section headers print them verbatim).
import 'package:cycle_app/db/mappers.dart';
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:cycle_app/domain/models.dart';
import 'package:cycle_app/ui/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/diary_harness.dart';
import 'support/finders.dart';

// A chip of the custom-mark sections: [entry] omitted for the single
// toggle chip of an entry-less category (key `customMarkChip-<category>`),
// present for an entry chip (key `customMarkChip-<category>-<entry>`).
Finder customMarkChip(String category, [String? entry]) => find.byKey(
  ValueKey(
    entry == null
        ? 'customMarkChip-$category'
        : 'customMarkChip-$category-$entry',
  ),
);

Finder sectionHeader(String title) =>
    find.byWidgetPredicate((w) => w is SectionHeader && w.title == title);

final _now = DateTime(2026, 5, 10, 9);

const _sport = CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']);
const _medikamente = CustomCategory(
  name: 'Medikamente',
  visible: false,
  items: ['Ibuprofen'],
);
const _launen = CustomCategory(name: 'Launen');

/// The stored custom marks of the harness's selected day, read back through
/// the same database the form writes with.
Future<Map<String, List<String>>> storedMarks(DiaryHarness harness) async {
  final row = await harness.db!.entriesDao.entryFor(harness.selectedDay);
  return row == null
      ? <String, List<String>>{}
      : dailyEntryFromDrift(row).customMarks;
}

/// Saves the day through the form's bottom save button (untouched otherwise).
Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(diarySaveButton());
  await tester.pumpAndSettle();
  await tester.tap(diarySaveButton());
  await tester.pumpAndSettle();
}

/// Pumps the entry form over the harness scope with [categories] as the
/// pinned definitions and — when given — [stored] seeded onto the selected
/// day, then enlarges the surface so the custom sections and the save
/// button are built and tappable. Returns the harness (its database for
/// stored-map readbacks).
Future<DiaryHarness> pumpForm(
  WidgetTester tester, {
  required List<CustomCategory> categories,
  Map<String, List<String>>? stored,
}) async {
  final harness = DiaryHarness(now: _now);
  await tester.pumpWidget(
    harness.scope(
      customCategories: categories,
      seed: stored == null
          ? null
          : (db) => db.entriesDao.upsertDaily(
              DailyEntry(date: harness.selectedDay, customMarks: stored),
            ),
    ),
  );
  await tester.pumpAndSettle();
  harness.tallSurface(tester);
  return harness;
}

void main() {
  testWidgets(
    'one section per visible category in definitions order, invisible ones hidden',
    (tester) async {
      await pumpForm(tester, categories: [_sport, _medikamente, _launen]);

      expect(sectionHeader('Sport'), findsOneWidget);
      expect(sectionHeader('Launen'), findsOneWidget);
      // An invisible category renders nothing at all — no header, no chips.
      expect(sectionHeader('Medikamente'), findsNothing);
      expect(find.text('Medikamente'), findsNothing);
      expect(customMarkChip('Medikamente', 'Ibuprofen'), findsNothing);

      // The custom sections sit after the pain section and before the
      // notes field (vertical order of the laid-out form).
      final painTop = tester.getRect(sectionHeader('Schmerzen')).top;
      final sportTop = tester.getRect(sectionHeader('Sport')).top;
      final launenTop = tester.getRect(sectionHeader('Launen')).top;
      final notesTop = tester.getRect(find.text('Notizen')).top;
      expect(painTop, lessThan(sportTop));
      expect(sportTop, lessThan(launenTop));
      expect(launenTop, lessThan(notesTop));
    },
  );

  testWidgets('entry chips multi-select and round-trip through the save', (
    tester,
  ) async {
    final harness = await pumpForm(tester, categories: [_sport]);

    await tester.ensureVisible(customMarkChip('Sport', 'Joggen'));
    await tester.pumpAndSettle();
    await tester.tap(customMarkChip('Sport', 'Joggen'));
    await tester.pumpAndSettle();
    await tester.tap(customMarkChip('Sport', 'Kraft'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(await storedMarks(harness), {
      'Sport': ['Joggen', 'Kraft'],
    });

    // The ticks survive in the form state: deselecting one and saving
    // again stores exactly the remaining ticked entries.
    await tester.tap(customMarkChip('Sport', 'Joggen'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(await storedMarks(harness), {
      'Sport': ['Kraft'],
    });
  });

  testWidgets(
    'entry-less category: one toggle chip, ON stores the bare key, OFF removes it',
    (tester) async {
      final harness = await pumpForm(tester, categories: [_launen]);

      expect(customMarkChip('Launen'), findsOneWidget);
      expect(
        tester.widget<FilterChip>(customMarkChip('Launen')).selected,
        isFalse,
      );

      await tester.ensureVisible(customMarkChip('Launen'));
      await tester.pumpAndSettle();
      await tester.tap(customMarkChip('Launen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(customMarkChip('Launen')).selected,
        isTrue,
      );
      await save(tester);
      expect(await storedMarks(harness), {'Launen': <String>[]});

      await tester.tap(customMarkChip('Launen'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(await storedMarks(harness), <String, List<String>>{});
    },
  );

  testWidgets('loading a day re-seeds the ticks from the stored map', (
    tester,
  ) async {
    await pumpForm(
      tester,
      categories: [_sport, _medikamente],
      stored: {
        'Sport': ['Joggen'],
        'Medikamente': ['Ibuprofen'],
        'Alt': ['X'],
      },
    );

    expect(
      tester.widget<FilterChip>(customMarkChip('Sport', 'Joggen')).selected,
      isTrue,
    );
    expect(
      tester.widget<FilterChip>(customMarkChip('Sport', 'Kraft')).selected,
      isFalse,
    );
  });

  testWidgets(
    'untouched save preserves ticks of unknown and invisible categories',
    (tester) async {
      const stored = {
        'Alt': ['X'],
        'Medikamente': ['Ibuprofen'],
      };
      final harness = await pumpForm(
        tester,
        categories: [_sport, _medikamente],
        stored: stored,
      );

      await save(tester);
      expect(await storedMarks(harness), stored);
    },
  );

  testWidgets(
    'a known category is fully chip-controlled: undefined entry labels drop on save',
    (tester) async {
      final harness = await pumpForm(
        tester,
        categories: [_sport],
        stored: {
          'Sport': ['Joggen', 'Gelaufen'],
        },
      );

      await save(tester);
      expect(await storedMarks(harness), {
        'Sport': ['Joggen'],
      });
    },
  );

  testWidgets(
    'unknown-category preservation survives a save that toggles known chips',
    (tester) async {
      final harness = await pumpForm(
        tester,
        categories: [_sport],
        stored: {
          'Alt': ['X'],
          'Sport': ['Joggen'],
        },
      );

      await tester.ensureVisible(customMarkChip('Sport', 'Kraft'));
      await tester.pumpAndSettle();
      await tester.tap(customMarkChip('Sport', 'Kraft'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(await storedMarks(harness), {
        'Alt': ['X'],
        'Sport': ['Joggen', 'Kraft'],
      });
    },
  );
}
