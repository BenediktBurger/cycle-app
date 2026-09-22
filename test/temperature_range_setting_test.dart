// Temperature-range setting: the cycle chart's y range (default
// 36–38 °C) is selectable in the settings screen's "Temperaturbereich"
// card — two half-degree pickers inside the allowed 34.0–42.0 °C window
// with min < max enforced by construction. Mirrors the theme-mode/language
// switcher pattern: the choice is written through to the local app_settings
// table on change and hydrated back on the next start (the persistence
// round trip itself is pinned in settings_persistence_test.dart).
//
// The chart-side reaction to the range is pinned in
// test/cycle_chart_temperature_test.dart and
// test/cycle_chart_left_rail_test.dart (overridden provider): the settings
// tests pin the CARD — the pickers, the defaults and the immediate
// provider write.
//
// An in-memory drift database override, no platform channels (same
// pattern as theme_mode_setting_test.dart).
import 'package:cycle_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/database.dart';
import 'support/finders.dart';

ProviderScope _appScope() => appScope();

/// The running app's ProviderScope container (for direct provider reads).
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<void> _openSettings(WidgetTester tester) async {
  // Tap scoped to the navigation bar: all tabs stay mounted (IndexedStack),
  // so the 'Settings' label also matches the offstage screen's AppBar —
  // and in tree order that AppBar precedes the bar, so a bare .first tap
  // would miss.
  await tester.tap(navLabel('Settings'));
  await tester.pumpAndSettle();
}

Finder _minField() => find.byKey(const ValueKey('temperatureRangeMin'));
Finder _maxField() => find.byKey(const ValueKey('temperatureRangeMax'));

/// The picker widget itself (the form field wraps a DropdownButton that
/// carries value + items).
DropdownButton<double> _picker(WidgetTester tester, Finder field) =>
    tester.widget<DropdownButton<double>>(find.descendant(
        of: field, matching: find.byType(DropdownButton<double>)));

void main() {
  testWidgets(
      'with no override the provider defaults to 36.0..38.0 °C and the '
      'card renders the two pickers on it', (WidgetTester tester) async {
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();

    final range = _container(tester).read(temperatureRangeProvider);
    expect(range.min, 36.0, reason: 'no override → the default 36–38 °C range');
    expect(range.max, 38.0, reason: 'no override → the default 36–38 °C range');

    await _openSettings(tester);

    expect(find.text('Temperature range'), findsOneWidget,
        reason: 'the card offers the chart\'s y range');
    expect(_picker(tester, _minField()).value, 36.0,
        reason: 'the lower-limit picker shows the current range min');
    expect(_picker(tester, _maxField()).value, 38.0,
        reason: 'the upper-limit picker shows the current range max');
  });

  testWidgets(
      'changing the lower limit updates the provider immediately and the '
      'picker shows the half-degree steps', (WidgetTester tester) async {
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();
    await _openSettings(tester);

    await tester.tap(_minField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('35.0 °C').last);
    await tester.pumpAndSettle();

    final range = _container(tester).read(temperatureRangeProvider);
    expect(range.min, 35.0,
        reason: 'selecting a half-degree step writes the provider at once');
    expect(range.max, 38.0, reason: 'the upper limit stays untouched');
    expect(_picker(tester, _minField()).value, 35.0);
  });

  testWidgets(
      'min < max is enforced by construction: each picker only offers '
      'values strictly on its side of the other bound',
      (WidgetTester tester) async {
    await tester.pumpWidget(_appScope());
    await tester.pumpAndSettle();
    await _openSettings(tester);

    final minDrop = _picker(tester, _minField());
    final maxDrop = _picker(tester, _maxField());
    for (final item in minDrop.items!) {
      expect(item.value! < maxDrop.value!, isTrue,
          reason: 'the min picker never offers ${item.value} '
              '(the max is ${maxDrop.value})');
    }
    for (final item in maxDrop.items!) {
      expect(item.value! > minDrop.value!, isTrue,
          reason: 'the max picker never offers ${item.value} '
              '(the min is ${minDrop.value})');
    }

    // Tighten the lower limit to 37.5: the max picker must then start at
    // 38.0 — no equal or lower value is offered.
    await tester.tap(_minField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('37.5 °C').last);
    await tester.pumpAndSettle();

    final maxAfter = _picker(tester, _maxField());
    final offeredMax = [for (final item in maxAfter.items!) item.value!];
    expect(offeredMax.first, 38.0,
        reason: 'with min 37.5 the max picker starts at 38.0 (min < max)');
  });
}
