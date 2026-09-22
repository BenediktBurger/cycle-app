// Domain-test mark fixtures: the typed CycleMark constructions several
// domain suites kept copy-pasting — one definition each here, identical
// bodies. Deliberately minimal: suites with extra fixtures of their own
// (e.g. evaluation's mucus-peak/first-higher pairs) keep their locals.
import 'package:cycle_app/domain/marks.dart';

/// A user-placed cycleStart mark on (year, month, day) — the authoritative
/// cycle boundary (see lib/domain/cycle_grouping.dart: grouping is
/// mark-driven; bleeding only suggests).
CycleMark start(int year, int month, int day) => CycleMark(
  date: DateTime(year, month, day),
  type: CycleMarkTypes.cycleStart,
);

/// The analysis-exclusion mark on (year, month, day): the ONLY exclusion
/// signal the evaluation consumes. Raw disturbance flags never exclude.
CycleMark excludedDay(int year, int month, int day) => CycleMark(
  date: DateTime(year, month, day),
  type: CycleMarkTypes.ignoreTemperature,
);
