// The day options panel of the cycle tab (Mode M, ADR-0001): tapping a
// chart day shows this panel below the chart instead of jumping straight
// to the entry form. It opens with a one-row day header: the selected
// day's locale-formatted label (expanded, so long localized names
// soft-wrap), then the compact "edit day" icon button, then the close
// button. The chips show the user-placed marks as Material FilterChips —
// ALL six of them (the five mark chips AND the temperature-exclusion
// chip) in ONE shared two-column grid of equal column widths (three
// columns when the grid spans 600 dp or more), so every row completes
// evenly and nothing ends on its own full-width bottom row. Each chip
// carries a STATIC mark-name label plus the mark type's identifying
// leading avatar icon, and the chip's selected state carries the mark
// state itself — the Material selected fill, announced as selected to
// screen readers; the canvas-drawn check on selected chips is OFF (see
// the gridChip doc comment).
//
// COMMENT EDITING IS NOT HOSTED HERE (by design): the panel distributes
// nothing but the chips above — notes live in the diary entry form (see
// cycle.dart's note row), so there is no comment surface to lay out in
// columns in the first place.
//
// The toggles are the cycle start (the authoritative cycle boundary of
// the mark-driven grouping; bleeding only suggests it — see
// lib/domain/cycle_grouping.dart and ADR-0008), the mucus peak and the
// first higher measurement (both may live on one day, two independent
// chips), and the SUZ start (from a morning or from an evening; the two
// variants are mutually exclusive per day: placing one removes the
// other). The temperature exclusion is the grid's THIRD chip, directly
// before first higher (the evaluation-based reading order: cycle start,
// mucus peak, exclusion/first higher grouped, then SUZ; it keeps its own
// keyed group cell inside the grid). The measurement time is not
// part of the panel: the chart's time row renders it on wide columns and
// the diary entry form edits it.
//
// NON-MODAL by design: the panel is owned by the Zyklus screen
// (cycle_day_panel_provider) and rendered in a fixed slot below the chart,
// NOT pushed as a route. Tapping another chart day retargets it in place —
// the first day's marks are never deselected by a dismissal — and the
// close button clears the panel explicitly (cycleDayPanelProvider).
//
// The SUZ suggestion follows the locked decision (the app SUGGESTS, the
// user PLACES): on the computed suzBegins day the panel shows a suggestion
// line naming which rule (D/E) fired, with the rule's time of day — rule D
// suggests the EVENING phrasing (the SUZ begins that evening, "gegen
// Abendessen"), rule E the MORNING phrasing (the SUZ begins that morning) —
// as long as NO user SUZ mark exists anywhere in that cycle. The computed
// SUZ is never persisted and never renders on the chart; a manual SUZ mark
// in turn never alters the arithmetic (compute-only separation, ADR-0001).
//
// HARD RULE (ADR-0001): the user places marks, the app only computes. The
// panel writes nothing derived — mark toggles go through the MarksDao
// (toggleMark to add, deleteMark to remove) via the database from
// databaseProvider; everything the panel SHOWS as evaluation data is
// recomputed from (entries, marks) at render time: the 1–6 numbering, the
// baseline value, the difference to the baseline for marked candidates
// (R7), the stopped-evaluation notice (R2) and the SUZ suggestion. No
// provider state is mutated outside the streams: a write re-emits through
// marksProvider, so the panel labels, the chart overlay and the info lines
// all update live.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/date_only.dart';
import '../domain/evaluation.dart';
import '../domain/evaluation_overlay.dart';
import '../domain/marks.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// One chip column's width inside the shared [Wrap] whose row fits
/// [columns] columns with the 8 dp wrap spacing between them (two columns
/// on phone-width grids, three from 600 dp).
double _chipWidthFor(double gridWidth, int columns) =>
    (gridWidth - 8 * (columns - 1)) / columns;

/// The shared chip column width for [maxWidth]: two columns on phone-width
/// grids, three from 600 dp (the breakpoint THE grid uses).
double _gridChipWidth(double maxWidth) =>
    _chipWidthFor(maxWidth, maxWidth >= 600 ? 3 : 2);

/// The options panel for one tapped day. Stays open across mark toggles
/// (so both marks can be placed in one go) and ACROSS retargets — the
/// tapped day lives in cycleDayPanelProvider, so a chart tap simply moves
/// the panel to the new day with the old day's marks untouched. The mark
/// chips read their selected state from the live marks stream — the state
/// visualization (selected fill; the canvas check is off, see gridChip)
/// instead of flipping set/remove labels.
final class CycleDayPanel extends ConsumerWidget {
  const CycleDayPanel({super.key, required this.day, required this.onClose});

  /// The tapped calendar day (UTC-midnight normalized).
  final DateTime day;

  /// Clears the panel (the provider write the close button and the
  /// "edit day" navigation use).
  final VoidCallback onClose;

  /// Whether the day already carries a mark of [type]. The resulting
  /// booleans decide each chip's selected state (the Material selected
  /// fill), never a contextual set/remove wording.
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
      await db.marksDao.deleteMark(day, type);
    } else {
      await db.marksDao.toggleMark(day, type);
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
      await db.marksDao.deleteMark(day, type);
      return;
    }
    // Variant switch first, then the add — never two variants on one day.
    await db.marksDao.deleteMark(day, otherType);
    await db.marksDao.addMark(day, type);
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
    await _writeMark(
      ref,
      type: CycleMarkTypes.firstHigherMeasurement,
      remove: remove,
    );
    if (remove) return;

    // The mark is written; the provider stream re-emits asynchronously, so
    // the check evaluates the exact post-write inputs (the placed mark
    // added to the current marks) instead of racing the stream.
    final placed = [
      ...marks,
      CycleMark(date: day, type: CycleMarkTypes.firstHigherMeasurement),
    ];
    final evaluations = evaluateCycles(entries, placed);
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
      // no-usable-temperature fact. The ignored-state comes from the
      // ignoreTemperature MARK (the temperature evaluation ignores the
      // day — raw flags never make a day unusable here).
      DailyEntry? markedEntry;
      for (final entry in evaluation.cycle.days) {
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
                // Remove goes through the existing mark-toggle path.
                await _writeMark(
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

  /// The old tap behavior, preserved as the panel's "edit day" action:
  /// write the pre-selected date, switch the shell to the Tagebuch tab and
  /// clear the panel (no route to pop — the panel is part of the screen).
  void _editDay(BuildContext context, WidgetRef ref) {
    ref.read(selectedDateProvider.notifier).state = DateOnly.normalize(day);
    ref.read(tabIndexProvider.notifier).state = 0; // Tagebuch tab
    onClose();
  }

  /// Whether a user SUZ mark (either variant) exists inside [evaluation]'s
  /// cycle window — the shared attribution of isDayInCycleWindow (see
  /// lib/domain/evaluation_overlay.dart).
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
        // candidates ("maybe we can show the difference for easy
        // checking").
        // TODO(user-review): the sheet info line is the MINIMUM placement
        // for the difference display — the owner left the exact placement
        // open; extra placements (labels at the chart curve) remain an
        // option and would be reviewed with the experts.
        lines.add((
          l10n.cycleSheetDifferenceInfo(
            _formatValue(locale, higher.differenceK),
          ),
          null,
        ));
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
    final marks = ref.watch(marksProvider).valueOrNull ?? const <CycleMark>[];
    final entries =
        ref.watch(dailyEntriesProvider).valueOrNull ?? const <DailyEntry>[];

    final hasPeak = _hasMark(marks, CycleMarkTypes.mucusPeakDay);
    final hasExcluded = _hasMark(marks, CycleMarkTypes.ignoreTemperature);
    final hasFirstHigher = _hasMark(
      marks,
      CycleMarkTypes.firstHigherMeasurement,
    );
    final hasSuzEvening = _hasMark(marks, CycleMarkTypes.suzEvening);
    final hasSuzMorning = _hasMark(marks, CycleMarkTypes.suzMorning);
    final hasCycleStart = _hasMark(marks, CycleMarkTypes.cycleStart);
    final infoLines = _infoLines(context, l10n, entries, marks);
    final locale = Localizations.localeOf(context).toString();

    /// One grid chip at [width]: the STATIC mark-name [label] plus the
    /// mark type's identifying leading [icon] (recovered from the
    /// pre-refactor toggle rows — flag, dot, ring, dusk, sun, crossed-out
    /// eye — identification only, never a set/remove affordance: the
    /// selected state carries set/remove now). The selected state takes
    /// the Material fill only: the canvas-drawn check is OFF — it
    /// overlapped the scrimmed avatar icon, and the fill plus the
    /// announced selection carry set/remove to screen readers, so the
    /// check adds nothing. [onSelected] receives the wanted new state;
    /// true places the mark through the unchanged write path, false
    /// removes it. Space check: at the three-column (>= 600 dp) chip
    /// width even the widest German label ("Erste höhere Messung") fits
    /// beside the icon on a single line, so no width/ellipsis fallback is
    /// needed.
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

    // A non-modal CARD in the Zyklus screen's list (below the chart, above
    // the summary table): the panel's own key (set on the widget by the
    // screen) is what the tests and the retargeting provider address.
    // Scrollability comes from the owning ListView — the old modal sheet
    // needed its own scrolling because a modal hit region cannot grow with
    // the content; a list child can.

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The day header ROW: the selected day's locale-formatted label
          // (expanded, so long localized names soft-wrap instead of
          // overflowing the row), then the compact "edit day" icon button,
          // then the explicit close affordance — the whole row replaces
          // both the old label+close line and the old full-width "edit
          // day" action above the chips, saving a whole row.
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // The date-only convention is UTC-normalized
                    // midnights; DateFormat reads the value's OWN fields —
                    // print it verbatim (a .toLocal() would show the
                    // PREVIOUS day on UTC-negative hosts).
                    DateFormat.yMMMEd(locale).format(DateOnly.normalize(day)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // The preserved old tap behavior, now the compact header
                // action between the date and the close button.
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
          // The SHARED chip grid: all six chips (the five mark chips AND
          // the temperature-exclusion chip) in ONE LayoutBuilder/Wrap of
          // equal column widths — two columns on phone-width panels and
          // three columns from 600 dp of grid width. With the exclusion in
          // the grid every row completes evenly by construction: six chips
          // make three even rows of two on a phone and two even rows of
          // three from 600 dp, instead of the old 3+2 wrap with a lone
          // below-grid exclusion row.
          // TODO(user-review): the grid stops at the three-column
          // breakpoint; a further column count on even wider surfaces
          // (>600 dp) was deliberately left out until a concrete viewport
          // asks for it.
          //
          // Reading order: cycle start, mucus peak, temperature
          // exclusion, first higher measurement, SUZ evening, SUZ
          // morning.
          //
          // No comment surface follows: the panel deliberately hosts no
          // note editing (notes live in the diary entry form — see
          // cycle.dart's note row), so there is nothing else to
          // distribute across the columns.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chipWidth = _gridChipWidth(constraints.maxWidth);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // The cycle start comes FIRST among the chips: it is the
                    // authoritative cycle-boundary mark of the mark-driven
                    // grouping (bleeding only SUGGESTS it — the diary asks on
                    // a suggested menstruation day). Settable and removable
                    // on ANY day, wherever the user judges the new cycle to
                    // begin; the chart draws the boundary line where the
                    // grouping opens the group.
                    gridChip(
                      l10n.termCycleStart,
                      hasCycleStart,
                      icon: Icons.flag_outlined,
                      key: const ValueKey('cycleSheetChip-cycleStart'),
                      (wanted) => _writeMark(
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
                        ref,
                        type: CycleMarkTypes.mucusPeakDay,
                        remove: !wanted,
                      ),
                      width: chipWidth,
                    ),
                    // The exclusion group (owner decision 2026-09-19:
                    // manual-only exclusion, made visible), the grid's
                    // THIRD chip — it sits directly before the
                    // first-higher chip (evaluation-based reading order:
                    // the exclusion groups with the temperature
                    // evaluation marks, ahead of the SUZ variants). Its
                    // keyed group cell keeps its
                    // test-visible key while sharing the same column width
                    // as every other chip, instead of opening its own
                    // full-width row below. The day's disturbance flags are
                    // NOT shown here (the chart's disturbance row already
                    // spells them per day), so on a flagged and a flag-less
                    // day alike the group is exactly this chip.
                    // Flag EDITING stays diary-side (data entry), the chip
                    // writes through the unchanged _writeMark path. A
                    // marked day's temperature is excluded from the
                    // evaluation arithmetic (the day behaves like an
                    // unmeasured one — see lib/domain/evaluation.dart);
                    // the mark does NOT affect the foreign-import
                    // cycleStart replay (drip-local bleeding continuity,
                    // any level — see lib/domain/drip_import.dart), and
                    // it IS the temperature
                    // curve's rendering key (marked days render lighter —
                    // owner decision 2026-09-19).
                    SizedBox(
                      key: const ValueKey('cycleSheetExcludeGroup'),
                      child: gridChip(
                        l10n.cycleSheetSetIgnoreTemperature,
                        hasExcluded,
                        icon: Icons.visibility_off_outlined,
                        key: const ValueKey('cycleSheetChip-ignoreTemperature'),
                        (wanted) => _writeMark(
                          ref,
                          type: CycleMarkTypes.ignoreTemperature,
                          remove: !wanted,
                        ),
                        width: chipWidth,
                      ),
                    ),
                    // The first-higher placement goes through the consistency
                    // dialog check (the dialog fires on PLACEMENT only, the
                    // unselect path removes directly).
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
                    // The SUZ start, placeable on ANY day, from a morning or
                    // from an evening. The two variants are mutually
                    // exclusive per day: placing one removes the other, and
                    // the other chip unselects on the re-render.
                    gridChip(
                      l10n.cycleSheetSuzEveningLabel,
                      hasSuzEvening,
                      icon: Icons.nightlight_outlined,
                      key: const ValueKey('cycleSheetChip-suzEvening'),
                      (wanted) => _writeSuzMark(
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
