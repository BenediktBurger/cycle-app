// Pure-Dart domain models: no drift types, no Flutter imports. The db layer
// converts between these models and drift rows (see lib/db/mappers.dart).

import 'cervix.dart';
import 'date_only.dart';
import 'mucus.dart';

/// Bleeding intensity observed on a single day, on the shared 5-step numeric
/// scale (drip-compatible levels shifted by +1 so an explicit `none` exists).
///
/// Stored as INTEGER in SQLite — the [level] number below is what the db
/// layer and the export document carry; the db mapping MUST go through
/// `level`, never the Dart declaration index.
enum Bleeding {
  none(0),
  spotting(1),
  light(2),
  medium(3),
  heavy(4);

  const Bleeding(this.level);

  /// The stored scale value (0=none … 4=heavy).
  final int level;
}

/// Parses an export/storage bleeding field into the enum ([Bleeding.values]
/// vocabulary), null for anything else. SHARED by the import planner and the
/// db writer — the single source of truth for this field's validation, like
/// parseExportId for ids, so a row a writer would drop is never counted as a
/// write (and never vice versa). Accepts `Object?` (see tryParseBleeding's
/// callers: export rows arrive JSON-decoded as the loosest possible shape).
///
/// Two accepted shapes:
///  - `int` 0–4 → the enum member carrying that [Bleeding.level] (mapped by
///    level, NOT by declaration order) — the current document/storage scale;
///  - legacy string tokens `none` / `period` / `spotting` from old export
///    documents (the member vocabulary before heaviness existed). A string
///    of a NEW member name is deliberately invalid — the names are not a
///    storage format.
///
/// Both shapes parse regardless of the document's schema version (v1/v2
/// documents carry tokens, v3 carries numbers — the field parser is
/// shape-agnostic, see lib/domain/export_import.dart).
///
/// TODO(user-review): `period` means "menstruation, heaviness unknown"; it
/// degrades to `medium` (3), the central menstruation level. INER experts
/// may prefer a different default.
Bleeding? tryParseBleeding(Object? raw) {
  if (raw is int) {
    for (final b in Bleeding.values) {
      if (b.level == raw) return b;
    }
    return null;
  }
  if (raw is String) {
    return switch (raw) {
      'none' => Bleeding.none,
      'period' => Bleeding.medium,
      'spotting' => Bleeding.spotting,
      _ => null,
    };
  }
  return null;
}

/// Parses a stored/exported time-of-day token into minutes since midnight
/// (0–1439), the vocabulary of [DailyEntry.measuredAtMinutes].
///
/// An `int` is taken verbatim (inside the valid range); a numeric string is
/// tolerated like `parseExportId` (lib/domain/export_import.dart) tolerates
/// ids: lossy tools serialize integers as strings. Everything else —
/// including NULL-as-"not recorded" and out-of-range values — yields null.
/// Never drops a row: callers treat null as "field not recorded", mirroring
/// the SQL CHECK on the column.
int? tryParseMeasuredAtMinutes(Object? raw) {
  final int? minutes = switch (raw) {
    int() => raw,
    String() => int.tryParse(raw),
    _ => null,
  };
  if (minutes == null) return null;
  return (minutes >= 0 && minutes <= 1439) ? minutes : null;
}

/// One tracked day of cycle symptoms, decoupled from any storage layer.
///
/// Date semantics: [date] must be a calendar-day-only value (see
/// [DateOnly.normalize]); time-of-day components are ignored everywhere.
final class DailyEntry {
  const DailyEntry({
    required this.date,
    this.profileId = 1,
    this.bbtC,
    int? measuredAtMinutes,
    this.bleeding = Bleeding.none,
    this.excludeIllness = false,
    this.excludeAlcohol = false,
    this.excludeTravel = false,
    this.excludeOther = false,
    this.mucusSign,
    this.mucusQuality,
    this.cervix,
    this.cervixPosition,
    this.cervixOpening,
    this.painBreast = false,
    this.painMittelschmerz = false,
    this.mood = false,
    this.desire = false,
    this.sex = false,
    this.notes,
  })  : // The measurement time is metadata OF the temperature measurement:
        // without a temperature there is no measurement to time, so the time
        // is dropped — never stored (and never invented) on mucus-only etc.
        // days. Enforcing this in the constructor makes every writer (db
        // mappers, export/import, the drip importer, the entry form) inherit
        // the rule; copyWith re-runs it through this constructor.
        measuredAtMinutes = bbtC == null ? null : measuredAtMinutes,
        assert(mucusQuality == null || mucusSign == MucusSign.s,
            'mucusQuality is only valid together with mucusSign == MucusSign.s');

  final int profileId;
  final DateTime date;

  /// Basal body temperature in degrees Celsius, if measured.
  final double? bbtC;

  /// Time-of-day of the temperature measurement, as minutes since midnight
  /// (0–1439), or null when the user did not record it. Stored per day —
  /// the entry form prefills the CURRENT time for a fresh day and keeps an
  /// already-stored value when the day is re-opened (UI layer, see
  /// lib/ui/diary.dart; injectable clock there).
  ///
  /// Invariant: only ever set together with [bbtC] — the constructor drops
  /// a time without a temperature (and `copyWith(bbtC: null)` therefore
  /// drops the time as well). The time is metadata of the temperature
  /// measurement; it belongs to nothing else and is never stored alone.
  final int? measuredAtMinutes;

  final Bleeding bleeding;

  // Disturbance/exclusion flags: a day with any flag set is an interrupted
  // day for evaluation purposes (illness, alcohol, travel, other events).
  final bool excludeIllness;
  final bool excludeAlcohol;
  final bool excludeTravel;
  final bool excludeOther;

  /// Fertility sign observed on the day (t / Ø-nichts / f / S), or null when
  /// no observation was recorded. Stored verbatim — never interpreted (Mode
  /// M, ADR-0001).
  final MucusSign? mucusSign;

  /// Quality qualifier of the mucus sign; null for every sign other than
  /// `MucusSign.s` (constructor assert mirrors the SQL CHECK constraint).
  final MucusQuality? mucusQuality;

  /// Optional cervix observation note (e.g. open/closed, position).
  final String? cervix;

  /// Muttermund (cervix) observation of the day, as two independent
  /// categorical options: how deep the cervix sat ([CervixPosition],
  /// tief … unerreichbar) and how far it was open ([CervixOpening],
  /// geschlossen … offen). Each null when not observed; no rule binds the
  /// two together. Stored/displayed verbatim — never interpreted
  /// (Mode M, ADR-0001). The display glyphs live in lib/domain/cervix.dart.
  final CervixPosition? cervixPosition;
  final CervixOpening? cervixOpening;

  /// Pain experiences of the day, as two independent flags — the
  /// letter-coded pain options of the cheat sheet: breast tenderness
  /// (`painBreast`, letter B) and ovulation pain (Mittelschmerz,
  /// `painMittelschmerz`, letter M). Modeled like the exclusion flags:
  /// plain per-day booleans, no interval system.
  final bool painBreast;
  final bool painMittelschmerz;

  final bool mood;
  final bool desire;
  final bool sex;

  final String? notes;

  /// True when the day carries at least one exclusion flag, i.e. it is an
  /// interrupted day. Interrupted days never start cycles
  /// (see lib/domain/cycle_grouping.dart).
  bool get isExcluded =>
      excludeIllness || excludeAlcohol || excludeTravel || excludeOther;

  DailyEntry copyWith({
    DateTime? date,
    int? profileId,
    Object? bbtC = _sentinel,
    Object? measuredAtMinutes = _sentinel,
    Bleeding? bleeding,
    bool? excludeIllness,
    bool? excludeAlcohol,
    bool? excludeTravel,
    bool? excludeOther,
    Object? mucusSign = _sentinel,
    Object? mucusQuality = _sentinel,
    Object? cervix = _sentinel,
    Object? cervixPosition = _sentinel,
    Object? cervixOpening = _sentinel,
    bool? painBreast,
    bool? painMittelschmerz,
    bool? mood,
    bool? desire,
    bool? sex,
    Object? notes = _sentinel,
  }) {
    return DailyEntry(
      date: date ?? this.date,
      profileId: profileId ?? this.profileId,
      bbtC: bbtC == _sentinel ? this.bbtC : bbtC as double?,
      measuredAtMinutes: measuredAtMinutes == _sentinel
          ? this.measuredAtMinutes
          : measuredAtMinutes as int?,
      bleeding: bleeding ?? this.bleeding,
      excludeIllness: excludeIllness ?? this.excludeIllness,
      excludeAlcohol: excludeAlcohol ?? this.excludeAlcohol,
      excludeTravel: excludeTravel ?? this.excludeTravel,
      excludeOther: excludeOther ?? this.excludeOther,
      mucusSign:
          mucusSign == _sentinel ? this.mucusSign : mucusSign as MucusSign?,
      mucusQuality: mucusQuality == _sentinel
          ? this.mucusQuality
          : mucusQuality as MucusQuality?,
      cervix: cervix == _sentinel ? this.cervix : cervix as String?,
      cervixPosition: cervixPosition == _sentinel
          ? this.cervixPosition
          : cervixPosition as CervixPosition?,
      cervixOpening: cervixOpening == _sentinel
          ? this.cervixOpening
          : cervixOpening as CervixOpening?,
      painBreast: painBreast ?? this.painBreast,
      painMittelschmerz: painMittelschmerz ?? this.painMittelschmerz,
      mood: mood ?? this.mood,
      desire: desire ?? this.desire,
      sex: sex ?? this.sex,
      notes: notes == _sentinel ? this.notes : notes as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyEntry &&
        DateOnly.sameDay(date, other.date) &&
        profileId == other.profileId &&
        bbtC == other.bbtC &&
        measuredAtMinutes == other.measuredAtMinutes &&
        bleeding == other.bleeding &&
        excludeIllness == other.excludeIllness &&
        excludeAlcohol == other.excludeAlcohol &&
        excludeTravel == other.excludeTravel &&
        excludeOther == other.excludeOther &&
        mucusSign == other.mucusSign &&
        mucusQuality == other.mucusQuality &&
        cervix == other.cervix &&
        cervixPosition == other.cervixPosition &&
        cervixOpening == other.cervixOpening &&
        painBreast == other.painBreast &&
        painMittelschmerz == other.painMittelschmerz &&
        mood == other.mood &&
        desire == other.desire &&
        sex == other.sex &&
        notes == other.notes;
  }

  @override
  int get hashCode => Object.hash(
        DateOnly.normalize(date),
        profileId,
        bbtC,
        measuredAtMinutes,
        bleeding,
        excludeIllness,
        excludeAlcohol,
        excludeTravel,
        excludeOther,
        mucusSign,
        mucusQuality,
        cervix,
        cervixPosition,
        cervixOpening,
        painBreast,
        painMittelschmerz,
        mood,
        desire,
        sex,
        notes,
      );

  @override
  String toString() =>
      'DailyEntry(${DateOnly.normalize(date).toIso8601String()}, '
      'profile:$profileId, bbt:$bbtC, measuredAt:$measuredAtMinutes, '
      'bleeding:$bleeding, '
      'excluded:$isExcluded, mucusSign:$mucusSign, '
      'mucusQuality:$mucusQuality, '
      'cervixPosition:$cervixPosition, cervixOpening:$cervixOpening)';
}
