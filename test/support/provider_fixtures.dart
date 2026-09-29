// Writable provider fixtures for the widget tests.
//
// riverpod 3's `overrideWithValue` pins are inert: a provider they back
// throws (`_SyncValueProviderElement ... is not a subtype of type
// $ClassProviderElement`) the moment anything reaches its notifier —
// and the pumped UI does write back through some pinned providers.
// Anything pinned AND writable from the pumped surface goes through
// these fixtures instead: a subclass of the production notifier whose
// `build()` returns the seeded value.
// The fixture factories' `Override` return type ships from the misc entry.
import 'package:cycle_app/domain/temperature_range.dart';
import 'package:cycle_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';

Override localePin(Locale? value) =>
    localeProvider.overrideWith(() => _FixedLocale(value));

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this.seed);

  final Locale? seed;

  @override
  Locale? build() => seed;
}

Override themeModePin(ThemeMode value) =>
    themeModeProvider.overrideWith(() => _FixedThemeMode(value));

class _FixedThemeMode extends ThemeModeNotifier {
  _FixedThemeMode(this.seed);

  final ThemeMode seed;

  @override
  ThemeMode build() => seed;
}

Override onboardingPin(bool value) =>
    onboardingCompletedProvider.overrideWith(() => _FixedOnboarding(value));

class _FixedOnboarding extends OnboardingCompletedNotifier {
  _FixedOnboarding(this.seed);

  final bool seed;

  @override
  bool build() => seed;
}

Override selectedDatePin(DateTime value) =>
    selectedDateProvider.overrideWith(() => _FixedSelectedDate(value));

class _FixedSelectedDate extends SelectedDateNotifier {
  _FixedSelectedDate(this.seed);

  final DateTime seed;

  @override
  DateTime build() => seed;
}

Override tabIndexPin(int value) =>
    tabIndexProvider.overrideWith(() => _FixedTabIndex(value));

class _FixedTabIndex extends TabIndexNotifier {
  _FixedTabIndex(this.seed);

  final int seed;

  @override
  int build() => seed;
}

Override temperatureRangePin(TemperatureRange value) =>
    temperatureRangeProvider.overrideWith(() => _FixedRange(value));

class _FixedRange extends TemperatureRangeNotifier {
  _FixedRange(this.seed);

  final TemperatureRange seed;

  @override
  TemperatureRange build() => seed;
}

Override observedCyclesPin(int value) =>
    observedCyclesOutsideAppProvider.overrideWith(() => _FixedObserved(value));

class _FixedObserved extends ObservedCyclesOutsideAppNotifier {
  _FixedObserved(this.seed);

  final int seed;

  @override
  int build() => seed;
}

Override paperShortestPin(int? value) => shortestCycleLengthOutsideAppProvider
    .overrideWith(() => _FixedShortest(value));

class _FixedShortest extends ShortestCycleLengthOutsideAppNotifier {
  _FixedShortest(this.seed);

  final int? seed;

  @override
  int? build() => seed;
}

Override paperEarliestPin(int? value) =>
    earliestFirstHigherCycleDayOutsideAppProvider.overrideWith(
      () => _FixedEarliest(value),
    );

class _FixedEarliest extends EarliestFirstHigherCycleDayOutsideAppNotifier {
  _FixedEarliest(this.seed);

  final int? seed;

  @override
  int? build() => seed;
}

Override pdfExportNamePin(String? value) =>
    pdfExportNameProvider.overrideWith(() => _FixedPdfName(value));

class _FixedPdfName extends PdfExportNameNotifier {
  _FixedPdfName(this.seed);

  final String? seed;

  @override
  String? build() => seed;
}

Override pdfExportBirthDatePin(DateTime? value) =>
    pdfExportBirthDateProvider.overrideWith(() => _FixedPdfBirth(value));

class _FixedPdfBirth extends PdfExportBirthDateNotifier {
  _FixedPdfBirth(this.seed);

  final DateTime? seed;

  @override
  DateTime? build() => seed;
}
