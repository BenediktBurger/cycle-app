// Tests for the BBT decimal input parsing shared by the entry form
// (German decimal comma AND dot accepted; strict fraction-digit rules).

import 'package:cycle_app/domain/decimal_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BBT decimal input parsing', () {
    test('accepts dot and comma decimals with surrounding whitespace', () {
      expect(parseDecimalInput('36,6'), closeTo(36.6, 0.0001));
      expect(parseDecimalInput(' 36.65 '), closeTo(36.65, 0.0001));
      expect(parseDecimalInput('36'), 36.0);
    });

    test('rejects garbage and malformed numbers', () {
      expect(parseDecimalInput(''), isNull);
      expect(parseDecimalInput('fünf'), isNull);
      expect(parseDecimalInput('3,6,6'), isNull);
      expect(parseDecimalInput('36.6.1'), isNull);
      expect(parseDecimalInput('36,65'), closeTo(36.65, 0.0001),
          reason: 'two fraction digits are allowed');
      expect(parseDecimalInput('36,654'), isNull,
          reason: 'more than two fraction digits is a typo, not a value');
      expect(parseDecimalInput('-3'), isNull,
          reason: 'temperatures are non-negative');
    });

    test('plausible BBT range check', () {
      expect(isWithinBbtRange(36.6), isTrue);
      expect(isWithinBbtRange(29.0), isTrue);
      expect(isWithinBbtRange(24.9), isFalse);
      expect(isWithinBbtRange(45.1), isFalse);
    });
  });
}
