/// Which diary entry items the user tracks, and whether each one's entry
/// options appear on the Tagebuch form at all ("Was aufzeichnen" settings
/// card). Hiding is view-only: the form still loads and saves a stored
/// day's values for a hidden item (lib/ui/diary.dart).
///
/// One value for the whole family, one JSON map under one settings key:
/// a later item joins by adding one enum value, one field and one decoder
/// default here. A stored map missing a later-added key decodes to the new
/// item's default; unknown item keys are ignored.
enum DiaryItem { temperature, mucus, cervix, sex, pain }

final class DiaryTrack {
  const DiaryTrack({
    this.temperature = true,
    this.mucus = true,
    this.cervix = false,
    this.sex = true,
    this.pain = true,
  });

  static const DiaryTrack defaults = DiaryTrack();

  final bool temperature;
  final bool mucus;
  final bool cervix;
  final bool sex;
  final bool pain;

  bool isTracked(DiaryItem item) => switch (item) {
    DiaryItem.temperature => temperature,
    DiaryItem.mucus => mucus,
    DiaryItem.cervix => cervix,
    DiaryItem.sex => sex,
    DiaryItem.pain => pain,
  };

  /// A copy with exactly one item's tracking flipped — the write the
  /// settings card's switches issue.
  DiaryTrack withTracked(DiaryItem item, bool tracked) => switch (item) {
    DiaryItem.temperature => DiaryTrack(
      temperature: tracked,
      mucus: mucus,
      cervix: cervix,
      sex: sex,
      pain: pain,
    ),
    DiaryItem.mucus => DiaryTrack(
      temperature: temperature,
      mucus: tracked,
      cervix: cervix,
      sex: sex,
      pain: pain,
    ),
    DiaryItem.cervix => DiaryTrack(
      temperature: temperature,
      mucus: mucus,
      cervix: tracked,
      sex: sex,
      pain: pain,
    ),
    DiaryItem.sex => DiaryTrack(
      temperature: temperature,
      mucus: mucus,
      cervix: cervix,
      sex: tracked,
      pain: pain,
    ),
    DiaryItem.pain => DiaryTrack(
      temperature: temperature,
      mucus: mucus,
      cervix: cervix,
      sex: sex,
      pain: tracked,
    ),
  };

  /// JSON-map form for the generic settings store (the exact shape the
  /// app_settings column holds).
  Map<String, Object?> toJson() => {
    for (final item in DiaryItem.values) item.name: isTracked(item),
  };

  /// Restores a track map stored under [toJson]'s shape. Never throws:
  /// missing or mistyped items fall back item-by-item to their defaults,
  /// unknown keys (a newer app version's items) are ignored.
  static DiaryTrack fromJson(Map<String, Object?> json) => DiaryTrack(
    temperature: _boolOr(json['temperature'], true),
    mucus: _boolOr(json['mucus'], true),
    cervix: _boolOr(json['cervix'], false),
    sex: _boolOr(json['sex'], true),
    pain: _boolOr(json['pain'], true),
  );

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  @override
  bool operator ==(Object other) =>
      other is DiaryTrack &&
      other.temperature == temperature &&
      other.mucus == mucus &&
      other.cervix == cervix &&
      other.sex == sex &&
      other.pain == pain;

  @override
  int get hashCode => Object.hash(temperature, mucus, cervix, sex, pain);
}
