// Superscript rendering of a recorded mucus observation, shared by the
// Tagebuch day chip, the Zyklus symbol row and its legend (`Sᴱᵂ`-style).
import 'package:flutter/material.dart';

import '../domain/mucus.dart';

/// Renders a fertility-sign observation as rich text: the glyph of the
/// recorded sign plus, for quality qualifiers, a smaller superscript token
/// (`Sᴱᵂ`). Glyph and token choice come from the pure-Dart [MucusDisplay]
/// record built with [mucusDisplay] — this widget is the one renderer and
/// stays free of any interpretation (ADR-0001: pure recording).
///
/// Renders nothing when no sign was recorded (`symbol` null), so callers
/// can decide themselves whether to keep surrounding layout slots.
final class MucusSymbolText extends StatelessWidget {
  const MucusSymbolText({
    super.key,
    required this.display,
    required this.color,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w600,
  });

  /// The (symbol, superscript) record from `mucusDisplay`.
  final MucusDisplay display;

  final Color color;

  /// Font size of the base symbol; the superscript scales with it.
  final double fontSize;

  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final symbol = display.symbol;
    if (symbol == null) return const SizedBox.shrink();
    final superscript = display.superscript;

    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.1,
      color: color,
      fontWeight: fontWeight,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: symbol),
          if (superscript != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.aboveBaseline,
              child: Text(
                superscript,
                style: baseStyle.copyWith(fontSize: fontSize * 0.78),
              ),
            ),
        ],
      ),
    );
  }
}
