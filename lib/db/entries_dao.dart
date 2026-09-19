// EntriesDao: day-entry persistence for CycleEntries.
// This file is a part of the cycle_database.dart library (see the header
// there for why — drift-generated data classes live in one generated file).
//
// Day-keyed: a tracked day is identified by its calendar day alone (the
// (date) unique index is the whole key; there is no profile dimension).

part of 'cycle_database.dart';

@DriftAccessor(tables: [CycleEntries])
class EntriesDao extends DatabaseAccessor<CycleDatabase>
    with _$EntriesDaoMixin {
  EntriesDao(super.db);

  DateTime _normalize(DateTime d) => DateOnly.normalize(d);

  /// Reads a single day's entry; null when absent.
  Future<CycleEntry?> entryFor(DateTime date) {
    return (select(cycleEntries)
          ..where((t) => t.date.equalsValue(_normalize(date))))
        .getSingleOrNull();
  }

  /// Inserts the day entry, or FULLY replaces the row for the same day —
  /// the upsert semantics: every field present in [entry] is written as
  /// given (nulls included), the existing id and created_at are kept,
  /// updated_at is bumped to now.
  ///
  /// Requires [entry].date to be present. Returns the stored row.
  Future<CycleEntry> upsertByDate(CycleEntriesCompanion entry) {
    if (!entry.date.present) {
      throw ArgumentError.value(entry, 'entry', 'date must be present');
    }
    final date = _normalize(entry.date.value);

    return transaction(() async {
      final existing = await entryFor(date);
      final now = DateTime.now();
      if (existing == null) {
        final id = await into(cycleEntries).insert(entry.copyWith(
          date: Value(date),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        return (select(cycleEntries)..where((t) => t.id.equals(id)))
            .getSingle();
      }

      // Full replacement write: drop identity + timestamps handled below,
      // then write all provided fields as-is. created_at stays untouched;
      // updated_at is bumped.
      final replacement = entry.copyWith(
        id: const Value<int>.absent(),
        date: Value(date),
        createdAt: const Value<DateTime>.absent(),
        updatedAt: Value(now),
      );
      await (update(cycleEntries)..where((t) => t.id.equals(existing.id)))
          .write(replacement);
      return (select(cycleEntries)..where((t) => t.id.equals(existing.id)))
          .getSingle();
    });
  }

  /// Convenience wrapper for full-day writes from the domain layer:
  /// converts [day] to a companion where EVERY field is explicit (nulls
  /// included), so upsertByDate performs a genuine full replace.
  Future<CycleEntry> upsertDaily(DailyEntry day) {
    return upsertByDate(dailyEntryToCompanion(day));
  }

  /// All entries, ordered ascending by day.
  Future<List<CycleEntry>> allEntries() {
    return (select(cycleEntries)..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  /// All entries within [from, to] inclusive, ordered asc.
  /// Note: isBetweenValues compares on the raw SQL type, so the converted
  /// DateTime bounds are mapped to epoch days here.
  Future<List<CycleEntry>> range(DateTime from, DateTime to) {
    return (select(cycleEntries)
          ..where((t) => t.date.isBetweenValues(
              const EpochDayConverter().toSql(from),
              const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  /// Stream of entries within [from, to] inclusive, ordered ascending.
  Stream<List<CycleEntry>> watchRange(DateTime from, DateTime to) {
    return (select(cycleEntries)
          ..where((t) => t.date.isBetweenValues(
              const EpochDayConverter().toSql(from),
              const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  /// Stream of all entries, ordered ascending.
  Stream<List<CycleEntry>> watchAll() {
    return (select(cycleEntries)..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  /// Deletes the entry stored for [date]. Returns the number of removed
  /// rows (0 or 1).
  Future<int> deleteByDate(DateTime date) {
    return (delete(cycleEntries)
          ..where((t) => t.date.equalsValue(_normalize(date))))
        .go();
  }
}
