// The mark-entry bottom sheet of the cycle tab (Mode M, ADR-0001): tapping
// a chart day opens this sheet instead of jumping straight to the entry
// form. It offers the preserved "edit day" jump (the old tap behavior) and
// the contextual set/remove toggles for the user-placed marks — the mucus
// peak, the first higher measurement (both may live on one day, two
// independent toggles) and the SUZ start (from a morning or from an
// evening; the two variants are mutually exclusive per day: placing one
// removes the other) — plus the computed info lines for the day.
//
// The SUZ suggestion follows the locked decision (the app SUGGESTS, the
// user PLACES): on the computed suzBegins day the sheet shows a suggestion
// line naming which rule (D/E) fired, with the rule's time of day — rule D
// suggests the EVENING phrasing (the SUZ begins that evening, "gegen
// Abendessen"), rule E the MORNING phrasing (the SUZ begins that morning) —
// as long as NO user SUZ mark exists anywhere in that cycle. The computed
// SUZ is never persisted and never renders on the chart; a manual SUZ mark
// in turn never alters the arithmetic (compute-only separation, ADR-0001).
//
// HARD RULE (ADR-0001): the user places marks, the app only computes. The
// sheet writes nothing derived — mark toggles go through the MarksDao
// (toggleMark to add, deleteMark to remove) via the database from
// databaseProvider; everything the sheet SHOWS as evaluation data is
// recomputed from (entries, marks) at render time: the 1–6 numbering, the
// baseline value, the difference to the baseline for marked candidates
// (R7), the stopped-evaluation notice (R2) and the SUZ suggestion. No
// provider state is mutated outside the streams: a write re-emits through
// marksProvider, so the sheet labels, the chart overlay and the info lines
// all update live.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'cycle_mark_window.dart';

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

  /// The SUZ mark-writing action: set through [MarksDao.addMark] (after
  /// removing the OTHER variant on the same day — the two variants are
  /// mutually exclusive: placing one removes the other), remove through
  /// [MarksDao.deleteMark]. Same no-invalidation pattern as [_writeMark].
  Future<void> _writeSuzMark(
    WidgetRef ref, {
    required String type,
    required String otherType,
    required bool remove,
  }) async {
    final db = await ref.read(databaseProvider.future);
    if (remove) {
      await db.marksDao.deleteMark(defaultProfileId, day, type);
      return;
    }
    // Variant switch first, then the add — never two variants on one day.
    await db.marksDao.deleteMark(defaultProfileId, day, otherType);
    await db.marksDao.addMark(defaultProfileId, day, type);
  }

  /// The first-higher mark-writing action with the owner consistency
  /// warning (owner decision 2026-09-17): when PLACING the mark leaves it
  /// INCONSISTENT — the marked day carries no measured, not-excluded
  /// temperature strictly above the baseline — a NON-BLOCKING dialog shows
  /// the arithmetic (marked value vs baseline value, or the
  /// no-usable-temperature fact) with a Keep / Remove choice; Remove goes
  /// through the existing mark-toggle path, Keep (or dismissing the
  /// dialog) leaves the just-placed mark standing. Merely OPENING the
  /// sheet for an existing inconsistent mark never pops the dialog — the
  /// persistent info-line warning covers that case (see [_infoLines]).
  /// The dialog wording states the arithmetic fact only, never a verdict:
  // TODO(user-review): the exact wording is pending the expert review.
  Future<void> _writeFirstHigherMark(
    BuildContext context,
    WidgetRef ref, {
    required bool remove,
    required List<DailyEntry> entries,
    required List<CycleMark> marks,
  }) async {
    // Captured before the write-await (the repository's established
    // pattern — nothing derived from context after an async gap).
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    await _writeMark(ref,
        type: CycleMarkTypes.firstHigherMeasurement, remove: remove);
    if (remove) return;

    // The mark is written; the provider stream re-emits asynchronously, so
    // the check evaluates the exact post-write inputs (the placed mark
    // added to the current marks) instead of racing the stream.
    final placed = [
      ...marks,
      CycleMark(
        profileId: defaultProfileId,
        date: day,
        type: CycleMarkTypes.firstHigherMeasurement,
      ),
    ];
    final evaluations =
        evaluateCycles(entries, placed, profileId: defaultProfileId);
    for (var i = 0; i < evaluations.length; i++) {
      final evaluation = evaluations[i];
      if (!isDayInCycleWindow(evaluations, i, day)) continue;
      // Only the ANCHORING mark is checked (the most recent mark of the
      // cycle drives the evaluation, see R3): a mark superseded by a later
      // first-higher mark defines no baseline of its own.
      final anchor = evaluation.firstHigherDay;
      if (anchor == null || !DateOnly.sameDay(anchor, day)) continue;
      if (evaluation.riseMarkConsistent != false) return;

      // The marked day's entry (from the evaluation's own cycle days)
      // decides the dialog body: the value-vs-baseline arithmetic, or the
      // no-usable-temperature fact.
      DailyEntry? markedEntry;
      for (final entry in evaluation.cycle.days) {
        if (DateOnly.sameDay(entry.date, day)) markedEntry = entry;
      }
      String body;
      if (markedEntry == null ||
          markedEntry.bbtC == null ||
          markedEntry.isExcluded) {
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
          title: Text(l10n.cycleSheetRiseConsistencyTitle),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cycleSheetRiseConsistencyKeep),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // Remove goes through the existing mark-toggle path.
                await _writeMark(ref,
                    type: CycleMarkTypes.firstHigherMeasurement, remove: true);
              },
              child: Text(l10n.cycleSheetRemoveFirstHigher),
            ),
          ],
        ),
      );
      return;
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

  /// Whether a user SUZ mark (either variant) exists inside [evaluation]'s
  /// cycle window — the shared attribution of isDayInCycleWindow (see
  /// cycle_mark_window.dart).
  bool _cycleHasSuzMark(
    List<CycleEvaluation> evaluations,
    int index,
    List<CycleMark> marks,
  ) {
    return marks.any((m) {
      final isSuz = m.type == CycleMarkTypes.suzEvening ||
          m.type == CycleMarkTypes.suzMorning;
      if (!isSuz) return false;
      return isDayInCycleWindow(evaluations, index, m.date);
    });
  }

  /// Locale-formatted temperature value (two fraction digits — the same
  /// mechanism the entry form and the info lines use), shared by the info
  /// lines and the rise-consistency dialog. Takes the locale string (not
  /// the context) so callers can format across an async gap.
  String _formatValue(String locale, double value) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 2,
      ).format(value);

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
  /// The rise-mark consistency warning (owner decision 2026-09-17) shows
  /// on the marked first-higher day while the mark stands INCONSISTENT
  /// (the day carries no measured, not-excluded temperature strictly above
  /// the baseline) — recomputed at render time, so later data edits that
  /// change the baseline keep it in sync. The wording states the
  /// arithmetic fact only, never a verdict (TODO(user-review): pending the
  /// expert review).
  ///
  /// On the computed suzBegins day the sheet shows the SUZ
  /// suggestion (naming which rule fired and its time of day — evening for
  /// rule D, morning for rule E) as long as NO user SUZ mark
  /// exists anywhere in that cycle — the app suggests, the user places.
  ///
  /// Empty when no evaluation data exists for the day (no marks yet, or the
  /// day lies outside every derivation window).
  ///
  /// Each entry carries the line text plus an optional test-visible key
  /// (the stopped-evaluation notice and the SUZ suggestion get one).
  List<(String, Key?)> _infoLines(BuildContext context, AppLocalizations l10n,
      List<DailyEntry> entries, List<CycleMark> marks) {
    final locale = Localizations.localeOf(context).toString();

    final lines = <(String, Key?)>[];
    final evaluations =
        evaluateCycles(entries, marks, profileId: defaultProfileId);
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
          null
        ));
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
            l10n.cycleSheetDifferenceInfo(
                _formatValue(locale, higher.differenceK)),
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
      // The SUZ suggestion (locked decision: the app suggests, the user
      // places): only on the computed suzBegins day, naming which rule
      // (D/E) fired with that rule's time of day (D → evening phrasing,
      // E → morning phrasing — the rule-to-time mapping lives on SuzRule
      // in lib/domain/evaluation.dart), and only while NO user SUZ mark
      // exists anywhere in that cycle. The computed SUZ is never persisted;
      // a manual SUZ mark never alters this arithmetic in return
      // (compute-only separation, ADR-0001).
      final suzDay = evaluation.suzBegins;
      if (suzDay != null &&
          DateOnly.sameDay(suzDay, day) &&
          !_cycleHasSuzMark(evaluations, e, marks)) {
        final line = switch (evaluation.suzRule!) {
          SuzRule.d => l10n.cycleSheetSuzSuggestionEvening,
          SuzRule.e => l10n.cycleSheetSuzSuggestionMorning,
        };
        lines.add((
          line,
          const ValueKey('cycleSheetSuzSuggestion'),
        ));
      }
      if (evaluation.evaluationStopped &&
          !DateOnly.normalize(evaluation.cycle.startDate).isAfter(day) &&
          !DateOnly.normalize(evaluation.cycle.endDate).isBefore(day)) {
        lines.add((
          l10n.cycleSheetEvaluationStopped,
          const ValueKey('cycleSheetEvaluationStopped'),
        ));
      }
      // The rise-mark consistency warning (owner decision 2026-09-17):
      // PERSISTENT while the placed first-higher mark stands inconsistent —
      // shown on the marked day (where the mark lives), recomputed at
      // render time so LATER DATA EDITS that change the baseline or remove
      // the marked day's temperature keep the warning in sync. The wording
      // states the arithmetic fact only, never a verdict.
      // TODO(user-review): the exact wording (arithmetic fact stated, no
      // "this is wrong" phrasing) is pending the expert review.
      final firstHigher = evaluation.firstHigherDay;
      if (evaluation.riseMarkConsistent == false &&
          firstHigher != null &&
          DateOnly.sameDay(firstHigher, day)) {
        lines.add((
          l10n.cycleSheetRiseInconsistent(
              _formatValue(locale, evaluation.baseline!.value)),
          const ValueKey('cycleSheetRiseConsistency'),
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
    final hasSuzEvening = _hasMark(marks, CycleMarkTypes.suzEvening);
    final hasSuzMorning = _hasMark(marks, CycleMarkTypes.suzMorning);
    final infoLines = _infoLines(context, l10n, entries, marks);

    // The recorded fact the chart glyph cannot carry: the temperature
    // measurement time — the symbol row renders only a clock glyph on days
    // with a recorded time (the tiny 24 px column cannot spell a value).
    // Sex and pain need no sheet line: their glyphs (X, B/M) already carry
    // the full binary/letter information.
    int? measuredAt;
    for (final entry in entries) {
      if (DateOnly.sameDay(entry.date, day)) {
        measuredAt = entry.measuredAtMinutes;
      }
    }

    return SafeArea(
      // Scrollable: the sheet's actions grew (peak, first higher, two SUZ
      // variants) — on short viewports the column would otherwise overflow
      // the modal sheet's maximum height.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The recorded measurement time (see above), locale-formatted
            // via the same mechanism the Tagebuch form uses.
            if (measuredAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  l10n.cycleSheetMeasuredAt(
                    MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay(
                          hour: measuredAt ~/ 60, minute: measuredAt % 60),
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            // The computed info line(s): what the arithmetic derives for this
            // day — display only, no persisted copy (ADR-0001). The
            // stopped-evaluation notice and the SUZ suggestion carry
            // test-visible keys.
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
              onTap: () => _writeFirstHigherMark(context, ref,
                  remove: hasFirstHigher, entries: entries, marks: marks),
            ),
            // The SUZ start, placeable on ANY day, from a morning or from an
            // evening. The two variants are mutually exclusive per day:
            // placing one removes the other (variant switch), and the row
            // flips to its removal label while its variant is present.
            _SheetAction(
              icon: Icons.nightlight_outlined,
              label: hasSuzEvening
                  ? l10n.cycleSheetRemoveSuzEvening
                  : l10n.cycleSheetSetSuzEvening,
              onTap: () => _writeSuzMark(ref,
                  type: CycleMarkTypes.suzEvening,
                  otherType: CycleMarkTypes.suzMorning,
                  remove: hasSuzEvening),
            ),
            _SheetAction(
              icon: Icons.wb_sunny_outlined,
              label: hasSuzMorning
                  ? l10n.cycleSheetRemoveSuzMorning
                  : l10n.cycleSheetSetSuzMorning,
              onTap: () => _writeSuzMark(ref,
                  type: CycleMarkTypes.suzMorning,
                  otherType: CycleMarkTypes.suzEvening,
                  remove: hasSuzMorning),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
