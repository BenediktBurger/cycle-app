// The typed settings layer over the raw key-value DAO (settings_dao.dart):
// named keys, generic JSON encode/decode and typed helpers for the
// persisted general settings (language, theme mode, temperature range, the
// outside-app cycle triple).
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

import '../domain/date_only.dart';
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

  /// The LENGTH IN DAYS of the shortest cycle the user observed OUTSIDE
  /// this app (the paper-history family next to
  /// [observedCyclesOutsideApp] — the three outside-app facts live
  /// together), as a plain JSON integer >= 1. Nothing stored (or a corrupt
  /// row) means "not given" (null) — the value feeds statistics and the
  /// PDF export as an optional constant.
  static const shortestCycleLengthOutsideApp =
      'cyclesOutsideApp.shortestCycleLength';

  /// The CYCLE-DAY NUMBER (counting from 1) of the earliest first higher
  /// measurement the user observed OUTSIDE this app, as a plain JSON
  /// integer >= 1. Nothing stored (or a corrupt row) means "not given"
  /// (null) — the value feeds statistics and the PDF export like
  /// [shortestCycleLengthOutsideApp].
  static const earliestFirstHigherCycleDayOutsideApp =
      'cyclesOutsideApp.earliestFirstHigherCycleDay';

  /// First-start gate of the welcome/about page: the flag is a plain JSON
  /// boolean. NOTHING stored (or a corrupt row) means "not completed", so
  /// the shell shows the onboarding page next start; a stored true keeps
  /// the shell direct. Only true is ever written in practice (the "continue"
  /// action on the onboarding page) — an explicit false row simply reads
  /// like the absence of one.
  static const onboardingCompleted = 'onboardingCompleted';

  /// The user's NAME for the PDF export's paper-form header ("identifying
  /// source" value), as a plain JSON string. A whitespace-only or corrupt
  /// row decodes to null — no name in the document then. The per-export
  /// anonymize toggle hides this value in the generated document without
  /// touching the stored row.
  static const pdfExportName = 'pdfExport.name';

  /// The user's BIRTH DATE for the PDF export's paper-form header, as the
  /// plain ISO date string ('1990-01-02'). A nonexistent day, a non-date
  /// string or a corrupt row decodes to null. Hidden by the per-export
  /// anonymize toggle exactly like [pdfExportName].
  static const pdfExportBirthDate = 'pdfExport.birthDate';
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
    this.shortestCycleLengthOutsideApp,
    this.earliestFirstHigherCycleDayOutsideApp,
    this.onboardingCompleted = false,
    this.pdfExportName,
    this.pdfExportBirthDate,
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

  /// The shortest cycle length (>= 1, in days) observed outside this app,
  /// or null when not given. One recorded paper fact — statistics and the
  /// PDF export min-combine it with the in-app figures.
  final int? shortestCycleLengthOutsideApp;

  /// The earliest first higher measurement's cycle-day number (>= 1,
  /// counting from 1) observed outside this app, or null when not given.
  /// One recorded paper fact — statistics and the PDF export min-combine
  /// it with the in-app figures (both documented variants).
  final int? earliestFirstHigherCycleDayOutsideApp;

  /// Whether the onboarding page has been confirmed ("Weiter" tapped at
  /// least once). The absence of a row — this field's default — is also the
  /// "not answered yet" state.
  final bool onboardingCompleted;

  /// The stored name for the PDF export header (`pdfExport.name` family),
  /// or null when unset/blank. Written through from the settings pane's
  /// PDF-export card; hidden in the generated document by the per-export
  /// anonymize toggle.
  final String? pdfExportName;

  /// The stored birth date for the PDF export header
  /// (`pdfExport.birthDate`), date-only normalized (UTC midnight), or null
  /// when unset. Hidden in the generated document like [pdfExportName].
  final DateTime? pdfExportBirthDate;

  @override
  bool operator ==(Object other) =>
      other is PersistedSettings &&
      other.locale == locale &&
      other.themeMode == themeMode &&
      other.temperatureRange == temperatureRange &&
      other.observedCyclesOutsideApp == observedCyclesOutsideApp &&
      other.shortestCycleLengthOutsideApp == shortestCycleLengthOutsideApp &&
      other.earliestFirstHigherCycleDayOutsideApp ==
          earliestFirstHigherCycleDayOutsideApp &&
      other.onboardingCompleted == onboardingCompleted &&
      other.pdfExportName == pdfExportName &&
      other.pdfExportBirthDate == pdfExportBirthDate;

  @override
  int get hashCode => Object.hash(
    locale,
    themeMode,
    temperatureRange,
    observedCyclesOutsideApp,
    shortestCycleLengthOutsideApp,
    earliestFirstHigherCycleDayOutsideApp,
    onboardingCompleted,
    pdfExportName,
    pdfExportBirthDate,
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
    int? shortestCycleLengthOutsideApp;
    int? earliestFirstHigherCycleDayOutsideApp;
    var onboardingCompleted = false;
    String? pdfExportName;
    DateTime? pdfExportBirthDate;

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
          case SettingKeys.shortestCycleLengthOutsideApp:
            shortestCycleLengthOutsideApp = _paperHistoryIntFromStored(decoded);
          case SettingKeys.earliestFirstHigherCycleDayOutsideApp:
            earliestFirstHigherCycleDayOutsideApp = _paperHistoryIntFromStored(
              decoded,
            );
          case SettingKeys.onboardingCompleted:
            onboardingCompleted = _onboardingFromStored(decoded);
          case SettingKeys.pdfExportName:
            pdfExportName = _pdfExportNameFromStored(decoded);
          case SettingKeys.pdfExportBirthDate:
            pdfExportBirthDate = _pdfExportBirthDateFromStored(decoded);
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
      shortestCycleLengthOutsideApp: shortestCycleLengthOutsideApp,
      earliestFirstHigherCycleDayOutsideApp:
          earliestFirstHigherCycleDayOutsideApp,
      onboardingCompleted: onboardingCompleted,
      pdfExportName: pdfExportName,
      pdfExportBirthDate: pdfExportBirthDate,
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

  /// Persists the paper shortest-cycle value (>= 1, in days):
  /// [writeSetting] writes the plain JSON integer, null deletes the row. A
  /// value < 1 is not a plausible paper fact (the field validates >= 1) and
  /// is treated like null: deleted, so "absent" and "cleared/rejected" read
  /// the same (the persistPdfExportName pattern — both paper-history
  /// helpers share it).
  Future<void> persistShortestCycleLengthOutsideApp(int? value) => writeSetting(
    SettingKeys.shortestCycleLengthOutsideApp,
    (value == null || value < 1) ? null : value,
  );

  /// Persists the paper earliest-first-higher value (>= 1, the cycle-day
  /// number counting from 1) with the same null/< 1 deletes semantics as
  /// [persistShortestCycleLengthOutsideApp].
  Future<void> persistEarliestFirstHigherCycleDayOutsideApp(int? value) =>
      writeSetting(
        SettingKeys.earliestFirstHigherCycleDayOutsideApp,
        (value == null || value < 1) ? null : value,
      );

  /// Persists the onboarding completion flag as a plain JSON boolean. Only
  /// the "continue" action writes true in practice; the absent row is the
  /// "not completed" state, so nothing rewrites it on a plain start.
  Future<void> persistOnboardingCompleted(bool completed) =>
      writeSetting(SettingKeys.onboardingCompleted, completed);

  /// Persists the PDF-export name as a plain JSON string. A null or blank
  /// name deletes the row instead of storing an implicit "no name" —
  /// whitespace is not identity data.
  Future<void> persistPdfExportName(String? name) {
    final value = name?.trim();
    if (value == null || value.isEmpty) {
      return writeSetting(SettingKeys.pdfExportName, null);
    }
    return writeSetting(SettingKeys.pdfExportName, value);
  }

  /// Persists the PDF-export birth date as the plain ISO date string
  /// (yyyy-MM-dd); null deletes the row. The date-only normalization keeps
  /// time-of-day noise out of the document header.
  Future<void> persistPdfExportBirthDate(DateTime? birthDate) => writeSetting(
    SettingKeys.pdfExportBirthDate,
    birthDate == null ? null : formatIsoDate(birthDate),
  );
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

/// Paper-history decode (shortest cycle length AND earliest first higher's
/// cycle day share the validation): JSON integers >= 1 only. Non-integers
/// (strings, doubles, bools, null) and values < 1 decode to null, "not
/// given" — a corrupt or hostile row keeps the optional fact absent, never
/// an error.
int? _paperHistoryIntFromStored(Object? decoded) =>
    decoded is int && decoded >= 1 ? decoded : null;

/// Onboarding-flag decode: explicit JSON true only. Anything else (false,
/// null, strings, numbers) decodes to not-completed — the welcome page then
/// replays at worst, never getting silently skipped.
bool _onboardingFromStored(Object? decoded) => decoded is bool && decoded;

/// PDF-export name decode: a JSON string with actual (non-whitespace)
/// content only. Everything else — numbers, booleans, null, blank strings,
/// corrupt rows — decodes to null, "no name given".
String? _pdfExportNameFromStored(Object? decoded) {
  final value = decoded is String ? decoded.trim() : null;
  return value == null || value.isEmpty ? null : value;
}

DateTime? _pdfExportBirthDateFromStored(Object? decoded) =>
    decoded is String ? tryParseIsoDate(decoded) : null;

/// The ISO date string ('yyyy-MM-dd') of a calendar day — the EXACT shape
/// the birth-date field exchanges and the store's persist helper writes.
/// One definition so the field's echoed initial value and the stored rows
/// use the same form.
String formatIsoDate(DateTime date) =>
    DateOnly.normalize(date).toIso8601String().substring(0, 10);

/// The STRICT ISO date parse ('yyyy-MM-dd' only) behind the birth-date
/// decode AND the settings field's live validation — one definition so the
/// field and the store cannot drift. Returns the UTC-midnight calendar day
/// (DateOnly convention) or null: a non-string-shape day, a wrong shape,
/// a wrong form (Dart's lenient parser otherwise rolls impossible days
/// over, e.g. '1990-02-30' → 1990-03-02) all decode to null.
DateTime? tryParseIsoDate(String raw) {
  if (raw.length != 10 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final normalized = DateOnly.normalize(parsed);
  final iso = normalized.toIso8601String().substring(0, 10);
  return iso == raw ? normalized : null;
}
