// Locale-aware decimal display for every app-side decimal surface — the
// ONE counterpart to the entry rule in decimal_input.dart (which parses
// BOTH separators on every locale, deliberately unlocalized).
//
// Pure Dart so widget tests and host tools can assert the separators.
// Call sites pass the RESOLVED locale
// (`Localizations.localeOf(context).toString()`): the helper resolves
// nothing itself, and English devices show "37.65" while German ones
// show "37,65".
//
// The PDF stays OUT of this rule for now: its documents are fixed German
// by design (comma always — see the header decision in
// lib/pdf/cycle_pdf.dart), so localizing them is future work; when PDF
// localization lands, the `lib/pdf` label/row sites route through here
// with the generated document's locale.

import 'package:intl/intl.dart';

/// Formats [value] with the separator conventions of [locale]
/// (e.g. the fraction digits the site needs; rounding follows
/// `NumberFormat.decimalPatternDigits`).
String formatDecimal(
  double value, {
  required String locale,
  required int decimalDigits,
}) => NumberFormat.decimalPatternDigits(
  locale: locale,
  decimalDigits: decimalDigits,
).format(value);

/// Formats [value] the way its stored form was ENTERED: the value's own
/// fraction digits (1–2, the entry parser's shape) with the locale's
/// separator — '36,4' / '38,0' / '36,65' instead of a site-fixed digit
/// count. Used by the diary edit prefill: reopening a day reinstates the
/// reading the user typed (trailing zeros would suggest an unwritten
/// precision), only the separator follows the display rule.
String formatDecimalPrefill(double value, {required String locale}) =>
    NumberFormat('0.0#', locale).format(value);
