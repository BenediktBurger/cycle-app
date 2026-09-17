// The mark-entry bottom sheet of the cycle tab (Mode M, ADR-0001): tapping
// a chart day opens this sheet instead of jumping straight to the entry
// form. It offers the preserved "edit day" jump (the old tap behavior) and
// the contextual set/remove toggles for the two user-placed marks — the
// mucus peak and the first higher measurement (both may live on one day,
// two independent toggles) — plus the computed info lines for the day.
//
// HARD RULE (ADR-0001): the user places marks, the app only computes. The
// sheet writes nothing derived — mark toggles go through the MarksDao
// (toggleMark to add, deleteMark to remove) via the database from
// databaseProvider; everything the sheet SHOWS as evaluation data is
// recomputed from (entries, marks) at render time: the 1–6 numbering, the
// baseline value, the difference to the baseline for marked candidates
// (R7) and the stopped-evaluation notice (R2). No provider state is
// mutated outside the streams: a write re-emits through marksProvider, so
// the sheet labels, the chart overlay and the info lines all update live.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// Opens the mark-entry sheet for one calendar day of the cycle chart.
/// [day] must already be a UTC-midnight value (DateOnly convention — the
/// chart's day mapping produces exactly that).
Future<void> showCycleDaySheet(BuildContext context, {required DateTime day}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => CycleDaySheet(day: day),
  );
}

/// One row of the sheet: an icon, a label and the action behind it.
final class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}

/// The sheet's content for one tapped day. Stays open across mark toggles
/// (so both marks can be placed in one go); the labels derive from the live
/// marks stream, flipping to the "remove" wording as soon as the mark exists.
final class CycleDaySheet extends ConsumerWidget {
  const CycleDaySheet({super.key, required this.day});

  /// The tapped calendar day (UTC-midnight normalized).
  final DateTime day;

  /// Whether the day already carries a mark of [type] (the user-placed
  /// marks decide the contextual set/remove wording).
  bool _hasMark(List<CycleMark> marks, String type) =>
      marks.any((m) => m.type == type && DateOnly.sameDay(m.date, day));

  /// The mark-writing action: set through [MarksDao.toggleMark] (absent ->
  /// added), remove through [MarksDao.deleteMark] (present -> deleted).
  /// No provider invalidation: marksProvider sits on a drift watch stream,
  /// which re-emits after the write (same pattern as the diary's saves).
  Future<void> _writeMark(
    WidgetRef ref, {
    required String type,
    required bool remove,
  }) async {
    final db = await ref.read(databaseProvider.future);
    if (remove) {
      await db.marksDao.deleteMark(defaultProfileId, day, type);
    } else {
      await db.marksDao.toggleMark(defaultProfileId, day, type);
    }
  }

  /// The old tap behavior, preserved as the sheet's "edit day" action:
  /// write the pre-selected date and switch the shell to the Tagebuch tab,
  /// then close the sheet.
  void _editDay(BuildContext context, WidgetRef ref) {
    ref.read(selectedDateProvider.notifier).state = DateOnly.normalize(day);
    ref.read(tabIndexProvider.notifier).state = 0; // Tagebuch tab
    Navigator.of(context).pop();
  }

  /// The computed info lines for [day], in evaluation order: the 1-6 low
  /// number, the baseline value (the day the baseline runs through), and —
  /// for a MARKED candidate of that day (R7) — the difference to the
  /// baseline plus, for a CIRCLE, its circle ordinal. ARROW ordinals stay
  /// out of the sheet: they are curve-rendering input only (see
  /// HigherMeasurement.ordinal in lib/domain/evaluation.dart), so only
  /// circles get a numbering line here. A day can carry several facts at
  /// once (the baseline day is one of the six lows).
  ///
  /// A cycle whose automatic evaluation STOPPED mid-sequence (R2) shows the
  /// re-mark notice on every day of that cycle: the arithmetic will not
  /// continue by itself, the user must place a new first-higher mark.
  /// TODO(user-review): the notice surfaces on the whole cycle rather than
  /// only on the day after the break — the domain does not report the break
  /// day, and the whole-cycle notice reads clearly enough in practice.
  ///
  /// Empty when no evaluation data exists for the day (no marks yet, or the
  /// day lies outside every derivation window).
  ///
  /// Each entry carries the line text plus an optional test-visible key
  /// (the stopped-evaluation notice gets one).
  List<(String, Key?)> _infoLines(BuildContext context, AppLocalizations l10n,
      List<DailyEntry> entries, List<CycleMark> marks) {
    final locale = Localizations.localeOf(context).toString();
    String formatValue(double value) => NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: 2,
        ).format(value);

    final lines = <(String, Key?)>[];
    for (final evaluation
        in evaluateCycles(entries, marks, profileId: defaultProfileId)) {
      for (final low in evaluation.numberedLows) {
        if (DateOnly.sameDay(low.date, day)) {
          lines.add((l10n.cycleSheetLowInfo(low.number), null));
        }
      }
      final baseline = evaluation.baseline;
      if (baseline != null && DateOnly.sameDay(baseline.date, day)) {
        lines.add(
            (l10n.cycleSheetBaselineInfo(formatValue(baseline.value)), null));
      }
      for (final higher in evaluation.higherMeasurements) {
        if (!DateOnly.sameDay(higher.date, day)) continue;
        // R7: the difference to the baseline, for circled AND arrowed
        // candidates ("maybe we can show the difference for easy
        // checking").
        // TODO(user-review): the sheet info line is the MINIMUM placement
        // for the difference display — the owner left the exact placement
        // open; extra placements (labels at the chart curve) remain an
        // option and would be reviewed with the experts.
        lines.add(
          (
            l10n.cycleSheetDifferenceInfo(formatValue(higher.differenceK)),
            null
          ),
        );
        if (higher.markKind == MarkKind.circle && higher.ordinal != null) {
          // Unnumbered circles (beyond the per-kind cap) stay without the
          // numbering line — the difference line above still shows. Arrow
          // ordinals never surface here (curve-rendering input only).
          lines.add((l10n.cycleSheetCircledInfo(higher.ordinal!), null));
        }
      }
      if (evaluation.evaluationStopped &&
          !day.isBefore(evaluation.cycle.startDate) &&
          !DateOnly.normalize(evaluation.cycle.endDate).isBefore(day)) {
        lines.add((
          l10n.cycleSheetEvaluationStopped,
          const ValueKey('cycleSheetEvaluationStopped'),
        ));
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final marks = ref.watch(marksProvider).valueOrNull ?? const <CycleMark>[];
    final entries =
        ref.watch(dailyEntriesProvider).valueOrNull ?? const <DailyEntry>[];

    final hasPeak = _hasMark(marks, CycleMarkTypes.mucusPeakDay);
    final hasFirstHigher =
        _hasMark(marks, CycleMarkTypes.firstHigherMeasurement);
    final infoLines = _infoLines(context, l10n, entries, marks);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The computed info line(s): what the arithmetic derives for this
          // day — display only, no persisted copy (ADR-0001). The
          // stopped-evaluation notice carries a test-visible key.
          for (final (line, key) in infoLines)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                line,
                key: key,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          _SheetAction(
            icon: Icons.edit_outlined,
            label: l10n.cycleSheetEditDay,
            onTap: () => _editDay(context, ref),
          ),
          _SheetAction(
            // The action icons are affordances for the two user-placed
            // marks: the circle outline for the mucus peak (which renders
            // as a solid dot in the symbol row, R6) and the circled dot
            // for the first higher measurement.
            icon: Icons.radio_button_unchecked,
            label: hasPeak
                ? l10n.cycleSheetRemoveMucusPeak
                : l10n.cycleSheetSetMucusPeak,
            onTap: () => _writeMark(ref,
                type: CycleMarkTypes.mucusPeakDay, remove: hasPeak),
          ),
          _SheetAction(
            icon: Icons.adjust,
            label: hasFirstHigher
                ? l10n.cycleSheetRemoveFirstHigher
                : l10n.cycleSheetSetFirstHigher,
            onTap: () => _writeMark(ref,
                type: CycleMarkTypes.firstHigherMeasurement,
                remove: hasFirstHigher),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
