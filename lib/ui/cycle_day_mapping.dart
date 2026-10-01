// The cycle screen's day view model (_ChartDays): day index -> day, cycle
// boundaries, "Zyklus N" ordinals. Part of the cycle.dart library.

part of 'cycle.dart';

/// The chart data view model for one recorded range: day index -> signal.
final class _ChartDays {
  _ChartDays(
    List<DailyEntry> entries,
    List<CycleMark> marks,
    List<Cycle> cycles,
    this.observedCyclesOutsideApp,
  ) {
    final sorted = [...entries]
      ..sort((a, b) => DateOnly.daysBetween(a.date, b.date));
    firstDay = DateOnly.normalize(sorted.first.date);
    dayCount =
        DateOnly.daysBetween(DateOnly.normalize(sorted.last.date), firstDay) +
        1;
    for (final e in sorted) {
      byIndex[DateOnly.daysBetween(DateOnly.normalize(e.date), firstDay)] = e;
    }
    ignoredDayIndexes = {
      for (final mark in marks)
        if (mark.type == CycleMarkTypes.ignoreTemperature)
          DateOnly.daysBetween(DateOnly.normalize(mark.date), firstDay),
    };
    // Cycle mapping over the whole index range, from the cycle groups the
    // screen shares with Tagebuch/Statistik (the derived pass): every day
    // counts into the cycle with the LATEST group start on or before it, so
    // untracked gap days keep counting from the last start. A group opens
    // at a user-placed cycleStart mark, anchored at the MARK's own date.
    final starts = [for (final g in cycles) DateOnly.normalize(g.startDate)];
    cycleStartDates = {
      for (final g in cycles)
        if (g.startsAtMark) DateOnly.normalize(g.startDate),
    };
    // Ordinals at the mark-opened boundaries via the shared ordinal rule
    // (shifted by the outside-app setting).
    var markOpenedIndex = 0;
    cycleOrdinalByStart = {
      for (final g in cycles)
        if (g.startsAtMark)
          DateOnly.normalize(g.startDate): cycleOrdinalNumber(
            markOpenedIndex++,
            observedCyclesOutsideApp,
          ),
    };
    var group = 0;
    for (var i = 0; i < dayCount; i++) {
      final date = dayAt(i);
      while (group + 1 < starts.length && !starts[group + 1].isAfter(date)) {
        group++;
      }
      cycleDayByIndex[i] = DateOnly.daysBetween(date, starts[group]) + 1;
    }
  }

  /// The chart day indexes whose temperature is IGNORED, from the
  /// `ignoreTemperature` MARKS — the marks, not the raw disturbance mask,
  /// are the curve's rendering key.
  late final Set<int> ignoredDayIndexes;

  /// UTC-midnight of the first recorded day (day index 0).
  late final DateTime firstDay;

  /// Index range length (>= number of recorded days; gaps included).
  late final int dayCount;

  final Map<int, DailyEntry> byIndex = {};

  /// Day of cycle (1, 2, 3 …) per day index, counted from the start of the
  /// cycle group the day belongs to.
  final Map<int, int> cycleDayByIndex = {};

  /// The recorded dates at which a cycle group opens at a user-placed
  /// cycleStart mark ([Cycle.startsAtMark]) — the cycle separators.
  /// Never contains the leading group's start (it predates the first mark).
  late final Set<DateTime> cycleStartDates;

  /// The observed-cycles count the ordinals shift by (the settings value
  /// the screen watches; see [cycleOrdinalNumber]).
  final int observedCyclesOutsideApp;

  /// The "Zyklus N" ordinal for every mark-opened cycle start (the same
  /// dates as [cycleStartDates], keyed by their UTC-midnight date).
  late final Map<DateTime, int> cycleOrdinalByStart;

  DateTime dayAt(int index) => DateOnly.addDays(firstDay, index);

  /// Whether day [index] opens a new cycle (the cycleStart mark's own date
  /// — the shared boundary predicate for the thick separator lines). A mark
  /// on the FIRST tracked day is also a boundary (its separator is the
  /// first cells' thick LEFT border; the in-plot line starts at index 1),
  /// and a mark on an untracked gap day keeps its own date as the boundary.
  bool isCycleBoundary(int index) => cycleStartDates.contains(dayAt(index));
}
