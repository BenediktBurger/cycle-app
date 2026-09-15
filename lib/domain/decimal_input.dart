// Pure text parsing for the BBT (basal body temperature) decimal input.
//
// German-first app: users type either a comma or a dot as the decimal
// separator ("36,6" / "36.65"). We do NOT rely on intl.NumberFormat here so
// the entry value behaves identically on all locales/devices.
//
// Strictness decisions (validate with an expert reviewer as desired):
//  - at most TWO fraction digits ("36,654" is a typo, not a temperature)
//  - no sign (body temperatures are non-negative)
//  - the plausible range gate is separate ([isWithinBbtRange]) so the parser
//    stays re-usable for other decimal fields.

/// Recognized shape of a decimal temperature entry: 1..3 integer digits
/// plus an optional fraction of 1–2 digits, either separator.
final RegExp _decimalPattern = RegExp(r'^\d{1,3}([.,]\d{1,2})?$');

/// Parses [input] into a `double`, accepting both decimal separators.
/// Returns null for empty/garbage input, a sign, or more than two
/// fraction digits.
double? parseDecimalInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (!_decimalPattern.hasMatch(trimmed)) return null;
  return double.tryParse(trimmed.replaceFirst(',', '.'));
}

/// Plausible BBT recording window in degrees Celsius.
/// TODO(user-review): bounds are a generous sanity gate, not a NER rule.
const double bbtMinCelsius = 25.0;
const double bbtMaxCelsius = 45.0;

/// True when [value] lies within the plausible BBT window.
bool isWithinBbtRange(double value) =>
    value >= bbtMinCelsius && value <= bbtMaxCelsius;
