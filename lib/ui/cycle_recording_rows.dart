// The cycle screen's recording rows and the per-day content glyphs
// inside their cells; the day panel itself lives in
// cycle_mark_sheet.dart. Part of the cycle.dart library.

part of 'cycle.dart';

/// The top block's grid rows (paper sheet order): bleeding →
/// Mittelschmerz M. The mucus and sex observations render INSIDE the
/// temperature plot instead (_InPlotGlyphRows, chart_marks.dart).
/// TODO(user-review): the M letter's home (own row beneath bleeding;
/// clinicians may prefer it in the pain row too) is an owner-eyeball
/// choice.
const _topSignalKinds = <_SignalKind>[
  _SignalKind.bleeding,
  _SignalKind.mittelschmerz,
];

/// The below-chart strip's rows (owner-decided order): measurement time →
/// disturbance → cervix → pain → day-note indicator. TODO(user-review): the
/// note's home in the strip's last row is an owner-eyeball choice.
const _belowChartKinds = <_SignalKind>[
  _SignalKind.time,
  _SignalKind.disturbance,
  _SignalKind.cervix,
  _SignalKind.pain,
  _SignalKind.note,
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
  _ => 12,
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

enum _SignalKind {
  bleeding,
  mittelschmerz,
  time,
  disturbance,
  cervix,
  pain,
  note,
}

/// Test-visible key prefix of a row's day cells.
String _signalKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCell',
  _SignalKind.mittelschmerz => 'mittelschmerzCell',
  _SignalKind.cervix => 'cervixCell',
  _SignalKind.pain => 'painCell',
  _SignalKind.disturbance => 'disturbanceCell',
  _SignalKind.time => 'timeCell',
  _SignalKind.note => 'noteCell',
};

/// Test-visible key prefix of a row's 44 px corner slot.
String _signalCornerKeyPrefix(_SignalKind kind) => switch (kind) {
  _SignalKind.bleeding => 'bleedingCorner',
  _SignalKind.mittelschmerz => 'mittelschmerzCorner',
  _SignalKind.cervix => 'cervixCorner',
  _SignalKind.pain => 'painCorner',
  _SignalKind.disturbance => 'disturbanceCorner',
  _SignalKind.time => 'timeCorner',
  _SignalKind.note => 'noteCorner',
};

/// The localized row name for a signal (corner tooltip/semantics label).
// TODO(user-review): the row-name wording is a first draft mirroring the
// entry form's vocabulary; the experts may want different names.
String _signalRowName(_SignalKind kind, AppLocalizations l10n) =>
    switch (kind) {
      _SignalKind.bleeding => l10n.termBleeding,
      _SignalKind.mittelschmerz => l10n.termMittelschmerz,
      _SignalKind.cervix => l10n.cycleRowCervix,
      _SignalKind.pain => l10n.termBreastPain,
      _SignalKind.disturbance => l10n.cycleRowDisturbance,
      _SignalKind.time => l10n.termMeasurementTime,
      _SignalKind.note => l10n.cycleRowNote,
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
    _SignalKind.cervix => Text(
      cervixPositionSymbol(CervixPosition.medium),
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.mittelschmerz => Text(
      'M',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.pain => Text(
      'B',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.disturbance => Text(
      'kr',
      style: TextStyle(fontSize: 10, color: scheme.onSurface),
    ),
    _SignalKind.time => Icon(Icons.schedule, size: 12, color: scheme.onSurface),
    _SignalKind.note => Icon(
      Icons.sticky_note_2_outlined,
      size: 12,
      color: scheme.onSurface,
    ),
  };
}

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
      child: Center(
        child: switch (kind) {
          _SignalKind.bleeding => _bleedingContent(context, day),
          _SignalKind.mittelschmerz => _mittelschmerzContent(context, day),
          _SignalKind.cervix => _cervixContent(context, day),
          _SignalKind.pain => _painContent(context, day),
          _SignalKind.disturbance => _disturbanceContent(context, day),
          _SignalKind.time => _timeContent(context, day),
          _SignalKind.note => _noteContent(context, day),
        },
      ),
    );
  }

  /// Bleeding: the shared square-box symbol fills the day cell (the
  /// shared bottom-anchored fill-fraction convention; spotting dotted).
  static Widget _bleedingContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    return BleedingSymbol(bleeding: day.bleeding);
  }

  /// Cervix: position letter, firmness shorthand beside it; the OPENING is
  /// deliberately not displayed (entry-form-only field). Raw observation
  /// display only, never a fertility conclusion (ADR-0001); neutral
  /// on-surface ink (no scheme hue claimed).
  static Widget _cervixContent(BuildContext context, DailyEntry? day) {
    if (day == null) return const SizedBox.shrink();
    final List<String>? cervixLine =
        day.cervixPosition == null && day.cervixFirmness == null
        ? null
        : [
            if (day.cervixPosition case final position?)
              cervixPositionSymbol(position),
            if (day.cervixFirmness case final firmness?)
              cervixFirmnessSymbol(firmness),
          ];
    if (cervixLine == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cervixLine.length; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          Text(
            cervixLine[i],
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }

  /// Pain: the letter B (uppercase, distinguishable from the lowercase
  /// cervix letters; neutral on-surface ink). TODO(user-review): the letter
  /// mirrors the entry-form ("Brustschmerzen (B)") vocabulary — the same
  /// ad-hoc glyph caveat as the cervix letters applies.
  static Widget _painContent(BuildContext context, DailyEntry? day) {
    if (day == null || !day.painBreast) return const SizedBox.shrink();
    return Text(
      'B',
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// Mittelschmerz: the letter M in its own top strip row.
  static Widget _mittelschmerzContent(BuildContext context, DailyEntry? day) {
    if (day == null || !day.painMittelschmerz) return const SizedBox.shrink();
    return Text(
      'M',
      style: TextStyle(
        fontSize: 9,
        color: Theme.of(context).colorScheme.onSurface,
      ),
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
      // constant reserves that space (see _signalRowHeight).
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: RotatedBox(quarterTurns: 3, child: text),
      );
    }
    return FittedBox(fit: BoxFit.scaleDown, child: text);
  }

  /// Note indicator: a small sticky-note glyph for a day whose entry
  /// carries a NON-EMPTY notes text; the note is edited in the Diary form.
  static Widget _noteContent(BuildContext context, DailyEntry? day) {
    if (day == null || day.notes == null || day.notes!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Icon(
      Icons.sticky_note_2_outlined,
      size: 10,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
