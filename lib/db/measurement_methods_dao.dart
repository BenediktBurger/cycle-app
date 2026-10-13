// MeasurementMethodsDao: the day-keyed state snapshots of the measurement
// method (route + thermometer). Part of the cycle_database.dart library —
// see its header.
//
// Day-keyed: a snapshot is identified by its calendar day alone (the
// (date) unique index is the whole key; there is no profile dimension).

part of 'cycle_database.dart';

@DriftAccessor(tables: [MeasurementMethods])
class MeasurementMethodsDao extends DatabaseAccessor<CycleDatabase>
    with _$MeasurementMethodsDaoMixin {
  MeasurementMethodsDao(super.db);

  /// Reads a single day's snapshot; null when absent.
  Future<MeasurementMethod?> snapshotFor(DateTime date) {
    return (select(measurementMethods)
          ..where((t) => t.date.equalsValue(DateOnly.normalize(date))))
        .getSingleOrNull();
  }

  /// Inserts the snapshot, or FULLY replaces the row for the same day —
  /// EntriesDao.upsertByDate semantics: every field is written as given
  /// (a null thermometer clears the stored name), the existing id and
  /// created_at are kept, updated_at is bumped to now. [thermometer]
  /// arrives pre-trimmed (normalizeThermometerName is the shared writer
  /// rule — callers construct the domain snapshot first).
  Future<MeasurementMethod> upsertByDate({
    required DateTime date,
    required MeasurementRoute route,
    String? thermometer,
  }) {
    return transaction(() async {
      final existing = await snapshotFor(date);
      final now = DateTime.now();
      if (existing == null) {
        final id = await into(measurementMethods).insert(
          MeasurementMethodsCompanion.insert(
            date: DateOnly.normalize(date),
            method: route.name,
            thermometer: Value(thermometer),
          ).copyWith(createdAt: Value(now), updatedAt: Value(now)),
        );
        return (select(
          measurementMethods,
        )..where((t) => t.id.equals(id))).getSingle();
      }
      await (update(
        measurementMethods,
      )..where((t) => t.id.equals(existing.id))).write(
        MeasurementMethodsCompanion(
          method: Value(route.name),
          thermometer: Value(thermometer),
          updatedAt: Value(now),
        ),
      );
      return (select(
        measurementMethods,
      )..where((t) => t.id.equals(existing.id))).getSingle();
    });
  }

  /// Deletes the snapshot stored for [date]. Returns the number of removed
  /// rows (0 or 1).
  Future<int> deleteByDate(DateTime date) {
    return (delete(
      measurementMethods,
    )..where((t) => t.date.equalsValue(DateOnly.normalize(date)))).go();
  }

  /// All snapshots, ordered ascending by day (whole history — export and
  /// PDF support).
  Future<List<MeasurementMethod>> allSnapshots() {
    return (select(
      measurementMethods,
    )..orderBy([(t) => OrderingTerm.asc(t.date)])).get();
  }

  /// Stream of every snapshot, ordered ascending by day — the
  /// whole-history companion to EntriesDao.watchAll (the chart renders
  /// method glyphs across cycle boundaries, so it needs every snapshot
  /// without knowing the ranges up front).
  Stream<List<MeasurementMethod>> watchAll() {
    return (select(
      measurementMethods,
    )..orderBy([(t) => OrderingTerm.asc(t.date)])).watch();
  }

  /// Deletes EVERY snapshot row (the settings pane's wipe calls this inside
  /// the database-level transaction). Returns the number of removed rows.
  Future<int> deleteAll() => delete(measurementMethods).go();
}
