import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

Future<void> showStatisticsHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _StatisticsHelpSheet(),
  );
}

final class _StatisticsHelpSheet extends StatelessWidget {
  const _StatisticsHelpSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('statisticsHelpSheet'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.statisticsHelpTitle, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.statisticsHelpIntro, style: textTheme.bodySmall),
            _HelpSection(
              title: l10n.statisticsHelpSectionCycles,
              children: [
                _HelpEntry(
                  title: l10n.statisticsObservedCyclesTitle,
                  body: l10n.statisticsHelpObservedCycles,
                ),
                _HelpEntry(
                  title: l10n.statisticsShortest,
                  body: l10n.statisticsHelpShortest,
                ),
                _HelpEntry(
                  title: l10n.statisticsEarliestFirstHigher,
                  body: l10n.statisticsHelpEarliestFirstHigher,
                ),
              ],
            ),
            _HelpSection(
              title: l10n.statisticsHelpSectionCards,
              children: [
                _HelpEntry(
                  title: l10n.statisticsMetricCycleLength,
                  body: l10n.statisticsHelpCycleLength,
                ),
                _HelpEntry(
                  title: l10n.statisticsDistribution,
                  body: l10n.statisticsHelpDistribution,
                ),
                _HelpEntry(
                  title: l10n.statisticsMetricBleedingDuration,
                  body: l10n.statisticsHelpBleedingDuration,
                ),
                _HelpEntry(
                  title: l10n.statisticsMetricFirstHigherDay,
                  body: l10n.statisticsHelpFirstHigherDay,
                ),
                _HelpEntry(
                  title: l10n.statisticsMetricFirstHigherUntilEnd,
                  body: l10n.statisticsHelpFirstHigherUntilEnd,
                ),
              ],
            ),
            _HelpSection(
              title: l10n.statisticsHelpSectionFigures,
              children: [
                _HelpEntry(
                  title: l10n.statisticsMinimum,
                  body: l10n.statisticsHelpMinimum,
                ),
                _HelpEntry(
                  title: l10n.statisticsMaximum,
                  body: l10n.statisticsHelpMaximum,
                ),
                _HelpEntry(
                  title: l10n.statisticsAverage,
                  body: l10n.statisticsHelpAverage,
                ),
                _HelpEntry(
                  title: l10n.statisticsStandardDeviation,
                  body: l10n.statisticsHelpStandardDeviation,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  // statisticsMetricFromCycles carries a plural placeholder,
                  // so the count caption has a body but no static entry title.
                  child: Text(
                    l10n.statisticsHelpMetricCount,
                    style: textTheme.bodySmall,
                  ),
                ),
                _HelpEntry(
                  title: l10n.statisticsCycleTable,
                  body: l10n.statisticsHelpCycleTable,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// The title is the screen's own label, so help and screen cannot drift.
final class _HelpEntry extends StatelessWidget {
  const _HelpEntry({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(body, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
