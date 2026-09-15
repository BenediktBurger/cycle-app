// EntriesDao: day-entry persistence for CycleEntries.
// This file is a part of the cycle_database.dart library (see the header
// there for why — drift-generated data classes live in one generated file).

part of 'cycle_database.dart';

@DriftAccessor(tables: [CycleEntries])
class EntriesDao extends DatabaseAccessor<CycleDatabase>
    with _$EntriesDaoMixin {
  EntriesDao(super.db);

  DateTime _normalize(DateTime d) => DateOnly.normalize(d);

  /// Reads a single day's entry for [profileId]; null when absent.
  Future<CycleEntry?> entryFor(int profileId, DateTime date) {
    return (select(cycleEntries)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.date.equalsValue(_normalize(date))))
        .getSingleOrNull();
  }

  /// Inserts the day entry, or FULLY replaces the row for the same
  /// (profile, date) — the upsert semantics from the plan: every field
  /// present in [entry] is written as given (nulls included), the existing
  /// id and created_at are kept, updated_at is bumped to now.
  ///
  /// Requires [entry].date to be present. Returns the stored row.
  Future<CycleEntry> upsertByDate(CycleEntriesCompanion entry) {
    if (!entry.date.present) {
      throw ArgumentError.value(entry, 'entry', 'date must be present');
    }
    final profileId = entry.profileId.present ? entry.profileId.value : 1;
    final date = _normalize(entry.date.value);

    return transaction(() async {
      final existing = await entryFor(profileId, date);
      final now = DateTime.now();
      if (existing == null) {
        final id = await into(cycleEntries).insert(entry.copyWith(
          profileId: Value(profileId),
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
        profileId: Value(profileId),
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
  ///
  /// [profileId] overrides the profile stored on [day] itself; when null,
  /// the domain value inside [day] is used as-is (dailyEntryToCompanion
  /// always marks profileId present, so no absent-value clearance games are
  /// needed here — a `Value.absent()` copyWith would KEEP the present
  /// default 1 instead of deferring to [day]).
  Future<CycleEntry> upsertDaily(
    DailyEntry day, {
    int? profileId,
  }) {
    final companion = dailyEntryToCompanion(day);
    return upsertByDate(
      profileId == null
          ? companion
          : companion.copyWith(profileId: Value(profileId)),
    );
  }

  /// All entries of one profile, ordered ascending by day.
  Future<List<CycleEntry>> allEntries(int profileId) {
    return (select(cycleEntries)
          ..where((t) => t.profileId.equals(profileId))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  /// Every entry of every profile (export support), ordered by profile then
  /// day. Prefer [allEntries]/[watchAll] in UI code — the main app data set
  /// is always profile-scoped.
  Future<List<CycleEntry>> allEntriesForAllProfiles() {
    return (select(cycleEntries)
          ..orderBy([
            (t) => OrderingTerm.asc(t.profileId),
            (t) => OrderingTerm.asc(t.date),
          ]))
        .get();
  }

  /// All entries of one profile within [from, to] inclusive, ordered asc.
  /// Note: isBetweenValues compares on the raw SQL type, so the converted
  /// DateTime bounds are mapped to epoch days here.
  Future<List<CycleEntry>> range(int profileId, DateTime from, DateTime to) {
    return (select(cycleEntries)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.date.isBetweenValues(const EpochDayConverter().toSql(from),
                  const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  /// Stream of entries within [from, to] inclusive, ordered ascending.
  Stream<List<CycleEntry>> watchRange(
    int profileId,
    DateTime from,
    DateTime to,
  ) {
    return (select(cycleEntries)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.date.isBetweenValues(const EpochDayConverter().toSql(from),
                  const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  /// Stream of all entries of one profile, ordered ascending.
  Stream<List<CycleEntry>> watchAll(int profileId) {
    return (select(cycleEntries)
          ..where((t) => t.profileId.equals(profileId))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  /// Deletes the entry stored for (profileId, date). Returns the number of
  /// removed rows (0 or 1).
  Future<int> deleteByDate(int profileId, DateTime date) {
    return (delete(cycleEntries)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.date.equalsValue(_normalize(date))))
        .go();
  }
}
