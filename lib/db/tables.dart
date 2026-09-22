// Drift table definitions for the cycle app (the schema version number
// lives in cycle_database.dart).
//
// SQL-level naming: drift converts camelCase getter names to snake_case
// column names, matching the naming used in the plan and migration notes.
//
// Profile-free schema: there is no Profiles table and no profile_id column
// anywhere — a tracked day is identified by its calendar day alone, and a
// mark by (entry_date, mark_type).

import 'package:drift/drift.dart';

import '../domain/models.dart';
import 'converters.dart';

// NOTE: data classes (CycleEntry, UserMark), companions, and the table info
// classes are generated into cycle_database.g.dart, which is a part of the
// cycle_database.dart library — the DAOs there (also part files) can see
// them directly.

/// Tracked symptom days — the core table of the app.
///
/// One row exists per calendar day. Uniqueness is enforced by the unique
/// index [cycleEntriesDateUnique] (@TableIndex below), which the EntriesDao
/// upsert methods rely on.
@TableIndex(name: 'cycle_entries_date_unique', columns: {#date}, unique: true)
class CycleEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Calendar day, stored as unix-epoch days (see EpochDayConverter).
  IntColumn get date => integer().map(const EpochDayConverter())();

  /// Raw temperature-disturbance flags of the day (the NER "Störungen"
  /// vocabulary): one INTEGER mask, the OR of the [TempDisturbance] bits —
  /// sp(1) late to bed, a(2) frequent night awakening, alk(4) alcohol,
  /// kr(8) illness. 0 = no disturbance. Reise (travel) is deliberately NOT
  /// representable. This is RAW data whose remaining visual consumer is
  /// the Tagebuch list's interrupted-day badge (the temperature curve is
  /// MARK-keyed since owner decision 2026-09-19 — the ignoreTemperature
  /// mark dims the curve, never this mask); the temperature evaluation
  /// uses the
  /// separate ignoreTemperature MARK (user_marks).
  /// customConstraint replaces drift's own constraints, so NOT NULL, the
  /// default 0 and the 0..15 range check are written out explicitly inside
  /// the constraint string (a bare CHECK would silently drop both). The
  /// engine-level CHECK mirrors the domain constructor assert so foreign
  /// data cannot write an impossible mask.
  IntColumn get tempDisturbances => integer()
      .withDefault(const Constant(0))
      .customConstraint(
        'NOT NULL DEFAULT 0 CHECK (temp_disturbances BETWEEN 0 AND 15)',
      )();

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

  /// Bleeding intensity on the shared 6-step numeric scale, stored as the
  /// INTEGER [Bleeding.level]: none(0) / spotting(1) / light(2) / medium(3) /
  /// heavy(4) / maximum(5). The converter derives every mapping from
  /// [Bleeding.level],
  /// never from the declaration index; an unknown stored number throws so
  /// corrupt data is surfaced instead of silently mapped. The default 0
  /// stores an explicit `none` (a day with no observation still has a value).
  IntColumn get bleeding => integer()
      .map(const BleedingLevelConverter())
      .withDefault(const Constant(0))();

  /// Fertility sign recorded on the day: NULL when no observation, else one
  /// of the stable tokens 't' / 'nothing' / 'f' / 's' / 'fs' / 'a' (the
  /// MucusSign enum names — TEXT, unlike bleeding's numeric column; never
  /// display glyphs; 'fs' is "f vor S an einem Tag", a sign of its own with
  /// NO quality qualifier). customConstraint replaces drift's own
  /// constraints, which is fine here: SQLite columns admit NULL unless NOT
  /// NULL is written, and the check below allows exactly NULL or the
  /// vocabulary.
  TextColumn get mucusSign => text().nullable().customConstraint(
    "CHECK (mucus_sign IS NULL OR mucus_sign IN "
    "('t', 'nothing', 'f', 's', 'fs', 'a'))",
  )();

  /// Quality qualifier of the mucus sign S; NULL for every sign other than
  /// 's' and for days without a sign ('fs' deliberately carries no
  /// quality — it is not the S sign). Enforced at the engine level so
  /// broken data (e.g. from a future import path) cannot be written.
  TextColumn get mucusQuality => text().nullable().customConstraint(
    "CHECK (mucus_quality IS NULL OR (mucus_sign = 's' AND "
    "mucus_quality IN ('w', 'mi', 'cr', 'kl', 'glb', 'g', 'ew', 'gl', "
    "'fl', 'ns')))",
  )();

  /// Muttermund (cervix) POSITION of the day, as a nullable TEXT token from
  /// the [CervixPosition] enum-name vocabulary: NULL when not observed,
  /// else 'low' / 'medium' / 'high' / 'veryHigh' / 'unreachable' (tief …
  /// unerreichbar). Stored like mucus_sign (TEXT enum-name tokens, engine
  /// CHECK on the vocabulary; note the deliberate distinction
  /// position:'medium' — the OPENING column below spells its middle value
  /// 'middle'). German display labels live in the l10n arbs.
  TextColumn get cervixPosition => text().nullable().customConstraint(
    "CHECK (cervix_position IS NULL OR cervix_position IN "
    "('low', 'medium', 'high', 'veryHigh', 'unreachable'))",
  )();

  /// Muttermund (cervix) OPENING of the day, as above: NULL when not
  /// observed, else 'closed' / 'middle' / 'open' (geschlossen · mittel ·
  /// offen). Independent of cervix_position.
  TextColumn get cervixOpening => text().nullable().customConstraint(
    "CHECK (cervix_opening IS NULL OR cervix_opening IN "
    "('closed', 'middle', 'open'))",
  )();

  /// Muttermund (cervix) FIRMNESS of the day, as above: NULL when not
  /// observed, else 'hard' / 'halfSoft' / 'soft' (paper shorthand h / h/w /
  /// w — fest / teils fest, teils weich / weich). Stored like mucus_sign
  /// (TEXT enum-name tokens, engine CHECK on the vocabulary; the tokens
  /// never collide with a position or opening token). German display labels
  /// live in the l10n arbs.
  TextColumn get cervixFirmness => text().nullable().customConstraint(
    "CHECK (cervix_firmness IS NULL OR cervix_firmness IN "
    "('hard', 'halfSoft', 'soft'))",
  )();

  /// Pain options of the day, as two independent flags with the cheat
  /// sheet's letters: breast tenderness (painBreast, letter B) and
  /// ovulation pain / Mittelschmerz (painMittelschmerz, letter M). Modeled
  /// like the disturbance flags: plain booleans, no interval system.
  BoolColumn get painBreast => boolean().withDefault(const Constant(false))();
  BoolColumn get painMittelschmerz =>
      boolean().withDefault(const Constant(false))();

  /// Times of day sex happened, as an INTEGER bitmask of [SexTiming.bit]:
  /// start(1) / middle(2) / end(4), OR-combined — multiple bits mean
  /// multiple times on the same day; 0 = not recorded. "Sex happened, time
  /// unknown" is deliberately NOT representable (the observation is only
  /// recorded together with a concrete time slot). customConstraint replaces
  /// drift's own constraints, so NOT NULL and the column default 0 are
  /// written out explicitly inside the constraint string (a bare CHECK
  /// would silently drop both, leaving the column nullable).
  IntColumn get sexTimings => integer()
      .withDefault(const Constant(0))
      .customConstraint(
        'NOT NULL DEFAULT 0 CHECK (sex_timings BETWEEN 0 AND 7)',
      )();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Assisted-mode markers a user places onto specific days (Mode M, ADR-0001).
///
/// One mark of a given type per day. The type is an open TEXT vocabulary so
/// future marking tools can add types without a migration; well-known
/// initial types are listed in [MarkTypes]. Uniqueness is enforced by the
/// unique index [userMarksDateTypeUnique] (@TableIndex below).
@TableIndex(
  name: 'user_marks_date_type_unique',
  columns: {#entryDate, #markType},
  unique: true,
)
class UserMarks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Calendar day the mark belongs to (unix-epoch days).
  IntColumn get entryDate => integer().map(const EpochDayConverter())();

  /// Marking tool identifier, e.g. one of the [MarkTypes] constants.
  TextColumn get markType => text()();

  /// Who placed the mark. 'user' today; foreign imports (drip CSV, old
  /// export documents) derive marks with the 'import' author; open TEXT in
  /// storage for future authoring modes instead of constraining to an enum.
  TextColumn get author => text().withDefault(const Constant('user'))();
}

/// Well-known initial mark types (Mode M tools; UI on the cycle-day sheet).
abstract final class MarkTypes {
  static const firstHigherMeasurement = 'firstHigherMeasurement';
  static const mucusPeakDay = 'mucusPeakDay';

  /// The temperature-ignore mark ("Temperatur ignorieren"): a marked day's
  /// temperature is EXCLUDED FROM THE TEMPERATURE EVALUATION — the day
  /// behaves like an unmeasured day in the evaluation arithmetic (no low
  /// number, no baseline contribution, a gap in the candidate sequence),
  /// see lib/domain/evaluation.dart. The mark never touches cycle-start
  /// suggestions (the suggestion is keyed purely to bleeding continuity —
  /// see lib/domain/cycle_grouping.dart). MANUAL ONLY (owner decision
  /// 2026-09-19): written/removed by the diary form's exclude switch and
  /// the day sheet's toggle; disturbance flags never auto-set it and
  /// clearing them never auto-removes it. Foreign imports derive it with
  /// author 'import'.
  static const ignoreTemperature = 'ignoreTemperature';

  /// The user-placed start of the sicher unfruchtbare Zeit (SUZ) from a
  /// MORNING: the SUZ bar renders at the day column's START (x − 0.5).
  /// The computed SUZ (rules D/E) is suggestion-only — see
  /// lib/ui/cycle_mark_sheet.dart; manual SUZ marks never alter the
  /// arithmetic (ADR-0001: user places, app computes).
  static const suzMorning = 'suzMorning';

  /// The user-placed SUZ start from an EVENING: the SUZ bar renders at the
  /// day column's MIDDLE (x).
  static const suzEvening = 'suzEvening';

  /// The user-placed start of a menstrual cycle: the authoritative cycle
  /// boundary of the mark-driven grouping (bleeding only suggests a cycle
  /// start — see lib/domain/cycle_grouping.dart).
  static const cycleStart = 'cycleStart';
}

/// Generic key-value storage for general settings (language, theme mode,
/// temperature range, and any future setting such as PDF export options).
///
/// Deliberately schema-free: a NEW setting is a NEW KEY with a typed accessor
/// on top (see lib/db/settings_store.dart), never a new column — the table
/// shape never changes again, so adding settings needs no schema bump.
/// The value always stores a JSON-encoded text (e.g. `"de"`, `"dark"`,
/// `{"min":35.0,"max":39.0}`); the JSON layer lives in the store, not here.
class AppSettings extends Table {
  /// Dot-namespaced setting identifier, e.g. 'locale', 'themeMode',
  /// 'temperatureRange', 'pdfExport.anonymize'.
  TextColumn get key => text()();

  /// JSON-encoded setting value.
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
