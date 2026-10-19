// The custom-marks render line (customMarksNote): the ONE compact text
// formatter every render surface (diary list tile, cycle band, day sheet,
// PDF notes band) shares, so the surfaces cannot drift. Pins the line
// format, the pair separator, the bare-name rule of entry-less categories
// and the stored map's insertion order.
import 'package:cycle_app/domain/custom_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'customMarksNote (one line per category, joined with the separator)',
    () {
      test('an empty or missing stored map renders nothing', () {
        expect(customMarksNote(const {}), isNull);
        expect(customMarksNote(null), isNull);
      });

      test('each category renders "Kategorie: Eintrag, Eintrag"', () {
        expect(
          customMarksNote(const {
            'Sport': ['Joggen', 'Kraft'],
          }),
          'Sport: Joggen, Kraft',
        );
      });

      test('the lines join with the category separator in map order', () {
        expect(
          customMarksNote(const {
            'Sport': ['Joggen'],
            'Urlaub': [],
            'Launen': ['Gut'],
          }),
          'Sport: Joggen · Urlaub · Launen: Gut',
        );
      });

      test('an entry-less category renders its bare name (no prefix)', () {
        expect(
          customMarksNote(const {'Medikamente': <String>[]}),
          'Medikamente',
        );
      });

      test('the stored map\'s insertion order is the render order', () {
        expect(
          customMarksNote(const {
            'B': ['x'],
            'A': ['y'],
          }),
          'B: x · A: y',
        );
        expect(
          customMarksNote(const {
            'A': ['y'],
            'B': ['x'],
          }),
          'A: y · B: x',
        );
      });
    },
  );
}
