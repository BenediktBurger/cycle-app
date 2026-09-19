// SettingsDao: raw key-value access to the app_settings table.
// Part of the cycle_database.dart library — see its header.
//
// STORAGE ONLY: this DAO knows nothing about JSON encoding, defaults or key
// namespacing — the typed layer on top (lib/db/settings_store.dart, keys,
// codecs, snapshot loading) is the only intended consumer. Values are opaque
// texts here.

part of 'cycle_database.dart';

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<CycleDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// Every stored row, read in ONE query — the snapshot primitive behind
  /// the typed store's full-table load (no per-key round trips).
  Future<List<AppSetting>> readAll() => select(appSettings).get();

  /// The stored value for [key], or null when the key was never written
  /// (or was deleted). Deleting is the same as "no value stored".
  Future<String?> readValue(String key) async {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Upsert: writes [value] for [key], replacing any previous value — one
  /// row per key, ever.
  Future<void> writeValue(String key, String value) async {
    if (key.isEmpty) {
      // Every DAO method rejects an empty key with ArgumentError; thrown
      // inside these async bodies, the rejection is delivered through the
      // returned future — uniformly in all three.
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  /// Removes the row for [key] (absent keys are a no-op).
  Future<void> deleteValue(String key) async {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    await (delete(appSettings)..where((t) => t.key.equals(key))).go();
  }
}
