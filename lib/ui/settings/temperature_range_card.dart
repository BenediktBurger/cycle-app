import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/decimal_display.dart';
import '../../domain/temperature_range.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// The selectable half-degree steps of the temperature-range pickers, across
/// the allowed 34.0..42.0 °C window. Built from integer half-steps (k / 2)
/// so no float drift creeps into the 0.5 step grid.
final List<double> temperatureRangeSteps = List.unmodifiable(<double>[
  for (
    var k = (TemperatureRange.windowLower / 0.5).round(),
        upper = (TemperatureRange.windowUpper / 0.5).round();
    k <= upper;
    k++
  )
    k * 0.5,
]);

// --- temperature range ---------------------------------------
// The chart's y range: two half-degree pickers; min < max is
// enforced BY CONSTRUCTION — each picker only offers the values
// strictly on its side of the other bound (no error states).
final class TemperatureRangeCard extends ConsumerWidget {
  const TemperatureRangeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
            Builder(
              builder: (context) {
                final range = ref.watch(temperatureRangeProvider);
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: const ValueKey('temperatureRangeMin'),
                        initialValue: range.min,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.settingsRangeLower,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final step in temperatureRangeSteps.where(
                            (step) => step < range.max,
                          ))
                            DropdownMenuItem(
                              value: step,
                              child: Text(
                                '${formatDecimal(step, locale: Localizations.localeOf(context).toString(), decimalDigits: 1)} °C',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(temperatureRangeProvider.notifier)
                              .set(
                                TemperatureRange(min: value, max: range.max),
                              );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        key: const ValueKey('temperatureRangeMax'),
                        initialValue: range.max,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.settingsRangeUpper,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final step in temperatureRangeSteps.where(
                            (step) => step > range.min,
                          ))
                            DropdownMenuItem(
                              value: step,
                              child: Text(
                                '${formatDecimal(step, locale: Localizations.localeOf(context).toString(), decimalDigits: 1)} °C',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(temperatureRangeProvider.notifier)
                              .set(
                                TemperatureRange(min: range.min, max: value),
                              );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsTemperatureRangeDefaultHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
