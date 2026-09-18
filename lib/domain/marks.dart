// Pure-Dart model for user-placed analysis marks ("Markierungen", Mode M,
// ADR-0001): the domain-side representation of the UserMarks db table.
//
// No drift types, no Flutter imports — the db layer converts between this
// model and drift rows in lib/db/mappers.dart, the ONLY drift<->domain
// boundary.
import 'date_only.dart';
//
// The stored mark type is an OPEN TEXT vocabulary (lib/db/tables.dart): the
// table deliberately admits unknown future tokens so new marking tools need
// no migration. CycleMark.type is therefore a plain String, not an enum —
// a strict enum would silently drop rows the schema accepts. The constants
// below pin the well-known tokens; they mirror the db-side MarkTypes class
// (duplicated rather than imported because the domain layer must never
// reference lib/db — a db-side test pins the two definitions in sync).

/// Well-known mark-type tokens, mirroring the storage vocabulary.
abstract final class CycleMarkTypes {
  /// Mucus peak day ("Schleimhöhepunkt") placed by the user.
  static const mucusPeakDay = 'mucusPeakDay';

  /// First higher measurement after the peak ("erste höhere Messung").
  static const firstHigherMeasurement = 'firstHigherMeasurement';

  /// Baseline line ("Basislinie").
  static const baseline = 'baseline';

  /// Fertile window marker.
  static const fertileWindow = 'fertileWindow';

  /// Interrupted-day / cycle interruption marker.
  static const interruption = 'interruption';

  /// The user-placed start of the sicher unfruchtbare Zeit (SUZ) from a
  /// MORNING (the SUZ bar renders at the day column's start). The computed
  /// SUZ (rules D/E in lib/domain/evaluation.dart) is suggestion-only —
  /// manual SUZ marks never alter the arithmetic (ADR-0001).
  static const suzMorning = 'suzMorning';

  /// The user-placed SUZ start from an EVENING (the SUZ bar renders at the
  /// day column's middle).
  static const suzEvening = 'suzEvening';

  /// The user-placed start of a menstrual cycle. The AUTHORITATIVE cycle
  /// boundary: cycle grouping (lib/domain/cycle_grouping.dart) opens a new
  /// cycle group at this mark, wherever it sits — bleeding only SUGGESTS a
  /// cycle start via isSuggestedCycleStart, it never creates boundaries by
  /// itself.
  static const cycleStart = 'cycleStart';
}

/// One mark a user placed onto one calendar day.
///
/// Decoupled from any storage layer; equality compares every field and
/// judges dates by calendar day (like DailyEntry), so a local-time and a
/// UTC representation of the same day are equal.
final class CycleMark {
  const CycleMark({
    required this.profileId,
    required this.date,
    required this.type,
    this.author = 'user',
  });

  final int profileId;

  /// The marked calendar day. Normalized to UTC midnight on the way into
  /// the domain (mapper + DateOnly convention), so time-of-day components
  /// are never meaningful.
  final DateTime date;

  /// Mark-type token: one of [CycleMarkTypes] or an open-vocabulary token
  /// from a future tool (deliberately not validated here — the schema is
  /// the vocabulary authority).
  final String type;

  /// Who placed the mark ('user' today; open TEXT in storage for future
  /// authoring modes).
  final String author;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CycleMark &&
        DateOnly.sameDay(date, other.date) &&
        profileId == other.profileId &&
        type == other.type &&
        author == other.author;
  }

  @override
  int get hashCode => Object.hash(
        profileId,
        DateOnly.normalize(date),
        type,
        author,
      );

  @override
  String toString() =>
      'CycleMark(${DateOnly.normalize(date).toIso8601String()}, '
      'profile:$profileId, type:$type, author:$author)';
}
