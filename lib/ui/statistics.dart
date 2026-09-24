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
// and, when the user has set it, "outside: n"). The paper-history values
// (shortest cycle, earliest first higher — both optional settings) fold
// into the shortest/earliest surfaces as plain MIN-combination, since
// they were recorded before every in-app cycle; they stay OUT of the
// lengths list, the distribution and the per-cycle table (single
// recorded facts, not distribution entries). Missing values render as
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
          String day(DateTime d) => DateFormat.yMd(locale).format(
            // A date-only value is already UTC-normalized midnights (the
            // DateOnly convention); DateFormat reads the value's OWN
            // fields, so it must be printed verbatim — a .toLocal() would
            // show the PREVIOUS day on UTC-negative hosts.
            DateOnly.normalize(d),
          );

          // The per-cycle evaluations feed everything beyond the plain
          // cycle lengths (pure render-time arithmetic per ADR-0001).
          final evaluations = evaluateCycles(
            entries,
            marks,
            // The grouping's injected clock (last-cycle span rule — the
            // nowProvider seam, pinned in tests).
            today: ref.read(nowProvider)(),
          );
          // Each descriptive detail card aggregates the metric's values
          // over the mark-driven cycles; a cycle contributing no value
          // (no bleeding day, no rise mark, an open cycle) simply does
          // not feed the aggregate — the "—" card rows are for the
          // all-empty case.
          final lengthDetail = summarizeInts(lengths);
          final bleedingDetail = summarizeInts(
            cycleBleedingDurationsInDays(evaluations).nonNulls.toList(),
          );
          final riseDetail = summarizeInts(
            riseToEndDurationsInDays(evaluations).nonNulls.toList(),
          );
          final earliest = earliestFirstHigherCycleDay(evaluations);

          // The paper history folds in as plain MIN-combination at the
          // shortest/earliest surfaces: the paper figures were recorded
          // BEFORE every in-app cycle, so they are known facts at this
          // screen's point of view and a minimum of observed facts never
          // flips upward. They are single recorded facts — they do NOT
          // enter the lengths list, the distribution or the per-cycle
          // table (in-app-only surfaces below stay gated on `lengths`).
          final paperShortest = ref.watch(
            shortestCycleLengthOutsideAppProvider,
          );
          final paperEarliest = ref.watch(
            earliestFirstHigherCycleDayOutsideAppProvider,
          );
          final shortestOverall = _minFact(paperShortest, summary.shortest);
          final lengthDetailWithPaper = DescriptiveSummary(
            minimum: _minFact(paperShortest, lengthDetail.minimum),
            maximum: lengthDetail.maximum,
            average: lengthDetail.average,
            standardDeviation: lengthDetail.standardDeviation,
          );
          final earliestWithPaper = (
            any: _minFact(paperEarliest, earliest.any),
            afterMucusPeak: _minFact(paperEarliest, earliest.afterMucusPeak),
          );

          // The average/shortest/longest row renders with ONLY a paper
          // shortest present too (in-app lengths empty): a paper-only
          // user must see her recorded shortest figure instead of a
          // hidden row. The average and longest cells then dash — the
          // paper value is one fact, not a lengths distribution.
          final hasShortestRow =
              summary.lengths.isNotEmpty || paperShortest != null;

          // The upstream statistics rework's aggregate + per-cycle table
          // data: the fact rows and the first-higher-until-cycle-end
          // metric keep upstream's counting rule (each fact's span counts
          // to the next marked start; the trailing observed end is one
          // day past the last TRACKED day — see cycleFacts), rendered on
          // the shared card shape below.
          final stats = cycleStatistics(entries, marks);

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
              if (onsets.isEmpty) ...[
                // The no-data note keys on the FACT that no cycle start is
                // recorded yet (the first recorded start is the note's own
                // threshold) — never on the length count: a single still-
                // open cycle has recorded starts but no countable lengths
                // yet, and the lengths surfaces below stay hidden for it.
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
                    if (earliest.afterMucusPeak == null && earliest.any != null)
                      Text(
                        l10n.statisticsFirstHigherRealMissing,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // The fact-gated surfaces (the recorded data's own count —
              // not the lengths'): the onset list shows whenever a cycle
              // start is recorded, the per-cycle table whenever fact rows
              // exist; only the DISTRIBUTION card stays glued to the
              // lengths (it buckets lengths).
              if (onsets.isNotEmpty) ...[
                _onsetsCard(context, onsets, day),
                const SizedBox(height: 8),
              ],
              if (summary.lengths.isNotEmpty) ...[
                _distributionCard(context, buckets),
                const SizedBox(height: 8),
              ],
              if (stats.facts.isNotEmpty)
                // The table sits below ALL other statistics: one row per
                // mark-opened cycle keeps the numbers auditable against
                // the mark-driven boundaries without adding any
                // evaluation (the upstream rework's placement — kept).
                _CycleTableCard(
                  key: const ValueKey('statisticsCycleTable'),
                  facts: stats.facts,
                  day: day,
                ),
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
  // The min-combined shortest figure (paper fold included — see the
  // build method's fold comment); average and longest stay in-app-only
  // (single recorded facts never become distribution members).
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

// The histogram over the cycle lengths — the same fixed buckets the
// domain derives (bucket edges are a domain question, see there).
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

/// Re-expresses the shared cycle statistics' [MetricSummary] on the
/// screen's descriptive card shape so every metric card renders through
/// ONE shared class (no card drifts onto its own presentation).
DescriptiveSummary _descriptiveDetail(MetricSummary summary) =>
    DescriptiveSummary(
      minimum: summary.min,
      maximum: summary.max,
      average: summary.average,
      standardDeviation: summary.stdDev,
    );

/// The smallest of an optional paper-history constant and an optional
/// in-app figure — null folds to the other side (a missing fact adds
/// nothing). The MIN rule of the paper fold: see the build method.
int? _minFact(int? paperValue, int? inAppValue) {
  if (paperValue == null) return inAppValue;
  if (inAppValue == null) return paperValue;
  return paperValue < inAppValue ? paperValue : inAppValue;
}

/// The per-cycle table card: a simple bordered table (equal-width columns,
/// headers wrap) with the four exact columns the roadmap names: cycle
/// start, number of bleeding days, first higher measurement, length.
/// (The upstream statistics rework's card — kept verbatim, the shared
/// [_StatCard] shell rendering its rows.)
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
