// Tests for the mucus-feeling -> NFP 0..4 mapping table. The table itself is
// an explicitly marked working assumption pending expert review (ADR-0001) —
// the tests only pin the table's SHAPE (scale bounds, coverage, stable
// storage keys), not the expert-contested values.

import 'package:cycle_app/domain/mucus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mucus feeling -> NFP mapping table (assumption pending review)', () {
    test('every listed feeling maps into the NFP 0..4 scale', () {
      for (final feeling in MucusFeeling.values) {
        final nfp = feeling.mappedNfp;
        expect(nfp, lessThanOrEqualTo(4),
            reason: '${feeling.name} must map to <= 4');
        expect(nfp, greaterThanOrEqualTo(0),
            reason: '${feeling.name} must map to >= 0');
      }
    });

    test('dry is 0 and every other step is reachable', () {
      expect(MucusFeeling.dry.mappedNfp, 0);
      final nfpValues = MucusFeeling.values.map((f) => f.mappedNfp).toSet();
      expect(nfpValues, containsAll(const [1, 2, 3, 4]));
    });

    test('entry names are stable storage keys (do not rename values)', () {
      expect(
        MucusFeeling.values.map((f) => f.name),
        unorderedEquals(const [
          'dry',
          'sticky',
          'creamy',
          'moist',
          'wet',
          'stretchy',
        ]),
      );
    });
  });
}
