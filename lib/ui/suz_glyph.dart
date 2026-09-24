// The user-placed SUZ glyph's shared anchoring constants — pure Dart, NO
// Flutter imports (the cycle chart and the PDF export both anchor the
// glyph in °C scale units, and the PDF generation layer must stay free of
// material imports for the host smoke scripts, tool/pdf_smoke.dart).
//
// The bar hangs DOWN from the temperature plot's top border by
// [suzBarHangSpanDegrees] of the scale and the right-pointing arrow glyph
// centers at [suzArrowTopInsetDegrees] below that border, inside the hung
// band (TODO(user-review): both values are owner-eyeball rendering
// details, not settled rules; a temperature dot near the scale top can
// visually meet the top arrow — accepted, no avoidance logic).
const double suzBarHangSpanDegrees = 0.5;
const double suzArrowTopInsetDegrees = 0.25;
