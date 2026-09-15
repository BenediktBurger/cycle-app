// Statistik screen: pure arithmetic over cycle lengths.
//
// HARD PRODUCT RULE (docs/product/vision.md req. 3, lib/domain/statistics.dart):
// this screen shows RECORDED-DERIVED NUMBERS ONLY — lengths, averages,
// buckets. No status, no classification, no fertility statements. The
// caption below states this explicitly in the UI.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/statistics.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

class StatistikScreen extends ConsumerWidget {
  const StatistikScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final entriesAsync = ref.watch(dailyEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navStatistik)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text(l10n.loadFailed)),
        data: (entries) {
          final lengths = cycleLengthsInDays(entries);
          final summary = summarizeCycleLengths(lengths);
          final buckets = cycleLengthDistribution(lengths);
          final onsets = menstruationOnsetDates(entries);
          String day(DateTime d) =>
              DateFormat.yMd(locale).format(DateOnly.normalize(d).toLocal());

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                l10n.statistikNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (summary.lengths.isEmpty) ...[
                Text(l10n.statistikNoData),
              ] else ...[
                _StatCard(
                  title: l10n.statistikCycles,
                  child: Column(
                    children: [
                      for (final length in summary.lengths)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.loop_outlined),
                          title: Text(l10n.statistikDays(length)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: l10n.statistikAverage,
                        child: Text(
                          summary.average!.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: l10n.statistikShortest,
                        child: Text(
                          '${summary.shortest}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: l10n.statistikLongest,
                        child: Text(
                          '${summary.longest}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // The raw onset dates keep the length list auditable against
                // the (assumed) boundary rule without adding any evaluation.
                _StatCard(
                  title: l10n.statistikOnsets,
                  child: Column(
                    children: [
                      for (final onset in onsets)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.border_color_outlined),
                          title: Text(day(onset)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _StatCard(
                  title: l10n.statistikDistribution,
                  child: Column(
                    children: [
                      for (final bucket in buckets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(bucket.label,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: bucket.count == 0
                                      ? 0
                                      : bucket.count /
                                          buckets.map((b) => b.count).fold<int>(
                                              0, (a, b) => a > b ? a : b),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 24,
                                child: Text('${bucket.count}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

final class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}
