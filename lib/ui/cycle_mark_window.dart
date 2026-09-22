// The cycle-window attribution shared by the cycle chart's overlay
// (cycle_marks.dart) and the day options panel (cycle_mark_sheet.dart):
// which cycle's artifacts a mark belongs to. Kept in its own small file so
// both consumers can reach it without pulling in each other's widget/graph
// dependencies.

import '../domain/date_only.dart';
import '../domain/evaluation.dart';

/// Whether [day] falls inside the attribution window of the cycle at
/// [index] in [evaluations]: the window is `[cycle.startDate, next cycle's
/// startDate)` — half-open, so the next menstruation start itself belongs
/// to the NEXT cycle — and the LAST cycle's window is open-ended. The
/// bounds and [day] are compared as normalized UTC-midnight values
/// (DateOnly convention).
///
/// This mirrors the attribution the domain's evaluateCycles applies to its
/// own mark lookups (the `_latestMarkOf` filtering in
/// lib/domain/evaluation.dart); the UI reuses this helper so the chart
/// overlay and the sheet cannot drift from the domain's window semantics.
bool isDayInCycleWindow(
  List<CycleEvaluation> evaluations,
  int index,
  DateTime day,
) {
  final windowStart = DateOnly.normalize(evaluations[index].cycle.startDate);
  final windowEnd = index + 1 < evaluations.length
      ? DateOnly.normalize(evaluations[index + 1].cycle.startDate)
      : null;
  final d = DateOnly.normalize(day);
  if (d.isBefore(windowStart)) return false;
  if (windowEnd != null && !d.isBefore(windowEnd)) return false;
  return true;
}
