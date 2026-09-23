// The Zyklus screen's symbol glossary (help sheet): the on-screen legend
// moved into a bottom sheet opened from the AppBar's info_outline action —
// every symbol the legend carried (bleeding, mucus, mucus peak,
// Mittelschmerz, sex, temperature, ignored temperature, circled higher,
// arrow higher, baseline, SUZ, measurement time, disturbance, cervix
// position, cervix firmness, breast pain, note) plus the entry notes for
// the ignored-temperature entry (the lighter temperature rendering of the
// ignoreTemperature-marked days — see the entry note), the disturbance
// letters, the note indicator and the evaluation-arithmetic note. The
// entries render in the cycle tab's top-down appearance order so glossary
// and screen always agree. The glyph samples reuse the same shapes the
// chart and its rows render, so the glossary always shows what the screen
// draws. Pure display — no persistence (ADR-0001).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/cervix.dart';
import '../domain/models.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
import 'bleeding_symbol.dart';
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
            // The entries render in the cycle tab's top-down appearance
            // order: the signal rows above the temperature block
            // (_topSignalKinds, plus the mucus-peak dot above the mucus
            // glyph), then the temperature-curve group as the plot draws
            // it (curve, ignored-temperature rendering, circled higher,
            // premature rise, dashed baseline, SUZ), then the below-chart
            // strip (_belowChartKinds) — glossary and tab cannot drift.
            _HelpEntry(
              color: scheme.error,
              label: l10n.termBleeding,
              // Sample bleeding glyph: the shared square box in its
              // dotted spotting mode — the level least like a plain
              // fill, rendered exactly like a recorded spotting day on
              // the chart rows and the diary tiles (bleeding_symbol.dart).
              shape: _HelpEntryShape.bleeding,
            ),
            _HelpEntry(
              color: scheme.tertiary,
              label: l10n.termMucus,
              shape: _HelpEntryShape.text,
            ),
            _HelpEntry(
              color: scheme.tertiary,
              label: l10n.termMucusPeak,
              // R6: the peak renders as a SOLID dot above the mucus glyph
              // in the mucus row — the old curve-ring glyph is gone.
              shape: _HelpEntryShape.dot,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.termMittelschmerz,
              // Sample Mittelschmerz glyph: the M letter, exactly how a
              // recorded Mittelschmerz day renders in its own row beneath
              // the mucus row.
              shape: _HelpEntryShape.mittelschmerz,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendSex,
              shape: _HelpEntryShape.sex,
            ),
            _HelpEntry(
              color: scheme.primary,
              label: l10n.cycleLegendTemperature,
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
              color: scheme.secondary,
              label: l10n.cycleLegendBaseline,
              // Sample baseline glyph: the chart's dashed baseline segment
              // style, repainted by _DashedBaselinePainter — the chart's
              // own bar is an fl_chart segment and cannot be reused
              // outside the chart.
              shape: _HelpEntryShape.dashedLine,
            ),
            _HelpEntry(
              color: scheme.secondary,
              label: l10n.cycleLegendSuz,
              shape: _HelpEntryShape.suz,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.termMeasurementTime,
              // The measured-at entry keeps the clock icon here (in the
              // help sheet only — the chart's day cells spell the time as
              // text, vertically in narrow columns).
              shape: _HelpEntryShape.clock,
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
              label: l10n.termCervixPosition,
              shape: _HelpEntryShape.cervix,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.termCervixFirmness,
              shape: _HelpEntryShape.firmness,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.termBreastPain,
              shape: _HelpEntryShape.pain,
            ),
            _HelpEntry(
              color: scheme.onSurface,
              label: l10n.cycleLegendNote,
              // Sample note glyph: the sticky-note icon a noted day
              // renders at the very bottom of the chart block.
              shape: _HelpEntryShape.note,
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
  bleeding,
  text,
  circledDot,
  arrowUp,
  dashedLine,
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
      // Sample bleeding glyph: the shared square box symbol in its
      // dotted spotting mode — the fill-fraction convention's least
      // plain-looking level, at a small glossary size with the box
      // outlined so the interrupted quarter band reads as such.
      _HelpEntryShape.bleeding => SizedBox(
        width: 14,
        height: 14,
        child: BleedingSymbol(
          bleeding: Bleeding.spotting,
          color: color,
          borderColor: color,
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
      // The baseline sample: the chart's dashed segment style, repainted
      // by a small painter (the chart's bar is an fl_chart segment and
      // cannot be reused outside the chart) — see _DashedBaselinePainter.
      _HelpEntryShape.dashedLine => CustomPaint(
        // Keyed for the glossary tests: the dashed style is the entry's
        // changed aspect against the old solid line sample.
        key: const ValueKey('legendBaselineGlyph'),
        size: _baselineGlyphSize,
        painter: _DashedBaselinePainter(color: color),
      ),
      // The SUZ glyph: the chart's vertical bar plus the right-pointing
      // arrow from it (same shapes as the chart's painter).
      // TODO(user-review): the legend wording was re-checked against the
      // new top-anchored glyph (the bar now hangs down from the
      // temperature chart's top border, the arrow sits just below it) and
      // kept unchanged: the wording names the concept, not the placement,
      // so nothing here lies.
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

/// The baseline sample's box: the same 16 × 2 line the solid sample drew.
const Size _baselineGlyphSize = Size(16, 2);

/// The baseline glyph's painter: a short dashed horizontal line with the
/// strokeWidth 2 the old solid sample had. The chart draws its baseline as
/// an fl_chart segment bar with `dashArray: [6, 4]` — a bar that cannot be
/// reused outside the chart — so the legend repaints the same dashes here
/// (6 px ink, 4 px gap, truncated at the box edges).
final class _DashedBaselinePainter extends CustomPainter {
  const _DashedBaselinePainter({required this.color});

  final Color color;

  /// The dash pattern of the chart's baseline bar (dashArray [6, 4]):
  /// alternating ink length 6 and gap length 4, same order.
  final dashPattern = const [6.0, 4.0];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    var x = 0.0;
    var inkNext = true;
    while (x < size.width) {
      final remaining = size.width - x;
      final length = math.min(dashPattern[inkNext ? 0 : 1], remaining);
      if (inkNext) {
        canvas.drawRect(Rect.fromLTWH(x, 0, length, size.height), paint);
      }
      x += length;
      inkNext = !inkNext;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBaselinePainter oldDelegate) =>
      color != oldDelegate.color;
}
