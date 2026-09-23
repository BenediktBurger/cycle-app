// Statistik screen: the app's aggregate statistics, all on one tab (the
// cycle tab's evaluation table is the paper-form evaluation, not aggregates —
// nothing is moved there).
//
// HARD PRODUCT RULE (docs/product/vision.md req. 3, lib/domain/statistics.dart):
// this screen shows RECORDED-DERIVED NUMBERS ONLY — counts, lengths,
// averages, buckets. No status, no classification, no fertility statements.
// The caption below states this explicitly in the UI.
//
// Everything is computed at render time from the entries + marks streams
// (ADR-0001: nothing derived is persisted). The cycle-count card composes
// the total observed cycles from the mark-opened cycles recorded in the
// app plus the "observed cycles outside this app" settings value — the
// card's caption names that composition on the surface ("in this app: n"
// and, when the user has set it, "outside: n"). Missing values render as
// the "—" dash.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/marks.dart';
import '../domain/statistics.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// The shared missing-value marker of this screen, mirroring the cycle
/// page's evaluation table's dash — a neutral glyph, not language text.
const String _missing = '—';

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
          final lengths = cycleLengthsInDays(entries, marks);
          final summary = summarizeCycleLengths(lengths);
          final buckets = cycleLengthDistribution(lengths);
          final onsets = menstruationOnsetDates(entries, marks);
          String day(DateTime d) =>
              DateFormat.yMd(locale).format(DateOnly.normalize(d).toLocal());

          // The per-cycle evaluations feed everything beyond the plain
          // cycle lengths (pure render-time arithmetic per ADR-0001).
          final evaluations = evaluateCycles(entries, marks);
          // Each descriptive detail card aggregates the metric's values
          // over the mark-driven cycles; a cycle contributing no value
          // (no bleeding day, no rise mark, an open cycle) simply does
          // not feed the aggregate — the "—" card rows are for the
          // all-empty case.
          final lengthDetail = summarizeInts(lengths);
          final bleedingDetail = summarizeInts(
              cycleBleedingDurationsInDays(evaluations).nonNulls.toList());
          final riseDetail = summarizeInts(
              riseToEndDurationsInDays(evaluations).nonNulls.toList());
          final earliest = earliestFirstHigherCycleDay(evaluations);

          // The cycle-count surface: the mark-opened cycles recorded in
          // this app plus the outside-app count from the settings value.
          final cyclesInApp = markDrivenCycleCount(entries, marks);
          final cyclesOutsideApp = ref.watch(observedCyclesOutsideAppProvider);
          final cyclesTotal = cyclesInApp + cyclesOutsideApp;
          var countCaption = l10n.statisticsCyclesInApp(cyclesInApp);
          if (cyclesOutsideApp > 0) {
            countCaption +=
                ' · ${l10n.statisticsCyclesOutsideApp(cyclesOutsideApp)}';
          }

          // The earliest first higher, two documented variants: the
          // "real" one (strictly after the mucus peak) is the primary row;
          // the over-all-cycles minimum is the fallback row. When the real
          // variant qualifies nowhere, the dash + the missing-variant
          // caption state that fact.
          String cycleDayText(int? n) =>
              n == null ? _missing : l10n.statisticsCycleDay(n);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                l10n.statisticsNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _countCard(
                context,
                l10n,
                cyclesTotal: cyclesTotal,
                caption: countCaption,
              ),
              const SizedBox(height: 8),
              if (summary.lengths.isEmpty) ...[
                Text(l10n.statisticsNoData),
                const SizedBox(height: 8),
              ] else ...[
                _lengthsListCard(context, l10n, summary.lengths),
                const SizedBox(height: 8),
                _averageShortestLongestRow(context, summary),
                const SizedBox(height: 8),
              ],
              _MetricCard(
                key: const ValueKey('statisticsCard-cycleLength'),
                title: l10n.statisticsMetricCycleLength,
                detail: lengthDetail,
              ),
              const SizedBox(height: 8),
              _MetricCard(
                key: const ValueKey('statisticsCard-bleedingDuration'),
                title: l10n.statisticsMetricBleedingDuration,
                detail: bleedingDetail,
              ),
              const SizedBox(height: 8),
              _MetricCard(
                key: const ValueKey('statisticsCard-riseSpan'),
                title: l10n.statisticsMetricRiseSpan,
                detail: riseDetail,
              ),
              const SizedBox(height: 8),
              _StatCard(
                key: const ValueKey('statisticsCard-earliestFirstHigher'),
                title: l10n.statisticsEarliestFirstHigher,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ValueRow(
                        label: l10n.statisticsFirstHigherReal,
                        value: cycleDayText(earliest.afterMucusPeak)),
                    _ValueRow(
                        label: l10n.statisticsFirstHigherAny,
                        value: cycleDayText(earliest.any)),
                    if (earliest.afterMucusPeak == null && earliest.any != null)
                      Text(l10n.statisticsFirstHigherRealMissing,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (summary.lengths.isNotEmpty) ...[
                _onsetsCard(context, onsets, day),
                const SizedBox(height: 8),
                _distributionCard(context, buckets),
              ],
            ],
          );
        },
      ),
    );
  }
}

Widget _countCard(
  BuildContext context,
  AppLocalizations l10n, {
  required int cyclesTotal,
  required String caption,
}) =>
    _StatCard(
      key: const ValueKey('statisticsCard-cyclesCount'),
      title: l10n.statisticsObservedCyclesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$cyclesTotal',
              style: Theme.of(context).textTheme.headlineSmall),
          Text(caption),
        ],
      ),
    );

Widget _lengthsListCard(
  BuildContext context,
  AppLocalizations l10n,
  List<int> lengths,
) =>
    _StatCard(
      key: const ValueKey('statisticsCard-lengthsList'),
      title: l10n.statisticsCycles,
      child: Column(
        children: [
          for (final length in lengths)
            ListTile(
              dense: true,
              leading: const Icon(Icons.loop_outlined),
              title: Text(l10n.termCycleDays(length)),
            ),
        ],
      ),
    );

Widget _averageShortestLongestRow(
  BuildContext context,
  CycleLengthSummary summary,
) {
  final l10n = AppLocalizations.of(context);
  return Row(
    children: [
      Expanded(
        child: _StatCard(
          key: const ValueKey('statisticsCard-average'),
          title: l10n.statisticsAverage,
          child: Text(
            _scalarText(summary.average),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _StatCard(
          key: const ValueKey('statisticsCard-shortest'),
          title: l10n.statisticsShortest,
          child: _headlineText(context, summary.shortest),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _StatCard(
          key: const ValueKey('statisticsCard-longest'),
          title: l10n.statisticsLongest,
          child: _headlineText(context, summary.longest),
        ),
      ),
    ],
  );
}

Widget _headlineText(BuildContext context, int? value) => Text(
      value == null ? _missing : '$value',
      style: Theme.of(context).textTheme.headlineSmall,
    );

Widget _onsetsCard(
  BuildContext context,
  List<DateTime> onsets,
  String Function(DateTime) day,
) =>
    _StatCard(
      key: const ValueKey('statisticsCard-onsets'),
      title: AppLocalizations.of(context).statisticsOnsets,
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
    );

// The histogram over the cycle lengths — the same fixed buckets the
// domain derives (bucket edges are a domain question, see there).
Widget _distributionCard(
    BuildContext context, List<CycleLengthBucket> buckets) {
  final l10n = AppLocalizations.of(context);
  return _StatCard(
    key: const ValueKey('statisticsCard-distribution'),
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
                  child: Text(bucket.label,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: bucket.count == 0
                        ? 0
                        : bucket.count /
                            buckets
                                .map((b) => b.count)
                                .fold<int>(0, (a, b) => a > b ? a : b),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text('${bucket.count}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// One metric card of the Statistik screen: the descriptive detail set
/// (minimum, maximum, average, standard deviation) for ONE metric family,
/// rendered in the shared [_StatCard] card style. Values are numbers
/// ("n days" / one decimal) or the "—" dash when there is no data.
final class _MetricCard extends StatelessWidget {
  const _MetricCard({super.key, required this.title, required this.detail});

  final String title;
  final DescriptiveSummary detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StatCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueRow(
            label: l10n.statisticsMinimum,
            value: detail.minimum == null
                ? _missing
                : l10n.termCycleDays(detail.minimum!),
          ),
          _ValueRow(
            label: l10n.statisticsMaximum,
            value: detail.maximum == null
                ? _missing
                : l10n.termCycleDays(detail.maximum!),
          ),
          _ValueRow(
            label: l10n.statisticsAverage,
            value: _scalarText(detail.average),
          ),
          _ValueRow(
            label: l10n.statisticsStandardDeviation,
            value: _scalarText(detail.standardDeviation),
          ),
        ],
      ),
    );
  }
}

/// ONE scalar formatting rule for fractional descriptive values (average,
/// standard deviation): one decimal digit, or the "—" dash. Shared by the
/// metric cards and the old average card so they cannot drift.
String _scalarText(double? value) =>
    value == null ? _missing : value.toStringAsFixed(1);

/// One label/value line inside a statistics card (numbers only — the
/// label names WHAT is counted, never how to read it).
final class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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

/// One statistics card: a titled Card block (ONE style so the screen's
/// cards cannot drift visually). `title` is the localized card heading,
/// `child` its content, `key` the stable surface key used by the tests.
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
