// Pure-Dart date-only helpers. This file must stay free of any drift/Flutter
// imports so the whole lib/domain/ layer remains host-VM testable.
//
// Convention used across domain + db layers for "calendar days":
// a date-only value is a DateTime in UTC whose time-of-day is always 00:00.
// Normalizing by (year, month, day) via DateTime.utc makes every input
// (local, UTC, parsed strings) comparable without timezone surprises.

/// Utility class grouping date-only arithmetic on [DateTime] values.
abstract final class DateOnly {
  /// Converts [d] to a UTC midnight value, keeping the same calendar day as
  /// the value has in whatever timezone it claims.
  static DateTime normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Adds exactly [days] calendar days to the normalized [d].
  static DateTime addDays(DateTime d, int days) =>
      normalize(d).add(Duration(days: days));

  /// Difference in calendar days: `a - b` (positive when [a] is later).
  /// Also valid as a sort comparator result for ascending order.
  static int daysBetween(DateTime a, DateTime b) =>
      normalize(a).difference(normalize(b)).inDays;

  /// True when both values refer to the same calendar day.
  static bool sameDay(DateTime a, DateTime b) => normalize(a) == normalize(b);

  /// The calendar day before [d].
  static DateTime previousDay(DateTime d) => addDays(d, -1);
}
