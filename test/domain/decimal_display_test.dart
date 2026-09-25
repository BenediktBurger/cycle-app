// Tests for the locale-aware decimal display formatter shared by every
// app-side decimal surface (statistics rows, range dropdown, chart rail,
// diary prefill — see also the entry parser in decimal_input.dart, whose
// both-separator rule is deliberately NOT localized).

import 'package:cycle_app/domain/decimal_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localized decimal display formatting', () {
    test('de renders the comma separator', () {
      expect(formatDecimal(37.65, locale: 'de', decimalDigits: 2), '37,65');
    });

    test('en renders the dot separator', () {
      expect(formatDecimal(37.65, locale: 'en', decimalDigits: 2), '37.65');
    });

    test('one fraction digit keeps NumberFormat\'s rounding (no re-rounding '
        'rule here)', () {
      expect(formatDecimal(37.66, locale: 'en', decimalDigits: 1), '37.7');
      expect(formatDecimal(37.66, locale: 'de', decimalDigits: 1), '37,7');
      // 37.65 is not exactly representable as a double (37.6499…), so
      // NumberFormat keeps the 6 — pinning that the helper adds ONLY the
      // locale separator, never its own rounding semantics.
      expect(formatDecimal(37.65, locale: 'en', decimalDigits: 1), '37.6');
    });

    test('two digits on a whole value keep trailing zeros per digit count', () {
      expect(formatDecimal(38.0, locale: 'de', decimalDigits: 2), '38,00');
      expect(formatDecimal(38.0, locale: 'en', decimalDigits: 2), '38.00');
    });

    test('plain integers carry no separator in either language', () {
      expect(formatDecimal(37.0, locale: 'de', decimalDigits: 0), '37');
      expect(formatDecimal(38.0, locale: 'en', decimalDigits: 0), '38');
    });

    test('the edit-prefill shape keeps the stored value\'s own fraction '
        'digits (the entry parser\'s 1–2) — separator localized only', () {
      expect(formatDecimalPrefill(36.4, locale: 'de'), '36,4');
      expect(formatDecimalPrefill(36.9, locale: 'de'), '36,9');
      expect(formatDecimalPrefill(36.65, locale: 'en'), '36.65');
      // A whole stored reading keeps its one trailing zero — the shape
      // Dart's toString showed, so a reopening day reads as before typing.
      expect(formatDecimalPrefill(38.0, locale: 'de'), '38,0');
    });
  });
}
