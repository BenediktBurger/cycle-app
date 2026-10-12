/// Which diary entry items the user tracks, and whether each one's entry
/// options appear on the Tagebuch form at all ("Was aufzeichnen" settings
/// card). Hiding is view-only: the form still loads and saves a stored
/// day's values for a hidden item (lib/ui/diary.dart).
///
/// One value for the whole family, one JSON map under one settings key:
/// a later item (e.g. pain) joins by adding one enum value, one field and
/// one decoder default here. A stored map missing a later-added key
/// decodes to the new item's default; unknown item keys are ignored.
enum DiaryItem { mucus, cervix, sex }

final class DiaryTrack {
  const DiaryTrack({this.mucus = true, this.cervix = false, this.sex = true});

  static const DiaryTrack defaults = DiaryTrack();

  final bool mucus;
  final bool cervix;
  final bool sex;

  bool isTracked(DiaryItem item) => switch (item) {
    DiaryItem.mucus => mucus,
    DiaryItem.cervix => cervix,
    DiaryItem.sex => sex,
  };

  /// A copy with exactly one item's tracking flipped — the write the
  /// settings card's switches issue.
  DiaryTrack withTracked(DiaryItem item, bool tracked) => switch (item) {
    DiaryItem.mucus => DiaryTrack(mucus: tracked, cervix: cervix, sex: sex),
    DiaryItem.cervix => DiaryTrack(mucus: mucus, cervix: tracked, sex: sex),
    DiaryItem.sex => DiaryTrack(mucus: mucus, cervix: cervix, sex: tracked),
  };

  /// JSON-map form for the generic settings store (the exact shape the
  /// app_settings column holds).
  Map<String, Object?> toJson() => {
    'mucus': mucus,
    'cervix': cervix,
    'sex': sex,
  };

  /// Restores a track map stored under [toJson]'s shape. Never throws:
  /// missing or mistyped items fall back item-by-item to their defaults,
  /// unknown keys (a newer app version's items) are ignored.
  static DiaryTrack fromJson(Map<String, Object?> json) => DiaryTrack(
    mucus: _boolOr(json['mucus'], true),
    cervix: _boolOr(json['cervix'], false),
    sex: _boolOr(json['sex'], true),
  );

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  @override
  bool operator ==(Object other) =>
      other is DiaryTrack &&
      other.mucus == mucus &&
      other.cervix == cervix &&
      other.sex == sex;

  @override
  int get hashCode => Object.hash(mucus, cervix, sex);
}
