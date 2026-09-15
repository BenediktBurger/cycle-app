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
