// Statistik screen: aggregate statistics, all on one tab (the cycle tab's
// evaluation table is the paper-form evaluation, not aggregates).
//
// Recorded-derived numbers only (lib/domain/statistics.dart): counts,
// lengths, averages, buckets — no classification, no fertility
// statements. Everything is computed at render time from the entries +
// marks streams (ADR-0001: nothing derived is persisted); missing values
// render as the "—" dash. The paper-history settings fold into the
// shortest/earliest surfaces as a MIN-combination only — see the build
// method's fold comment.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/decimal_display.dart';
import '../domain/statistics.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'stream_error.dart';

/// The shared missing-value marker of this screen — a neutral glyph, not
/// language text.
const String _missing = '—';

class StatistikScreen extends ConsumerWidget {
  const StatistikScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(dailyEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navStatistics)),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => StreamLoadError(
          scope: 'entries',
          onRetry: () => ref.invalidate(dailyEntriesProvider),
        ),
        data: (entries) {
          // The marks watch stays unmasked: on a failed stream the screen
          // must not silently render aggregates from an empty marks list.
          final marksAsync = ref.watch(marksProvider);
          return marksAsync.when(
            loading: () => _statisticsView(context, ref),
            error: (e, s) => StreamLoadError(
              scope: 'marks',
              onRetry: () => ref.invalidate(marksProvider),
            ),
            data: (marks) => _statisticsView(context, ref),
          );
        },
      ),
    );
  }

  /// The statistics body rendered from one snapshot of the shared derived
  /// pass: every number comes from the ONE cached grouping + evaluation
  /// pass behind [derivedCycleDataProvider] — nothing groups or evaluates
  /// here during build.
  Widget _statisticsView(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final derived = ref.watch(derivedCycleDataProvider);
    final cycles = derived.cycles;
    final lengths = cycleLengthsInDaysFrom(cycles);
    final summary = summarizeCycleLengths(lengths);
    final buckets = cycleLengthDistribution(lengths);
    final onsets = menstruationOnsetDatesFrom(cycles);
    String day(DateTime d) => DateFormat.yMd(locale).format(
      // Date-only values are UTC-normalized midnights — print verbatim;
      // a .toLocal() shows the previous day on UTC-negative hosts.
      DateOnly.normalize(d),
    );

    // A cycle contributing no value to a card's metric (no bleeding day,
    // no rise mark, an open cycle) simply does not feed the aggregate —
    // the "—" rows are for the all-empty case.
    final evaluations = derived.evaluations;
    final lengthDetail = summarizeInts(lengths);
    final bleedingDetail = summarizeInts(
      cycleBleedingDurationsInDays(evaluations).nonNulls.toList(),
    );
    final riseDetail = summarizeInts(
      riseToEndDurationsInDays(evaluations).nonNulls.toList(),
    );
    final earliest = earliestFirstHigherCycleDay(evaluations);

    // The paper-history settings fold in through minRecordedFact at the
    // shortest/earliest surfaces: figures recorded BEFORE every in-app
    // cycle are known facts at this screen's point of view. They stay out
    // of the lengths list, distribution and per-cycle table (in-app-only
    // surfaces stay gated on `lengths`).
    final paperShortest = ref.watch(shortestCycleLengthOutsideAppProvider);
    final paperEarliest = ref.watch(
      earliestFirstHigherCycleDayOutsideAppProvider,
    );
    final shortestOverall = minRecordedFact(paperShortest, summary.shortest);
    final lengthDetailWithPaper = DescriptiveSummary(
      minimum: minRecordedFact(paperShortest, lengthDetail.minimum),
      maximum: lengthDetail.maximum,
      average: lengthDetail.average,
      standardDeviation: lengthDetail.standardDeviation,
    );
    final earliestWithPaper = (
      any: minRecordedFact(paperEarliest, earliest.any),
      afterMucusPeak: minRecordedFact(paperEarliest, earliest.afterMucusPeak),
    );

    // Renders with ONLY a paper shortest present (in-app lengths empty):
    // a paper-only user sees her recorded shortest figure instead of a
    // hidden row; average and longest dash (the paper value is one fact,
    // not a lengths distribution).
    final hasShortestRow = summary.lengths.isNotEmpty || paperShortest != null;

    // Fact rows keep the cycleFacts counting rule (each fact's span counts
    // to the next marked start; the trailing observed end is one day past
    // the last TRACKED day — see cycleFacts).
    final stats = cycleStatisticsFromCycles(cycles, evaluations);

    // The cycle-count surface: the mark-opened cycles recorded in the app
    // plus the outside-app count from the settings value (the caption
    // names the composition on the surface).
    final cyclesInApp = markDrivenCycleCountFrom(cycles);
    final cyclesOutsideApp = ref.watch(observedCyclesOutsideAppProvider);
    final cyclesTotal = cyclesInApp + cyclesOutsideApp;
    var countCaption = l10n.statisticsCyclesInApp(cyclesInApp);
    if (cyclesOutsideApp > 0) {
      countCaption += ' · ${l10n.statisticsCyclesOutsideApp(cyclesOutsideApp)}';
    }

    // The earliest first higher, two variants: "real" (strictly after the
    // mucus peak) is the primary row, the over-all-cycles minimum the
    // fallback. The missing-variant caption gates on the paper-FOLDED
    // pair — the rows display the fold, so gating on the raw in-app
    // values would claim a missing variant while the row carries the
    // paper figure.
    String cycleDayText(int? n) =>
        n == null ? _missing : l10n.statisticsCycleDay(n);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(l10n.statisticsNote, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        _countCard(
          context,
          l10n,
          cyclesTotal: cyclesTotal,
          caption: countCaption,
        ),
        const SizedBox(height: 8),
        if (onsets.isEmpty) ...[
          // Keys on the FACT that no cycle start is recorded yet, never on
          // the length count: a single still-open cycle has recorded starts
          // but no countable lengths yet.
          Text(l10n.statisticsNoData),
          const SizedBox(height: 8),
        ],
        if (summary.lengths.isNotEmpty) ...[
          _lengthsListCard(context, l10n, summary.lengths),
          const SizedBox(height: 8),
        ],
        if (hasShortestRow) ...[
          _averageShortestLongestRow(
            context,
            summary,
            shortestOverride: shortestOverall,
          ),
          const SizedBox(height: 8),
        ],
        _MetricCard(
          key: const ValueKey('statisticsCard-cycleLength'),
          title: l10n.statisticsMetricCycleLength,
          detail: lengthDetailWithPaper,
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
        _MetricCard(
          key: const ValueKey('statisticsMetric-firstHigherUntilEnd'),
          title: l10n.statisticsMetricFirstHigherUntilEnd,
          detail: _descriptiveDetail(stats.firstHigherUntilCycleEnd),
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
                value: cycleDayText(earliestWithPaper.afterMucusPeak),
              ),
              _ValueRow(
                label: l10n.statisticsFirstHigherAny,
                value: cycleDayText(earliestWithPaper.any),
              ),
              if (earliestWithPaper.afterMucusPeak == null &&
                  earliestWithPaper.any != null)
                Text(
                  l10n.statisticsFirstHigherRealMissing,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The fact-gated surfaces gate on the recorded data's own count —
        // not the lengths': the onset list shows whenever a cycle start is
        // recorded, the per-cycle table whenever fact rows exist; only the
        // distribution card stays glued to the lengths (it buckets lengths).
        if (onsets.isNotEmpty) ...[
          _onsetsCard(context, onsets, day),
          const SizedBox(height: 8),
        ],
        if (summary.lengths.isNotEmpty) ...[
          _distributionCard(context, buckets),
          const SizedBox(height: 8),
        ],
        if (stats.facts.isNotEmpty)
          // Below ALL other statistics: the one-row-per-cycle table keeps
          // the numbers auditable against the mark-driven boundaries
          // without adding any evaluation.
          _CycleTableCard(
            key: const ValueKey('statisticsCycleTable'),
            facts: stats.facts,
            day: day,
          ),
      ],
    );
  }
}

Widget _countCard(
  BuildContext context,
  AppLocalizations l10n, {
  required int cyclesTotal,
  required String caption,
}) => _StatCard(
  key: const ValueKey('statisticsCard-cyclesCount'),
  title: l10n.statisticsObservedCyclesTitle,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$cyclesTotal', style: Theme.of(context).textTheme.headlineSmall),
      Text(caption),
    ],
  ),
);

Widget _lengthsListCard(
  BuildContext context,
  AppLocalizations l10n,
  List<int> lengths,
) => _StatCard(
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
  CycleLengthSummary summary, {
  // Min-combined shortest figure (paper fold — see the build method's
  // fold comment); average and longest stay in-app-only.
  required int? shortestOverride,
}) {
  final l10n = AppLocalizations.of(context);
  return Row(
    children: [
      Expanded(
        child: _StatCard(
          key: const ValueKey('statisticsCard-average'),
          title: l10n.statisticsAverage,
          child: Text(
            _scalarText(context, summary.average),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _StatCard(
          key: const ValueKey('statisticsCard-shortest'),
          title: l10n.statisticsShortest,
          child: _headlineText(context, shortestOverride),
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
) => _StatCard(
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

// The histogram over the cycle lengths; the bucket edges are a domain
// question (lib/domain/statistics.dart).
Widget _distributionCard(
  BuildContext context,
  List<CycleLengthBucket> buckets,
) {
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
                                  .fold<int>(0, (a, b) => a > b ? a : b),
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
  );
}

/// One metric card: the descriptive detail set (minimum, maximum,
/// average, standard deviation) for ONE metric family, in the shared
/// [_StatCard] style. Values are numbers ("n days" / one decimal) or the
/// "—" dash when there is no data.
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
            value: _scalarText(context, detail.average),
          ),
          _ValueRow(
            label: l10n.statisticsStandardDeviation,
            value: _scalarText(context, detail.standardDeviation),
          ),
        ],
      ),
    );
  }
}

/// ONE scalar formatting rule for fractional descriptive values (average,
/// standard deviation): one decimal digit in the effective locale, or the
/// "—" dash.
String _scalarText(BuildContext context, double? value) => value == null
    ? _missing
    : formatDecimal(
        value,
        locale: Localizations.localeOf(context).toString(),
        decimalDigits: 1,
      );

/// One label/value line inside a statistics card — numbers only; the
/// label names WHAT is counted, never how to read it.
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

/// Maps the domain's [MetricSummary] onto the screen's descriptive card
/// shape so every metric card renders through one shared class.
DescriptiveSummary _descriptiveDetail(MetricSummary summary) =>
    DescriptiveSummary(
      minimum: summary.min,
      maximum: summary.max,
      average: summary.average,
      standardDeviation: summary.stdDev,
    );

/// The per-cycle table card: a bordered table of equal-width columns
/// (headers wrap) with the four columns: cycle start, bleeding days,
/// first higher measurement, length.
final class _CycleTableCard extends StatelessWidget {
  const _CycleTableCard({super.key, required this.facts, required this.day});

  final List<CycleFact> facts;
  final String Function(DateTime) day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StatCard(
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
                  l10n.termCycleStart,
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
                          ? _missing
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
                          ? _missing
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

/// One statistics card: a titled Card block (ONE style so the screen's
/// cards cannot drift visually); `key` is the stable surface key the
/// tests address.
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
