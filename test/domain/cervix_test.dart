// Tests for the Muttermund (cervix) vocabularies in
// lib/domain/cervix.dart: POSITION, OPENING, and FIRMNESS. Enum NAMES are
// the stable storage tokens (database + export), so the token-set tests
// below pin them — a rename is a data migration. The position and firmness
// glyphs are ad-hoc display choices (TODO(user-review) in the helpers), the
// opening glyph is the ruleset's circle notation; all three are pinned as
// the contract the chart renders.
import 'package:cycle_app/domain/cervix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CervixPosition vocabulary', () {
    test('token set is exactly the wish-list positions', () {
      expect(
        CervixPosition.values.map((p) => p.name),
        unorderedEquals(const [
          'low',
          'medium',
          'high',
          'veryHigh',
          'unreachable',
        ]),
      );
    });

    test('tryParseCervixPosition round-trips every token', () {
      for (final position in CervixPosition.values) {
        expect(tryParseCervixPosition(position.name), position);
      }
    });

    test('tryParseCervixPosition rejects unknown and non-string input', () {
      expect(tryParseCervixPosition('middle'), isNull);
      expect(tryParseCervixPosition(''), isNull);
      expect(tryParseCervixPosition(null), isNull);
      expect(tryParseCervixPosition(3), isNull);
      expect(tryParseCervixPosition(Object()), isNull);
    });
  });

  group('CervixOpening vocabulary', () {
    test('token set is exactly the wish-list openings', () {
      expect(
        CervixOpening.values.map((o) => o.name),
        unorderedEquals(const ['closed', 'middle', 'open']),
      );
    });

    test('tryParseCervixOpening round-trips every token', () {
      for (final opening in CervixOpening.values) {
        expect(tryParseCervixOpening(opening.name), opening);
      }
    });

    test('tryParseCervixOpening rejects unknown and non-string input', () {
      expect(
        tryParseCervixOpening('medium'),
        isNull,
        reason:
            'a row with opening=medium cannot exist '
            '(deliberate token distinction)',
      );
      expect(tryParseCervixOpening(''), isNull);
      expect(tryParseCervixOpening(null), isNull);
      expect(tryParseCervixOpening(1), isNull);
      expect(tryParseCervixOpening(Object()), isNull);
    });
  });

  group('CervixFirmness vocabulary', () {
    test('token set is exactly the paper hardness vocabulary', () {
      // Paper column: h / h/w / w.
      expect(
        CervixFirmness.values.map((f) => f.name),
        unorderedEquals(const ['hard', 'halfSoft', 'soft']),
      );
    });

    test('tryParseCervixFirmness round-trips every token', () {
      for (final firmness in CervixFirmness.values) {
        expect(tryParseCervixFirmness(firmness.name), firmness);
      }
    });

    test('tryParseCervixFirmness rejects unknown and non-string input', () {
      expect(tryParseCervixFirmness('medium'), isNull);
      expect(
        tryParseCervixFirmness('half-soft'),
        isNull,
        reason: 'tokens are the enum NAMES, no German or glyph variants',
      );
      expect(
        tryParseCervixFirmness('h'),
        isNull,
        reason: 'h/h-w/w are display glyphs, never stored tokens',
      );
      expect(tryParseCervixFirmness(''), isNull);
      expect(tryParseCervixFirmness(null), isNull);
      expect(tryParseCervixFirmness(2), isNull);
      expect(tryParseCervixFirmness(Object()), isNull);
    });

    test('firmness tokens never collide with position/opening tokens', () {
      final positionTokens = CervixPosition.values.map((p) => p.name).toSet();
      final openingTokens = CervixOpening.values.map((o) => o.name).toSet();
      for (final firmness in CervixFirmness.values) {
        expect(
          positionTokens.contains(firmness.name),
          isFalse,
          reason: '${firmness.name} must stay unambiguous per column',
        );
        expect(
          openingTokens.contains(firmness.name),
          isFalse,
          reason: '${firmness.name} must stay unambiguous per column',
        );
      }
    });
  });

  group('display symbols', () {
    test('firmness symbols follow the paper h / h-w / w shorthand', () {
      expect(cervixFirmnessSymbol(CervixFirmness.hard), 'h');
      expect(cervixFirmnessSymbol(CervixFirmness.halfSoft), 'h-w');
      expect(cervixFirmnessSymbol(CervixFirmness.soft), 'w');
    });

    test('opening symbols follow the ruleset circle notation', () {
      expect(cervixOpeningSymbol(CervixOpening.closed), '·');
      expect(cervixOpeningSymbol(CervixOpening.middle), '∘');
      expect(cervixOpeningSymbol(CervixOpening.open), '◯');
      expect(cervixOpeningSymbol(null), isNull);
    });
  });
}
