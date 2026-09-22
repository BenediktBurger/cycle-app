// The typed settings layer over the raw key-value DAO (settings_dao.dart):
// named keys, generic JSON encode/decode and typed helpers for the
// persisted general settings (language, theme mode, temperature range,
// outside-app cycle count).
//
// Adding a future setting (e.g. a PDF export option) is deliberately boring:
// a new constant in [SettingKeys] plus one typed helper — no schema change,
// no migration, the table shape is final. Everything a JSON-native value
// needs is already there ([SettingsStore.writeSetting]/[readSetting]).
//
// This file touches dart:ui (Locale, ThemeMode) and therefore stays OUT of
// the pure-Dart cycle_database.dart library the host smoke scripts import:
// it imports that library like any other consumer, without polluting it.
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;

import '../domain/temperature_range.dart';
import 'cycle_database.dart';

/// The names of every persisted general setting.
///
/// Values live as (key, JSON-encoded value) rows in the app_settings table —
/// a key is storage vocabulary, not schema. Dot-namespacing is free-form by
/// convention for grouping future families ('pdfExport.anonymize', …).
abstract final class SettingKeys {
  /// The app's explicit language as a language code string ('de', 'en');
  /// nothing stored means "follow the system language" (the null default of
  /// the app's locale provider).
  static const locale = 'locale';

  /// The app theme as the [ThemeMode] enum name ('system', 'light', 'dark').
  static const themeMode = 'themeMode';

  /// The temperature display range as a {"min":..,"max":..} JSON map
  /// (TemperatureRange.toJson).
  static const temperatureRange = 'temperatureRange';

  /// The count of cycles the user observed OUTSIDE this app (e.g. on paper
  /// or in a previous tracker), as a plain JSON integer >= 0. Nothing stored
  /// (or a corrupt row) means 0 — the cycle ordinals on the cycle page then
  /// count only the mark-opened cycles recorded in this database.
  static const observedCyclesOutsideApp = 'observedCyclesOutsideApp';

  /// First-start gate of the welcome/about page: the flag is a plain JSON
  /// boolean. NOTHING stored (or a corrupt row) means "not completed", so
  /// the shell shows the onboarding page next start; a stored true keeps the
  /// shell direct. Only true is ever written in practice (the "continue"
  /// action on the onboarding page) — an explicit false row simply reads
  /// like the absence of one.
  static const onboardingCompleted = 'onboardingCompleted';
}

/// One joined snapshot of all persisted general settings, as
/// [SettingsStore.load] reports them: every field is a DECODED, typed value —
/// corrupt rows already collapsed into their defaults before this object
/// exists. Missing rows and explicit defaults read identically.
final class PersistedSettings {
  const PersistedSettings({
    this.locale,
    this.themeMode = ThemeMode.system,
    this.temperatureRange = TemperatureRange.defaults,
    this.observedCyclesOutsideApp = 0,
    this.onboardingCompleted = false,
  });

  /// The all-defaults snapshot (what an empty table loads to).
  const PersistedSettings.defaults() : this();

  /// The stored explicit language, or null for "follow the system".
  final Locale? locale;

  /// The stored theme mode.
  final ThemeMode themeMode;

  /// The stored temperature display range.
  final TemperatureRange temperatureRange;

  /// The stored count of cycles observed outside this app (>= 0).
  final int observedCyclesOutsideApp;

  /// Whether the onboarding page has been confirmed ("Weiter" tapped at
  /// least once). The absence of a row — this field's default — is also the
  /// "not answered yet" state.
  final bool onboardingCompleted;

  @override
  bool operator ==(Object other) =>
      other is PersistedSettings &&
      other.locale == locale &&
      other.themeMode == themeMode &&
      other.temperatureRange == temperatureRange &&
      other.observedCyclesOutsideApp == observedCyclesOutsideApp &&
      other.onboardingCompleted == onboardingCompleted;

  @override
  int get hashCode => Object.hash(
    locale,
    themeMode,
    temperatureRange,
    observedCyclesOutsideApp,
    onboardingCompleted,
  );
}

/// Stateless typed wrapper over one database's [SettingsDao]. Cheap enough
/// to build per call site; all methods go through the DAO's upsert/delete.
final class SettingsStore {
  SettingsStore(this._dao);

  final SettingsDao _dao;

  /// Loads ALL persisted settings as one snapshot: every stored row in ONE
  /// query, each known key decoded through its typed helper. Unknown keys
  /// are ignored (forward compatibility — old rows never break new code).
  /// A row whose value fails to decode into the typed setting (broken JSON,
  /// wrong shape, unknown token) falls back to that setting's default; the
  /// other rows are unaffected.
  Future<PersistedSettings> load() async {
    final rows = await _dao.readAll();

    Locale? locale;
    var themeMode = ThemeMode.system;
    var temperatureRange = TemperatureRange.defaults;
    var observedCyclesOutsideApp = 0;
    var onboardingCompleted = false;

    for (final row in rows) {
      // Per row: a single corrupt value must degrade only its own key.
      try {
        final Object? decoded = jsonDecode(row.value);
        switch (row.key) {
          case SettingKeys.locale:
            locale = _localeFromStored(decoded);
          case SettingKeys.themeMode:
            themeMode = _themeModeFromStored(decoded);
          case SettingKeys.temperatureRange:
            if (decoded is Map<String, Object?>) {
              // fromJson rejects mistyped/unordered/out-of-window bounds;
              // that rejection keeps the default below.
              temperatureRange = TemperatureRange.fromJson(decoded);
            }
          case SettingKeys.observedCyclesOutsideApp:
            observedCyclesOutsideApp = _observedCyclesFromStored(decoded);
          case SettingKeys.onboardingCompleted:
            onboardingCompleted = _onboardingFromStored(decoded);
        }
      } catch (_) {
        // Not JSON / unrepresentable for this key: its default stands.
      }
    }

    return PersistedSettings(
      locale: locale,
      themeMode: themeMode,
      temperatureRange: temperatureRange,
      observedCyclesOutsideApp: observedCyclesOutsideApp,
      onboardingCompleted: onboardingCompleted,
    );
  }

  /// The JSON-decoded value stored under [key], or null when the key is
  /// absent/deleted. Unlike [load], a corrupt value here surfaces the
  /// decode error — the generic path serves code that defines the shape it
  /// writes itself.
  Future<Object?> readSetting(String key) async {
    final raw = await _dao.readValue(key);
    return raw == null ? null : jsonDecode(raw);
  }

  /// Generic JSON write for ANY future setting (proof of the schema-free
  /// table): [value] is JSON-encoded into the existing value column.
  /// `null` deletes the row — "absent" and "cleared" read the same later.
  /// The [key]-nonempty check lives in the DAO.
  Future<void> writeSetting(String key, Object? value) async {
    if (value == null) {
      await _dao.deleteValue(key);
    } else {
      await _dao.writeValue(key, jsonEncode(value));
    }
  }

  /// Persists the explicit language choice; `null` (system default) deletes
  /// the row instead of storing an explicit "system" token. Only the
  /// language code survives: the app's choices are language-only locales.
  Future<void> persistLocale(Locale? locale) =>
      writeSetting(SettingKeys.locale, locale?.languageCode);

  /// Persists the theme mode under its enum-name token, system included
  /// (an explicit default row is fine — it reads back as the default).
  Future<void> persistThemeMode(ThemeMode mode) =>
      writeSetting(SettingKeys.themeMode, mode.name);

  /// Persists the temperature display range as its JSON map. A wrongly
  /// ordered range is rejected with [ArgumentError] even in release builds
  /// (where the domain constructor's assert compiles away) — the store
  /// carries the same min < max invariant as [TemperatureRange] does.
  Future<void> persistTemperatureRange(TemperatureRange range) {
    if (range.min >= range.max) {
      throw ArgumentError.value(range, 'range', 'needs min < max');
    }
    return writeSetting(SettingKeys.temperatureRange, range.toJson());
  }

  /// Persists the count of cycles observed outside this app as a plain JSON
  /// integer; an explicit 0 row is kept (an absent row and a 0 row read the
  /// same, but the user's deliberate zeroing survives as a row). Negative
  /// counts are rejected with [ArgumentError] — the settings field lets no
  /// such value through, and the in-memory provider clamps anyway.
  Future<void> persistObservedCyclesOutsideApp(int cycles) {
    if (cycles < 0) {
      throw ArgumentError.value(cycles, 'cycles', 'must be >= 0');
    }
    return writeSetting(SettingKeys.observedCyclesOutsideApp, cycles);
  }

  /// Persists the onboarding completion flag as a plain JSON boolean. Only
  /// the "continue" action writes true in practice; the absent row is the
  /// "not completed" state, so nothing rewrites it on a plain start.
  Future<void> persistOnboardingCompleted(bool completed) =>
      writeSetting(SettingKeys.onboardingCompleted, completed);
}

/// Locale decode: any non-empty language code is accepted verbatim (a code
/// outside {de, en} is kept — locale RESOLUTION falls back later per
/// ADR-0007). Anything else (null, numbers, lists, empty strings) decodes to
/// null, the system default.
Locale? _localeFromStored(Object? decoded) =>
    decoded is String && decoded.isNotEmpty ? Locale(decoded) : null;

/// ThemeMode decode: enum-name tokens only. Unknown tokens and non-strings
/// decode to the system default, never to an error.
ThemeMode _themeModeFromStored(Object? decoded) {
  if (decoded is String) {
    return ThemeMode.values.asNameMap()[decoded] ?? ThemeMode.system;
  }
  return ThemeMode.system;
}

/// Observed-cycles decode: non-negative integers only. Non-integers
/// (strings, doubles, bools, null) and negative values decode to 0 — a
/// corrupt or hostile row keeps the default, never an error.
int _observedCyclesFromStored(Object? decoded) =>
    decoded is int && decoded >= 0 ? decoded : 0;

/// Onboarding-flag decode: explicit JSON true only. Anything else (false,
/// null, strings, numbers) decodes to not-completed — the welcome page then
/// replays at worst, never getting silently skipped.
bool _onboardingFromStored(Object? decoded) => decoded is bool && decoded;
