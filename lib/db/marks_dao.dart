// MarksDao: assisted-mode markers per day (Mode M, ADR-001).
// Part of the cycle_database.dart library — see its header.

part of 'cycle_database.dart';

@DriftAccessor(tables: [UserMarks])
class MarksDao extends DatabaseAccessor<CycleDatabase> with _$MarksDaoMixin {
  MarksDao(super.db);

  Future<UserMark?> _byKey(int profileId, DateTime date, String markType) {
    if (markType.isEmpty) {
      throw ArgumentError.value(markType, 'markType', 'must not be empty');
    }
    return (select(userMarks)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.entryDate.equalsValue(DateOnly.normalize(date)) &
              t.markType.equals(markType)))
        .getSingleOrNull();
  }

  /// Adds a mark. Idempotent: returns the existing mark instead of failing
  /// when one of the same type already exists for (profileId, date).
  Future<UserMark> addMark(
    int profileId,
    DateTime date,
    String markType, {
    String author = 'user',
  }) async {
    final existing = await _byKey(profileId, date, markType);
    if (existing != null) return existing;
    return into(userMarks).insertReturning(
      UserMarksCompanion(
        profileId: Value(profileId),
        entryDate: Value(DateOnly.normalize(date)),
        markType: Value(markType),
        author: Value(author),
      ),
    );
  }

  /// Toggles the (profileId, date, markType) mark:
  /// absent -> added (returns true), present -> removed (returns false).
  Future<bool> toggleMark(int profileId, DateTime date, String markType) {
    return transaction(() async {
      final existing = await _byKey(profileId, date, markType);
      if (existing != null) {
        await (delete(userMarks)..where((t) => t.id.equals(existing.id))).go();
        return false;
      }
      await addMark(profileId, date, markType);
      return true;
    });
  }

  /// All marks for a single day, sorted by type.
  Future<List<UserMark>> marksForDay(int profileId, DateTime date) {
    return (select(userMarks)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.entryDate.equalsValue(DateOnly.normalize(date)))
          ..orderBy([(t) => OrderingTerm.asc(t.markType)]))
        .get();
  }

  /// Marks within [from, to] inclusive, ordered by day then type.
  Future<List<UserMark>> marksInRange(
    int profileId,
    DateTime from,
    DateTime to,
  ) {
    return (select(userMarks)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.entryDate.isBetweenValues(const EpochDayConverter().toSql(from),
                  const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.entryDate)]))
        .get();
  }

  /// Stream of marks within [from, to] inclusive, ordered by day then type.
  Stream<List<UserMark>> watchMarks(
    int profileId,
    DateTime from,
    DateTime to,
  ) {
    return (select(userMarks)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.entryDate.isBetweenValues(const EpochDayConverter().toSql(from),
                  const EpochDayConverter().toSql(to)))
          ..orderBy([(t) => OrderingTerm.asc(t.entryDate)]))
        .watch();
  }

  /// Every mark of every profile (export support), ordered by profile,
  /// day and type.
  Future<List<UserMark>> allMarksForAllProfiles() {
    return (select(userMarks)
          ..orderBy([
            (t) => OrderingTerm.asc(t.profileId),
            (t) => OrderingTerm.asc(t.entryDate),
            (t) => OrderingTerm.asc(t.markType),
          ]))
        .get();
  }

  /// Deletes a specific mark; returns the number of removed rows (0 or 1).
  Future<int> deleteMark(int profileId, DateTime date, String markType) {
    if (markType.isEmpty) {
      throw ArgumentError.value(markType, 'markType', 'must not be empty');
    }
    return (delete(userMarks)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.entryDate.equalsValue(DateOnly.normalize(date)) &
              t.markType.equals(markType)))
        .go();
  }
}
