// Pure-Dart domain models: no drift types, no Flutter imports. The db layer
// converts between these models and drift rows (see lib/db/mappers.dart).

import 'date_only.dart';

/// Bleeding intensity observed on a single day.
///
/// Stored as TEXT in SQLite (the enum name) — see lib/db/converters.dart.
enum Bleeding { none, period, spotting }

/// One tracked day of cycle symptoms, decoupled from any storage layer.
///
/// Date semantics: [date] must be a calendar-day-only value (see
/// [DateOnly.normalize]); time-of-day components are ignored everywhere.
final class DailyEntry {
  const DailyEntry({
    required this.date,
    this.profileId = 1,
    this.bbtC,
    this.bleeding = Bleeding.none,
    this.excludeIllness = false,
    this.excludeAlcohol = false,
    this.excludeTravel = false,
    this.excludeOther = false,
    this.mucusFeeling,
    this.mucusNfp,
    this.cervix,
    this.pain = false,
    this.mood = false,
    this.desire = false,
    this.sex = false,
    this.notes,
  }) : assert(mucusNfp == null || (mucusNfp >= 0 && mucusNfp <= 4),
            'mucusNfp must be within 0..4 (NFP scale) or null');

  final int profileId;
  final DateTime date;

  /// Basal body temperature in degrees Celsius, if measured.
  final double? bbtC;

  final Bleeding bleeding;

  // Disturbance/exclusion flags: a day with any flag set is an interrupted
  // day for evaluation purposes (illness, alcohol, travel, other events).
  final bool excludeIllness;
  final bool excludeAlcohol;
  final bool excludeTravel;
  final bool excludeOther;

  /// Free-text cervical mucus description as entered by the user.
  final String? mucusFeeling;

  /// NFP mucus scale 0..4 (0 = none ... 4 = stretchy/clear, last "peak-like"
  /// value). Null when the user only gave a free-text feeling.
  final int? mucusNfp;

  /// Optional cervix observation note (e.g. open/closed, position).
  final String? cervix;

  final bool pain;
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
    Bleeding? bleeding,
    bool? excludeIllness,
    bool? excludeAlcohol,
    bool? excludeTravel,
    bool? excludeOther,
    Object? mucusFeeling = _sentinel,
    Object? mucusNfp = _sentinel,
    Object? cervix = _sentinel,
    bool? pain,
    bool? mood,
    bool? desire,
    bool? sex,
    Object? notes = _sentinel,
  }) {
    return DailyEntry(
      date: date ?? this.date,
      profileId: profileId ?? this.profileId,
      bbtC: bbtC == _sentinel ? this.bbtC : bbtC as double?,
      bleeding: bleeding ?? this.bleeding,
      excludeIllness: excludeIllness ?? this.excludeIllness,
      excludeAlcohol: excludeAlcohol ?? this.excludeAlcohol,
      excludeTravel: excludeTravel ?? this.excludeTravel,
      excludeOther: excludeOther ?? this.excludeOther,
      mucusFeeling: mucusFeeling == _sentinel
          ? this.mucusFeeling
          : mucusFeeling as String?,
      mucusNfp: mucusNfp == _sentinel ? this.mucusNfp : mucusNfp as int?,
      cervix: cervix == _sentinel ? this.cervix : cervix as String?,
      pain: pain ?? this.pain,
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
        bleeding == other.bleeding &&
        excludeIllness == other.excludeIllness &&
        excludeAlcohol == other.excludeAlcohol &&
        excludeTravel == other.excludeTravel &&
        excludeOther == other.excludeOther &&
        mucusFeeling == other.mucusFeeling &&
        mucusNfp == other.mucusNfp &&
        cervix == other.cervix &&
        pain == other.pain &&
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
        bleeding,
        excludeIllness,
        excludeAlcohol,
        excludeTravel,
        excludeOther,
        mucusFeeling,
        mucusNfp,
        cervix,
        pain,
        mood,
        desire,
        sex,
        notes,
      );

  @override
  String toString() =>
      'DailyEntry(${DateOnly.normalize(date).toIso8601String()}, '
      'profile:$profileId, bbt:$bbtC, bleeding:$bleeding, '
      'excluded:$isExcluded, mucusNfp:$mucusNfp)';
}
