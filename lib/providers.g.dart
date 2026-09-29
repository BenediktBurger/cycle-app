// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The one open database for the app lifetime, kept alive for its whole
/// lifetime (no autoDispose). Disposing the ProviderScope closes it. UI
/// screens wait on it via the splash gate in main.dart, so everything
/// downstream can `ref.read(databaseProvider.future)`.
///
/// Opening is async since the native path first resolves the encryption
/// key from the platform's secure storage (and fails loudly if that is
/// impossible — lib/db/db_key.dart); the splash gate surfaces the error.

@ProviderFor(database)
final databaseProvider = DatabaseProvider._();

/// The one open database for the app lifetime, kept alive for its whole
/// lifetime (no autoDispose). Disposing the ProviderScope closes it. UI
/// screens wait on it via the splash gate in main.dart, so everything
/// downstream can `ref.read(databaseProvider.future)`.
///
/// Opening is async since the native path first resolves the encryption
/// key from the platform's secure storage (and fails loudly if that is
/// impossible — lib/db/db_key.dart); the splash gate surfaces the error.

final class DatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<CycleDatabase>,
          CycleDatabase,
          FutureOr<CycleDatabase>
        >
    with $FutureModifier<CycleDatabase>, $FutureProvider<CycleDatabase> {
  /// The one open database for the app lifetime, kept alive for its whole
  /// lifetime (no autoDispose). Disposing the ProviderScope closes it. UI
  /// screens wait on it via the splash gate in main.dart, so everything
  /// downstream can `ref.read(databaseProvider.future)`.
  ///
  /// Opening is async since the native path first resolves the encryption
  /// key from the platform's secure storage (and fails loudly if that is
  /// impossible — lib/db/db_key.dart); the splash gate surfaces the error.
  DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $FutureProviderElement<CycleDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CycleDatabase> create(Ref ref) {
    return database(ref);
  }
}

String _$databaseHash() => r'060c027a48143127107e170943d3f59e079e8853';

/// The current wall-clock time, injectable: the Tagebuch entry form prefills
/// the time-of-measurement with this value for a fresh day. Widget tests
/// override it with a fixed clock (`() => fixedNow`) so "the form shows the
/// current time" is deterministic (no race against the real minute boundary).

@ProviderFor(now)
final nowProvider = NowProvider._();

/// The current wall-clock time, injectable: the Tagebuch entry form prefills
/// the time-of-measurement with this value for a fresh day. Widget tests
/// override it with a fixed clock (`() => fixedNow`) so "the form shows the
/// current time" is deterministic (no race against the real minute boundary).

final class NowProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The current wall-clock time, injectable: the Tagebuch entry form prefills
  /// the time-of-measurement with this value for a fresh day. Widget tests
  /// override it with a fixed clock (`() => fixedNow`) so "the form shows the
  /// current time" is deterministic (no race against the real minute boundary).
  NowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nowProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nowHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return now(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$nowHash() => r'a18fd0a1c525818279254bbe775974fc6f13cf60';

/// Live stream of the tracked days (as pure domain models) — the single
/// source of truth behind Tagebuch, Zyklus and Statistik screens. Re-emits
/// on every write.

@ProviderFor(dailyEntries)
final dailyEntriesProvider = DailyEntriesProvider._();

/// Live stream of the tracked days (as pure domain models) — the single
/// source of truth behind Tagebuch, Zyklus and Statistik screens. Re-emits
/// on every write.

final class DailyEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DailyEntry>>,
          List<DailyEntry>,
          Stream<List<DailyEntry>>
        >
    with $FutureModifier<List<DailyEntry>>, $StreamProvider<List<DailyEntry>> {
  /// Live stream of the tracked days (as pure domain models) — the single
  /// source of truth behind Tagebuch, Zyklus and Statistik screens. Re-emits
  /// on every write.
  DailyEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dailyEntriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dailyEntriesHash();

  @$internal
  @override
  $StreamProviderElement<List<DailyEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DailyEntry>> create(Ref ref) {
    return dailyEntries(ref);
  }
}

String _$dailyEntriesHash() => r'2a04be3ebc3e8f0cbed01df2f828cbeb4945e58f';

/// Live stream of the user-placed marks (as pure domain models) — the read
/// side of the evaluation feature (Mode M, the counterpart to
/// [dailyEntriesProvider]). Re-emits on every mark write (add/remove);
/// consumers recompute the derived evaluation (baseline, circled higher
/// measurements, SUZ) from it at render time — never from a persisted copy,
/// per ADR-0001.

@ProviderFor(marks)
final marksProvider = MarksProvider._();

/// Live stream of the user-placed marks (as pure domain models) — the read
/// side of the evaluation feature (Mode M, the counterpart to
/// [dailyEntriesProvider]). Re-emits on every mark write (add/remove);
/// consumers recompute the derived evaluation (baseline, circled higher
/// measurements, SUZ) from it at render time — never from a persisted copy,
/// per ADR-0001.

final class MarksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CycleMark>>,
          List<CycleMark>,
          Stream<List<CycleMark>>
        >
    with $FutureModifier<List<CycleMark>>, $StreamProvider<List<CycleMark>> {
  /// Live stream of the user-placed marks (as pure domain models) — the read
  /// side of the evaluation feature (Mode M, the counterpart to
  /// [dailyEntriesProvider]). Re-emits on every mark write (add/remove);
  /// consumers recompute the derived evaluation (baseline, circled higher
  /// measurements, SUZ) from it at render time — never from a persisted copy,
  /// per ADR-0001.
  MarksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'marksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$marksHash();

  @$internal
  @override
  $StreamProviderElement<List<CycleMark>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CycleMark>> create(Ref ref) {
    return marks(ref);
  }
}

String _$marksHash() => r'5caa831b4920c0bd557c09b53a1df1d3f4295ff1';

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

@ProviderFor(derivedCycleData)
final derivedCycleDataProvider = DerivedCycleDataProvider._();

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

final class DerivedCycleDataProvider
    extends
        $FunctionalProvider<
          DerivedCycleData,
          DerivedCycleData,
          DerivedCycleData
        >
    with $Provider<DerivedCycleData> {
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
  DerivedCycleDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'derivedCycleDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$derivedCycleDataHash();

  @$internal
  @override
  $ProviderElement<DerivedCycleData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DerivedCycleData create(Ref ref) {
    return derivedCycleData(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DerivedCycleData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DerivedCycleData>(value),
    );
  }
}

String _$derivedCycleDataHash() => r'3fb6504c68719d99acf7e8a8d04268867f04a0b7';

/// Tab index of the bottom navigation shell. Screens (e.g. a chart tap on
/// the Zyklus screen) can jump the shell to the Tagebuch tab by writing
/// here.

@ProviderFor(TabIndexNotifier)
final tabIndexProvider = TabIndexNotifierProvider._();

/// Tab index of the bottom navigation shell. Screens (e.g. a chart tap on
/// the Zyklus screen) can jump the shell to the Tagebuch tab by writing
/// here.
final class TabIndexNotifierProvider
    extends $NotifierProvider<TabIndexNotifier, int> {
  /// Tab index of the bottom navigation shell. Screens (e.g. a chart tap on
  /// the Zyklus screen) can jump the shell to the Tagebuch tab by writing
  /// here.
  TabIndexNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tabIndexProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tabIndexNotifierHash();

  @$internal
  @override
  TabIndexNotifier create() => TabIndexNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$tabIndexNotifierHash() => r'd1162d68a68844337d8ee125993f984e46501077';

/// Tab index of the bottom navigation shell. Screens (e.g. a chart tap on
/// the Zyklus screen) can jump the shell to the Tagebuch tab by writing
/// here.

abstract class _$TabIndexNotifier extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
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

@ProviderFor(LocaleNotifier)
final localeProvider = LocaleNotifierProvider._();

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
final class LocaleNotifierProvider
    extends $NotifierProvider<LocaleNotifier, Locale?> {
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
  LocaleNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localeNotifierHash();

  @$internal
  @override
  LocaleNotifier create() => LocaleNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Locale? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Locale?>(value),
    );
  }
}

String _$localeNotifierHash() => r'fe6084f2f6d91db3c29d592c995c79946e62d005';

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

abstract class _$LocaleNotifier extends $Notifier<Locale?> {
  Locale? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Locale?, Locale?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Locale?, Locale?>,
              Locale?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

@ProviderFor(ThemeModeNotifier)
final themeModeProvider = ThemeModeNotifierProvider._();

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
final class ThemeModeNotifierProvider
    extends $NotifierProvider<ThemeModeNotifier, ThemeMode> {
  /// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
  /// device brightness setting, an explicit light/dark choice from the settings
  /// switcher wins over the platform. The light/dark `ThemeData`s themselves
  /// live in `main.CycleApp` (both derived from one seed color).
  ///
  /// Persisted exactly as [localeProvider] (registrar-table entry below).
  ThemeModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeNotifierHash();

  @$internal
  @override
  ThemeModeNotifier create() => ThemeModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeNotifierHash() => r'dcef87d43497ac11ec2f47751066d63f48d64b9e';

/// Theme mode of the whole app: `ThemeMode.system` (the default) follows the
/// device brightness setting, an explicit light/dark choice from the settings
/// switcher wins over the platform. The light/dark `ThemeData`s themselves
/// live in `main.CycleApp` (both derived from one seed color).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

abstract class _$ThemeModeNotifier extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
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

@ProviderFor(TemperatureRangeNotifier)
final temperatureRangeProvider = TemperatureRangeNotifierProvider._();

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
final class TemperatureRangeNotifierProvider
    extends $NotifierProvider<TemperatureRangeNotifier, TemperatureRange> {
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
  TemperatureRangeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'temperatureRangeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$temperatureRangeNotifierHash();

  @$internal
  @override
  TemperatureRangeNotifier create() => TemperatureRangeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TemperatureRange value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TemperatureRange>(value),
    );
  }
}

String _$temperatureRangeNotifierHash() =>
    r'dd8f555f05696e85b9216726184a4be5add95faa';

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

abstract class _$TemperatureRangeNotifier extends $Notifier<TemperatureRange> {
  TemperatureRange build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TemperatureRange, TemperatureRange>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TemperatureRange, TemperatureRange>,
              TemperatureRange,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The count of cycles the user observed OUTSIDE this app (set in the
/// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
/// the chart's boundary labels AND the evaluation table's column headers —
/// add this count on top of the mark-opened cycles recorded in the
/// database, so numbering continues seamlessly across the migration
/// (lib/domain/cycle_grouping.dart's shared ordinal rule).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

@ProviderFor(ObservedCyclesOutsideAppNotifier)
final observedCyclesOutsideAppProvider =
    ObservedCyclesOutsideAppNotifierProvider._();

/// The count of cycles the user observed OUTSIDE this app (set in the
/// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
/// the chart's boundary labels AND the evaluation table's column headers —
/// add this count on top of the mark-opened cycles recorded in the
/// database, so numbering continues seamlessly across the migration
/// (lib/domain/cycle_grouping.dart's shared ordinal rule).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
final class ObservedCyclesOutsideAppNotifierProvider
    extends $NotifierProvider<ObservedCyclesOutsideAppNotifier, int> {
  /// The count of cycles the user observed OUTSIDE this app (set in the
  /// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
  /// the chart's boundary labels AND the evaluation table's column headers —
  /// add this count on top of the mark-opened cycles recorded in the
  /// database, so numbering continues seamlessly across the migration
  /// (lib/domain/cycle_grouping.dart's shared ordinal rule).
  ///
  /// Persisted exactly as [localeProvider] (registrar-table entry below).
  ObservedCyclesOutsideAppNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'observedCyclesOutsideAppProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$observedCyclesOutsideAppNotifierHash();

  @$internal
  @override
  ObservedCyclesOutsideAppNotifier create() =>
      ObservedCyclesOutsideAppNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$observedCyclesOutsideAppNotifierHash() =>
    r'f38373543f42d23f20fec525cb13aa37b0e060da';

/// The count of cycles the user observed OUTSIDE this app (set in the
/// settings pane's integer field). The cycle page's "Zyklus N" ordinals —
/// the chart's boundary labels AND the evaluation table's column headers —
/// add this count on top of the mark-opened cycles recorded in the
/// database, so numbering continues seamlessly across the migration
/// (lib/domain/cycle_grouping.dart's shared ordinal rule).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

abstract class _$ObservedCyclesOutsideAppNotifier extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The shortest cycle's LENGTH IN DAYS (>= 1) observed outside this app
/// (the paper-history family next to [observedCyclesOutsideApp]); null
/// means "not given" — the value is optional. Statistics and the PDF
/// export min-combine it with the in-app figures (a paper fact predates
/// every in-app cycle).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

@ProviderFor(ShortestCycleLengthOutsideAppNotifier)
final shortestCycleLengthOutsideAppProvider =
    ShortestCycleLengthOutsideAppNotifierProvider._();

/// The shortest cycle's LENGTH IN DAYS (>= 1) observed outside this app
/// (the paper-history family next to [observedCyclesOutsideApp]); null
/// means "not given" — the value is optional. Statistics and the PDF
/// export min-combine it with the in-app figures (a paper fact predates
/// every in-app cycle).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
final class ShortestCycleLengthOutsideAppNotifierProvider
    extends $NotifierProvider<ShortestCycleLengthOutsideAppNotifier, int?> {
  /// The shortest cycle's LENGTH IN DAYS (>= 1) observed outside this app
  /// (the paper-history family next to [observedCyclesOutsideApp]); null
  /// means "not given" — the value is optional. Statistics and the PDF
  /// export min-combine it with the in-app figures (a paper fact predates
  /// every in-app cycle).
  ///
  /// Persisted exactly as [localeProvider] (registrar-table entry below).
  ShortestCycleLengthOutsideAppNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shortestCycleLengthOutsideAppProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$shortestCycleLengthOutsideAppNotifierHash();

  @$internal
  @override
  ShortestCycleLengthOutsideAppNotifier create() =>
      ShortestCycleLengthOutsideAppNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$shortestCycleLengthOutsideAppNotifierHash() =>
    r'd12a3207ac306a68a3c5ffab771c633d4795f731';

/// The shortest cycle's LENGTH IN DAYS (>= 1) observed outside this app
/// (the paper-history family next to [observedCyclesOutsideApp]); null
/// means "not given" — the value is optional. Statistics and the PDF
/// export min-combine it with the in-app figures (a paper fact predates
/// every in-app cycle).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

abstract class _$ShortestCycleLengthOutsideAppNotifier extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The earliest first higher measurement's CYCLE-DAY NUMBER (>= 1,
/// counting from 1) observed outside this app; null means "not given".
/// Statistics (both documented variants) and the PDF export min-combine
/// it with the in-app figures like
/// [shortestCycleLengthOutsideAppProvider].
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

@ProviderFor(EarliestFirstHigherCycleDayOutsideAppNotifier)
final earliestFirstHigherCycleDayOutsideAppProvider =
    EarliestFirstHigherCycleDayOutsideAppNotifierProvider._();

/// The earliest first higher measurement's CYCLE-DAY NUMBER (>= 1,
/// counting from 1) observed outside this app; null means "not given".
/// Statistics (both documented variants) and the PDF export min-combine
/// it with the in-app figures like
/// [shortestCycleLengthOutsideAppProvider].
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).
final class EarliestFirstHigherCycleDayOutsideAppNotifierProvider
    extends
        $NotifierProvider<EarliestFirstHigherCycleDayOutsideAppNotifier, int?> {
  /// The earliest first higher measurement's CYCLE-DAY NUMBER (>= 1,
  /// counting from 1) observed outside this app; null means "not given".
  /// Statistics (both documented variants) and the PDF export min-combine
  /// it with the in-app figures like
  /// [shortestCycleLengthOutsideAppProvider].
  ///
  /// Persisted exactly as [localeProvider] (registrar-table entry below).
  EarliestFirstHigherCycleDayOutsideAppNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'earliestFirstHigherCycleDayOutsideAppProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$earliestFirstHigherCycleDayOutsideAppNotifierHash();

  @$internal
  @override
  EarliestFirstHigherCycleDayOutsideAppNotifier create() =>
      EarliestFirstHigherCycleDayOutsideAppNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$earliestFirstHigherCycleDayOutsideAppNotifierHash() =>
    r'af2b41142f5e8ec46b226921279d4492fb04d593';

/// The earliest first higher measurement's CYCLE-DAY NUMBER (>= 1,
/// counting from 1) observed outside this app; null means "not given".
/// Statistics (both documented variants) and the PDF export min-combine
/// it with the in-app figures like
/// [shortestCycleLengthOutsideAppProvider].
///
/// Persisted exactly as [localeProvider] (registrar-table entry below).

abstract class _$EarliestFirstHigherCycleDayOutsideAppNotifier
    extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the onboarding page has been completed ("Weiter" tapped). The
/// default false shows the shared about-content page full-page once the
/// database is open; the continue action flips it to true, and the shell
/// takes over (main._HomeGate reads this provider).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below): an
/// absent row means not completed, for existing installs too, so the
/// welcome page shows once after the update.

@ProviderFor(OnboardingCompletedNotifier)
final onboardingCompletedProvider = OnboardingCompletedNotifierProvider._();

/// Whether the onboarding page has been completed ("Weiter" tapped). The
/// default false shows the shared about-content page full-page once the
/// database is open; the continue action flips it to true, and the shell
/// takes over (main._HomeGate reads this provider).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below): an
/// absent row means not completed, for existing installs too, so the
/// welcome page shows once after the update.
final class OnboardingCompletedNotifierProvider
    extends $NotifierProvider<OnboardingCompletedNotifier, bool> {
  /// Whether the onboarding page has been completed ("Weiter" tapped). The
  /// default false shows the shared about-content page full-page once the
  /// database is open; the continue action flips it to true, and the shell
  /// takes over (main._HomeGate reads this provider).
  ///
  /// Persisted exactly as [localeProvider] (registrar-table entry below): an
  /// absent row means not completed, for existing installs too, so the
  /// welcome page shows once after the update.
  OnboardingCompletedNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingCompletedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingCompletedNotifierHash();

  @$internal
  @override
  OnboardingCompletedNotifier create() => OnboardingCompletedNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$onboardingCompletedNotifierHash() =>
    r'a669c60bfed4ebdcc714d1278422f5bde5982def';

/// Whether the onboarding page has been completed ("Weiter" tapped). The
/// default false shows the shared about-content page full-page once the
/// database is open; the continue action flips it to true, and the shell
/// takes over (main._HomeGate reads this provider).
///
/// Persisted exactly as [localeProvider] (registrar-table entry below): an
/// absent row means not completed, for existing installs too, so the
/// welcome page shows once after the update.

abstract class _$OnboardingCompletedNotifier extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The user's NAME for the PDF export header (settings card "PDF-Export");
/// null means "not given". The per-export "anonymize" toggle NEVER writes
/// through this provider — it only changes what the generated document
/// shows. Persisted exactly as [localeProvider] (registrar-table entry
/// below).

@ProviderFor(PdfExportNameNotifier)
final pdfExportNameProvider = PdfExportNameNotifierProvider._();

/// The user's NAME for the PDF export header (settings card "PDF-Export");
/// null means "not given". The per-export "anonymize" toggle NEVER writes
/// through this provider — it only changes what the generated document
/// shows. Persisted exactly as [localeProvider] (registrar-table entry
/// below).
final class PdfExportNameNotifierProvider
    extends $NotifierProvider<PdfExportNameNotifier, String?> {
  /// The user's NAME for the PDF export header (settings card "PDF-Export");
  /// null means "not given". The per-export "anonymize" toggle NEVER writes
  /// through this provider — it only changes what the generated document
  /// shows. Persisted exactly as [localeProvider] (registrar-table entry
  /// below).
  PdfExportNameNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pdfExportNameProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pdfExportNameNotifierHash();

  @$internal
  @override
  PdfExportNameNotifier create() => PdfExportNameNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$pdfExportNameNotifierHash() =>
    r'8c34a329025580d8b6cb63df363f25a12a5b15f3';

/// The user's NAME for the PDF export header (settings card "PDF-Export");
/// null means "not given". The per-export "anonymize" toggle NEVER writes
/// through this provider — it only changes what the generated document
/// shows. Persisted exactly as [localeProvider] (registrar-table entry
/// below).

abstract class _$PdfExportNameNotifier extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The user's BIRTH DATE for the PDF export header (date-only normalized);
/// null means "not given". Hidden by the per-export anonymize toggle like
/// [pdfExportNameProvider]. Persisted exactly as [localeProvider]
/// (registrar-table entry below).

@ProviderFor(PdfExportBirthDateNotifier)
final pdfExportBirthDateProvider = PdfExportBirthDateNotifierProvider._();

/// The user's BIRTH DATE for the PDF export header (date-only normalized);
/// null means "not given". Hidden by the per-export anonymize toggle like
/// [pdfExportNameProvider]. Persisted exactly as [localeProvider]
/// (registrar-table entry below).
final class PdfExportBirthDateNotifierProvider
    extends $NotifierProvider<PdfExportBirthDateNotifier, DateTime?> {
  /// The user's BIRTH DATE for the PDF export header (date-only normalized);
  /// null means "not given". Hidden by the per-export anonymize toggle like
  /// [pdfExportNameProvider]. Persisted exactly as [localeProvider]
  /// (registrar-table entry below).
  PdfExportBirthDateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pdfExportBirthDateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pdfExportBirthDateNotifierHash();

  @$internal
  @override
  PdfExportBirthDateNotifier create() => PdfExportBirthDateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime?>(value),
    );
  }
}

String _$pdfExportBirthDateNotifierHash() =>
    r'f85f85aee304055e8c576b761792298e679f6d63';

/// The user's BIRTH DATE for the PDF export header (date-only normalized);
/// null means "not given". Hidden by the per-export anonymize toggle like
/// [pdfExportNameProvider]. Persisted exactly as [localeProvider]
/// (registrar-table entry below).

abstract class _$PdfExportBirthDateNotifier extends $Notifier<DateTime?> {
  DateTime? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime?, DateTime?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime?, DateTime?>,
              DateTime?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The persisted general settings as one snapshot, freshly loaded from the
/// app_settings table the moment the database opens ([databaseProvider]).
/// The hydration registrar's driver ([hydratePersistedSettings], called
/// from main.CycleApp's snapshot listener) applies each snapshot into the
/// providers of the table below — the shared fill rule lives on that
/// table.
/// KeepAlive like [databaseProvider] — the load keeps the database open for
/// the app lifetime.

@ProviderFor(persistedSettings)
final persistedSettingsProvider = PersistedSettingsProvider._();

/// The persisted general settings as one snapshot, freshly loaded from the
/// app_settings table the moment the database opens ([databaseProvider]).
/// The hydration registrar's driver ([hydratePersistedSettings], called
/// from main.CycleApp's snapshot listener) applies each snapshot into the
/// providers of the table below — the shared fill rule lives on that
/// table.
/// KeepAlive like [databaseProvider] — the load keeps the database open for
/// the app lifetime.

final class PersistedSettingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PersistedSettings>,
          PersistedSettings,
          FutureOr<PersistedSettings>
        >
    with
        $FutureModifier<PersistedSettings>,
        $FutureProvider<PersistedSettings> {
  /// The persisted general settings as one snapshot, freshly loaded from the
  /// app_settings table the moment the database opens ([databaseProvider]).
  /// The hydration registrar's driver ([hydratePersistedSettings], called
  /// from main.CycleApp's snapshot listener) applies each snapshot into the
  /// providers of the table below — the shared fill rule lives on that
  /// table.
  /// KeepAlive like [databaseProvider] — the load keeps the database open for
  /// the app lifetime.
  PersistedSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistedSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistedSettingsHash();

  @$internal
  @override
  $FutureProviderElement<PersistedSettings> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PersistedSettings> create(Ref ref) {
    return persistedSettings(ref);
  }
}

String _$persistedSettingsHash() => r'33bcf0b5392e99e9d5d7ef3c193a09545b12df5a';

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).

@ProviderFor(SelectedDateNotifier)
final selectedDateProvider = SelectedDateNotifierProvider._();

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).
final class SelectedDateNotifierProvider
    extends $NotifierProvider<SelectedDateNotifier, DateTime> {
  /// The day currently pre-selected in the entry form (Tagebuch). Chart taps
  /// on the Zyklus screen write here; the entry form reloads its fields when
  /// it changes. Normalized to UTC midnight on read/write (DateOnly).
  SelectedDateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedDateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedDateNotifierHash();

  @$internal
  @override
  SelectedDateNotifier create() => SelectedDateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime>(value),
    );
  }
}

String _$selectedDateNotifierHash() =>
    r'e777edb5d6f4a7dc1c66c1e842efe8d2707a2c43';

/// The day currently pre-selected in the entry form (Tagebuch). Chart taps
/// on the Zyklus screen write here; the entry form reloads its fields when
/// it changes. Normalized to UTC midnight on read/write (DateOnly).

abstract class _$SelectedDateNotifier extends $Notifier<DateTime> {
  DateTime build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime, DateTime>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime, DateTime>,
              DateTime,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
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

@ProviderFor(LastForegroundDayNotifier)
final lastForegroundDayProvider = LastForegroundDayNotifierProvider._();

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
final class LastForegroundDayNotifierProvider
    extends $NotifierProvider<LastForegroundDayNotifier, DateTime?> {
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
  LastForegroundDayNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastForegroundDayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastForegroundDayNotifierHash();

  @$internal
  @override
  LastForegroundDayNotifier create() => LastForegroundDayNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime?>(value),
    );
  }
}

String _$lastForegroundDayNotifierHash() =>
    r'4efb3adb8396775817e28a7a617f08c5ee952d72';

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

abstract class _$LastForegroundDayNotifier extends $Notifier<DateTime?> {
  DateTime? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime?, DateTime?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime?, DateTime?>,
              DateTime?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
/// AppBar's actions (next to the info action — a row of its own above the
/// chart wasted vertical space), but the jump logic needs the chart's scroll
/// state (the viewport/column geometry, the day mapping and the scroll
/// controller all live on the chart state), so the chart state registers its
/// action here while mounted and clears it again on dispose. Null while no
/// chart is on screen (entries still loading, no data) — the AppBar hides
/// the button then.

@ProviderFor(CycleChartJumpNotifier)
final cycleChartJumpProvider = CycleChartJumpNotifierProvider._();

/// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
/// AppBar's actions (next to the info action — a row of its own above the
/// chart wasted vertical space), but the jump logic needs the chart's scroll
/// state (the viewport/column geometry, the day mapping and the scroll
/// controller all live on the chart state), so the chart state registers its
/// action here while mounted and clears it again on dispose. Null while no
/// chart is on screen (entries still loading, no data) — the AppBar hides
/// the button then.
final class CycleChartJumpNotifierProvider
    extends
        $NotifierProvider<
          CycleChartJumpNotifier,
          void Function(BuildContext context)?
        > {
  /// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
  /// AppBar's actions (next to the info action — a row of its own above the
  /// chart wasted vertical space), but the jump logic needs the chart's scroll
  /// state (the viewport/column geometry, the day mapping and the scroll
  /// controller all live on the chart state), so the chart state registers its
  /// action here while mounted and clears it again on dispose. Null while no
  /// chart is on screen (entries still loading, no data) — the AppBar hides
  /// the button then.
  CycleChartJumpNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cycleChartJumpProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cycleChartJumpNotifierHash();

  @$internal
  @override
  CycleChartJumpNotifier create() => CycleChartJumpNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void Function(BuildContext context)? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<void Function(BuildContext context)?>(value),
    );
  }
}

String _$cycleChartJumpNotifierHash() =>
    r'48fc0feea50dd31cafba9850132e5c1bbc92193f';

/// The cycle chart's jump-to-date affordance. The button lives in the Zyklus
/// AppBar's actions (next to the info action — a row of its own above the
/// chart wasted vertical space), but the jump logic needs the chart's scroll
/// state (the viewport/column geometry, the day mapping and the scroll
/// controller all live on the chart state), so the chart state registers its
/// action here while mounted and clears it again on dispose. Null while no
/// chart is on screen (entries still loading, no data) — the AppBar hides
/// the button then.

abstract class _$CycleChartJumpNotifier
    extends $Notifier<void Function(BuildContext context)?> {
  void Function(BuildContext context)? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              void Function(BuildContext context)?,
              void Function(BuildContext context)?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                void Function(BuildContext context)?,
                void Function(BuildContext context)?
              >,
              void Function(BuildContext context)?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The day whose options panel is shown on the Zyklus screen (null = no
/// panel). Chart taps (the curve, the marks row, the signal-row cells)
/// write here instead of pushing a modal route, so tapping ANOTHER day
/// retargets the panel in place — the first day's marks are never
/// deselected by a dismissal — and the panel's close button clears it.
/// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
/// every writer is a chart day mapping). In-memory only: the panel is a
/// view-mode, not data.

@ProviderFor(CycleDayPanelNotifier)
final cycleDayPanelProvider = CycleDayPanelNotifierProvider._();

/// The day whose options panel is shown on the Zyklus screen (null = no
/// panel). Chart taps (the curve, the marks row, the signal-row cells)
/// write here instead of pushing a modal route, so tapping ANOTHER day
/// retargets the panel in place — the first day's marks are never
/// deselected by a dismissal — and the panel's close button clears it.
/// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
/// every writer is a chart day mapping). In-memory only: the panel is a
/// view-mode, not data.
final class CycleDayPanelNotifierProvider
    extends $NotifierProvider<CycleDayPanelNotifier, DateTime?> {
  /// The day whose options panel is shown on the Zyklus screen (null = no
  /// panel). Chart taps (the curve, the marks row, the signal-row cells)
  /// write here instead of pushing a modal route, so tapping ANOTHER day
  /// retargets the panel in place — the first day's marks are never
  /// deselected by a dismissal — and the panel's close button clears it.
  /// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
  /// every writer is a chart day mapping). In-memory only: the panel is a
  /// view-mode, not data.
  CycleDayPanelNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cycleDayPanelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cycleDayPanelNotifierHash();

  @$internal
  @override
  CycleDayPanelNotifier create() => CycleDayPanelNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime?>(value),
    );
  }
}

String _$cycleDayPanelNotifierHash() =>
    r'3e4f60a07ffc40628aa6d64f72ebdb42cccfb16a';

/// The day whose options panel is shown on the Zyklus screen (null = no
/// panel). Chart taps (the curve, the marks row, the signal-row cells)
/// write here instead of pushing a modal route, so tapping ANOTHER day
/// retargets the panel in place — the first day's marks are never
/// deselected by a dismissal — and the panel's close button clears it.
/// UTC-midnight normalized on write (DateOnly convention, checked nowhere:
/// every writer is a chart day mapping). In-memory only: the panel is a
/// view-mode, not data.

abstract class _$CycleDayPanelNotifier extends $Notifier<DateTime?> {
  DateTime? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime?, DateTime?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime?, DateTime?>,
              DateTime?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(pdfDocumentBuilder)
final pdfDocumentBuilderProvider = PdfDocumentBuilderProvider._();

final class PdfDocumentBuilderProvider
    extends
        $FunctionalProvider<
          PdfExportDocumentBuilder,
          PdfExportDocumentBuilder,
          PdfExportDocumentBuilder
        >
    with $Provider<PdfExportDocumentBuilder> {
  PdfDocumentBuilderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pdfDocumentBuilderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pdfDocumentBuilderHash();

  @$internal
  @override
  $ProviderElement<PdfExportDocumentBuilder> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PdfExportDocumentBuilder create(Ref ref) {
    return pdfDocumentBuilder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PdfExportDocumentBuilder value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PdfExportDocumentBuilder>(value),
    );
  }
}

String _$pdfDocumentBuilderHash() =>
    r'd66422a9b754b01bcdf8f75324cd551ac99349f5';
