// The basal-temperature measurement METHOD of a day: which measurement
// route (vaginal / rectal / oral / other) and thermometer name apply FROM
// THAT DAY ON. One stored row is a STATE SNAPSHOT ("from this date
// onwards") — writing a new method means a new row, not an edit of a
// per-day fact, so the volume stays tiny and every later day's effective
// method is the latest snapshot at or before it
// ([effectiveMeasurementMethod]).
//
// Storage rule (like the cervix vocabularies, lib/domain/cervix.dart): the
// enum NAMES are the TEXT tokens stored in the database (engine-level
// CHECK) and in the export document. A rename of any value is therefore a
// data migration — the tests pin every token; treat a rename as a schema
// change, not a refactor.

import 'date_only.dart';

/// Which measurement route applies from a day on:
///
/// - `vaginal`: vaginal (Scheide)
/// - `rectal`: rektal (After)
/// - `oral`: oral (Mund)
/// - `other`: andere Messmethode
enum MeasurementRoute { vaginal, rectal, oral, other }

/// Parses a stored/exported route token back into the enum, or null for
/// anything else. SHARED by the db mapper and the export/import writer —
/// like tryParseCervixPosition (lib/domain/cervix.dart), the single source
/// of truth for this field's validation, so a row a writer would drop is
/// never counted as a write. Accepts `Object?`: export rows arrive
/// JSON-decoded as the loosest shape.
MeasurementRoute? tryParseMeasurementRoute(Object? raw) {
  if (raw is! String) return null;
  for (final route in MeasurementRoute.values) {
    if (route.name == raw) return route;
  }
  return null;
}

/// The shared thermometer-NAME rule: `null` stays `null`, a whitespace-only
/// name is no name, anything else loses its edge padding. The snapshot
/// constructor and the diary dialog's writer both run through this, so the
/// stored name and the value the dialog displays can never disagree.
String? normalizeThermometerName(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// One stored state change: from [date] onwards, [route] and [thermometer]
/// apply. The date is normalized to UTC midnight (the DateOnly convention)
/// and the name runs through the shared trim helper at construction, so a
/// snapshot can only carry clean field values.
final class MeasurementMethodSnapshot {
  /// The day the state starts applying, UTC midnight (DateOnly convention).
  final DateTime date;

  final MeasurementRoute route;

  final String? thermometer;

  MeasurementMethodSnapshot({
    required DateTime date,
    required this.route,
    String? thermometer,
  }) : date = DateOnly.normalize(date),
       thermometer = normalizeThermometerName(thermometer);

  @override
  bool operator ==(Object other) =>
      other is MeasurementMethodSnapshot &&
      other.date == date &&
      other.route == route &&
      other.thermometer == thermometer;

  @override
  int get hashCode => Object.hash(date, route, thermometer);

  @override
  String toString() =>
      'MeasurementMethodSnapshot($date, $route, thermometer: $thermometer)';
}

/// The method in effect on [day] according to [snapshots]: the latest one
/// whose date is at or before it — the day itself counts (a snapshot stored
/// on that day governs that day), a day after every snapshot keeps the
/// last one, a day before every one has none. Order-independent by
/// construction.
MeasurementMethodSnapshot? effectiveMeasurementMethod(
  List<MeasurementMethodSnapshot> snapshots,
  DateTime day,
) {
  final date = DateOnly.normalize(day);
  MeasurementMethodSnapshot? effective;
  for (final snapshot in snapshots) {
    if (!snapshot.date.isAfter(date) &&
        (effective == null || snapshot.date.isAfter(effective.date))) {
      effective = snapshot;
    }
  }
  return effective;
}
