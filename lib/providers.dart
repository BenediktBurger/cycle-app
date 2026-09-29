// Riverpod providers for the app's state: the single open database, live
// entry streams and cross-screen selection state (tab index, locale, the
// date pre-selected in the entry form).
//
// The persisted general settings (locale, theme mode, temperature range,
// the outside-app cycle family, PDF export, onboarding) live in the
// app_settings key-value table of the drift database. The hydration
// registrar in this file is their single wiring point: one declarative
// table of settings entries, driven in both directions — the root widget
// (main.CycleApp) calls [hydratePersistedSettings] in initState to fill
// still-untouched providers from [persistedSettingsProvider]'s snapshot,
// and [registerSettingsWriteThrough] in build to write every provider
// change back to that table. The settings themselves are @riverpod
// Notifier providers in this file; their only sanctioned external write
// is the notifier's `set` member.
//
// The PIN lock stub (Settings screen) is non-functional and local.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderBase/Refreshable (the registrar bind's parameter types) ship from
// the misc entry — the main import doesn't export them.
import 'package:flutter_riverpod/misc.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'db/cycle_database.dart';
import 'db/database_opener.dart';
import 'db/mappers.dart';
import 'db/settings_store.dart';
import 'domain/date_only.dart';
import 'domain/marks.dart';
import 'domain/models.dart';
import 'domain/pdf_export_model.dart';
import 'domain/statistics.dart';
import 'domain/temperature_range.dart';
import 'pdf/cycle_pdf.dart';

part 'providers.g.dart';

/// The one open database for the app lifetime, kept alive for its whole
/// lifetime (no autoDispose). Disposing the ProviderScope closes it. UI
/// screens wait on it via the splash gate in main.dart, so everything
/// downstream can `ref.read(databaseProvider.future)`.
///
/// Opening is async since the native path first resolves the encryption
/// key from the platform's secure storage (and fails loudly if that is
/// impossible — lib/db/db_key.dart); the splash gate surfaces the error.
@Riverpod(keepAlive: true)
Future<CycleDatabase> database(Ref ref) async {
  final db = await openCycleDatabase();
  ref.onDispose(db.close);
  return db;
}

/// The current wall-clock time, injectable: the Tagebuch entry form prefills
/// the time-of-measurement with this value for a fresh day. Widget tests
/// override it with a fixed clock (`() => fixedNow`) so "the form shows the
/// current time" is deterministic (no race against the real minute boundary).
@Riverpod(keepAlive: true)
DateTime Function() now(Ref ref) => DateTime.now;

/// Live stream of the tracked days (as pure domain models) — the single
/// source of truth behind Tagebuch, Zyklus and Statistik screens. Re-emits
/// on every write.
@riverpod
Stream<List<DailyEntry>> dailyEntries(Ref ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.entriesDao.watchAll().map(
    (rows) => rows.map(dailyEntryFromDrift).toList(),
  );
}

/// Live stream of the user-placed marks (as pure domain models) — the read
/// side of the evaluation feature (Mode M, the counterpart to
/// [dailyEntriesProvider]). Re-emits on every mark write (add/remove);
/// consumers recompute the derived evaluation (baseline, circled higher
/// measurements, SUZ) from it at render time — never from a persisted copy,
/// per ADR-0001.
@riverpod
Stream<List<CycleMark>> marks(Ref ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.marksDao.watchAll().map(
    (rows) => rows.map(cycleMarkFromDrift).toList(),
  );
}

/// The one derived grouping+evaluation pass behind the Tagebuch, Zyklus and
/// Statistik screens: each faces its data through the SAME
/// [DerivedCycleData] instance, so a mark write or entry write re-derives it
/// once and the passing tabs (kept mounted in the app shell) read the cached
/// result instead of each re-grouping per build.
///
/// Masked stream reads: a stream still loading (or failed) drains as empty
/// data here — the same shape the screens' own masked reads consume.
/// The marks ERROR itself stays a render concern of the screens — they keep
/// their own unmasked [marksProvider] watches to surface the retry.
///
/// The derivation pins the clock at derivation time (`nowProvider`), so the
/// "today" of the span extension is refreshed on every entries/marks
/// emission; until the next emission the value can lag the wall clock by up
/// to one calendar day — an accepted staleness window, not worth timer
/// machinery.
///
/// KeepAlive on top of the autoDispose streams: the cached derivation lives
/// as long as the process, exactly what "the passing tabs read the cached
/// result" needs.
@Riverpod(keepAlive: true)
DerivedCycleData derivedCycleData(Ref ref) {
  final entries = ref.watch(dailyEntriesProvider).value;
  final marks = ref.watch(marksProvider).value;
  return deriveCycleData(
    entries ?? const <DailyEntry>[],
    marks ?? const <CycleMark>[],
    today: ref.watch(nowProvider)(),
  );
}

/// Tab index of the bottom navigation shell. Screens (e.g. a chart tap on
/// the Zyklus screen) can jump the shell to the Tagebuch tab by writing
/// here.
@Riverpod(keepAlive: true)
class TabIndexNotifier extends _$TabIndexNotifier
    implements SettableSetting<int> {
  @override
  int build() => 0;
  @override
  void set(int value) => state = value;
}

/// Locale of the whole app: `null` (the default) means "follow the system
/// language", a non-null value is an explicit choice from the settings
/// language switcher that wins over the platform.
///
/// With null, [main.CycleApp] leaves `MaterialApp.locale` unset, so
/// Flutter's locale resolution matches the platform language against the
/// supported de/en set and falls back to the first supported locale —
/// English — for any other device language (ADR-0007; the list lives in
/// main.dart and the resolution story in its comment).
///
/// Persisted: an entry in the hydration registrar's table (below) fills
/// this provider from the app_settings snapshot and echoes every change
/// back to the table.
@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier
    implements SettableSetting<Locale?> {
  @override
  Locale? build() => null;
  @override
  void set(Locale? value) => state = value;
}

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier
    implements SettableSetting<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  @override
  void set(ThemeMode value) => state = value;
}

/// The cycle chart's temperature display range ("Temperaturbereich"
/// settings card): the FIXED y bounds the chart's plot and the frozen
/// rail's scale share — settings-selectable, default 36–38 °C. Readings
/// outside the range are not rendered: their dots are skipped and the
/// curve's drawable line pieces clip at the boundary crossings (see
/// lib/ui/cycle_curve.dart); the scale never stretches to fit an outlier.
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
/// The °C unit stays the unit of record —
/// a later Fahrenheit display conversion would happen above this provider.
@Riverpod(keepAlive: true)
class TemperatureRangeNotifier extends _$TemperatureRangeNotifier
    implements SettableSetting<TemperatureRange> {
  @override
  TemperatureRange build() => TemperatureRange.defaults;
  @override
  void set(TemperatureRange value) => state = value;
}

/// The count of cycles the user observed OUTSIDE this app (set in the
/// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
/// the chart's boundary labels AND the evaluation table's column headers —
/// add this count on top of the mark-opened cycles recorded in the
/// database, so numbering continues seamlessly across the migration
/// (lib/domain/cycle_grouping.dart's shared ordinal rule).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
@Riverpod(keepAlive: true)
class ObservedCyclesOutsideAppNotifier
    extends _$ObservedCyclesOutsideAppNotifier
    implements SettableSetting<int> {
  @override
  int build() => 0;
  @override
  void set(int value) => state = value;
}

/// The shortest cycle's LENGTH IN DAYS (>= 1) observed outside this app
/// (the paper-history family next to [observedCyclesOutsideApp]); null
/// means "not given" — the value is optional. Statistics and the PDF
/// export min-combine it with the in-app figures (a paper fact predates
/// every in-app cycle).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
@Riverpod(keepAlive: true)
class ShortestCycleLengthOutsideAppNotifier
    extends _$ShortestCycleLengthOutsideAppNotifier
    implements SettableSetting<int?> {
  @override
  int? build() => null;
  @override
  void set(int? value) => state = value;
}

/// The earliest first higher measurement's CYCLE-DAY NUMBER (>= 1,
/// counting from 1) observed outside this app; null means "not given".
/// Statistics (both documented variants) and the PDF export min-combine
/// it with the in-app figures like
/// [shortestCycleLengthOutsideAppProvider].
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
@Riverpod(keepAlive: true)
class EarliestFirstHigherCycleDayOutsideAppNotifier
    extends _$EarliestFirstHigherCycleDayOutsideAppNotifier
    implements SettableSetting<int?> {
  @override
  int? build() => null;
  @override
  void set(int? value) => state = value;
}

/// Whether the onboarding page has been completed ("Weiter" tapped). The
/// default false shows the shared about-content page full-page once the
/// database is open; the continue action flips it to true, and the shell
/// takes over (main._HomeGate reads this provider).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below): an
/// absent row means not completed, for existing installs too, so the
/// welcome page shows once after the update.
@Riverpod(keepAlive: true)
class OnboardingCompletedNotifier extends _$OnboardingCompletedNotifier
    implements SettableSetting<bool> {
  @override
  bool build() => false;
  @override
  void set(bool value) => state = value;
}

/// The user's NAME for the PDF export header (settings card "PDF-Export");
/// null means "not given". The per-export "anonymize" toggle NEVER writes
/// through this provider — it only changes what the generated document
/// shows. Persisted exactly as [localeProvider] (registrar-table entry
/// below).
@Riverpod(keepAlive: true)
class PdfExportNameNotifier extends _$PdfExportNameNotifier
    implements SettableSetting<String?> {
  @override
  String? build() => null;
  @override
  void set(String? value) => state = value;
}

/// The user's BIRTH DATE for the PDF export header (date-only normalized);
/// null means "not given". Hidden by the per-export anonymize toggle like
/// [pdfExportNameProvider]. Persisted exactly as [localeProvider]
/// (registrar-table entry below).
@Riverpod(keepAlive: true)
class PdfExportBirthDateNotifier extends _$PdfExportBirthDateNotifier
    implements SettableSetting<DateTime?> {
  @override
  DateTime? build() => null;
  @override
  void set(DateTime? value) => state = value;
}

/// The persisted general settings as one snapshot, freshly loaded from the
/// app_settings table the moment the database opens ([databaseProvider]).
/// The hydration registrar's driver ([hydratePersistedSettings], called
/// from main.CycleApp's snapshot listener) applies each snapshot into the
/// providers of the table below — the shared fill rule lives on that
/// table.
/// KeepAlive like [databaseProvider] — the load keeps the database open for
/// the app lifetime.
@Riverpod(keepAlive: true)
Future<PersistedSettings> persistedSettings(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SettingsStore(db.settingsDao).load();
}

/// Write-through seam for the registrar: one call per provider change with
/// a write closure holding that change's typed store upsert. The root
/// widget supplies the sink (its fire-and-forget per-change persistence,
/// silent storage failures) so the error policy stays a root-widget
/// concern and the registrar stays policy-free.
typedef SettingsWriteSink =
    void Function(Future<void> Function(SettingsStore store) write);

/// One table entry of the hydration registrar: a persisted setting bound
/// to its in-memory [ProviderBase], its untouched sentinel and the typed
/// store write. The generic [PersistedSetting.bind] keeps the nine
/// heterogeneous value types out of the drivers — both iterate the plain
/// entries below without knowing `T`.
///
/// The write contract every mutable settings notifier exposes — the
/// sanctioned external write (`ref.read(xProvider.notifier).set(v)`),
/// because riverpod annotates the Notifier `state` setter `@protected`.
/// Implemented by all 14 Notifier classes below; the registrar's
/// [PersistedSetting.bind] is generic over it.
mixin SettableSetting<T> {
  /// The sanctioned external write for the provider this notifier backs.
  void set(T value);
}

final class PersistedSetting {
  const PersistedSetting._(this._applyOnUntouched, this._listenWriteThrough);

  /// Fills the entry's provider from [snapshot] when (and only when) the
  /// provider still holds its untouched sentinel and the snapshot differs
  /// from it.
  final void Function(WidgetRef ref, PersistedSettings snapshot)
  _applyOnUntouched;

  /// Registers one write-through listener for the entry's provider.
  final void Function(WidgetRef ref, SettingsWriteSink sink)
  _listenWriteThrough;

  /// Binds one persisted setting: its provider (plus its notifier
  /// accessor), the untouched sentinel (also the provider's declared
  /// default) and the typed persist helper. The binding captures `T`
  /// inside the two driver-facing closures, so the table itself is
  /// type-safe while the drivers stay generic.
  static PersistedSetting bind<T, N extends SettableSetting<T>>({
    required ProviderBase<T> provider,
    required Refreshable<N> notifier,
    required T untouched,
    required T Function(PersistedSettings snapshot) fromSnapshot,
    required Future<void> Function(SettingsStore store, T value) persist,
  }) {
    return PersistedSetting._(
      (ref, snapshot) {
        final value = fromSnapshot(snapshot);
        if (ref.read(provider) == untouched && value != untouched) {
          ref.read(notifier).set(value);
        }
      },
      (ref, sink) => ref.listen<T>(
        provider,
        (_, value) => sink((store) => persist(store, value)),
      ),
    );
  }
}

/// The hydration registrar's table — EVERY persisted setting as exactly
/// one entry. Adding a persisted setting means adding one entry here:
/// hydration AND write-through follow it.
///
/// The shared fill rule (applied per entry by [hydratePersistedSettings])
/// is fill-if-untouched:
/// - A live choice always wins: a provider whose state still equals its
///   untouched sentinel takes the snapshot value; an already-set provider
///   (user choice, test override) is never clobbered.
/// - A snapshot default equals the sentinel and is skipped as a no-op —
///   for the onboarding flag this is the whole one-way flip: the snapshot
///   value only ever completes the flag, a false/absent row never re-sets
///   a completed one.
/// - A hydration assignment echoes back through the (already or about to
///   be) registered write-through listener as the same-content upsert —
///   storing a hydrated value again is idempotent, so hydrated values
///   need no special-casing there.
final _persistedSettings = <PersistedSetting>[
  PersistedSetting.bind(
    provider: localeProvider,
    notifier: localeProvider.notifier,
    untouched: null,
    fromSnapshot: (snapshot) => snapshot.locale,
    persist: (store, value) => store.persistLocale(value),
  ),
  PersistedSetting.bind(
    provider: themeModeProvider,
    notifier: themeModeProvider.notifier,
    untouched: ThemeMode.system,
    fromSnapshot: (snapshot) => snapshot.themeMode,
    persist: (store, value) => store.persistThemeMode(value),
  ),
  PersistedSetting.bind(
    provider: temperatureRangeProvider,
    notifier: temperatureRangeProvider.notifier,
    untouched: TemperatureRange.defaults,
    fromSnapshot: (snapshot) => snapshot.temperatureRange,
    persist: (store, value) => store.persistTemperatureRange(value),
  ),
  PersistedSetting.bind(
    provider: observedCyclesOutsideAppProvider,
    notifier: observedCyclesOutsideAppProvider.notifier,
    untouched: 0,
    fromSnapshot: (snapshot) => snapshot.observedCyclesOutsideApp,
    persist: (store, value) => store.persistObservedCyclesOutsideApp(value),
  ),
  PersistedSetting.bind(
    provider: shortestCycleLengthOutsideAppProvider,
    notifier: shortestCycleLengthOutsideAppProvider.notifier,
    untouched: null,
    fromSnapshot: (snapshot) => snapshot.shortestCycleLengthOutsideApp,
    persist: (store, value) =>
        store.persistShortestCycleLengthOutsideApp(value),
  ),
  PersistedSetting.bind(
    provider: earliestFirstHigherCycleDayOutsideAppProvider,
    notifier: earliestFirstHigherCycleDayOutsideAppProvider.notifier,
    untouched: null,
    fromSnapshot: (snapshot) => snapshot.earliestFirstHigherCycleDayOutsideApp,
    persist: (store, value) =>
        store.persistEarliestFirstHigherCycleDayOutsideApp(value),
  ),
  PersistedSetting.bind(
    provider: pdfExportNameProvider,
    notifier: pdfExportNameProvider.notifier,
    untouched: null,
    fromSnapshot: (snapshot) => snapshot.pdfExportName,
    persist: (store, value) => store.persistPdfExportName(value),
  ),
  PersistedSetting.bind(
    provider: pdfExportBirthDateProvider,
    notifier: pdfExportBirthDateProvider.notifier,
    untouched: null,
    fromSnapshot: (snapshot) => snapshot.pdfExportBirthDate,
    persist: (store, value) => store.persistPdfExportBirthDate(value),
  ),
  PersistedSetting.bind(
    provider: onboardingCompletedProvider,
    notifier: onboardingCompletedProvider.notifier,
    untouched: false,
    fromSnapshot: (snapshot) => snapshot.onboardingCompleted,
    persist: (store, value) => store.persistOnboardingCompleted(value),
  ),
];

/// The hydration direction: applies the table's fill rule entry by entry
/// into the settings' Notifier providers. Called from main.CycleApp's
/// [persistedSettingsProvider] listener (initState) with each loaded
/// snapshot.
void hydratePersistedSettings(WidgetRef ref, PersistedSettings snapshot) {
  for (final setting in _persistedSettings) {
    setting._applyOnUntouched(ref, snapshot);
  }
}

/// The write-through direction: registers one [WidgetRef.listen] per table
/// entry, feeding each change through [sink]. Must be called synchronously
/// from the root widget's build (Riverpod binds listeners only inside the
/// build frame); a helper invocation is fine.
void registerSettingsWriteThrough(WidgetRef ref, SettingsWriteSink sink) {
  for (final setting in _persistedSettings) {
    setting._listenWriteThrough(ref, sink);
  }
}

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).
@Riverpod(keepAlive: true)
class SelectedDateNotifier extends _$SelectedDateNotifier
    implements SettableSetting<DateTime> {
  @override
  DateTime build() => DateOnly.normalize(DateTime.now());
  @override
  void set(DateTime value) => state = value;
}

/// The calendar day the app was last seen alive-and-in-foreground on: the
/// lifecycle observer in main.CycleApp records it when the app goes deeper
/// away from the foreground (inactive/hidden/paused on the way down — see
/// main.dart's direction-aware lifecycle observer; resume-path intermediates
/// can't clobber the stored day), and on the wake-up it decides between the
/// "morning jump"
/// (the first foreground of a NEW calendar day resets the shell to today's
/// entry form on the diary tab) and a plain resume that keeps everything
/// where the user left off. Null until the first backgrounding — the very
/// first foreground after launch compares against nothing and stays a
/// no-op, because the provider defaults (tab + selected date) already show
/// today's diary form on a fresh start.
///
/// In-memory only ON PURPOSE: it must survive exactly as long as the process
/// does. A killed (cold) start re-derives "today" from
/// [selectedDateProvider]'s default, so persisting or hydrating this value
/// is unnecessary — and would reintroduce exactly the cold-start jump the
/// defaults make impossible.
@Riverpod(keepAlive: true)
class LastForegroundDayNotifier extends _$LastForegroundDayNotifier
    implements SettableSetting<DateTime?> {
  @override
  DateTime? build() => null;
  @override
  void set(DateTime? value) => state = value;
}

/// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
/// AppBar's actions (next to the info action — a row of its own above the
/// chart wasted vertical space), but the jump logic needs the chart's scroll
/// state (the viewport/column geometry, the day mapping and the scroll
/// controller all live on the chart state), so the chart state registers its
/// action here while mounted and clears it again on dispose. Null while no
/// chart is on screen (entries still loading, no data) — the AppBar hides
/// the button then.
@Riverpod(keepAlive: true)
class CycleChartJumpNotifier extends _$CycleChartJumpNotifier
    implements SettableSetting<void Function(BuildContext)?> {
  @override
  void Function(BuildContext context)? build() => null;
  @override
  void set(void Function(BuildContext context)? value) => state = value;
}

/// The day whose options panel is shown on the Zyklus screen (null = no
/// panel). Chart taps (the curve, the marks row, the signal-row cells)
/// write here instead of pushing a modal route, so tapping ANOTHER day
/// retargets the panel in place — the first day's marks are never
/// deselected by a dismissal — and the panel's close button clears it.
/// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
/// every writer is a chart day mapping). In-memory only: the panel is a
/// view-mode, not data.
@Riverpod(keepAlive: true)
class CycleDayPanelNotifier extends _$CycleDayPanelNotifier
    implements SettableSetting<DateTime?> {
  @override
  DateTime? build() => null;
  @override
  void set(DateTime? value) => state = value;
}

/// The PDF export's document factory: turns model + per-export options
/// (+ the bundled font's bytes) into the PDF byte stream. A Provider of a
/// function keeps the export card pure UI — the widget tests override
/// this to stub generation and capture the input (model / options),
/// exactly like the file transfer's pick/save seams for the platform
/// side.
typedef PdfExportDocumentBuilder =
    Future<List<int>> Function(
      PdfExportModel model,
      PdfExportOptions options,
      List<int> fontBytes,
    );

@Riverpod(keepAlive: true)
PdfExportDocumentBuilder pdfDocumentBuilder(Ref ref) {
  return (model, options, fontBytes) {
    return generatePdfBytes(
      model: model,
      fontBytes: fontBytes,
      options: options,
    );
  };
}
