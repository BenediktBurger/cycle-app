// The cycle screen's evaluation table (the paper's bottom summary): one ROW
// per attribute — Zykluslänge (days between consecutive marked cycle
// starts), Mensbeginn, Mensende, mucus-peak day, SUZ begin + rule (D/E) and
// the evaluation status — and one COLUMN per cycle group. Everything is
// computed purely at render time from the CycleEvaluation list the screen
// derives with evaluateCycles (ADR-0001: nothing here is persisted — the
// derived artifacts live only in the widget tree). Missing values render as
// the "—" dash, the same unset marker the diary's observation cells use.
// Columns beyond the viewport scroll horizontally so the attribute rows stay
// readable instead of being squeezed.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../l10n/app_localizations.dart';

final class CycleSummaryTable extends StatelessWidget {
  const CycleSummaryTable({super.key, required this.evaluations});

  /// The per-cycle evaluations in cycle-group order, as [evaluateCycles]
  /// returns them. Each carries its cycle group (days, onset flag), so the
  /// bleeding attributes and the cycle-length arithmetic need no separate
  /// entries parameter.
  final List<CycleEvaluation> evaluations;

  /// The attribute-label column's width.
  static const double _labelWidth = 120;

  /// One cycle column's width: generous enough for a localized date and a
  /// wrapped status text, so the rows stay readable at any cycle count.
  static const double _columnWidth = 110;

  /// The missing-value marker, mirroring the diary's unset observation
  /// markers ("mucusSignUnset", "cervixPositionUnset", …).
  static const String _missing = '—';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final columns = [
      for (var i = 0; i < evaluations.length; i++)
        _columnFor(evaluations, i, l10n, locale),
    ];

    Widget cell(String attribute, int index, Widget child) => SizedBox(
          key: ValueKey('cycleSummaryCell-$attribute-$index'),
          width: _columnWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: child,
          ),
        );

    Widget attributeRow(
            String label, String attribute, List<String?> values) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(label),
              ),
            ),
            for (var i = 0; i < values.length; i++)
              cell(attribute, i, Text(values[i] ?? _missing)),
          ],
        );

    return SingleChildScrollView(
      key: const ValueKey('cycleSummaryScroll'),
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The column headers: one per cycle group ("Zyklus 1 …", the
          // leading group by its Tagebuch-style label).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: _labelWidth),
              for (var i = 0; i < columns.length; i++)
                SizedBox(
                  key: ValueKey('cycleSummaryHeader-$i'),
                  width: _columnWidth,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      columns[i].header,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
            ],
          ),
          attributeRow(
            l10n.cycleSummaryCycleLength,
            'length',
            [for (final c in columns) c.length],
          ),
          attributeRow(
            l10n.cycleSummaryPeriodStart,
            'start',
            [for (final c in columns) c.start],
          ),
          attributeRow(
            l10n.cycleSummaryPeriodEnd,
            'end',
            [for (final c in columns) c.end],
          ),
          attributeRow(
            l10n.cycleSummaryPeak,
            'peak',
            [for (final c in columns) c.peak],
          ),
          attributeRow(
            l10n.cycleSummarySuz,
            'suz',
            [for (final c in columns) c.suz],
          ),
          attributeRow(
            l10n.cycleSummaryStatus,
            'status',
            [for (final c in columns) c.status],
          ),
        ],
      ),
    );
  }

  /// One column's derived values. The bleeding attributes follow the
  /// grouping (lib/domain/cycle_grouping.dart): the leading group (it
  /// predates the first cycleStart mark, `startsAtMenstruation == false`)
  /// shows the dash for period start, period end and cycle length —
  /// consistent with the cycle-counting TODO(user-review) on the chart's
  /// day header. The evaluation attributes (peak, SUZ, status) come from
  /// the CycleEvaluation of the group.
  _CycleColumn _columnFor(
    List<CycleEvaluation> evaluations,
    int index,
    AppLocalizations l10n,
    String locale,
  ) {
    final evaluation = evaluations[index];
    final cycle = evaluation.cycle;
    final isOnsetGroup = cycle.startsAtMenstruation;

    String dayLabel(DateTime? date) => date == null
        ? _missing
        : DateFormat.yMd(locale).format(DateOnly.normalize(date).toLocal());

    // The group's own marked start (the leading group has none).
    final onset =
        isOnsetGroup ? DateOnly.normalize(cycle.startDate) : null;
    // The next marked start: only a following marked group counts (the
    // leading group is always the first group, so any successor of a
    // marked group is a marked group itself).
    final nextOnset =
        index + 1 < evaluations.length && evaluations[index + 1].cycle.startsAtMenstruation
            ? DateOnly.normalize(evaluations[index + 1].cycle.startDate)
            : null;

    // Mensende: the last day of the group whose bleeding level is >= 2
    // (menstruation-level bleeding; spotting continuations do not extend
    // it). TODO(user-review): the cheat sheet does not spell out how
    // spotting after the last bleeding day should count — if the experts
    // want spotting to extend the period end, this rule changes here and
    // only here.
    DateTime? periodEnd;
    if (isOnsetGroup) {
      for (final day in cycle.days) {
        if (day.bleeding.level >= 2) periodEnd = DateOnly.normalize(day.date);
      }
    }

    final suzText = evaluation.suzBegins == null
        ? null
        : _ruleText(evaluation.suzRule!, l10n);

    return _CycleColumn(
      header: isOnsetGroup
          ? // TODO(user-review): the "Zyklus n" label is a first draft — the
            // experts may want a different caption (or numbering direction).
            l10n.cycleSummaryColumn(_onsetNumber(evaluations, index))
          // The leading group predates the first cycleStart mark: it is
          // not a numbered cycle, so it keeps the Tagebuch's leading-group
          // label with its (knowable) end day.
          : l10n.cycleGroupLeading(dayLabel(cycle.endDate)),
      length: onset == null || nextOnset == null
          ? null
          : l10n.cycleDays(DateOnly.daysBetween(nextOnset, onset)),
      start: onset == null ? null : dayLabel(onset),
      end: periodEnd == null ? null : dayLabel(periodEnd),
      peak: dayLabel(evaluation.mucusPeakDay),
      suz: evaluation.suzBegins == null
          ? null
          : '${dayLabel(evaluation.suzBegins)} · $suzText',
      status: evaluation.evaluationStopped
          ? l10n.cycleSheetEvaluationStopped
          : evaluation.suzBegins == null
              ? null
              : '${l10n.cycleSummarySuzFrom(dayLabel(evaluation.suzBegins))} · $suzText',
    );
  }

  /// The 1-based number of the onset group at [index], counting the onset
  /// groups only (the leading group carries no cycle number).
  int _onsetNumber(List<CycleEvaluation> evaluations, int index) {
    var number = 0;
    for (var i = 0; i <= index; i++) {
      if (evaluations[i].cycle.startsAtMenstruation) number++;
    }
    return number;
  }

  /// The localized rule-to-time phrasing of the SUZ cells: rule D begins
  /// the SUZ in the evening of the trigger day, rule E in the morning (the
  /// same mapping the day sheet's suggestion phrases carry).
  // TODO(user-review): the rule phrasing ("Regel D (gegen Abend)") is a
  // first draft; the status wording as a whole is a review candidate.
  String _ruleText(SuzRule rule, AppLocalizations l10n) =>
      switch (rule) {
        SuzRule.d => l10n.cycleSummarySuzEvening,
        SuzRule.e => l10n.cycleSummarySuzMorning,
      };
}

/// One cycle column's pre-rendered strings (localized at build time; null
/// where the value is missing and the cell renders the dash).
final class _CycleColumn {
  const _CycleColumn({
    required this.header,
    required this.length,
    required this.start,
    required this.end,
    required this.peak,
    required this.suz,
    required this.status,
  });

  final String header;
  final String? length;
  final String? start;
  final String? end;
  final String? peak;
  final String? suz;
  final String? status;
}
