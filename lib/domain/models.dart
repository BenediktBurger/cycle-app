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
/// db writer — the single source of truth for this field's validation, so a
/// row a writer would drop is never counted as a write (and never vice
/// versa). Accepts `Object?` (see tryParseBleeding's callers: export rows
/// arrive JSON-decoded as the loosest possible shape).
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
/// tolerated because lossy tools serialize integers as strings. Everything
/// else — including NULL-as-"not recorded" and out-of-range values — yields
/// null.
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

/// One time-of-day of sex on a tracked day, as a single-bit flag. A day
/// stores the OR of the observed times in [DailyEntry.sexTimings] — multiple
/// bits mean multiple times on the same day.
///
/// Stored as INTEGER (the bitmask itself, not a numbered scale like
/// Bleeding.level) in the db and the export document; the db mapping MUST go
/// through `bit`, never the Dart declaration index. Note the deliberate
/// vocabulary decision: "sex happened, but the time is unknown" is NOT
/// representable — the observation is either tied to a recorded time or not
/// recorded.
enum SexTiming {
  start(1),
  middle(2),
  end(4);

  const SexTiming(this.bit);

  /// The single bit this timing contributes to a day's mask.
  final int bit;
}

/// One temperature-disturbance flag of a tracked day (the NER "Störungen"
/// vocabulary), as a single-bit flag. A day stores the OR of the observed
/// flags in [DailyEntry.tempDisturbances] — multiple bits mean multiple
/// disturbances on the same day.
///
/// Stored as an INTEGER (the mask itself) in the db column
/// `temp_disturbances` and in the export document key `temp_disturbances`;
/// the db mapping MUST go through `bit`, never the Dart declaration index.
/// NOTE the vocabulary decision: Reise (travel) is NOT representable — the
/// old exclusion-reason booleans are gone. This mask is RAW data whose
/// remaining visual consumer is the Tagebuch list's interrupted-day badge
/// (the temperature curve is MARK-keyed since owner decision 2026-09-19: the
/// ignoreTemperature mark, not this mask, dims the curve). The temperature
/// evaluation uses the separate ignoreTemperature MARK (see
/// lib/domain/evaluation.dart), which the diary save auto-sets
/// (idempotently) whenever a flag is selected; cycle-start suggestions are
/// untouched by both (bleeding continuity only).
enum TempDisturbance {
  /// Late to bed ("spät ins Bett").
  sp(1),

  /// Frequent night awakening ("häufig aufstehen").
  a(2),

  /// Alcohol.
  alk(4),

  /// Illness ("krank").
  kr(8);

  const TempDisturbance(this.bit);

  /// The single bit this disturbance contributes to a day's mask.
  final int bit;

  /// The stable token of the flag: the enum name itself (display letters
  /// come from the tokens — sp/a/alk/kr; a rename is therefore a storage
  /// change, not a refactor).
  String get token => name;
}

/// Parses a stored/exported `temp_disturbances` value into the 0..15 mask
/// (the vocabulary of [DailyEntry.tempDisturbances]).
///
/// An `int` inside 0..15 is taken verbatim. Everything else — a missing
/// key, a non-int, an out-of-range or negative value — collapses to 0 ("no
/// disturbance"), NEVER a row killer: same lenient-coercion principle as
/// the other coercible fields (mucus tokens, sex_timings), so foreign/legacy
/// data cannot invalidate a row through this field. SHARED by the db layer
/// and the export/import writer — the single source of truth for this
/// field's validation.
int tryParseTempDisturbances(Object? raw) {
  if (raw is! int) return 0;
  return (raw >= 0 && raw <= 15) ? raw : 0;
}

/// One tracked day of cycle symptoms, decoupled from any storage layer.
///
/// Date semantics: [date] must be a calendar-day-only value (see
/// [DateOnly.normalize]); time-of-day components are ignored everywhere.
final class DailyEntry {
  const DailyEntry({
    required this.date,
    this.bbtC,
    int? measuredAtMinutes,
    this.bleeding = Bleeding.none,
    this.tempDisturbances = 0,
    this.mucusSign,
    this.mucusQuality,
    this.cervixPosition,
    this.cervixOpening,
    this.cervixFirmness,
    this.painBreast = false,
    this.painMittelschmerz = false,
    this.sexTimings = 0,
    this.notes,
  })  : // The measurement time is metadata OF the temperature measurement:
        // without a temperature there is no measurement to time, so the time
        // is dropped — never stored (and never invented) on mucus-only etc.
        // days. Enforcing this in the constructor makes every writer (db
        // mappers, export/import, the drip importer, the entry form) inherit
        // the rule; copyWith re-runs it through this constructor.
        measuredAtMinutes = bbtC == null ? null : measuredAtMinutes,
        assert(mucusQuality == null || mucusSign == MucusSign.s,
            'mucusQuality is only valid together with mucusSign == MucusSign.s'),
        // The mask must stay inside the TempDisturbance vocabulary: exactly
        // the 4 bits (0..15). Anything else — negative, or a value with
        // unknown bits — cannot round-trip through storage, so the
        // constructor rejects it (same assert style as the mucus-quality
        // rule).
        assert(
            tempDisturbances >= 0 && tempDisturbances <= 15,
            'tempDisturbances must be a mask of TempDisturbance bits '
            '(0..15), got $tempDisturbances'),
        // The mask must stay inside the SexTiming vocabulary: exactly the
        // 3 bits (0..7). Anything else — negative, or a value with unknown
        // bits — cannot round-trip through storage, so the constructor
        // rejects it (same assert style as the mucus-quality rule).
        assert(sexTimings >= 0 && sexTimings <= 7,
            'sexTimings must be a mask of SexTiming bits (0..7), got $sexTimings');

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

  /// Raw disturbance flags of the day, as a bitmask of [TempDisturbance.bit]
  /// values (0 = no disturbance; 1 sp / 2 a / 4 alk / 8 kr; OR-combined for
  /// multiple disturbances on one day). RAW data: its remaining visual
  /// consumer is the Tagebuch list's interrupted-day badge — the
  /// temperature curve is MARK-keyed (the ignoreTemperature mark dims it,
  /// see lib/ui/cycle_curve.dart) and the temperature evaluation ignores
  /// marked days entirely (see lib/domain/evaluation.dart).
  final int tempDisturbances;

  /// Fertility sign observed on the day (t / Ø-nichts / f / S / f/S
  /// ("f vor S an einem Tag") / A-Ausfluss), or null when no observation
  /// was recorded. Stored verbatim — never interpreted (Mode M, ADR-0001).
  final MucusSign? mucusSign;

  /// Quality qualifier of the mucus sign; null for every sign other than
  /// `MucusSign.s` (constructor assert mirrors the SQL CHECK constraint;
  /// the 'fs' sign carries no quality either).
  final MucusQuality? mucusQuality;

  /// Muttermund (cervix) observation of the day, as three independent
  /// categorical options: how deep the cervix sat ([CervixPosition],
  /// tief … unerreichbar), how far it was open ([CervixOpening],
  /// geschlossen … offen), and how firm it felt ([CervixFirmness],
  /// h / h-w / w). Each null when not observed; no rule binds them
  /// together. Stored/displayed verbatim — never interpreted
  /// (Mode M, ADR-0001). The display glyphs live in lib/domain/cervix.dart.
  final CervixPosition? cervixPosition;
  final CervixOpening? cervixOpening;
  final CervixFirmness? cervixFirmness;

  /// Pain experiences of the day, as two independent flags — the
  /// letter-coded pain options of the cheat sheet: breast tenderness
  /// (`painBreast`, letter B) and ovulation pain (Mittelschmerz,
  /// `painMittelschmerz`, letter M). Modeled like the disturbance flags:
  /// plain per-day booleans, no interval system.
  final bool painBreast;
  final bool painMittelschmerz;

  /// Times of day sex happened, as a bitmask of [SexTiming.bit] values
  /// (0 = not recorded; 1 start / 2 middle / 4 end; OR-combined for
  /// multiple times on one day). "Sex happened, time unknown" is
  /// deliberately NOT representable — the observation is only recorded
  /// together with a concrete time slot.
  final int sexTimings;

  final String? notes;

  /// True when the day carries at least one raw disturbance flag, i.e. the
  /// temperature is interrupted (the input of the Tagebuch list's
  /// interrupted-day badge — the curve renders MARK-keyed since owner
  /// decision 4, and the temperature EVALUATION uses the separate
  /// ignoreTemperature mark; neither consumes this getter — see
  /// lib/domain/evaluation.dart).
  bool get isInterrupted => tempDisturbances != 0;

  DailyEntry copyWith({
    DateTime? date,
    Object? bbtC = _sentinel,
    Object? measuredAtMinutes = _sentinel,
    Bleeding? bleeding,
    int? tempDisturbances,
    Object? mucusSign = _sentinel,
    Object? mucusQuality = _sentinel,
    Object? cervixPosition = _sentinel,
    Object? cervixOpening = _sentinel,
    Object? cervixFirmness = _sentinel,
    bool? painBreast,
    bool? painMittelschmerz,
    int? sexTimings,
    Object? notes = _sentinel,
  }) {
    return DailyEntry(
      date: date ?? this.date,
      bbtC: bbtC == _sentinel ? this.bbtC : bbtC as double?,
      measuredAtMinutes: measuredAtMinutes == _sentinel
          ? this.measuredAtMinutes
          : measuredAtMinutes as int?,
      bleeding: bleeding ?? this.bleeding,
      tempDisturbances: tempDisturbances ?? this.tempDisturbances,
      mucusSign:
          mucusSign == _sentinel ? this.mucusSign : mucusSign as MucusSign?,
      mucusQuality: mucusQuality == _sentinel
          ? this.mucusQuality
          : mucusQuality as MucusQuality?,
      cervixPosition: cervixPosition == _sentinel
          ? this.cervixPosition
          : cervixPosition as CervixPosition?,
      cervixOpening: cervixOpening == _sentinel
          ? this.cervixOpening
          : cervixOpening as CervixOpening?,
      cervixFirmness: cervixFirmness == _sentinel
          ? this.cervixFirmness
          : cervixFirmness as CervixFirmness?,
      painBreast: painBreast ?? this.painBreast,
      painMittelschmerz: painMittelschmerz ?? this.painMittelschmerz,
      sexTimings: sexTimings ?? this.sexTimings,
      notes: notes == _sentinel ? this.notes : notes as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyEntry &&
        DateOnly.sameDay(date, other.date) &&
        bbtC == other.bbtC &&
        measuredAtMinutes == other.measuredAtMinutes &&
        bleeding == other.bleeding &&
        tempDisturbances == other.tempDisturbances &&
        mucusSign == other.mucusSign &&
        mucusQuality == other.mucusQuality &&
        cervixPosition == other.cervixPosition &&
        cervixOpening == other.cervixOpening &&
        cervixFirmness == other.cervixFirmness &&
        painBreast == other.painBreast &&
        painMittelschmerz == other.painMittelschmerz &&
        sexTimings == other.sexTimings &&
        notes == other.notes;
  }

  @override
  int get hashCode => Object.hash(
        DateOnly.normalize(date),
        bbtC,
        measuredAtMinutes,
        bleeding,
        tempDisturbances,
        mucusSign,
        mucusQuality,
        cervixPosition,
        cervixOpening,
        cervixFirmness,
        painBreast,
        painMittelschmerz,
        sexTimings,
        notes,
      );

  @override
  String toString() =>
      'DailyEntry(${DateOnly.normalize(date).toIso8601String()}, '
      'bbt:$bbtC, measuredAt:$measuredAtMinutes, '
      'bleeding:$bleeding, tempDisturbances:$tempDisturbances, '
      'mucusSign:$mucusSign, '
      'mucusQuality:$mucusQuality, '
      'cervixPosition:$cervixPosition, cervixOpening:$cervixOpening, '
      'cervixFirmness:$cervixFirmness, sexTimings:$sexTimings)';
}
