// Conversions between drift rows/companions and pure domain models.
// This is the ONLY place where drift types meet lib/domain types; the domain
// layer itself never imports drift.

import 'package:drift/drift.dart';

import '../domain/date_only.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import 'cycle_database.dart';

/// Row -> domain model.
///
/// The stored tokens go through the shared parse helpers; a quality token on
/// a row without the S sign cannot exist behind the SQL CHECK, but the pair
/// is sanitized anyway (defense in depth): the mapper must never emit a
/// (sign, quality) pair that DailyEntry (or the CHECK) would reject.
DailyEntry dailyEntryFromDrift(CycleEntry e) {
  final mucus = sanitizeMucusPair(
    sign: tryParseMucusSign(e.mucusSign),
    quality: tryParseMucusQuality(e.mucusQuality),
  );
  return DailyEntry(
    date: e.date,
    profileId: e.profileId,
    bbtC: e.bbtC,
    bleeding: e.bleeding,
    excludeIllness: e.excludeIllness,
    excludeAlcohol: e.excludeAlcohol,
    excludeTravel: e.excludeTravel,
    excludeOther: e.excludeOther,
    mucusSign: mucus.sign,
    mucusQuality: mucus.quality,
    cervix: e.cervix,
    pain: e.pain,
    mood: e.mood,
    desire: e.desire,
    sex: e.sex,
    notes: e.notes,
  );
}

/// Domain model -> companion. Every domain field is written explicitly
/// (Value(null) for nulls), which makes the EntriesDao upsert a genuine
/// FULL replacement of the day's entry rather than a sparse patch.
CycleEntriesCompanion dailyEntryToCompanion(DailyEntry d) =>
    CycleEntriesCompanion(
      profileId: Value(d.profileId),
      date: Value(DateOnly.normalize(d.date)),
      bbtC: Value(d.bbtC),
      bleeding: Value(d.bleeding),
      excludeIllness: Value(d.excludeIllness),
      excludeAlcohol: Value(d.excludeAlcohol),
      excludeTravel: Value(d.excludeTravel),
      excludeOther: Value(d.excludeOther),
      // Stable enum-name TEXT tokens (like bleeding); DailyEntry enforces
      // quality-only-with-S, so the pair written here always satisfies the
      // SQL CHECK.
      mucusSign: Value(d.mucusSign?.name),
      mucusQuality: Value(d.mucusQuality?.name),
      cervix: Value(d.cervix),
      pain: Value(d.pain),
      mood: Value(d.mood),
      desire: Value(d.desire),
      sex: Value(d.sex),
      notes: Value(d.notes),
    );
