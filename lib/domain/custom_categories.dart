/// One user-defined diary category ("eigene Kategorie") and its entry
/// labels, as configured in the settings and stored under the
/// `customDiaryCategories` app_settings key. A definition is display
/// vocabulary only — the stored days reference category/entry names
/// verbatim (label-keyed), so renaming or deleting a definition never
/// rewrites history.
///
/// The label caps below are UI write-time guards only: the JSON decoders
/// stay lenient and do NOT enforce them, so older or hand-edited rows keep
/// rendering.
const customLabelMaxLength = 40;
const maxCustomCategories = 10;
const maxCustomCategoryEntries = 15;

/// The entry labels inside one mark's "Kategorie: A, B" listing.
const customMarkItemsSeparator = ', ';

/// The separator joining two mark listings — and, on the full-text screen
/// surfaces, the marks text and the free note.
const customMarkCategoriesSeparator = ' · ';

/// One stored day's custom marks as the compact display line ALL render
/// surfaces share (they cannot drift): one "Kategorie: A, B" listing per
/// stored category — an entry-less category renders its bare name — in
/// the stored map's insertion order. Null when the map is empty or
/// missing: nothing to render.
String? customMarksNote(Map<String, List<String>>? customMarks) {
  if (customMarks == null || customMarks.isEmpty) return null;
  return [
    for (final MapEntry(key: category, value: items) in customMarks.entries)
      items.isEmpty
          ? category
          : '$category: ${items.join(customMarkItemsSeparator)}',
  ].join(customMarkCategoriesSeparator);
}

/// The map members of a JSON-decoded settings value, in stored order.
List<Map<String, Object?>> customCategoryRowsFromStored(Object? decoded) {
  if (decoded is! List) return const [];
  return [
    for (final member in decoded)
      if (member is Map<String, Object?>) member,
  ];
}

final class CustomCategory {
  const CustomCategory({
    required this.name,
    this.visible = true,
    this.items = const [],
  });

  final String name;
  final bool visible;

  /// The entry labels offered as ticks for this category, in display order.
  final List<String> items;

  /// JSON-map form for the generic settings store (the exact shape the
  /// app_settings column holds).
  Map<String, Object?> toJson() => {
    'name': name,
    'visible': visible,
    'items': List<String>.of(items),
  };

  /// Restores a category stored under [toJson]'s shape. Never throws:
  /// missing or mistyped fields fall back per field (an empty name, the
  /// default visibility, no items), non-string entry labels are dropped,
  /// unknown future keys are ignored.
  static CustomCategory fromJson(Map<String, Object?> json) => CustomCategory(
    name: _stringOr(json['name'], ''),
    visible: _boolOr(json['visible'], true),
    items: [
      if (json['items'] is List)
        for (final item in json['items'] as List)
          if (item is String) item,
    ],
  );

  static String _stringOr(Object? value, String fallback) =>
      value is String ? value : fallback;

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  @override
  bool operator ==(Object other) =>
      other is CustomCategory &&
      other.name == name &&
      other.visible == visible &&
      _itemsEqual(other.items, items);

  @override
  int get hashCode => Object.hash(name, visible, Object.hashAll(items));

  static bool _itemsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

bool sameCustomCategories(List<CustomCategory> a, List<CustomCategory> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
