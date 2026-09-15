// Mucus observation vocabulary and the feeling -> NFP 0..4 scale mapping.
//
// TODO(user-review): the mapping below is a first, pragmatic encoding of the
// NFP (Rötzer) mucus scale 0–4 from everyday feelings, recorded as a working
// assumption pending expert review (ADR-0001,
// docs/adr/0001-iner-mode-m-hypothesis.md). If experts correct it, edit the
// `mappedNfp` values in exactly ONE place — this table — nothing else.
// Keep the SHARED `enum` NAMES stable: they are stored verbatim in the
// database and in the export schema, so a rename is a data migration.
//
// The scale itself (NFP convention, in numbers):
//   0 = no mucus feeling / dry
//   1 = first moist, barely fertile-relevant mucus
//   2 = more moist / creamy mucus
//   3 = clearly wet and/or stretchy mucus, day(s) before the peak
//   4 = peak-like, very stretchy and slippery (egg-white) mucus
//
// UI consequence: the entry form shows the mapped value as a suggestion and
// lets the user override it per day — the mapping is only an assistant.

enum MucusFeeling {
  /// No moist mucus feeling.
  dry(0),

  /// Sticky, opaque, bread-porridge-like.
  sticky(1),

  /// Milky, creamy, hand-lotion-like.
  creamy(2),

  /// Moist without clearly sticky consistency.
  moist(2),

  /// Clearly wet and starting to become slippery.
  wet(3),

  /// Stringy/stretchy and slippery, like raw egg white (peak-like).
  stretchy(4);

  const MucusFeeling(this.mappedNfp);

  /// The NFP scale value this feeling maps to (0..4). The user can freely
  /// override it per day in the entry form.
  final int mappedNfp;

  /// Parses a storage/export identifier back into a feeling, or null.
  static MucusFeeling? tryFromName(String name) {
    for (final f in MucusFeeling.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// The feeling an entry displays when only the numeric NFP value is known
/// (e.g. from a previous version/import): the inverse mapping (first
/// feeling with that value, preferring canonical names in declaration
/// order). Returns null for out-of-scale or null input.
MucusFeeling? feelingForNfp(int? nfp) {
  if (nfp == null || nfp < 0 || nfp > mucusNfpMax) return null;
  for (final f in MucusFeeling.values) {
    if (f.mappedNfp == nfp) return f;
  }
  return null;
}

/// Guards the mucus NFP value the same way the database CHECK constraint
/// does (cycle_entries.mucus_nfp); returns null for out-of-scale input.
int? clampedMucusNfp(Object? raw) {
  if (raw is! int) return null;
  if (raw < 0 || raw > mucusNfpMax) return null;
  return raw;
}

/// Scale max, matching the DailyEntry assertion in models.dart and the SQL
/// CHECK constraint on cycle_entries.mucus_nfp.
const int mucusNfpMax = 4;
