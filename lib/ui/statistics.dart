// Statistik screen: pure arithmetic over cycle data.
//
// HARD PRODUCT RULE (docs/product/vision.md req. 3, lib/domain/statistics.dart):
// this screen shows RECORDED-DERIVED NUMBERS ONLY — counts, lengths,
// spreads, buckets. No status, no classification, no fertility statements.
// The caption below states this explicitly in the UI.
//
// Layout: the number of cycles first, then the uniform metric presentation
// (Minimum/Streuung/Maximum/Durchschnitt) for the three metrics — cycle
// length, bleeding days, first higher measurement until the cycle end —
// plus the earliest first higher measurement as a day-of-cycle number, and
// below ALL other statistics the per-cycle table (start, bleeding days,
// first higher, length). The distribution card keeps its place above the
// table.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/marks.dart';
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
      appBar: AppBar(title: Text(l10n.navStatistics)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text(l10n.loadFailed)),
        data: (entries) {
          final marks =
              ref.watch(marksProvider).valueOrNull ?? const <CycleMark>[];
          final stats = cycleStatistics(entries, marks);
          final lengths = cycleLengthsInDays(entries, marks);
          final buckets = cycleLengthDistribution(lengths);
          String day(DateTime d) =>
              DateFormat.yMd(locale).format(DateOnly.normalize(d).toLocal());

          return ListView(
            key: const ValueKey('statisticsScroll'),
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                l10n.statisticsNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (stats.cycleCount == 0) ...[
                // The statistics appear once a mark-opened cycle (with
                // tracked data) exists — not "two cycle starts" as before.
                Text(l10n.statisticsNoData),
              ] else ...[
                _StatCard(
                  key: const ValueKey('statisticsCycleCountCard'),
                  title: l10n.statisticsCycleCount,
                  child: Text(
                    '${stats.cycleCount}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                _MetricCard(
                  key: const ValueKey('statisticsMetric-cycleLength'),
                  title: l10n.statisticsMetricCycleLength,
                  summary: stats.cycleLengths,
                  locale: locale,
                ),
                const SizedBox(height: 8),
                _MetricCard(
                  key: const ValueKey('statisticsMetric-bleedingDays'),
                  title: l10n.statisticsBleedingDays,
                  summary: stats.bleedingDays,
                  locale: locale,
                ),
                const SizedBox(height: 8),
                _MetricCard(
                  key: const ValueKey('statisticsMetric-firstHigherUntilEnd'),
                  title: l10n.statisticsMetricFirstHigherUntilEnd,
                  summary: stats.firstHigherUntilCycleEnd,
                  locale: locale,
                ),
                const SizedBox(height: 8),
                _StatCard(
                  key: const ValueKey('statisticsEarliestFirstHigher'),
                  title: l10n.statisticsEarliestFirstHigher,
                  child: Text(
                    stats.earliestFirstHigherDayOfCycle == null
                        ? '-'
                        : l10n.statisticsFirstHigherDayOfCycle(
                            stats.earliestFirstHigherDayOfCycle!,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                _StatCard(
                  title: l10n.statisticsDistribution,
                  child: Column(
                    children: [
                      for (final bucket in buckets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  bucket.label,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: bucket.count == 0
                                      ? 0
                                      : bucket.count /
                                            buckets
                                                .map((b) => b.count)
                                                .fold<int>(
                                                  0,
                                                  (a, b) => a > b ? a : b,
                                                ),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '${bucket.count}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // The table sits below ALL other statistics: one row per
                // mark-opened cycle keeps the numbers auditable against the
                // mark-driven boundaries without adding any evaluation.
                _CycleTableCard(facts: stats.facts, day: day),
              ],
            ],
          );
        },
      ),
    );
  }
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.title,
    required this.summary,
    required this.locale,
  });

  final String title;
  final MetricSummary summary;
  final String locale;

  /// One decimal place (average and spread), localized — the same "0.0"
  /// pattern in every locale; intl renders the decimal separator per
  /// [locale]. Missing values render as the dash placeholder.
  String _fmt(double? value) =>
      value == null ? '-' : NumberFormat('0.0', locale).format(value);

  String _fmtInt(int? value) => value == null ? '-' : '$value';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StatCard(
      title: title,
      child: Column(
        children: [
          _metricRow(context, l10n.statisticsMinimum, _fmtInt(summary.min)),
          _metricRow(context, l10n.statisticsStdDev, _fmt(summary.stdDev)),
          _metricRow(context, l10n.statisticsMaximum, _fmtInt(summary.max)),
          _metricRow(context, l10n.statisticsAverage, _fmt(summary.average)),
        ],
      ),
    );
  }

  Widget _metricRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// The per-cycle table card: a simple bordered table (equal-width columns,
/// headers wrap) with the four exact columns the roadmap names: cycle
/// start, number of bleeding days, first higher measurement, length.
final class _CycleTableCard extends StatelessWidget {
  const _CycleTableCard({required this.facts, required this.day});

  final List<CycleFact> facts;
  final String Function(DateTime) day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StatCard(
      key: const ValueKey('statisticsCycleTable'),
      title: l10n.statisticsCycleTable,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        columnWidths: const {
          0: FlexColumnWidth(),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(),
        },
        children: [
          TableRow(
            children: [
              _cell(
                context,
                Text(
                  l10n.statisticsTableCycleStart,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              _cell(
                context,
                Text(
                  l10n.statisticsBleedingDays,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              _cell(
                context,
                Text(
                  l10n.termFirstHigher,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              _cell(
                context,
                Text(
                  l10n.statisticsTableLength,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          for (final (index, fact) in facts.indexed)
            TableRow(
              children: [
                _cell(
                  context,
                  KeyedSubtree(
                    key: ValueKey('statisticsRowStart-$index'),
                    child: Text(day(fact.cycleStart)),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    '${fact.bleedingDays}',
                    key: ValueKey('statisticsRowBleeding-$index'),
                  ),
                ),
                _cell(
                  context,
                  KeyedSubtree(
                    key: ValueKey('statisticsRowFirstHigher-$index'),
                    child: Text(
                      fact.firstHigherDay == null
                          ? '-'
                          : l10n.statisticsFirstHigherDayOfCycle(
                              DateOnly.daysBetween(
                                    fact.firstHigherDay!,
                                    fact.cycleStart,
                                  ) +
                                  1,
                            ),
                    ),
                  ),
                ),
                _cell(
                  context,
                  KeyedSubtree(
                    key: ValueKey('statisticsRowLength-$index'),
                    child: Text(
                      fact.lengthDays == null
                          ? '-'
                          : l10n.termCycleDays(fact.lengthDays!),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, Widget child) =>
      Padding(padding: const EdgeInsets.all(4), child: child);
}

final class _StatCard extends StatelessWidget {
  const _StatCard({super.key, required this.title, required this.child});

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
