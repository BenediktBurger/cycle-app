// Cycle grouping: split a stream of tracked days into cycles.
//
// Boundary assumption (THE rule to review with experts):
//
//   TODO(user-review): A new menstrual cycle is assumed to start on the
//   FIRST day with `period` bleeding that follows any non-period day (or a
//   data gap). This is the classical NFP/Rötzer "cycle day 1 = first
//   bleeding day" posture, recorded here as an ASSUMPTION pending expert
//   review — see ADR-0001 draft note, docs/adr/0001-iner-mode-m-hypothesis.md
//   (status: Hypothesis). Details of this rule that need validation:
//     - Spotting days never start a cycle (spotting is not menstruation).
//     - Interrupted days (any exclude flag set) never start a cycle; they
//       are treated as opaque.
//     - A period day directly following an interrupted period day IS
//       treated as a new menstruation onset (the interrupted day may hide
//       the true start of the bleeding phase).
//     - A data gap (day without any entry) allows the next period day to
//       be an onset (an absent previous day cannot be proven non-period).

import 'date_only.dart';
import 'models.dart';

/// One cycle = all tracked days between two consecutive menstruation onsets.
final class Cycle {
  const Cycle({required this.days, required this.startsAtMenstruation});

  /// The cycle's tracked days, ordered ascending by date. Held non-empty by
  /// the grouping algorithm.
  final List<DailyEntry> days;

  /// True when the group's first tracked day is a menstruation onset
  /// (a cycle boundary). False only for the leading group formed from
  /// entries that predate the first known period onset.
  final bool startsAtMenstruation;

  /// First tracked day of the group.
  DateTime get startDate => days.first.date;

  /// Last tracked day of the group. Days without entries are silent gaps.
  DateTime get endDate => days.last.date;
}

/// Dates on which (per the assumption above) a new cycle starts — the
/// anchors for cycle-length statistics. Sorted ascending, normalized to
/// UTC-midnight (see DateOnly.normalize) so calendar-day arithmetic is
/// immune to DST shifts.
List<DateTime> menstruationOnsetDates(List<DailyEntry> entries) =>
    groupIntoCycles(entries)
        .where((c) => c.startsAtMenstruation)
        .map((c) => DateOnly.normalize(c.startDate))
        .toList();

/// Groups the given (possibly unsorted) entries into cycles.
///
/// Entries are sorted by date; entry timing (date-only) decides grouping.
/// A group starts at every menstruation onset; entries before the first
/// onset form one leading group with `startsAtMenstruation == false`.
List<Cycle> groupIntoCycles(List<DailyEntry> entries) {
  if (entries.isEmpty) return const [];

  final sorted = [...entries]
    ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));

  final cycles = <Cycle>[];
  var currentDays = <DailyEntry>[];
  var currentStartsAtMenstruation = false;
  DailyEntry? previous;

  void flush() {
    if (currentDays.isEmpty) return;
    cycles.add(Cycle(
      days: List.unmodifiable(currentDays),
      startsAtMenstruation: currentStartsAtMenstruation,
    ));
    currentDays = <DailyEntry>[];
  }

  for (final entry in sorted) {
    final isOnset = _isMenstruationOnset(entry, previous);
    if (isOnset || currentDays.isEmpty) {
      // A new boundary always opens a group; the very first group opens
      // regardless (leading, non-boundary group starts at false).
      flush();
      currentStartsAtMenstruation = isOnset;
    }
    currentDays.add(entry);
    previous = entry;
  }
  flush();

  return cycles;
}

/// The boundary rule (see the TODO(user-review) comment at the top):
/// a non-excluded period day starts a new cycle unless the immediately
/// preceding calendar day is also a non-excluded period day (i.e. we are in
/// the middle of one continuous menstruation).
bool _isMenstruationOnset(DailyEntry entry, DailyEntry? previous) {
  if (entry.bleeding != Bleeding.period) return false;
  if (entry.isExcluded) return false;

  if (previous != null &&
      DateOnly.sameDay(previous.date, DateOnly.previousDay(entry.date)) &&
      previous.bleeding == Bleeding.period &&
      !previous.isExcluded) {
    return false;
  }
  return true;
}
