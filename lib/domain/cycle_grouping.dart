// Cycle grouping: split a stream of tracked days into cycles.
//
// Boundary rule (decided — the cycle start is a user mark):
//
//   A new cycle group opens at the first tracked day on/after a user-placed
//   `cycleStart` mark (CycleMarkTypes.cycleStart). The mark
//   is AUTHORITATIVE and binds wherever it sits — including on days without
//   menstruation bleeding, on excluded (interrupted) days, and on untracked
//   gap days. Bleeding never creates a boundary by itself; it only SUGGESTS
//   a cycle start via [isSuggestedCycleStart] (derived marks — a
//   foreign-import derivation only, since the diary's bleeding-suggested
//   prompt became the entry form's explicit cycle-start switch).
//   The cycle's START DATE is the opening mark's OWN date — when that mark
//   lies on an untracked gap day, the start sits inside the gap and the
//   untracked gap days belong to the new cycle (they are not in
//   [Cycle.days]). Among multiple marks on/before a group's first tracked
//   day the NEWEST one supersedes the older ones (the re-marking rule of
//   the mark sheet). A leading group of entries that predate the first
//   mark keeps `startsAtMenstruation == false` and anchors on its first
//   tracked day. Marks without any tracked day after them still open a
//   group — a data-less one (see the span rule).
//
// Span rule (owner requirement, app-wide — "a cycle goes on until the next
// cycle mark, regardless whether there is data"): a cycle's day list is
// NOT just its tracked days. After the tracked days it carries DATA-LESS
// placeholder entries (no temperature, bleeding none, no observations)
// out to the cycle's true calendar end:
//
//   - a cycle followed by another cycle: the day BEFORE the next cycle's
//     opening cycleStart mark, exactly;
//   - the LAST cycle (the still-running one): max(last tracked day of the
//     WHOLE data set, today) — never earlier than its own start.
//
// Untracked days BETWEEN a cycle's own tracked days are NOT backfilled:
// they stay out of the day list, keeping the gap-day conventions intact
// (marks on untracked days drop out of the curves; lib/domain/
// evaluation.dart reaches gap days through calendar-day walking).
//
// The "today" of the last-cycle rule is injectable via the `today`
// parameter — tests pin a date; production calls pass the wall clock
// (nowProvider at the UI call sites) or nothing (wall clock).
//
// Profile-free: marks key to days only (the (entry_date, mark_type) unique
// index is the whole key); grouping is no longer per profile.

import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// One cycle = all tracked days between two consecutive cycle starts,
/// extended with data-less placeholder days out to the next cycle-start
/// mark (or the last-cycle rule — see the span rule in the file header).
final class Cycle {
  const Cycle({
    required this.days,
    required this.startsAtMenstruation,
    required this.startDate,
    required this.trackedEndDate,
  });

  /// The cycle's days, ordered ascending by date: the tracked days plus
  /// the data-less span-extension days after them (none inside — untracked
  /// gaps BETWEEN tracked days are not backfilled; see the file header).
  /// Held non-empty by the grouping algorithm.
  final List<DailyEntry> days;

  /// True when the group opened at a user-placed cycleStart mark (the
  /// group's first tracked day is the first tracked day on/after that
  /// mark). False only for the leading group formed from entries that
  /// predate the first cycleStart mark.
  final bool startsAtMenstruation;

  /// The cycle's start date. For a mark-opened group it is the opening
  /// cycleStart mark's OWN date (the newest mark on/before the group's
  /// first tracked day — re-marking supersedes) and may lie on an untracked
  /// gap day BEFORE the first tracked day of [days]; the days without
  /// entries between mark and first tracked day belong to this cycle but
  /// are not held in [days]. Only the leading group (no opening mark)
  /// anchors on its first tracked day.
  final DateTime startDate;

  /// The cycle's last TRACKED day — the last entry of [days] that carries
  /// real recorded data, i.e. WITHOUT the data-less span-extension
  /// placeholder days after it (see the span rule). Null only for a
  /// data-less cycle (a fresh mark without any tracked day on/after it).
  ///
  /// Statistics endpoints that report an OBSERVED end ("one day past the
  /// last tracked day") anchor on this instead of [endDate]: the span
  /// extension reaches toward today for UI display, but such unobserved
  /// extension days must not shift a statistics count.
  final DateTime? trackedEndDate;

  /// Last day of the group — the span-extension end (day before the next
  /// cycle-start mark, or the last-cycle rule), data-less when extended
  /// beyond the tracked data.
  DateTime get endDate => days.last.date;
}

/// Dates of the mark-driven cycle starts — the anchors for cycle-length
/// statistics (all groups with `startsAtMenstruation == true`, i.e. every
/// user-placed cycle start that has at least one tracked day on/after it,
/// and every data-less fresh-mark cycle — see the span rule in the file
/// header). The onsets are the opening mark dates themselves, so a mark
/// placed on an untracked gap day yields an onset inside the gap — the
/// resulting lengths match the visible distance between two marks. Sorted
/// ascending, normalized to UTC-midnight (see DateOnly.normalize) so
/// calendar-day arithmetic is immune to DST shifts.
List<DateTime> menstruationOnsetDates(
  List<DailyEntry> entries,
  List<CycleMark> marks,
) => groupIntoCycles(entries, marks)
    .where((c) => c.startsAtMenstruation)
    .map((c) => DateOnly.normalize(c.startDate))
    .toList();

/// Groups the given (possibly unsorted) entries into cycles.
///
/// Entries are sorted by date; entry timing (date-only) decides grouping.
/// A group opens at the first tracked day on/after a cycleStart mark, and
/// its [Cycle.startDate] is that mark's own date — which may lie on an
/// untracked gap day before the group's first tracked day. Leading entries
/// (before the first mark) form one leading group with
/// `startsAtMenstruation == false`, anchored on its first tracked day.
/// Day-keyed: every cycleStart mark in [marks] contributes (there is no
/// profile dimension).
///
/// Span semantics (see the file header): after the tracked days every
/// cycle is extended with data-less entries to the day before the next
/// opening cycleStart mark; the LAST cycle — and any mark without tracked
/// data after it ("just created the cycle mark") — extends to
/// [today] (wall clock by default) but never before the last tracked day
/// of the whole data set, and never before the cycle's own start.
List<Cycle> groupIntoCycles(
  List<DailyEntry> entries,
  List<CycleMark> marks, {
  DateTime? today,
}) {
  final now = DateOnly.normalize(today ?? DateTime.now());

  // The cycleStart marks (marks of other types never create boundaries),
  // as pairs of the normalized day (comparisons/sorting key) and the
  // mark's raw date (the cycle's start date — kept local-midnight so
  // callers see the same date shape as the entries themselves).
  final cycleStartMarks = <({DateTime day, DateTime date})>[];
  for (final mark in marks) {
    if (mark.type != CycleMarkTypes.cycleStart) continue;
    final pair = (
      day: DateOnly.normalize(mark.date),
      date: DateTime(mark.date.year, mark.date.month, mark.date.day),
    );
    // A same-day duplicate mark does not open a second group for the same
    // day (the db index is unique on (date, type) — this only guards
    // hand-made or legacy lists); the LAST one in input order stays, like
    // the re-marking rule at the group's opening batch.
    cycleStartMarks.removeWhere((m) => m.day == pair.day);
    cycleStartMarks.add(pair);
  }
  cycleStartMarks.sort((a, b) => a.day.compareTo(b.day));

  if (cycleStartMarks.isEmpty && entries.isEmpty) return const [];

  final sorted = [...entries]
    ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));

  // The last tracked day of the WHOLE data set — the last cycle's
  // extension floor ("the data set's last tracked day").
  final dataEnd = sorted.isEmpty ? null : DateOnly.normalize(sorted.last.date);

  /// The last-cycle rule: the still-running cycle ends at the later of the
  /// data set's last tracked day and [today], clamped to [start] so a
  /// clock behind the mark never retracts a cycle below its start.
  DateTime lastCycleEnd(DateTime start) {
    var end = DateOnly.normalize(start);
    if (dataEnd != null && dataEnd.isAfter(end)) end = dataEnd;
    if (now.isAfter(end)) end = now;
    return end;
  }

  /// Materializes one cycle: the tracked days plus data-less extension
  /// entries for every calendar day after the last tracked day up to
  /// [end] (inclusive). Untracked days BEFORE the last tracked day are
  /// not touched — they stay silent gaps (see the file header).
  Cycle materialize(
    List<DailyEntry> tracked,
    bool startsAtMenstruation,
    DateTime end,
    DateTime startDate,
  ) {
    final extras = <DailyEntry>[];
    var day = DateOnly.addDays(tracked.last.date, 1);
    while (!day.isAfter(end)) {
      extras.add(DailyEntry(date: day));
      day = DateOnly.addDays(day, 1);
    }
    return Cycle(
      days: List.unmodifiable([...tracked, ...extras]),
      startsAtMenstruation: startsAtMenstruation,
      startDate: startDate,
      // The tracked list is never empty here: materialize always receives
      // the group's tracked body (leading group, mark-opened group) — the
      // data-less case never routes through materialize.
      trackedEndDate: DateOnly.normalize(tracked.last.date),
    );
  }

  // No marks at all: the tracked data is ONE leading group, extended by
  // the last-cycle rule.
  if (cycleStartMarks.isEmpty) {
    return [
      materialize(
        sorted,
        false,
        lastCycleEnd(sorted.first.date),
        sorted.first.date,
      ),
    ];
  }

  // Index of the next NOT-yet-consumed mark. A mark is consumed when the
  // group it opens has started (all marks on/before that day together —
  // they cannot open a second group for the same day, and anything on/before
  // the group's start is a no-op anyway).
  var cursor = 0;

  // The tracked groups exactly as the boundary rule above forms them (the
  // opening semantics are unchanged by the span extension): the cycle's
  // tracked days, whether a mark opened it, that mark's normalized day
  // (the anchor the PREVIOUS cycle extends its span with) and the group's
  // start date (the anchor rule — the opening mark's own date, or the
  // leading group's first tracked day).
  final groups =
      <
        ({
          List<DailyEntry> days,
          bool markOpened,
          DateTime? openingMarkDay,
          DateTime startDate,
        })
      >[];

  var currentDays = <DailyEntry>[];
  var currentStartsAtMenstruation = false;
  DateTime? currentOpeningMarkDay;
  DateTime? currentStartDate;

  void flush() {
    if (currentDays.isEmpty) return;
    groups.add((
      days: currentDays,
      markOpened: currentStartsAtMenstruation,
      openingMarkDay: currentOpeningMarkDay,
      // An entry only ever lands in currentDays after currentStartDate was
      // assigned (both branch kinds set it before the add), so a non-empty
      // currentDays implies currentStartDate != null.
      startDate: currentStartDate!,
    ));
    currentDays = <DailyEntry>[];
  }

  /// The cycleStart mark that would open a group at [entryDate], or null:
  /// - the very first tracked group opens when a mark sits on or before
  ///   [entryDate] (no leading group forms before that mark);
  /// - an already-open group is left when the next mark lies after the
  ///   group's start and no later than [entryDate] — a mark no later than
  ///   the current group's start is a no-op.
  /// On success all marks on or before [entryDate] are consumed (they
  /// cannot open a second group for the same day) and the OPENER — the
  /// LAST (newest) consumed mark — is returned: among multiple marks
  /// on/before the group's first tracked day it supersedes the older ones
  /// (the re-marking rule), and its own date is the cycle's start date.
  /// Returns null when no group opens.
  ({DateTime day, DateTime date})? markOpensGroup(
    DateTime entryDate,
    bool haveGroup,
  ) {
    if (cursor >= cycleStartMarks.length) return null;
    final day = DateOnly.normalize(entryDate);
    if (haveGroup) {
      final lower = DateOnly.normalize(currentStartDate!);
      if (cycleStartMarks[cursor].day.compareTo(lower) <= 0 ||
          cycleStartMarks[cursor].day.compareTo(day) > 0) {
        return null;
      }
    } else if (cycleStartMarks[cursor].day.compareTo(day) > 0) {
      return null;
    }
    var consumed = cursor;
    while (consumed < cycleStartMarks.length &&
        cycleStartMarks[consumed].day.compareTo(day) <= 0) {
      consumed++;
    }
    cursor = consumed;
    return cycleStartMarks[consumed - 1];
  }

  for (final entry in sorted) {
    final isGroupOpen = currentStartDate != null;
    final openerMark = markOpensGroup(entry.date, isGroupOpen);
    if (openerMark != null || !isGroupOpen) {
      // A new boundary always opens a group; the very first group opens
      // regardless (leading, non-boundary group starts at false — unless a
      // mark on/before the first tracked day opens the cycle right there).
      flush();
      currentStartsAtMenstruation = openerMark != null;
      // Mark-opened groups anchor on the newest opening mark's own date
      // (which may lie on an untracked gap day before this entry); only
      // the leading group anchors on its first tracked day.
      currentOpeningMarkDay = openerMark?.day;
      currentStartDate = openerMark?.date ?? entry.date;
    }
    currentDays.add(entry);
  }
  flush();

  // The materialized cycles: every tracked cycle extends to the day
  // before the NEXT boundary's opening mark — the next group's opening
  // mark, or the first leftover mark's (the data-less cycle it opens);
  // with nothing left, the last-cycle rule.
  final cycles = <Cycle>[
    for (var i = 0; i < groups.length; i++)
      materialize(
        groups[i].days,
        groups[i].markOpened,
        i + 1 < groups.length
            ?
              // The next group is always mark-opened (only the leading
              // pre-mark group can be the first group), so its opening
              // mark anchors this cycle's end.
              DateOnly.previousDay(groups[i + 1].openingMarkDay!)
            : cursor < cycleStartMarks.length
            // Marks beyond the recorded data still open data-less
            // cycles: this cycle ends the day before the first of them.
            ? DateOnly.previousDay(cycleStartMarks[cursor].day)
            : lastCycleEnd(groups[i].days.last.date),
        // The group's start date (the anchor rule above).
        groups[i].startDate,
      ),
  ];

  // Marks with no tracked day after them (placed beyond the recorded
  // data): each opens a DATA-LESS cycle at the mark day itself — at least
  // cycle day 1 exists. Consecutive such marks bound each other; the last
  // one runs by the last-cycle rule.
  for (var i = cursor; i < cycleStartMarks.length; i++) {
    final start = cycleStartMarks[i];
    final end = i + 1 < cycleStartMarks.length
        ? DateOnly.previousDay(cycleStartMarks[i + 1].day)
        : lastCycleEnd(start.day);
    final days = <DailyEntry>[];
    for (
      var day = start.day;
      !day.isAfter(end);
      day = DateOnly.addDays(day, 1)
    ) {
      days.add(DailyEntry(date: day));
    }
    cycles.add(
      Cycle(
        days: List.unmodifiable(days),
        startsAtMenstruation: true,
        // The data-less placeholder days are normalized-day arithmetic
        // (see the span rule) — the start date matches that shape.
        startDate: start.day,
        // A data-less mark cycle observes nothing by definition.
        trackedEndDate: null,
      ),
    );
  }

  return cycles;
}

/// The shared display ordinal of a mark-opened cycle ("Zyklus N"): cycles
/// observed OUTSIDE the app (settings key `observedCyclesOutsideApp`,
/// default 0) shift every number by their count, so a user who tracked on
/// paper first continues her numbering seamlessly. Input is the 0-based
/// index of the mark-opened cycle in observation order (the leading
/// pre-mark group carries no ordinal — it is not mark-opened, so it shifts
/// nothing). ONE shared rule so the chart's boundary labels and the
/// evaluation table's column headers cannot drift.
int cycleOrdinalNumber(int markOpenedIndex, int observedCyclesOutsideApp) =>
    observedCyclesOutsideApp + markOpenedIndex + 1;

/// The 1-based day-of-cycle of [date] within the latest cycle in [cycles]
/// that starts on or before it — the label no. of a diary day tile and the
/// entry form's date row. The containing cycle is the one with the LATEST
/// [Cycle.startDate] <= [date] (normalized comparison, so calendar-day
/// arithmetic is DST-immune); its number is `date - startDate + 1`
/// (DateOnly.daysBetween + 1).
///
/// Two anchoring rules keep the numbering continuous:
///
///  - The count anchors on [Cycle.startDate] itself. For a mark-opened
///    cycle that is the SYNCHRONOUS cycleStart mark's own date, which may
///    sit on an untracked gap day before the first tracked day — the gap
///    days between mark and first tracked day keep counting (so a first
///    tracked day after a gap-day start numbers > 1), and a tracked day
///    AFTER the cycle's last tracked day keeps counting too: without a
///    later start the cycle silently continues (forward projection) — the
///    day is labeled as if the cycle went on until the next mark opens.
///  - The leading pre-mark group (no opening mark) anchors on its FIRST
///    TRACKED day, since its begin is unknown otherwise.
///
/// Returns null when no cycle starts on or before [date] (a day before
/// every group start — nothing is labeled there) or when [cycles] is empty.
int? dayOfCycleFor(DateTime date, List<Cycle> cycles) {
  Cycle? containing;
  for (final cycle in cycles) {
    final startsOnOrBefore = DateOnly.daysBetween(date, cycle.startDate) >= 0;
    if (startsOnOrBefore &&
        (containing == null ||
            DateOnly.daysBetween(cycle.startDate, containing.startDate) > 0)) {
      containing = cycle;
    }
  }
  if (containing == null) return null;
  return DateOnly.daysBetween(date, containing.startDate) + 1;
}

/// The bleeding SUGGESTION predicate (the demoted former boundary rule):
/// a day with menstruation-level bleeding (`level >= 2`) suggests starting
/// a new cycle unless the immediately preceding CALENDAR day is also a
/// menstruation-level day (i.e. we are in the middle of one continuous
/// menstruation). This gates derivations only — the diary's old
/// bleeding-suggested prompt is now the entry form's explicit cycle-start
/// switch, and the predicate NEVER creates a cycle boundary by itself.
///
/// Temperature-only semantics (owner decision 2026-09-18): the suppression
/// is keyed PURELY on bleeding continuity. The ignoreTemperature mark does
/// NOT affect suggestions (a marked bleeding day suggests, a marked
/// previous bleeding day suppresses like any other bleeding day), and the
/// raw disturbance flags ([DailyEntry.tempDisturbances]) are equally
/// invisible — the predicate reads bleeding levels only.
bool isSuggestedCycleStart(DailyEntry entry, DailyEntry? previous) {
  if (entry.bleeding.level < 2) return false;

  if (previous != null &&
      DateOnly.sameDay(previous.date, DateOnly.previousDay(entry.date)) &&
      previous.bleeding.level >= 2) {
    return false;
  }
  return true;
}
