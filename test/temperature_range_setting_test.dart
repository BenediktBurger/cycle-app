// Temperature-range setting: the cycle chart's y range (default
// 36–38 °C) is selectable in the settings screen's "Temperaturbereich"
// card — one RangeSlider across the allowed 34.0–42.0 °C window whose
// onChanged keeps a one-degree gap between the bounds (min < max) on the
// half-degree grid the slider's divisions imply.
// Mirrors the theme-mode/language switcher pattern: the choice is written
// through to the local app_settings table on change and hydrated back on
// the next start (the persistence round trip itself is pinned in
// settings_persistence_test.dart).
//
// The chart-side reaction to the range is pinned in
// test/cycle_chart_temperature_test.dart and
// test/cycle_chart_left_rail_test.dart (overridden provider): the settings
// tests pin the CARD — the slider, the defaults and the immediate
// provider write.
//
// An in-memory drift database override, no platform channels (same
// pattern as theme_mode_setting_test.dart). The slider is driven at its
// thumb geometry (support/range_slider.dart); the immediate-apply
// behavior is parametrized over the label formats.
import 'package:cycle_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/range_slider.dart';
import 'support/settings_switcher.dart';
import 'support/viewport.dart';

/// The running app's ProviderScope container (for direct provider reads).
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

RangeSlider _slider(WidgetTester tester) => tester.widget<RangeSlider>(
  find.byKey(const ValueKey('temperatureRangeSlider')),
);

/// One label-format case of the lower-thumb immediate-apply test: the
/// [deviceLocale] governs the decimal separator the bounds row renders
/// (null = the default test dispatcher, dot-formatted English).
class _MinStepCase {
  final String name;
  final Locale? deviceLocale;
  final String tabLabel;
  final String defaultLowerRow;
  final String draggedLowerRow;
  final String draggedUpperRow;
  final double target;
  final double expectedMin;

  const _MinStepCase(
    this.name, {
    required this.deviceLocale,
    required this.tabLabel,
    required this.defaultLowerRow,
    required this.draggedLowerRow,
    required this.draggedUpperRow,
    required this.target,
    required this.expectedMin,
  });
}

const _minStepCases = [
  _MinStepCase(
    'dot labels',
    deviceLocale: null,
    tabLabel: 'Settings',
    defaultLowerRow: 'Lower limit: 36.0 °C',
    draggedLowerRow: 'Lower limit: 35.0 °C',
    draggedUpperRow: 'Upper limit: 38.0 °C',
    target: 35.0,
    expectedMin: 35.0,
  ),
  _MinStepCase(
    'German comma labels (display only)',
    deviceLocale: Locale('de'),
    tabLabel: 'Einstellungen',
    defaultLowerRow: 'Untergrenze: 36,0 °C',
    draggedLowerRow: 'Untergrenze: 35,5 °C',
    draggedUpperRow: 'Obergrenze: 38,0 °C',
    target: 35.5,
    expectedMin: 35.5,
  ),
];

void main() {
  for (final stepCase in _minStepCases) {
    testWidgets('dragging the lower thumb updates the provider immediately '
        '(${stepCase.name})', (tester) async {
      if (stepCase.deviceLocale != null) {
        useDeviceLocales(tester, [stepCase.deviceLocale!]);
      }
      await pumpSettingsPane(tester, stepCase.tabLabel);

      expect(
        find.text(stepCase.defaultLowerRow),
        findsOneWidget,
        reason:
            'the bounds row renders the current range in this locale\'s format',
      );

      await dragRangeThumbToValue(tester, lower: true, value: stepCase.target);

      final range = _container(tester).read(temperatureRangeProvider);
      expect(
        range.min,
        stepCase.expectedMin,
        reason: 'the drag writes the provider at once',
      );
      expect(range.max, 38.0, reason: 'the upper bound stays untouched');
      expect(
        _slider(tester).values,
        RangeValues(stepCase.expectedMin, 38.0),
        reason: 'the slider shows the written range',
      );
      expect(
        find.text(stepCase.draggedLowerRow),
        findsOneWidget,
        reason: 'the bounds row follows the drag in this locale\'s format',
      );
      expect(find.text(stepCase.draggedUpperRow), findsOneWidget);
    });
  }

  testWidgets('with no override the provider defaults to 36.0..38.0 °C and the '
      'card renders the slider on it', (WidgetTester tester) async {
    await pumpSettingsPane(tester, 'Settings');

    final range = _container(tester).read(temperatureRangeProvider);
    expect(range.min, 36.0, reason: 'no override → the default 36–38 °C range');
    expect(range.max, 38.0, reason: 'no override → the default 36–38 °C range');

    expect(
      find.text('Temperature range'),
      findsOneWidget,
      reason: 'the card offers the chart\'s y range',
    );
    expect(
      _slider(tester).values,
      const RangeValues(36.0, 38.0),
      reason: 'the slider shows the current range',
    );

    expect(
      find.text(
        'Visible range of the temperature chart on the cycle tab. '
        'Default: 36–38 °C.',
      ),
      findsOneWidget,
      reason: 'the card explains what the range is for and its default',
    );

    await dragRangeThumbToValue(tester, lower: true, value: 36.5);

    final dragged = _container(tester).read(temperatureRangeProvider);
    expect(
      dragged.min,
      36.5,
      reason: 'a rightward drag writes the provider too',
    );
    expect(dragged.max, 38.0, reason: 'the upper bound stays untouched');
  });

  testWidgets('dragging the upper thumb onto the lower one keeps a one-degree '
      'gap in the provider (min < max)', (WidgetTester tester) async {
    await pumpSettingsPane(tester, 'Settings');

    await dragRangeThumbToValue(tester, lower: true, value: 36.5);
    await dragRangeThumbToValue(tester, lower: false, value: 36.5);

    final range = _container(tester).read(temperatureRangeProvider);
    expect(range.min, 36.5, reason: 'the lower bound stands as dragged');
    expect(
      range.max,
      37.5,
      reason: 'the zero-gap attempt is clamped back to a one-degree gap',
    );
    expect(range.min < range.max, isTrue);
  });

  testWidgets('dragging past the opposite thumb never persists an inverted '
      'range', (WidgetTester tester) async {
    await pumpSettingsPane(tester, 'Settings');

    await dragRangeThumbToValue(tester, lower: true, value: 39.0);

    var range = _container(tester).read(temperatureRangeProvider);
    expect(
      range.min,
      37.0,
      reason: 'the lower thumb is clamped to one degree below the upper one',
    );
    expect(range.max, 38.0, reason: 'the upper bound stays untouched');
    expect(range.min < range.max, isTrue);

    await dragRangeThumbToValue(tester, lower: false, value: 35.0);

    range = _container(tester).read(temperatureRangeProvider);
    expect(range.min, 37.0, reason: 'the lower bound stays untouched');
    expect(
      range.max,
      38.0,
      reason: 'the upper thumb is clamped to one degree above the lower one',
    );
    expect(range.min < range.max, isTrue);
  });

  testWidgets('the slider thumbs announce their bound name and current value '
      'to screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    useDeviceLocales(tester, const [Locale('de')]);
    await pumpSettingsPane(tester, 'Einstellungen');

    final lower = find.semantics.byValue('Untergrenze: 36,0 °C');
    final upper = find.semantics.byValue('Obergrenze: 38,0 °C');
    expect(
      lower,
      findsOneWidget,
      reason: 'the lower thumb announces its bound name and value',
    );
    expect(
      upper,
      findsOneWidget,
      reason: 'the upper thumb announces its bound name and value',
    );

    expect(
      lower.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.increase,
      ),
      isTrue,
    );
    tester.semantics.performAction(lower, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(
      _container(tester).read(temperatureRangeProvider).min,
      36.5,
      reason:
          'the screen-reader increase action moves the lower thumb by '
          'one half-degree step',
    );

    expect(
      upper.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.decrease,
      ),
      isTrue,
    );
    tester.semantics.performAction(upper, SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(
      _container(tester).read(temperatureRangeProvider).max,
      37.5,
      reason:
          'the screen-reader decrease action moves the upper thumb by '
          'one half-degree step',
    );

    semantics.dispose();
  });
}
