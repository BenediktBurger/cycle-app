// The PDF export model: the export-ready record distilled from the tracked
// data (entries + marks) plus the settings values — the input the PDF
// generator and the settings-pane export card both work from.
//
// Pure render-time arithmetic (ADR-0001: nothing here is persisted), NO
// fertility interpretation (same hard rule as lib/domain/statistics.dart —
// arithmetic facts only), and NO pdf-package import: the model stays
// host-VM-testable and the layout/generation layer consumes it as-is.
//
// Chosen shape for the per-cycle display artifacts: `PdfExportModel.overlays`
// is a LIST PARALLEL to `cycles` (`overlays[i]` draws over `cycles[i]`,
// built by the same filter), so the page builder indexes both consistently
// and a cycle with no derived artifacts simply carries an empty overlay.
//
// Day-index convention inside [PdfCycleOverlay]: index i is the calendar
// day `cycle.startDate + i` — the space the shared overlay builder maps the
// shared artifacts onto (see lib/domain/evaluation_overlay.dart). While a
// cycle is tracked daily this equals the position in its tracked-day list
// (the PDF page windows' space); with untracked gap days the PDF's draw
// layers map the two spaces explicitly — the page-window draw list maps
// every overlay index through the tracked days' calendar offsets
// (lib/pdf/pdf_curve.dart) and any mark on an untracked gap day drops out
// instead of sliding onto a neighboring column. For that mapping to see
// the cycle's WHOLE calendar span (the last tracked day sits at a larger
// offset than the tracked count once a gap exists), the overlay window is
// built over the span day count below, not over `cycle.days.length`.
//
// Numbering rule (decided, shared with the cycle page): ONLY the cycles a
// user-placed cycleStart mark opened (`Cycle.startsAtMenstruation == true`)
// are exported, counted and numbered; the LEADING pre-mark group — entries
// that predate the first cycleStart mark, which the cycle page leaves
// unnumbered — is excluded here as well, so a PDF always agrees with the
// chart's boundary labels and the evaluation table's column headers. The
// outside-app cycles (settings key `observedCyclesOutsideApp`) shift the
// ordinals on top, through the ONE shared helper [cycleOrdinalNumber]
// (lib/domain/cycle_grouping.dart) — the numbering cannot drift.
import 'cycle_grouping.dart';
import 'date_only.dart';
import 'evaluation.dart';
import 'evaluation_overlay.dart';
import 'marks.dart';
import 'models.dart';
import 'statistics.dart';
import 'temperature_range.dart';

/// The export-ready record: the exported cycles, the echoed identifying
/// values and the paper-form header facts. Every header fact is nullable —
/// the generator renders the "—" convention for missing values.
///
/// The evaluation overlay of ONE exported cycle, localized to that
/// cycle's day space (see the file-header note on the index convention):
/// the same derived artifacts the cycle chart draws (built with the shared
/// [buildEvaluationOverlay], fed the WHOLE evaluation list so the SUZ
/// attribution windows match the chart's) plus the cycle's
/// temperature-ignore indexes. The drawing layer draws, it never re-derives.
final class PdfCycleOverlay {
  const PdfCycleOverlay({
    this.peakIndexes = const {},
    this.circledIndexes = const {},
    this.arrowIndexes = const {},
    this.numbersByIndex = const {},
    this.baselineSegments = const [],
    this.suzMarks = const [],
    this.ignoredIndexes = const {},
  });

  /// Copies the shared overlay's fields; [ignoredIndexes] come from the
  /// cycle-local [ignoredDayIndexes] derivation.
  PdfCycleOverlay.from(EvaluationOverlay overlay, this.ignoredIndexes)
    : peakIndexes = overlay.peakIndexes,
      circledIndexes = overlay.circledIndexes,
      arrowIndexes = overlay.arrowIndexes,
      numbersByIndex = overlay.numbersByIndex,
      baselineSegments = overlay.baselineSegments,
      suzMarks = overlay.suzMarks;

  /// Day indexes carrying a mucus-peak mark (EVERY placed peak; see
  /// EvaluationOverlay.peakIndexes).
  final Set<int> peakIndexes;

  /// Circled / arrowed marked candidates (per-candidate rule R4).
  final Set<int> circledIndexes;
  final Set<int> arrowIndexes;

  /// The 1–6 low numbers by day index.
  final Map<int, int> numbersByIndex;

  /// The drawn baseline segments (R10).
  final List<BaselineSegment> baselineSegments;

  /// The user-placed SUZ marks (suzMorning/suzEvening).
  final List<SuzOverlayMark> suzMarks;

  /// The temperature-ignore day indexes ([ignoredDayIndexes]) — the
  /// curve's dimming key, shared with the chart's derivation.
  final Set<int> ignoredIndexes;
}

final class PdfExportModel {
  const PdfExportModel({
    required this.cycles,
    required this.markOpenedIndexes,
    required this.overlays,
    required this.observedCyclesOutsideApp,
    required this.name,
    required this.birthDate,
    required this.shortestCycleLengths,
    required this.earliestFirstHigherCycleDays,
    this.temperatureRange = TemperatureRange.defaults,
  });

  /// The exported cycles: the MARK-OPENED cycle groups surviving the
  /// export constraints (see [buildPdfExportModel] — "up to" and/or the
  /// card's selected-cycles set), in observation order. The leading
  /// pre-mark group is never among them.
  final List<CycleEvaluation> cycles;

  /// The real mark-opened index of every exported cycle, PARALLEL to
  /// [cycles] (`markOpenedIndexes[i]` is `cycles[i]`'s 0-based position
  /// among ALL mark-opened cycles of the record — the leading unnumbered
  /// pre-mark group excluded, same as the count). [ordinalOf] routes
  /// through it so an exported cycle always prints its REAL number from
  /// the whole record — a subset export never re-indexes the selected
  /// set, and that same real number is the page's observed-cycle count
  /// (the paper form counts up until the count reaches the cycle's own
  /// number).
  final List<int> markOpenedIndexes;

  /// The per-cycle evaluation overlays, PARALLEL to [cycles]
  /// (`overlays[i]` carries the display artifacts of `cycles[i]` — the
  /// derived marks/low numbers/baseline/SUZ pieces plus the
  /// temperature-ignore indexes, all in the owning cycle's day space, see
  /// the file header). Built with the shared overlay derivation so the PDF
  /// draws exactly what the chart draws.
  final List<PdfCycleOverlay> overlays;

  /// The temperature-display range ("Temperaturbereich" settings card)
  /// echoed into the model: the curve block's fixed y scale — a chosen
  /// range is never rescaled for the data (same behavior as the chart).
  /// Defaults to [TemperatureRange.defaults] when the caller passes none.
  final TemperatureRange temperatureRange;

  /// The persisted count of cycles observed outside this app (settings
  /// family / provider, default 0). Echoed, not recomputed, so the
  /// generator and tests can derive ordinals exactly as the caller chose.
  final int observedCyclesOutsideApp;

  /// The identifying name from the settings (`pdfExport.name` family),
  /// trimmed, or null when unset/blank after trimming (matching
  /// `persistPdfExportName`). The generator hides these values when the
  /// per-export "anonymize" switch was on.
  final String? name;

  /// The identifying birth date from the settings (`pdfExport.birthDate`),
  /// date-only normalized, or null when unset.
  final DateTime? birthDate;

  /// The per-cycle shortest-cycle fact, PARALLEL to [cycles]: the length
  /// of the shortest COMPLETED cycle known at `cycles[i]`'s point of view
  /// — the minimum over the mark-opened cycles STRICTLY EARLIER in the
  /// whole record. The running cycle's own length is deliberately
  /// excluded: a cycle's length is only known once a LATER cycle exists,
  /// so counting it would make an early page's number change when it is
  /// reprinted after later cycles were tracked (the paper form counts up
  /// as cycles accumulate — an export must reproduce the sheet exactly as
  /// it looked at that cycle's time). The first cycle of a record
  /// therefore always carries null and the renderer shows "—". The
  /// lengths measure each earlier cycle to its direct successor in the
  /// WHOLE record (never a between-cycles distance in a subset).
  ///
  /// The shortest of the cycles observed OUTSIDE this app (the settings
  /// pane's paper-history card) min-combines into every page's value: the
  /// paper history predates every in-app cycle, so the paper figure was
  /// already part of the observed record when the first in-app page
  /// printed — and being constant it can never break the idempotency
  /// above (see [buildPdfExportModel]). The first cycle's page therefore
  /// prints the paper figure instead of "—" when one was given.
  final List<int?> shortestCycleLengths;

  /// The per-cycle earliest-first-higher fact, PARALLEL to [cycles]: the
  /// documented two-variant record of `earliestFirstHigherCycleDay`
  /// (lib/domain/statistics.dart) computed over the evaluation list
  /// truncated AT `cycles[i]` (its own rise INCLUDED — from that cycle's
  /// point of view its rise is part of its own observation, and its marks
  /// exist in the record whenever it is printed). `any` — the pure
  /// minimum; `afterMucusPeak` — the minimum over only the first-higher
  /// marks lying STRICTLY after their cycle's marked mucus peak ("the
  /// real first higher"). The generator prefers `afterMucusPeak` and
  /// falls back to `any`; null when no cycle in the prefix carries a
  /// qualifying mark.
  ///
  /// The paper-history earliest first higher (both variants at once — the
  /// paper form saw the rise but did not record its mucus-peak relation
  /// as data) min-combines into both variants of every page for the same
  /// constant-before-the-first-cycle reason as [shortestCycleLengths].
  final List<({int? any, int? afterMucusPeak})> earliestFirstHigherCycleDays;

  /// The display ordinal ("Zyklus N") of the exported cycle at 0-based
  /// [index] — the cycle's REAL number: its mark-opened index in the
  /// whole record ([markOpenedIndexes]) through [cycleOrdinalNumber], so
  /// the page header names the cycle exactly as the selection list and
  /// the cycle page do, whatever subset was exported. This is ALSO the
  /// page's "Beobachtete Zyklen" count: on the paper form the count-up
  /// reaches the cycle's own number when it is printed, so both header
  /// lines carry the same figure and cannot drift.
  int ordinalOf(int index) =>
      cycleOrdinalNumber(markOpenedIndexes[index], observedCyclesOutsideApp);
}

/// Builds the [PdfExportModel] for one export run.
///
/// Export filter: a cycle group is exported exactly when a user-placed
/// cycleStart mark opened it (`Cycle.startsAtMenstruation == true`) AND —
/// its start date (the opening mark's local-midnight datetime since the
/// mark-anchoring change) normalized to the calendar day is no later than
/// [exportStartsUpTo]'s (equally normalized) calendar day AND — given
/// [selectedStartDates] — its identity START DATE is in the
/// chosen set. Both constraints default to null (no constraint): every
/// mark-opened cycle is exported. [selectedStartDates] is the PDF export
/// card's checkbox selection; its IDENTITY is the cycle's start DAY — the
/// values are normalized (DateOnly) before matching, so time-of-day noise
/// in a caller's set can never miss a cycle, and dates matching no cycle
/// are silently dropped (the set is what the user checked, cycles come
/// from the data). NOTE: a selection that drops interior cycles makes the
/// exported list SHORTER than the observed record — but the exported
/// cycles keep their REAL numbers from the whole record (each carries its
/// mark-opened index; see [PdfExportModel.markOpenedIndexes]):
/// every running header fact is computed from the record PREFIX truncated
/// at the printed cycle, from the paper form's point of view — an
/// exported page is identical however late it is printed (print
/// idempotency). In the same view the per-cycle shortest-cycle fact and
/// earliest-higher fact stay truthful regardless of the subset: they read
/// the whole record up to the printed cycle (see
/// [PdfExportModel.shortestCycleLengths] and
/// [PdfExportModel.earliestFirstHigherCycleDays]), never the exported
/// pages alone.
///
/// [birthDate] may carry time-of-day noise; it is normalized to the
/// calendar day (DateOnly convention) so header formatting stays exact.
///
/// [shortestCycleLengthOutsideApp] and [earliestFirstHigherCycleDayOutsideApp]
/// are the optional paper-history constants of the settings pane's
/// paper-history card (null = not given). They fold into EVERY exported
/// cycle's per-cycle stats below, and that fold never breaks print
/// idempotency: the paper history predates ALL in-app cycles, so these
/// facts were already known and counted when the FIRST in-app cycle was
/// printed on the paper form — a constant that never changes with later
/// cycles can never rewrite an earlier page's paper-derived figure (a
/// freshly tracked cycle only ever adds in-app data, which stays
/// truncated at the printed cycle).
///
/// [temperatureRange] is the settings card's display range, echoed into
/// the model for the curve block's fixed y scale (default:
/// [TemperatureRange.defaults] — the provider's starting window).
///
/// [today] is the grouping's injected clock for the span extension's
/// last-cycle rule (lib/domain/cycle_grouping.dart); default: the wall
/// clock at build time.
PdfExportModel buildPdfExportModel({
  required List<DailyEntry> entries,
  required List<CycleMark> marks,
  int observedCyclesOutsideApp = 0,
  String? name,
  DateTime? birthDate,
  int? shortestCycleLengthOutsideApp,
  int? earliestFirstHigherCycleDayOutsideApp,
  DateTime? exportStartsUpTo,
  Set<DateTime>? selectedStartDates,
  TemperatureRange temperatureRange = TemperatureRange.defaults,
  DateTime? today,
}) {
  // The iteration limit is a CALENDAR day: date-only normalized (the
  // builder does this itself, so a caller's time-of-day noise is already
  // gone). The compared cycle start is NOT in that shape automatically —
  // since the mark-anchoring change `Cycle.startDate` is the placed
  // mark's local-midnight datetime — so the start date is normalized to
  // its calendar day before the instant comparison against the (already
  // normalized) limit; the local UTC offset can then never shift a start
  // across the limit's day (wrongly dropping it) or pull it back to it.
  final limit = exportStartsUpTo == null
      ? null
      : DateOnly.normalize(exportStartsUpTo);
  // The chosen cycles' identity set (see the header note): normalized
  // start dates.
  final selected = selectedStartDates == null
      ? null
      : {for (final d in selectedStartDates) DateOnly.normalize(d)};
  final all = evaluateCycles(entries, marks, today: today);
  // The exported cycle groups as the indexes they hold in `all` (the
  // attribution windows the overlay builder consults span the WHOLE list,
  // so an exported cycle's position in it matters — same call shape the
  // chart uses, one overlay per exported cycle). The same loop counts the
  // record's mark-opened cycles, so every exported cycle records its REAL
  // 0-based mark-opened index alongside (the outside-app shift is part of
  // the ordinal, not of this index).
  final exportedIndexes = <int>[];
  final markOpenedIndexes = <int>[];
  var markOpenedCount = 0;
  for (var i = 0; i < all.length; i++) {
    if (!all[i].cycle.startsAtMenstruation) continue;
    final markOpenedIndex = markOpenedCount++;
    if ((limit == null ||
            !DateOnly.normalize(all[i].cycle.startDate).isAfter(limit)) &&
        (selected == null ||
            selected.contains(DateOnly.normalize(all[i].cycle.startDate)))) {
      exportedIndexes.add(i);
      markOpenedIndexes.add(markOpenedIndex);
    }
  }
  final exported = [for (final i in exportedIndexes) all[i]];

  // The per-cycle overlays, parallel to `exported`: the shared derivation
  // maps each cycle's day space directly (firstDay = the cycle's start
  // day, dayCount = its full CALENDAR span — tracked days plus any
  // untracked gap days between them; isolated per cycle — a page never
  // carries two cycles), fed the WHOLE evaluation list so a mark's
  // attributed cycle window matches the chart's. The PDF's page-window
  // draw-list helper maps this calendar-offset space onto tracked
  // positions (see lib/pdf/pdf_curve.dart).
  final overlays = [
    for (final i in exportedIndexes)
      PdfCycleOverlay.from(
        buildEvaluationOverlay(
          evaluations: all,
          marks: marks,
          firstDay: DateOnly.normalize(all[i].cycle.startDate),
          dayCount: _calendarSpanDays(all[i].cycle),
        ),
        ignoredDayIndexes(cycle: all[i].cycle, marks: marks),
      ),
  ];

  // The per-cycle header statistics, parallel to `exported`, each
  // computed from the record's point of view AT that cycle so a page is
  // idempotent however late it is printed:
  //
  // - Shortest cycle (EXCLUSIVE of the running cycle): the minimum over
  //   the COMPLETED lengths of the strictly earlier mark-opened cycles
  //   (indexes 0..m-1). Earlier cycles' lengths are known from the record
  //   whenever the page prints, so they cannot change it; the running
  //   cycle's own length needs a LATER cycle to exist and would rewrite
  //   the page once it did — excluded. The first cycle of a record has no
  //   completed earlier cycle and carries null (the renderer's "—").
  //
  // - Earliest first higher (INCLUSIVE of the running cycle): the shared
  //   two-variant helper over the evaluation PREFIX — `all` truncated at
  //   the cycle's own position (a slice of the already-built list, so the
  //   per-cycle anchored fields are the identical objects). The helper's
  //   own rules (skip non-mark-opened, ignore the leading pre-mark group)
  //   keep applying on the slice; unexported earlier cycles count too —
  //   the paper form counted them.
  final shortestCycleLengths = <int?>[];
  final earliestFirstHigherCycleDays = <({int? any, int? afterMucusPeak})>[];
  for (var e = 0; e < exportedIndexes.length; e++) {
    final i = exportedIndexes[e];
    int? shortest;
    for (var p = 0; p < i; p++) {
      // Only mark-opened cycles are observed cycles the paper form
      // counts; their successor all[p + 1] always exists (p < i).
      if (!all[p].cycle.startsAtMenstruation) continue;
      final gap = DateOnly.daysBetween(
        all[p + 1].cycle.startDate,
        all[p].cycle.startDate,
      );
      if (shortest == null || gap < shortest) shortest = gap;
    }
    shortestCycleLengths.add(
      _minPaperFact(shortest, shortestCycleLengthOutsideApp),
    );
    final inAppFirstHigher = earliestFirstHigherCycleDay(all.sublist(0, i + 1));
    earliestFirstHigherCycleDays.add((
      any: _minPaperFact(
        inAppFirstHigher.any,
        earliestFirstHigherCycleDayOutsideApp,
      ),
      afterMucusPeak: _minPaperFact(
        inAppFirstHigher.afterMucusPeak,
        earliestFirstHigherCycleDayOutsideApp,
      ),
    ));
  }

  final trimmedName = name?.trim();

  return PdfExportModel(
    cycles: List.unmodifiable(exported),
    markOpenedIndexes: List.unmodifiable(markOpenedIndexes),
    overlays: List.unmodifiable(overlays),
    observedCyclesOutsideApp: observedCyclesOutsideApp,
    // The name is trimmed HERE, at the model entry point, so the model can
    // never carry padding — persistPdfExportName and the settings UI trim
    // the same way, and blank (whitespace-only) input stays null.
    name: (trimmedName != null && trimmedName.isNotEmpty) ? trimmedName : null,
    birthDate: birthDate == null ? null : DateOnly.normalize(birthDate),
    shortestCycleLengths: List.unmodifiable(shortestCycleLengths),
    earliestFirstHigherCycleDays: List.unmodifiable(
      earliestFirstHigherCycleDays,
    ),
    temperatureRange: temperatureRange,
  );
}

/// The SMALLER of an in-app-derived figure and a paper-history constant —
/// the fold rule of the paper history into in-app statistics: the paper
/// values were recorded BEFORE any in-app cycle existed, so they compete
/// in every cycle's point of view, and a minimum of observed facts never
/// flips upward. null folds to the other side's value (a missing paper
/// fact adds nothing — the in-app figure stands alone).
int? _minPaperFact(int? inAppValue, int? paperValue) {
  if (inAppValue == null) return paperValue;
  if (paperValue == null) return inAppValue;
  return inAppValue < paperValue ? inAppValue : paperValue;
}

/// The cycle's full CALENDAR span as the overlay window's day count:
/// from the cycle's start day through its span end (the lib/domain/
/// cycle_grouping.dart extension — data-less trailing days included),
/// inclusive — larger than `cycle.days.length` exactly when untracked gap
/// days sit between the tracked days (they are not in the day list), so
/// marks beyond a gap (e.g. on the last tracked day) still map to the
/// correct calendar offset (the draw layers map offsets onto tracked
/// positions; see lib/pdf/pdf_curve.dart).
int _calendarSpanDays(Cycle cycle) =>
    DateOnly.daysBetween(
      DateOnly.normalize(cycle.days.last.date),
      DateOnly.normalize(cycle.startDate),
    ) +
    1;

/// The cycle selector's option rows: one per MARK-OPENED cycle (the leading
/// pre-mark group stays unnumbered and is omitted — same rule as the
/// export), each carrying its display ordinal ("Zyklus N") and its start
/// day. The settings pane's dropdown lists these; the default selection is
/// the LAST row (the latest mark-opened cycle).
List<({int ordinal, DateTime startDate})> exportableCycles(
  List<DailyEntry> entries,
  List<CycleMark> marks, {
  int observedCyclesOutsideApp = 0,
  DateTime? today,
}) {
  final rows = <({int ordinal, DateTime startDate})>[];
  var markOpenedIndex = 0;
  for (final cycle in groupIntoCycles(entries, marks, today: today)) {
    if (!cycle.startsAtMenstruation) continue;
    rows.add((
      ordinal: cycleOrdinalNumber(markOpenedIndex, observedCyclesOutsideApp),
      startDate: DateOnly.normalize(cycle.startDate),
    ));
    markOpenedIndex++;
  }
  return rows;
}
