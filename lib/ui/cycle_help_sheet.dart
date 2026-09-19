// The Zyklus screen's symbol glossary (help sheet): the on-screen legend
// moved into a bottom sheet opened from the AppBar's info_outline action —
// every symbol the legend carried (temperature, bleeding, mucus, mucus
// peak, circled higher, arrow higher, baseline, SUZ, cervix position,
// cervix firmness, measurement time, sex, pain) plus the ignored-
// temperature entry (the lighter temperature rendering of the
// ignoreTemperature-marked days — see the entry note), the breast-pain
// and Mittelschmerz letters, the disturbance letters, the note indicator
// and the evaluation-arithmetic note. The glyph samples reuse the same
// shapes the chart and its rows render, so the glossary always shows
// what the screen draws. Pure display — no persistence (ADR-0001).

import 'package:flutter/material.dart';

import '../domain/cervix.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import 'cycle_curve.dart';
import 'cycle_marks.dart';
import 'mucus_symbol.dart';

/// Opens the symbol-glossary bottom sheet.
Future<void> showCycleHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _CycleHelpSheet(),
  );
}

/// The glossary sheet: a scrollable list of glyph + explanation rows
/// followed by the arithmetic note.
/// TODO(user-review): the sheet title/action wording
/// ("Zeichenerklärung" / "Show symbol glossary") is a first draft the
/// experts may want reworded.
final class _CycleHelpSheet extends StatelessWidget {
  const _CycleHelpSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('cycleHelpSheet'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.cycleHelpTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _HelpEntry(
              color: scheme.primary,
              label: l10n.cycleLegendTemperature,
              shape: _HelpEntryShape.dot,
            ),
            _HelpEntry(
              color: scheme.error,
              label: l10n.cycleLegendBleeding,
              shape: _HelpEntryShape.ring,
            ),
            _HelpEntry(
              color: scheme.tertiary,
              label: l10n.cycleLegendMucus,
              shape: _HelpEntryShape.text,
            ),
            _HelpEntry(
              color: scheme.tertiary,
              label: l10n.cycleLegendMucusPeak,
              // R6: the peak renders as a SOLID dot above the mucus glyph
              // in the mucus row — the old curve-ring glyph is gone.
              shape: _HelpEntryShape.dot,
            ),
            _HelpEntry(
              // The ignored-temperature entry presents the VISUAL
              // consequence (owner decision 2026-09-19: the mark is the curve's
              // rendering key — marked days render lighter): the sample is
              // a lighter temperature dot, derived from the SAME constant
              // the curve draws with (ignoredTemperatureAlpha) so legend
              // and chart cannot drift.
              color: scheme.primary.withValues(alpha: ignoredTemperatureAlpha),
              label: l10n.cycleLegendIgnoreTemperature,
              shape: _HelpEntryShape.dot,
            ),
            _HelpEntry(
              color: scheme.primary,
              label: l10n.cycleLegendCircledHigher,
              shape: _HelpEntryShape.circledDot,
            ),
            _HelpEntry(
              color: scheme.primary,
              label: l10n.cycleLegendArrowHigher,
              shape: _HelpEntryShape.arrowUp,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendCervix,
              shape: _HelpEntryShape.cervix,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendCervixFirmness,
              shape: _HelpEntryShape.firmness,
            ),
            _HelpEntry(
              color: scheme.secondary,
              label: l10n.cycleLegendBaseline,
              shape: _HelpEntryShape.line,
            ),
            _HelpEntry(
              color: scheme.secondary,
              label: l10n.cycleLegendSuz,
              shape: _HelpEntryShape.suz,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendDisturbance,
              // Sample disturbance glyph: the stacked letter codes the
              // disturbance row renders per set temperature-disturbance
              // flag of the diary (here the two alcohol/illness codes;
              // more codes stack further and shrink to fit the row).
              shape: _HelpEntryShape.disturbance,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendNote,
              // Sample note glyph: the sticky-note icon a noted day
              // renders at the very bottom of the chart block.
              shape: _HelpEntryShape.note,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendMittelschmerz,
              // Sample Mittelschmerz glyph: the M letter, exactly how a
              // recorded Mittelschmerz day renders in its own row beneath
              // the mucus row.
              shape: _HelpEntryShape.mittelschmerz,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendMeasuredAt,
              // The measured-at entry keeps the clock icon here (in the
              // help sheet only — the chart's day cells spell the time as
              // text, vertically in narrow columns).
              shape: _HelpEntryShape.clock,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendSex,
              shape: _HelpEntryShape.sex,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendPain,
              shape: _HelpEntryShape.pain,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.cycleArithmeticNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum _HelpEntryShape {
  dot,
  ring,
  text,
  circledDot,
  arrowUp,
  line,
  cervix,
  firmness,
  suz,
  clock,
  sex,
  pain,
  mittelschmerz,
  disturbance,
  note,
}

final class _HelpEntry extends StatelessWidget {
  const _HelpEntry({
    required this.color,
    required this.label,
    required this.shape,
  });

  final Color color;
  final String label;
  final _HelpEntryShape shape;

  @override
  Widget build(BuildContext context) {
    final Widget symbol = switch (shape) {
      _HelpEntryShape.dot => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      _HelpEntryShape.ring => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(width: 1.5, color: color),
          ),
        ),
      _HelpEntryShape.text => MucusSymbolText(
          // Sample glyph: plain S, matching the chart legend — no quality
          // qualifier shown.
          display: mucusDisplay(sign: MucusSign.s),
          fontSize: 10,
          color: color,
        ),
      _HelpEntryShape.circledDot => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(width: 1.5, color: color),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      _HelpEntryShape.arrowUp => ArrowUpGlyph(color: color),
      // Sample Muttermund glyph: the "medium" letter, exactly how a
      // recorded cervix day renders in the cervix row.
      _HelpEntryShape.cervix => Text(
          cervixPositionSymbol(CervixPosition.medium),
          style: TextStyle(fontSize: 10, color: color),
        ),
      // Sample firmness glyph: the soft shorthand 'w', exactly how a
      // recorded firmness renders beside the position letter in the cervix
      // row.
      _HelpEntryShape.firmness => Text(
          cervixFirmnessSymbol(CervixFirmness.soft),
          style: TextStyle(fontSize: 10, color: color),
        ),
      _HelpEntryShape.line => Container(width: 16, height: 2, color: color),
      // The SUZ glyph: the chart's vertical bar plus the right-pointing
      // arrow from it (same shapes as the chart's painter).
      _HelpEntryShape.suz => SuzArrowGlyph(color: color),
      // Sample measurement-time glyph: the clock icon (help sheet only —
      // the chart's day cells show the recorded time as text instead).
      _HelpEntryShape.clock => Icon(Icons.schedule, size: 12, color: color),
      // Sample sex glyph: the X, exactly how a recorded sex day renders in
      // the sex row.
      _HelpEntryShape.sex => Text(
          'X',
          style: TextStyle(fontSize: 10, color: color),
        ),
      // Sample pain glyph: the B letter, the breast-pain option the below-
      // curve pain row renders per flag (the M letter has its own entry).
      _HelpEntryShape.pain => Text(
          'B',
          style: TextStyle(fontSize: 10, color: color),
        ),
      // Sample Mittelschmerz glyph: the M letter, exactly how a recorded
      // Mittelschmerz day renders in its own row beneath the mucus row.
      _HelpEntryShape.mittelschmerz => Text(
          'M',
          style: TextStyle(fontSize: 10, color: color),
        ),
      // Sample disturbance glyphs: the stacked letter codes of the
      // disturbance vocabulary (the TempDisturbance tokens that
      // disturbanceLetters in cycle.dart emits) — stacked in the same
      // render order as a real two-disturbance day (values order:
      // alk before kr).
      _HelpEntryShape.disturbance => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('alk', style: TextStyle(fontSize: 9, color: color)),
            Text('kr', style: TextStyle(fontSize: 9, color: color)),
          ],
        ),
      // Sample note glyph: the same sticky-note icon a noted day renders
      // in its cell at the very bottom of the chart block.
      _HelpEntryShape.note => Icon(
          Icons.sticky_note_2_outlined,
          size: 12,
          color: color,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          symbol,
          const SizedBox(width: 6),
          // Flexible: the longer entries (the disturbance codes' legend,
          // the arithmetic wording) wrap within the sheet width instead of
          // overflowing the row.
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
