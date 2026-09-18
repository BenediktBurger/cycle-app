// Conversions between drift rows/companions and pure domain models.
// This is the ONLY place where drift types meet lib/domain types; the domain
// layer itself never imports drift.

import 'package:drift/drift.dart';

import '../domain/cervix.dart';
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
    bbtC: e.bbtC,
    measuredAtMinutes: e.measuredAtMinutes,
    bleeding: e.bleeding,
    tempDisturbances: e.tempDisturbances,
    mucusSign: mucus.sign,
    mucusQuality: mucus.quality,
    cervixPosition: tryParseCervixPosition(e.cervixPosition),
    cervixOpening: tryParseCervixOpening(e.cervixOpening),
    cervixFirmness: tryParseCervixFirmness(e.cervixFirmness),
    painBreast: e.painBreast,
    painMittelschmerz: e.painMittelschmerz,
    // Stored as the mask itself (0..7, engine CHECK); no per-bit conversion
    // happens on either side — the SexTiming.bit values ARE the storage.
    sexTimings: e.sexTimings,
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
    date: Value(DateOnly.normalize(d.date)),
    bbtC: Value(d.bbtC),
    measuredAtMinutes: Value(d.measuredAtMinutes),
    bleeding: Value(d.bleeding),
    tempDisturbances: Value(d.tempDisturbances),
    // Stable enum-name TEXT tokens (bleeding itself is the numeric level
    // column), written post-sanitize so the pair can never violate the SQL
    // CHECK.
    mucusSign: Value(mucus.sign?.name),
    mucusQuality: Value(mucus.quality?.name),
    // Stable enum-name TEXT tokens (like mucusSign/mucusQuality); the CHECK
    // constraints on the columns accept exactly this vocabulary.
    cervixPosition: Value(d.cervixPosition?.name),
    cervixOpening: Value(d.cervixOpening?.name),
    cervixFirmness: Value(d.cervixFirmness?.name),
    painBreast: Value(d.painBreast),
    painMittelschmerz: Value(d.painMittelschmerz),
    // The mask as-is (DailyEntry's constructor already asserts 0..7, which
    // the SQL CHECK mirrors); the SexTiming.bit values ARE the storage, no
    // per-bit conversion happens here either.
    sexTimings: Value(d.sexTimings),
    notes: Value(d.notes),
  );
}

/// UserMarks row -> domain model. The mark vocabulary is open TEXT in
/// storage, so no sanitizing gate applies: an unknown token must survive
/// the round trip verbatim (future tools write them; the schema is the
/// vocabulary authority, not the mapper).
CycleMark cycleMarkFromDrift(UserMark m) => CycleMark(
      date: m.entryDate,
      type: m.markType,
      author: m.author,
    );

/// Domain model -> companion. Marks are add/remove events (toggle semantics
/// in the DAO), never partial patches, so every field is written explicitly
/// — a companion built from a [CycleMark] is a complete replacement row.
UserMarksCompanion cycleMarkToCompanion(CycleMark mark) => UserMarksCompanion(
      entryDate: Value(DateOnly.normalize(mark.date)),
      markType: Value(mark.type),
      author: Value(mark.author),
    );
