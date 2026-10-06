// The cycle screen's recording rows and the per-day content glyphs
// inside their cells; the day panel itself lives in
// cycle_mark_sheet.dart. Part of the cycle.dart library.

part of 'cycle.dart';

/// The top strip's row (paper sheet order): bleeding is the only one. The
/// mucus and sex observations, the Mittelschmerz M and the evaluation day
/// numbers render INSIDE the temperature plot instead (_InPlotGlyphRows,
/// chart_marks.dart).
const _topSignalKinds = <_SignalKind>[_SignalKind.bleeding];

/// The below-chart strip's rows (owner-decided order): measurement time →
/// disturbance → the merged notes band.
const _belowChartKinds = <_SignalKind>[
  _SignalKind.time,
  _SignalKind.disturbance,
  _SignalKind.notesBand,
];

/// One recording row per segment signal, top-down in segment order. The
/// rows hold ONLY day cells (name glyphs live in the frozen left rail) and
/// render every day, windowed at the curve's global column positions.
final class _SignalRows extends StatelessWidget {
  const _SignalRows({
    required this.kinds,
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
    required this.onDayTap,
  });

  final List<_SignalKind> kinds;

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final kind in kinds)
        Padding(
          padding: EdgeInsets.only(
            top: kind == kinds.first ? 0 : _signalRowGap,
          ),
          child: _SignalRow(
            kind: kind,
            days: days,
            cellWidth: cellWidth,
            windowStart: windowStart,
            windowEnd: windowEnd,
            onDayTap: onDayTap,
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// The recording rows' fixed heights, shared between the scrolling rows and
/// the frozen left rail — a layout change here must move both sides or the
/// rail's alignment test fails.
const double _signalRowGap = 2;

/// The fixed height a signal row's day cells occupy: disturbance reserves
/// two letter slots; the time row the height of a vertically written HH:mm
/// text (see _timeContent).
double _signalRowHeight(_SignalKind kind) => switch (kind) {
  _SignalKind.disturbance => 24,
  _SignalKind.time => 30,
  _SignalKind.notesBand => notesBandHeight,
  _SignalKind.bleeding => 12,
};

double _signalRowTop(_SignalKind kind, List<_SignalKind> kinds) {
  var top = 0.0;
  for (final k in kinds) {
    if (k == kind) break;
    top += _signalRowHeight(k) + _signalRowGap;
  }
  return top;
}

/// A segment's total height — the rail's glyph segment must match it.
double _signalSegmentHeight(List<_SignalKind> kinds) =>
    kinds.fold(0.0, (h, kind) => h + _signalRowHeight(kind) + _signalRowGap) -
    (kinds.isEmpty ? 0 : _signalRowGap);

enum _SignalKind { bleeding, time, disturbance, notesBand }

/// Test-visible key prefix of a row's day cells.
String _signalKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCell',
  _SignalKind.notesBand => 'notesBandCell',
  _SignalKind.disturbance => 'disturbanceCell',
  _SignalKind.time => 'timeCell',
};

/// Test-visible key prefix of a row's 44 px corner slot.
String _signalCornerKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCorner',
  _SignalKind.notesBand => 'notesBandCorner',
  _SignalKind.disturbance => 'disturbanceCorner',
  _SignalKind.time => 'timeCorner',
};

/// The localized row name for a signal (corner tooltip/semantics label).
// TODO(user-review): the row-name wording is a first draft mirroring the
// entry form's vocabulary; the experts may want different names.
String _signalRowName(_SignalKind kind, AppLocalizations l10n) =>
    switch (kind) {
      _SignalKind.bleeding => l10n.termBleeding,
      _SignalKind.notesBand => l10n.cycleRowNote,
      _SignalKind.disturbance => l10n.cycleRowDisturbance,
      _SignalKind.time => l10n.termMeasurementTime,
    };

/// A signal row's sample glyph, rendered in the frozen left rail at the
/// row's vertical slot.
Widget _signalCornerSample(BuildContext context, _SignalKind kind) {
  final scheme = Theme.of(context).colorScheme;
  return switch (kind) {
    _SignalKind.bleeding => SizedBox(
      width: 10,
      height: 10,
      child: BleedingSymbol(
        bleeding: Bleeding.spotting,
        color: scheme.error,
        borderColor: scheme.error,
      ),
    ),
    _SignalKind.notesBand => Icon(
      Icons.sticky_note_2_outlined,
      size: 12,
      color: scheme.onSurface,
    ),
    _SignalKind.disturbance => Text(
      'kr',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.time => Icon(Icons.schedule, size: 12, color: scheme.onSurface),
  };
}

/// The notes band's text: a diary note may be recorded MULTI-LINE
/// (embedded line breaks) but the rotated band line renders it as one
/// line — every whitespace run folds into a single space, mirroring the
/// PDF's joinedNoteText (lib/pdf/pdf_symbols.dart).
String _joinedNoteText(String notes) =>
    notes.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The day-column width boundary between the time row's HORIZONTAL and
/// VERTICAL rendering: below it the HH:mm text renders rotated so the time
/// stays visible even at the minimum usable column width.
// TODO(user-review): the threshold is a tuned display heuristic, not a
// rule from the cheat sheet.
const double _timeCellMinColumnWidth = 32;

/// One signal's recording row: the window's day cells only — the row's
/// name glyph lives in the frozen left rail (see _LeftRail), at this row's
/// vertical slot.
final class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.kind,
    required this.days,
    required this.cellWidth,
    required this.windowStart,
    required this.windowEnd,
    required this.onDayTap,
  });

  final _SignalKind kind;

  final _ChartDays days;
  final double cellWidth;
  final int windowStart;
  final int windowEnd;

  final void Function(int index) onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (windowStart > 0) SizedBox(width: windowStart * cellWidth),
        for (var i = windowStart; i <= windowEnd; i++)
          SizedBox(
            key: ValueKey('${_signalKeyPrefix(kind)}-$i'),
            width: cellWidth,
            child: InkWell(
              onTap: () => onDayTap(i),
              // The day-cell separator, thickened to the solid cycle-start
              // line when the NEXT day opens a cycle (the first tracked day
              // thickens its LEFT border: the domain-edge separator would
              // clamp at the plot's left edge).
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: i == 0
                        ? cycleDayCellBorderSide(
                            context,
                            isCycleBoundary: days.isCycleBoundary(0),
                          )
                        : BorderSide.none,
                    right: cycleDayCellBorderSide(
                      context,
                      isCycleBoundary: days.isCycleBoundary(i + 1),
                    ),
                  ),
                ),
                child: _cell(context, i),
              ),
            ),
          ),
      ],
    );
  }

  /// The fixed height each row's day cell occupies — keeps a row's empty
  /// cells at the recorded cells' height (the shared height the frozen
  /// rail's glyph slot mirrors).
  double get _cellHeight => _signalRowHeight(kind);

  /// One day's cell content.
  Widget _cell(BuildContext context, int index) {
    final day = days.byIndex[index];
    return SizedBox(
      height: _cellHeight,
      child: switch (kind) {
        _SignalKind.bleeding => Center(child: _bleedingContent(context, day)),
        _SignalKind.notesBand => _notesBandContent(context, day, index),
        _SignalKind.disturbance => Center(
          child: _disturbanceContent(context, day),
        ),
        _SignalKind.time => Center(child: _timeContent(context, day)),
      },
    );
  }

  /// Bleeding: the shared square-box symbol fills the day cell (the
  /// shared bottom-anchored fill-fraction convention; spotting dotted).
  static Widget _bleedingContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    return BleedingSymbol(bleeding: day.bleeding);
  }

  /// One day's slot ink, centered in the glyph zone at its slot: the
  /// opening renders as a painted circle sized by its value (diameter
  /// communicates the opening), placed at the position's slot — the
  /// position only picks the slot, a position without an opening paints
  /// nothing.
  static Widget? _cervixSlotInk(
    BuildContext context,
    DailyEntry day,
    int index,
  ) {
    final zones = notesBandLayout(day);
    if (zones.opening == null || zones.slotIndex == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final (diameter, filled) = switch (zones.opening!) {
      CervixOpening.closed => (cervixClosedDotSize, true),
      CervixOpening.middle => (cervixMiddleCircleSize, false),
      CervixOpening.open => (cervixOpenCircleSize, false),
    };
    final centerY = cervixSlotCenterY(zones.slotIndex!);
    return Positioned(
      left: 0,
      right: 0,
      top: centerY - diameter / 2,
      height: diameter,
      child: Center(
        child: Container(
          key: ValueKey('cervixSlotGlyph-$index'),
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? scheme.onSurface : null,
            border: filled
                ? null
                : Border.all(
                    color: scheme.onSurface,
                    width: cervixCircleStrokeWidth,
                  ),
          ),
        ),
      ),
    );
  }

  /// The day cell's merged notes band: the cervix stacked zones on top
  /// (only for days with any cervix observation — glyph zone, letter row,
  /// then the note zone; one reserved top block per cervix day, so the
  /// slot ink never depends on the note or the firmness letter), the
  /// breast-pain B letter row directly above the note zone (at the very
  /// band top on cervix-free days; not rendered or reserved on pain-free
  /// days), then the note zone. The note line reads top→bottom. Raw
  /// observation display only, never a fertility conclusion (ADR-0001);
  /// neutral on-surface ink with the in-plot glyphs' halo pass.
  static Widget _notesBandContent(
    BuildContext context,
    DailyEntry? day,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final zones = notesBandLayout(day);
    final joined = day == null || day.notes == null
        ? null
        : _joinedNoteText(day.notes!);
    final note = switch (joined) {
      final text? when text.isNotEmpty => text,
      _ => null,
    };
    return Stack(
      children: [
        if (zones.hasCervix)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cervixGlyphZoneHeight,
            child: _cervixZone(context, day!, index),
          ),
        if (day?.cervixFirmness case final firmness?)
          Positioned(
            left: 0,
            right: 0,
            top: cervixGlyphZoneHeight,
            height: cervixLetterRowHeight,
            child: Center(
              child: _InPlotGlyphRows._haloedText(
                inkKey: 'cervixFirmnessGlyph-$index',
                haloKey: 'cervixFirmnessHalo-$index',
                text: cervixFirmnessSymbol(firmness),
                style: TextStyle(fontSize: 9, color: scheme.onSurface),
                haloColor: surface,
              ),
            ),
          ),
        if (zones.hasPain)
          Positioned(
            left: 0,
            right: 0,
            top: zones.painRowTop,
            height: painRowHeight,
            child: Center(
              child: _InPlotGlyphRows._haloedText(
                inkKey: 'painBreastGlyph-$index',
                haloKey: 'painBreastHalo-$index',
                text: 'B',
                style: TextStyle(fontSize: 9, color: scheme.onSurface),
                haloColor: surface,
              ),
            ),
          ),
        if (note case final text?)
          Positioned(
            left: 0,
            right: 0,
            top: zones.noteTop,
            bottom: 0,
            child: Align(
              alignment: Alignment.topLeft,
              child: RotatedBox(
                quarterTurns: 1,
                child: _InPlotGlyphRows._haloedText(
                  inkKey: 'notesText-$index',
                  haloKey: 'notesHaloText-$index',
                  text: text,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                  haloColor: surface,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The cervix zone's glyph area: the day's ink in ONE of the evenly
  /// spaced position slots (the other four stay empty). An opening-only
  /// day takes the medium slot.
  static Widget _cervixZone(BuildContext context, DailyEntry day, int index) {
    return SizedBox(
      height: cervixGlyphZoneHeight,
      child: Stack(children: [?_cervixSlotInk(context, day, index)]),
    );
  }

  /// Disturbance: the stacked letter codes of the day's temperature
  /// disturbances ([disturbanceLetters]) — neutral on-surface ink. These
  /// letters only NAME the recorded disturbances; the interrupted curve
  /// rendering is keyed to the ignoreTemperature MARK (cycle_curve.dart).
  static Widget _disturbanceContent(BuildContext context, DailyEntry? day) {
    final letters = disturbanceLetters(day);
    if (letters.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final letter in letters)
            Text(
              letter,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  /// Measurement time: the localized HH:mm text, vertical in narrow
  /// columns (below [_timeCellMinColumnWidth]), horizontal in wide ones.
  /// measuredAtMinutes exists only together with bbtC (the DailyEntry
  /// constructor drops a time without a temperature), so the text never
  /// claims a time for a temperature-free day.
  Widget _timeContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final minutes = day.measuredAtMinutes;
    if (minutes == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final time = DateTime.utc(2000).add(Duration(minutes: minutes));
    final text = Text(
      DateFormat.Hm(locale).format(time),
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    if (cellWidth < _timeCellMinColumnWidth) {
      // The rotated text's width becomes its cell height — the row-height
      // constant reserves that space (see _signalRowHeight). The Align
      // anchors the reading start at the row's top (the outer Center only
      // fills the cell).
      return Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: RotatedBox(quarterTurns: 1, child: text),
        ),
      );
    }
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }
}
