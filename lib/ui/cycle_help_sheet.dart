// The Zyklus screen's symbol glossary (help sheet): the on-screen legend
// moved into a bottom sheet opened from the AppBar's info_outline action —
// every symbol the legend carried (temperature, bleeding, mucus, mucus
// peak, circled higher, arrow higher, baseline, SUZ, cervix position,
// cervix firmness, measurement time, sex, pain) plus the user-placed
// analysis-exclusion toggle (a day-sheet mark, no chart glyph — see the
// entry note) and the evaluation-arithmetic note. The glyph samples reuse
// the same shapes the chart and its rows render, so the glossary always
// shows what the screen draws. Pure display — no persistence (ADR-0001).

import 'package:flutter/material.dart';

import '../domain/cervix.dart';
import '../domain/mucus.dart';
import '../l10n/app_localizations.dart';
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
              color: scheme.onSurface,
              label: l10n.cycleLegendIgnoreTemperature,
              // The temperature-ignore mark draws NO chart glyph (the
              // interrupted-lookup is the raw Temperature mask, and the
              // mark is deliberately not doubled onto the curve): the
              // glossary entry therefore carries the day-sheet TOGGLE
              // affordance itself as its "symbol".
              shape: _HelpEntryShape.eyeOff,
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
              label: l10n.cycleLegendMeasuredAt,
              // The measured-at entry keeps the clock icon here (in the
              // help sheet only — the per-day clock glyph on the chart is
              // gone; wide columns spell the time as text instead).
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
  eyeOff,
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
      // The temperature-ignore entry: no chart glyph exists (see the
      // entry note), so the sample is the day sheet's own toggle icon —
      // the affordance IS the explanation.
      _HelpEntryShape.eyeOff =>
        Icon(Icons.visibility_off_outlined, size: 12, color: color),
      // Sample sex glyph: the X, exactly how a recorded sex day renders in
      // the sex row.
      _HelpEntryShape.sex => Text(
          'X',
          style: TextStyle(fontSize: 10, color: color),
        ),
      // Pain glyphs: B and M, the letter-coded pain options the
      // pain row renders per flag (sample).
      _HelpEntryShape.pain => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('B', style: TextStyle(fontSize: 10, color: color)),
            const SizedBox(width: 1),
            Text('M', style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          symbol,
          const SizedBox(width: 6),
          // Flexible: a long label wraps instead of overflowing its row
          // (the exclusion entry's wording is deliberately descriptive).
          Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
