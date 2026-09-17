// Conversions between drift rows/companions and pure domain models.
// This is the ONLY place where drift types meet lib/domain types; the domain
// layer itself never imports drift.

import 'package:drift/drift.dart';

import '../domain/date_only.dart';
import '../domain/marks.dart';
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
    measuredAtMinutes: e.measuredAtMinutes,
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
CycleEntriesCompanion dailyEntryToCompanion(DailyEntry d) {
  // Belt-and-braces parity with the read direction: the shared guard runs at
  // the write boundary too. DailyEntry's constructor already enforces
  // quality-only-with-S; sanitizing here as well means the tokens written
  // always satisfy the SQL CHECK even if that invariant ever weakens.
  final mucus = sanitizeMucusPair(sign: d.mucusSign, quality: d.mucusQuality);
  return CycleEntriesCompanion(
    profileId: Value(d.profileId),
    date: Value(DateOnly.normalize(d.date)),
    bbtC: Value(d.bbtC),
    measuredAtMinutes: Value(d.measuredAtMinutes),
    bleeding: Value(d.bleeding),
    excludeIllness: Value(d.excludeIllness),
    excludeAlcohol: Value(d.excludeAlcohol),
    excludeTravel: Value(d.excludeTravel),
    excludeOther: Value(d.excludeOther),
    // Stable enum-name TEXT tokens (bleeding itself is the numeric level
    // column), written post-sanitize so the pair can never violate the SQL
    // CHECK.
    mucusSign: Value(mucus.sign?.name),
    mucusQuality: Value(mucus.quality?.name),
    cervix: Value(d.cervix),
    pain: Value(d.pain),
    mood: Value(d.mood),
    desire: Value(d.desire),
    sex: Value(d.sex),
    notes: Value(d.notes),
  );
}

/// UserMarks row -> domain model. The mark vocabulary is open TEXT in
/// storage, so no sanitizing gate applies: an unknown token must survive
/// the round trip verbatim (future tools write them; the schema is the
/// vocabulary authority, not the mapper).
CycleMark cycleMarkFromDrift(UserMark m) => CycleMark(
      profileId: m.profileId,
      date: m.entryDate,
      type: m.markType,
      author: m.author,
    );

/// Domain model -> companion. Marks are add/remove events (toggle semantics
/// in the DAO), never partial patches, so every field is written explicitly
/// — a companion built from a [CycleMark] is a complete replacement row.
UserMarksCompanion cycleMarkToCompanion(CycleMark mark) => UserMarksCompanion(
      profileId: Value(mark.profileId),
      entryDate: Value(DateOnly.normalize(mark.date)),
      markType: Value(mark.type),
      author: Value(mark.author),
    );
