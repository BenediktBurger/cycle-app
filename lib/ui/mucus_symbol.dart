// Rendering of a recorded mucus observation, shared by the Tagebuch day
// chip, the Zyklus symbol row and its legend (`Sᴱᵂ`-style), plus the
// tooltip texts of the mucus surfaces.
import 'package:flutter/material.dart';

import '../domain/mucus.dart';
import '../l10n/app_localizations.dart' show AppLocalizations;

/// Tooltip texts of the mucus surfaces, keyed by the domain values — the
/// single source the picker chips and the display glyphs read, so their
/// wording cannot drift.
String mucusSignTooltip(MucusSign sign, AppLocalizations l10n) =>
    switch (sign) {
      MucusSign.t => l10n.mucusSignTooltipT,
      MucusSign.nothing => l10n.mucusSignTooltipNothing,
      MucusSign.f => l10n.mucusSignTooltipF,
      MucusSign.s => l10n.mucusSignTooltipS,
      MucusSign.fs => l10n.mucusSignTooltipFs,
      MucusSign.a => l10n.mucusSignTooltipA,
    };

String mucusQualityTooltip(MucusQuality quality, AppLocalizations l10n) =>
    switch (quality) {
      MucusQuality.w => l10n.mucusQualityTooltipW,
      MucusQuality.mi => l10n.mucusQualityTooltipMi,
      MucusQuality.cr => l10n.mucusQualityTooltipCr,
      MucusQuality.kl => l10n.mucusQualityTooltipKl,
      MucusQuality.glb => l10n.mucusQualityTooltipGlb,
      MucusQuality.g => l10n.mucusQualityTooltipG,
      MucusQuality.ew => l10n.mucusQualityTooltipEw,
      MucusQuality.gl => l10n.mucusQualityTooltipGl,
      MucusQuality.fl => l10n.mucusQualityTooltipFl,
      MucusQuality.ns => l10n.mucusQualityTooltipNs,
    };

/// Tooltip message of a rendered observation: the sign's cheat-sheet
/// explanation, and when a quality is rendered the quality explanation
/// after an en dash.
String mucusGlyphTooltip(
  MucusSign sign,
  MucusQuality? quality,
  AppLocalizations l10n,
) {
  final message = mucusSignTooltip(sign, l10n);
  if (quality == null) return message;
  return '$message – ${mucusQualityTooltip(quality, l10n)}';
}

/// Renders a fertility-sign observation as rich text: the glyph of the
/// recorded sign plus, for quality qualifiers, a smaller superscript token
/// (`Sᴱᵂ`). Glyph choice comes from the pure-Dart [MucusDisplay] record
/// built with [mucusDisplay] — this widget is the one renderer and stays
/// free of any interpretation (ADR-0001: pure recording).
///
/// The glyph carries the cheat-sheet explanation as a long-press/hover
/// tooltip: the sign explanation, plus the quality explanation when one is
/// rendered.
///
/// Renders nothing when no sign was recorded (`sign` null), so callers
/// can decide themselves whether to keep surrounding layout slots.
final class MucusSymbolText extends StatelessWidget {
  const MucusSymbolText({
    super.key,
    this.sign,
    this.quality,
    this.display,
    required this.color,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w600,
  });

  final MucusSign? sign;

  final MucusQuality? quality;

  /// The pure-Dart record the caller precomputed — the in-plot glyph rows
  /// read it straight from the pure chart record (chart_marks.dart). When
  /// given, it renders verbatim and no tooltip is attached.
  final MucusDisplay? display;

  final Color color;

  /// Font size of the base symbol; the superscript scales with it.
  final double fontSize;

  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final MucusSign? displayedSign;
    final MucusQuality? displayedQuality;
    final MucusDisplay shown;

    if (display case final record?) {
      // A precomputed record renders verbatim and carries no tooltip.
      shown = record;
      displayedSign = null;
      displayedQuality = null;
    } else {
      // The sanitizer drops any quality on a non-S sign — the tooltip must
      // never explain a quality the glyph does not show.
      final sanitized = sanitizeMucusPair(sign: sign, quality: quality);
      shown = mucusDisplay(sign: sanitized.sign, quality: sanitized.quality);
      displayedSign = sanitized.sign;
      displayedQuality = sanitized.quality;
    }

    final symbol = shown.symbol;
    if (symbol == null) return const SizedBox.shrink();
    final superscript = shown.superscript;

    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.1,
      color: color,
      fontWeight: fontWeight,
    );

    Widget result = Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: symbol),
          if (superscript != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.aboveBaseline,
              // Current Flutter requires an explicit baseline for spans that
              // align to one; alphabetic keeps the historical placement of
              // the superscript next to the base glyph.
              baseline: TextBaseline.alphabetic,
              child: Text(
                superscript,
                style: baseStyle.copyWith(fontSize: fontSize * 0.78),
              ),
            ),
        ],
      ),
    );

    if (displayedSign != null) {
      result = Tooltip(
        message: mucusGlyphTooltip(
          displayedSign,
          displayedQuality,
          AppLocalizations.of(context),
        ),
        child: result,
      );
    }
    return result;
  }
}
