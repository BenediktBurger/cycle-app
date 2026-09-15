// Conversions between drift rows/companions and pure domain models.
// This is the ONLY place where drift types meet lib/domain types; the domain
// layer itself never imports drift.

import 'package:drift/drift.dart';

import '../domain/date_only.dart';
import '../domain/models.dart';
import 'cycle_database.dart';

/// Row -> domain model.
DailyEntry dailyEntryFromDrift(CycleEntry e) => DailyEntry(
      date: e.date,
      profileId: e.profileId,
      bbtC: e.bbtC,
      bleeding: e.bleeding,
      excludeIllness: e.excludeIllness,
      excludeAlcohol: e.excludeAlcohol,
      excludeTravel: e.excludeTravel,
      excludeOther: e.excludeOther,
      mucusFeeling: e.mucusFeeling,
      mucusNfp: e.mucusNfp,
      cervix: e.cervix,
      pain: e.pain,
      mood: e.mood,
      desire: e.desire,
      sex: e.sex,
      notes: e.notes,
    );

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
      mucusFeeling: Value(d.mucusFeeling),
      mucusNfp: Value(d.mucusNfp),
      cervix: Value(d.cervix),
      pain: Value(d.pain),
      mood: Value(d.mood),
      desire: Value(d.desire),
      sex: Value(d.sex),
      notes: Value(d.notes),
    );
