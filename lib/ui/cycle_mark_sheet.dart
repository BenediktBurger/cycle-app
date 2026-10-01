// The cycle tab's day options panel: tapping a chart day shows this
// non-modal panel below the chart instead of jumping straight to the
// entry form. HARD RULE (ADR-0001): the user places all marks, the app
// only computes — writes go through the MarksDao, everything shown as
// evaluation data is recomputed from the entries + marks streams at
// render time. Layout, suggestion and exclusion-posture details live in
// docs/dev-notes.md ("Cycle day mark sheet").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/cycle_grouping.dart';
import '../domain/date_only.dart';
import '../domain/decimal_display.dart';
import '../domain/evaluation.dart';
import '../domain/evaluation_overlay.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'stream_error.dart';

double _chipWidthFor(double gridWidth, int columns) =>
    (gridWidth - 8 * (columns - 1)) / columns;

/// Chip column width for a grid of [maxWidth]: two columns below 600 dp
/// of grid width, three from 600 dp.
double _gridChipWidth(double maxWidth) =>
    _chipWidthFor(maxWidth, maxWidth >= 600 ? 3 : 2);

/// The options panel for one tapped day. Stays open across mark toggles
/// (so both marks can be placed in one go) and ACROSS retargets — the
/// tapped day lives in cycleDayPanelProvider, so a chart tap moves the
/// panel to the new day with the old day's marks untouched. The chips
/// read their selected state from the live marks stream.
final class CycleDayPanel extends ConsumerWidget {
  const CycleDayPanel({super.key, required this.day, required this.onClose});

  /// The tapped calendar day (UTC-midnight normalized).
  final DateTime day;

  final VoidCallback onClose;

  /// Whether the day already carries a mark of [type] — the chip's
  /// selected state, never a contextual set/remove wording.
  bool _hasMark(List<CycleMark> marks, String type) =>
      marks.any((m) => m.type == type && DateOnly.sameDay(m.date, day));

  /// The mark-writing action: set through [MarksDao.toggleMark], remove
  /// through [MarksDao.deleteMark]; marksProvider re-emits after the
  /// write. Returns whether the write completed — on failure the caller
  /// must not build follow-up UI.
  Future<bool> _writeMark(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    required bool remove,
  }) async {
    // Captured before the write-await: nothing derived from context
    // after the async gap.
    final l10n = AppLocalizations.of(context);
    try {
      final db = await ref.read(databaseProvider.future);
      if (remove) {
        await db.marksDao.deleteMark(day, type);
      } else {
        await db.marksDao.toggleMark(day, type);
      }
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
      return false;
    }
    return true;
  }

  /// The SUZ mark-writing action: set through [MarksDao.addMark], remove
  /// through [MarksDao.deleteMark]. The two variants are mutually
  /// exclusive per day, so the delete-and-add variant switch is ONE
  /// all-or-nothing transaction — a failure leaves the previous variant
  /// standing.
  Future<bool> _writeSuzMark(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    required String otherType,
    required bool remove,
  }) async {
    // Captured before the write-await.
    final l10n = AppLocalizations.of(context);
    try {
      final db = await ref.read(databaseProvider.future);
      if (remove) {
        await db.marksDao.deleteMark(day, type);
      } else {
        await db.transaction(() async {
          await db.marksDao.deleteMark(day, otherType);
          await db.marksDao.addMark(day, type);
        });
      }
    } catch (_) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
      return false;
    }
    return true;
  }

  /// The first-higher mark-writing action with the owner consistency
  /// warning (owner decision 2026-09-17): placing a mark that is
  /// INCONSISTENT — the day carries no measured, not-excluded temperature
  /// strictly above the baseline — pops a NON-BLOCKING Keep/Remove dialog
  /// stating the arithmetic fact only, never a verdict (wording
  /// TODO(user-review)).
  Future<void> _writeFirstHigherMark(
    BuildContext context,
    WidgetRef ref, {
    required bool remove,
    required List<DailyEntry> entries,
    required List<CycleMark> marks,
  }) async {
    // Captured before the write-await.
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final written = await _writeMark(
      context,
      ref,
      type: CycleMarkTypes.firstHigherMeasurement,
      remove: remove,
    );
    // Nothing to check when the write failed (reported by [_writeMark]).
    if (!written || remove) return;

    // The provider stream re-emits asynchronously, so the check evaluates
    // the placed mark added to the current marks instead of racing it.
    final placed = [
      ...marks,
      CycleMark(date: day, type: CycleMarkTypes.firstHigherMeasurement),
    ];
    final evaluations = evaluateCycles(entries, placed);
    for (var i = 0; i < evaluations.length; i++) {
      final evaluation = evaluations[i];
      if (!isDayInCycleWindow(evaluations, i, day)) continue;
      // Only the ANCHORING mark is checked (R3): a superseded earlier
      // mark defines no baseline of its own.
      final anchor = evaluation.firstHigherDay;
      if (anchor == null || !DateOnly.sameDay(anchor, day)) continue;
      if (evaluation.riseMarkConsistent != false) return;

      // The day's entry (from the evaluation's own cycle) decides the
      // dialog body; the excluded-state comes from the ignoreTemperature
      // mark — raw flags never make a day unusable here.
      DailyEntry? markedEntry;
      for (final entry in cycleSpanDays(evaluation.cycle)) {
        if (DateOnly.sameDay(entry.date, day)) {
          markedEntry = entry;
          break;
        }
      }
      final dayExcluded = marks.any(
        (m) =>
            m.type == CycleMarkTypes.ignoreTemperature &&
            DateOnly.sameDay(m.date, day),
      );
      String body;
      if (markedEntry == null || markedEntry.bbtC == null || dayExcluded) {
        body = l10n.cycleSheetRiseConsistencyNoValue;
      } else {
        body = l10n.cycleSheetRiseConsistencyBelow(
          _formatValue(locale, markedEntry.bbtC!),
          _formatValue(locale, evaluation.baseline!.value),
        );
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.termFirstHigher),
          content: Text(body),
          actions: [
            TextButton(
              key: const ValueKey('cycleSheetRiseKeepButton'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cycleSheetRiseConsistencyKeep),
            ),
            TextButton(
              key: const ValueKey('cycleSheetRiseRemoveButton'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _writeMark(
                  context,
                  ref,
                  type: CycleMarkTypes.firstHigherMeasurement,
                  remove: true,
                );
              },
              child: Text(l10n.cycleSheetRemoveFirstHigher),
            ),
          ],
        ),
      );
      return;
    }
  }

  /// Writes the pre-selected date, switches the shell to the Tagebuch tab
  /// and clears the panel (no route to pop — the panel is part of the
  /// screen).
  void _editDay(BuildContext context, WidgetRef ref) {
    ref.read(selectedDateProvider.notifier).set(DateOnly.normalize(day));
    ref.read(tabIndexProvider.notifier).set(0); // Tagebuch tab
    onClose();
  }

  /// Whether a user SUZ mark (either variant) exists inside the cycle
  /// window of the evaluation at [index].
  bool _cycleHasSuzMark(
    List<CycleEvaluation> evaluations,
    int index,
    List<CycleMark> marks,
  ) {
    return marks.any((m) {
      final isSuz =
          m.type == CycleMarkTypes.suzEvening ||
          m.type == CycleMarkTypes.suzMorning;
      if (!isSuz) return false;
      return isDayInCycleWindow(evaluations, index, m.date);
    });
  }

  /// Locale-formatted value (two fraction digits); takes the locale
  /// string, not the context, so callers can format across an async gap.
  String _formatValue(String locale, double value) =>
      formatDecimal(value, locale: locale, decimalDigits: 2);

  /// The computed info lines for [day] (empty when no evaluation data
  /// exists for it), each the line text plus an optional test-visible key.
  /// A day can carry several facts at once: the 1-6 low number, the
  /// baseline value, the marked candidate's baseline difference (R7) plus
  /// a circle's ordinal (arrow ordinals are curve-rendering input only),
  /// the SUZ suggestion, the stopped-evaluation notice (R2) and the
  /// inconsistent rise-mark warning.
  ///
  /// TODO(user-review): the R2 notice surfaces on the whole cycle rather
  /// than only the day after the break — the domain does not report the
  /// break day.
  List<(String, Key?)> _infoLines(
    BuildContext context,
    AppLocalizations l10n,
    List<DailyEntry> entries,
    List<CycleMark> marks,
  ) {
    final locale = Localizations.localeOf(context).toString();

    final lines = <(String, Key?)>[];
    final evaluations = evaluateCycles(entries, marks);
    for (var e = 0; e < evaluations.length; e++) {
      final evaluation = evaluations[e];
      for (final low in evaluation.numberedLows) {
        if (DateOnly.sameDay(low.date, day)) {
          lines.add((l10n.cycleSheetLowInfo(low.number), null));
        }
      }
      final baseline = evaluation.baseline;
      if (baseline != null && DateOnly.sameDay(baseline.date, day)) {
        lines.add((
          l10n.cycleSheetBaselineInfo(_formatValue(locale, baseline.value)),
          null,
        ));
      }
      for (final higher in evaluation.higherMeasurements) {
        if (!DateOnly.sameDay(higher.date, day)) continue;
        // R7: the difference to the baseline, for circled AND arrowed
        // candidates.
        // TODO(user-review): the sheet info line is the minimum placement
        // for the difference display; extra placements (chart-curve
        // labels) remain an option for the expert review.
        lines.add((
          l10n.cycleSheetDifferenceInfo(
            _formatValue(locale, higher.differenceK),
          ),
          null,
        ));
        if (higher.markKind == MarkKind.circle && higher.ordinal != null) {
          // Unnumbered circles (beyond the per-kind cap) stay without the
          // numbering line.
          lines.add((l10n.cycleSheetCircledInfo(higher.ordinal!), null));
        }
      }
      // The SUZ suggestion (locked decision: the app suggests, the user
      // places) — shown while NO user SUZ mark exists anywhere in the
      // cycle; the computed SUZ is never persisted.
      final suzDay = evaluation.suzBegins;
      if (suzDay != null &&
          DateOnly.sameDay(suzDay, day) &&
          !_cycleHasSuzMark(evaluations, e, marks)) {
        final line = switch (evaluation.suzRule!) {
          SuzRule.d => l10n.cycleSheetSuzSuggestionEvening,
          SuzRule.e => l10n.cycleSheetSuzSuggestionMorning,
        };
        lines.add((line, const ValueKey('cycleSheetSuzSuggestion')));
      }
      if (evaluation.evaluationStopped &&
          !DateOnly.normalize(evaluation.cycle.startDate).isAfter(day) &&
          !DateOnly.normalize(evaluation.cycle.endDate).isBefore(day)) {
        lines.add((
          l10n.cycleSheetEvaluationStopped,
          const ValueKey('cycleSheetEvaluationStopped'),
        ));
      }
      // The persistent inconsistency warning (owner decision
      // 2026-09-17), recomputed at render time so later data edits keep
      // it in sync.
      // TODO(user-review): the exact wording is pending the expert review.
      final firstHigher = evaluation.firstHigherDay;
      if (evaluation.riseMarkConsistent == false &&
          firstHigher != null &&
          DateOnly.sameDay(firstHigher, day)) {
        lines.add((
          l10n.cycleSheetRiseInconsistent(
            _formatValue(locale, evaluation.baseline!.value),
          ),
          const ValueKey('cycleSheetRiseConsistency'),
        ));
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The marks watch stays unmasked: a failed stream must surface in the
    // grid area instead of all-unselected chips implying "not placed".
    final marksAsync = ref.watch(marksProvider);
    // The entries read stays masked: the panel is reachable only from the
    // cycle screen's data branch, so a session-long entries error cannot
    // open it.
    final entries =
        ref.watch(dailyEntriesProvider).value ?? const <DailyEntry>[];
    final marks = marksAsync.value ?? const <CycleMark>[];

    final hasPeak = _hasMark(marks, CycleMarkTypes.mucusPeakDay);
    final hasExcluded = _hasMark(marks, CycleMarkTypes.ignoreTemperature);
    final hasFirstHigher = _hasMark(
      marks,
      CycleMarkTypes.firstHigherMeasurement,
    );
    final hasSuzEvening = _hasMark(marks, CycleMarkTypes.suzEvening);
    final hasSuzMorning = _hasMark(marks, CycleMarkTypes.suzMorning);
    final hasCycleStart = _hasMark(marks, CycleMarkTypes.cycleStart);
    // With the marks stream in error the info lines would compute from no
    // data, so they stay hidden while the grid area shows the retry
    // surface.
    final infoLines = marksAsync.hasError
        ? const <(String, Key?)>[]
        : _infoLines(context, l10n, entries, marks);
    final locale = Localizations.localeOf(context).toString();

    /// One grid chip: the STATIC mark-name [label] plus the mark type's
    /// identifying leading [icon]. The selected state carries set/remove
    /// (Material fill, announced to screen readers); the canvas-drawn
    /// check is off.
    // TODO(user-review): removing the check mark is an owner-visible
    // appearance decision — confirm with the experts that the selected
    // fill alone reads clearly as "placed".
    Widget gridChip(
      String label,
      bool selected,
      ValueChanged<bool> onSelected, {
      required IconData icon,
      Key? key,
      double? width,
    }) => SizedBox(
      width: width,
      child: FilterChip(
        key: key,
        label: Text(label),
        avatar: Icon(icon),
        selected: selected,
        showCheckmark: false,
        onSelected: onSelected,
      ),
    );

    // A non-modal card in the Zyklus screen's list; scrollability comes
    // from the owning ListView, and the panel's own key is what the tests
    // and the retargeting provider address.
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The day header row: the date label (expanded, so long
          // localized names soft-wrap), then "edit day", then close.
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // Date-only values are UTC-normalized midnights —
                    // print verbatim; a .toLocal() shows the previous day
                    // on UTC-negative hosts.
                    DateFormat.yMMMEd(locale).format(DateOnly.normalize(day)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('cycleDayPanelEdit'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.cycleSheetEditDay,
                  onPressed: () => _editDay(context, ref),
                ),
                IconButton(
                  key: const ValueKey('cycleDayPanelClose'),
                  icon: const Icon(Icons.close),
                  tooltip: l10n.cycleDayPanelClose,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Computed per build — display only, nothing persisted (ADR-0001).
          for (final (line, key) in infoLines)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                line,
                key: key,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          // The shared chip grid: all six chips in ONE Wrap of equal
          // column widths — two columns on phone-width panels, three from
          // 600 dp — so every row completes evenly.
          // TODO(user-review): a further column count on even wider
          // surfaces (>600 dp) is left out until a concrete viewport asks
          // for it.
          //
          // Reading order: cycle start, mucus peak, temperature
          // exclusion, first higher measurement, SUZ evening, SUZ
          // morning.
          if (marksAsync.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: StreamLoadError(
                scope: 'marks',
                onRetry: () => ref.invalidate(marksProvider),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: LayoutBuilder(
                // The chip closures capture the panel's context, not the
                // builder's: the grid element is recomputed whenever the
                // info-line count above changes, so a captured builder
                // context could go defunct while the closure still runs.
                builder: (_, constraints) {
                  final chipWidth = _gridChipWidth(constraints.maxWidth);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // The authoritative cycle-boundary mark of the
                      // mark-driven grouping (bleeding only suggests it —
                      // lib/domain/cycle_grouping.dart); settable on any
                      // day.
                      gridChip(
                        l10n.termCycleStart,
                        hasCycleStart,
                        icon: Icons.flag_outlined,
                        key: const ValueKey('cycleSheetChip-cycleStart'),
                        (wanted) => _writeMark(
                          context,
                          ref,
                          type: CycleMarkTypes.cycleStart,
                          remove: !wanted,
                        ),
                        width: chipWidth,
                      ),
                      gridChip(
                        l10n.termMucusPeak,
                        hasPeak,
                        icon: Icons.circle,
                        key: const ValueKey('cycleSheetChip-mucusPeakDay'),
                        (wanted) => _writeMark(
                          context,
                          ref,
                          type: CycleMarkTypes.mucusPeakDay,
                          remove: !wanted,
                        ),
                        width: chipWidth,
                      ),
                      // Manual-only exclusion (owner decision
                      // 2026-09-19), the grid's third chip; the day's
                      // disturbance flags are not shown here (the chart's
                      // disturbance row spells them, flag editing stays
                      // diary-side). The mark is the temperature curve's
                      // dimming key (owner decision 2026-09-19) and does
                      // not affect the drip-import cycleStart replay
                      // (lib/domain/drip_import.dart).
                      SizedBox(
                        key: const ValueKey('cycleSheetExcludeGroup'),
                        child: gridChip(
                          l10n.cycleSheetSetIgnoreTemperature,
                          hasExcluded,
                          icon: Icons.visibility_off_outlined,
                          key: const ValueKey(
                            'cycleSheetChip-ignoreTemperature',
                          ),
                          (wanted) => _writeMark(
                            context,
                            ref,
                            type: CycleMarkTypes.ignoreTemperature,
                            remove: !wanted,
                          ),
                          width: chipWidth,
                        ),
                      ),
                      // Placement goes through the consistency dialog
                      // check; deselect removes directly.
                      gridChip(
                        l10n.termFirstHigher,
                        hasFirstHigher,
                        icon: Icons.adjust,
                        key: const ValueKey(
                          'cycleSheetChip-firstHigherMeasurement',
                        ),
                        (wanted) => _writeFirstHigherMark(
                          context,
                          ref,
                          remove: !wanted,
                          entries: entries,
                          marks: marks,
                        ),
                        width: chipWidth,
                      ),
                      // SUZ start from a morning or an evening, placeable
                      // on any day; the two variants are mutually
                      // exclusive per day.
                      gridChip(
                        l10n.cycleSheetSuzEveningLabel,
                        hasSuzEvening,
                        icon: Icons.nightlight_outlined,
                        key: const ValueKey('cycleSheetChip-suzEvening'),
                        (wanted) => _writeSuzMark(
                          context,
                          ref,
                          type: CycleMarkTypes.suzEvening,
                          otherType: CycleMarkTypes.suzMorning,
                          remove: !wanted,
                        ),
                        width: chipWidth,
                      ),
                      gridChip(
                        l10n.cycleSheetSuzMorningLabel,
                        hasSuzMorning,
                        icon: Icons.wb_sunny_outlined,
                        key: const ValueKey('cycleSheetChip-suzMorning'),
                        (wanted) => _writeSuzMark(
                          context,
                          ref,
                          type: CycleMarkTypes.suzMorning,
                          otherType: CycleMarkTypes.suzEvening,
                          remove: !wanted,
                        ),
                        width: chipWidth,
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
