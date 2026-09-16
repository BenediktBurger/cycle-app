// Drift table definitions for the cycle app (the schema version number
// lives in cycle_database.dart).
//
// SQL-level naming: drift converts camelCase getter names to snake_case
// column names, matching the naming used in the plan and migration notes.

import 'package:drift/drift.dart';

import '../domain/models.dart';
import 'converters.dart';

// NOTE: data classes (CycleEntry, UserMark, Profile), companions, and
// the table info classes are generated into cycle_database.g.dart, which is a
// part of the cycle_database.dart library — the DAOs there (also part files)
// can see them directly.

/// Tracked symptom days — the core table of the app.
///
/// One row exists per (profile, calendar day). Uniqueness is enforced by the
/// unique index [cycleEntriesProfileDateUnique], which the EntriesDao upsert
/// methods rely on.
@TableIndex(
  name: 'cycle_entries_profile_date_unique',
  columns: {#profileId, #date},
  unique: true,
)
class CycleEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// FK to Profiles; defaults to the seeded main profile (id 1).
  IntColumn get profileId =>
      integer().withDefault(const Constant(1)).references(Profiles, #id)();

  /// Calendar day, stored as unix-epoch days (see EpochDayConverter).
  IntColumn get date => integer().map(const EpochDayConverter())();

  /// Basal body temperature in degrees Celsius, when measured.
  RealColumn get bbtC => real().nullable()();

  /// Time-of-day of the temperature measurement, minutes since midnight
  /// (0–1439), NULL when not recorded. Engine-level CHECK mirrors the
  /// shared parse helper (lib/domain/models.dart) so foreign data (e.g. a
  /// future import path) cannot write an impossible time.
  IntColumn get measuredAtMinutes => integer().nullable().customConstraint(
        'CHECK (measured_at_minutes IS NULL OR '
        '(measured_at_minutes BETWEEN 0 AND 1439))',
      )();

  /// Bleeding vocabulary: none(0) / spotting(1) / light(2) / medium(3) /
  /// heavy(4) — the enum names as TEXT tokens, while the enum itself carries
  /// each member's numeric scale value ([Bleeding.level]); every mapping
  /// derives from that field, never from the declaration index.
  /// Note: textEnum's Dart-level builder type is String, so the default is
  /// the SQL-level enum name.
  TextColumn get bleeding =>
      textEnum<Bleeding>().withDefault(const Constant('none'))();

  // Disturbance/exclusion flags for interrupted days (NFP "Störungen").
  BoolColumn get excludeIllness =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get excludeAlcohol =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get excludeTravel =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get excludeOther => boolean().withDefault(const Constant(false))();

  /// Fertility sign recorded on the day: NULL when no observation, else one
  /// of the stable tokens 't' / 'nothing' / 'f' / 's' (the MucusSign enum
  /// names — TEXT like bleeding, never numbers, never display glyphs).
  /// customConstraint replaces drift's own constraints, which is fine here:
  /// SQLite columns admit NULL unless NOT NULL is written, and the check
  /// below allows exactly NULL or the vocabulary.
  TextColumn get mucusSign => text().nullable().customConstraint(
        "CHECK (mucus_sign IS NULL OR mucus_sign IN ('t', 'nothing', 'f', 's'))",
      )();

  /// Quality qualifier of the mucus sign S; NULL for every sign other than
  /// 's' and for days without a sign. Enforced at the engine level so broken
  /// data (e.g. from a future import path) cannot be written.
  TextColumn get mucusQuality => text().nullable().customConstraint(
        "CHECK (mucus_quality IS NULL OR (mucus_sign = 's' AND "
        "mucus_quality IN ('w', 'mi', 'cr', 'kl', 'glb', 'g', 'ew', 'gl', "
        "'fl', 'ns')))",
      )();

  /// Optional cervix observation (free text).
  TextColumn get cervix => text().nullable()();

  BoolColumn get pain => boolean().withDefault(const Constant(false))();
  BoolColumn get mood => boolean().withDefault(const Constant(false))();
  BoolColumn get desire => boolean().withDefault(const Constant(false))();
  BoolColumn get sex => boolean().withDefault(const Constant(false))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Assisted-mode markers a user places onto specific days (Mode M, ADR-001).
///
/// One mark of a given type per (profile, day). The type is an open TEXT
/// vocabulary so future marking tools can add types without a migration;
/// well-known initial types are listed in [MarkTypes].
@TableIndex(
  name: 'user_marks_profile_date_type_unique',
  columns: {#profileId, #entryDate, #markType},
  unique: true,
)
class UserMarks extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get profileId =>
      integer().withDefault(const Constant(1)).references(Profiles, #id)();

  /// Calendar day the mark belongs to (unix-epoch days).
  IntColumn get entryDate => integer().map(const EpochDayConverter())();

  /// Marking tool identifier, e.g. one of the [MarkTypes] constants.
  TextColumn get markType => text()();

  /// Who placed the mark. 'user' today; later milestones may add modes
  /// (e.g. an 'assist' author for Mode-S suggestions — deliberately kept
  /// open TEXT instead of constraining to an enum).
  TextColumn get author => text().withDefault(const Constant('user'))();
}

/// Well-known initial mark types (Mode M tools, data-model-ready in M1,
/// UI deferred — see ADR-001).
abstract final class MarkTypes {
  static const firstHigherMeasurement = 'firstHigherMeasurement';
  static const baseline = 'baseline';
  static const mucusPeakDay = 'mucusPeakDay';
  static const fertileWindow = 'fertileWindow';
  static const interruption = 'interruption';
}

/// Evaluation profiles on this device (partner mode, v0 schema, UI later).
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get ordinal => integer().withDefault(const Constant(0))();
}
