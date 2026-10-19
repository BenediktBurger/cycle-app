import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/decimal_display.dart';
import '../../domain/temperature_range.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// The snap grid the slider's `divisions` imply: every drag value and
/// clamp result lands on a half-degree value.
const double _step = 0.5;

/// The smallest gap the card keeps between the two bounds: two grid steps,
/// so every clamp lands back on the half-degree grid.
const double _minimumGap = 2 * _step;

/// Rounds [value] onto the half-degree grid the slider's divisions imply.
double _snap(double value) => (value / _step).round() * _step;

/// The range the card writes for a reported drag: both values snapped onto
/// the half-degree grid (drags stay on it via divisions, but the
/// screen-reader actions round to two decimals on the way), then the thumb
/// that moved — detected against the current provider value — nudged back
/// to the minimum gap when it landed on the other one (the framework
/// never reports a crossing).
TemperatureRange _clampedRange(RangeValues values, TemperatureRange current) {
  final start = _snap(values.start);
  final end = _snap(values.end);
  final movedLower = start != current.min;
  return TemperatureRange(
    min: movedLower && start > end - _minimumGap ? end - _minimumGap : start,
    max: movedLower
        ? end
        : end < start + _minimumGap
        ? start + _minimumGap
        : end,
  );
}

// --- temperature range ---------------------------------------
// The chart's y range: one RangeSlider across the allowed
// 34.0..42.0 °C window; min < max is enforced BY CONSTRUCTION
// (_clampedRange) — no error states.
final class TemperatureRangeCard extends ConsumerWidget {
  const TemperatureRangeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final range = ref.watch(temperatureRangeProvider);
    final locale = Localizations.localeOf(context).toString();
    String format(double value) =>
        '${formatDecimal(value, locale: locale, decimalDigits: 1)} °C';
    final lowerBound = '${l10n.settingsRangeLower}: ${format(range.min)}';
    final upperBound = '${l10n.settingsRangeUpper}: ${format(range.max)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsTemperatureRange,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(lowerBound)),
                const SizedBox(width: 12),
                Expanded(child: Text(upperBound)),
              ],
            ),
            RangeSlider(
              key: const ValueKey('temperatureRangeSlider'),
              values: RangeValues(range.min, range.max),
              min: TemperatureRange.windowLower,
              max: TemperatureRange.windowUpper,
              divisions:
                  ((TemperatureRange.windowUpper -
                              TemperatureRange.windowLower) /
                          _step)
                      .round(),
              labels: RangeLabels(format(range.min), format(range.max)),
              // The framework dispatches the callback per thumb without
              // handle identity; the nearer bound identifies the thumb —
              // a drag value can sit strictly between the stored ones.
              semanticFormatterCallback: (value) =>
                  (value - range.min).abs() <= (range.max - value).abs()
                  ? lowerBound
                  : upperBound,
              onChanged: (values) => ref
                  .read(temperatureRangeProvider.notifier)
                  .set(
                    _clampedRange(values, ref.read(temperatureRangeProvider)),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsTemperatureRangeNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
