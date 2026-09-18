// Cycle grouping: split a stream of tracked days into cycles.
//
// Boundary rule (decided — the cycle start is a user mark):
//
//   A new cycle group opens at the first tracked day on/after a user-placed
//   `cycleStart` mark (CycleMarkTypes.cycleStart). The mark
//   is AUTHORITATIVE and binds wherever it sits — including on days without
//   menstruation bleeding, on excluded (interrupted) days, and on untracked
//   gap days (the group then opens at the next tracked entry). Bleeding
//   never creates a boundary by itself; it only SUGGESTS a cycle start via
//   [isSuggestedCycleStart] (prompts / derived marks). A leading group of
//   entries that predate the first mark keeps
//   `startsAtMenstruation == false`.
//
// Profile-free: marks key to days only (the (entry_date, mark_type) unique
// index is the whole key); grouping is no longer per profile.

import 'date_only.dart';
import 'marks.dart';
import 'models.dart';

/// One cycle = all tracked days between two consecutive cycle starts.
final class Cycle {
  const Cycle({required this.days, required this.startsAtMenstruation});

  /// The cycle's tracked days, ordered ascending by date. Held non-empty by
  /// the grouping algorithm.
  final List<DailyEntry> days;

  /// True when the group opened at a user-placed cycleStart mark (the
  /// group's first tracked day is the first tracked day on/after that
  /// mark). False only for the leading group formed from entries that
  /// predate the first cycleStart mark.
  final bool startsAtMenstruation;

  /// First tracked day of the group.
  DateTime get startDate => days.first.date;

  /// Last tracked day of the group. Days without entries are silent gaps.
  DateTime get endDate => days.last.date;
}

/// Dates of the mark-driven cycle starts — the anchors for cycle-length
/// statistics (all groups with `startsAtMenstruation == true`, i.e. every
/// user-placed cycle start that has at least one tracked day on/after it).
/// Sorted ascending, normalized to UTC-midnight (see DateOnly.normalize) so
/// calendar-day arithmetic is immune to DST shifts.
List<DateTime> menstruationOnsetDates(
  List<DailyEntry> entries,
  List<CycleMark> marks,
) =>
    groupIntoCycles(entries, marks)
        .where((c) => c.startsAtMenstruation)
        .map((c) => DateOnly.normalize(c.startDate))
        .toList();

/// Groups the given (possibly unsorted) entries into cycles.
///
/// Entries are sorted by date; entry timing (date-only) decides grouping.
/// A group starts at the first tracked day on/after a cycleStart mark;
/// leading entries (before the first mark) form one leading group with
/// `startsAtMenstruation == false`. Day-keyed: every cycleStart mark in
/// [marks] contributes (there is no profile dimension).
List<Cycle> groupIntoCycles(
  List<DailyEntry> entries,
  List<CycleMark> marks,
) {
  if (entries.isEmpty) return const [];

  // The cycleStart mark dates (marks of other types never create
  // boundaries). Normalized so calendar-day comparisons are exact.
  final markDates = <DateTime>[];
  for (final mark in marks) {
    if (mark.type != CycleMarkTypes.cycleStart) continue;
    markDates.add(DateOnly.normalize(mark.date));
  }
  markDates.sort();

  // Index of the next NOT-yet-consumed mark. A mark is consumed when the
  // group it opens has started (all marks on/before that day together —
  // they cannot open a second group for the same day, and anything on/before
  // the group's start is a no-op anyway).
  var cursor = 0;

  final sorted = [...entries]
    ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));

  final cycles = <Cycle>[];
  var currentDays = <DailyEntry>[];
  var currentStartsAtMenstruation = false;
  DateTime? currentStart;

  void flush() {
    if (currentDays.isEmpty) return;
    cycles.add(Cycle(
      days: List.unmodifiable(currentDays),
      startsAtMenstruation: currentStartsAtMenstruation,
    ));
    currentDays = <DailyEntry>[];
  }

  /// True when the next unconsumed cycleStart mark opens a group at
  /// [entryDate]:
  /// - the very first tracked group opens when a mark sits on or before
  ///   [entryDate] (no leading group forms before that mark);
  /// - an already-open group is left when the next mark lies after the
  ///   group's start and no later than [entryDate] — a mark no later than
  ///   the current group's start is a no-op.
  /// On success all marks on or before [entryDate] are consumed (they
  /// cannot open a second group for the same day).
  bool markOpensGroup(DateTime entryDate, bool haveGroup) {
    if (cursor >= markDates.length) return false;
    final nextMark = markDates[cursor];
    final day = DateOnly.normalize(entryDate);
    if (haveGroup) {
      final lower = DateOnly.normalize(currentStart!);
      if (nextMark.compareTo(lower) <= 0 || nextMark.compareTo(day) > 0) {
        return false;
      }
    } else if (nextMark.compareTo(day) > 0) {
      return false;
    }
    var consumed = cursor;
    while (consumed < markDates.length &&
        markDates[consumed].compareTo(day) <= 0) {
      consumed++;
    }
    cursor = consumed;
    return true;
  }

  for (final entry in sorted) {
    final isGroupOpen = currentStart != null;
    final opens = markOpensGroup(entry.date, isGroupOpen);
    if (opens || !isGroupOpen) {
      // A new boundary always opens a group; the very first group opens
      // regardless (leading, non-boundary group starts at false — unless a
      // mark on/before the first tracked day opens the cycle right there).
      flush();
      currentStartsAtMenstruation = opens;
      currentStart = entry.date;
    }
    currentDays.add(entry);
  }
  flush();

  return cycles;
}

/// The bleeding SUGGESTION predicate (the demoted former boundary rule):
/// a day with menstruation-level bleeding (`level >= 2`) suggests starting
/// a new cycle unless the immediately preceding CALENDAR day is also a
/// menstruation-level day (i.e. we are in the middle of one continuous
/// menstruation). This gates prompts and derived marks — it NEVER creates
/// a cycle boundary by itself.
///
/// Temperature-only semantics (owner decision 2026-09-18): the suppression
/// is keyed PURELY on bleeding continuity. The ignoreTemperature mark does
/// NOT affect suggestions (a marked bleeding day suggests, a marked
/// previous bleeding day suppresses like any other bleeding day), and the
/// raw disturbance flags ([DailyEntry.tempDisturbances]) are equally
/// invisible — the predicate reads bleeding levels only.
bool isSuggestedCycleStart(
  DailyEntry entry,
  DailyEntry? previous,
) {
  if (entry.bleeding.level < 2) return false;

  if (previous != null &&
      DateOnly.sameDay(previous.date, DateOnly.previousDay(entry.date)) &&
      previous.bleeding.level >= 2) {
    return false;
  }
  return true;
}
