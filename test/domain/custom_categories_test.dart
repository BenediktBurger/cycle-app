// CustomCategory: one user-defined diary category definition (name,
// visibility, entry labels) as stored under the customDiaryCategories
// settings key. Pins the value semantics, the JSON round trip, the lenient
// per-field decode (older/hand-edited rows must never throw) and the label
// caps the management card enforces at write time.
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('value semantics', () {
    test('defaults are visible with no entries', () {
      const category = CustomCategory(name: 'Sport');
      expect(category.visible, isTrue);
      expect(category.items, isEmpty);
    });

    test('equal categories (same items, same order) are == and hash equal', () {
      const a = CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']);
      const b = CustomCategory(name: 'Sport', items: ['Joggen', 'Kraft']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing name, visibility or items are not equal', () {
      const base = CustomCategory(name: 'Sport', items: ['Joggen']);
      expect(base, isNot(const CustomCategory(name: 'Urlaub')));
      expect(base, isNot(CustomCategory(name: 'Sport', visible: false)));
      expect(
        base,
        isNot(const CustomCategory(name: 'Sport', items: ['Kraft'])),
      );
      expect(
        base,
        isNot(const CustomCategory(name: 'Sport', items: ['Kraft', 'Joggen'])),
        reason: 'the entry order is part of the value',
      );
    });
  });

  group('JSON round trip', () {
    test('toJson emits the pinned keys and fromJson restores the category', () {
      const category = CustomCategory(name: 'Sport', items: ['Joggen']);
      expect(category.toJson(), {
        'name': 'Sport',
        'visible': true,
        'items': ['Joggen'],
      });
      expect(CustomCategory.fromJson(category.toJson()), category);
    });

    test('an invisible category round-trips its visibility', () {
      const category = CustomCategory(name: 'Medikamente', visible: false);
      expect(CustomCategory.fromJson(category.toJson()), category);
    });

    test('the entry order survives the round trip', () {
      const category = CustomCategory(name: 'Sport', items: ['B', 'A']);
      expect(CustomCategory.fromJson(category.toJson()).items, ['B', 'A']);
    });
  });

  group('lenient fromJson', () {
    test('missing fields fall back to the defaults', () {
      expect(CustomCategory.fromJson(const {}), const CustomCategory(name: ''));
    });

    test('mistyped scalars fall back per field, never throwing', () {
      final mistyped = CustomCategory.fromJson({
        'name': 42,
        'visible': 'yes',
        'items': 'Joggen',
      });
      expect(mistyped, const CustomCategory(name: ''));
      expect(mistyped.visible, isTrue);
      expect(mistyped.items, isEmpty);
    });

    test('a mistyped items list member keeps the valid entries', () {
      expect(
        CustomCategory.fromJson({
          'name': 'Sport',
          'items': ['Joggen', 42, null, 'Kraft'],
        }).items,
        ['Joggen', 'Kraft'],
      );
    });

    test('unknown future keys are ignored', () {
      expect(
        CustomCategory.fromJson({
          'name': 'Sport',
          'icon': 'runner',
          'items': ['Joggen'],
        }),
        const CustomCategory(name: 'Sport', items: ['Joggen']),
      );
    });
  });

  group(
    'label caps (UI write-time guards; the decoders do not enforce them)',
    () {
      test('pinned values', () {
        expect(customLabelMaxLength, 40);
        expect(maxCustomCategories, 10);
        expect(maxCustomCategoryEntries, 15);
      });

      test('the decoders keep over-cap labels (older data must render)', () {
        final overCap = 'x' * 50;
        expect(CustomCategory.fromJson({'name': overCap}).name, overCap);
      });
    },
  );
}
