// MarksDao: assisted-mode markers per day (Mode M, ADR-0001).
// Part of the cycle_database.dart library — see its header.
//
// Day-keyed: a mark is identified by (entry_date, mark_type) — the unique
// index is the whole key; there is no profile dimension.

part of 'cycle_database.dart';

@DriftAccessor(tables: [UserMarks])
class MarksDao extends DatabaseAccessor<CycleDatabase> with _$MarksDaoMixin {
  MarksDao(super.db);

  Future<UserMark?> _byKey(DateTime date, String markType) {
    if (markType.isEmpty) {
      throw ArgumentError.value(markType, 'markType', 'must not be empty');
    }
    return (select(userMarks)
          ..where((t) =>
              t.entryDate.equalsValue(DateOnly.normalize(date)) &
              t.markType.equals(markType)))
        .getSingleOrNull();
  }

  /// Adds a mark. Idempotent: returns the existing mark instead of failing
  /// when one of the same type already exists for (date).
  Future<UserMark> addMark(
    DateTime date,
    String markType, {
    String author = 'user',
  }) async {
    final existing = await _byKey(date, markType);
    if (existing != null) return existing;
    return into(userMarks).insertReturning(
      UserMarksCompanion(
        entryDate: Value(DateOnly.normalize(date)),
        markType: Value(markType),
        author: Value(author),
      ),
    );
  }

  /// Toggles the (date, markType) mark:
  /// absent -> added (returns true), present -> removed (returns false).
  Future<bool> toggleMark(DateTime date, String markType) {
    return transaction(() async {
      final existing = await _byKey(date, markType);
      if (existing != null) {
        await (delete(userMarks)..where((t) => t.id.equals(existing.id))).go();
        return false;
      }
      await addMark(date, markType);
      return true;
    });
  }

  /// All marks for a single day, sorted by type.
  Future<List<UserMark>> marksForDay(DateTime date) {
    return (select(userMarks)
          ..where((t) => t.entryDate.equalsValue(DateOnly.normalize(date)))
          ..orderBy([(t) => OrderingTerm.asc(t.markType)]))
        .get();
  }

  /// Marks within [from, to] inclusive, ordered by day then type.
  Future<List<UserMark>> marksInRange(DateTime from, DateTime to) {
    return (select(userMarks)
          ..where((t) => t.entryDate.isBetweenValues(
              const EpochDayConverter().toSql(from),
              const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.entryDate)]))
        .get();
  }

  /// Stream of marks within [from, to] inclusive, ordered by day then type.
  Stream<List<UserMark>> watchMarks(DateTime from, DateTime to) {
    return (select(userMarks)
          ..where((t) => t.entryDate.isBetweenValues(
              const EpochDayConverter().toSql(from),
              const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.entryDate)]))
        .watch();
  }

  /// Stream of every mark, ordered by day then type — the whole-history
  /// companion to EntriesDao.watchAll. [watchMarks] requires a [from, to]
  /// range and cannot serve a whole-history stream (the cycle tab renders
  /// evaluation data across cycle boundaries, so it needs every mark
  /// without knowing the ranges up front).
  Stream<List<UserMark>> watchAll() {
    return (select(userMarks)
          ..orderBy([
            (t) => OrderingTerm.asc(t.entryDate),
            (t) => OrderingTerm.asc(t.markType),
          ]))
        .watch();
  }

  /// Every mark (export support), ordered by day and type.
  Future<List<UserMark>> allMarks() {
    return (select(userMarks)
          ..orderBy([
            (t) => OrderingTerm.asc(t.entryDate),
            (t) => OrderingTerm.asc(t.markType),
          ]))
        .get();
  }

  /// Deletes a specific mark; returns the number of removed rows (0 or 1).
  Future<int> deleteMark(DateTime date, String markType) {
    if (markType.isEmpty) {
      throw ArgumentError.value(markType, 'markType', 'must not be empty');
    }
    return (delete(userMarks)
          ..where((t) =>
              t.entryDate.equalsValue(DateOnly.normalize(date)) &
              t.markType.equals(markType)))
        .go();
  }

  /// Deletes EVERY mark row (the settings pane's wipe calls this inside the
  /// database-level transaction). Returns the number of removed rows.
  Future<int> deleteAll() => delete(userMarks).go();
}
