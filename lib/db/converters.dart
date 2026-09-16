// Value converters between Dart-level types and the SQLite representation.
//
// Date representation decision (verify with reviewer):
// calendar days are stored as INTEGER unix-epoch days (days since 1970-01-01).
// This is timezone-neutral and keeps sorting/range math trivial; drift's
// default DateTime storage (UTC seconds incl. time-of-day) would mix
// timezones into what is conceptually a calendar date. The converter accepts
// any DateTime and keeps the calendar day it shows in its own timezone.

import 'package:drift/drift.dart';

import '../domain/date_only.dart';
import '../domain/models.dart';

/// Stores a calendar day as INTEGER (days since the Unix epoch).
class EpochDayConverter extends TypeConverter<DateTime, int> {
  const EpochDayConverter();

  @override
  DateTime fromSql(int argFromDb) =>
      DateTime.utc(1970, 1, 1).add(Duration(days: argFromDb));

  @override
  int toSql(DateTime value) =>
      DateOnly.normalize(value).difference(DateTime.utc(1970)).inDays;
}

/// Maps the [Bleeding] domain enum to the stored INTEGER bleeding level: the
/// number is exactly [Bleeding.level] (0 none … 4 heavy), kept in sync with
/// that field — never the Dart declaration index. An unknown stored number is
/// data corruption (e.g. foreign data bypassing the engine): reading throws
/// so drift surfaces the corrupt row instead of silently mapping it.
class BleedingLevelConverter extends TypeConverter<Bleeding, int> {
  const BleedingLevelConverter();

  @override
  Bleeding fromSql(int argFromDb) {
    for (final b in Bleeding.values) {
      if (b.level == argFromDb) return b;
    }
    throw ArgumentError.value(
        argFromDb, 'bleeding', 'unknown stored bleeding level');
  }

  @override
  int toSql(Bleeding value) => value.level;
}
