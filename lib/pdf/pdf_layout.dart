// The PDF layout planner: the pure (cycle -> pages) split deciding how the
// exported cycles lay out onto pages.
//
// THE RULE (roadmap: "at most 1 cycle per page"): every page window belongs
// to EXACTLY ONE cycle — a cycle whose column count exceeds the printable
// width continues onto further pages (page-break mid-cycle allowed, long
// cycles like a pregnancy take several pages), but NO page ever carries
// days from two cycles. The planner is cheap enough to unit-test directly
// and re-decide per export; the document builder consumes its windows
// verbatim, so page counts in the PDF equal plan lengths by construction.
//
// Pure Dart, no pdf-package import: the planner knows only day counts.

/// One page window for ONE cycle: the cycle's days
/// `[firstDayIndex, firstDayIndex + dayCount)` — indices into that cycle's
/// tracked-day list (Cycle.days). Ordered: cycle order first, then page
/// order inside the cycle.
final class CyclePagePlan {
  const CyclePagePlan({
    required this.cycleIndex,
    required this.pageIndexInCycle,
    required this.firstDayIndex,
    required this.dayCount,
  });

  /// 0-based index of the cycle within the exported model.
  final int cycleIndex;

  /// 0-based page number WITHIN this cycle (for "Blatt k/n" labels).
  final int pageIndexInCycle;

  /// The first day (index into the cycle's day list) drawn on this page.
  final int firstDayIndex;

  /// How many of the cycle's days this page draws.
  final int dayCount;
}

/// The default day-column budget per page: the paper sheet lists exactly
/// 40 day columns per landscape sheet, so the export draws the same
/// column count on plain paper (the printable landscape-A4 width fits 40
/// — see lib/pdf/cycle_pdf.dart, which does not even pass `maxDaysPerPage`
/// explicitly: it relies on this planner default verbatim, so the
/// planner and the drawn grid cannot drift).
const int defaultMaxDaysPerPage = 40;

/// Plans the pages of the exported cycles: [cycleDayCounts] carries each
/// exported cycle's tracked-day COUNT in observation order; the result
/// lists one entry per page, in print order.
///
/// Every cycle gets `ceil(dayCount / maxDaysPerPage)` pages; the last page
/// of a cycle takes only its trailing remainder days. An empty input
/// yields an empty plan. `maxDaysPerPage` must be >= 1; a day count must
/// be >= 0.
List<CyclePagePlan> planCyclePages(
  List<int> cycleDayCounts, {
  int maxDaysPerPage = defaultMaxDaysPerPage,
}) {
  if (maxDaysPerPage < 1) {
    throw ArgumentError.value(
      maxDaysPerPage,
      'maxDaysPerPage',
      'must be at least 1 (days per printable page)',
    );
  }
  final plan = <CyclePagePlan>[];
  for (var cycle = 0; cycle < cycleDayCounts.length; cycle++) {
    final total = cycleDayCounts[cycle];
    if (total < 0) {
      throw ArgumentError.value(
        total,
        'cycleDayCounts[$cycle]',
        'a cycle day count must not be negative',
      );
    }
    if (total == 0) continue; // nothing to draw (every tracked cycle group
    // holds at least one day; harmless for direct callers).
    var pageInCycle = 0;
    for (var first = 0; first < total; first += maxDaysPerPage) {
      final windowEnd = (first + maxDaysPerPage) > total
          ? total
          : first + maxDaysPerPage;
      plan.add(
        CyclePagePlan(
          cycleIndex: cycle,
          pageIndexInCycle: pageInCycle++,
          firstDayIndex: first,
          dayCount: windowEnd - first,
        ),
      );
    }
  }
  return plan;
}
