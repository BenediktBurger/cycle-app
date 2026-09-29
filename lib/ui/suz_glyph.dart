// The user-placed SUZ glyph's shared anchoring constants — pure Dart, NO
// Flutter imports (the cycle chart and the PDF export both anchor the
// glyph in °C scale units, and the PDF generation layer must stay free of
// material imports for the host smoke scripts, tool/pdf_smoke.dart).
//
// The bar hangs DOWN from the temperature plot's top border by
// [suzBarHangSpanDegrees] of the scale — exactly spanning the sex X row
// and the arrow row, stopping short of the mucus glyph row — and the
// right-pointing arrow glyph centers at [suzArrowTopInsetDegrees] below
// that border, inside the hung band on the peak dot's row (a rare
// same-column dot/arrow co-occurrence stays an accepted collision;
// TODO(user-review): both values are owner-eyeball rendering details, not
// settled rules — no avoidance logic).
const double suzBarHangSpanDegrees = 0.2;
const double suzArrowTopInsetDegrees = 0.15;
